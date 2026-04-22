//! Recovery model.
//!
//! The MVP does not implement an automatic recovery engine. Backends
//! and the executor instead **classify** failures via `RecoveryHint`
//! so future layers (or UI) can decide whether to retry, abort, prompt
//! the user, or mark the action as unavailable on this system.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecoveryHint {
    /// The operation is safe to retry (transient failure).
    Retry,
    /// The operation should be aborted; retrying will not help.
    Abort,
    /// The user should be asked (missing permission, ambiguous target).
    AskUser,
    /// The backend is structurally unable to perform this kind of
    /// action on this system (e.g. no display server).
    FallbackUnavailable,
}

impl RecoveryHint {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Retry => "retry",
            Self::Abort => "abort",
            Self::AskUser => "ask_user",
            Self::FallbackUnavailable => "fallback_unavailable",
        }
    }
}
