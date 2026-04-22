//! Interaction executor.
//!
//! Takes an `InteractionAction`, a configured backend, and a
//! `InteractionConfig`. Enforces allow-list and confirmation policy,
//! dispatches to the backend, turns verification results and errors
//! into a sequence of Action Events.
//!
//! The executor is transport-agnostic: it returns a
//! `Vec<OutgoingMessage>` just like the existing IPC handlers, so the
//! server can splice them into the response stream.

use tracing::info;

use crate::actions::{
    ActionCompletedPayload, ActionFailedPayload, ActionKind, ActionPhase, ActionPlannedPayload,
    ActionStartedPayload, ActionStatus, ActionStepPayload, ActionVerificationPayload,
};
use crate::ipc::protocol::OutgoingMessage;

use super::action::{InteractionAction, InteractionKind, InteractionPayload};
use super::backend::InteractionBackend;
use super::recovery::RecoveryHint;
use super::types::InteractionError;
use super::verifier::{VerificationConfidence, VerificationResult};

/// Runtime-configurable policy for the interaction layer. Built from
/// `InteractionConfig` in `crate::config`.
#[derive(Debug, Clone)]
pub struct InteractionPolicy {
    pub enabled: bool,
    pub allow_open_application: bool,
    pub allow_type_text: bool,
    pub allow_shortcuts: bool,
    /// When true, any action with `requires_confirmation=true` is
    /// refused until a confirmation channel is wired up (Phase 8b).
    pub require_confirmation: bool,
}

impl InteractionPolicy {
    pub fn allows(&self, kind: InteractionKind) -> Result<(), InteractionError> {
        if !self.enabled {
            return Err(InteractionError::LayerDisabled);
        }
        match kind {
            InteractionKind::OpenApplication if !self.allow_open_application => {
                Err(InteractionError::ActionKindDisallowed("open_application"))
            }
            InteractionKind::TypeText if !self.allow_type_text => {
                Err(InteractionError::ActionKindDisallowed("type_text"))
            }
            InteractionKind::SendShortcut if !self.allow_shortcuts => {
                Err(InteractionError::ActionKindDisallowed("send_shortcut"))
            }
            _ => Ok(()),
        }
    }
}

pub struct InteractionExecutor<B: InteractionBackend> {
    backend: B,
    policy: InteractionPolicy,
}

impl<B: InteractionBackend> InteractionExecutor<B> {
    pub fn new(backend: B, policy: InteractionPolicy) -> Self {
        Self { backend, policy }
    }

    /// Read-only accessor so app-level orchestration (approval flow)
    /// can consult the active policy without duplicating fields.
    pub fn policy(&self) -> &InteractionPolicy {
        &self.policy
    }

    /// Builds the `action_planned` event for `action` without running
    /// anything. Used by orchestration layers that want to emit
    /// planned before deciding whether to ask for approval.
    pub fn plan_event(&self, action: &InteractionAction) -> OutgoingMessage {
        planned(action)
    }

    /// Builds a policy-refusal sequence (`action_started` +
    /// `action_failed`) for a `planned` that was already emitted.
    pub fn refusal_events(
        &self,
        action_id: &str,
        err: &InteractionError,
    ) -> Vec<OutgoingMessage> {
        let hint = recovery_hint_for(err);
        vec![
            started(action_id),
            failed(action_id, &format!("{err}"), hint),
        ]
    }

    /// Runs the action as if approval had already been granted. Emits
    /// `started`, the two `step` events, the backend call, and the
    /// final `verification` + `completed` / `failed` pair.
    ///
    /// Does **not** check `policy.allows` or `requires_confirmation`
    /// again — the caller is expected to have done so before issuing
    /// an approval.
    pub async fn run_approved(&self, action: InteractionAction) -> Vec<OutgoingMessage> {
        let mut out = Vec::with_capacity(5);
        out.push(started(&action.action_id));
        out.push(step(&action.action_id, "Resolving target"));
        out.push(step(
            &action.action_id,
            step_title_for_kind(action.kind()),
        ));

        let result = match &action.payload {
            InteractionPayload::OpenApplication { name } => {
                self.backend.open_application(&action, name).await
            }
            InteractionPayload::TypeText { text } => {
                self.backend.type_text(&action, text).await
            }
            InteractionPayload::SendShortcut { combo } => {
                self.backend.send_shortcut(&action, combo).await
            }
            InteractionPayload::Noop => Ok(VerificationResult::verified("No-op")),
        };

        match result {
            Ok(verification) => {
                out.push(verification_event(&action.action_id, &verification));
                out.push(completed(&action.action_id, &verification));
                info!(
                    action_id = %action.action_id,
                    backend = self.backend.name(),
                    kind = action.kind().as_str(),
                    confidence = verification.confidence.as_str(),
                    "interaction completed"
                );
            }
            Err(err) => {
                let hint = recovery_hint_for(&err);
                let msg = format!("{err}");
                out.push(failed(&action.action_id, &msg, hint));
                info!(
                    action_id = %action.action_id,
                    backend = self.backend.name(),
                    kind = action.kind().as_str(),
                    recovery = hint.as_str(),
                    error = %msg,
                    "interaction failed"
                );
            }
        }

        out
    }

    /// Dispatches `action`, emits Action Events, and returns them as a
    /// flat vector suitable for sending over the IPC stream.
    pub async fn execute(&self, action: InteractionAction) -> Vec<OutgoingMessage> {
        let mut out = Vec::with_capacity(6);

        out.push(planned(&action));
        out.push(started(&action.action_id));

        if let Err(err) = self.policy.allows(action.kind()) {
            let hint = recovery_hint_for(&err);
            out.push(failed(&action.action_id, &format!("{err}"), hint));
            return out;
        }

        if action.requires_confirmation && self.policy.require_confirmation {
            let err = InteractionError::ConfirmationRequired;
            let hint = recovery_hint_for(&err);
            out.push(failed(&action.action_id, &format!("{err}"), hint));
            return out;
        }

        out.push(step(&action.action_id, "Resolving target"));
        out.push(step(
            &action.action_id,
            step_title_for_kind(action.kind()),
        ));

        let result = match &action.payload {
            InteractionPayload::OpenApplication { name } => {
                self.backend.open_application(&action, name).await
            }
            InteractionPayload::TypeText { text } => {
                self.backend.type_text(&action, text).await
            }
            InteractionPayload::SendShortcut { combo } => {
                self.backend.send_shortcut(&action, combo).await
            }
            InteractionPayload::Noop => Ok(VerificationResult::verified("No-op")),
        };

        match result {
            Ok(verification) => {
                out.push(verification_event(&action.action_id, &verification));
                out.push(completed(&action.action_id, &verification));
                info!(
                    action_id = %action.action_id,
                    backend = self.backend.name(),
                    kind = action.kind().as_str(),
                    confidence = verification.confidence.as_str(),
                    "interaction completed"
                );
            }
            Err(err) => {
                let hint = recovery_hint_for(&err);
                let msg = format!("{err}");
                out.push(failed(&action.action_id, &msg, hint));
                info!(
                    action_id = %action.action_id,
                    backend = self.backend.name(),
                    kind = action.kind().as_str(),
                    recovery = hint.as_str(),
                    error = %msg,
                    "interaction failed"
                );
            }
        }

        out
    }
}

fn step_title_for_kind(kind: InteractionKind) -> &'static str {
    match kind {
        InteractionKind::OpenApplication => "Opening application",
        InteractionKind::TypeText => "Typing text",
        InteractionKind::SendShortcut => "Sending shortcut",
        InteractionKind::Noop => "No-op",
        InteractionKind::Unknown => "Unknown operation",
    }
}

fn recovery_hint_for(err: &InteractionError) -> RecoveryHint {
    match err {
        InteractionError::LayerDisabled
        | InteractionError::ActionKindDisallowed(_)
        | InteractionError::BackendUnsupported(_) => RecoveryHint::FallbackUnavailable,
        InteractionError::ConfirmationRequired => RecoveryHint::AskUser,
        InteractionError::Preconditions(_) => RecoveryHint::Abort,
        InteractionError::BackendFailed(_) => RecoveryHint::Retry,
    }
}

fn planned(action: &InteractionAction) -> OutgoingMessage {
    OutgoingMessage::ActionPlanned {
        payload: ActionPlannedPayload {
            action_id: action.action_id.clone(),
            action_kind: ActionKind::Automation,
            title: action.title.clone(),
            description: Some(format!("interaction:{}", action.kind().as_str())),
            target: action.target.clone(),
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

fn verification_event(action_id: &str, verification: &VerificationResult) -> OutgoingMessage {
    let prefix = match verification.confidence {
        VerificationConfidence::Verified => "Verified",
        VerificationConfidence::Uncertain => "Best-effort",
        VerificationConfidence::Failed => "Verification failed",
    };
    OutgoingMessage::ActionVerification {
        payload: ActionVerificationPayload {
            action_id: action_id.to_string(),
            title: format!("{prefix}: {}", verification.title),
        },
    }
}

fn completed(action_id: &str, verification: &VerificationResult) -> OutgoingMessage {
    let message = match verification.confidence {
        VerificationConfidence::Verified => verification.message.clone(),
        VerificationConfidence::Uncertain => Some(
            verification
                .message
                .clone()
                .unwrap_or_else(|| "completed (verification uncertain)".into()),
        ),
        VerificationConfidence::Failed => verification.message.clone(),
    };
    OutgoingMessage::ActionCompleted {
        payload: ActionCompletedPayload {
            action_id: action_id.to_string(),
            status: ActionStatus::Completed,
            message,
        },
    }
}

fn failed(action_id: &str, message: &str, hint: RecoveryHint) -> OutgoingMessage {
    OutgoingMessage::ActionFailed {
        payload: ActionFailedPayload {
            action_id: action_id.to_string(),
            status: ActionStatus::Failed,
            message: message.to_string(),
            error: Some(format!("recovery_hint={}", hint.as_str())),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::interaction::backend::{CommandBackend, CommandBackendConfig};

    fn policy_all_allowed() -> InteractionPolicy {
        InteractionPolicy {
            enabled: true,
            allow_open_application: true,
            allow_type_text: true,
            allow_shortcuts: true,
            require_confirmation: true,
        }
    }

    fn policy_disabled() -> InteractionPolicy {
        InteractionPolicy {
            enabled: false,
            allow_open_application: true,
            allow_type_text: true,
            allow_shortcuts: true,
            require_confirmation: true,
        }
    }

    fn backend_with_true() -> CommandBackend {
        CommandBackend::new(CommandBackendConfig {
            open_app_cmd_template: Some("/bin/true".into()),
            ..CommandBackendConfig::default()
        })
    }

    fn backend_without_template() -> CommandBackend {
        CommandBackend::new(CommandBackendConfig::default())
    }

    fn find_first<'a>(msgs: &'a [OutgoingMessage], pat: &str) -> &'a OutgoingMessage {
        msgs.iter()
            .find(|m| serde_json::to_string(m).unwrap().contains(pat))
            .unwrap_or_else(|| panic!("no message with {pat} in {msgs:?}"))
    }

    #[tokio::test]
    async fn layer_disabled_emits_failed() {
        let exec = InteractionExecutor::new(backend_with_true(), policy_disabled());
        let action = InteractionAction::open_application("act_000001", "calendar");
        let out = exec.execute(action).await;
        assert!(matches!(out[0], OutgoingMessage::ActionPlanned { .. }));
        assert!(matches!(out[1], OutgoingMessage::ActionStarted { .. }));
        find_first(&out, r#""type":"action_failed""#);
        find_first(&out, "interaction layer is disabled");
    }

    #[tokio::test]
    async fn open_application_disallowed_emits_failed() {
        let policy = InteractionPolicy {
            allow_open_application: false,
            ..policy_all_allowed()
        };
        let exec = InteractionExecutor::new(backend_with_true(), policy);
        let action = InteractionAction::open_application("act_000002", "calendar");
        let out = exec.execute(action).await;
        find_first(&out, r#""type":"action_failed""#);
        find_first(&out, "open_application");
    }

    #[tokio::test]
    async fn open_application_with_template_emits_verification_and_completed() {
        let exec = InteractionExecutor::new(backend_with_true(), policy_all_allowed());
        let action = InteractionAction::open_application("act_000003", "calendar");
        let out = exec.execute(action).await;

        // Sequence: planned, started, step(resolving), step(opening),
        //           verification, completed.
        assert!(matches!(out[0], OutgoingMessage::ActionPlanned { .. }));
        assert!(matches!(out[1], OutgoingMessage::ActionStarted { .. }));
        find_first(&out, r#""type":"action_step""#);
        find_first(&out, r#""type":"action_verification""#);
        find_first(&out, "Best-effort");
        find_first(&out, r#""type":"action_completed""#);
    }

    #[tokio::test]
    async fn open_application_without_template_emits_failed_with_recovery_hint() {
        let exec = InteractionExecutor::new(backend_without_template(), policy_all_allowed());
        let action = InteractionAction::open_application("act_000004", "calendar");
        let out = exec.execute(action).await;
        find_first(&out, r#""type":"action_failed""#);
        find_first(&out, "recovery_hint=abort");
    }

    #[tokio::test]
    async fn type_text_action_is_unsupported_at_backend() {
        let policy = InteractionPolicy {
            allow_type_text: true,
            ..policy_all_allowed()
        };
        let exec = InteractionExecutor::new(backend_with_true(), policy);
        let action = InteractionAction {
            action_id: "act_000005".into(),
            title: "Type hello".into(),
            target: crate::actions::ActionTarget::unknown(),
            payload: InteractionPayload::TypeText {
                text: "hello".into(),
            },
            requires_confirmation: false,
            trusted_only: false,
        };
        let out = exec.execute(action).await;
        find_first(&out, r#""type":"action_failed""#);
        find_first(&out, "type_text");
        find_first(&out, "recovery_hint=fallback_unavailable");
    }
}
