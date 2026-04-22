//! Verification model.
//!
//! Each interaction result carries a verification outcome. The MVP does
//! **not** try to prove success (no window probing, no OCR, no a11y
//! trees); it just lets each backend admit how sure it is. This keeps
//! the protocol honest and gives the UI a clear spot to render
//! "uncertain" / "best-effort" badges.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VerificationConfidence {
    /// The backend has positive evidence that the action took effect.
    Verified,
    /// The backend performed the operation but cannot confirm the
    /// outcome — use this for MVP `open_application` where we spawn a
    /// command but never inspect the resulting window stack.
    Uncertain,
    /// The backend is certain the action did *not* take effect.
    Failed,
}

impl VerificationConfidence {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Verified => "verified",
            Self::Uncertain => "uncertain",
            Self::Failed => "failed",
        }
    }
}

/// Outcome of an interaction attempt. The `title` is reused as the
/// `action_verification` step title on the IPC bus.
#[derive(Debug, Clone)]
pub struct VerificationResult {
    pub confidence: VerificationConfidence,
    pub title: String,
    pub message: Option<String>,
}

impl VerificationResult {
    pub fn verified(title: impl Into<String>) -> Self {
        Self {
            confidence: VerificationConfidence::Verified,
            title: title.into(),
            message: None,
        }
    }

    pub fn uncertain(title: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            confidence: VerificationConfidence::Uncertain,
            title: title.into(),
            message: Some(message.into()),
        }
    }

    pub fn failed(title: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            confidence: VerificationConfidence::Failed,
            title: title.into(),
            message: Some(message.into()),
        }
    }
}
