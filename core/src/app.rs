use anyhow::Result;
use serde::Serialize;
use tracing::warn;

use crate::adapters::abrain;
use crate::audio::{SttService, TtsService};
use crate::config::Config;

pub struct App {
    pub config: Config,
    pub tts: TtsService,
    pub stt: SttService,
}

#[derive(Debug, Clone, Serialize)]
pub struct StatusPayload {
    pub tts_enabled: bool,
    pub tts_available: bool,
    pub stt_enabled: bool,
    pub stt_available: bool,
    pub auto_speak: bool,
}

impl App {
    pub fn new(config: Config) -> Self {
        let tts = TtsService::new(&config.audio);
        let stt = SttService::new(&config.audio);
        Self { config, tts, stt }
    }

    pub async fn handle_text_query(&self, input: &str) -> Result<String> {
        abrain::run_task_with_cmd(&self.config.abrain_cmd, input).await
    }

    pub async fn handle_voice_once(&self) -> Result<String> {
        self.stt.listen_once().await
    }

    pub async fn handle_speak(&self, text: &str) -> Result<()> {
        self.tts.speak(text).await
    }

    pub async fn maybe_auto_speak(&self, text: &str) {
        if !self.config.audio.auto_speak || !self.tts.is_available() {
            return;
        }
        if let Err(err) = self.tts.speak(text).await {
            warn!(error = %err, "auto-speak TTS failed");
        }
    }

    pub fn build_status_payload(&self) -> StatusPayload {
        let tts = self.tts.state();
        let stt = self.stt.state();
        StatusPayload {
            tts_enabled: tts.enabled,
            tts_available: tts.available,
            stt_enabled: stt.enabled,
            stt_available: stt.available,
            auto_speak: self.config.audio.auto_speak,
        }
    }
}
