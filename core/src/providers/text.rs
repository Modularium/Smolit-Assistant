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
#[derive(Debug)]
pub enum TextProviderImpl {
    Abrain(AbrainCliProvider),
}

impl TextProviderImpl {
    /// Kanonischer Namensstring des Provider-Kinds. Wird für
    /// Statusanzeige und Log-Korrelation verwendet.
    pub fn kind_name(&self) -> &'static str {
        match self {
            Self::Abrain(_) => PROVIDER_NAME_ABRAIN,
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
        // `context()`- und `bail!`-Zeilen von `AbrainCliProvider::run`.
        let chain: Vec<String> = err.chain().map(|e| e.to_string()).collect();
        let joined = chain.join(" | ").to_ascii_lowercase();

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

    /// Baut einen Resolver aus einer Kind-Kette und einer für ABrain
    /// aufgelösten Kommandozeile. Unbekannte Kind-Namen werden
    /// zusammen mit einem `warn!`-Log verworfen — der Core crasht nie
    /// wegen einer kaputten `SMOLIT_TEXT_PROVIDER_CHAIN`.
    ///
    /// Bleibt nach dem Filtern keine einzige bekannte Klasse übrig,
    /// fällt die Kette auf den **Default** (`["abrain"]`) zurück und
    /// loggt das sichtbar. Das ist die konservative Variante aus
    /// §3 der Architektur-Doku („Fallback ist explizit"): wir fallen
    /// niemals in eine Cloud-Klasse zurück, und wir lassen die Kette
    /// auch nicht still leer.
    pub fn from_chain(chain: &[TextProviderChainItem], abrain_cmd: &str) -> Self {
        let mut providers: Vec<TextProviderImpl> = Vec::with_capacity(chain.len());
        let mut skipped_unknown: Vec<String> = Vec::new();
        for item in chain {
            let normalized = item.kind.trim().to_ascii_lowercase();
            match normalized.as_str() {
                PROVIDER_NAME_ABRAIN => {
                    providers.push(TextProviderImpl::Abrain(AbrainCliProvider::new(abrain_cmd)));
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

    // --- Resolver chain building --------------------------------------

    #[test]
    fn from_chain_keeps_known_kinds() {
        let r = TextProviderResolver::from_chain(&[abrain_item()], "/bin/true");
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
        let r = TextProviderResolver::from_chain(&chain, "/bin/true");
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
    }

    #[test]
    fn from_chain_empty_or_all_unknown_falls_back_to_default() {
        let chain = vec![
            TextProviderChainItem { kind: "foo".into() },
            TextProviderChainItem { kind: "bar".into() },
        ];
        let r = TextProviderResolver::from_chain(&chain, "/bin/echo");
        assert_eq!(r.chain_kinds(), vec!["abrain"]);
        assert_eq!(r.status().configured, "abrain");

        let r_empty = TextProviderResolver::from_chain(&[], "/bin/echo");
        assert_eq!(r_empty.chain_kinds(), vec!["abrain"]);
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
