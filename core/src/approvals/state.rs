//! Pending-approval registry.
//!
//! Maps `approval_id → oneshot::Sender<ApprovalDecision>`. When an
//! approval is issued, the core task that fired it awaits on the
//! matching receiver; when a response arrives (or a timeout fires),
//! whoever wins `take()` delivers the decision.
//!
//! The registry is intentionally in-memory only: no persistence, no
//! remembered decisions. A core restart clears all pending approvals.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

use super::response::ApprovalDecision;

#[derive(Debug)]
pub enum PendingApprovalError {
    /// No pending approval exists for this id (unknown, already
    /// resolved, or already timed out).
    Unknown,
    /// The waiter was dropped before the decision could be delivered.
    Closed,
}

impl std::fmt::Display for PendingApprovalError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unknown => write!(f, "unknown approval id"),
            Self::Closed => write!(f, "approval waiter already dropped"),
        }
    }
}

impl std::error::Error for PendingApprovalError {}

/// Thread-safe map of pending approvals. The `Mutex` is a plain
/// `std::sync::Mutex` because all operations are short and non-awaiting.
#[derive(Default)]
pub struct PendingApprovalRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<ApprovalDecision>>>,
}

impl PendingApprovalRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a new pending approval and return the matching receiver.
    /// The caller is expected to `.await` the receiver (typically under
    /// a `tokio::time::timeout`).
    pub fn register(&self, approval_id: impl Into<String>) -> oneshot::Receiver<ApprovalDecision> {
        let (tx, rx) = oneshot::channel();
        let mut guard = self.inner.lock().expect("pending approvals mutex poisoned");
        guard.insert(approval_id.into(), tx);
        rx
    }

    /// Remove and return the sender for `approval_id`, if any.
    pub fn take(&self, approval_id: &str) -> Option<oneshot::Sender<ApprovalDecision>> {
        let mut guard = self.inner.lock().expect("pending approvals mutex poisoned");
        guard.remove(approval_id)
    }

    /// Resolve a pending approval by delivering the decision through its
    /// oneshot sender. Returns an error if no matching pending approval
    /// exists or if its receiver has already been dropped.
    pub fn resolve(
        &self,
        approval_id: &str,
        decision: ApprovalDecision,
    ) -> Result<(), PendingApprovalError> {
        let sender = self.take(approval_id).ok_or(PendingApprovalError::Unknown)?;
        sender
            .send(decision)
            .map_err(|_| PendingApprovalError::Closed)
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.inner
            .lock()
            .expect("pending approvals mutex poisoned")
            .len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn resolve_delivers_decision() {
        let reg = PendingApprovalRegistry::new();
        let rx = reg.register("apr_000001");
        reg.resolve("apr_000001", ApprovalDecision::Approved)
            .expect("resolve");
        let decision = rx.await.expect("receiver");
        assert_eq!(decision, ApprovalDecision::Approved);
        assert_eq!(reg.len(), 0);
    }

    #[test]
    fn resolve_unknown_returns_error() {
        let reg = PendingApprovalRegistry::new();
        let err = reg
            .resolve("apr_missing", ApprovalDecision::Approved)
            .unwrap_err();
        assert!(matches!(err, PendingApprovalError::Unknown));
    }

    #[tokio::test]
    async fn take_removes_entry() {
        let reg = PendingApprovalRegistry::new();
        let _rx = reg.register("apr_000002");
        assert_eq!(reg.len(), 1);
        let sender = reg.take("apr_000002").expect("sender");
        drop(sender);
        assert_eq!(reg.len(), 0);
    }
}
