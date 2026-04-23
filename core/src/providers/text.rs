//! Text / Reasoning Provider layer.
//!
//! Kleine, interne, kuratierte Provider-Schicht für Text-Anfragen. Siehe
//! `docs/provider_fallback_and_settings_architecture.md` §3 („Provider-
//! Achsen getrennt führen / UI bleibt Renderer / Core bleibt Source of
//! Truth / Fallback ist explizit, nicht still") und §4.1 („ABrain /
//! Lokaler CLI-Command / Lokaler HTTP / Cloud").
//!
//! Design-Entscheidungen für PR 2:
//!
//! * **Enum-Dispatch statt Trait-Objekt.** Die Menge der erlaubten
//!   Provider-Kinds ist in diesem Repo **kuratiert**: kein dynamisches
//!   Plug-in-Laden, kein Fremdcode-Zugriff, kein SDK-Wildwuchs. Ein
//!   `enum TextProviderImpl` bildet das direkt ab — neue Kinds kommen
//!   als neue Varianten per PR, nicht zur Laufzeit.
//! * **ABrain bleibt Default und einziger produktiver Kind.** Andere
//!   Provider-Klassen (LocalCommand, LocalHttp, Cloud) sind in der
//!   Architektur-Doku beschrieben, werden aber erst in späteren PRs
//!   implementiert. Dieser PR liefert die Schicht dahinter.
//! * **Chain-Konfiguration mit einem einzigen Kind ist zulässig.** Der
//!   Resolver funktioniert auch, wenn nur ein Provider konfiguriert
//!   ist — er ist dann faktisch kein Fallback, aber strukturell
//!   identisch zum späteren Multi-Provider-Pfad.
//! * **Kein stiller Fallback in nicht konfigurierte Provider.** Die
//!   Kette ist explizit; ein leerer / ungültiger Kettenparameter fällt
//!   auf die Default-Kette `["abrain"]` zurück, niemals auf eine
//!   andere Klasse und niemals in Richtung Cloud.
//! * **Runtime-Status ohne externe Sichtbarkeit von Secrets.** Der
//!   Resolver merkt sich nur Provider-*Kind*-Namen und kurze
//!   Fehlerklassen, keine Kommandozeilen, keine Prozess-Outputs,
//!   keine Netzwerk-Antworten — falls spätere Provider-Klassen Secrets
//!   halten, müssen deren eigene `run`-Implementierungen sie sauber
//!   kapseln.

use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::process::{Child, Command};
use tokio::sync::Mutex as AsyncMutex;
use tokio::time::{sleep, timeout};
use tracing::{info, warn};

/// Kanonischer Namensstring für den ABrain-Provider. Wird an vielen
/// Stellen verglichen; als Konstante gehalten, damit ein Tippfehler
/// beim Config-Parsen sofort beim Kompilieren auffällt.
pub const PROVIDER_NAME_ABRAIN: &str = "abrain";

/// Kanonischer Namensstring für den lokalen llamafile-Provider.
/// **Architektonisch vorbereitet**, Runtime noch nicht implementiert.
/// In der Konfiguration als `llamafile_local` einzusetzen.
pub const PROVIDER_NAME_LLAMAFILE_LOCAL: &str = "llamafile_local";

/// Kanonischer Namensstring für den allgemeinen lokalen HTTP-Provider
/// (PR 8). Ziel: ein schmaler, produktiver HTTP-Adapter gegen einen
/// lokal laufenden, llama.cpp-kompatiblen Completion-Server, ohne
/// Cloud-SDK, ohne Secrets, ohne Streaming.
pub const PROVIDER_NAME_LOCAL_HTTP: &str = "local_http";

const ABRAIN_DEFAULT_TIMEOUT_SECS: u64 = 30;

/// Fehlerklassen, die der Resolver intern trackt. Die Strings sind
/// bewusst kurz und maschinenlesbar — sie landen später in
/// `StatusPayload.text_provider_last_error`, nicht Nutzerinhalte,
/// keine Stacktraces, keine Secrets. Freitext-Erklärungen gehen
/// weiterhin über das `error`-IPC-Envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TextProviderError {
    /// Die aufgelöste Provider-Kette ist leer — keine Konfiguration,
    /// keine Magie, nur ehrliches "nicht verfügbar".
    EmptyChain,
    /// Alle Provider der Kette haben diesen Request abgelehnt. Trägt
    /// den kurzen Fehlerklassen-Tag des zuletzt probierten Providers.
    AllFailed(String),
}

impl std::fmt::Display for TextProviderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyChain => write!(
                f,
                "no text provider configured (chain is empty); check SMOLIT_TEXT_PROVIDER_CHAIN or core config",
            ),
            Self::AllFailed(last) => write!(
                f,
                "all configured text providers failed; last error: {last}",
            ),
        }
    }
}

impl std::error::Error for TextProviderError {}

/// Ein einzelner Eintrag einer konfigurierten Provider-Kette. Der
/// Resolver baut daraus seinen produktiven `TextProviderImpl`-Vektor.
#[derive(Debug, Clone)]
pub struct TextProviderChainItem {
    /// Kanonischer Kind-Name, etwa `"abrain"`.
    pub kind: String,
}

/// Enum-Dispatch über alle heute existierenden Text-Provider.
/// Bewusst klein; neue Varianten kommen per eigenem PR.
///
/// * `Abrain` — produktiv implementiert (Ist-Zustand).
/// * `LlamafileLocal` — **architektonisch vorbereitet**, Runtime-
///   Integration folgt in einem Folge-PR. Siehe
///   [`LlamafileLocalProvider`] für die Stub-Semantik.
#[derive(Debug)]
pub enum TextProviderImpl {
    Abrain(AbrainCliProvider),
    LlamafileLocal(LlamafileLocalProvider),
    /// Lokaler HTTP-Provider (PR 8). Spricht einen konfigurierten
    /// Endpoint per `POST` mit JSON-Body an und liest einen
    /// Text-Feldwert aus der Antwort. Loopback-first, kein TLS,
    /// keine Secrets in dieser Stufe.
    LocalHttp(LocalHttpProvider),
}

impl TextProviderImpl {
    /// Kanonischer Namensstring des Provider-Kinds. Wird für
    /// Statusanzeige und Log-Korrelation verwendet.
    pub fn kind_name(&self) -> &'static str {
        match self {
            Self::Abrain(_) => PROVIDER_NAME_ABRAIN,
            Self::LlamafileLocal(_) => PROVIDER_NAME_LLAMAFILE_LOCAL,
            Self::LocalHttp(_) => PROVIDER_NAME_LOCAL_HTTP,
        }
    }

    /// Kurze Fehlerklasse (ein Wort, keine Nutzerinhalte) für
    /// `StatusPayload.text_provider_last_error`. Übersetzt den
    /// `anyhow::Error` defensiv — wer mehr Detail will, nutzt das
    /// bestehende `error`-IPC-Envelope.
    ///
    /// Gehört auf die Provider-Ebene, weil verschiedene Kinds
    /// unterschiedliche Fehlerquellen haben können (Prozess-Spawn,
    /// HTTP, Auth usw.). Für den heutigen ABrain-CLI-Pfad reicht ein
    /// kleiner Satz gängiger Klassen.
    pub fn classify_error(err: &anyhow::Error) -> &'static str {
        // Wir greifen defensiv auf die Kette von Fehlern zu. `anyhow`
        // stapelt Contexts; die Signalstrings unten kommen aus den
        // `context()`- und `bail!`-Zeilen von `AbrainCliProvider::run`
        // bzw. `LlamafileLocalProvider::run`.
        let chain: Vec<String> = err.chain().map(|e| e.to_string()).collect();
        let joined = chain.join(" | ").to_ascii_lowercase();

        // local_http-spezifische Tags (PR 8). Wie bei llamafile
        // zuerst geprüft, damit die allgemeinen Muster weiter unten
        // nicht fälschlicherweise auf lokal-HTTP-Refusals greifen.
        if joined.contains("local_http") {
            if joined.contains("is disabled") {
                return "disabled";
            }
            if joined.contains("not configured") {
                return "not_configured";
            }
            if joined.contains("endpoint must start with http://") {
                return "endpoint_scheme_unsupported";
            }
            if joined.contains("endpoint url is not parseable") {
                return "endpoint_unparseable";
            }
            if joined.contains("timed out") {
                return "timeout";
            }
            if joined.contains("http connect") {
                return "http_connect_failed";
            }
            if joined.contains("http returned status") {
                return "http_error";
            }
            if joined.contains("returned no content") {
                return "empty_response";
            }
            if joined.contains("is not valid json") || joined.contains("not valid utf-8") {
                return "invalid_response";
            }
        }

        // Llamafile-spezifische Tags zuerst prüfen, damit die
        // allgemeinen Muster („failed to spawn" o. ä.) nicht
        // fälschlicherweise auf Refusal- oder Runtime-Fehler greifen.
        if joined.contains("llamafile") {
            // Prep-Refusals (PR 2a): weiterhin gültig, wenn der
            // Provider im Lifecycle `Disabled`/`NotConfigured`
            // steht — die Runtime prüft das selbst und reicht die
            // Meldung nach oben.
            if joined.contains("is disabled") {
                return "disabled";
            }
            if joined.contains("not configured") {
                return "not_configured";
            }
            if joined.contains("runtime is not yet implemented") {
                return "not_implemented";
            }
            // Runtime-Fehler (PR 2b).
            if joined.contains("readiness check timed out") {
                return "startup_timeout";
            }
            if joined.contains("exited during startup") {
                return "process_exit_early";
            }
            if joined.contains("process spawn failed") {
                return "process_missing";
            }
            if joined.contains("http returned status") {
                return "http_error";
            }
            if joined.contains("returned no content") {
                return "empty_response";
            }
            if joined.contains("is not valid json") || joined.contains("not valid utf-8") {
                return "invalid_response";
            }
            if joined.contains("timed out") {
                return "timeout";
            }
            if joined.contains("http connect") {
                return "http_connect_failed";
            }
        }

        if joined.contains("timed out") {
            "timeout"
        } else if joined.contains("failed to spawn") || joined.contains("no such file") {
            "process_missing"
        } else if joined.contains("returned no output") {
            "empty_response"
        } else if joined.contains("not valid utf-8") {
            "invalid_response"
        } else if joined.contains("failed with status") {
            "exit_nonzero"
        } else {
            "unknown"
        }
    }

    pub async fn run(&self, input: &str) -> Result<String> {
        match self {
            Self::Abrain(p) => p.run(input).await,
            Self::LlamafileLocal(p) => p.run(input).await,
            Self::LocalHttp(p) => p.run(input).await,
        }
    }
}

/// ABrain-CLI-Provider (Ist-Zustand, siehe `docs/api.md` §3).
///
/// Spricht ABrain weiterhin als externes Kommando an. Die Kommandoform
/// ist unverändert `{cmd} task run "<input>"`, damit bestehende ABrain-
/// Installationen nicht zu aktualisieren sind. Der Unterschied zu
/// vor-PR-2: der Aufruf läuft jetzt **immer** über die Provider-Schicht
/// — `App::handle_text_query` geht nicht mehr direkt in
/// `adapters::abrain`, sondern durch den Resolver.
#[derive(Debug, Clone)]
pub struct AbrainCliProvider {
    command: String,
    timeout_secs: u64,
}

impl AbrainCliProvider {
    pub fn new(command: impl Into<String>) -> Self {
        Self {
            command: command.into(),
            timeout_secs: ABRAIN_DEFAULT_TIMEOUT_SECS,
        }
    }

    pub async fn run(&self, input: &str) -> Result<String> {
        let command = self.command.clone();
        let output = timeout(Duration::from_secs(self.timeout_secs), async {
            Command::new(&command)
                .args(["task", "run", input])
                .output()
                .await
        })
        .await
        .context("ABrain task timed out")?
        .with_context(|| format!("failed to spawn ABrain command `{command}`"))?;

        let stdout = String::from_utf8(output.stdout).context("ABrain stdout was not valid UTF-8")?;
        let stderr = String::from_utf8(output.stderr).context("ABrain stderr was not valid UTF-8")?;

        if !output.status.success() {
            let detail = if stderr.trim().is_empty() {
                "process exited without error output".to_string()
            } else {
                stderr.trim().to_string()
            };
            bail!(
                "ABrain command `{command}` failed with status {}: {}",
                output.status,
                detail,
            );
        }

        let response = stdout.trim().to_string();
        if response.is_empty() {
            bail!("ABrain command `{command}` returned no output");
        }
        Ok(response)
    }
}

// --- Llamafile Local (architektonisch vorbereitet, Runtime folgt) ---
//
// Siehe `docs/provider_fallback_and_settings_architecture.md` §4.1
// („Lokaler HTTP-Provider") und §4.3 des Llamafile-Vorbereitungs-PRs.
// Diese Schicht ist bewusst ein **ehrlicher Stub**: sie modelliert die
// Config, den Lifecycle und die Dispatch-Integration vollständig,
// liefert aber beim Aufruf deterministisch einen Fehler mit klar
// benannter Klasse (`disabled` / `not_configured` / `not_implemented`).
// Die echte Prozess-Orchestrierung (Spawn, HTTP-Client, Idle-Timeout,
// Warm-Standby) wohnt in einem expliziten Folge-PR. Dieser PR macht
// ausschließlich die Architektur tragfähig.

/// Lifecycle des lokalen llamafile-Providers. Das Vokabular ist
/// absichtlich größer als heute produziert: die ersten drei Varianten
/// entstehen bereits in diesem PR (Disabled / NotConfigured /
/// Configured), die übrigen sind **Scaffolding** für die spätere
/// Runtime-Stufe (Starting / Ready / Busy / Failed / Stopped).
///
/// Die Enum ist exhaustiv, damit der Stub heute schon keine
/// undefinierten Zwischenzustände kennt und spätere Runtime-Übergänge
/// additiv entlang dieser Strings laufen — ohne Enum-Umbau. Die
/// Scaffolding-Varianten sind heute unerreichbar; `as_str()` deckt sie
/// aber ab (siehe Test `llamafile_lifecycle_tag_strings_are_stable`),
/// damit die Tag-Strings eingefroren sind, bevor der Runtime-PR sie
/// aktiv nutzt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum LlamafileLifecycle {
    /// Feature-Flag aus (`SMOLIT_LLAMAFILE_ENABLED` nicht gesetzt /
    /// explizit `false`). Provider-Instanz existiert, ist aber inert.
    Disabled,
    /// Enabled, aber Pfad fehlt oder ist leer (`SMOLIT_LLAMAFILE_PATH`).
    /// Ohne Path gibt es nichts zu starten — ein Request führt zu
    /// einer klaren `not_configured`-Refusal, nicht zu einem
    /// halbgültigen Startversuch.
    NotConfigured,
    /// Enabled und konfiguriert; Prozess noch nicht gestartet. In
    /// dieser Stufe landet der Stub heute, wenn Env-Flags vollständig
    /// gesetzt sind. Ein Request führt aktuell zu `not_implemented` —
    /// die Runtime-Integration kommt in einem Folge-PR.
    Configured,
    /// Prozess wird hochgefahren. **Heute nicht erreichbar.**
    Starting,
    /// Prozess läuft und ist idle-ready. **Heute nicht erreichbar.**
    Ready,
    /// Prozess bedient gerade einen Request. **Heute nicht erreichbar.**
    Busy,
    /// Prozess hat sich abgemeldet, letzter Start ist fehlgeschlagen.
    /// **Heute nicht erreichbar.**
    Failed,
    /// Prozess wurde kontrolliert beendet (z. B. Idle-Timeout oder
    /// Shutdown). **Heute nicht erreichbar.**
    Stopped,
}

impl LlamafileLifecycle {
    /// Kleiner, stabiler String-Tag pro Lifecycle-Zustand. Primär für
    /// Logs und Tests; könnte später in additive Statusfelder
    /// wandern, wenn die UI das braucht.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::NotConfigured => "not_configured",
            Self::Configured => "configured",
            Self::Starting => "starting",
            Self::Ready => "ready",
            Self::Busy => "busy",
            Self::Failed => "failed",
            Self::Stopped => "stopped",
        }
    }
}

/// Providers-interne Sicht auf die llamafile-Konfiguration. Gemapped
/// vom serde-kompatiblen `config::LlamafileConfig` durch den
/// Resolver-Builder. Bewusst eigene Struktur, damit `providers/text.rs`
/// nicht auf `config` rückwärts abhängt und Tests diese Sicht direkt
/// konstruieren können.
#[derive(Debug, Clone)]
pub struct LlamafileConfigView {
    pub enabled: bool,
    pub path: Option<String>,
    /// Zulässige Werte (Stand PR 2b): `"on_demand"` / `"standby"`.
    /// Heute wird `standby` bewusst wie `on_demand` behandelt — der
    /// Runtime-Unterschied (Prozess dauerhaft halten) ist einem
    /// späteren PR vorbehalten. Der Wert ist gelesen/gespeichert.
    pub mode: String,
    /// Sekunden, nach denen der lokale Prozess im `on_demand`-Modus
    /// nach dem letzten Request wieder beendet werden soll. In PR 2b
    /// vom Watchdog tatsächlich überprüft.
    pub idle_timeout_seconds: u64,
    /// TCP-Port auf `127.0.0.1`, auf dem der lokale llamafile-Server
    /// erwartet wird bzw. gestartet wird.
    pub port: u16,
    /// Zeitbudget für das Warten auf `GET /health`-Erreichbarkeit
    /// nach Prozess-Spawn.
    pub startup_timeout_seconds: u64,
    /// Zeitbudget pro Completion-Request.
    pub request_timeout_seconds: u64,
}


/// Constante HTTP-Host des lokalen llamafile-Servers. Bewusst **nicht**
/// konfigurierbar, damit die Oberfläche nicht versehentlich nach außen
/// gebunden wird (siehe Architektur-Doku §7).
const LLAMAFILE_HOST: &str = "127.0.0.1";
/// Intervall zwischen `/health`-Polls während der Readiness-Phase.
const HEALTH_POLL_INTERVAL: Duration = Duration::from_millis(250);
/// Default-`n_predict` für den HTTP-Completion-Pfad. Bewusst konservativ
/// gewählt: kurze Antworten, überschaubare Latenz, keine Streaming-
/// Komplexität im MVP.
const DEFAULT_N_PREDICT: u32 = 256;

/// Runtime-Zustand des lokalen llamafile-Prozesses. Wird hinter einer
/// `tokio::sync::Mutex` serialisiert: genau ein Spawn und genau ein
/// Request zur selben Zeit (siehe Architektur-Entscheidung „Single-
/// Process-/Single-Request-MVP").
struct LlamafileRuntimeState {
    /// Laufender Kind-Prozess. `None` = kein Prozess aktiv (nie
    /// gespawnt oder bereits gestoppt). `kill_on_drop(true)` garantiert,
    /// dass ein Drop der Struktur den Prozess zuverlässig beendet.
    child: Option<Child>,
    /// Zeitstempel des letzten erfolgreichen Requests oder Spawn-
    /// Endes. Der Watchdog vergleicht ihn mit `idle_timeout_seconds`.
    last_used: Instant,
    /// Markiert, ob bereits ein Watchdog-Task läuft. Verhindert
    /// mehrfaches Spawnen bei Stop→Start-Zyklen.
    watchdog_running: bool,
}

/// Gemeinsamer Zustand, den der Watchdog-Task per `Weak`-Referenz
/// erreicht. Der Arc hält zwei Mutexe: einen `tokio::sync::Mutex` für
/// die serialisierte Runtime (`state`) und einen `std::sync::Mutex` für
/// den Lifecycle, damit Observers kurze, nicht-asynchrone Reads machen
/// können. Schreiben erfolgt immer aus dem `run()`-Pfad oder vom
/// Watchdog; beide halten nie beide Locks gleichzeitig (Reihenfolge:
/// erst `state.lock()`, dann `lifecycle.lock()`, wieder frei).
struct LlamafileInner {
    state: AsyncMutex<LlamafileRuntimeState>,
    lifecycle: Mutex<LlamafileLifecycle>,
    /// Test-Hook: wenn gesetzt, wird der HTTP-Client auf diesen Port
    /// geleitet statt auf `config.port`. Produktionspfade setzen das
    /// Feld nie; es bleibt dann `None`. Kein Secret-Relevanz.
    test_port_override: Mutex<Option<u16>>,
}

/// Lokaler llamafile-Provider mit Lazy-Load-Runtime (PR 2b).
///
/// Lifecycle (real):
///
///   * `Disabled` / `NotConfigured` → `run()` liefert ehrliche
///     Refusal (unverändert zu PR 2a).
///   * `Configured` → erster `run()` führt `Starting` → `Ready` →
///     `Busy` → `Ready` aus. Watchdog-Task wird einmalig gestartet
///     und beendet den Prozess nach `idle_timeout_seconds` Ruhe.
///   * `Stopped` → nächster `run()` startet den Prozess wieder.
///   * `Failed` → nächster `run()` versucht einen frischen Neustart;
///     bei weiterem Fehlschlag bleibt der Lifecycle `Failed` und der
///     Fehler wird klassifiziert.
pub struct LlamafileLocalProvider {
    config: LlamafileConfigView,
    inner: Arc<LlamafileInner>,
}

impl std::fmt::Debug for LlamafileLocalProvider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Eigener Debug-Impl ohne die Runtime-Mutexe, um
        // Mutex-Debug-Formate (und potenzielle Lock-Akquirierungen
        // beim Loggen) zu vermeiden.
        f.debug_struct("LlamafileLocalProvider")
            .field("config", &self.config)
            .field("lifecycle", &self.lifecycle().as_str())
            .finish()
    }
}

impl LlamafileLocalProvider {
    pub fn new(config: LlamafileConfigView) -> Self {
        let initial = Self::initial_lifecycle(&config);
        let inner = Arc::new(LlamafileInner {
            state: AsyncMutex::new(LlamafileRuntimeState {
                child: None,
                last_used: Instant::now(),
                watchdog_running: false,
            }),
            lifecycle: Mutex::new(initial),
            test_port_override: Mutex::new(None),
        });
        Self { config, inner }
    }

    fn initial_lifecycle(config: &LlamafileConfigView) -> LlamafileLifecycle {
        if !config.enabled {
            return LlamafileLifecycle::Disabled;
        }
        let path_empty = config
            .path
            .as_deref()
            .map(|p| p.trim().is_empty())
            .unwrap_or(true);
        if path_empty {
            LlamafileLifecycle::NotConfigured
        } else {
            LlamafileLifecycle::Configured
        }
    }

    /// Aktueller Lifecycle-Zustand. Non-blocking (std mutex); der
    /// Watchdog aktualisiert ihn, sobald der Prozess stoppt.
    pub fn lifecycle(&self) -> LlamafileLifecycle {
        *self
            .inner
            .lifecycle
            .lock()
            .expect("llamafile lifecycle mutex poisoned")
    }

    fn set_lifecycle(&self, next: LlamafileLifecycle) {
        *self
            .inner
            .lifecycle
            .lock()
            .expect("llamafile lifecycle mutex poisoned") = next;
    }

    /// Read-only-Sicht auf die eingegangene Config (für Tests /
    /// Diagnose).
    #[cfg(test)]
    pub fn config(&self) -> &LlamafileConfigView {
        &self.config
    }

    pub async fn run(&self, input: &str) -> Result<String> {
        match self.lifecycle() {
            LlamafileLifecycle::Disabled => {
                bail!(
                    "provider llamafile_local is disabled (set SMOLIT_LLAMAFILE_ENABLED=1 to enable)"
                )
            }
            LlamafileLifecycle::NotConfigured => {
                bail!(
                    "provider llamafile_local is enabled but not configured (set SMOLIT_LLAMAFILE_PATH)"
                )
            }
            _ => {}
        }

        // Serialisierter Runtime-Block: Spawn (falls nötig), Readiness,
        // Request. `state` bleibt den gesamten run()-Aufruf gelockt —
        // das ist der bewusste Single-Request-MVP.
        let mut state = self.inner.state.lock().await;

        // Falls bereits gestoppt oder nie gestartet, starte jetzt.
        // Der Test-Port-Override lenkt nur den HTTP-Client um; der
        // Prozess-Spawn wird nicht übersprungen.
        let need_spawn = state.child.is_none();
        if need_spawn {
            self.spawn_and_wait_ready(&mut state).await?;
        }

        // Request senden. Busy für die Dauer des HTTP-Calls, anschließend
        // zurück auf Ready.
        self.set_lifecycle(LlamafileLifecycle::Busy);
        let port = self.effective_port();
        let timeout_secs = self.config.request_timeout_seconds;
        let result = post_completion(LLAMAFILE_HOST, port, input, DEFAULT_N_PREDICT, timeout_secs).await;
        match result {
            Ok(text) => {
                state.last_used = Instant::now();
                self.set_lifecycle(LlamafileLifecycle::Ready);
                // Watchdog einmalig starten, sobald echter Runtime
                // aktiv ist (nicht im Test-Port-Override-Pfad).
                if !state.watchdog_running && state.child.is_some() {
                    state.watchdog_running = true;
                    self.spawn_watchdog();
                }
                Ok(text)
            }
            Err(err) => {
                // Ehrliche Runtime-Semantik: Lifecycle auf Failed,
                // Fehler hochreichen. Nächster run() versucht einen
                // frischen Spawn (siehe `need_spawn`-Check).
                self.set_lifecycle(LlamafileLifecycle::Failed);
                // Prozess killen (Drop + kill_on_drop), damit der
                // nächste Request nicht auf einen halbkaputten
                // Hintergrundprozess trifft.
                state.child = None;
                state.watchdog_running = false;
                Err(err)
            }
        }
    }

    /// Startet den lokalen Prozess und pollt `/health`, bis er antwortet
    /// oder `startup_timeout_seconds` erreicht ist. Setzt Lifecycle von
    /// `Starting` auf `Ready` — bei Fehler auf `Failed`.
    async fn spawn_and_wait_ready(
        &self,
        state: &mut LlamafileRuntimeState,
    ) -> Result<()> {
        self.set_lifecycle(LlamafileLifecycle::Starting);

        let path = self
            .config
            .path
            .clone()
            .unwrap_or_default();
        if path.trim().is_empty() {
            // Darf eigentlich nicht passieren (initial_lifecycle setzt
            // NotConfigured), defensiv trotzdem behandelt.
            self.set_lifecycle(LlamafileLifecycle::NotConfigured);
            bail!(
                "provider llamafile_local is enabled but not configured (set SMOLIT_LLAMAFILE_PATH)"
            );
        }

        // Prozess-Spawn. `kill_on_drop(true)` ist die wichtigste
        // Sicherheitsleine — wird der Provider (oder der Resolver)
        // gedroppt, stirbt auch der Kind-Prozess zuverlässig.
        let mut cmd = Command::new(&path);
        cmd.arg("--server")
            .arg("--host")
            .arg(LLAMAFILE_HOST)
            .arg("--port")
            .arg(self.config.port.to_string())
            .arg("--nobrowser")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        let child = cmd.spawn().map_err(|e| {
            self.set_lifecycle(LlamafileLifecycle::Failed);
            // Kind-spezifischen Fehler sichtbar machen; den
            // konfigurierten Binary-Pfad *nicht* in den Text spiegeln,
            // um Pfad-Leak in Status/Logs zu vermeiden.
            anyhow::anyhow!(
                "llamafile process spawn failed: {}",
                e.kind()
            )
        })?;
        info!(
            mode = %self.config.mode,
            port = self.config.port,
            idle_timeout_seconds = self.config.idle_timeout_seconds,
            startup_timeout_seconds = self.config.startup_timeout_seconds,
            "llamafile process spawned (mode `standby` is reserved and currently behaves like `on_demand`)",
        );
        state.child = Some(child);
        state.last_used = Instant::now();

        // Readiness-Loop. Wir pollen `effective_port()` — in
        // Produktions-Läufen identisch zu `config.port`; in Tests mit
        // gesetztem `test_port_override` wird der HTTP-Client auf den
        // Fake-Server umgelenkt, ohne den Spawn-Pfad zu verbiegen.
        let port = self.effective_port();
        let startup_total = Duration::from_secs(self.config.startup_timeout_seconds);
        let start = Instant::now();
        loop {
            // Wenn der Prozess früh stirbt, Loop abbrechen.
            let child_ref = state
                .child
                .as_mut()
                .expect("child must be Some during readiness");
            if let Ok(Some(status)) = child_ref.try_wait() {
                self.set_lifecycle(LlamafileLifecycle::Failed);
                state.child = None;
                bail!(
                    "llamafile process exited during startup with {}",
                    status,
                );
            }
            // Eine einzelne /health-Probe mit kurzem eigenem Timeout,
            // damit der äußere Readiness-Timeout die Richtschnur bleibt.
            let probe_deadline = start + startup_total;
            let remaining = probe_deadline
                .saturating_duration_since(Instant::now())
                .max(Duration::from_millis(100));
            if check_health(LLAMAFILE_HOST, port, remaining.as_secs().max(1)).await {
                self.set_lifecycle(LlamafileLifecycle::Ready);
                state.last_used = Instant::now();
                return Ok(());
            }
            if start.elapsed() >= startup_total {
                self.set_lifecycle(LlamafileLifecycle::Failed);
                state.child = None;
                bail!("llamafile readiness check timed out");
            }
            sleep(HEALTH_POLL_INTERVAL).await;
        }
    }

    fn spawn_watchdog(&self) {
        // Watchdog hält nur eine `Weak`-Referenz, damit er das Drop des
        // Providers nicht blockiert. Sobald der Arc freigegeben ist,
        // beendet sich der Watchdog beim nächsten Tick.
        let weak = Arc::downgrade(&self.inner);
        // Check-Intervall: halber idle_timeout, mindestens 100 ms,
        // höchstens 5 s. Kurze Werte machen kurze Test-Timeouts
        // reaktionsschnell; lange Werte halten die Last im Produktiv-
        // Betrieb minimal.
        let idle_timeout = Duration::from_secs(self.config.idle_timeout_seconds.max(1));
        let check_interval = idle_timeout
            .checked_div(2)
            .unwrap_or(idle_timeout)
            .max(Duration::from_millis(100))
            .min(Duration::from_secs(5));
        tokio::spawn(async move {
            loop {
                sleep(check_interval).await;
                let Some(inner) = weak.upgrade() else {
                    return;
                };
                let mut state = inner.state.lock().await;
                if state.child.is_none() {
                    state.watchdog_running = false;
                    return;
                }
                if state.last_used.elapsed() >= idle_timeout {
                    // Drop = kill_on_drop (SIGKILL + reap).
                    state.child = None;
                    state.watchdog_running = false;
                    *inner
                        .lifecycle
                        .lock()
                        .expect("llamafile lifecycle mutex poisoned") =
                        LlamafileLifecycle::Stopped;
                    info!("llamafile idle timeout reached; process stopped");
                    return;
                }
            }
        });
    }

    fn effective_port(&self) -> u16 {
        self.test_port().unwrap_or(self.config.port)
    }

    fn test_port(&self) -> Option<u16> {
        // In Produktions-Läufen nie gesetzt — Feld bleibt dort
        // permanent `None`. Der kleine Mutex-Read schont Cache-Line
        // und hat keine Kosten im Hot-Path, weil `run()` diese
        // Funktion genau einmal pro Request aufruft.
        *self
            .inner
            .test_port_override
            .lock()
            .expect("test port override poisoned")
    }
}

// --- Local-HTTP-Provider (PR 8) ----------------------------------------
//
// Allgemeiner lokaler HTTP-Text-Provider. Spiegelt den minimalen
// Request-/Response-Pfad des llamafile-Runtimes, aber gegen einen
// **konfigurierbaren** Endpoint statt eines selbst gestarteten
// Prozesses. Keine eigene HTTP-Library — wir nutzen den bereits
// bestehenden [`http_request`]-Helfer (raw HTTP/1.1 über
// `tokio::net::TcpStream`), damit wir keine neue Dependency einziehen
// und die Secret-/Leak-Disziplin identisch bleibt.
//
// Architektur-Grenzen (siehe
// `docs/provider_fallback_and_settings_architecture.md` §4.1):
//
//   * **Kein TLS.** `https://` wird beim Parse verworfen. PR 8 ist
//     loopback-first; eine Remote-/TLS-Integration bräuchte eine
//     eigene Credential-/Trust-Discovery, die dieser PR bewusst nicht
//     einführt.
//   * **Keine Secrets.** Kein Authorization-Header, keine API-Keys
//     — der Provider transportiert sie nicht, die Config speichert sie
//     nicht.
//   * **Kein Streaming, kein Tool-/Schema-Mode.** Single-Shot-Request
//     mit einem einzigen Prompt-Feld; Antwort ist ein einziges
//     Text-Feld. Wer mehr braucht, kommt in einem späteren PR dran.

#[derive(Debug, Clone)]
pub struct LocalHttpConfigView {
    pub enabled: bool,
    pub endpoint: Option<String>,
    pub request_timeout_seconds: u64,
    pub prompt_field: String,
    pub response_field: String,
}

#[derive(Debug, Clone)]
pub struct LocalHttpProvider {
    config: LocalHttpConfigView,
}

impl LocalHttpProvider {
    pub fn new(config: LocalHttpConfigView) -> Self {
        Self { config }
    }

    /// Kleiner URL-Parser. Akzeptiert ausschließlich `http://`-URLs
    /// ohne User-Info und ohne Query. Liefert `(host, port, path)`.
    /// Fehlt der Port, wird `80` angenommen.
    ///
    /// Bewusst kein `url`-Crate, kein `http`-Crate, kein `reqwest` —
    /// wir sprechen HTTP/1.1 direkt, und die Parse-Regeln sind so
    /// schmal wie der Provider.
    pub fn parse_endpoint(endpoint: &str) -> Result<(String, u16, String)> {
        let trimmed = endpoint.trim();
        if trimmed.is_empty() {
            bail!("local_http endpoint is not configured");
        }
        if trimmed.starts_with("https://") {
            bail!(
                "local_http endpoint must start with http:// (https:// is not supported in this build)"
            );
        }
        let Some(rest) = trimmed.strip_prefix("http://") else {
            bail!("local_http endpoint url is not parseable (missing http:// prefix)");
        };
        if rest.contains('@') {
            bail!("local_http endpoint url is not parseable (user-info in url not supported)");
        }
        let (authority, path) = match rest.find('/') {
            Some(idx) => (&rest[..idx], &rest[idx..]),
            None => (rest, "/"),
        };
        if authority.is_empty() {
            bail!("local_http endpoint url is not parseable (empty host)");
        }
        let (host, port) = match authority.rfind(':') {
            Some(idx) => {
                let (h, p) = authority.split_at(idx);
                let p_num = p[1..]
                    .parse::<u16>()
                    .map_err(|_| anyhow::anyhow!(
                        "local_http endpoint url is not parseable (bad port)"
                    ))?;
                (h.to_string(), p_num)
            }
            None => (authority.to_string(), 80u16),
        };
        if host.is_empty() {
            bail!("local_http endpoint url is not parseable (empty host)");
        }
        Ok((host, port, path.to_string()))
    }

    pub async fn run(&self, input: &str) -> Result<String> {
        if !self.config.enabled {
            bail!("provider local_http is disabled (set SMOLIT_LOCAL_HTTP_ENABLED=1 to enable)");
        }
        let endpoint = self
            .config
            .endpoint
            .as_deref()
            .map(str::trim)
            .filter(|e| !e.is_empty())
            .context("provider local_http is enabled but not configured (set SMOLIT_LOCAL_HTTP_ENDPOINT)")?;

        let (host, port, path) = Self::parse_endpoint(endpoint)?;

        // Request-Body: ein einziges JSON-Objekt mit dem konfigurierten
        // Prompt-Feldnamen. `stream=false` bleibt konstant — siehe
        // Nicht-Ziele.
        let prompt_field = if self.config.prompt_field.trim().is_empty() {
            "prompt"
        } else {
            self.config.prompt_field.as_str()
        };
        let response_field = if self.config.response_field.trim().is_empty() {
            "content"
        } else {
            self.config.response_field.as_str()
        };
        let payload = serde_json::json!({
            prompt_field: input,
            "stream": false,
        });
        let body = payload.to_string();

        let timeout_secs = self.config.request_timeout_seconds.max(1);
        let (status, response_body) =
            match http_request(&host, port, "POST", &path, Some(&body), timeout_secs).await {
                Ok(v) => v,
                Err(err) => {
                    // Raw-Helper-Fehler tragen bereits Kontext
                    // (`llamafile HTTP connect timed out` etc.). Um den
                    // Fehler eindeutig dem `local_http`-Provider
                    // zuzuordnen, wrappen wir die Meldung — der
                    // Klassifikator in [`TextProviderImpl::classify_error`]
                    // greift darauf zu.
                    let msg = format!("{err}");
                    if msg.contains("connect timed out") || msg.contains("connect failed") {
                        return Err(err.context("local_http HTTP connect failed"));
                    }
                    if msg.contains("timed out") {
                        return Err(err.context("local_http request timed out"));
                    }
                    return Err(err.context("local_http HTTP request failed"));
                }
            };
        if status != 200 {
            bail!("local_http HTTP returned status {status}");
        }
        let parsed: serde_json::Value = serde_json::from_str(&response_body)
            .context("local_http response is not valid JSON")?;
        let content = parsed
            .get(response_field)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if content.is_empty() {
            bail!("local_http returned no content");
        }
        Ok(content)
    }
}

// --- Kleine lokale HTTP-Helfer (POST /completion + GET /health) -----
//
// Keine SDK-Abhängigkeit: wir sprechen HTTP/1.1 direkt über
// `tokio::net::TcpStream`. llamafile bzw. llama.cpp-Server antworten
// standardmäßig mit `Content-Length` (kein Streaming in dieser Stufe),
// `Connection: close` auf unserer Seite erzwingt das Schließen nach
// der Response. So können wir `read_to_end` nutzen, ohne eine
// komplette HTTP-Parsing-Bibliothek einzuziehen.

async fn http_request(
    host: &str,
    port: u16,
    method: &str,
    path: &str,
    body: Option<&str>,
    timeout_secs: u64,
) -> Result<(u16, String)> {
    let addr = format!("{host}:{port}");
    let total_timeout = Duration::from_secs(timeout_secs.max(1));

    let mut request = String::new();
    request.push_str(&format!("{method} {path} HTTP/1.1\r\n"));
    request.push_str(&format!("Host: {host}:{port}\r\n"));
    request.push_str("Connection: close\r\n");
    if let Some(b) = body {
        request.push_str("Content-Type: application/json\r\n");
        request.push_str(&format!("Content-Length: {}\r\n", b.len()));
    }
    request.push_str("\r\n");
    if let Some(b) = body {
        request.push_str(b);
    }

    let mut stream = timeout(total_timeout, TcpStream::connect(&addr))
        .await
        .context("llamafile HTTP connect timed out")?
        .context("llamafile HTTP connect failed")?;
    timeout(total_timeout, stream.write_all(request.as_bytes()))
        .await
        .context("llamafile HTTP write timed out")?
        .context("llamafile HTTP write failed")?;
    let mut buf = Vec::with_capacity(4096);
    timeout(total_timeout, stream.read_to_end(&mut buf))
        .await
        .context("llamafile HTTP read timed out")?
        .context("llamafile HTTP read failed")?;

    let text = String::from_utf8(buf).context("llamafile HTTP response not valid UTF-8")?;
    let (status_line, rest) = text
        .split_once("\r\n")
        .context("llamafile HTTP response missing status line")?;
    let status = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse::<u16>().ok())
        .context("llamafile HTTP response has no numeric status code")?;
    let (_headers, body_out) = rest
        .split_once("\r\n\r\n")
        .context("llamafile HTTP response has no body separator")?;
    Ok((status, body_out.to_string()))
}

/// Kleiner `GET /health`-Ping. Liefert `true`, wenn der Server mit
/// Status 200 antwortet. Jeder andere Fehler wird still als `false`
/// behandelt, damit die Readiness-Schleife weiter pollt, statt sofort
/// abzubrechen.
async fn check_health(host: &str, port: u16, timeout_secs: u64) -> bool {
    match http_request(host, port, "GET", "/health", None, timeout_secs).await {
        Ok((200, _)) => true,
        _ => false,
    }
}

/// `POST /completion` gegen einen lokalen llama.cpp-kompatiblen Server.
/// Erwartet die nicht-streaming-Antwortform `{"content": "..."}`. Leere
/// Antworten und JSON-Parse-Fehler werden klassifiziert und ehrlich
/// weitergereicht (siehe `TextProviderImpl::classify_error`).
async fn post_completion(
    host: &str,
    port: u16,
    prompt: &str,
    n_predict: u32,
    timeout_secs: u64,
) -> Result<String> {
    let payload = serde_json::json!({
        "prompt": prompt,
        "n_predict": n_predict,
        "stream": false,
    });
    let body = payload.to_string();
    let (status, response_body) =
        http_request(host, port, "POST", "/completion", Some(&body), timeout_secs).await?;
    if status != 200 {
        bail!("llamafile HTTP returned status {status}");
    }
    let parsed: serde_json::Value =
        serde_json::from_str(&response_body).context("llamafile response is not valid JSON")?;
    let content = parsed
        .get("content")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if content.is_empty() {
        bail!("llamafile returned no content");
    }
    Ok(content)
}

/// Laufzeit-Status des Resolvers. Wird pro Request aktualisiert und im
/// `StatusPayload` gespiegelt.
#[derive(Debug, Clone)]
pub struct TextProviderRuntimeStatus {
    /// Primärer (konfigurierter) Provider-Kind-Name in der Kette —
    /// `chain[0]`. `"none"` wenn die Kette leer ist.
    pub configured: String,
    /// Provider-Kind, der den **letzten** erfolgreichen Request
    /// beantwortet hat. Leer, solange kein Request erfolgreich war.
    pub active: String,
    /// `"available"` (nominell, Kette nicht leer) / `"unavailable"`
    /// (Kette leer oder letzter Request in allen Providern
    /// fehlgeschlagen) / `"fallback_active"` (ein Nicht-Primary-
    /// Provider hat den letzten Request beantwortet).
    pub availability: String,
    /// Kurze Fehlerklasse des letzten Failure-Zyklus. `None` im
    /// Erfolgsfall.
    pub last_error: Option<String>,
    /// Ob der aktuell aktive Provider ein Cloud-Pfad ist. In PR 2
    /// existiert kein Cloud-Provider — das Feld ist additiv da, damit
    /// spätere PRs die Regel aus Architektur-Doku §7 einhalten können,
    /// ohne das StatusPayload-Schema zu brechen.
    pub cloud: bool,
}

impl TextProviderRuntimeStatus {
    fn initial(chain: &[TextProviderImpl]) -> Self {
        let (configured, availability) = match chain.first() {
            Some(first) => (first.kind_name().to_string(), "available".to_string()),
            None => ("none".to_string(), "unavailable".to_string()),
        };
        Self {
            configured,
            active: String::new(),
            availability,
            last_error: None,
            cloud: false,
        }
    }
}

/// Der eigentliche Resolver. Hält die geordnete Provider-Kette und
/// einen kleinen Laufzeit-Status.
pub struct TextProviderResolver {
    providers: Vec<TextProviderImpl>,
    status: Mutex<TextProviderRuntimeStatus>,
}

impl TextProviderResolver {
    /// Konstruiert einen Resolver aus einer vorgefertigten Provider-
    /// Liste. Diese Form wird in Tests direkt benutzt; die produktive
    /// Einbettung nutzt [`Self::from_chain`].
    pub fn from_providers(providers: Vec<TextProviderImpl>) -> Self {
        let status = TextProviderRuntimeStatus::initial(&providers);
        Self {
            providers,
            status: Mutex::new(status),
        }
    }

    /// Baut einen Resolver aus einer Kind-Kette, der ABrain-CLI-
    /// Kommandozeile und der Llamafile-Config-Sicht. Unbekannte
    /// Kind-Namen werden zusammen mit einem `warn!`-Log verworfen —
    /// der Core crasht nie wegen einer kaputten
    /// `SMOLIT_TEXT_PROVIDER_CHAIN`.
    ///
    /// Bleibt nach dem Filtern keine einzige bekannte Klasse übrig,
    /// fällt die Kette auf den **Default** (`["abrain"]`) zurück und
    /// loggt das sichtbar. Das ist die konservative Variante aus
    /// §3 der Architektur-Doku („Fallback ist explizit"): wir fallen
    /// niemals in eine Cloud-Klasse zurück, und wir lassen die Kette
    /// auch nicht still leer.
    ///
    /// `llamafile_local` wird in dieser Stufe **instanziiert**, auch
    /// wenn die Config ihn als disabled oder nicht konfiguriert
    /// ausweist — der Stub trägt das als Lifecycle sichtbar und
    /// liefert bei `run()` einen ehrlichen klassifizierten Fehler,
    /// statt still aus der Kette zu verschwinden. So bleibt der
    /// Fallback-Fluss `llamafile_local → abrain` überprüfbar.
    pub fn from_chain(
        chain: &[TextProviderChainItem],
        abrain_cmd: &str,
        llamafile: &LlamafileConfigView,
        local_http: &LocalHttpConfigView,
    ) -> Self {
        let mut providers: Vec<TextProviderImpl> = Vec::with_capacity(chain.len());
        let mut skipped_unknown: Vec<String> = Vec::new();
        let mut saw_llamafile = false;
        for item in chain {
            let normalized = item.kind.trim().to_ascii_lowercase();
            match normalized.as_str() {
                PROVIDER_NAME_ABRAIN => {
                    providers.push(TextProviderImpl::Abrain(AbrainCliProvider::new(abrain_cmd)));
                }
                PROVIDER_NAME_LLAMAFILE_LOCAL => {
                    providers.push(TextProviderImpl::LlamafileLocal(
                        LlamafileLocalProvider::new(llamafile.clone()),
                    ));
                    saw_llamafile = true;
                }
                PROVIDER_NAME_LOCAL_HTTP => {
                    providers.push(TextProviderImpl::LocalHttp(LocalHttpProvider::new(
                        local_http.clone(),
                    )));
                }
                other => {
                    skipped_unknown.push(other.to_string());
                }
            }
        }
        if !skipped_unknown.is_empty() {
            warn!(
                skipped = ?skipped_unknown,
                "ignoring unknown text provider kinds in chain (not yet implemented in this build)",
            );
        }
        if providers.is_empty() {
            warn!(
                "no known text providers in configured chain — falling back to default chain [abrain]",
            );
            providers.push(TextProviderImpl::Abrain(AbrainCliProvider::new(abrain_cmd)));
        }
        if saw_llamafile {
            // Ehrlicher Sichtbarkeits-Log beim Build: wenn ein
            // llamafile-Stub aktiv mit disabled/not_configured startet,
            // zeigt das Betreibern der Konfiguration, warum der Fallback
            // später greifen wird. `ready` (heute unerreichbar) taucht
            // hier nicht auf, damit Nutzer nicht glauben, der Runtime-
            // Pfad sei schon aktiv.
            if let Some(TextProviderImpl::LlamafileLocal(stub)) = providers.iter().find(|p| {
                matches!(p, TextProviderImpl::LlamafileLocal(_))
            }) {
                info!(
                    lifecycle = %stub.lifecycle().as_str(),
                    "llamafile_local provider built (runtime not yet implemented; refusal is honest)",
                );
            }
        }
        Self::from_providers(providers)
    }

    /// Read-only-Snapshot des Laufzeit-Status — für StatusPayload /
    /// Diagnose-Logs. Klont das Dict; der Mutex wird nicht gehalten.
    pub fn status(&self) -> TextProviderRuntimeStatus {
        self.status
            .lock()
            .expect("text provider status mutex poisoned")
            .clone()
    }

    /// Anzahl Provider in der aktuellen Kette. Primär für Tests.
    #[cfg(test)]
    pub fn chain_len(&self) -> usize {
        self.providers.len()
    }

    /// Kanonische Kind-Namen der aktuellen Kette in Reihenfolge.
    /// Wird ab PR 4 zusätzlich zum bestehenden `configured`-Feld in
    /// das StatusPayload projiziert, damit die UI die gesamte Fallback-
    /// Reihenfolge ehrlich anzeigen kann — kein neues Event, kein
    /// Push-Kanal.
    pub fn chain_kinds(&self) -> Vec<&'static str> {
        self.providers.iter().map(|p| p.kind_name()).collect()
    }

    /// Lifecycle des `llamafile_local`-Providers aus der Kette, **falls
    /// vorhanden**. Gibt `None` zurück, wenn die Kette keinen
    /// llamafile-Provider enthält — so bleibt die UI ehrlich:
    /// `None` bedeutet „nicht in der Kette", nicht „Runtime kaputt".
    ///
    /// Zwei llamafile-Einträge in derselben Kette sind laut Resolver-
    /// Baupfad nicht vorgesehen; der Lookup liefert in diesem
    /// (hypothetischen) Fall den Lifecycle des ersten Vorkommens.
    pub fn llamafile_lifecycle(&self) -> Option<LlamafileLifecycle> {
        self.providers.iter().find_map(|p| match p {
            TextProviderImpl::LlamafileLocal(provider) => Some(provider.lifecycle()),
            _ => None,
        })
    }

    /// Hauptdispatch: probiert jeden Provider der Kette in Reihenfolge,
    /// liefert die erste erfolgreiche Antwort. Aktualisiert den
    /// Laufzeit-Status deterministisch.
    ///
    /// Semantik in Kürze:
    ///
    /// * **Leere Kette** → `Err(TextProviderError::EmptyChain)`.
    ///   Status: `availability="unavailable"`, `active=""`.
    ///   Kein stiller Fallback in irgendetwas anderes.
    /// * **Ein Provider gelingt** → `Ok(text)`. Status: `active=<kind>`,
    ///   `availability="available"` (wenn `kind == chain[0]`) oder
    ///   `"fallback_active"` (sonst). `last_error=None`.
    /// * **Alle Provider scheitern** → `Err(TextProviderError::AllFailed)`.
    ///   Status: `availability="unavailable"`, `active=""`,
    ///   `last_error=<kurze Klasse>`. Log zeigt die Fehlerkette, aber
    ///   nicht den Roh-Output der Provider.
    pub async fn run(&self, input: &str) -> Result<String, TextProviderError> {
        if self.providers.is_empty() {
            let mut s = self
                .status
                .lock()
                .expect("text provider status mutex poisoned");
            s.configured = "none".to_string();
            s.active = String::new();
            s.availability = "unavailable".to_string();
            s.last_error = Some("empty_chain".to_string());
            s.cloud = false;
            return Err(TextProviderError::EmptyChain);
        }

        let primary = self.providers[0].kind_name().to_string();
        let mut last_err_class: Option<String> = None;

        for (index, provider) in self.providers.iter().enumerate() {
            match provider.run(input).await {
                Ok(text) => {
                    let kind = provider.kind_name().to_string();
                    let availability = if index == 0 {
                        "available".to_string()
                    } else {
                        "fallback_active".to_string()
                    };
                    let mut s = self
                        .status
                        .lock()
                        .expect("text provider status mutex poisoned");
                    s.configured = primary;
                    s.active = kind.clone();
                    s.availability = availability;
                    s.last_error = None;
                    s.cloud = false;
                    if index > 0 {
                        info!(
                            primary = %s.configured,
                            active = %kind,
                            "text provider fallback active — primary unavailable, secondary produced response",
                        );
                    }
                    return Ok(text);
                }
                Err(err) => {
                    let class = TextProviderImpl::classify_error(&err);
                    warn!(
                        provider = %provider.kind_name(),
                        error_class = %class,
                        error = %err,
                        "text provider failed — trying next in chain",
                    );
                    last_err_class = Some(class.to_string());
                }
            }
        }

        let last = last_err_class.unwrap_or_else(|| "unknown".to_string());
        {
            let mut s = self
                .status
                .lock()
                .expect("text provider status mutex poisoned");
            s.configured = primary;
            s.active = String::new();
            s.availability = "unavailable".to_string();
            s.last_error = Some(last.clone());
            s.cloud = false;
        }
        Err(TextProviderError::AllFailed(last))
    }
}

impl std::fmt::Debug for TextProviderResolver {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TextProviderResolver")
            .field("providers", &self.providers)
            .field("status", &self.status())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn abrain_item() -> TextProviderChainItem {
        TextProviderChainItem {
            kind: PROVIDER_NAME_ABRAIN.to_string(),
        }
    }

    fn llamafile_item() -> TextProviderChainItem {
        TextProviderChainItem {
            kind: PROVIDER_NAME_LLAMAFILE_LOCAL.to_string(),
        }
    }

    fn local_http_item() -> TextProviderChainItem {
        TextProviderChainItem {
            kind: PROVIDER_NAME_LOCAL_HTTP.to_string(),
        }
    }

    /// Default-`LocalHttpConfigView` mit disabled/None-Endpoint — für
    /// Tests, die `local_http` gar nicht in der Kette haben und nur
    /// einen ehrlichen Default-View an den Resolver-Builder reichen
    /// müssen.
    fn local_http_view_disabled() -> LocalHttpConfigView {
        LocalHttpConfigView {
            enabled: false,
            endpoint: None,
            request_timeout_seconds: 5,
            prompt_field: "prompt".into(),
            response_field: "content".into(),
        }
    }

    /// Aktive View gegen einen Fake-Server. Der Aufrufer muss den Port
    /// in die URL einsetzen.
    fn local_http_view_with_endpoint(endpoint: String) -> LocalHttpConfigView {
        LocalHttpConfigView {
            enabled: true,
            endpoint: Some(endpoint),
            request_timeout_seconds: 3,
            prompt_field: "prompt".into(),
            response_field: "content".into(),
        }
    }

    fn llamafile_view_disabled() -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: false,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 5,
            request_timeout_seconds: 5,
        }
    }

    fn llamafile_view_not_configured() -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: true,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 5,
            request_timeout_seconds: 5,
        }
    }

    /// "Configured" mit einem Pfad, der garantiert *nicht* existiert.
    /// Wird verwendet, um den Spawn-Failure-Pfad (→ `process_missing`)
    /// zu testen, ohne einen echten llamafile-Prozess zu brauchen.
    fn llamafile_view_configured_missing_binary() -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: true,
            path: Some("/nonexistent/smolit-llamafile-test-binary".into()),
            mode: "standby".into(),
            idle_timeout_seconds: 120,
            port: 8788,
            startup_timeout_seconds: 1,
            request_timeout_seconds: 1,
        }
    }

    // --- Lifecycle tag stability --------------------------------------

    #[test]
    fn llamafile_lifecycle_tag_strings_are_stable() {
        // Die as_str()-Tags sind das einzige stabile externe
        // Vokabular des Lifecycle-Modells (Logs, spätere StatusPayload-
        // Erweiterung). Wir frieren sie hier ein, damit ein späterer
        // Runtime-PR die Strings nicht versehentlich umbenennt.
        assert_eq!(LlamafileLifecycle::Disabled.as_str(), "disabled");
        assert_eq!(LlamafileLifecycle::NotConfigured.as_str(), "not_configured");
        assert_eq!(LlamafileLifecycle::Configured.as_str(), "configured");
        assert_eq!(LlamafileLifecycle::Starting.as_str(), "starting");
        assert_eq!(LlamafileLifecycle::Ready.as_str(), "ready");
        assert_eq!(LlamafileLifecycle::Busy.as_str(), "busy");
        assert_eq!(LlamafileLifecycle::Failed.as_str(), "failed");
        assert_eq!(LlamafileLifecycle::Stopped.as_str(), "stopped");
    }

    // --- LlamafileLocalProvider lifecycle init + run ------------------

    #[test]
    fn llamafile_disabled_when_enabled_flag_is_false() {
        let p = LlamafileLocalProvider::new(llamafile_view_disabled());
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Disabled);
    }

    #[test]
    fn llamafile_not_configured_when_enabled_but_path_missing() {
        let p = LlamafileLocalProvider::new(llamafile_view_not_configured());
        assert_eq!(p.lifecycle(), LlamafileLifecycle::NotConfigured);
    }

    #[test]
    fn llamafile_configured_when_enabled_and_path_set() {
        let p = LlamafileLocalProvider::new(llamafile_view_configured_missing_binary());
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Configured);
        assert_eq!(p.config().mode, "standby");
        assert_eq!(p.config().idle_timeout_seconds, 120);
    }

    #[test]
    fn llamafile_path_with_only_whitespace_counts_as_not_configured() {
        let view = LlamafileConfigView {
            enabled: true,
            path: Some("   ".into()),
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 1,
            request_timeout_seconds: 1,
        };
        let p = LlamafileLocalProvider::new(view);
        assert_eq!(p.lifecycle(), LlamafileLifecycle::NotConfigured);
    }

    #[tokio::test]
    async fn llamafile_run_reports_disabled_when_lifecycle_disabled() {
        let p = LlamafileLocalProvider::new(llamafile_view_disabled());
        let err = p.run("hi").await.expect_err("disabled must refuse");
        let class = TextProviderImpl::classify_error(&err);
        assert_eq!(class, "disabled");
        assert!(format!("{err:#}").contains("llamafile_local"));
    }

    #[tokio::test]
    async fn llamafile_run_reports_not_configured_when_path_missing() {
        let p = LlamafileLocalProvider::new(llamafile_view_not_configured());
        let err = p.run("hi").await.expect_err("missing path must refuse");
        let class = TextProviderImpl::classify_error(&err);
        assert_eq!(class, "not_configured");
    }

    #[tokio::test]
    async fn llamafile_run_spawn_failure_reports_process_missing() {
        // PR 2b: Configured-Lifecycle versucht einen echten Spawn. Ein
        // nicht existierender Binary-Pfad schlägt sofort mit einer
        // os::ErrorKind fehl und landet im `process_missing`-Tag. Nach
        // dem Fehlschlag ist der Lifecycle `Failed` und der Pfad bleibt
        // *nicht* im Fehlertext sichtbar (Pfad-Leak-Schutz).
        let p = LlamafileLocalProvider::new(llamafile_view_configured_missing_binary());
        let err = p
            .run("hi")
            .await
            .expect_err("spawn with missing binary must fail");
        let class = TextProviderImpl::classify_error(&err);
        assert_eq!(class, "process_missing");
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Failed);
        let msg = format!("{err:#}");
        assert!(
            !msg.contains("/nonexistent/smolit-llamafile-test-binary"),
            "binary path must not leak into error text (got: {msg})",
        );
    }

    // --- Runtime-Integrationstests ------------------------------------
    //
    // Ohne echten llamafile-Binary: wir setzen zwei Primitiven auf:
    //
    //   * einen kleinen lokalen Tokio-HTTP-Server, der `GET /health`
    //     mit 200 OK und `POST /completion` mit einer fixen
    //     `{"content": "..."}`-Antwort beantwortet,
    //   * ein kurzes Shell-Skript unter `/tmp`, das bei Start
    //     unkonditional `sleep 60` ausführt und damit als
    //     „Runtime-Prozess" lebendig bleibt.
    //
    // Über den (cfg(test)-gated) `test_port_override` lenken wir den
    // HTTP-Client des Providers auf den Fake-Server um. Der Provider
    // durchläuft dadurch die produktive Code-Bahn (Spawn → try_wait-
    // Probe → Readiness-Poll → HTTP → Busy/Ready-Transitions), ohne
    // ein echtes llamafile-Binary zu brauchen.

    use tokio::net::TcpListener;
    use tokio::task::JoinHandle;

    /// Startet einen winzigen lokalen HTTP-Server auf `127.0.0.1:0`,
    /// der `GET /health` mit 200 OK und `POST /completion` mit einer
    /// fixen Completion-Antwort beantwortet. Liefert den effektiven
    /// Port und ein Handle auf den Accept-Loop. Der Loop wird beim
    /// Drop des Handles abgewürgt (`abort()`), nicht graceful — für
    /// Tests ausreichend.
    async fn start_fake_llama_server(content: &'static str) -> (u16, JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let port = listener.local_addr().unwrap().port();
        let handle = tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    return;
                };
                // Kleines Request-Puffer-Read; für Health/Completion-
                // Requests reicht ein einmaliger read — kein
                // dynamisches Content-Length-Handling.
                let mut buf = [0u8; 4096];
                let Ok(n) = socket.read(&mut buf).await else {
                    let _ = socket.shutdown().await;
                    continue;
                };
                let request = String::from_utf8_lossy(&buf[..n]);
                let (status, body) = if request.starts_with("GET /health") {
                    ("HTTP/1.1 200 OK", "{\"status\":\"ok\"}".to_string())
                } else if request.starts_with("POST /completion") {
                    let json = format!(r#"{{"content":"{content}"}}"#);
                    ("HTTP/1.1 200 OK", json)
                } else {
                    ("HTTP/1.1 404 Not Found", String::new())
                };
                let response = format!(
                    "{status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len(),
                );
                let _ = socket.write_all(response.as_bytes()).await;
                let _ = socket.shutdown().await;
            }
        });
        (port, handle)
    }

    /// Wie `start_fake_llama_server`, aber der Server liefert immer
    /// `500 Internal Server Error` — für Tests, die den non-200-Pfad
    /// brauchen.
    async fn start_fake_llama_server_returning_500() -> (u16, JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let port = listener.local_addr().unwrap().port();
        let handle = tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    return;
                };
                let mut buf = [0u8; 1024];
                let _ = socket.read(&mut buf).await;
                let response =
                    "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                let _ = socket.write_all(response.as_bytes()).await;
                let _ = socket.shutdown().await;
            }
        });
        (port, handle)
    }

    /// Legt ein kleines Shell-Skript unter `/tmp` an, das `sleep 60`
    /// ausführt und damit als „lebendiger Runtime-Prozess" für
    /// Spawn-Tests dient. Ruft `chmod 755`, damit der Kernel es
    /// exec'en darf. Ignoriert alle CLI-Args, die der Provider
    /// anhängt (`--server`, `--host`, `--port`, `--nobrowser`).
    fn make_fake_llama_binary(suffix: &str) -> String {
        let path = format!(
            "/tmp/smolit-test-llama-{pid}-{suffix}.sh",
            pid = std::process::id(),
        );
        std::fs::write(&path, "#!/bin/sh\nexec sleep 60\n").expect("write fake binary");
        let status = std::process::Command::new("chmod")
            .arg("755")
            .arg(&path)
            .status()
            .expect("chmod");
        assert!(status.success(), "chmod failed on {path}");
        path
    }

    fn llamafile_view_runtime(path: &str, idle_timeout_seconds: u64) -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: true,
            path: Some(path.to_string()),
            mode: "on_demand".into(),
            idle_timeout_seconds,
            // Dummy Port; wird im Test durch test_port_override
            // überschrieben, sodass der HTTP-Client den Fake-Server
            // erreicht.
            port: 9,
            startup_timeout_seconds: 3,
            request_timeout_seconds: 3,
        }
    }

    /// Test-Hilfsfunktion: setzt den Port-Override direkt auf dem
    /// Inner-Arc. Produktionspfade verwenden das nicht (siehe
    /// `test_port()`-Kommentar).
    fn set_port_override(provider: &LlamafileLocalProvider, port: u16) {
        *provider
            .inner
            .test_port_override
            .lock()
            .expect("test port override poisoned") = Some(port);
    }

    // --- HTTP-Helfer gegen den Fake-Server ---------------------------

    #[tokio::test]
    async fn http_request_hits_fake_health_endpoint() {
        let (port, _server) = start_fake_llama_server("hi").await;
        let (status, body) = http_request("127.0.0.1", port, "GET", "/health", None, 3)
            .await
            .expect("health request must succeed");
        assert_eq!(status, 200);
        assert!(body.contains("ok"));
    }

    #[tokio::test]
    async fn post_completion_parses_content_field() {
        let (port, _server) = start_fake_llama_server("hallo welt").await;
        let response = post_completion("127.0.0.1", port, "gruß?", 128, 3)
            .await
            .expect("completion must succeed");
        assert_eq!(response, "hallo welt");
    }

    #[tokio::test]
    async fn post_completion_rejects_non_200_status() {
        let (port, _server) = start_fake_llama_server_returning_500().await;
        let err = post_completion("127.0.0.1", port, "x", 16, 3)
            .await
            .expect_err("non-200 must propagate as error");
        let class = TextProviderImpl::classify_error(&err);
        assert_eq!(class, "http_error");
    }

    // --- Runtime: Happy Path --------------------------------------------

    #[tokio::test]
    async fn llamafile_runtime_happy_path_with_fake_server() {
        let (port, _server) = start_fake_llama_server("fake response").await;
        let binary = make_fake_llama_binary("happy");
        let p = LlamafileLocalProvider::new(llamafile_view_runtime(&binary, 600));
        // Port-Override vor dem ersten run() setzen, damit sowohl der
        // Readiness-Poll als auch der Completion-Call am Fake-Server
        // landen.
        set_port_override(&p, port);

        assert_eq!(p.lifecycle(), LlamafileLifecycle::Configured);
        let out = p.run("prompt").await.expect("run must succeed");
        assert_eq!(out, "fake response");
        // Nach erfolgreichem Request zurück auf Ready.
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Ready);
        // Der zweite Request darf nicht erneut spawnen (state.child
        // bleibt Some), aber wieder eine erfolgreiche Antwort liefern.
        let out2 = p.run("prompt 2").await.expect("second run must succeed");
        assert_eq!(out2, "fake response");
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Ready);

        // Cleanup: Provider droppen → kill_on_drop schießt den
        // /bin/sleep-Kind-Prozess ab; Fake-Server-Task wird am Ende des
        // Tests durch `_server` -> JoinHandle::abort() (implizit via
        // Drop) terminiert.
        drop(p);
        let _ = std::fs::remove_file(&binary);
    }

    // --- Runtime: Idle Timeout + Respawn --------------------------------

    #[tokio::test]
    async fn llamafile_idle_timeout_stops_process_and_respawn_recovers() {
        let (port, _server) = start_fake_llama_server("ok").await;
        let binary = make_fake_llama_binary("idle");
        // idle_timeout_seconds = 1 → Watchdog-Intervall ca. 500 ms.
        let p = LlamafileLocalProvider::new(llamafile_view_runtime(&binary, 1));
        set_port_override(&p, port);

        // Erster Request startet Runtime und triggert den Watchdog.
        let _ = p.run("a").await.expect("first run");
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Ready);

        // Auf Stopped warten — max 5 s, in 100-ms-Polls.
        let mut stopped = false;
        for _ in 0..50 {
            sleep(Duration::from_millis(100)).await;
            if p.lifecycle() == LlamafileLifecycle::Stopped {
                stopped = true;
                break;
            }
        }
        assert!(stopped, "watchdog should transition to Stopped");

        // Folge-Request nach Stop muss sauber respawnen und liefern.
        let out = p.run("b").await.expect("respawn must succeed");
        assert_eq!(out, "ok");
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Ready);

        drop(p);
        let _ = std::fs::remove_file(&binary);
    }

    // --- Runtime: Readiness-Timeout -------------------------------------

    #[tokio::test]
    async fn llamafile_readiness_timeout_when_no_http_endpoint() {
        // Kein Fake-Server → Port 1 (reserviert, nichts lauscht) liefert
        // sofort ConnectionRefused für `check_health`. Mit
        // startup_timeout_seconds=1 muss der Readiness-Loop innerhalb
        // kurzer Zeit abbrechen und Lifecycle=Failed setzen.
        let binary = make_fake_llama_binary("readiness");
        let p = LlamafileLocalProvider::new(llamafile_view_runtime(&binary, 600));
        set_port_override(&p, 1);

        let err = p.run("x").await.expect_err("readiness must time out");
        let class = TextProviderImpl::classify_error(&err);
        assert_eq!(class, "startup_timeout");
        assert_eq!(p.lifecycle(), LlamafileLifecycle::Failed);

        drop(p);
        let _ = std::fs::remove_file(&binary);
    }

    // --- Resolver chain building --------------------------------------

    #[test]
    fn from_chain_keeps_known_kinds() {
        let r = TextProviderResolver::from_chain(
            &[abrain_item()],
            "/bin/true",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_len(), 1);
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
        let status = r.status();
        assert_eq!(status.configured, "abrain");
        assert_eq!(status.active, "");
        assert_eq!(status.availability, "available");
        assert!(status.last_error.is_none());
        assert!(!status.cloud);
    }

    #[test]
    fn from_chain_drops_unknown_kinds() {
        let chain = vec![
            TextProviderChainItem {
                kind: "unknown_cloud".into(),
            },
            abrain_item(),
        ];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/true",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
    }

    #[test]
    fn from_chain_empty_or_all_unknown_falls_back_to_default() {
        let chain = vec![
            TextProviderChainItem { kind: "foo".into() },
            TextProviderChainItem { kind: "bar".into() },
        ];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
        assert_eq!(r.status().configured, "abrain");

        let r_empty = TextProviderResolver::from_chain(
            &[],
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r_empty.chain_kinds(), vec!["abrain"]);
    }

    #[test]
    fn from_chain_instantiates_llamafile_local_when_listed() {
        let chain = vec![abrain_item(), llamafile_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured_missing_binary(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["abrain", "llamafile_local"]);
        // Primary bleibt abrain; availability nominell „available".
        assert_eq!(r.status().configured, "abrain");
    }

    #[test]
    fn from_chain_llamafile_first_then_abrain_preserves_order() {
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured_missing_binary(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["llamafile_local", "abrain"]);
        // Primary ist jetzt llamafile_local.
        assert_eq!(r.status().configured, "llamafile_local");
    }

    #[tokio::test]
    async fn run_falls_back_from_llamafile_spawn_failure_to_abrain() {
        // Kette: llamafile_local mit ungültigem Binary-Pfad (Spawn
        // schlägt mit Klasse `process_missing` fehl) → abrain
        // (/bin/echo, produziert Antwort). Erwartung: Resolver
        // aktiviert den Fallback-Pfad, liefert die echo-Antwort und
        // setzt availability=fallback_active.
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured_missing_binary(),
            &local_http_view_disabled(),
        );
        let out = r.run("ping").await.expect("abrain fallback must succeed");
        assert!(out.contains("ping"));
        let status = r.status();
        assert_eq!(status.configured, "llamafile_local");
        assert_eq!(status.active, "abrain");
        assert_eq!(status.availability, "fallback_active");
        assert!(status.last_error.is_none());
    }

    #[tokio::test]
    async fn run_reports_unavailable_when_every_provider_in_chain_refuses() {
        // Kette: llamafile_local (disabled → disabled-Klasse) →
        // abrain (/bin/false → exit_nonzero). Alle Provider scheitern,
        // availability=unavailable, last_error trägt den Tag des
        // *letzten* Providers (abrain → exit_nonzero).
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/false",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        let err = r.run("hi").await.expect_err("all must fail");
        assert!(matches!(err, TextProviderError::AllFailed(_)));
        let status = r.status();
        assert_eq!(status.configured, "llamafile_local");
        assert_eq!(status.active, "");
        assert_eq!(status.availability, "unavailable");
        assert_eq!(status.last_error.as_deref(), Some("exit_nonzero"));
    }

    #[tokio::test]
    async fn run_primary_abrain_success_keeps_llamafile_stub_untouched() {
        // Kette: abrain (/bin/echo, Erfolg) → llamafile_local
        // (Configured-Stub). Primary gelingt direkt, der Stub wird in
        // diesem Request gar nicht erst aufgerufen — availability=
        // available, active=abrain.
        let chain = vec![abrain_item(), llamafile_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured_missing_binary(),
            &local_http_view_disabled(),
        );
        let out = r.run("hi").await.expect("primary abrain must win");
        assert!(out.contains("hi"));
        let status = r.status();
        assert_eq!(status.configured, "abrain");
        assert_eq!(status.active, "abrain");
        assert_eq!(status.availability, "available");
        assert!(status.last_error.is_none());
    }

    // --- run() semantics (via real AbrainCliProvider subprocess calls) -
    // Using real commands keeps the test honest: we exercise the actual
    // production path. `/bin/false` always exits nonzero → provider
    // failure. `/bin/echo` prints its args to stdout; `{cmd} task run
    // <input>` with `echo` yields a non-empty line → provider success.

    #[tokio::test]
    async fn run_success_updates_status_to_available() {
        let providers = vec![TextProviderImpl::Abrain(AbrainCliProvider::new("/bin/echo"))];
        let r = TextProviderResolver::from_providers(providers);
        let out = r.run("hello").await.expect("echo should succeed");
        assert!(out.contains("hello"));
        let status = r.status();
        assert_eq!(status.configured, "abrain");
        assert_eq!(status.active, "abrain");
        assert_eq!(status.availability, "available");
        assert!(status.last_error.is_none());
    }

    #[tokio::test]
    async fn run_single_failing_provider_reports_all_failed_and_classifies_error() {
        let providers = vec![TextProviderImpl::Abrain(AbrainCliProvider::new("/bin/false"))];
        let r = TextProviderResolver::from_providers(providers);
        let err = r.run("hello").await.expect_err("must fail");
        match err {
            TextProviderError::AllFailed(ref class) => {
                assert_eq!(class, "exit_nonzero");
            }
            other => panic!("expected AllFailed, got {other:?}"),
        }
        let status = r.status();
        assert_eq!(status.active, "");
        assert_eq!(status.availability, "unavailable");
        assert_eq!(status.last_error.as_deref(), Some("exit_nonzero"));
    }

    #[tokio::test]
    async fn run_fallback_activates_when_primary_fails_and_secondary_succeeds() {
        // Primary exits nonzero → provider fails. Secondary echoes
        // input → provider succeeds. Resolver must pick the secondary
        // and report `fallback_active`.
        let providers = vec![
            TextProviderImpl::Abrain(AbrainCliProvider::new("/bin/false")),
            TextProviderImpl::Abrain(AbrainCliProvider::new("/bin/echo")),
        ];
        let r = TextProviderResolver::from_providers(providers);
        let out = r.run("ping").await.expect("fallback must succeed");
        assert!(out.contains("ping"));
        let status = r.status();
        assert_eq!(status.configured, "abrain");
        assert_eq!(status.active, "abrain");
        assert_eq!(status.availability, "fallback_active");
        assert!(status.last_error.is_none());
    }

    #[tokio::test]
    async fn run_empty_chain_returns_empty_chain_error() {
        let r = TextProviderResolver::from_providers(vec![]);
        let err = r.run("hi").await.expect_err("empty chain must fail");
        assert!(matches!(err, TextProviderError::EmptyChain));
        let status = r.status();
        assert_eq!(status.configured, "none");
        assert_eq!(status.active, "");
        assert_eq!(status.availability, "unavailable");
        assert_eq!(status.last_error.as_deref(), Some("empty_chain"));
    }

    // --- Local-HTTP-Provider (PR 8) ----------------------------------
    //
    // Minimaler, ehrlicher HTTP-MVP: wir wiederverwenden den schon
    // bestehenden `start_fake_llama_server`-Helfer. Er antwortet auf
    // `POST /completion` mit `{"content": "..."}` — genau das, was der
    // `local_http`-Default-Response-Field erwartet. So können wir den
    // Request-/Response-Pfad vollständig prüfen, ohne eine neue
    // Test-Infrastruktur einzuziehen.

    #[test]
    fn local_http_endpoint_parser_accepts_http_url_with_port_and_path() {
        let (host, port, path) =
            LocalHttpProvider::parse_endpoint("http://127.0.0.1:9000/v1/completion").unwrap();
        assert_eq!(host, "127.0.0.1");
        assert_eq!(port, 9000);
        assert_eq!(path, "/v1/completion");
    }

    #[test]
    fn local_http_endpoint_parser_defaults_port_80_and_root_path() {
        let (host, port, path) = LocalHttpProvider::parse_endpoint("http://localhost").unwrap();
        assert_eq!(host, "localhost");
        assert_eq!(port, 80);
        assert_eq!(path, "/");
    }

    #[test]
    fn local_http_endpoint_parser_rejects_https() {
        let err = LocalHttpProvider::parse_endpoint("https://example.test/").unwrap_err();
        assert!(format!("{err}").contains("must start with http://"));
    }

    #[test]
    fn local_http_endpoint_parser_rejects_non_http_scheme() {
        let err = LocalHttpProvider::parse_endpoint("ftp://example.test/").unwrap_err();
        assert!(format!("{err}").contains("not parseable"));
    }

    #[test]
    fn local_http_endpoint_parser_rejects_user_info() {
        let err = LocalHttpProvider::parse_endpoint("http://user:pw@host/").unwrap_err();
        assert!(format!("{err}").contains("not parseable"));
    }

    #[test]
    fn local_http_endpoint_parser_rejects_bad_port() {
        let err = LocalHttpProvider::parse_endpoint("http://host:notaport/").unwrap_err();
        assert!(format!("{err}").contains("not parseable"));
    }

    #[tokio::test]
    async fn local_http_run_returns_content_from_fake_server() {
        let (port, _server) = start_fake_llama_server("hallo lokal").await;
        let endpoint = format!("http://127.0.0.1:{port}/completion");
        let provider = LocalHttpProvider::new(local_http_view_with_endpoint(endpoint));
        let response = provider.run("gruß?").await.expect("run must succeed");
        assert_eq!(response, "hallo lokal");
    }

    #[tokio::test]
    async fn local_http_run_disabled_reports_disabled_class() {
        let provider = LocalHttpProvider::new(local_http_view_disabled());
        let err = provider.run("x").await.unwrap_err();
        assert_eq!(
            TextProviderImpl::classify_error(&err),
            "disabled",
        );
    }

    #[tokio::test]
    async fn local_http_run_enabled_without_endpoint_reports_not_configured() {
        let view = LocalHttpConfigView {
            enabled: true,
            endpoint: None,
            ..local_http_view_disabled()
        };
        let provider = LocalHttpProvider::new(view);
        let err = provider.run("x").await.unwrap_err();
        assert_eq!(
            TextProviderImpl::classify_error(&err),
            "not_configured",
        );
    }

    #[tokio::test]
    async fn local_http_run_rejects_https_with_stable_class() {
        let provider = LocalHttpProvider::new(local_http_view_with_endpoint(
            "https://example.test/".into(),
        ));
        let err = provider.run("x").await.unwrap_err();
        assert_eq!(
            TextProviderImpl::classify_error(&err),
            "endpoint_scheme_unsupported",
        );
    }

    #[tokio::test]
    async fn local_http_run_non_200_reports_http_error_class() {
        let (port, _server) = start_fake_llama_server_returning_500().await;
        let provider = LocalHttpProvider::new(local_http_view_with_endpoint(format!(
            "http://127.0.0.1:{port}/completion"
        )));
        let err = provider.run("x").await.unwrap_err();
        assert_eq!(
            TextProviderImpl::classify_error(&err),
            "http_error",
        );
    }

    #[test]
    fn from_chain_instantiates_local_http_when_listed() {
        let r = TextProviderResolver::from_chain(
            &[local_http_item(), abrain_item()],
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_with_endpoint("http://127.0.0.1:59999/completion".into()),
        );
        assert_eq!(r.chain_kinds(), vec!["local_http", "abrain"]);
    }

    #[tokio::test]
    async fn resolver_falls_back_from_local_http_to_abrain_on_connect_failure() {
        // Niemand lauscht auf Port 59999 — der Connect läuft in einen
        // Fehler; die Kette fällt deterministisch auf abrain zurück.
        let r = TextProviderResolver::from_chain(
            &[local_http_item(), abrain_item()],
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_with_endpoint("http://127.0.0.1:59999/completion".into()),
        );
        let response = r.run("hi").await.expect("fallback to abrain must succeed");
        assert!(!response.is_empty());
        let status = r.status();
        assert_eq!(status.configured, "local_http");
        assert_eq!(status.active, "abrain");
        assert_eq!(status.availability, "fallback_active");
    }

    // --- Chain + Llamafile lifecycle accessors (PR 4) -----------------

    /// `llamafile_lifecycle()` gibt `None` zurück, wenn keine
    /// llamafile-Instanz in der Kette steht. So bleibt die UI-Seite
    /// ehrlich: `None` == „nicht in der Kette", nicht „irgendein
    /// Runtime-Problem".
    #[test]
    fn llamafile_lifecycle_none_when_not_in_chain() {
        let r = TextProviderResolver::from_chain(
            &[abrain_item()],
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
        assert!(r.llamafile_lifecycle().is_none());
    }

    /// Steht llamafile in der Kette **und** ist der Feature-Flag aus,
    /// meldet der Stub `Disabled`. Wichtig: der Provider wird trotzdem
    /// instanziiert (siehe Resolver-Baupfad) — die UI sieht also
    /// deterministisch den Refusal-Grund.
    #[test]
    fn llamafile_lifecycle_disabled_when_flag_off() {
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["llamafile_local", "abrain"]);
        assert_eq!(r.llamafile_lifecycle(), Some(LlamafileLifecycle::Disabled));
    }

    /// Enabled aber ohne Pfad → `NotConfigured`. Wieder sichtbar
    /// für die UI, damit Betreiber den fehlenden `SMOLIT_LLAMAFILE_PATH`
    /// direkt im Settings-Readout erkennen, ohne ins Log schauen zu
    /// müssen.
    #[test]
    fn llamafile_lifecycle_not_configured_when_path_missing() {
        let chain = vec![llamafile_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_not_configured(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["llamafile_local"]);
        assert_eq!(
            r.llamafile_lifecycle(),
            Some(LlamafileLifecycle::NotConfigured),
        );
    }

    /// Enabled + Pfad vorhanden (auch wenn das Binary nicht existiert) →
    /// Lifecycle startet auf `Configured`. Der tatsächliche Spawn läuft
    /// erst beim ersten `run()`-Aufruf.
    #[test]
    fn llamafile_lifecycle_configured_when_enabled_and_pathed() {
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured_missing_binary(),
            &local_http_view_disabled(),
        );
        assert_eq!(
            r.llamafile_lifecycle(),
            Some(LlamafileLifecycle::Configured),
        );
    }

    /// `chain_kinds()` ist jetzt Teil des stabilen Produkt-API
    /// (wird im StatusPayload projiziert). Der Test friert die
    /// Reihenfolge ein — zwei Kinds, zwei Einträge in genau der
    /// konfigurierten Sequenz.
    #[test]
    fn chain_kinds_preserves_configured_order() {
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_disabled(),
            &local_http_view_disabled(),
        );
        assert_eq!(r.chain_kinds(), vec!["llamafile_local", "abrain"]);
    }

    // --- Error classification ------------------------------------------

    #[test]
    fn classify_error_buckets() {
        let err = anyhow::anyhow!("ABrain task timed out");
        assert_eq!(TextProviderImpl::classify_error(&err), "timeout");

        let err = anyhow::anyhow!("failed to spawn ABrain command `/no/such/path`");
        assert_eq!(TextProviderImpl::classify_error(&err), "process_missing");

        let err = anyhow::anyhow!("ABrain command `/bin/false` returned no output");
        assert_eq!(TextProviderImpl::classify_error(&err), "empty_response");

        let err = anyhow::anyhow!("ABrain stdout was not valid UTF-8");
        assert_eq!(TextProviderImpl::classify_error(&err), "invalid_response");

        let err = anyhow::anyhow!(
            "ABrain command `/bin/false` failed with status exit status: 1: output"
        );
        assert_eq!(TextProviderImpl::classify_error(&err), "exit_nonzero");

        let err = anyhow::anyhow!("something else entirely");
        assert_eq!(TextProviderImpl::classify_error(&err), "unknown");
    }
}
