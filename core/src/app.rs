use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use anyhow::Result;
use serde::Serialize;
use tokio::sync::broadcast;
use tokio::time::timeout;
use tracing::{info, warn};

use crate::actions::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionKind, ActionPhase,
    ActionPlannedPayload, ActionStartedPayload, ActionStatus, ActionStepPayload, ActionTarget,
    ActionVerificationPayload,
};
use crate::adapters::abrain;
use crate::approvals::{
    ApprovalDecision, ApprovalRequest, ApprovalResolvedPayload, PendingApprovalError,
    PendingApprovalRegistry,
};
use crate::audio::{SttService, TtsService};
use crate::config::Config;
use crate::interaction::{
    AccessibilityDiscovery, AccessibilityProbe, CommandBackend, CommandBackendConfig,
    InteractionAction, InteractionExecutor, InteractionKind, InteractionPolicy, discover_top_level,
    inspect_target,
};
use crate::ipc::protocol::{InteractionFocusTarget, OutgoingMessage};

const EVENTS_CHANNEL_CAPACITY: usize = 256;

pub struct App {
    pub config: Config,
    pub tts: TtsService,
    pub stt: SttService,
    interaction: InteractionExecutor<CommandBackend>,
    action_counter: AtomicU64,
    approval_counter: AtomicU64,
    pending_approvals: Arc<PendingApprovalRegistry>,
    events_tx: broadcast::Sender<OutgoingMessage>,
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
    pub approval_timeout_seconds: u64,
    /// Honest, environment-based verdict from the AT-SPI spike at
    /// core start-up. One of `"uncertain"`, `"unavailable"`,
    /// `"failed"`. See
    /// [`crate::interaction::AccessibilityProbe`] for semantics.
    pub accessibility_probe: String,
    /// Short free-form reason accompanying `accessibility_probe`.
    pub accessibility_probe_reason: String,
}

impl App {
    pub fn new(config: Config) -> Self {
        let tts = TtsService::new(&config.audio);
        let stt = SttService::new(&config.audio);

        let backend = CommandBackend::new(CommandBackendConfig {
            open_app_cmd_template: config.interaction.open_app_cmd_template.clone(),
            focus_window_cmd_template: config.interaction.focus_window_cmd_template.clone(),
        });
        let policy = InteractionPolicy {
            enabled: config.interaction.enabled,
            allow_open_application: config.interaction.allow_open_application,
            allow_focus_window: config.interaction.allow_focus_window,
            allow_type_text: config.interaction.allow_type_text,
            allow_shortcuts: config.interaction.allow_shortcuts,
            require_confirmation: config.interaction.require_confirmation,
        };
        let interaction = InteractionExecutor::new(backend, policy);
        let (events_tx, _) = broadcast::channel(EVENTS_CHANNEL_CAPACITY);

        Self {
            config,
            tts,
            stt,
            interaction,
            action_counter: AtomicU64::new(0),
            approval_counter: AtomicU64::new(0),
            pending_approvals: Arc::new(PendingApprovalRegistry::new()),
            events_tx,
        }
    }

    pub fn next_action_id(&self) -> String {
        let n = self.action_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("act_{n:06}")
    }

    fn next_approval_id(&self) -> String {
        let n = self.approval_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("apr_{n:06}")
    }

    /// Subscribe to async continuation events (approval outcomes,
    /// background-task progress). Used by IPC handlers to forward
    /// these to connected WS clients.
    pub fn subscribe_events(&self) -> broadcast::Receiver<OutgoingMessage> {
        self.events_tx.subscribe()
    }

    fn broadcast(&self, msg: OutgoingMessage) {
        // Ignore send errors: `broadcast::Sender::send` only errors
        // when there are zero receivers, which is a legitimate state
        // (no UI connected) rather than a bug.
        let _ = self.events_tx.send(msg);
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

    /// Deliver a decision submitted by the UI to the matching pending
    /// approval. Returns an error message suitable for an IPC
    /// `error` envelope when the approval id is unknown or stale.
    pub fn resolve_approval(
        &self,
        approval_id: &str,
        decision: ApprovalDecision,
    ) -> Result<(), String> {
        match self.pending_approvals.resolve(approval_id, decision) {
            Ok(()) => Ok(()),
            Err(PendingApprovalError::Unknown) => Err(format!(
                "no pending approval with id {approval_id} (already resolved or unknown)"
            )),
            Err(PendingApprovalError::Closed) => Err(format!(
                "approval {approval_id} was already closed"
            )),
        }
    }

    /// Entry point for IPC handlers. Plans the interaction, checks
    /// policy, and either:
    ///   * refuses the action (layer disabled / kind disallowed),
    ///   * runs the backend directly (no confirmation required), or
    ///   * emits `approval_requested` and spawns a background task
    ///     that awaits the UI decision (or a timeout) before running
    ///     the backend.
    ///
    /// Returns the *immediate* Action Events the IPC handler should
    /// flush to the caller. Any further continuation events (backend
    /// progress after approval, `approval_resolved`) arrive via the
    /// broadcast channel.
    pub async fn dispatch_interaction(
        self: &Arc<Self>,
        action: InteractionAction,
    ) -> Vec<OutgoingMessage> {
        let mut out = Vec::with_capacity(3);
        out.push(self.interaction.plan_event(&action));

        if let Err(err) = self.interaction.policy().allows(action.kind()) {
            out.extend(self.interaction.refusal_events(&action.action_id, &err));
            return out;
        }

        let needs_approval =
            action.requires_confirmation && self.interaction.policy().require_confirmation;

        if !needs_approval {
            out.extend(self.interaction.run_approved(action).await);
            return out;
        }

        let approval_id = self.next_approval_id();
        let timeout_seconds = self.config.approval.timeout_seconds;
        let request = ApprovalRequest {
            approval_id: approval_id.clone(),
            action_id: action.action_id.clone(),
            action_kind: action.kind(),
            title: action.title.clone(),
            message: approval_message(&action),
            target: action.target.clone(),
            reason: None,
            timeout_seconds,
        };
        let rx = self.pending_approvals.register(&approval_id);
        out.push(OutgoingMessage::ApprovalRequested { payload: request });

        let app = Arc::clone(self);
        tokio::spawn(async move {
            app.await_and_continue(action, approval_id, rx, timeout_seconds)
                .await;
        });

        out
    }

    async fn await_and_continue(
        self: Arc<Self>,
        action: InteractionAction,
        approval_id: String,
        rx: tokio::sync::oneshot::Receiver<ApprovalDecision>,
        timeout_seconds: u64,
    ) {
        let decision = match timeout(Duration::from_secs(timeout_seconds), rx).await {
            Ok(Ok(decision)) => decision,
            Ok(Err(_)) => {
                // Sender dropped without sending — treat as cancelled.
                ApprovalDecision::Cancelled
            }
            Err(_) => {
                // Timed out: remove the pending entry ourselves so any
                // late `approval_response` is rejected as Unknown.
                let _ = self.pending_approvals.take(&approval_id);
                ApprovalDecision::TimedOut
            }
        };

        info!(
            approval_id = %approval_id,
            action_id = %action.action_id,
            decision = decision.as_str(),
            "approval resolved"
        );

        self.broadcast(OutgoingMessage::ApprovalResolved {
            payload: ApprovalResolvedPayload {
                approval_id: approval_id.clone(),
                action_id: action.action_id.clone(),
                decision: decision.as_str().to_string(),
            },
        });

        match decision {
            ApprovalDecision::Approved => {
                let msgs = self.interaction.run_approved(action).await;
                for msg in msgs {
                    self.broadcast(msg);
                }
            }
            ApprovalDecision::Denied
            | ApprovalDecision::Cancelled
            | ApprovalDecision::TimedOut => {
                let message = match decision {
                    ApprovalDecision::Denied => "Action denied by user",
                    ApprovalDecision::Cancelled => "Action cancelled",
                    ApprovalDecision::TimedOut => "Approval timed out",
                    ApprovalDecision::Approved => unreachable!(),
                };
                self.broadcast(OutgoingMessage::ActionCancelled {
                    payload: ActionCancelledPayload {
                        action_id: action.action_id.clone(),
                        status: ActionStatus::Cancelled,
                        message: Some(message.to_string()),
                    },
                });
            }
        }
    }

    pub async fn execute_open_application(
        self: &Arc<Self>,
        name: &str,
    ) -> Vec<OutgoingMessage> {
        let mut action = InteractionAction::open_application(self.next_action_id(), name);
        // `open_application` is the first action that goes through the
        // approval flow — flip the confirmation flag here rather than
        // inside the factory so pure executor tests stay deterministic.
        action.requires_confirmation = true;
        self.dispatch_interaction(action).await
    }

    /// Run the environment-based accessibility probe and wrap the
    /// result into a small Action-Event sequence plus a dedicated
    /// `accessibility_probe_result` envelope. Emission is read-only
    /// and does not require approval — the probe never touches the
    /// user's desktop.
    pub async fn probe_accessibility(self: &Arc<Self>) -> Vec<OutgoingMessage> {
        let action_id = self.next_action_id();
        let probe = AccessibilityProbe::detect();
        let reason = probe.reason().to_string();
        let status = probe.status_str();

        let mut out = Vec::with_capacity(6);
        out.push(planned(
            &action_id,
            ActionKind::System,
            "Probe accessibility backend",
            ActionTarget::unknown(),
        ));
        out.push(started(&action_id));
        out.push(step(&action_id, "Checking session environment"));
        out.push(OutgoingMessage::ActionVerification {
            payload: ActionVerificationPayload {
                action_id: action_id.clone(),
                title: format!("Probe: {status}"),
            },
        });
        out.push(OutgoingMessage::AccessibilityProbeResult {
            payload: probe.clone(),
        });
        out.push(OutgoingMessage::ActionCompleted {
            payload: ActionCompletedPayload {
                action_id,
                status: ActionStatus::Completed,
                message: Some(format!("{status}: {reason}")),
            },
        });
        out
    }

    /// Run the accessibility discovery / inspection spike. When `hint`
    /// is provided the spike inspects that symbolic target; otherwise
    /// it attempts a top-level discovery. In both cases the actual
    /// RPC walk is not yet wired up, so honest `uncertain` /
    /// `unavailable` results are expected.
    pub async fn discover_accessibility(
        self: &Arc<Self>,
        hint: Option<String>,
    ) -> Vec<OutgoingMessage> {
        let action_id = self.next_action_id();
        let trimmed_hint = hint
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string);

        let (title, step_label) = match &trimmed_hint {
            Some(name) => (
                format!("Inspect accessible target `{name}`"),
                format!("Inspecting `{name}` via accessibility probe"),
            ),
            None => (
                "Discover top-level accessibles".to_string(),
                "Discovering top-level accessibles via AT-SPI probe".to_string(),
            ),
        };

        let target = match &trimmed_hint {
            Some(name) => ActionTarget::application(name.clone()),
            None => ActionTarget::unknown(),
        };

        let result = match &trimmed_hint {
            Some(name) => inspect_target(name),
            None => discover_top_level(),
        };

        let status = result.status_str();
        let reason = result.reason().to_string();

        let mut out = Vec::with_capacity(7);
        out.push(planned(&action_id, ActionKind::System, &title, target));
        out.push(started(&action_id));
        out.push(step(&action_id, "Probing accessibility backend"));
        out.push(step(&action_id, &step_label));
        out.push(OutgoingMessage::ActionVerification {
            payload: ActionVerificationPayload {
                action_id: action_id.clone(),
                title: format!("Discovery: {status}"),
            },
        });
        out.push(OutgoingMessage::AccessibilityDiscoveryResult {
            payload: result.clone(),
        });

        match &result {
            AccessibilityDiscovery::Uncertain { .. } => {
                out.push(OutgoingMessage::ActionCompleted {
                    payload: ActionCompletedPayload {
                        action_id,
                        status: ActionStatus::Completed,
                        message: Some(format!("{status}: {reason}")),
                    },
                });
            }
            AccessibilityDiscovery::Unavailable { .. }
            | AccessibilityDiscovery::Failed { .. } => {
                out.push(OutgoingMessage::ActionFailed {
                    payload: ActionFailedPayload {
                        action_id,
                        status: ActionStatus::Failed,
                        message: format!("{status}: {reason}"),
                        error: Some("recovery_hint=fallback_unavailable".to_string()),
                    },
                });
            }
        }
        out
    }

    pub async fn execute_focus_window(
        self: &Arc<Self>,
        target: InteractionFocusTarget,
    ) -> Vec<OutgoingMessage> {
        let (title, app) = match target {
            InteractionFocusTarget::Window { name, title, app } => {
                // Accept either `name` (per-spec example) or `title`
                // as the window title — `title` takes precedence when
                // both are provided.
                (title.or(name), app)
            }
            InteractionFocusTarget::Application { name } => (None, Some(name)),
        };
        let mut action = InteractionAction::focus_window(self.next_action_id(), title, app);
        action.requires_confirmation = true;
        self.dispatch_interaction(action).await
    }

    pub fn build_status_payload(&self) -> StatusPayload {
        let tts = self.tts.state();
        let stt = self.stt.state();
        let probe = AccessibilityProbe::detect();
        StatusPayload {
            tts_enabled: tts.enabled,
            tts_available: tts.available,
            stt_enabled: stt.enabled,
            stt_available: stt.available,
            auto_speak: self.config.audio.auto_speak,
            ipc_enabled: self.config.ipc.enabled,
            interaction_enabled: self.config.interaction.enabled,
            interaction_backend: self.config.interaction.backend.clone(),
            approval_timeout_seconds: self.config.approval.timeout_seconds,
            accessibility_probe: probe.status_str().to_string(),
            accessibility_probe_reason: probe.reason().to_string(),
        }
    }
}

fn planned(
    action_id: &str,
    kind: ActionKind,
    title: &str,
    target: ActionTarget,
) -> OutgoingMessage {
    OutgoingMessage::ActionPlanned {
        payload: ActionPlannedPayload {
            action_id: action_id.to_string(),
            action_kind: kind,
            title: title.to_string(),
            description: None,
            target,
            mapping: None,
        },
    }
}

fn started(action_id: &str) -> OutgoingMessage {
    OutgoingMessage::ActionStarted {
        payload: ActionStartedPayload {
            action_id: action_id.to_string(),
            phase: ActionPhase::Started,
        },
    }
}

fn step(action_id: &str, title: &str) -> OutgoingMessage {
    OutgoingMessage::ActionStep {
        payload: ActionStepPayload {
            action_id: action_id.to_string(),
            title: title.to_string(),
            description: None,
        },
    }
}

fn approval_message(action: &InteractionAction) -> String {
    match action.kind() {
        InteractionKind::OpenApplication => format!("Smolit möchte {0}", action.title.to_lowercase()),
        InteractionKind::FocusWindow => {
            let label = action
                .title
                .strip_prefix("Focus ")
                .unwrap_or(&action.title);
            format!("Smolit möchte das Fenster \"{label}\" fokussieren.")
        }
        InteractionKind::TypeText => format!("Smolit möchte Text eingeben: {}", action.title),
        InteractionKind::SendShortcut => {
            format!("Smolit möchte einen Shortcut senden: {}", action.title)
        }
        InteractionKind::Noop | InteractionKind::Unknown => {
            format!("Confirm {kind}: {title}",
                kind = action.kind().as_str(),
                title = action.title
            )
        }
    }
}
