//! Outbound approval data (core → UI).
//!
//! `ApprovalRequest` is the payload of the `approval_requested`
//! IPC message. It is deliberately descriptive so the UI can render a
//! banner without having to re-derive the action's meaning.
//!
//! `ApprovalResolvedPayload` is the payload of the `approval_resolved`
//! IPC message. It simply echoes the final decision back to listeners.
//!
//! PR 17 adds two additive fields without breaking the existing wire
//! contract:
//!
//!   * `ApprovalRequest.risk` — one of `low` / `medium` / `high`.
//!     Older emitters that do not set the field default to `medium`;
//!     older receivers that ignore the field remain compatible.
//!   * `ApprovalResolvedPayload.source` — one of `user` / `timeout` /
//!     `system`. Defaults to `user` for inbound UI decisions, so
//!     older emitters keep working without explicit propagation.
//!
//! PR 17 also reserves the convention that `action_id` may be an
//! empty string when an approval is issued **without** a backend
//! action (the new demo path). UIs should tolerate the empty-string
//! case.

use serde::{Deserialize, Serialize};

use crate::actions::ActionTarget;
use crate::interaction::{InteractionKind, SelectedTarget};

/// Risk level vocabulary shared between core and UI. Kept as a
/// canonical string constant set rather than an enum so JSON
/// serialization stays stable across additive future levels.
pub const RISK_LOW: &str = "low";
pub const RISK_MEDIUM: &str = "medium";
pub const RISK_HIGH: &str = "high";

/// Valid risk strings, in ascending severity.
pub const KNOWN_RISKS: &[&str] = &[RISK_LOW, RISK_MEDIUM, RISK_HIGH];

/// Source vocabulary for [`ApprovalResolvedPayload::source`].
pub const SOURCE_USER: &str = "user";
pub const SOURCE_TIMEOUT: &str = "timeout";
pub const SOURCE_SYSTEM: &str = "system";

fn default_risk_medium() -> String {
    RISK_MEDIUM.to_string()
}

fn default_source_user() -> String {
    SOURCE_USER.to_string()
}

/// Normalizes a caller-supplied risk string to one of
/// [`KNOWN_RISKS`]. Trims whitespace, lowercases, and falls back to
/// `medium` on empty / unknown input. Kept here so both the Desktop
/// Interaction flow and the demo path share the same sanitizer.
pub fn sanitize_risk<S: AsRef<str>>(raw: S) -> String {
    let normalized = raw.as_ref().trim().to_ascii_lowercase();
    if KNOWN_RISKS.iter().any(|k| *k == normalized) {
        normalized
    } else {
        RISK_MEDIUM.to_string()
    }
}

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
    /// PR 17 — risk level. Additive: older emitters default to
    /// `medium`; older receivers ignore the field.
    #[serde(default = "default_risk_medium")]
    pub risk: String,
    /// PR 54 — additives, optionales `correlation_id`-Token. Spiegelt
    /// die Action-Identity der umgebenden Approval-Klammer; siehe
    /// [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../../../docs/contracts/AUDIT_CORRELATION_ID_SPEC.md).
    /// Ältere Emitter lassen das Feld `None`; ältere Receiver
    /// ignorieren es.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
    /// PR 55 — additives, optionales Capability-Token. Trägt die
    /// kanonische Capability-ID des Aktionspfads
    /// (Spec [`docs/contracts/CAPABILITY_VOCABULARY.md`](../../../docs/contracts/CAPABILITY_VOCABULARY.md)).
    /// Werte stammen ausschließlich aus
    /// [`crate::capabilities::KNOWN_CAPABILITY_IDS`]; UI nutzt das
    /// Feld als descriptive metadata, nicht als Permission-Eingabe.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capability_id: Option<String>,
}

#[cfg(test)]
mod risk_tests {
    use super::*;

    #[test]
    fn sanitize_accepts_known_levels_and_normalizes() {
        assert_eq!(sanitize_risk("low"), RISK_LOW);
        assert_eq!(sanitize_risk("Medium"), RISK_MEDIUM);
        assert_eq!(sanitize_risk("  HIGH  "), RISK_HIGH);
    }

    #[test]
    fn sanitize_falls_back_to_medium_on_unknown_or_empty() {
        assert_eq!(sanitize_risk(""), RISK_MEDIUM);
        assert_eq!(sanitize_risk("critical"), RISK_MEDIUM);
        assert_eq!(sanitize_risk("  "), RISK_MEDIUM);
    }

    #[test]
    fn known_risks_has_all_three_levels() {
        assert_eq!(KNOWN_RISKS, &[RISK_LOW, RISK_MEDIUM, RISK_HIGH]);
    }
}

/// Echoes the final decision for a given approval back to the UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalResolvedPayload {
    pub approval_id: String,
    pub action_id: String,
    /// One of `approved`, `denied`, `cancelled`, `timed_out`.
    pub decision: String,
    /// PR 17 — source of the resolution: `user` (inbound UI
    /// decision), `timeout` (watchdog), or `system` (core-internal
    /// cancel). Additive — older receivers simply ignore the field.
    #[serde(default = "default_source_user")]
    pub source: String,
    /// PR 54 — additives, optionales `correlation_id`-Token. Spiegelt
    /// die `correlation_id` der ursprünglichen `approval_requested`-
    /// Klammer; der Core mappt Re-Resolves über die `approval_id` auf
    /// dasselbe Token. Ältere Receiver ignorieren das Feld.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
}
