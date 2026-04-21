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
    pub allow_type_text: bool,
    pub allow_shortcuts: bool,
    pub require_confirmation: bool,
    /// Command template used by the `command` backend to spawn an
    /// application launcher. `{name}` is substituted at call time.
    /// Kept optional so absence is an honest "unavailable" signal
    /// rather than a silent default like `xdg-open`.
    pub open_app_cmd_template: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub abrain_cmd: String,
    pub log_level: String,
    pub audio: AudioConfig,
    pub ipc: IpcConfig,
    pub interaction: InteractionConfig,
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
                allow_type_text,
                allow_shortcuts,
                require_confirmation,
                open_app_cmd_template,
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
