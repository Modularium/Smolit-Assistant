//! Outbound approval data (core → UI).
//!
//! `ApprovalRequest` is the payload of the `approval_requested`
//! IPC message. It is deliberately descriptive so the UI can render a
//! banner without having to re-derive the action's meaning.
//!
//! `ApprovalResolvedPayload` is the payload of the `approval_resolved`
//! IPC message. It simply echoes the final decision back to listeners.

use serde::{Deserialize, Serialize};

use crate::actions::ActionTarget;
use crate::interaction::{InteractionKind, SelectedTarget};

/// Describes a pending approval as presented to the UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalRequest {
    pub approval_id: String,
    pub action_id: String,
    pub action_kind: InteractionKind,
    pub title: String,
    pub message: String,
    pub target: ActionTarget,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    pub timeout_seconds: u64,
    /// Snapshot of the current Interaction target at the moment the
    /// approval was requested, when one was held. Purely descriptive —
    /// the UI renders it, the core does not derive additional
    /// permissions from it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_target: Option<SelectedTarget>,
}

/// Echoes the final decision for a given approval back to the UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalResolvedPayload {
    pub approval_id: String,
    pub action_id: String,
    /// One of `approved`, `denied`, `cancelled`, `timed_out`.
    pub decision: String,
}
