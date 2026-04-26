use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::Parser;
use serde::{Deserialize, Serialize};

const DEFAULT_ABRAIN_CMD: &str = "abrain";
const DEFAULT_LOG_LEVEL: &str = "info";
const DEFAULT_STT_TIMEOUT_SECONDS: u64 = 20;
const DEFAULT_TTS_TIMEOUT_SECONDS: u64 = 20;
const DEFAULT_IPC_BIND: &str = "127.0.0.1:8787";
const DEFAULT_INTERACTION_BACKEND: &str = "command";
/// Policy v0 — Interaction default gates (PR 25).
///
/// These constants lock the safety baseline for real interaction
/// actions. Any change here is a policy change and must flip the
/// accompanying `policy_v0_defaults_are_locked` test.
///
/// Rationale:
/// * `allow_open_application = true` — the only real interaction
///   kind we ship; still gated by approval.
/// * `allow_focus_window = false` — double opt-in: env flag **and**
///   X11 template must be set (see
///   `docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`).
/// * `allow_type_text` / `allow_shortcuts = false` — no backend
///   exists; flipping these to `true` would not *enable* the
///   actions, but the signal of the default is what's locked.
/// * `require_confirmation = true` — real interaction actions that
///   carry `requires_confirmation=true` must go through the
///   approval pipeline before any backend is invoked.
const DEFAULT_INTERACTION_ALLOW_OPEN_APP: bool = true;
const DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW: bool = false;
const DEFAULT_INTERACTION_ALLOW_TYPE_TEXT: bool = false;
const DEFAULT_INTERACTION_ALLOW_SHORTCUTS: bool = false;
const DEFAULT_INTERACTION_REQUIRE_CONFIRMATION: bool = true;
const DEFAULT_APPROVAL_TIMEOUT_SECONDS: u64 = 20;
/// Konservativer Default der Text-Provider-Kette. ABrain bleibt
/// Primary — explizit in der Architektur-Doku §3 / §5 festgelegt.
const DEFAULT_TEXT_PROVIDER_CHAIN: &[&str] = &["abrain"];
/// Default-Kette für STT und TTS (PR 6). Beide Achsen starten mit
/// dem Command-Kind — entspricht dem bisherigen Verhalten von
/// `SMOLIT_STT_CMD`/`SMOLIT_TTS_CMD`. Keine stille Aufweichung:
/// unbekannte Env-Kinds werden im Resolver verworfen, die Kette
/// fällt dann wieder auf diesen Default.
const DEFAULT_STT_PROVIDER_CHAIN: &[&str] = &["command"];
const DEFAULT_TTS_PROVIDER_CHAIN: &[&str] = &["command"];
/// Default-Mode des lokalen llamafile-Providers. Die Runtime-Stufe
/// (PR 2b) implementiert heute `on_demand` vollständig; `standby` ist
/// reserviert für einen späteren PR und wird aktuell wie `on_demand`
/// behandelt (siehe `providers/text.rs`).
const DEFAULT_LLAMAFILE_MODE: &str = "on_demand";
const DEFAULT_LLAMAFILE_IDLE_TIMEOUT_SECONDS: u64 = 300;
/// TCP-Port des lokalen llamafile-Servers. Default ist bewusst
/// abweichend vom IPC-Port (8787), damit die beiden Dienste sich nicht
/// in die Quere kommen. llamafile lauscht immer ausschließlich auf
/// `127.0.0.1` (Loopback); der Host ist nicht konfigurierbar.
const DEFAULT_LLAMAFILE_PORT: u16 = 8788;
/// Maximale Wartezeit zwischen „Prozess gespawnt" und „`GET /health`
/// liefert 200 OK". Wird überschritten → Runtime-Lifecycle `Failed`.
const DEFAULT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS: u64 = 30;
/// Maximale Wartezeit pro Completion-Request gegen den lokalen
/// llamafile-Server. Dient dazu, hängende Requests sichtbar mit
/// `timeout`-Klasse zu terminieren und den Resolver-Fallback nicht
/// blockieren zu lassen.
const DEFAULT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS: u64 = 60;
/// Whitelist zulässiger Mode-Strings. Eingaben außerhalb dieser Menge
/// werden beim Parsing verworfen und fallen auf den Default zurück;
/// das hält das Vokabular klein und vermeidet stille Freiform-Werte.
const ALLOWED_LLAMAFILE_MODES: &[&str] = &["on_demand", "standby"];
/// Default-Timeout für einzelne `local_http`-Completion-Requests (PR 8).
const DEFAULT_LOCAL_HTTP_REQUEST_TIMEOUT_SECONDS: u64 = 60;
/// Default-Feldname im JSON-Request-Body, unter dem der Prompt an den
/// lokalen HTTP-Server geht. Bewusst gleich zum llama.cpp-Server-
/// Vokabular, damit ein unkonfigurierter `local_http` gegen einen
/// llama.cpp-kompatiblen Dienst ohne Zusatz-Mapping funktioniert.
const DEFAULT_LOCAL_HTTP_PROMPT_FIELD: &str = "prompt";
/// Default-Feldname im JSON-Response, aus dem der Antworttext gelesen
/// wird. Ebenfalls llama.cpp-kompatibel.
const DEFAULT_LOCAL_HTTP_RESPONSE_FIELD: &str = "content";
/// Default-Timeout für einzelne `cloud_http`-Completion-Requests (PR 10).
/// Bewusst größer als bei lokalen Providern — Remote-Endpoints haben
/// üblicherweise mehr Netzwerk-Latenz und serverseitige Warteschlangen.
const DEFAULT_CLOUD_HTTP_REQUEST_TIMEOUT_SECONDS: u64 = 90;
/// Default-Feldnamen für `cloud_http`. Llama.cpp-kompatibel, damit der
/// Provider ohne Zusatz-Mapping gegen einen authentifizierten
/// llama.cpp-Server (z. B. über LAN-Reverse-Proxy) arbeitet.
const DEFAULT_CLOUD_HTTP_PROMPT_FIELD: &str = "prompt";
const DEFAULT_CLOUD_HTTP_RESPONSE_FIELD: &str = "content";
/// Default-Header-Name für den API-Key. Bewusst auf `Authorization`
/// festgenagelt — der Provider setzt `Authorization: Bearer <key>`.
/// Ein konfigurierbarer Header-Name ist erst sinnvoll, wenn wir einen
/// zweiten Cloud-Provider haben, der nicht Bearer nutzt.
const DEFAULT_CLOUD_HTTP_AUTH_HEADER: &str = "Authorization";

#[derive(Debug, Parser)]
#[command(name = "smolit", about = "Smolit Assistant core daemon")]
struct CliArgs {
    #[arg(long)]
    abrain_cmd: Option<String>,

    #[arg(long)]
    log_level: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioConfig {
    pub tts_enabled: bool,
    pub tts_cmd: Option<String>,
    pub tts_timeout_seconds: u64,
    pub stt_enabled: bool,
    pub stt_cmd: Option<String>,
    /// Command template for the `whisper_cpp` STT provider kind (PR 27).
    /// Env-only (`SMOLIT_STT_WHISPER_CPP_CMD`); not editable via
    /// Settings-Shell runtime. `None` means the kind is not configured
    /// and the resolver reports `not_configured` / `unavailable` when
    /// it is primary. Whisper.cpp is not a build dependency — this is
    /// an external-process adapter just like the `command` kind.
    #[serde(default)]
    pub stt_whisper_cpp_cmd: Option<String>,
    /// Command template for the `piper` TTS provider kind (PR 34).
    /// Env-only (`SMOLIT_TTS_PIPER_CMD`); not editable via
    /// Settings-Shell runtime. `None` means the kind is not configured
    /// and the resolver reports `not_configured` / `unavailable` when
    /// it is primary. Piper is not a build dependency — this is an
    /// external-process adapter just like the TTS `command` kind and
    /// uses the same stdin-text contract.
    #[serde(default)]
    pub tts_piper_cmd: Option<String>,
    pub stt_timeout_seconds: u64,
    pub auto_speak: bool,
    /// Geordnete STT-Provider-Kette (PR 6). Env-Override
    /// `SMOLIT_STT_PROVIDER_CHAIN` (komma-separierte Kind-Namen).
    /// Heute nur `command` implementiert; unbekannte Kinds werden im
    /// Resolver sichtbar verworfen. Default `["command"]`.
    #[serde(default = "default_stt_provider_chain")]
    pub stt_provider_chain: Vec<String>,
    /// Geordnete TTS-Provider-Kette (PR 6). Env-Override
    /// `SMOLIT_TTS_PROVIDER_CHAIN`. Gleiche Semantik wie
    /// `stt_provider_chain`.
    #[serde(default = "default_tts_provider_chain")]
    pub tts_provider_chain: Vec<String>,
}

fn default_stt_provider_chain() -> Vec<String> {
    DEFAULT_STT_PROVIDER_CHAIN
        .iter()
        .map(|s| (*s).to_string())
        .collect()
}

fn default_tts_provider_chain() -> Vec<String> {
    DEFAULT_TTS_PROVIDER_CHAIN
        .iter()
        .map(|s| (*s).to_string())
        .collect()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcConfig {
    pub enabled: bool,
    pub bind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteractionConfig {
    pub enabled: bool,
    pub backend: String,
    pub allow_open_application: bool,
    pub allow_focus_window: bool,
    pub allow_type_text: bool,
    pub allow_shortcuts: bool,
    pub require_confirmation: bool,
    /// Command template used by the `command` backend to spawn an
    /// application launcher. `{name}` is substituted at call time.
    /// Kept optional so absence is an honest "unavailable" signal
    /// rather than a silent default like `xdg-open`.
    pub open_app_cmd_template: Option<String>,
    /// Command template used by the `command` backend to focus a
    /// window. `{name}` is the preferred display string (title or
    /// app); `{title}` and `{app}` are each substituted or empty.
    /// Kept optional so absence is an honest "unsupported" signal
    /// (e.g. on Wayland there is no generic focus primitive).
    pub focus_window_cmd_template: Option<String>,
}

/// Accessibility-related runtime config. Today only the read-only AT-SPI
/// RPC FA-1 spike toggle (ADR-0002 / PR 53). Default-off; even when
/// `rpc_enabled=true` the actual RPC path additionally requires the
/// `accessibility_rpc` Cargo feature **and** a wired registry client —
/// without all three the path returns `Unavailable` with an honest reason.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AccessibilityConfig {
    pub rpc_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalConfig {
    /// How long the core waits for an `approval_response` before
    /// treating the approval as timed out and cancelling the action.
    pub timeout_seconds: u64,
}

/// Text/Reasoning-Provider-Konfiguration (PR 2 der Provider-Fallback-
/// Linie, siehe `docs/provider_fallback_and_settings_architecture.md`).
///
/// Bewusst klein gehalten:
///   * Eine geordnete **Kette** von Provider-Kind-Namen. ABrain ist
///     Default und erster Eintrag, solange nichts anderes konfiguriert
///     ist.
///   * Pro-Kind-Config wird **nur dort** ergänzt, wo ein Provider
///     echte Runtime-Entscheidungen braucht (heute: llamafile_local,
///     architektonisch vorbereitet). ABrain bleibt ohne eigene
///     Sub-Struktur, weil er nur das oberste `abrain_cmd`-Feld nutzt.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextProviderConfig {
    /// Reihenfolge der probierten Provider. Unbekannte Namen werden
    /// beim Resolver-Bau sichtbar verworfen; bleibt die Liste leer,
    /// fällt der Resolver auf `["abrain"]` zurück (siehe
    /// [`crate::providers::text::TextProviderResolver::from_chain`]).
    pub chain: Vec<String>,
    /// Llamafile-spezifische Einstellungen. Werden nur wirksam, wenn
    /// `llamafile_local` in `chain` enthalten ist. Siehe
    /// [`LlamafileConfig`] für die Semantik.
    pub llamafile: LlamafileConfig,
    /// Einstellungen für den lokalen HTTP-Provider (PR 8, additiv).
    /// Werden nur wirksam, wenn `local_http` in `chain` enthalten ist.
    /// Siehe [`LocalHttpConfig`] für die Semantik.
    #[serde(default)]
    pub local_http: LocalHttpConfig,
    /// Einstellungen für den ersten Cloud-/Remote-Text-Provider
    /// `cloud_http` (PR 10, additiv). Werden nur wirksam, wenn
    /// `cloud_http` in `chain` enthalten ist. Siehe
    /// [`CloudHttpConfig`] für die Semantik. **Enthält keinen
    /// API-Key** — der Key lebt ausschließlich im dedizierten
    /// [`crate::secrets_store`] (siehe Doku §11).
    #[serde(default)]
    pub cloud_http: CloudHttpConfig,
}

/// Einstellungen für den lokalen **llamafile**-Provider
/// (architektonisch vorbereitet; Runtime folgt, siehe
/// `docs/provider_fallback_and_settings_architecture.md` §4.1 und den
/// Llamafile-Vorbereitungs-PR).
///
/// ABrain bleibt Default-Reasoning-Provider. `LlamafileConfig::default()`
/// entspricht einem **abgeschalteten** llamafile: ohne gesetzte
/// Env-Variablen bleibt das Feature inert und verändert kein Verhalten.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlamafileConfig {
    /// Harter Master-Schalter: ohne `SMOLIT_LLAMAFILE_ENABLED=1` bleibt
    /// der llamafile-Stub auf `Disabled` — unabhängig davon, ob er in
    /// der Chain steht. Das hält den Produktpfad konservativ und
    /// macht ein unbeabsichtigtes Einschalten unmöglich.
    pub enabled: bool,
    /// Pfad zum llamafile-Binary bzw. Modell-Wrapper. Der Runtime-Pfad
    /// (PR 2b) ruft dieses Binary mit
    /// `--server --host 127.0.0.1 --port <port>` auf. Ohne Pfad bleibt
    /// der Provider im Lifecycle `NotConfigured`.
    pub path: Option<String>,
    /// Modus: `"on_demand"` (Default — Prozess beim ersten Request
    /// starten, nach Idle-Timeout wieder beenden) oder `"standby"`
    /// (Prozess dauerhaft halten, solange `enabled`). Unbekannte
    /// Eingaben fallen auf den Default zurück. `standby` wird in
    /// PR 2b bewusst wie `on_demand` behandelt (siehe
    /// `docs/provider_fallback_and_settings_architecture.md` §4.1a).
    pub mode: String,
    /// Idle-Timeout in Sekunden für den `on_demand`-Modus. Greift in
    /// PR 2b real: nach dieser Zeit ohne neuen Request beendet der
    /// Runtime-Watchdog den lokalen Prozess und setzt den Lifecycle
    /// auf `Stopped`.
    pub idle_timeout_seconds: u64,
    /// TCP-Port, auf dem der lokale llamafile-Server lauscht. Default
    /// `8788`. Loopback-only (`127.0.0.1`) — der Host ist nicht
    /// konfigurierbar, damit die Oberfläche nicht versehentlich nach
    /// außen gebunden wird.
    pub port: u16,
    /// Zeitbudget für das Warten auf `GET /health`-Erreichbarkeit nach
    /// dem Prozess-Spawn. Überschreitung → Lifecycle `Failed`.
    pub startup_timeout_seconds: u64,
    /// Zeitbudget pro Completion-Request. Überschreitung → kurze
    /// Fehlerklasse `timeout` im `text_provider_last_error`.
    pub request_timeout_seconds: u64,
}

impl Default for LlamafileConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            path: None,
            mode: DEFAULT_LLAMAFILE_MODE.to_string(),
            idle_timeout_seconds: DEFAULT_LLAMAFILE_IDLE_TIMEOUT_SECONDS,
            port: DEFAULT_LLAMAFILE_PORT,
            startup_timeout_seconds: DEFAULT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS,
            request_timeout_seconds: DEFAULT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS,
        }
    }
}

/// Einstellungen für den lokalen HTTP-Provider `local_http` (PR 8).
///
/// Bewusst schmal: ein konfigurierbarer Endpoint, ein Request-Timeout
/// und zwei Feldnamen, damit der Provider mit einem lokalen
/// llama.cpp-kompatiblen Server **ohne** zusätzliche Konfiguration
/// redet, aber auch einen abweichenden Dienst ansprechen kann, der
/// beim Prompt-/Response-Feldnamen nicht 1:1 die llama.cpp-Namen
/// nutzt.
///
/// Nicht-Ziele dieser Struktur:
///
/// - **kein Cloud-SDK** — der Provider spricht HTTP/1.1 direkt über
///   den bestehenden [`crate::providers::text::http_request`]-Helfer,
///   identisch zum llamafile-Runtime-Pfad.
/// - **keine API-Keys / keine Secrets** — dieser PR transportiert
///   keine Credentials.
/// - **keine generische OpenAI-Welt** — kein `messages`-Array, kein
///   Tool-/Schema-Mode, kein Streaming. Der Provider postet genau ein
///   JSON-Objekt mit dem Prompt-Feld und liest genau ein Text-Feld
///   aus der Antwort.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalHttpConfig {
    /// Master-Schalter, analog zu `llamafile_local.enabled`. Ohne
    /// `SMOLIT_LOCAL_HTTP_ENABLED=1` bleibt der Provider inert, auch
    /// wenn er in der Chain steht.
    pub enabled: bool,
    /// Ziel-URL, z. B. `http://127.0.0.1:8080/completion`. Muss mit
    /// `http://` beginnen — `https://` wird vom Provider bewusst
    /// abgelehnt, weil PR 8 **loopback-first** gedacht ist und keine
    /// TLS-/Cert-/Trust-Infrastruktur mitbringt.
    pub endpoint: Option<String>,
    /// Zeitbudget pro Completion-Request. Überschreitung →
    /// `timeout`-Klasse in `text_provider_last_error`.
    pub request_timeout_seconds: u64,
    /// JSON-Feldname für den Prompt im Request-Body. Default
    /// `"prompt"`. Ein leerer Override fällt still auf den Default
    /// zurück.
    pub prompt_field: String,
    /// JSON-Feldname für den Antworttext im Response-Body. Default
    /// `"content"`. Auch hier fällt ein leerer Override still zurück.
    pub response_field: String,
}

impl Default for LocalHttpConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            endpoint: None,
            request_timeout_seconds: DEFAULT_LOCAL_HTTP_REQUEST_TIMEOUT_SECONDS,
            prompt_field: DEFAULT_LOCAL_HTTP_PROMPT_FIELD.to_string(),
            response_field: DEFAULT_LOCAL_HTTP_RESPONSE_FIELD.to_string(),
        }
    }
}

/// Einstellungen für den ersten Cloud-/Remote-Text-Provider
/// `cloud_http` (PR 10).
///
/// Bewusst klein: ein authentifizierter HTTP-Endpoint, ein optionaler
/// Modell-Name, ein Request-Timeout, zwei Feldnamen. **Enthält keinen
/// API-Key** — der wohnt ausschließlich im
/// [`crate::secrets_store`]. `CloudHttpConfig` ist damit operational-
/// sicher: das Struct darf in `Serialize`-Pfade fallen (JSON-Dumps,
/// Debug), ohne dass dabei Secrets durchschlagen können.
///
/// **MVP-Beschränkungen (PR 10):**
///
///   * **Plaintext HTTP nur.** `https://` wird bewusst **abgelehnt**,
///     weil PR 10 keine TLS-/Trust-Infrastruktur mitbringt (siehe
///     Architektur-Doku §4.1d). Ein Betreiber stellt einen
///     vertrauenswürdigen Reverse-Proxy vor den Endpoint, der TLS
///     terminiert.
///   * **Ein Auth-Pfad.** `Authorization: Bearer <key>` aus dem
///     Secrets-Store; keine Basic-Auth, keine Header-Maps.
///   * **Kein Streaming, kein Tool-Calling, kein `messages`-Array.**
///     POST JSON mit einem Prompt-Feld, Antwort enthält ein
///     Text-Feld.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloudHttpConfig {
    /// Master-Schalter. Ohne `SMOLIT_CLOUD_HTTP_ENABLED=1` bleibt der
    /// Provider inert, auch wenn er in der Chain steht — selbst dann,
    /// wenn im Secret-Store bereits ein Key liegt. Cloud ist opt-in.
    pub enabled: bool,
    /// Ziel-URL, z. B. `http://127.0.0.1:8090/v1/completion`
    /// (typischerweise hinter einem lokalen TLS-terminierenden
    /// Reverse-Proxy). `https://` wird im Provider abgelehnt.
    pub endpoint: Option<String>,
    /// Optionaler Modellname — wird, falls gesetzt, als
    /// `model`-Feld in den JSON-Body aufgenommen. Viele OpenAI-/
    /// llama.cpp-kompatible Endpoints erwarten das Feld.
    pub model: Option<String>,
    /// Zeitbudget pro Completion-Request.
    pub request_timeout_seconds: u64,
    /// JSON-Feldname für den Prompt. Default `"prompt"`.
    pub prompt_field: String,
    /// JSON-Feldname für den Antworttext. Default `"content"`.
    pub response_field: String,
    /// HTTP-Header, unter dem der API-Key angehängt wird. Default
    /// `"Authorization"` (mit `Bearer `-Prefix). Nur env-konfigurier-
    /// bar — die Settings-Shell editiert diesen Wert nicht, um die
    /// UX klein zu halten.
    pub auth_header: String,
}

impl Default for CloudHttpConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            endpoint: None,
            model: None,
            request_timeout_seconds: DEFAULT_CLOUD_HTTP_REQUEST_TIMEOUT_SECONDS,
            prompt_field: DEFAULT_CLOUD_HTTP_PROMPT_FIELD.to_string(),
            response_field: DEFAULT_CLOUD_HTTP_RESPONSE_FIELD.to_string(),
            auth_header: DEFAULT_CLOUD_HTTP_AUTH_HEADER.to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub abrain_cmd: String,
    pub log_level: String,
    pub audio: AudioConfig,
    pub ipc: IpcConfig,
    pub interaction: InteractionConfig,
    #[serde(default)]
    pub accessibility: AccessibilityConfig,
    pub approval: ApprovalConfig,
    pub text_provider: TextProviderConfig,
}

impl Config {
    pub fn load() -> Result<Self> {
        let args = CliArgs::parse();
        let dotenv = load_dotenv()?;

        let lookup = |key: &str| -> Option<String> {
            env::var(key).ok().or_else(|| dotenv.get(key).cloned())
        };

        let abrain_cmd = args
            .abrain_cmd
            .or_else(|| lookup("ABRAIN_CMD"))
            .unwrap_or_else(|| DEFAULT_ABRAIN_CMD.to_string());

        let log_level = args
            .log_level
            .or_else(|| lookup("LOG_LEVEL"))
            .unwrap_or_else(|| DEFAULT_LOG_LEVEL.to_string());

        let tts_enabled = parse_bool(lookup("SMOLIT_TTS_ENABLED").as_deref(), true);
        let tts_cmd = non_empty(lookup("SMOLIT_TTS_CMD"));
        let tts_piper_cmd = non_empty(lookup("SMOLIT_TTS_PIPER_CMD"));
        let tts_timeout_seconds =
            parse_u64(lookup("SMOLIT_TTS_TIMEOUT_SECONDS").as_deref(), DEFAULT_TTS_TIMEOUT_SECONDS);

        let stt_enabled = parse_bool(lookup("SMOLIT_STT_ENABLED").as_deref(), true);
        let stt_cmd = non_empty(lookup("SMOLIT_STT_CMD"));
        let stt_whisper_cpp_cmd = non_empty(lookup("SMOLIT_STT_WHISPER_CPP_CMD"));
        let stt_timeout_seconds =
            parse_u64(lookup("SMOLIT_STT_TIMEOUT_SECONDS").as_deref(), DEFAULT_STT_TIMEOUT_SECONDS);

        let auto_speak = parse_bool(lookup("SMOLIT_AUDIO_AUTO_SPEAK").as_deref(), true);

        // Audio-Provider-Ketten (PR 6). Gleiche Parser-Regeln wie beim
        // Text-Resolver: komma-separierter Env-String, Lowercase-Normalisierung,
        // Filter leerer Tokens, Fallback auf den kuratierten Default. Die
        // eigentliche Whitelist für bekannte Kinds sitzt im Resolver
        // (`providers::stt`/`providers::tts`) — hier nur der Parse-Schritt.
        let stt_provider_chain = parse_audio_provider_chain(
            lookup("SMOLIT_STT_PROVIDER_CHAIN").as_deref(),
            DEFAULT_STT_PROVIDER_CHAIN,
        );
        let tts_provider_chain = parse_audio_provider_chain(
            lookup("SMOLIT_TTS_PROVIDER_CHAIN").as_deref(),
            DEFAULT_TTS_PROVIDER_CHAIN,
        );

        let ipc_enabled = parse_bool(lookup("SMOLIT_IPC_ENABLED").as_deref(), true);
        let ipc_bind = non_empty(lookup("SMOLIT_IPC_BIND"))
            .unwrap_or_else(|| DEFAULT_IPC_BIND.to_string());

        let interaction_enabled =
            parse_bool(lookup("SMOLIT_INTERACTION_ENABLED").as_deref(), true);
        let interaction_backend = non_empty(lookup("SMOLIT_INTERACTION_BACKEND"))
            .unwrap_or_else(|| DEFAULT_INTERACTION_BACKEND.to_string());
        let allow_open_application = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_OPEN_APP").as_deref(),
            DEFAULT_INTERACTION_ALLOW_OPEN_APP,
        );
        let allow_focus_window = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW").as_deref(),
            DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW,
        );
        let allow_type_text = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_TYPE_TEXT").as_deref(),
            DEFAULT_INTERACTION_ALLOW_TYPE_TEXT,
        );
        let allow_shortcuts = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_SHORTCUTS").as_deref(),
            DEFAULT_INTERACTION_ALLOW_SHORTCUTS,
        );
        let require_confirmation = parse_bool(
            lookup("SMOLIT_INTERACTION_REQUIRE_CONFIRMATION").as_deref(),
            DEFAULT_INTERACTION_REQUIRE_CONFIRMATION,
        );
        let open_app_cmd_template = non_empty(lookup("SMOLIT_INTERACTION_OPEN_APP_CMD"));
        let focus_window_cmd_template =
            non_empty(lookup("SMOLIT_INTERACTION_FOCUS_WINDOW_CMD"));

        let approval_timeout_seconds = parse_u64(
            lookup("SMOLIT_APPROVAL_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_APPROVAL_TIMEOUT_SECONDS,
        );

        // Accessibility RPC FA-1 (ADR-0002, PR 53). Default-off.
        // The runtime path additionally requires the `accessibility_rpc`
        // Cargo feature; without the feature this flag still parses but
        // the orchestrator returns `Unavailable { reason:
        // "accessibility_rpc_feature_disabled" }`.
        let accessibility_rpc_enabled = parse_bool(
            lookup("SMOLIT_ACCESSIBILITY_RPC_ENABLED").as_deref(),
            false,
        );

        // Text-Provider-Kette. Env-Format: komma-separierte
        // Kind-Namen. Unbekannte Kinds werden beim Resolver-Bau mit
        // `warn!` verworfen — Config hält den Rohwert und filtert nur
        // leere Tokens. Ohne Env bleibt der Default `["abrain"]`
        // bindend, damit ein Start ohne Konfiguration das bisherige
        // ABrain-Only-Verhalten reproduziert.
        let text_provider_chain = parse_text_provider_chain(
            lookup("SMOLIT_TEXT_PROVIDER_CHAIN").as_deref(),
        );

        // Llamafile-Provider-Konfiguration. Alle Felder sind opt-in:
        // ohne Env-Variablen bleibt das Feature inert
        // (`enabled=false`, `path=None`). Das schützt den Default-
        // Lauf davor, still in einen lokalen LLM-Pfad abzukippen.
        let llamafile_enabled = parse_bool(
            lookup("SMOLIT_LLAMAFILE_ENABLED").as_deref(),
            false,
        );
        let llamafile_path = non_empty(lookup("SMOLIT_LLAMAFILE_PATH"));
        let llamafile_mode = parse_llamafile_mode(
            lookup("SMOLIT_LLAMAFILE_MODE").as_deref(),
        );
        let llamafile_idle_timeout = parse_u64(
            lookup("SMOLIT_LLAMAFILE_IDLE_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_LLAMAFILE_IDLE_TIMEOUT_SECONDS,
        );
        let llamafile_port = parse_llamafile_port(
            lookup("SMOLIT_LLAMAFILE_PORT").as_deref(),
        );
        let llamafile_startup_timeout = parse_u64(
            lookup("SMOLIT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS,
        );
        let llamafile_request_timeout = parse_u64(
            lookup("SMOLIT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS,
        );

        // Local-HTTP-Provider-Konfiguration (PR 8). Alle Felder sind
        // opt-in; ohne Env bleibt der Provider inert. Wie beim
        // Llamafile-Pfad wird ein leerer oder nur-Whitespace-Endpoint
        // wie "nicht gesetzt" behandelt.
        let local_http_enabled = parse_bool(
            lookup("SMOLIT_LOCAL_HTTP_ENABLED").as_deref(),
            false,
        );
        let local_http_endpoint = non_empty(lookup("SMOLIT_LOCAL_HTTP_ENDPOINT"));
        let local_http_request_timeout = parse_u64(
            lookup("SMOLIT_LOCAL_HTTP_REQUEST_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_LOCAL_HTTP_REQUEST_TIMEOUT_SECONDS,
        );
        let local_http_prompt_field = non_empty(lookup("SMOLIT_LOCAL_HTTP_PROMPT_FIELD"))
            .unwrap_or_else(|| DEFAULT_LOCAL_HTTP_PROMPT_FIELD.to_string());
        let local_http_response_field = non_empty(lookup("SMOLIT_LOCAL_HTTP_RESPONSE_FIELD"))
            .unwrap_or_else(|| DEFAULT_LOCAL_HTTP_RESPONSE_FIELD.to_string());

        // Cloud-HTTP-Provider-Konfiguration (PR 10). Wie Local-HTTP
        // opt-in; ohne Env bleibt der Provider inert. Der API-Key
        // wird **nicht** hier gelesen — er wohnt im Secrets-Store.
        let cloud_http_enabled = parse_bool(
            lookup("SMOLIT_CLOUD_HTTP_ENABLED").as_deref(),
            false,
        );
        let cloud_http_endpoint = non_empty(lookup("SMOLIT_CLOUD_HTTP_ENDPOINT"));
        let cloud_http_model = non_empty(lookup("SMOLIT_CLOUD_HTTP_MODEL"));
        let cloud_http_request_timeout = parse_u64(
            lookup("SMOLIT_CLOUD_HTTP_REQUEST_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_CLOUD_HTTP_REQUEST_TIMEOUT_SECONDS,
        );
        let cloud_http_prompt_field = non_empty(lookup("SMOLIT_CLOUD_HTTP_PROMPT_FIELD"))
            .unwrap_or_else(|| DEFAULT_CLOUD_HTTP_PROMPT_FIELD.to_string());
        let cloud_http_response_field = non_empty(lookup("SMOLIT_CLOUD_HTTP_RESPONSE_FIELD"))
            .unwrap_or_else(|| DEFAULT_CLOUD_HTTP_RESPONSE_FIELD.to_string());
        let cloud_http_auth_header = non_empty(lookup("SMOLIT_CLOUD_HTTP_AUTH_HEADER"))
            .unwrap_or_else(|| DEFAULT_CLOUD_HTTP_AUTH_HEADER.to_string());

        Ok(Self {
            abrain_cmd,
            log_level,
            audio: AudioConfig {
                tts_enabled,
                tts_cmd,
                tts_timeout_seconds,
                stt_enabled,
                stt_cmd,
                stt_whisper_cpp_cmd,
                tts_piper_cmd,
                stt_timeout_seconds,
                auto_speak,
                stt_provider_chain,
                tts_provider_chain,
            },
            ipc: IpcConfig {
                enabled: ipc_enabled,
                bind: ipc_bind,
            },
            interaction: InteractionConfig {
                enabled: interaction_enabled,
                backend: interaction_backend,
                allow_open_application,
                allow_focus_window,
                allow_type_text,
                allow_shortcuts,
                require_confirmation,
                open_app_cmd_template,
                focus_window_cmd_template,
            },
            approval: ApprovalConfig {
                timeout_seconds: approval_timeout_seconds,
            },
            accessibility: AccessibilityConfig {
                rpc_enabled: accessibility_rpc_enabled,
            },
            text_provider: TextProviderConfig {
                chain: text_provider_chain,
                llamafile: LlamafileConfig {
                    enabled: llamafile_enabled,
                    path: llamafile_path,
                    mode: llamafile_mode,
                    idle_timeout_seconds: llamafile_idle_timeout,
                    port: llamafile_port,
                    startup_timeout_seconds: llamafile_startup_timeout,
                    request_timeout_seconds: llamafile_request_timeout,
                },
                local_http: LocalHttpConfig {
                    enabled: local_http_enabled,
                    endpoint: local_http_endpoint,
                    request_timeout_seconds: local_http_request_timeout,
                    prompt_field: local_http_prompt_field,
                    response_field: local_http_response_field,
                },
                cloud_http: CloudHttpConfig {
                    enabled: cloud_http_enabled,
                    endpoint: cloud_http_endpoint,
                    model: cloud_http_model,
                    request_timeout_seconds: cloud_http_request_timeout,
                    prompt_field: cloud_http_prompt_field,
                    response_field: cloud_http_response_field,
                    auth_header: cloud_http_auth_header,
                },
            },
        })
    }

    pub fn as_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{\"error\":\"config-serialize\"}".into())
    }
}

fn parse_bool(value: Option<&str>, default: bool) -> bool {
    match value.map(|v| v.trim().to_ascii_lowercase()) {
        Some(v) if matches!(v.as_str(), "true" | "1" | "yes" | "on") => true,
        Some(v) if matches!(v.as_str(), "false" | "0" | "no" | "off") => false,
        Some(_) | None => default,
    }
}

fn parse_u64(value: Option<&str>, default: u64) -> u64 {
    value
        .and_then(|v| v.trim().parse::<u64>().ok())
        .unwrap_or(default)
}

/// Parst die rohe `SMOLIT_TEXT_PROVIDER_CHAIN`-Eingabe (komma-separiert)
/// in eine Liste normalisierter Kind-Namen. Leerer oder nicht gesetzter
/// Input → Default `["abrain"]`. Unbekannte Kinds bleiben hier
/// **enthalten** — der eigentliche Whitelist-Filter passiert im
/// Provider-Resolver, damit die Doku-Entscheidung („unbekannte Kinds
/// werden sichtbar verworfen") an einer einzigen Stelle lebt.
fn parse_text_provider_chain(raw: Option<&str>) -> Vec<String> {
    let Some(value) = raw else {
        return DEFAULT_TEXT_PROVIDER_CHAIN
            .iter()
            .map(|s| (*s).to_string())
            .collect();
    };
    let items: Vec<String> = value
        .split(',')
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    if items.is_empty() {
        DEFAULT_TEXT_PROVIDER_CHAIN
            .iter()
            .map(|s| (*s).to_string())
            .collect()
    } else {
        items
    }
}

/// Parst eine rohe komma-separierte Audio-Provider-Kette
/// (`SMOLIT_STT_PROVIDER_CHAIN` / `SMOLIT_TTS_PROVIDER_CHAIN`). Regeln
/// wie beim Text-Resolver: Trim, Lowercase, leere Tokens weg; leere
/// Liste fällt auf `default_chain` zurück. Unbekannte Kinds werden
/// **hier bewusst nicht** gefiltert — der Resolver
/// (`providers::stt::SttProviderResolver::from_chain` bzw.
/// `providers::tts::TtsProviderResolver::from_chain`) hält die
/// Whitelist an einer einzigen Stelle.
fn parse_audio_provider_chain(raw: Option<&str>, default_chain: &[&str]) -> Vec<String> {
    let Some(value) = raw else {
        return default_chain.iter().map(|s| (*s).to_string()).collect();
    };
    let items: Vec<String> = value
        .split(',')
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    if items.is_empty() {
        default_chain.iter().map(|s| (*s).to_string()).collect()
    } else {
        items
    }
}

/// Parst den rohen `SMOLIT_LLAMAFILE_MODE`-Wert in einen Mode-String
/// aus der Whitelist. Unbekannte Eingaben fallen auf den Default
/// zurück — kein Silent-Free-Form, keine zukunftsoffenen Sonderwerte.
fn parse_llamafile_mode(raw: Option<&str>) -> String {
    match raw.and_then(validate_llamafile_mode) {
        Some(canonical) => canonical.to_string(),
        None => DEFAULT_LLAMAFILE_MODE.to_string(),
    }
}

/// Kanonisiert einen Llamafile-Mode-String gegen die Whitelist. Gibt
/// `None` zurück, wenn der Wert nicht aus
/// [`ALLOWED_LLAMAFILE_MODES`] stammt. Wird sowohl beim Startup-Parser
/// (leise Default-Fallback) als auch im Settings-Schreibpfad genutzt
/// — dort lehnen wir unbekannte Werte **ausdrücklich** ab, statt sie
/// still zu verwerfen. Single source of truth für die Whitelist.
pub fn validate_llamafile_mode(raw: &str) -> Option<&'static str> {
    let normalized = raw.trim().to_ascii_lowercase();
    ALLOWED_LLAMAFILE_MODES
        .iter()
        .find(|m| **m == normalized)
        .copied()
}

/// Parst einen rohen `SMOLIT_LLAMAFILE_PORT`-Wert. Unbekannte oder
/// ungültige Ports fallen auf den Default zurück. Ports im
/// Well-Known-Bereich (< 1024) werden abgelehnt — der Runtime-PR
/// startet den Prozess als Nutzer und hat dort ohnehin keine
/// Berechtigung, und reservierte Ports sind keine legitime Ziel-
/// konfiguration für einen lokalen LLM-Server.
fn parse_llamafile_port(raw: Option<&str>) -> u16 {
    let Some(value) = raw else {
        return DEFAULT_LLAMAFILE_PORT;
    };
    match value.trim().parse::<u16>() {
        Ok(p) if p >= 1024 => p,
        _ => DEFAULT_LLAMAFILE_PORT,
    }
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.and_then(|v| {
        let trimmed = v.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn load_dotenv() -> Result<HashMap<String, String>> {
    let Some(path) = find_dotenv_path()? else {
        return Ok(HashMap::new());
    };

    let content = fs::read_to_string(&path)
        .with_context(|| format!("failed to read env file at {}", path.display()))?;

    Ok(parse_dotenv(&content))
}

fn find_dotenv_path() -> Result<Option<PathBuf>> {
    let current_dir = env::current_dir().context("failed to resolve current directory")?;
    let candidates = [current_dir.join(".env"), current_dir.join("..").join(".env")];

    Ok(candidates.into_iter().find(|path| path.is_file()))
}

fn parse_dotenv(content: &str) -> HashMap<String, String> {
    content
        .lines()
        .filter_map(|line| parse_dotenv_line(line.trim()))
        .collect()
}

fn parse_dotenv_line(line: &str) -> Option<(String, String)> {
    if line.is_empty() || line.starts_with('#') {
        return None;
    }

    let (key, value) = line.split_once('=')?;
    let key = key.trim().strip_prefix("export ").unwrap_or(key.trim()).trim();
    let value = normalize_env_value(value.trim());

    if key.is_empty() {
        return None;
    }

    Some((key.to_string(), value))
}

fn normalize_env_value(value: &str) -> String {
    let trimmed = value.trim();

    if let Some(unquoted) = trimmed
        .strip_prefix('"')
        .and_then(|value| value.strip_suffix('"'))
    {
        return unquoted.to_string();
    }

    if let Some(unquoted) = trimmed
        .strip_prefix('\'')
        .and_then(|value| value.strip_suffix('\''))
    {
        return unquoted.to_string();
    }

    trimmed.to_string()
}

#[allow(dead_code)]
fn _is_repo_root(path: &Path) -> bool {
    path.join("core").exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_text_provider_chain_defaults_to_abrain_when_missing() {
        assert_eq!(parse_text_provider_chain(None), vec!["abrain"]);
    }

    #[test]
    fn parse_text_provider_chain_trims_normalises_and_filters_empty() {
        assert_eq!(
            parse_text_provider_chain(Some("  ABrain , , local_cmd ")),
            vec!["abrain", "local_cmd"],
        );
    }

    #[test]
    fn parse_text_provider_chain_empty_string_falls_back_to_default() {
        assert_eq!(parse_text_provider_chain(Some("")), vec!["abrain"]);
        assert_eq!(parse_text_provider_chain(Some(", , ")), vec!["abrain"]);
    }

    #[test]
    fn parse_text_provider_chain_passes_llamafile_through() {
        // Whitelist-Filter passiert im Resolver, nicht in Config. Hier
        // reicht, dass der Name normalisiert (lowercase, stripped)
        // durchgereicht wird.
        assert_eq!(
            parse_text_provider_chain(Some("abrain, LLAMAFILE_LOCAL")),
            vec!["abrain", "llamafile_local"],
        );
    }

    // --- Audio-Provider-Chain-Parser (PR 6) -----------------------------

    #[test]
    fn parse_audio_chain_defaults_to_command_when_missing() {
        assert_eq!(
            parse_audio_provider_chain(None, DEFAULT_STT_PROVIDER_CHAIN),
            vec!["command"],
        );
        assert_eq!(
            parse_audio_provider_chain(None, DEFAULT_TTS_PROVIDER_CHAIN),
            vec!["command"],
        );
    }

    #[test]
    fn parse_audio_chain_trims_normalises_and_filters_empty() {
        assert_eq!(
            parse_audio_provider_chain(
                Some("  COMMAND , , http_local "),
                DEFAULT_STT_PROVIDER_CHAIN,
            ),
            vec!["command", "http_local"],
        );
    }

    #[test]
    fn parse_audio_chain_empty_string_falls_back_to_default() {
        assert_eq!(
            parse_audio_provider_chain(Some(""), DEFAULT_STT_PROVIDER_CHAIN),
            vec!["command"],
        );
        assert_eq!(
            parse_audio_provider_chain(Some(", , "), DEFAULT_TTS_PROVIDER_CHAIN),
            vec!["command"],
        );
    }

    #[test]
    fn parse_llamafile_mode_defaults_when_missing() {
        assert_eq!(parse_llamafile_mode(None), "on_demand");
    }

    #[test]
    fn parse_llamafile_mode_accepts_whitelist_values() {
        assert_eq!(parse_llamafile_mode(Some("on_demand")), "on_demand");
        assert_eq!(parse_llamafile_mode(Some("standby")), "standby");
        // case-insensitive + whitespace
        assert_eq!(parse_llamafile_mode(Some("  STANDBY ")), "standby");
    }

    #[test]
    fn parse_llamafile_mode_rejects_unknown_values() {
        assert_eq!(parse_llamafile_mode(Some("auto")), "on_demand");
        assert_eq!(parse_llamafile_mode(Some("")), "on_demand");
        assert_eq!(parse_llamafile_mode(Some("cloud")), "on_demand");
    }

    #[test]
    fn parse_llamafile_port_uses_default_when_missing() {
        assert_eq!(parse_llamafile_port(None), 8788);
    }

    #[test]
    fn parse_llamafile_port_accepts_valid_unprivileged_ports() {
        assert_eq!(parse_llamafile_port(Some("8788")), 8788);
        assert_eq!(parse_llamafile_port(Some("  9001 ")), 9001);
        assert_eq!(parse_llamafile_port(Some("65535")), 65535);
    }

    #[test]
    fn parse_llamafile_port_rejects_privileged_and_invalid() {
        // Well-Known-Ports unzulässig — fallen auf Default zurück.
        assert_eq!(parse_llamafile_port(Some("80")), 8788);
        assert_eq!(parse_llamafile_port(Some("443")), 8788);
        assert_eq!(parse_llamafile_port(Some("1023")), 8788);
        // Nicht-Zahlen, Overflows, leere Strings.
        assert_eq!(parse_llamafile_port(Some("foo")), 8788);
        assert_eq!(parse_llamafile_port(Some("70000")), 8788);
        assert_eq!(parse_llamafile_port(Some("")), 8788);
    }

    // --- Policy v0 defaults lock (PR 25) --------------------------------

    #[test]
    fn policy_v0_defaults_are_locked() {
        // Safety baseline: real interaction actions require approval by
        // default, and only `open_application` is allow-listed out of
        // the box. Flipping any of these is a policy change and must
        // come with an updated ADR / OPEN_WORK entry.
        assert_eq!(DEFAULT_INTERACTION_REQUIRE_CONFIRMATION, true);
        assert_eq!(DEFAULT_INTERACTION_ALLOW_OPEN_APP, true);
        assert_eq!(DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW, false);
        assert_eq!(DEFAULT_INTERACTION_ALLOW_TYPE_TEXT, false);
        assert_eq!(DEFAULT_INTERACTION_ALLOW_SHORTCUTS, false);
    }

    #[test]
    fn policy_v0_parse_bool_with_no_env_uses_locked_defaults() {
        // `Config::load` delegates to `parse_bool` with the locked
        // constants; mirror that call with `None` to prove an empty
        // environment reproduces the Policy v0 baseline end-to-end.
        assert_eq!(
            parse_bool(None, DEFAULT_INTERACTION_REQUIRE_CONFIRMATION),
            true,
        );
        assert_eq!(
            parse_bool(None, DEFAULT_INTERACTION_ALLOW_OPEN_APP),
            true,
        );
        assert_eq!(
            parse_bool(None, DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW),
            false,
        );
        assert_eq!(
            parse_bool(None, DEFAULT_INTERACTION_ALLOW_TYPE_TEXT),
            false,
        );
        assert_eq!(
            parse_bool(None, DEFAULT_INTERACTION_ALLOW_SHORTCUTS),
            false,
        );
    }
}
