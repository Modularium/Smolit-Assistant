//! Shared low-level types for the Desktop Interaction Layer.
//!
//! Only the common error enum lives here; richer types (actions,
//! backends, verification, recovery) have their own modules so that the
//! layer stays easy to extend backend-by-backend without a single
//! god-module.

use std::fmt;

/// Errors produced while executing an `InteractionAction` against a
/// backend. The variants are deliberately small and descriptive so they
/// can be mapped cleanly onto `action_failed` events and logs.
#[derive(Debug)]
pub enum InteractionError {
    /// The desktop interaction layer is disabled globally via config.
    LayerDisabled,
    /// The requested interaction kind is disabled via config (allow-list).
    ActionKindDisallowed(&'static str),
    /// The current backend cannot perform this kind of action yet. The
    /// architecture exposes the method, but no implementation has
    /// landed for this MVP.
    BackendUnsupported(&'static str),
    /// The action requires an explicit user confirmation and no
    /// confirmation channel is wired up yet.
    ConfirmationRequired,
    /// The backend attempted the operation but a clearly recoverable /
    /// pre-flight precondition was missing (e.g. no command configured).
    Preconditions(String),
    /// The backend attempted the operation and the underlying system
    /// command / API failed.
    BackendFailed(String),
}

impl fmt::Display for InteractionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::LayerDisabled => write!(f, "interaction layer is disabled"),
            Self::ActionKindDisallowed(kind) => {
                write!(f, "interaction kind `{kind}` is disallowed by configuration")
            }
            Self::BackendUnsupported(kind) => {
                write!(f, "interaction kind `{kind}` is not supported by the active backend")
            }
            Self::ConfirmationRequired => write!(
                f,
                "action requires user confirmation, but no confirmation channel is wired up yet"
            ),
            Self::Preconditions(msg) => write!(f, "preconditions not met: {msg}"),
            Self::BackendFailed(msg) => write!(f, "backend failed: {msg}"),
        }
    }
}

impl std::error::Error for InteractionError {}
