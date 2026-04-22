//! Desktop Interaction Layer (MVP).
//!
//! Core-internal module that models, executes, verifies and reports
//! desktop-level interactions (opening an app, focusing a window,
//! typing, shortcut). For this MVP phase only `open_application` is
//! wired through to a real backend — the rest are modelled as honest
//! `BackendUnsupported` hooks so the protocol can already describe
//! them and future backends can fill them in.
//!
//! Design intent:
//!   * separate *what* the assistant wants to do (`InteractionAction`)
//!     from *how* it gets done (`InteractionBackend`) from *whether it
//!     may be done* (`InteractionPolicy`).
//!   * emit Action Event Model v1 events as side-effects of execution
//!     so the UI can render progress without learning a second
//!     protocol.
//!   * stay conservative by default: the allow-list and the
//!     `require_confirmation` flag both lean toward "disabled".

#![allow(dead_code)]

pub mod accessibility;
pub mod action;
pub mod backend;
pub mod executor;
pub mod recovery;
pub mod types;
pub mod verifier;

#[allow(unused_imports)]
pub use accessibility::{
    AccessibilityDiscovery, AccessibilityItem, AccessibilityProbe, discover_top_level,
    inspect_target,
};
#[allow(unused_imports)]
pub use action::{InteractionAction, InteractionKind, InteractionPayload};
#[allow(unused_imports)]
pub use backend::{CommandBackend, CommandBackendConfig, InteractionBackend};
pub use executor::{InteractionExecutor, InteractionPolicy};
#[allow(unused_imports)]
pub use recovery::RecoveryHint;
#[allow(unused_imports)]
pub use types::InteractionError;
#[allow(unused_imports)]
pub use verifier::{VerificationConfidence, VerificationResult};
