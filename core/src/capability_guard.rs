//! Capability Guard (PR 56 — Runtime FA-3 spike).
//!
//! Ein **kleiner, deterministischer, fail-closed** Guard, der auf den
//! in [`crate::capabilities`] gepflegten Capability-Konstanten und
//! Metadaten arbeitet.
//!
//! **Was diese Datei ist:**
//!
//! - Ein lokaler Filter, der Future-/Unsupported-/Unbekannte
//!   Capabilities **vor** dem bestehenden Approval-/Policy-v0-Pfad
//!   ablehnt (deny-by-default für alles außerhalb des heute live
//!   Vokabulars).
//! - Ein Diagnostik-Helfer mit kuratierten Deny-Gründen, die im
//!   Audit-Store landen können — siehe
//!   [`docs/security/AUDIT_TRAIL.md`](../../../docs/security/AUDIT_TRAIL.md).
//!
//! **Was diese Datei _nicht_ ist:**
//!
//! - Keine Policy-Engine. Die Approval-Entscheidung bleibt bei der
//!   bestehenden Approval-/Policy-v0-Linie; der Guard kann nur
//!   *zusätzlich* verweigern, **nie** zusätzlich genehmigen.
//! - Keine dynamische Registry. Es gibt kein File-Loading, kein
//!   Plug-in, kein OPA/Rego.
//! - Kein Backend. Der Guard führt **nichts** aus.
//! - Keine Risk-Klassifikation. Der Guard verändert keinen
//!   `risk_level`.
//! - Keine User-Eingabe. `capability_id` muss aus den kuratierten
//!   Konstanten in [`crate::capabilities`] kommen, nie aus rohem
//!   IPC- oder UI-Text.
//!
//! Leitprinzip: *Capability metadata may deny unsupported or future
//! capabilities, but it must not grant new powers.*
#![allow(dead_code)]

use crate::capabilities::{self, INTERACTION_SEND_SHORTCUT, INTERACTION_TYPE_TEXT};
use crate::interaction::InteractionKind;

// ---------------------------------------------------------------------------
// Deny reasons — kurze, kuratierte Klassen-Strings für Audit/Wire.
// Nicht aus User-Input befüllbar.
// ---------------------------------------------------------------------------

/// Capability-ID war nicht in [`crate::capabilities::KNOWN_CAPABILITY_IDS`]
/// oder fehlt komplett.
pub const REASON_UNKNOWN_CAPABILITY_ID: &str = "unknown_capability_id";

/// Capability ist im Vokabular geführt, aber [`crate::capabilities::is_executable_today`]
/// liefert `false` (z. B. `provider.text.generate` ist `live`, aber als
/// Action-Guard nicht nutzbar; reine Read-Capabilities laufen nicht
/// durch den Action-Guard).
pub const REASON_CAPABILITY_NOT_EXECUTABLE_TODAY: &str = "capability_not_executable_today";

/// Capability gehört zu `admin.*` / `data.*` — Future-Work, lokal nicht
/// implementiert.
pub const REASON_FUTURE_CAPABILITY_NOT_IMPLEMENTED: &str = "future_capability_not_implemented";

/// `interaction.type_text` ist heute `BackendUnsupported` (siehe
/// [`crate::interaction::InteractionKind`]).
pub const REASON_INTERACTION_TYPE_TEXT_NOT_SUPPORTED: &str =
    "interaction_type_text_not_supported";

/// `interaction.send_shortcut` ist heute `BackendUnsupported`.
pub const REASON_INTERACTION_SEND_SHORTCUT_NOT_SUPPORTED: &str =
    "interaction_send_shortcut_not_supported";

/// Kuratierter Recovery-Hint für eine `Deny`-Antwort. Nutzt dasselbe
/// Vokabular wie [`crate::interaction::recovery::RecoveryHint`] —
/// `fallback_unavailable` ist der einzig sinnvolle Wert für
/// "Capability ist heute nicht verfügbar".
pub const RECOVERY_HINT_FALLBACK_UNAVAILABLE: &str = "fallback_unavailable";

/// Liste aller Deny-Gründe, die der Guard erzeugen kann. Nutzbar für
/// Tests und für die Audit-Sanitization-Whitelist (Future Work).
pub const KNOWN_GUARD_REASONS: &[&str] = &[
    REASON_UNKNOWN_CAPABILITY_ID,
    REASON_CAPABILITY_NOT_EXECUTABLE_TODAY,
    REASON_FUTURE_CAPABILITY_NOT_IMPLEMENTED,
    REASON_INTERACTION_TYPE_TEXT_NOT_SUPPORTED,
    REASON_INTERACTION_SEND_SHORTCUT_NOT_SUPPORTED,
];

// ---------------------------------------------------------------------------
// Decision and input types.
// ---------------------------------------------------------------------------

/// Ergebnis des Guards. **Allow** lässt den Aufrufer in den
/// bestehenden Approval-/Executor-Pfad weiterlaufen; **Deny** trägt
/// einen kurzen, kuratierten Grund (aus [`KNOWN_GUARD_REASONS`]) und
/// einen optionalen Recovery-Hint, den der Aufrufer in eine
/// existierende `action_failed`/`error`-Form gießen kann.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CapabilityGuardDecision {
    Allow,
    Deny {
        reason: &'static str,
        recovery_hint: Option<&'static str>,
    },
}

impl CapabilityGuardDecision {
    pub fn is_allow(&self) -> bool {
        matches!(self, Self::Allow)
    }

    pub fn is_deny(&self) -> bool {
        matches!(self, Self::Deny { .. })
    }

    /// Kurzer Reason-String für Audit und Logs. `Allow` liefert
    /// `"allow"`, damit Logger nicht extra branchen müssen.
    pub fn reason_str(&self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::Deny { reason, .. } => reason,
        }
    }
}

/// Eingabe-Bündel. Alle Felder sind optional, damit kleine
/// Aufruf-Stellen den Guard ohne Boilerplate nutzen können. Die
/// `correlation_id` wird **nicht** für die Entscheidung gelesen —
/// sie steht nur für Diagnostik / Audit-Verknüpfung im Vec.
#[derive(Debug, Clone, Default)]
pub struct CapabilityGuardInput {
    pub capability_id: Option<String>,
    pub action_kind: Option<InteractionKind>,
    pub source: Option<&'static str>,
    pub correlation_id: Option<String>,
}

impl CapabilityGuardInput {
    pub fn for_capability(id: impl Into<String>) -> Self {
        Self {
            capability_id: Some(id.into()),
            ..Self::default()
        }
    }
}

// ---------------------------------------------------------------------------
// Public guard surface.
// ---------------------------------------------------------------------------

/// Generischer Capability-Guard. Erwartet eine
/// [`CapabilityGuardInput`] und liefert eine
/// [`CapabilityGuardDecision`].
///
/// Regeln (alle fail-closed):
///
/// - `capability_id` fehlt oder ist unbekannt →
///   [`REASON_UNKNOWN_CAPABILITY_ID`].
/// - Capability liegt in `admin.*` / `data.*` →
///   [`REASON_FUTURE_CAPABILITY_NOT_IMPLEMENTED`].
/// - Capability liegt im Vokabular, ist aber heute nicht
///   ausführbar → [`REASON_CAPABILITY_NOT_EXECUTABLE_TODAY`].
/// - Capability ist `interaction.type_text` /
///   `interaction.send_shortcut` →
///   spezifische `REASON_INTERACTION_*_NOT_SUPPORTED`-Klasse,
///   damit der Audit-Trail die spezifische Unsupported-Achse zeigt.
/// - Capability ist `audit.read_recent` → Allow (read-only Pfad,
///   wird selbst nicht audit-erfasst — Anti-Rekursion gemäß
///   [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../../../docs/contracts/AUDIT_CORRELATION_ID_SPEC.md) §9).
/// - Sonst Allow.
pub fn guard_capability(input: CapabilityGuardInput) -> CapabilityGuardDecision {
    let id = match input.capability_id.as_deref() {
        Some(id) if !id.trim().is_empty() => id,
        _ => {
            return CapabilityGuardDecision::Deny {
                reason: REASON_UNKNOWN_CAPABILITY_ID,
                recovery_hint: Some(RECOVERY_HINT_FALLBACK_UNAVAILABLE),
            };
        }
    };
    if !capabilities::is_known_capability_id(id) {
        return CapabilityGuardDecision::Deny {
            reason: REASON_UNKNOWN_CAPABILITY_ID,
            recovery_hint: Some(RECOVERY_HINT_FALLBACK_UNAVAILABLE),
        };
    }
    // Spezifische Sub-Reasons für die zwei dokumentierten
    // BackendUnsupported-Pfade — der Audit-Trail darf den Grund
    // präzise tragen (siehe Vocab §5.1).
    if id == INTERACTION_TYPE_TEXT {
        return CapabilityGuardDecision::Deny {
            reason: REASON_INTERACTION_TYPE_TEXT_NOT_SUPPORTED,
            recovery_hint: Some(RECOVERY_HINT_FALLBACK_UNAVAILABLE),
        };
    }
    if id == INTERACTION_SEND_SHORTCUT {
        return CapabilityGuardDecision::Deny {
            reason: REASON_INTERACTION_SEND_SHORTCUT_NOT_SUPPORTED,
            recovery_hint: Some(RECOVERY_HINT_FALLBACK_UNAVAILABLE),
        };
    }
    // Future-Capabilities: alle `admin.*` / `data.*` IDs sind im
    // Vokabular, aber `is_executable_today` liefert `false`. Wir
    // klassifizieren sie spezifisch, damit der Audit-Hinweis nicht
    // mit "irgendeine nicht ausführbare ID" verschwimmt.
    if id.starts_with("admin.") || id.starts_with("data.") {
        return CapabilityGuardDecision::Deny {
            reason: REASON_FUTURE_CAPABILITY_NOT_IMPLEMENTED,
            recovery_hint: Some(RECOVERY_HINT_FALLBACK_UNAVAILABLE),
        };
    }
    if !capabilities::is_executable_today(id) {
        return CapabilityGuardDecision::Deny {
            reason: REASON_CAPABILITY_NOT_EXECUTABLE_TODAY,
            recovery_hint: Some(RECOVERY_HINT_FALLBACK_UNAVAILABLE),
        };
    }
    CapabilityGuardDecision::Allow
}

/// Spezialisierte Variante für Interaction-Aktionen. `Noop` /
/// `Unknown` haben keine Capability — der Guard verweigert sie als
/// `unknown_capability_id`, weil sie keinen Aktionspfad
/// rechtfertigen.
pub fn guard_interaction_kind(kind: InteractionKind) -> CapabilityGuardDecision {
    let cap = capabilities::capability_id_for_interaction(kind);
    guard_capability(CapabilityGuardInput {
        capability_id: cap.map(str::to_string),
        action_kind: Some(kind),
        source: Some("interaction"),
        correlation_id: None,
    })
}

/// Spezialisierte Variante für den Demo-Planner. Kinds, die nicht im
/// Demo-Vokabular liegen, fallen auf `assistant.plan_demo_action`
/// zurück — entsprechend der Sanitisierung in
/// [`crate::actions::sanitize_kind`].
pub fn guard_demo_kind(kind: &str) -> CapabilityGuardDecision {
    let cap = capabilities::capability_id_for_plan(kind);
    guard_capability(CapabilityGuardInput {
        capability_id: Some(cap.to_string()),
        action_kind: None,
        source: Some("demo"),
        correlation_id: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capabilities::{
        ADMIN_ACTION_EXECUTE, ADMIN_STATUS_READ, ASSISTANT_DEMO_ECHO, ASSISTANT_DEMO_WAIT,
        ASSISTANT_PLAN_DEMO_ACTION, AUDIT_READ_RECENT, DATA_CONTEXT_QUERY, DATA_DECIDE_ACCESS,
        INTERACTION_FOCUS_WINDOW, INTERACTION_OPEN_APPLICATION, PROVIDER_TEXT_GENERATE,
    };

    #[test]
    fn guard_allows_open_application() {
        let d = guard_interaction_kind(InteractionKind::OpenApplication);
        assert_eq!(d, CapabilityGuardDecision::Allow);
        assert!(d.is_allow());
    }

    #[test]
    fn guard_allows_focus_window_without_overriding_executor_policy() {
        // Der Guard sagt nur, dass die Capability heute lokal lebt.
        // Über die existierende doppelte Opt-in-Linie (Env +
        // Template) entscheidet weiterhin der Executor — der Guard
        // hebt **nichts** davon auf.
        let d = guard_interaction_kind(InteractionKind::FocusWindow);
        assert_eq!(d, CapabilityGuardDecision::Allow);
    }

    #[test]
    fn guard_allows_demo_echo() {
        let d = guard_demo_kind(crate::actions::DEMO_KIND_ECHO);
        assert_eq!(d, CapabilityGuardDecision::Allow);
    }

    #[test]
    fn guard_allows_demo_wait() {
        let d = guard_demo_kind(crate::actions::DEMO_KIND_WAIT);
        assert_eq!(d, CapabilityGuardDecision::Allow);
    }

    #[test]
    fn guard_allows_plan_demo_action_for_noop_and_unknown_kind() {
        // `noop` und unbekannte Kinds fallen auf
        // `assistant.plan_demo_action` zurück.
        assert_eq!(
            guard_demo_kind(crate::actions::DEMO_KIND_NOOP),
            CapabilityGuardDecision::Allow,
        );
        assert_eq!(
            guard_demo_kind("rm_rf_slash"),
            CapabilityGuardDecision::Allow,
        );
    }

    #[test]
    fn guard_denies_unknown_capability_id() {
        let d = guard_capability(CapabilityGuardInput::for_capability("interaction.format_disk"));
        assert!(matches!(
            d,
            CapabilityGuardDecision::Deny {
                reason: REASON_UNKNOWN_CAPABILITY_ID,
                ..
            },
        ));
    }

    #[test]
    fn guard_denies_missing_capability_id() {
        for raw in [None, Some(String::new()), Some("   ".into())] {
            let d = guard_capability(CapabilityGuardInput {
                capability_id: raw,
                ..Default::default()
            });
            assert!(
                matches!(
                    d,
                    CapabilityGuardDecision::Deny {
                        reason: REASON_UNKNOWN_CAPABILITY_ID,
                        ..
                    },
                ),
                "missing capability must deny, got {:?}",
                d,
            );
        }
    }

    #[test]
    fn guard_denies_admin_future_capability() {
        for id in [ADMIN_STATUS_READ, ADMIN_ACTION_EXECUTE] {
            let d = guard_capability(CapabilityGuardInput::for_capability(id));
            assert!(
                matches!(
                    d,
                    CapabilityGuardDecision::Deny {
                        reason: REASON_FUTURE_CAPABILITY_NOT_IMPLEMENTED,
                        ..
                    },
                ),
                "admin capability `{id}` must deny as future, got {:?}",
                d,
            );
        }
    }

    #[test]
    fn guard_denies_data_future_capability() {
        for id in [DATA_CONTEXT_QUERY, DATA_DECIDE_ACCESS] {
            let d = guard_capability(CapabilityGuardInput::for_capability(id));
            assert!(
                matches!(
                    d,
                    CapabilityGuardDecision::Deny {
                        reason: REASON_FUTURE_CAPABILITY_NOT_IMPLEMENTED,
                        ..
                    },
                ),
                "data capability `{id}` must deny as future, got {:?}",
                d,
            );
        }
    }

    #[test]
    fn guard_denies_type_text() {
        let d = guard_interaction_kind(InteractionKind::TypeText);
        assert!(matches!(
            d,
            CapabilityGuardDecision::Deny {
                reason: REASON_INTERACTION_TYPE_TEXT_NOT_SUPPORTED,
                ..
            },
        ));
    }

    #[test]
    fn guard_denies_send_shortcut() {
        let d = guard_interaction_kind(InteractionKind::SendShortcut);
        assert!(matches!(
            d,
            CapabilityGuardDecision::Deny {
                reason: REASON_INTERACTION_SEND_SHORTCUT_NOT_SUPPORTED,
                ..
            },
        ));
    }

    #[test]
    fn guard_denies_noop_and_unknown_interactions() {
        for kind in [InteractionKind::Noop, InteractionKind::Unknown] {
            let d = guard_interaction_kind(kind);
            assert!(
                matches!(
                    d,
                    CapabilityGuardDecision::Deny {
                        reason: REASON_UNKNOWN_CAPABILITY_ID,
                        ..
                    },
                ),
                "Noop/Unknown must deny as unknown, got {:?}",
                d,
            );
        }
    }

    #[test]
    fn guard_decision_is_descriptive_not_policy_engine() {
        // Anker-Test gegen Drift: der Guard ändert keinen Risk,
        // erzeugt keine neue Approval-Decision, führt nichts aus.
        // Das prüfen wir, indem wir alle dokumentierten Guard-
        // Reasons gegen die kuratierte Whitelist halten.
        for d in [
            guard_interaction_kind(InteractionKind::OpenApplication),
            guard_interaction_kind(InteractionKind::FocusWindow),
            guard_interaction_kind(InteractionKind::TypeText),
            guard_interaction_kind(InteractionKind::SendShortcut),
            guard_interaction_kind(InteractionKind::Noop),
            guard_capability(CapabilityGuardInput::for_capability(ADMIN_ACTION_EXECUTE)),
            guard_capability(CapabilityGuardInput::for_capability(DATA_CONTEXT_QUERY)),
        ] {
            match d {
                CapabilityGuardDecision::Allow => {}
                CapabilityGuardDecision::Deny { reason, .. } => {
                    assert!(
                        KNOWN_GUARD_REASONS.iter().any(|r| *r == reason),
                        "deny reason `{reason}` must be in KNOWN_GUARD_REASONS",
                    );
                }
            }
        }
    }

    #[test]
    fn guard_allows_audit_read_recent_anti_recursion() {
        // `audit.read_recent` ist im Vokabular, executable_today,
        // läuft aber selbst nicht durch den Action-Guard. Der Guard
        // muss Allow liefern, ohne die Anti-Rekursions-Regel
        // (Read-only löst keinen Audit-Eintrag aus) zu berühren.
        let d = guard_capability(CapabilityGuardInput::for_capability(AUDIT_READ_RECENT));
        assert_eq!(d, CapabilityGuardDecision::Allow);
    }

    #[test]
    fn guard_allows_provider_capabilities_descriptively() {
        // Provider-Capabilities sind heute live, der Guard sagt
        // Allow — er gewährt dadurch aber keinen neuen Provider-
        // Pfad; Provider-Auswahl bleibt im Resolver.
        let d = guard_capability(CapabilityGuardInput::for_capability(PROVIDER_TEXT_GENERATE));
        assert_eq!(d, CapabilityGuardDecision::Allow);
    }

    #[test]
    fn guard_allows_known_capabilities_for_existing_lifecycles() {
        for id in [
            INTERACTION_OPEN_APPLICATION,
            INTERACTION_FOCUS_WINDOW,
            ASSISTANT_PLAN_DEMO_ACTION,
            ASSISTANT_DEMO_ECHO,
            ASSISTANT_DEMO_WAIT,
            AUDIT_READ_RECENT,
        ] {
            let d = guard_capability(CapabilityGuardInput::for_capability(id));
            assert_eq!(
                d,
                CapabilityGuardDecision::Allow,
                "{id} must Allow today",
            );
        }
    }

    #[test]
    fn known_guard_reasons_are_short_and_safe() {
        // Audit-Hygiene: keine User-Inhalte, keine Pfade, keine
        // Mehrsprachigkeit, keine Whitespace-Artefakte. Jeder
        // Reason ist ein kurzer, snake_case-Token.
        for r in KNOWN_GUARD_REASONS {
            assert!(!r.is_empty());
            assert!(r.len() <= 64, "reason `{r}` too long");
            for c in r.chars() {
                assert!(
                    matches!(c, 'a'..='z' | '0'..='9' | '_'),
                    "reason `{r}` has invalid char `{c}`",
                );
            }
        }
    }
}
