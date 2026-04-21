use serde::{Deserialize, Serialize};

use super::mapping::ActionMapping;
use super::target::ActionTarget;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ActionKind {
    Query,
    Speech,
    Ui,
    System,
    Automation,
    Unknown,
}

/// Internal phase model for an ongoing action. Kept small on purpose;
/// it backs both core state and the `phase` field of IPC events.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ActionPhase {
    Planned,
    Started,
    InProgress,
    Verifying,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ActionStatus {
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionPlannedPayload {
    pub action_id: String,
    pub action_kind: ActionKind,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub target: ActionTarget,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mapping: Option<ActionMapping>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionStartedPayload {
    pub action_id: String,
    pub phase: ActionPhase,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionProgressPayload {
    pub action_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub progress: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionStepPayload {
    pub action_id: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionVerificationPayload {
    pub action_id: String,
    pub title: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionCompletedPayload {
    pub action_id: String,
    pub status: ActionStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionFailedPayload {
    pub action_id: String,
    pub status: ActionStatus,
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionCancelledPayload {
    pub action_id: String,
    pub status: ActionStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_planned_payload() {
        let payload = ActionPlannedPayload {
            action_id: "act_000001".into(),
            action_kind: ActionKind::Query,
            title: "Process text request".into(),
            description: None,
            target: ActionTarget::unknown(),
            mapping: None,
        };
        let json = serde_json::to_string(&payload).unwrap();
        assert_eq!(
            json,
            r#"{"action_id":"act_000001","action_kind":"query","title":"Process text request","target":{"type":"unknown"}}"#
        );
    }

    #[test]
    fn serializes_failed_payload() {
        let payload = ActionFailedPayload {
            action_id: "act_000002".into(),
            status: ActionStatus::Failed,
            message: "ABrain command failed".into(),
            error: None,
        };
        let json = serde_json::to_string(&payload).unwrap();
        assert_eq!(
            json,
            r#"{"action_id":"act_000002","status":"failed","message":"ABrain command failed"}"#
        );
    }
}
