//! Approval / Confirmation Flow (MVP).
//!
//! When a core-side action (today: the Desktop Interaction Layer)
//! declares `requires_confirmation=true` and the active policy also
//! requires confirmation, the core does not silently refuse anymore.
//! Instead it:
//!
//!   1. emits the planned Action Event,
//!   2. emits an `approval_requested` IPC message describing the pending
//!      decision, and
//!   3. waits for a matching `approval_response` message (or a timeout)
//!      before running the backend.
//!
//! This module owns the shared approval data model plus a small pending
//! registry (`approval_id → oneshot sender`). It is deliberately narrow:
//! no persistence, no remembered decisions, no multi-user semantics.

#![allow(dead_code)]

pub mod request;
pub mod response;
pub mod state;

pub use request::{ApprovalRequest, ApprovalResolvedPayload};
pub use response::{ApprovalDecision, IncomingApprovalDecision};
pub use state::{PendingApprovalError, PendingApprovalRegistry};
