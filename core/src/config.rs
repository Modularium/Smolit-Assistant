use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::Parser;
use serde::{Deserialize, Serialize};

const DEFAULT_ABRAIN_CMD: &str = "abrain";
const DEFAULT_LOG_LEVEL: &str = "info";

#[derive(Debug, Parser)]
#[command(name = "smolit", about = "Smolit Assistant core daemon")]
struct CliArgs {
    #[arg(long)]
    abrain_cmd: Option<String>,

    #[arg(long)]
    log_level: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub abrain_cmd: String,
    pub log_level: String,
}

impl Config {
    pub fn load() -> Result<Self> {
        let args = CliArgs::parse();
        let dotenv = load_dotenv()?;

        let abrain_cmd = args
            .abrain_cmd
            .or_else(|| env::var("ABRAIN_CMD").ok())
            .or_else(|| dotenv.get("ABRAIN_CMD").cloned())
            .unwrap_or_else(|| DEFAULT_ABRAIN_CMD.to_string());

        let log_level = args
            .log_level
            .or_else(|| env::var("LOG_LEVEL").ok())
            .or_else(|| dotenv.get("LOG_LEVEL").cloned())
            .unwrap_or_else(|| DEFAULT_LOG_LEVEL.to_string());

        Ok(Self {
            abrain_cmd,
            log_level,
        })
    }

    pub fn as_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{\"error\":\"config-serialize\"}".into())
    }
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
