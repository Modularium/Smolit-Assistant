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
const DEFAULT_APPROVAL_TIMEOUT_SECONDS: u64 = 20;
/// Konservativer Default der Text-Provider-Kette. ABrain bleibt
/// Primary — explizit in der Architektur-Doku §3 / §5 festgelegt.
const DEFAULT_TEXT_PROVIDER_CHAIN: &[&str] = &["abrain"];
/// Default-Mode des lokalen llamafile-Providers. Wird heute nur
/// gelesen und an den Provider-Stub weitergereicht — Runtime
/// implementiert die Unterscheidung in einem Folge-PR.
const DEFAULT_LLAMAFILE_MODE: &str = "on_demand";
const DEFAULT_LLAMAFILE_IDLE_TIMEOUT_SECONDS: u64 = 300;
/// Whitelist zulässiger Mode-Strings. Eingaben außerhalb dieser Menge
/// werden beim Parsing verworfen und fallen auf den Default zurück;
/// das hält das Vokabular klein und vermeidet stille Freiform-Werte.
const ALLOWED_LLAMAFILE_MODES: &[&str] = &["on_demand", "standby"];

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
    pub stt_timeout_seconds: u64,
    pub auto_speak: bool,
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
    /// Pfad zum llamafile-Binary bzw. Modell-Wrapper. Heute nur
    /// gelesen und zur Lifecycle-Entscheidung genutzt
    /// (`None` / leer → `NotConfigured`); wird vom Runtime-PR
    /// tatsächlich aufgerufen.
    pub path: Option<String>,
    /// Modus: `"on_demand"` (Default — Prozess beim ersten Request
    /// starten, nach Idle-Timeout wieder beenden) oder `"standby"`
    /// (Prozess dauerhaft halten, solange `enabled`). Unbekannte
    /// Eingaben fallen auf den Default zurück.
    pub mode: String,
    /// Idle-Timeout in Sekunden für den `on_demand`-Modus. Heute
    /// gelesen und gespeichert, noch nicht ausgeführt.
    pub idle_timeout_seconds: u64,
}

impl Default for LlamafileConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            path: None,
            mode: DEFAULT_LLAMAFILE_MODE.to_string(),
            idle_timeout_seconds: DEFAULT_LLAMAFILE_IDLE_TIMEOUT_SECONDS,
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
        let tts_timeout_seconds =
            parse_u64(lookup("SMOLIT_TTS_TIMEOUT_SECONDS").as_deref(), DEFAULT_TTS_TIMEOUT_SECONDS);

        let stt_enabled = parse_bool(lookup("SMOLIT_STT_ENABLED").as_deref(), true);
        let stt_cmd = non_empty(lookup("SMOLIT_STT_CMD"));
        let stt_timeout_seconds =
            parse_u64(lookup("SMOLIT_STT_TIMEOUT_SECONDS").as_deref(), DEFAULT_STT_TIMEOUT_SECONDS);

        let auto_speak = parse_bool(lookup("SMOLIT_AUDIO_AUTO_SPEAK").as_deref(), true);

        let ipc_enabled = parse_bool(lookup("SMOLIT_IPC_ENABLED").as_deref(), true);
        let ipc_bind = non_empty(lookup("SMOLIT_IPC_BIND"))
            .unwrap_or_else(|| DEFAULT_IPC_BIND.to_string());

        let interaction_enabled =
            parse_bool(lookup("SMOLIT_INTERACTION_ENABLED").as_deref(), true);
        let interaction_backend = non_empty(lookup("SMOLIT_INTERACTION_BACKEND"))
            .unwrap_or_else(|| DEFAULT_INTERACTION_BACKEND.to_string());
        let allow_open_application = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_OPEN_APP").as_deref(),
            true,
        );
        let allow_focus_window = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW").as_deref(),
            false,
        );
        let allow_type_text = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_TYPE_TEXT").as_deref(),
            false,
        );
        let allow_shortcuts = parse_bool(
            lookup("SMOLIT_INTERACTION_ALLOW_SHORTCUTS").as_deref(),
            false,
        );
        let require_confirmation = parse_bool(
            lookup("SMOLIT_INTERACTION_REQUIRE_CONFIRMATION").as_deref(),
            true,
        );
        let open_app_cmd_template = non_empty(lookup("SMOLIT_INTERACTION_OPEN_APP_CMD"));
        let focus_window_cmd_template =
            non_empty(lookup("SMOLIT_INTERACTION_FOCUS_WINDOW_CMD"));

        let approval_timeout_seconds = parse_u64(
            lookup("SMOLIT_APPROVAL_TIMEOUT_SECONDS").as_deref(),
            DEFAULT_APPROVAL_TIMEOUT_SECONDS,
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

        // Llamafile-Provider-Konfiguration. Alle vier Felder sind
        // opt-in: ohne Env-Variablen bleibt das Feature inert
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

        Ok(Self {
            abrain_cmd,
            log_level,
            audio: AudioConfig {
                tts_enabled,
                tts_cmd,
                tts_timeout_seconds,
                stt_enabled,
                stt_cmd,
                stt_timeout_seconds,
                auto_speak,
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
            text_provider: TextProviderConfig {
                chain: text_provider_chain,
                llamafile: LlamafileConfig {
                    enabled: llamafile_enabled,
                    path: llamafile_path,
                    mode: llamafile_mode,
                    idle_timeout_seconds: llamafile_idle_timeout,
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

/// Parst den rohen `SMOLIT_LLAMAFILE_MODE`-Wert in einen Mode-String
/// aus der Whitelist. Unbekannte Eingaben fallen auf den Default
/// zurück — kein Silent-Free-Form, keine zukunftsoffenen Sonderwerte.
fn parse_llamafile_mode(raw: Option<&str>) -> String {
    let Some(value) = raw else {
        return DEFAULT_LLAMAFILE_MODE.to_string();
    };
    let normalized = value.trim().to_ascii_lowercase();
    if ALLOWED_LLAMAFILE_MODES.iter().any(|m| *m == normalized) {
        normalized
    } else {
        DEFAULT_LLAMAFILE_MODE.to_string()
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
}
