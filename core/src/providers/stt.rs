//! STT-Provider-Abstraktion (PR 6 der Provider-Fallback-/Settings-Linie).
//!
//! Architekturmäßig parallel zum Text-Provider-Resolver
//! ([`crate::providers::text`]), aber bewusst kleiner: heute existiert
//! **ein einziges** produktiv implementiertes Kind — `command`, das den
//! bisherigen `SMOLIT_STT_CMD`-Pfad 1:1 übernimmt. Die Enum-Dispatch-
//! Struktur ist gewählt, damit spätere Kinds (z. B. `http_local`) als
//! additive Varianten landen können, ohne Plugin-/Dyn-Trait-Geometrie.
//!
//! **Nicht-Ziele dieses Moduls:**
//!
//! - kein Cloud-SDK, keine Cloud-Kinds,
//! - keine Streaming-Audio-Pipeline,
//! - keine neuen Audio-UX-Primitive (keine `listening_started`-Events
//!   u. ä.),
//! - kein Secrets-Transport (Cloud-Kinds kämen mit eigenem Pfad, nicht
//!   über die hier definierten Strukturen).
//!
//! Persistenz des `last_error`-Tags folgt denselben Regeln wie bei Text:
//! kurze, stabile, maschinenlesbare Klasse — keine Rohstrings, keine
//! Nutzerinhalte, keine Secrets.

use std::sync::Mutex;

use anyhow::{Context, Result, bail};
use tokio::process::Command;
use tokio::time::{Duration, timeout};
use tracing::{debug, info, warn};

use crate::audio::types::{AudioFeatureState, split_command};
use crate::config::AudioConfig;

/// Kanonischer Namensstring für den Command-basierten STT-Provider.
/// Entspricht dem heutigen `SMOLIT_STT_CMD`-Verhalten. Konstante
/// gehalten, damit ein Tippfehler beim Config-Parse zur Compile-Zeit
/// auffällt.
pub const PROVIDER_NAME_STT_COMMAND: &str = "command";

/// Kanonischer Namensstring für den whisper.cpp-STT-Provider (PR 27).
/// Externer Command-Adapter — whisper.cpp ist keine Build-Abhängigkeit,
/// kein Modell-Manager, kein Streaming-Pfad. Semantisch eine zweite
/// command-basierte Adapter-Variante, damit der Resolver-Fallback
/// (z. B. Chain `["whisper_cpp", "command"]`) real wird.
pub const PROVIDER_NAME_STT_WHISPER_CPP: &str = "whisper_cpp";

/// Kuratierte Whitelist bekannter STT-Kinds. Seit PR 27: `command` +
/// `whisper_cpp`. Neue Kinds werden hier eingetragen, wenn ihre
/// Runtime wirklich gelandet ist — kein freier Registrierungs-Pfad.
/// Die Liste wird vom Chain-Editor-Validator (`validate_stt_chain`),
/// vom `from_chain`-Resolver und von der Settings-Shell konsumiert.
pub const KNOWN_STT_KINDS: &[&str] =
    &[PROVIDER_NAME_STT_COMMAND, PROVIDER_NAME_STT_WHISPER_CPP];

/// Default-STT-Kette. **Bleibt** `["command"]` — PR 27 fügt
/// `whisper_cpp` nur zur Whitelist hinzu, ändert aber den
/// Compile-Time-Default nicht. Wird vom Chain-Editor-Reset-Pfad und
/// als Startup-Fallback verwendet. Spiegel zu
/// `DEFAULT_STT_PROVIDER_CHAIN` in `crate::config`.
pub const DEFAULT_STT_PROVIDER_CHAIN: &[&str] = &[PROVIDER_NAME_STT_COMMAND];

/// Fehlerklassen für die STT-Chain-Validierung (PR 13). Spiegel zu
/// [`crate::providers::text::TextChainValidationError`]. Bewusst klein
/// und stabil — jede Variante wird direkt in eine kuratierte,
/// deutsche Fehlermeldung im IPC-Schreibpfad gespiegelt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SttChainValidationError {
    /// Chain ist leer. Kein stiller Default-Fallback — die UI
    /// erreicht den Default über den dedizierten Reset-Pfad.
    Empty,
    /// Ein Kind-Name ist nicht in `KNOWN_STT_KINDS` enthalten.
    UnknownKind(String),
    /// Ein Kind erscheint mehrfach in der Kette.
    Duplicate(String),
}

impl std::fmt::Display for SttChainValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => write!(
                f,
                "stt provider chain is empty (use reset to restore default)",
            ),
            Self::UnknownKind(k) => write!(
                f,
                "unknown stt provider kind `{k}` (known: {})",
                KNOWN_STT_KINDS.join(", "),
            ),
            Self::Duplicate(k) => write!(f, "duplicate stt provider kind `{k}` in chain"),
        }
    }
}

impl std::error::Error for SttChainValidationError {}

/// Validiert und normalisiert eine Chain-Eingabe für den STT-
/// Provider (PR 13). Regeln identisch zu `validate_text_chain`:
/// trim + lowercase, leere Tokens als unbekannt ablehnen,
/// Duplikate explizit zurückweisen, leere Eingabe → `Empty`.
pub fn validate_stt_chain(raw: &[String]) -> Result<Vec<String>, SttChainValidationError> {
    if raw.is_empty() {
        return Err(SttChainValidationError::Empty);
    }
    let mut out: Vec<String> = Vec::with_capacity(raw.len());
    for item in raw {
        let normalized = item.trim().to_ascii_lowercase();
        if normalized.is_empty() || !KNOWN_STT_KINDS.iter().any(|k| *k == normalized) {
            return Err(SttChainValidationError::UnknownKind(normalized));
        }
        if out.iter().any(|existing| existing == &normalized) {
            return Err(SttChainValidationError::Duplicate(normalized));
        }
        out.push(normalized);
    }
    Ok(out)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SttProviderError {
    /// Kette leer — kein konfigurierter Provider, kein stiller
    /// Fallback in fremde Klassen.
    EmptyChain,
    /// Jeder Provider der Kette hat den Request abgelehnt. Trägt die
    /// kurze Fehlerklasse des letzten Versuchs.
    AllFailed(String),
}

impl std::fmt::Display for SttProviderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyChain => write!(
                f,
                "no STT provider configured (chain is empty); check SMOLIT_STT_PROVIDER_CHAIN or core config",
            ),
            Self::AllFailed(last) => write!(
                f,
                "all configured STT providers failed; last error: {last}",
            ),
        }
    }
}

impl std::error::Error for SttProviderError {}

/// Ein Kettenelement (kanonischer Kind-Name). Spiegel zu
/// [`crate::providers::text::TextProviderChainItem`].
#[derive(Debug, Clone)]
pub struct SttProviderChainItem {
    pub kind: String,
}

/// Enum-Dispatch über die heutigen STT-Provider. Seit PR 27 zwei
/// Varianten: `Command` (bestehend, `SMOLIT_STT_CMD`) und
/// `WhisperCpp` (env-only, `SMOLIT_STT_WHISPER_CPP_CMD`). Beide sind
/// command-basiert; whisper.cpp ist kein neues Audio-Subsystem,
/// sondern ein zweiter Adapter unter demselben Spawn-Pfad.
#[derive(Debug)]
pub enum SttProviderImpl {
    Command(SttCommandProvider),
    WhisperCpp(SttWhisperCppProvider),
}

impl SttProviderImpl {
    pub fn kind_name(&self) -> &'static str {
        match self {
            Self::Command(_) => PROVIDER_NAME_STT_COMMAND,
            Self::WhisperCpp(_) => PROVIDER_NAME_STT_WHISPER_CPP,
        }
    }

    /// Kurze, stabile Fehlerklasse für `stt_provider_last_error`.
    /// Defensiv — wer mehr Kontext braucht, nutzt das bestehende
    /// `error`-IPC-Envelope.
    pub fn classify_error(err: &anyhow::Error) -> &'static str {
        let chain: Vec<String> = err.chain().map(|e| e.to_string()).collect();
        let joined = chain.join(" | ").to_ascii_lowercase();
        if joined.contains("stt is disabled") {
            return "disabled";
        }
        if joined.contains("stt command is not configured")
            || joined.contains("stt command is empty after parsing")
        {
            return "not_configured";
        }
        if joined.contains("timed out") {
            return "timeout";
        }
        if joined.contains("failed to spawn") || joined.contains("no such file") {
            return "process_missing";
        }
        if joined.contains("not valid utf-8") {
            return "invalid_response";
        }
        if joined.contains("returned no recognized text") {
            return "empty_response";
        }
        if joined.contains("failed with status") {
            return "exit_nonzero";
        }
        "unknown"
    }

    /// Preflight-Check ohne Spawn: ist der Provider grundsätzlich
    /// einsatzfähig? Wird für die nominelle `availability` im Status
    /// und für den `is_available()`-Shortcut in IPC-Vorabprüfungen
    /// (z. B. `voice_once`) benutzt.
    pub fn is_ready(&self) -> bool {
        match self {
            Self::Command(p) => p.is_ready(),
            Self::WhisperCpp(p) => p.is_ready(),
        }
    }

    /// Ob der Provider eine Cloud-Komponente hat. Heute alles `false`.
    pub fn is_cloud(&self) -> bool {
        match self {
            Self::Command(_) => false,
            Self::WhisperCpp(_) => false,
        }
    }

    /// Feature-State (`enabled` + `available`) des konkreten Kinds.
    /// Wird vom Resolver für den legacy `stt_enabled`/`stt_available`-
    /// Feldpaar-Pfad am Primär-Provider abgefragt.
    pub fn feature_state(&self) -> AudioFeatureState {
        match self {
            Self::Command(p) => p.feature_state(),
            Self::WhisperCpp(p) => p.feature_state(),
        }
    }

    pub async fn run(&self) -> Result<String> {
        match self {
            Self::Command(p) => p.run().await,
            Self::WhisperCpp(p) => p.run().await,
        }
    }
}

/// Command-basierter STT-Provider (Ist-Zustand). Spiegelt das bis PR 5
/// in `audio::stt::SttService` lebende Verhalten 1:1 — `enabled` +
/// `SMOLIT_STT_CMD` werden genauso interpretiert, kein semantischer
/// Breaking Change.
#[derive(Debug, Clone)]
pub struct SttCommandProvider {
    enabled: bool,
    command: Option<String>,
    timeout_seconds: u64,
}

impl SttCommandProvider {
    pub fn from_config(config: &AudioConfig) -> Self {
        if config.stt_enabled && config.stt_cmd.is_none() {
            warn!("STT is enabled but SMOLIT_STT_CMD is empty; STT will be unavailable");
        }
        Self {
            enabled: config.stt_enabled,
            command: config.stt_cmd.clone(),
            timeout_seconds: config.stt_timeout_seconds,
        }
    }

    /// Preflight: enabled + Command gesetzt. Kein Dateisystem-Check,
    /// kein Spawn — der Run-Pfad meldet echte Ausführungsfehler.
    pub fn is_ready(&self) -> bool {
        self.enabled && self.command.is_some()
    }

    /// Symmetrisch zu `audio::stt::SttService::state()` — das alte
    /// Feld-Paar `stt_enabled`/`stt_available` wird auch weiterhin
    /// aus diesem Provider abgeleitet.
    pub fn feature_state(&self) -> AudioFeatureState {
        AudioFeatureState::new(self.enabled, self.command.is_some())
    }

    pub async fn run(&self) -> Result<String> {
        run_external_stt_command(self.enabled, self.command.as_deref(), self.timeout_seconds).await
    }
}

/// PR 27 — `whisper_cpp`-STT-Provider. Zweiter command-basierter Adapter
/// unter einer eigenen Env-Variable (`SMOLIT_STT_WHISPER_CPP_CMD`). Die
/// Laufzeit ist identisch zum `command`-Provider — Binary spawnen,
/// stdout als erkannten Text lesen. whisper.cpp selbst ist **keine**
/// Build-Abhängigkeit; der Adapter erwartet, dass der externe
/// Command selbst die Modell-/Audio-Orchestrierung macht und trimmten
/// Text auf stdout ausgibt.
///
/// Identisches `enabled`-Feld zum Command-Provider: die globale Audio-
/// Achse (`SMOLIT_STT_ENABLED`) gilt auch für whisper.cpp. Eine
/// dedizierte Per-Kind-Enabled-Flag gibt es bewusst **nicht** — das
/// hätte eine zweite Schalter-Oberfläche bedeutet; das `command`-
/// Feld selbst entscheidet über „konfiguriert" vs. „nicht
/// konfiguriert".
#[derive(Debug, Clone)]
pub struct SttWhisperCppProvider {
    enabled: bool,
    command: Option<String>,
    timeout_seconds: u64,
}

impl SttWhisperCppProvider {
    pub fn from_config(config: &AudioConfig) -> Self {
        if config.stt_enabled && config.stt_whisper_cpp_cmd.is_none() {
            warn!(
                "STT is enabled and whisper_cpp is in the chain but SMOLIT_STT_WHISPER_CPP_CMD is empty; whisper_cpp will be unavailable",
            );
        }
        Self {
            enabled: config.stt_enabled,
            command: config.stt_whisper_cpp_cmd.clone(),
            timeout_seconds: config.stt_timeout_seconds,
        }
    }

    pub fn is_ready(&self) -> bool {
        self.enabled && self.command.is_some()
    }

    pub fn feature_state(&self) -> AudioFeatureState {
        AudioFeatureState::new(self.enabled, self.command.is_some())
    }

    pub async fn run(&self) -> Result<String> {
        run_external_stt_command(self.enabled, self.command.as_deref(), self.timeout_seconds).await
    }
}

/// Geteilter Spawn-Pfad für command-basierte STT-Provider (PR 27).
/// Beide Kinds (`command`, `whisper_cpp`) teilen die exakt gleiche
/// Bail-Formulierung, damit `SttProviderImpl::classify_error` für
/// beide die gleichen Klassen liefert (`disabled`, `not_configured`,
/// `timeout`, `process_missing`, `invalid_response`, `empty_response`,
/// `exit_nonzero`). Der Adapter trimmt stdout und verweigert leere
/// Ergebnisse — kein Audio-Bytes im Status, keine Nutzerinhalte in
/// Lifecycle-Events.
async fn run_external_stt_command(
    enabled: bool,
    command: Option<&str>,
    timeout_seconds: u64,
) -> Result<String> {
    if !enabled {
        bail!("STT is disabled");
    }
    let cmd = command.context("STT command is not configured")?;
    let (program, args) =
        split_command(cmd).context("STT command is empty after parsing")?;

    debug!(program = %program, "invoking STT command");
    let output = timeout(
        Duration::from_secs(timeout_seconds),
        Command::new(&program).args(&args).output(),
    )
    .await
    .context("STT command timed out")?
    .with_context(|| format!("failed to spawn STT command `{program}`"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let detail = if stderr.is_empty() {
            "process exited without error output".to_string()
        } else {
            stderr
        };
        bail!(
            "STT command `{program}` failed with status {}: {}",
            output.status,
            detail
        );
    }

    let stdout = String::from_utf8(output.stdout).context("STT stdout was not valid UTF-8")?;
    let recognized = stdout.trim().to_string();
    if recognized.is_empty() {
        bail!("STT command `{program}` returned no recognized text");
    }
    Ok(recognized)
}

/// Snapshot des Laufzeit-Status. Wird 1:1 in den StatusPayload
/// gespiegelt (Felder `stt_provider_*`).
#[derive(Debug, Clone)]
pub struct SttProviderRuntimeStatus {
    pub configured: String,
    pub active: String,
    pub availability: String,
    pub last_error: Option<String>,
    pub cloud: bool,
}

impl SttProviderRuntimeStatus {
    fn initial(chain: &[SttProviderImpl]) -> Self {
        let (configured, availability) = match chain.first() {
            Some(first) if first.is_ready() => {
                (first.kind_name().to_string(), "available".to_string())
            }
            Some(first) => (first.kind_name().to_string(), "unavailable".to_string()),
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

pub struct SttProviderResolver {
    providers: Vec<SttProviderImpl>,
    status: Mutex<SttProviderRuntimeStatus>,
}

impl std::fmt::Debug for SttProviderResolver {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SttProviderResolver")
            .field("providers", &self.providers)
            .field("status", &self.status())
            .finish()
    }
}

impl SttProviderResolver {
    pub fn from_providers(providers: Vec<SttProviderImpl>) -> Self {
        let status = SttProviderRuntimeStatus::initial(&providers);
        Self {
            providers,
            status: Mutex::new(status),
        }
    }

    /// Baut den Resolver aus einer Kette von Kind-Namen + der
    /// Audio-Config. Unbekannte Kind-Namen werden sichtbar verworfen
    /// (analog zum Text-Resolver); ohne einen bekannten Kind fällt
    /// die Kette auf den Default `["command"]`, damit der bisherige
    /// Audio-Pfad byte-identisch erhalten bleibt.
    pub fn from_chain(chain: &[SttProviderChainItem], audio: &AudioConfig) -> Self {
        let mut providers: Vec<SttProviderImpl> = Vec::with_capacity(chain.len().max(1));
        let mut skipped: Vec<String> = Vec::new();
        for item in chain {
            let normalized = item.kind.trim().to_ascii_lowercase();
            match normalized.as_str() {
                PROVIDER_NAME_STT_COMMAND => {
                    providers.push(SttProviderImpl::Command(SttCommandProvider::from_config(
                        audio,
                    )));
                }
                PROVIDER_NAME_STT_WHISPER_CPP => {
                    providers.push(SttProviderImpl::WhisperCpp(
                        SttWhisperCppProvider::from_config(audio),
                    ));
                }
                other => skipped.push(other.to_string()),
            }
        }
        if !skipped.is_empty() {
            warn!(
                skipped = ?skipped,
                "ignoring unknown STT provider kinds in chain (not yet implemented in this build)",
            );
        }
        if providers.is_empty() {
            warn!(
                "no known STT providers in configured chain — falling back to default chain [command]",
            );
            providers.push(SttProviderImpl::Command(SttCommandProvider::from_config(
                audio,
            )));
        }
        let resolver = Self::from_providers(providers);
        info!(
            kinds = ?resolver.chain_kinds(),
            ready = resolver.is_available(),
            "STT provider resolver built",
        );
        resolver
    }

    pub fn status(&self) -> SttProviderRuntimeStatus {
        self.status
            .lock()
            .expect("stt provider status mutex poisoned")
            .clone()
    }

    pub fn chain_kinds(&self) -> Vec<&'static str> {
        self.providers.iter().map(|p| p.kind_name()).collect()
    }

    /// Primärer Readiness-Shortcut — das reicht für die IPC-Vorabprüfung
    /// (`voice_once` bricht sonst ehrlich mit "STT is not available" ab).
    pub fn is_available(&self) -> bool {
        self.providers.first().map(|p| p.is_ready()).unwrap_or(false)
    }

    /// Feature-State für das bestehende `stt_enabled`/`stt_available`-
    /// Feldpaar im StatusPayload. Liest immer vom Primärprovider —
    /// Chain-Glieder ab Position 1 sind Fallback und bestimmen die
    /// „Kernsichtbarkeit" der Audio-Achse nicht. Seit PR 27
    /// generalisiert auf alle `SttProviderImpl`-Varianten.
    pub fn feature_state(&self) -> AudioFeatureState {
        match self.providers.first() {
            Some(p) => p.feature_state(),
            None => AudioFeatureState::new(false, false),
        }
    }

    /// Hauptdispatch. Probiert jeden Provider in Reihenfolge. Semantik
    /// identisch zum Text-Resolver: erster Erfolg gewinnt, Status wird
    /// deterministisch aktualisiert.
    pub async fn run(&self) -> Result<String, SttProviderError> {
        if self.providers.is_empty() {
            let mut s = self.status.lock().expect("stt status mutex poisoned");
            s.configured = "none".to_string();
            s.active = String::new();
            s.availability = "unavailable".to_string();
            s.last_error = Some("empty_chain".to_string());
            s.cloud = false;
            return Err(SttProviderError::EmptyChain);
        }

        let primary = self.providers[0].kind_name().to_string();
        let mut last_err_class: Option<String> = None;
        for (index, provider) in self.providers.iter().enumerate() {
            match provider.run().await {
                Ok(text) => {
                    let kind = provider.kind_name().to_string();
                    let availability = if index == 0 {
                        "available".to_string()
                    } else {
                        "fallback_active".to_string()
                    };
                    let mut s = self.status.lock().expect("stt status mutex poisoned");
                    s.configured = primary;
                    s.active = kind.clone();
                    s.availability = availability;
                    s.last_error = None;
                    s.cloud = provider.is_cloud();
                    if index > 0 {
                        info!(
                            primary = %s.configured,
                            active = %kind,
                            "STT provider fallback active — primary unavailable, secondary produced result",
                        );
                    }
                    return Ok(text);
                }
                Err(err) => {
                    let class = SttProviderImpl::classify_error(&err);
                    warn!(
                        provider = %provider.kind_name(),
                        error_class = %class,
                        error = %err,
                        "STT provider failed — trying next in chain",
                    );
                    last_err_class = Some(class.to_string());
                }
            }
        }
        let last = last_err_class.unwrap_or_else(|| "unknown".to_string());
        {
            let mut s = self.status.lock().expect("stt status mutex poisoned");
            s.configured = primary;
            s.active = String::new();
            s.availability = "unavailable".to_string();
            s.last_error = Some(last.clone());
            s.cloud = false;
        }
        Err(SttProviderError::AllFailed(last))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn audio_with(stt_enabled: bool, stt_cmd: Option<&str>) -> AudioConfig {
        audio_with_both(stt_enabled, stt_cmd, None)
    }

    fn audio_with_both(
        stt_enabled: bool,
        stt_cmd: Option<&str>,
        stt_whisper_cpp_cmd: Option<&str>,
    ) -> AudioConfig {
        AudioConfig {
            tts_enabled: true,
            tts_cmd: None,
            tts_timeout_seconds: 5,
            stt_enabled,
            stt_cmd: stt_cmd.map(|s| s.to_string()),
            stt_whisper_cpp_cmd: stt_whisper_cpp_cmd.map(|s| s.to_string()),
            stt_timeout_seconds: 5,
            auto_speak: false,
            stt_provider_chain: vec!["command".into()],
            tts_provider_chain: vec!["command".into()],
        }
    }

    fn command_item() -> SttProviderChainItem {
        SttProviderChainItem {
            kind: PROVIDER_NAME_STT_COMMAND.to_string(),
        }
    }

    fn whisper_cpp_item() -> SttProviderChainItem {
        SttProviderChainItem {
            kind: PROVIDER_NAME_STT_WHISPER_CPP.to_string(),
        }
    }

    #[test]
    fn from_chain_default_instantiates_command_provider() {
        let r = SttProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, Some("/bin/echo hello")),
        );
        assert_eq!(r.chain_kinds(), vec!["command"]);
        assert_eq!(r.status().configured, "command");
        assert!(r.is_available());
    }

    #[test]
    fn from_chain_unknown_kind_falls_back_to_default() {
        let r = SttProviderResolver::from_chain(
            &[SttProviderChainItem {
                kind: "cloud:unknown".into(),
            }],
            &audio_with(true, Some("/bin/echo hi")),
        );
        // Fall-back auf die Default-Kette mit Command-Provider.
        assert_eq!(r.chain_kinds(), vec!["command"]);
        assert_eq!(r.status().configured, "command");
    }

    #[test]
    fn initial_status_is_unavailable_when_command_missing() {
        let r = SttProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, None),
        );
        let st = r.status();
        assert_eq!(st.configured, "command");
        assert_eq!(st.availability, "unavailable");
        assert!(!r.is_available());
        // Kein last_error vor dem ersten Run — das Feld ist dem
        // Fehlerpfad vorbehalten, um die Unterscheidung „nicht
        // konfiguriert" vs. „nach Versuch gescheitert" sichtbar zu
        // halten.
        assert!(st.last_error.is_none());
    }

    #[test]
    fn initial_status_is_unavailable_when_disabled() {
        let r = SttProviderResolver::from_chain(
            &[command_item()],
            &audio_with(false, Some("/bin/echo hi")),
        );
        let st = r.status();
        assert_eq!(st.availability, "unavailable");
        assert!(!r.is_available());
    }

    #[tokio::test]
    async fn run_success_updates_status_to_available() {
        let r = SttProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, Some("/bin/echo hi there")),
        );
        let out = r.run().await.unwrap();
        assert_eq!(out, "hi there");
        let st = r.status();
        assert_eq!(st.active, "command");
        assert_eq!(st.availability, "available");
        assert!(st.last_error.is_none());
        assert!(!st.cloud);
    }

    #[tokio::test]
    async fn run_without_command_reports_not_configured() {
        let r = SttProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, None),
        );
        let err = r.run().await.unwrap_err();
        match err {
            SttProviderError::AllFailed(class) => assert_eq!(class, "not_configured"),
            other => panic!("unexpected: {other:?}"),
        }
        let st = r.status();
        assert_eq!(st.availability, "unavailable");
        assert_eq!(st.last_error.as_deref(), Some("not_configured"));
    }

    #[tokio::test]
    async fn run_empty_stdout_reports_empty_response() {
        let r = SttProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, Some("/bin/true")),
        );
        let err = r.run().await.unwrap_err();
        match err {
            SttProviderError::AllFailed(class) => assert_eq!(class, "empty_response"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn classify_error_buckets_cover_known_classes() {
        let err = anyhow::anyhow!("STT command timed out");
        assert_eq!(SttProviderImpl::classify_error(&err), "timeout");
        let err = anyhow::anyhow!("failed to spawn STT command `/no/such`");
        assert_eq!(SttProviderImpl::classify_error(&err), "process_missing");
        let err = anyhow::anyhow!("STT stdout was not valid UTF-8");
        assert_eq!(SttProviderImpl::classify_error(&err), "invalid_response");
        let err = anyhow::anyhow!("STT command `/bin/true` returned no recognized text");
        assert_eq!(SttProviderImpl::classify_error(&err), "empty_response");
    }

    // --- Chain-Validator (PR 13) ---

    #[test]
    fn validate_stt_chain_accepts_command_kind() {
        let normalized = validate_stt_chain(&["command".to_string()]).expect("valid chain");
        assert_eq!(normalized, vec!["command"]);
    }

    #[test]
    fn validate_stt_chain_normalizes_case_and_whitespace() {
        let normalized =
            validate_stt_chain(&["  COMMAND ".to_string()]).expect("valid chain");
        assert_eq!(normalized, vec!["command"]);
    }

    #[test]
    fn validate_stt_chain_rejects_empty() {
        let err = validate_stt_chain(&[]).unwrap_err();
        assert_eq!(err, SttChainValidationError::Empty);
    }

    #[test]
    fn validate_stt_chain_rejects_unknown_kind() {
        let err = validate_stt_chain(&["command".into(), "cloud_whisper".into()]).unwrap_err();
        match err {
            SttChainValidationError::UnknownKind(k) => assert_eq!(k, "cloud_whisper"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn validate_stt_chain_rejects_duplicates() {
        let err = validate_stt_chain(&["command".into(), "command".into()]).unwrap_err();
        match err {
            SttChainValidationError::Duplicate(k) => assert_eq!(k, "command"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn known_stt_kinds_stable_set() {
        // PR 27 lockt die Whitelist auf `[command, whisper_cpp]`.
        // Default bleibt bewusst `[command]` (siehe PR-27-Review).
        assert_eq!(KNOWN_STT_KINDS, &["command", "whisper_cpp"]);
        assert_eq!(DEFAULT_STT_PROVIDER_CHAIN, &["command"]);
    }

    // --- PR 27: whisper_cpp-Kind -------------------------------------------

    #[test]
    fn validate_stt_chain_accepts_whisper_cpp_kind() {
        let normalized = validate_stt_chain(&["whisper_cpp".to_string()]).expect("valid chain");
        assert_eq!(normalized, vec!["whisper_cpp"]);
    }

    #[test]
    fn validate_stt_chain_accepts_whisper_cpp_then_command_fallback() {
        let normalized = validate_stt_chain(&[
            "whisper_cpp".to_string(),
            "command".to_string(),
        ])
        .expect("valid chain");
        assert_eq!(normalized, vec!["whisper_cpp", "command"]);
    }

    #[test]
    fn validate_stt_chain_rejects_duplicate_whisper_cpp() {
        let err = validate_stt_chain(&["whisper_cpp".into(), "whisper_cpp".into()]).unwrap_err();
        match err {
            SttChainValidationError::Duplicate(k) => assert_eq!(k, "whisper_cpp"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn from_chain_with_whisper_cpp_instantiates_whisper_cpp_provider() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item()],
            &audio_with_both(true, None, Some("/bin/echo hi")),
        );
        assert_eq!(r.chain_kinds(), vec!["whisper_cpp"]);
        assert_eq!(r.status().configured, "whisper_cpp");
        assert!(r.is_available());
        assert!(!r.status().cloud);
    }

    #[test]
    fn whisper_cpp_primary_without_command_reports_unavailable() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item()],
            &audio_with_both(true, None, None),
        );
        let st = r.status();
        assert_eq!(st.configured, "whisper_cpp");
        assert_eq!(st.availability, "unavailable");
        assert!(!r.is_available());
    }

    #[tokio::test]
    async fn whisper_cpp_run_without_command_reports_not_configured() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item()],
            &audio_with_both(true, None, None),
        );
        let err = r.run().await.unwrap_err();
        match err {
            SttProviderError::AllFailed(class) => assert_eq!(class, "not_configured"),
            other => panic!("unexpected: {other:?}"),
        }
        let st = r.status();
        assert_eq!(st.last_error.as_deref(), Some("not_configured"));
    }

    #[tokio::test]
    async fn whisper_cpp_run_success_sets_active_to_whisper_cpp() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item()],
            &audio_with_both(true, None, Some("/bin/echo transcribed")),
        );
        let out = r.run().await.unwrap();
        assert_eq!(out, "transcribed");
        let st = r.status();
        assert_eq!(st.configured, "whisper_cpp");
        assert_eq!(st.active, "whisper_cpp");
        assert_eq!(st.availability, "available");
        assert!(st.last_error.is_none());
        assert!(!st.cloud);
    }

    #[tokio::test]
    async fn whisper_cpp_run_empty_stdout_reports_empty_response() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item()],
            &audio_with_both(true, None, Some("/bin/true")),
        );
        let err = r.run().await.unwrap_err();
        match err {
            SttProviderError::AllFailed(class) => assert_eq!(class, "empty_response"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[tokio::test]
    async fn whisper_cpp_run_missing_binary_reports_process_missing() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item()],
            &audio_with_both(true, None, Some("/no/such/whisper-cpp-binary")),
        );
        let err = r.run().await.unwrap_err();
        match err {
            SttProviderError::AllFailed(class) => assert_eq!(class, "process_missing"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[tokio::test]
    async fn fallback_chain_whisper_cpp_then_command_uses_command_when_whisper_cpp_missing() {
        // Primary `whisper_cpp` is unset → error; secondary `command`
        // has a valid echo and must produce the result. `active`
        // mirrors the producing kind; `availability` becomes
        // `fallback_active`.
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item(), command_item()],
            &audio_with_both(true, Some("/bin/echo fallback-ok"), None),
        );
        let out = r.run().await.unwrap();
        assert_eq!(out, "fallback-ok");
        let st = r.status();
        assert_eq!(st.configured, "whisper_cpp");
        assert_eq!(st.active, "command");
        assert_eq!(st.availability, "fallback_active");
        assert!(st.last_error.is_none());
    }

    #[tokio::test]
    async fn fallback_chain_whisper_cpp_wins_when_configured() {
        let r = SttProviderResolver::from_chain(
            &[whisper_cpp_item(), command_item()],
            &audio_with_both(true, Some("/bin/echo command"), Some("/bin/echo whisper")),
        );
        let out = r.run().await.unwrap();
        assert_eq!(out, "whisper");
        let st = r.status();
        assert_eq!(st.active, "whisper_cpp");
        assert_eq!(st.availability, "available");
    }
}
