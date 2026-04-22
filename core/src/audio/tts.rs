use std::process::Stdio;

use anyhow::{Context, Result, bail};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::time::{Duration, timeout};
use tracing::{debug, warn};

use crate::audio::types::{AudioFeatureState, split_command};
use crate::config::AudioConfig;

pub struct TtsService {
    enabled: bool,
    command: Option<String>,
    timeout_seconds: u64,
}

impl TtsService {
    pub fn new(config: &AudioConfig) -> Self {
        if config.tts_enabled && config.tts_cmd.is_none() {
            warn!("TTS is enabled but SMOLIT_TTS_CMD is empty; TTS will be unavailable");
        }

        Self {
            enabled: config.tts_enabled,
            command: config.tts_cmd.clone(),
            timeout_seconds: config.tts_timeout_seconds,
        }
    }

    pub fn is_available(&self) -> bool {
        self.enabled && self.command.is_some()
    }

    pub fn state(&self) -> AudioFeatureState {
        AudioFeatureState::new(self.enabled, self.command.is_some())
    }

    pub async fn speak(&self, text: &str) -> Result<()> {
        if !self.enabled {
            bail!("TTS is disabled");
        }
        let cmd = self
            .command
            .as_deref()
            .context("TTS command is not configured")?;

        let (program, args) =
            split_command(cmd).context("TTS command is empty after parsing")?;

        debug!(program = %program, "invoking TTS command");

        let mut child = Command::new(&program)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .with_context(|| format!("failed to spawn TTS command `{program}`"))?;

        if let Some(mut stdin) = child.stdin.take() {
            let text_owned = text.to_string();
            stdin
                .write_all(text_owned.as_bytes())
                .await
                .context("failed to write text to TTS stdin")?;
            stdin
                .shutdown()
                .await
                .context("failed to close TTS stdin")?;
        }

        let output = timeout(
            Duration::from_secs(self.timeout_seconds),
            child.wait_with_output(),
        )
        .await
        .context("TTS command timed out")?
        .context("failed to await TTS command")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let detail = if stderr.is_empty() {
                "process exited without error output".to_string()
            } else {
                stderr
            };
            bail!(
                "TTS command `{program}` failed with status {}: {}",
                output.status,
                detail
            );
        }

        Ok(())
    }
}
