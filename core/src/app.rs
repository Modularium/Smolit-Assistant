use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::Result;
use serde::Serialize;
use tracing::warn;

use crate::adapters::abrain;
use crate::audio::{SttService, TtsService};
use crate::config::Config;
use crate::interaction::{
    CommandBackend, CommandBackendConfig, InteractionAction, InteractionExecutor,
    InteractionPolicy,
};
use crate::ipc::protocol::OutgoingMessage;

pub struct App {
    pub config: Config,
    pub tts: TtsService,
    pub stt: SttService,
    interaction: InteractionExecutor<CommandBackend>,
    action_counter: AtomicU64,
}

#[derive(Debug, Clone, Serialize)]
pub struct StatusPayload {
    pub tts_enabled: bool,
    pub tts_available: bool,
    pub stt_enabled: bool,
    pub stt_available: bool,
    pub auto_speak: bool,
    pub ipc_enabled: bool,
    pub interaction_enabled: bool,
    pub interaction_backend: String,
}

impl App {
    pub fn new(config: Config) -> Self {
        let tts = TtsService::new(&config.audio);
        let stt = SttService::new(&config.audio);

        let backend = CommandBackend::new(CommandBackendConfig {
            open_app_cmd_template: config.interaction.open_app_cmd_template.clone(),
        });
        let policy = InteractionPolicy {
            enabled: config.interaction.enabled,
            allow_open_application: config.interaction.allow_open_application,
            allow_type_text: config.interaction.allow_type_text,
            allow_shortcuts: config.interaction.allow_shortcuts,
            require_confirmation: config.interaction.require_confirmation,
        };
        let interaction = InteractionExecutor::new(backend, policy);

        Self {
            config,
            tts,
            stt,
            interaction,
            action_counter: AtomicU64::new(0),
        }
    }

    pub fn next_action_id(&self) -> String {
        let n = self.action_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("act_{n:06}")
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

    pub async fn execute_open_application(&self, name: &str) -> Vec<OutgoingMessage> {
        let action = InteractionAction::open_application(self.next_action_id(), name);
        self.interaction.execute(action).await
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
            ipc_enabled: self.config.ipc.enabled,
            interaction_enabled: self.config.interaction.enabled,
            interaction_backend: self.config.interaction.backend.clone(),
        }
    }
}
