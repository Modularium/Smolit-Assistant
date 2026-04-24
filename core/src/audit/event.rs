//! Audit Event Model v1 (PR 19).
//!
//! Kleines, streng sanitisiertes Event-Modell für die lokale
//! Nachvollziehbarkeit. Das Modul hält **keine** sensiblen
//! Full-Payloads fest — jede eingehende Zeichenkette wird hart
//! gekürzt, bevor sie im Store landet. Keine Audio-Bytes, keine
//! vollständigen TTS-/STT-Texte, keine Langzeit-Historie.
//!
//! Leitprinzip: *accountability without surveillance.* Der Store ist
//! ein Dev-/Debug-Hilfsmittel, nicht ein Produkt-Feature. Inhalte
//! sind bewusst klein.

use serde::{Deserialize, Serialize};

/// Kuratierte Kategorien für Audit-Einträge. Die Liste deckt den
/// Lifecycle der Approval-Gated Demo-Actions aus PR 18 ab plus ein
/// paar IPC-Grenzfälle. Unbekannte Kategorien werden gar nicht erst
/// akzeptiert — das Modell ist deliberately narrow.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AuditKind {
    /// Ein relevanter IPC-Command kam an (z. B. `plan_demo_action`).
    /// Wir loggen nicht *jeden* Command — nur die, die die Gating-
    /// Kette berühren.
    IpcCommandReceived,
    /// Ein Command wurde abgelehnt (z. B. unbekannte `approval_id`,
    /// idempotente Double-Approve).
    IpcCommandRejected,
    /// Ein Plan wurde geöffnet und das `action_planned`-Envelope
    /// emittiert.
    ActionPlanned,
    /// Der Core hat um eine Freigabe gebeten.
    ApprovalRequested,
    /// Die Freigabe wurde aufgelöst — `result` trägt die
    /// Entscheidung, `source` deren Herkunft.
    ApprovalResolved,
    /// Der Executor startet.
    ActionStarted,
    /// Die Aktion ist regulär abgeschlossen.
    ActionCompleted,
    /// Die Aktion wurde abgebrochen (Deny / Cancel / Timeout).
    ActionCancelled,
    /// Die Aktion ist fehlgeschlagen.
    ActionFailed,
}

impl AuditKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::IpcCommandReceived => "ipc_command_received",
            Self::IpcCommandRejected => "ipc_command_rejected",
            Self::ActionPlanned => "action_planned",
            Self::ApprovalRequested => "approval_requested",
            Self::ApprovalResolved => "approval_resolved",
            Self::ActionStarted => "action_started",
            Self::ActionCompleted => "action_completed",
            Self::ActionCancelled => "action_cancelled",
            Self::ActionFailed => "action_failed",
        }
    }
}

/// Maximale sichtbare Länge eines Audit-Summaries. Bewusst klein:
/// das Audit-Protokoll soll Kontext liefern, nicht Inhalt.
pub const MAX_SUMMARY_CHARS: usize = 80;

const ELLIPSIS: &str = "…";

/// Kürzt rohen Summary-Text für den Audit-Store. Whitespace wird
/// gestrippt; längere Zeichenketten werden mit Ellipsis
/// abgeschnitten. Leere Eingabe → `None`, damit der Store das Feld
/// gar nicht erst serialisiert.
pub fn sanitize_summary(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.chars().count() <= MAX_SUMMARY_CHARS {
        return Some(trimmed.to_string());
    }
    let mut out: String = trimmed
        .chars()
        .take(MAX_SUMMARY_CHARS.saturating_sub(ELLIPSIS.chars().count()))
        .collect();
    out.push_str(ELLIPSIS);
    Some(out)
}

/// Bekannte `source`-Werte. Das Modell spiegelt das Vokabular aus
/// [`crate::approvals::SOURCE_USER`] / `_TIMEOUT` / `_SYSTEM` plus
/// die UI-/Core-Herkunftsmarker.
pub const SOURCE_USER: &str = "user";
pub const SOURCE_TIMEOUT: &str = "timeout";
pub const SOURCE_SYSTEM: &str = "system";
pub const SOURCE_UI: &str = "ui";
pub const SOURCE_CORE: &str = "core";

pub const KNOWN_SOURCES: &[&str] = &[SOURCE_USER, SOURCE_TIMEOUT, SOURCE_SYSTEM, SOURCE_UI, SOURCE_CORE];

/// Bekannte `result`-Werte. Deckt Approval- und Action-Outcomes.
pub const RESULT_APPROVED: &str = "approved";
pub const RESULT_DENIED: &str = "denied";
pub const RESULT_EXPIRED: &str = "expired";
pub const RESULT_COMPLETED: &str = "completed";
pub const RESULT_FAILED: &str = "failed";
pub const RESULT_CANCELLED: &str = "cancelled";
pub const RESULT_REJECTED: &str = "rejected";

pub const KNOWN_RESULTS: &[&str] = &[
    RESULT_APPROVED,
    RESULT_DENIED,
    RESULT_EXPIRED,
    RESULT_COMPLETED,
    RESULT_FAILED,
    RESULT_CANCELLED,
    RESULT_REJECTED,
];

/// Sanitisiert einen `source`-String. Unbekannte Werte fallen auf
/// `None`, damit sie nicht serialisiert werden — lieber kein Feld
/// als ein freies User-Label.
pub fn sanitize_source(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let n = s.trim().to_ascii_lowercase();
    if KNOWN_SOURCES.iter().any(|v| *v == n) {
        Some(n)
    } else {
        None
    }
}

/// Sanitisiert einen `result`-String. Unbekannte Werte fallen auf
/// `None`.
pub fn sanitize_result(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let n = s.trim().to_ascii_lowercase();
    if KNOWN_RESULTS.iter().any(|v| *v == n) {
        Some(n)
    } else {
        None
    }
}

/// Sanitisiert einen `risk`-String — Wiederverwendung der bestehenden
/// Whitelist aus dem Approval-Modul.
pub fn sanitize_risk(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let n = crate::approvals::sanitize_risk(&s);
    if n.is_empty() {
        None
    } else {
        Some(n)
    }
}

/// Einzelner Audit-Eintrag. `audit_id` wird vom [`AuditStore`]
/// vergeben; alle anderen Felder liefert der Aufrufer.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEvent {
    pub audit_id: String,
    pub timestamp_ms: u64,
    pub kind: AuditKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub risk: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
}

/// Felder-Bundle für einen neuen Audit-Eintrag. Wird vom Store
/// entgegengenommen und sanitisiert; danach baut er daraus ein
/// [`AuditEvent`] mit frischer `audit_id` und Timestamp.
#[derive(Debug, Clone, Default)]
pub struct AuditFields {
    pub action_id: Option<String>,
    pub approval_id: Option<String>,
    pub risk: Option<String>,
    pub result: Option<String>,
    pub source: Option<String>,
    pub summary: Option<String>,
}

impl AuditFields {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_action_id(mut self, id: impl Into<String>) -> Self {
        self.action_id = Some(id.into());
        self
    }

    pub fn with_approval_id(mut self, id: impl Into<String>) -> Self {
        self.approval_id = Some(id.into());
        self
    }

    pub fn with_risk(mut self, risk: impl Into<String>) -> Self {
        self.risk = Some(risk.into());
        self
    }

    pub fn with_result(mut self, result: impl Into<String>) -> Self {
        self.result = Some(result.into());
        self
    }

    pub fn with_source(mut self, source: impl Into<String>) -> Self {
        self.source = Some(source.into());
        self
    }

    pub fn with_summary(mut self, summary: impl Into<String>) -> Self {
        self.summary = Some(summary.into());
        self
    }

    /// Sanitisiert die Felder. Leere Zeichenketten und unbekannte
    /// Vokabeln werden zu `None` — wir speichern lieber nichts als
    /// kaputten Kontext.
    pub fn sanitized(self) -> Self {
        Self {
            action_id: non_empty(self.action_id),
            approval_id: non_empty(self.approval_id),
            risk: sanitize_risk(self.risk),
            result: sanitize_result(self.result),
            source: sanitize_source(self.source),
            summary: sanitize_summary(self.summary),
        }
    }
}

fn non_empty(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let t = s.trim();
    if t.is_empty() {
        None
    } else {
        Some(t.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_summary_trims_whitespace_and_truncates() {
        assert_eq!(sanitize_summary(None), None);
        assert_eq!(sanitize_summary(Some("".into())), None);
        assert_eq!(sanitize_summary(Some("   \t\n  ".into())), None);
        assert_eq!(sanitize_summary(Some("hello".into())).unwrap(), "hello");
        let long = "a".repeat(200);
        let trimmed = sanitize_summary(Some(long)).unwrap();
        assert_eq!(trimmed.chars().count(), MAX_SUMMARY_CHARS);
        assert!(trimmed.ends_with(ELLIPSIS));
    }

    #[test]
    fn sanitize_source_accepts_whitelist_and_rejects_unknown() {
        assert_eq!(sanitize_source(Some("User".into())).as_deref(), Some("user"));
        assert_eq!(sanitize_source(Some(" timeout ".into())).as_deref(), Some("timeout"));
        assert!(sanitize_source(Some("attacker".into())).is_none());
        assert!(sanitize_source(None).is_none());
    }

    #[test]
    fn sanitize_result_accepts_whitelist() {
        for v in KNOWN_RESULTS {
            assert_eq!(sanitize_result(Some(v.to_string())).as_deref(), Some(*v));
        }
        assert!(sanitize_result(Some("pwned".into())).is_none());
    }

    #[test]
    fn sanitize_risk_defers_to_approvals_module() {
        assert_eq!(sanitize_risk(Some("low".into())).as_deref(), Some("low"));
        // Unknown values fall back to the approval module's default
        // ("medium"), but we surface them — the approval whitelist
        // already guarantees a safe, kurated string.
        assert_eq!(
            sanitize_risk(Some("nonsense".into())).as_deref(),
            Some("medium"),
        );
    }

    #[test]
    fn audit_fields_sanitized_drops_empty_strings() {
        let f = AuditFields::new()
            .with_action_id("   ")
            .with_summary("")
            .with_source("unknown_source");
        let s = f.sanitized();
        assert!(s.action_id.is_none());
        assert!(s.summary.is_none());
        assert!(s.source.is_none());
    }

    #[test]
    fn audit_kind_as_str_is_snake_case() {
        assert_eq!(AuditKind::ActionPlanned.as_str(), "action_planned");
        assert_eq!(AuditKind::IpcCommandRejected.as_str(), "ipc_command_rejected");
        assert_eq!(AuditKind::ApprovalResolved.as_str(), "approval_resolved");
    }
}
