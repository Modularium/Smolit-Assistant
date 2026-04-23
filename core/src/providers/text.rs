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

use std::sync::Mutex;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::process::Command;
use tokio::time::timeout;
use tracing::{info, warn};

/// Kanonischer Namensstring für den ABrain-Provider. Wird an vielen
/// Stellen verglichen; als Konstante gehalten, damit ein Tippfehler
/// beim Config-Parsen sofort beim Kompilieren auffällt.
pub const PROVIDER_NAME_ABRAIN: &str = "abrain";

/// Kanonischer Namensstring für den lokalen llamafile-Provider.
/// **Architektonisch vorbereitet**, Runtime noch nicht implementiert.
/// In der Konfiguration als `llamafile_local` einzusetzen.
pub const PROVIDER_NAME_LLAMAFILE_LOCAL: &str = "llamafile_local";

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
}

impl TextProviderImpl {
    /// Kanonischer Namensstring des Provider-Kinds. Wird für
    /// Statusanzeige und Log-Korrelation verwendet.
    pub fn kind_name(&self) -> &'static str {
        match self {
            Self::Abrain(_) => PROVIDER_NAME_ABRAIN,
            Self::LlamafileLocal(_) => PROVIDER_NAME_LLAMAFILE_LOCAL,
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

        // Llamafile-spezifische Tags zuerst prüfen, damit die
        // allgemeinen Muster („failed to spawn" o. ä.) nicht
        // fälschlicherweise auf Prep-Refusals greifen.
        if joined.contains("llamafile_local") {
            if joined.contains("is disabled") {
                return "disabled";
            }
            if joined.contains("not configured") {
                return "not_configured";
            }
            if joined.contains("runtime is not yet implemented") {
                return "not_implemented";
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
    /// Zulässige Werte (Stand Vorbereitungs-PR): `"on_demand"` /
    /// `"standby"`. Der Wert wird gelesen und im Provider gehalten,
    /// aber noch nicht ausgeführt — die produktive Unterscheidung
    /// greift erst, wenn der Runtime-Pfad implementiert ist.
    pub mode: String,
    /// Sekunden, nach denen der lokale Prozess im `on_demand`-Modus
    /// nach dem letzten Request wieder beendet werden soll. Heute
    /// unausgeführt.
    pub idle_timeout_seconds: u64,
}


/// Lokaler llamafile-Provider — Vorbereitungs-Stub.
///
/// **Heute produziert jeder `run()`-Aufruf einen ehrlichen Fehler.**
/// Die Provider-Instanz hält den Lifecycle-Schatten, die kanonische
/// Config-Sicht und erlaubt dem Resolver, ihn in einer Kette zu führen,
/// ohne dass sich andere Provider-Varianten daran anpassen müssen.
#[derive(Debug)]
pub struct LlamafileLocalProvider {
    config: LlamafileConfigView,
    lifecycle: Mutex<LlamafileLifecycle>,
}

impl LlamafileLocalProvider {
    pub fn new(config: LlamafileConfigView) -> Self {
        let initial = Self::initial_lifecycle(&config);
        Self {
            config,
            lifecycle: Mutex::new(initial),
        }
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

    /// Aktueller Lifecycle-Zustand. Wird heute nie transitioniert —
    /// der Provider hält den bei `new()` gesetzten Initialzustand. Der
    /// spätere Runtime-PR wechselt hier zwischen Starting / Ready /
    /// Busy / Failed / Stopped.
    pub fn lifecycle(&self) -> LlamafileLifecycle {
        *self
            .lifecycle
            .lock()
            .expect("llamafile lifecycle mutex poisoned")
    }

    /// Read-only-Sicht auf die eingegangene Config (für Tests /
    /// Diagnose).
    #[cfg(test)]
    pub fn config(&self) -> &LlamafileConfigView {
        &self.config
    }

    pub async fn run(&self, _input: &str) -> Result<String> {
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
            LlamafileLifecycle::Configured | LlamafileLifecycle::Stopped => {
                // Architektonisch vorbereitet; der produktive Runtime-
                // Pfad (Prozess-Spawn, HTTP-Client, Idle-Timeout)
                // kommt in einem dedizierten Folge-PR. Die Fehler-
                // meldung trägt Mode + Idle-Timeout mit, damit
                // Betreiber beim späteren Runtime-Start sofort sehen,
                // mit welchem Parameter-Satz sie rechnen konnten.
                bail!(
                    "provider llamafile_local runtime is not yet implemented in this build (mode={}, idle_timeout_seconds={}; scheduled for a follow-up PR)",
                    self.config.mode,
                    self.config.idle_timeout_seconds,
                )
            }
            other => {
                // Die Prozess-Zustände Starting/Ready/Busy/Failed sind
                // in diesem PR nicht erreichbar; wenn ein späterer
                // Runtime-PR sie aktiviert, wird dieser Fallback
                // ersetzt. Bis dahin: ehrliche Meldung.
                bail!(
                    "provider llamafile_local is in state {} which is not yet reachable in this build",
                    other.as_str(),
                )
            }
        }
    }
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

    /// Kanonische Kind-Namen der aktuellen Kette. Primär für
    /// Logs/Tests — kein stabiles Produkt-API.
    #[cfg(test)]
    pub fn chain_kinds(&self) -> Vec<&'static str> {
        self.providers.iter().map(|p| p.kind_name()).collect()
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

    fn llamafile_view_disabled() -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: false,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
        }
    }

    fn llamafile_view_not_configured() -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: true,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
        }
    }

    fn llamafile_view_configured() -> LlamafileConfigView {
        LlamafileConfigView {
            enabled: true,
            path: Some("/opt/llamafile/smolit.llamafile".into()),
            mode: "standby".into(),
            idle_timeout_seconds: 120,
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
        let p = LlamafileLocalProvider::new(llamafile_view_configured());
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
    async fn llamafile_run_reports_not_implemented_when_configured() {
        let p = LlamafileLocalProvider::new(llamafile_view_configured());
        let err = p
            .run("hi")
            .await
            .expect_err("configured stub must still refuse in this PR");
        let class = TextProviderImpl::classify_error(&err);
        assert_eq!(class, "not_implemented");
        // Der Fehler trägt Mode + idle_timeout als Diagnose-Hinweis.
        let msg = format!("{err:#}");
        assert!(msg.contains("mode=standby"));
        assert!(msg.contains("idle_timeout_seconds=120"));
    }

    // --- Resolver chain building --------------------------------------

    #[test]
    fn from_chain_keeps_known_kinds() {
        let r = TextProviderResolver::from_chain(
            &[abrain_item()],
            "/bin/true",
            &llamafile_view_disabled(),
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
        );
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
        assert_eq!(r.status().configured, "abrain");

        let r_empty = TextProviderResolver::from_chain(
            &[],
            "/bin/echo",
            &llamafile_view_disabled(),
        );
        assert_eq!(r_empty.chain_kinds(), vec!["abrain"]);
    }

    #[test]
    fn from_chain_instantiates_llamafile_local_when_listed() {
        let chain = vec![abrain_item(), llamafile_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured(),
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
            &llamafile_view_configured(),
        );
        assert_eq!(r.chain_kinds(), vec!["llamafile_local", "abrain"]);
        // Primary ist jetzt llamafile_local (wird aber bei run() als
        // not_implemented refused — nächster Test).
        assert_eq!(r.status().configured, "llamafile_local");
    }

    #[tokio::test]
    async fn run_falls_back_from_llamafile_stub_to_abrain_on_chain_head() {
        // Kette: llamafile_local (Stub refused mit not_implemented) →
        // abrain (/bin/echo, produziert Antwort). Erwartung: Resolver
        // aktiviert den Fallback-Pfad, liefert die echo-Antwort und
        // setzt availability=fallback_active.
        let chain = vec![llamafile_item(), abrain_item()];
        let r = TextProviderResolver::from_chain(
            &chain,
            "/bin/echo",
            &llamafile_view_configured(),
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
            &llamafile_view_configured(),
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
