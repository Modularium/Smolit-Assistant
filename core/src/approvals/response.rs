//! Inbound approval decisions (UI → core) and the canonical internal
//! `ApprovalDecision` enum used to settle a pending approval.
//!
//! `IncomingApprovalDecision` is intentionally narrower than the full
//! `ApprovalDecision` — a remote peer cannot signal "timed out" since
//! timeouts are strictly a core-internal event.

use serde::{Deserialize, Serialize};

/// Final outcome of a pending approval. Produced either by a UI
/// response, by a core-side cancellation, or by a timeout watchdog.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApprovalDecision {
    Approved,
    Denied,
    Cancelled,
    TimedOut,
}

impl ApprovalDecision {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Approved => "approved",
            Self::Denied => "denied",
            Self::Cancelled => "cancelled",
            Self::TimedOut => "timed_out",
        }
    }
}

/// Subset of `ApprovalDecision` that clients are allowed to send over
/// IPC. The core maps each variant onto the internal enum.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum IncomingApprovalDecision {
    Approved,
    Denied,
    Cancelled,
}

impl IncomingApprovalDecision {
    pub fn to_decision(self) -> ApprovalDecision {
        match self {
            Self::Approved => ApprovalDecision::Approved,
            Self::Denied => ApprovalDecision::Denied,
            Self::Cancelled => ApprovalDecision::Cancelled,
        }
    }
}
