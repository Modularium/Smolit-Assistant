use anyhow::{Context, Result, bail};
use tokio::process::Command;
use tokio::time::{Duration, timeout};
use tracing::{debug, warn};

use crate::audio::types::{AudioFeatureState, split_command};
use crate::config::AudioConfig;

pub struct SttService {
    enabled: bool,
    command: Option<String>,
    timeout_seconds: u64,
}

impl SttService {
    pub fn new(config: &AudioConfig) -> Self {
        if config.stt_enabled && config.stt_cmd.is_none() {
            warn!("STT is enabled but SMOLIT_STT_CMD is empty; STT will be unavailable");
        }

        Self {
            enabled: config.stt_enabled,
            command: config.stt_cmd.clone(),
            timeout_seconds: config.stt_timeout_seconds,
        }
    }

    pub fn is_available(&self) -> bool {
        self.enabled && self.command.is_some()
    }

    pub fn state(&self) -> AudioFeatureState {
        AudioFeatureState::new(self.enabled, self.command.is_some())
    }

    pub async fn listen_once(&self) -> Result<String> {
        if !self.enabled {
            bail!("STT is disabled");
        }
        let cmd = self
            .command
            .as_deref()
            .context("STT command is not configured")?;

        let (program, args) =
            split_command(cmd).context("STT command is empty after parsing")?;

        debug!(program = %program, "invoking STT command");

        let output = timeout(
            Duration::from_secs(self.timeout_seconds),
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

        let stdout = String::from_utf8(output.stdout)
            .context("STT stdout was not valid UTF-8")?;
        let recognized = stdout.trim().to_string();

        if recognized.is_empty() {
            bail!("STT command `{program}` returned no recognized text");
        }

        Ok(recognized)
    }
}
