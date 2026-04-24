//! Approval-Gated Demo Action Planner v1 (PR 18).
//!
//! Kleines reines Datenmodell für geplante Demo-Aktionen. Der Planner
//! erzeugt eine [`DemoPlan`]-Instanz, die vom Executor im `app`-Modul
//! mockweise durchlaufen wird — **ohne** Shell, ohne Dateisystem, ohne
//! Desktop-Automation, ohne Provider-Mutation. Die Datenklasse lebt
//! hier, damit Unit-Tests sie ohne Tokio/IPC-Abhängigkeiten prüfen
//! können.
//!
//! Design-Grenzen:
//!
//!   * **Keine Persistenz.** Ein `DemoPlan` lebt nur so lange, bis der
//!     Executor seine Ausführung abgeschlossen, verweigert oder
//!     abgebrochen hat.
//!   * **Keine generische Aktion-Engine.** Drei kuratierte Kinds,
//!     bewusst alle ohne echte Seiteneffekte.
//!   * **Keine neue Policy.** Das `requires_approval`-Flag ist eine
//!     caller-seitige Produkt-Entscheidung und wird nicht durch den
//!     Core reinterpretiert; der Core *vollzieht* die Gating-Regel,
//!     entscheidet sie aber nicht.

use serde::{Deserialize, Serialize};

use crate::approvals::{sanitize_risk, RISK_MEDIUM};

/// Kuratierte Demo-Kinds. Alle drei sind garantiert seiteneffekt-frei.
///
///   * `demo_echo` — der Mock schreibt eine Step-Zeile mit dem
///     Plan-Titel; danach folgt `action_completed`.
///   * `demo_wait` — wie `demo_echo`, aber mit einem sichtbaren
///     kurzen Warte-Step (der Executor blockiert *intern*, nicht die
///     UI — die Frames fließen wie gewohnt).
///   * `noop` — der Mock emittiert nur die Klammer-Events, keinen
///     Step-Text. Dient als „minimal possible action" für Smokes.
pub const DEMO_KIND_ECHO: &str = "demo_echo";
pub const DEMO_KIND_WAIT: &str = "demo_wait";
pub const DEMO_KIND_NOOP: &str = "noop";
pub const KNOWN_DEMO_KINDS: &[&str] = &[DEMO_KIND_ECHO, DEMO_KIND_WAIT, DEMO_KIND_NOOP];

pub const DEFAULT_DEMO_KIND: &str = DEMO_KIND_NOOP;

/// Schmaler Statusraum des Planners. Der Core emittiert bewusst
/// *keine* zusätzliche IPC-Variante pro Status — der bestehende
/// Action-Event-Stream (`action_planned`/`started`/`step`/`completed`/
/// `failed`/`cancelled`) plus die Approval-Envelopes aus PR 17
/// reichen vollständig, um alle Übergänge zu kommunizieren. Der
/// Status wird intern geführt, damit der Executor idempotent bleibt
/// und Unit-Tests die Gating-Regeln prüfen können.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DemoPlanStatus {
    Planned,
    WaitingApproval,
    Approved,
    Running,
    Completed,
    Failed,
    Denied,
    Expired,
}

impl DemoPlanStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Planned => "planned",
            Self::WaitingApproval => "waiting_approval",
            Self::Approved => "approved",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Denied => "denied",
            Self::Expired => "expired",
        }
    }

    /// Liefert `true`, wenn der Plan abgeschlossen ist (in welcher
    /// Form auch immer). Ein terminaler Status darf sich nicht mehr
    /// verändern — der Executor gate-t gegen diese Regel.
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::Completed | Self::Failed | Self::Denied | Self::Expired
        )
    }
}

/// Sanitisiert eine benutzergelieferte Kind-Zeichenkette. Unbekannte
/// / leere Werte fallen auf [`DEFAULT_DEMO_KIND`] (`noop`) zurück —
/// das ist die sicherste Default-Aktion (macht nichts).
pub fn sanitize_kind<S: AsRef<str>>(raw: S) -> String {
    let normalized = raw.as_ref().trim().to_ascii_lowercase();
    if KNOWN_DEMO_KINDS.iter().any(|k| *k == normalized) {
        normalized
    } else {
        DEFAULT_DEMO_KIND.to_string()
    }
}

/// Kuratierte, harmlose Demo-Aktion. Alle Felder werden beim
/// Konstruieren einmal sanitisiert; danach ist die Struct immutabel
/// (abgesehen vom `status`-Feld, das der Executor weiterdreht).
#[derive(Debug, Clone)]
pub struct DemoPlan {
    pub action_id: String,
    pub title: String,
    pub summary: String,
    pub kind: String,
    pub risk: String,
    pub requires_approval: bool,
    pub status: DemoPlanStatus,
}

/// Titel-Limit für Demo-Plans. Der Plan-Titel landet direkt in
/// `action_planned` und in der Approval-Card — also zählt er als
/// sichtbarer User-Text und wird gekürzt. Bewusst klein.
pub const MAX_TITLE_CHARS: usize = 80;

/// Summary-Limit. Spiegelt die UI-Seite aus PR 17 (Approval-Card
/// zeigt `MAX_SUMMARY_CHARS = 140`); der Core kürzt bereits
/// serverseitig, damit ein defektes Payload gar nicht erst die
/// Leitung sprengen kann.
pub const MAX_SUMMARY_CHARS: usize = 140;

const ELLIPSIS: &str = "…";

fn trim_to(raw: &str, limit: usize) -> String {
    let trimmed = raw.trim();
    if trimmed.chars().count() <= limit {
        return trimmed.to_string();
    }
    let mut out: String = trimmed
        .chars()
        .take(limit.saturating_sub(ELLIPSIS.chars().count()))
        .collect();
    out.push_str(ELLIPSIS);
    out
}

impl DemoPlan {
    /// Baut einen frischen Plan. Nimmt rohe Strings an und sanitisiert
    /// sie: leere Titel/Summaries werden mit sinnvollen Defaults
    /// ersetzt, Kind/Risk werden auf die kuratierten Whitelists
    /// geklemmt. Der Anfangsstatus ist `Planned`.
    pub fn new(
        action_id: impl Into<String>,
        title: impl AsRef<str>,
        summary: impl AsRef<str>,
        kind: impl AsRef<str>,
        risk: impl AsRef<str>,
        requires_approval: bool,
    ) -> Self {
        let t = trim_to(title.as_ref(), MAX_TITLE_CHARS);
        let s = trim_to(summary.as_ref(), MAX_SUMMARY_CHARS);
        let kind_norm = sanitize_kind(kind.as_ref());
        let risk_norm = sanitize_risk(risk.as_ref());
        let title_final = if t.is_empty() {
            "Demo action".to_string()
        } else {
            t
        };
        let summary_final = if s.is_empty() {
            "Harmless demo action — no system effect.".to_string()
        } else {
            s
        };
        let risk_final = if risk_norm.trim().is_empty() {
            RISK_MEDIUM.to_string()
        } else {
            risk_norm
        };
        Self {
            action_id: action_id.into(),
            title: title_final,
            summary: summary_final,
            kind: kind_norm,
            risk: risk_final,
            requires_approval,
            status: DemoPlanStatus::Planned,
        }
    }

    /// Mutiert den Status idempotent: terminale Stände lassen sich
    /// nicht mehr ändern, und ein wiederholtes Setzen auf denselben
    /// Status ist ein No-op. Der Executor nutzt diese Invariante, um
    /// Double-Execution zu verhindern.
    pub fn set_status(&mut self, next: DemoPlanStatus) -> bool {
        if self.status == next {
            return false;
        }
        if self.status.is_terminal() {
            return false;
        }
        self.status = next;
        true
    }

    /// Liefert eine kurze, sichere Label-Zeile für Action-Steps.
    pub fn step_label(&self) -> String {
        match self.kind.as_str() {
            DEMO_KIND_ECHO => format!("Echo: {}", self.title),
            DEMO_KIND_WAIT => "Wait (demo)".to_string(),
            _ => "No operation".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_kind_accepts_known_values_and_normalizes() {
        assert_eq!(sanitize_kind("demo_echo"), DEMO_KIND_ECHO);
        assert_eq!(sanitize_kind("Demo_Wait"), DEMO_KIND_WAIT);
        assert_eq!(sanitize_kind("  NOOP "), DEMO_KIND_NOOP);
    }

    #[test]
    fn sanitize_kind_falls_back_to_noop_on_unknown_or_empty() {
        assert_eq!(sanitize_kind(""), DEMO_KIND_NOOP);
        assert_eq!(sanitize_kind("rm_rf_slash"), DEMO_KIND_NOOP);
    }

    #[test]
    fn plan_new_defaults_title_and_summary_when_empty() {
        let p = DemoPlan::new("act_1", "", "", "demo_echo", "low", false);
        assert_eq!(p.title, "Demo action");
        assert!(!p.summary.is_empty());
        assert_eq!(p.kind, DEMO_KIND_ECHO);
        assert_eq!(p.risk, "low");
        assert!(!p.requires_approval);
        assert_eq!(p.status, DemoPlanStatus::Planned);
    }

    #[test]
    fn plan_new_trims_long_title_and_summary() {
        let long = "x".repeat(400);
        let p = DemoPlan::new("act_1", &long, &long, "noop", "medium", true);
        assert_eq!(p.title.chars().count(), MAX_TITLE_CHARS);
        assert!(p.title.ends_with(ELLIPSIS));
        assert_eq!(p.summary.chars().count(), MAX_SUMMARY_CHARS);
        assert!(p.summary.ends_with(ELLIPSIS));
    }

    #[test]
    fn plan_new_sanitizes_unknown_kind_to_noop() {
        let p = DemoPlan::new("act_1", "t", "s", "rm_rf", "high", false);
        assert_eq!(p.kind, DEMO_KIND_NOOP);
    }

    #[test]
    fn plan_new_sanitizes_unknown_risk_to_medium() {
        let p = DemoPlan::new("act_1", "t", "s", "noop", "critical", false);
        assert_eq!(p.risk, RISK_MEDIUM);
    }

    #[test]
    fn set_status_refuses_to_leave_terminal_states() {
        let mut p = DemoPlan::new("act_1", "t", "s", "noop", "low", false);
        assert!(p.set_status(DemoPlanStatus::Running));
        assert!(p.set_status(DemoPlanStatus::Completed));
        assert!(!p.set_status(DemoPlanStatus::Running));
        assert_eq!(p.status, DemoPlanStatus::Completed);
    }

    #[test]
    fn set_status_is_noop_for_same_value() {
        let mut p = DemoPlan::new("act_1", "t", "s", "noop", "low", false);
        assert!(!p.set_status(DemoPlanStatus::Planned));
        assert_eq!(p.status, DemoPlanStatus::Planned);
    }

    #[test]
    fn is_terminal_covers_completed_failed_denied_expired() {
        for s in [
            DemoPlanStatus::Completed,
            DemoPlanStatus::Failed,
            DemoPlanStatus::Denied,
            DemoPlanStatus::Expired,
        ] {
            assert!(s.is_terminal(), "{s:?} should be terminal");
        }
        for s in [
            DemoPlanStatus::Planned,
            DemoPlanStatus::WaitingApproval,
            DemoPlanStatus::Approved,
            DemoPlanStatus::Running,
        ] {
            assert!(!s.is_terminal(), "{s:?} should be non-terminal");
        }
    }

    #[test]
    fn step_label_reflects_kind() {
        let p_echo = DemoPlan::new("a", "Say hi", "s", "demo_echo", "low", false);
        assert_eq!(p_echo.step_label(), "Echo: Say hi");
        let p_wait = DemoPlan::new("a", "t", "s", "demo_wait", "low", false);
        assert_eq!(p_wait.step_label(), "Wait (demo)");
        let p_noop = DemoPlan::new("a", "t", "s", "noop", "low", false);
        assert_eq!(p_noop.step_label(), "No operation");
    }
}
