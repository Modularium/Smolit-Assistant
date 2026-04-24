//! Action Event Model v1.
//!
//! Standardised event primitives for core → UI action reporting. Some of
//! the types here are deliberately part of the v1 API surface even if
//! they are not yet emitted by a concrete handler (e.g. progress,
//! verification, cancellation, symbolic mapping). They exist so that UI
//! and future automation adapters can rely on a stable shape.
#![allow(dead_code)]

pub mod event;
pub mod mapping;
pub mod plan;
pub mod target;

pub use event::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionKind, ActionPhase,
    ActionPlannedPayload, ActionProgressPayload, ActionStartedPayload, ActionStatus,
    ActionStepPayload, ActionVerificationPayload,
};
#[allow(unused_imports)]
pub use mapping::{ActionMapping, ActionSpace};
pub use plan::{DemoPlan, DemoPlanStatus};
#[allow(unused_imports)]
pub use plan::{
    DEFAULT_DEMO_KIND, DEMO_KIND_ECHO, DEMO_KIND_NOOP, DEMO_KIND_WAIT, KNOWN_DEMO_KINDS,
    sanitize_kind,
};
pub use target::ActionTarget;
