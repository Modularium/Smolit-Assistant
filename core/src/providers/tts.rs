//! TTS-Provider-Abstraktion (PR 6 der Provider-Fallback-/Settings-Linie).
//!
//! Spiegel zu [`crate::providers::stt`]: gleiche Enum-Dispatch-
//! Architektur, gleiche Resolver-Semantik, gleiche Leitplanken. Ein
//! einziges produktives Kind heute — `command`, das den bisherigen
//! `SMOLIT_TTS_CMD`-Pfad übernimmt. `speak`-Signatur und Timeout-
//! Verhalten bleiben byte-kompatibel zum bisherigen
//! `audio::tts::TtsService`.
//!
//! **Nicht-Ziele dieses Moduls:**
//!
//! - kein Cloud-SDK,
//! - keine Streaming-TTS-Pipeline,
//! - keine neuen `speaking_started`/`speaking_ended`-Events
//!   (bleiben für einen späteren Audio-UX-PR offen),
//! - kein Secrets-Transport.

use std::process::Stdio;
use std::sync::Mutex;

use anyhow::{Context, Result, bail};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::time::{Duration, timeout};
use tracing::{debug, info, warn};

use crate::audio::types::{AudioFeatureState, split_command};
use crate::config::AudioConfig;

pub const PROVIDER_NAME_TTS_COMMAND: &str = "command";
#[allow(dead_code)]
pub const KNOWN_TTS_KINDS: &[&str] = &[PROVIDER_NAME_TTS_COMMAND];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TtsProviderError {
    EmptyChain,
    AllFailed(String),
}

impl std::fmt::Display for TtsProviderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyChain => write!(
                f,
                "no TTS provider configured (chain is empty); check SMOLIT_TTS_PROVIDER_CHAIN or core config",
            ),
            Self::AllFailed(last) => write!(
                f,
                "all configured TTS providers failed; last error: {last}",
            ),
        }
    }
}

impl std::error::Error for TtsProviderError {}

#[derive(Debug, Clone)]
pub struct TtsProviderChainItem {
    pub kind: String,
}

#[derive(Debug)]
pub enum TtsProviderImpl {
    Command(TtsCommandProvider),
}

impl TtsProviderImpl {
    pub fn kind_name(&self) -> &'static str {
        match self {
            Self::Command(_) => PROVIDER_NAME_TTS_COMMAND,
        }
    }

    pub fn classify_error(err: &anyhow::Error) -> &'static str {
        let chain: Vec<String> = err.chain().map(|e| e.to_string()).collect();
        let joined = chain.join(" | ").to_ascii_lowercase();
        if joined.contains("tts is disabled") {
            return "disabled";
        }
        if joined.contains("tts command is not configured")
            || joined.contains("tts command is empty after parsing")
        {
            return "not_configured";
        }
        if joined.contains("timed out") {
            return "timeout";
        }
        if joined.contains("failed to spawn") || joined.contains("no such file") {
            return "process_missing";
        }
        if joined.contains("failed to write text to tts stdin")
            || joined.contains("failed to close tts stdin")
        {
            return "stdin_write_failed";
        }
        if joined.contains("failed with status") {
            return "exit_nonzero";
        }
        "unknown"
    }

    pub fn is_ready(&self) -> bool {
        match self {
            Self::Command(p) => p.is_ready(),
        }
    }

    pub fn is_cloud(&self) -> bool {
        match self {
            Self::Command(_) => false,
        }
    }

    pub async fn run(&self, text: &str) -> Result<()> {
        match self {
            Self::Command(p) => p.run(text).await,
        }
    }
}

/// Command-basierter TTS-Provider. Byte-kompatibel zum bisherigen
/// `audio::tts::TtsService`: `text` wird auf `stdin` geschrieben, das
/// Kommando gewartet, bei Non-Zero-Exit ein klarer Fehler gebaut.
#[derive(Debug, Clone)]
pub struct TtsCommandProvider {
    enabled: bool,
    command: Option<String>,
    timeout_seconds: u64,
}

impl TtsCommandProvider {
    pub fn from_config(config: &AudioConfig) -> Self {
        if config.tts_enabled && config.tts_cmd.is_none() {
            warn!("TTS is enabled but SMOLIT_TTS_CMD is empty; TTS will be unavailable");
        }
        Self {
            enabled: config.tts_enabled,
            command: config.tts_cmd.clone(),
            timeout_seconds: config.tts_timeout_seconds,
        }
    }

    pub fn is_ready(&self) -> bool {
        self.enabled && self.command.is_some()
    }

    pub fn feature_state(&self) -> AudioFeatureState {
        AudioFeatureState::new(self.enabled, self.command.is_some())
    }

    pub async fn run(&self, text: &str) -> Result<()> {
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

#[derive(Debug, Clone)]
pub struct TtsProviderRuntimeStatus {
    pub configured: String,
    pub active: String,
    pub availability: String,
    pub last_error: Option<String>,
    pub cloud: bool,
}

impl TtsProviderRuntimeStatus {
    fn initial(chain: &[TtsProviderImpl]) -> Self {
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

pub struct TtsProviderResolver {
    providers: Vec<TtsProviderImpl>,
    status: Mutex<TtsProviderRuntimeStatus>,
}

impl std::fmt::Debug for TtsProviderResolver {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TtsProviderResolver")
            .field("providers", &self.providers)
            .field("status", &self.status())
            .finish()
    }
}

impl TtsProviderResolver {
    pub fn from_providers(providers: Vec<TtsProviderImpl>) -> Self {
        let status = TtsProviderRuntimeStatus::initial(&providers);
        Self {
            providers,
            status: Mutex::new(status),
        }
    }

    pub fn from_chain(chain: &[TtsProviderChainItem], audio: &AudioConfig) -> Self {
        let mut providers: Vec<TtsProviderImpl> = Vec::with_capacity(chain.len().max(1));
        let mut skipped: Vec<String> = Vec::new();
        for item in chain {
            let normalized = item.kind.trim().to_ascii_lowercase();
            match normalized.as_str() {
                PROVIDER_NAME_TTS_COMMAND => {
                    providers.push(TtsProviderImpl::Command(TtsCommandProvider::from_config(
                        audio,
                    )));
                }
                other => skipped.push(other.to_string()),
            }
        }
        if !skipped.is_empty() {
            warn!(
                skipped = ?skipped,
                "ignoring unknown TTS provider kinds in chain (not yet implemented in this build)",
            );
        }
        if providers.is_empty() {
            warn!(
                "no known TTS providers in configured chain — falling back to default chain [command]",
            );
            providers.push(TtsProviderImpl::Command(TtsCommandProvider::from_config(
                audio,
            )));
        }
        let resolver = Self::from_providers(providers);
        info!(
            kinds = ?resolver.chain_kinds(),
            ready = resolver.is_available(),
            "TTS provider resolver built",
        );
        resolver
    }

    pub fn status(&self) -> TtsProviderRuntimeStatus {
        self.status
            .lock()
            .expect("tts provider status mutex poisoned")
            .clone()
    }

    pub fn chain_kinds(&self) -> Vec<&'static str> {
        self.providers.iter().map(|p| p.kind_name()).collect()
    }

    pub fn is_available(&self) -> bool {
        self.providers.first().map(|p| p.is_ready()).unwrap_or(false)
    }

    pub fn feature_state(&self) -> AudioFeatureState {
        match self.providers.first() {
            Some(TtsProviderImpl::Command(p)) => p.feature_state(),
            None => AudioFeatureState::new(false, false),
        }
    }

    pub async fn run(&self, text: &str) -> Result<(), TtsProviderError> {
        if self.providers.is_empty() {
            let mut s = self.status.lock().expect("tts status mutex poisoned");
            s.configured = "none".to_string();
            s.active = String::new();
            s.availability = "unavailable".to_string();
            s.last_error = Some("empty_chain".to_string());
            s.cloud = false;
            return Err(TtsProviderError::EmptyChain);
        }
        let primary = self.providers[0].kind_name().to_string();
        let mut last_err_class: Option<String> = None;
        for (index, provider) in self.providers.iter().enumerate() {
            match provider.run(text).await {
                Ok(()) => {
                    let kind = provider.kind_name().to_string();
                    let availability = if index == 0 {
                        "available".to_string()
                    } else {
                        "fallback_active".to_string()
                    };
                    let mut s = self.status.lock().expect("tts status mutex poisoned");
                    s.configured = primary;
                    s.active = kind.clone();
                    s.availability = availability;
                    s.last_error = None;
                    s.cloud = provider.is_cloud();
                    if index > 0 {
                        info!(
                            primary = %s.configured,
                            active = %kind,
                            "TTS provider fallback active — primary unavailable, secondary spoke",
                        );
                    }
                    return Ok(());
                }
                Err(err) => {
                    let class = TtsProviderImpl::classify_error(&err);
                    warn!(
                        provider = %provider.kind_name(),
                        error_class = %class,
                        error = %err,
                        "TTS provider failed — trying next in chain",
                    );
                    last_err_class = Some(class.to_string());
                }
            }
        }
        let last = last_err_class.unwrap_or_else(|| "unknown".to_string());
        {
            let mut s = self.status.lock().expect("tts status mutex poisoned");
            s.configured = primary;
            s.active = String::new();
            s.availability = "unavailable".to_string();
            s.last_error = Some(last.clone());
            s.cloud = false;
        }
        Err(TtsProviderError::AllFailed(last))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn audio_with(tts_enabled: bool, tts_cmd: Option<&str>) -> AudioConfig {
        AudioConfig {
            tts_enabled,
            tts_cmd: tts_cmd.map(|s| s.to_string()),
            tts_timeout_seconds: 5,
            stt_enabled: true,
            stt_cmd: None,
            stt_timeout_seconds: 5,
            auto_speak: false,
            stt_provider_chain: vec!["command".into()],
            tts_provider_chain: vec!["command".into()],
        }
    }

    fn command_item() -> TtsProviderChainItem {
        TtsProviderChainItem {
            kind: PROVIDER_NAME_TTS_COMMAND.to_string(),
        }
    }

    #[test]
    fn from_chain_default_instantiates_command_provider() {
        let r = TtsProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, Some("/bin/cat")),
        );
        assert_eq!(r.chain_kinds(), vec!["command"]);
        assert!(r.is_available());
    }

    #[test]
    fn from_chain_unknown_kind_falls_back_to_default() {
        let r = TtsProviderResolver::from_chain(
            &[TtsProviderChainItem {
                kind: "cloud:unknown".into(),
            }],
            &audio_with(true, Some("/bin/cat")),
        );
        assert_eq!(r.chain_kinds(), vec!["command"]);
    }

    #[test]
    fn initial_status_unavailable_when_cmd_missing() {
        let r = TtsProviderResolver::from_chain(&[command_item()], &audio_with(true, None));
        let st = r.status();
        assert_eq!(st.availability, "unavailable");
        assert!(!r.is_available());
        assert!(st.last_error.is_none());
    }

    #[tokio::test]
    async fn run_success_with_cat_as_command() {
        // `/bin/cat` schreibt stdin 1:1 auf stdout und exited sauber —
        // das reicht als "TTS-Kommando" im Testbetrieb.
        let r = TtsProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, Some("/bin/cat")),
        );
        r.run("hello").await.unwrap();
        let st = r.status();
        assert_eq!(st.active, "command");
        assert_eq!(st.availability, "available");
        assert!(st.last_error.is_none());
        assert!(!st.cloud);
    }

    #[tokio::test]
    async fn run_disabled_reports_not_configured_when_cmd_missing() {
        let r = TtsProviderResolver::from_chain(&[command_item()], &audio_with(true, None));
        let err = r.run("x").await.unwrap_err();
        match err {
            TtsProviderError::AllFailed(class) => assert_eq!(class, "not_configured"),
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[tokio::test]
    async fn run_with_failing_command_reports_exit_nonzero() {
        let r = TtsProviderResolver::from_chain(
            &[command_item()],
            &audio_with(true, Some("/bin/false")),
        );
        let err = r.run("x").await.unwrap_err();
        match err {
            TtsProviderError::AllFailed(class) => assert_eq!(class, "exit_nonzero"),
            other => panic!("unexpected: {other:?}"),
        }
        let st = r.status();
        assert_eq!(st.availability, "unavailable");
        assert_eq!(st.last_error.as_deref(), Some("exit_nonzero"));
    }

    #[test]
    fn classify_error_buckets_cover_known_classes() {
        let err = anyhow::anyhow!("TTS command timed out");
        assert_eq!(TtsProviderImpl::classify_error(&err), "timeout");
        let err = anyhow::anyhow!("failed to spawn TTS command `/no/such`");
        assert_eq!(TtsProviderImpl::classify_error(&err), "process_missing");
        let err = anyhow::anyhow!("failed to write text to TTS stdin");
        assert_eq!(TtsProviderImpl::classify_error(&err), "stdin_write_failed");
        let err = anyhow::anyhow!("TTS command `/bin/false` failed with status exit status: 1");
        assert_eq!(TtsProviderImpl::classify_error(&err), "exit_nonzero");
    }
}
