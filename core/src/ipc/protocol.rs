use serde::{Deserialize, Serialize};

use crate::actions::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionPlannedPayload,
    ActionProgressPayload, ActionStartedPayload, ActionStepPayload, ActionVerificationPayload,
};
use crate::app::StatusPayload;
use crate::approvals::{ApprovalRequest, ApprovalResolvedPayload, IncomingApprovalDecision};

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IncomingMessage {
    Ping,
    GetStatus,
    SubmitText {
        text: String,
    },
    SpeakText {
        text: String,
    },
    VoiceOnce,
    InteractionOpenApplication {
        application: String,
    },
    InteractionFocusWindow {
        target: InteractionFocusTarget,
    },
    ApprovalResponse {
        approval_id: String,
        decision: IncomingApprovalDecision,
    },
}

/// Target shape accepted by the `interaction_focus_window` IPC request.
/// Intentionally narrower than `ActionTarget` so the wire contract is
/// obvious: either "a window" (optionally scoped by app) or
/// "the focused window of this application". The richer `ActionTarget`
/// is still used for rendering downstream events.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InteractionFocusTarget {
    Window {
        /// Short display name (e.g. `"calendar"`). Accepted as an
        /// alias for `title` so the wire contract matches the
        /// `{"type":"window","name":"calendar"}` example in docs.
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        title: Option<String>,
        #[serde(default)]
        app: Option<String>,
    },
    Application {
        name: String,
    },
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
#[allow(dead_code)]
pub enum OutgoingMessage {
    Pong,
    Status { payload: StatusPayload },
    Thinking,
    Response { payload: ResponsePayload },
    Heard { payload: HeardPayload },
    Error { message: String },
    ActionPlanned { payload: ActionPlannedPayload },
    ActionStarted { payload: ActionStartedPayload },
    ActionProgress { payload: ActionProgressPayload },
    ActionStep { payload: ActionStepPayload },
    ActionVerification { payload: ActionVerificationPayload },
    ActionCompleted { payload: ActionCompletedPayload },
    ActionFailed { payload: ActionFailedPayload },
    ActionCancelled { payload: ActionCancelledPayload },
    ApprovalRequested { payload: ApprovalRequest },
    ApprovalResolved { payload: ApprovalResolvedPayload },
}

#[derive(Debug, Clone, Serialize)]
pub struct ResponsePayload {
    pub text: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct HeardPayload {
    pub text: String,
}

pub fn parse_incoming(raw: &str) -> Result<IncomingMessage, serde_json::Error> {
    serde_json::from_str(raw)
}

pub fn encode_outgoing(msg: &OutgoingMessage) -> String {
    serde_json::to_string(msg).unwrap_or_else(|err| {
        format!(
            "{{\"type\":\"error\",\"message\":\"failed to encode outgoing message: {err}\"}}"
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actions::{ActionKind, ActionPhase, ActionStatus, ActionTarget};

    #[test]
    fn parses_ping() {
        let msg = parse_incoming(r#"{"type":"ping"}"#).unwrap();
        assert!(matches!(msg, IncomingMessage::Ping));
    }

    #[test]
    fn parses_submit_text() {
        let msg = parse_incoming(r#"{"type":"submit_text","text":"hi"}"#).unwrap();
        match msg {
            IncomingMessage::SubmitText { text } => assert_eq!(text, "hi"),
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_voice_once() {
        let msg = parse_incoming(r#"{"type":"voice_once"}"#).unwrap();
        assert!(matches!(msg, IncomingMessage::VoiceOnce));
    }

    #[test]
    fn rejects_unknown() {
        assert!(parse_incoming(r#"{"type":"nope"}"#).is_err());
    }

    #[test]
    fn encodes_pong() {
        let encoded = encode_outgoing(&OutgoingMessage::Pong);
        assert_eq!(encoded, r#"{"type":"pong"}"#);
    }

    #[test]
    fn encodes_error() {
        let encoded = encode_outgoing(&OutgoingMessage::Error {
            message: "boom".into(),
        });
        assert_eq!(encoded, r#"{"type":"error","message":"boom"}"#);
    }

    #[test]
    fn encodes_response() {
        let encoded = encode_outgoing(&OutgoingMessage::Response {
            payload: ResponsePayload { text: "ok".into() },
        });
        assert_eq!(encoded, r#"{"type":"response","payload":{"text":"ok"}}"#);
    }

    #[test]
    fn encodes_action_planned() {
        let encoded = encode_outgoing(&OutgoingMessage::ActionPlanned {
            payload: ActionPlannedPayload {
                action_id: "act_000001".into(),
                action_kind: ActionKind::Query,
                title: "Process text request".into(),
                description: None,
                target: ActionTarget::unknown(),
                mapping: None,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"action_planned","payload":{"action_id":"act_000001","action_kind":"query","title":"Process text request","target":{"type":"unknown"}}}"#
        );
    }

    #[test]
    fn encodes_action_started() {
        let encoded = encode_outgoing(&OutgoingMessage::ActionStarted {
            payload: ActionStartedPayload {
                action_id: "act_000001".into(),
                phase: ActionPhase::Started,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"action_started","payload":{"action_id":"act_000001","phase":"started"}}"#
        );
    }

    #[test]
    fn encodes_action_failed() {
        let encoded = encode_outgoing(&OutgoingMessage::ActionFailed {
            payload: ActionFailedPayload {
                action_id: "act_000001".into(),
                status: ActionStatus::Failed,
                message: "ABrain command failed".into(),
                error: None,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"action_failed","payload":{"action_id":"act_000001","status":"failed","message":"ABrain command failed"}}"#
        );
    }
}
