//! Capability ID Constants (PR 55 — Runtime FA-1 spike).
//!
//! Implementiert das in
//! [`docs/contracts/CAPABILITY_VOCABULARY.md`](../../../docs/contracts/CAPABILITY_VOCABULARY.md)
//! beschriebene Capability-Vokabular als kleine, **rein deskriptive**
//! Code-Schicht. Scope: stabile, testbare String-Konstanten plus ein
//! paar Mapping-Helfer, damit lokale Smolit-Assistant-Aktionen einen
//! kanonischen Capability-Namen tragen können.
//!
//! **Was diese Datei ist:**
//!
//! - Eine kuratierte Liste konstanter Capability-IDs.
//! - Mapping-Funktionen vom heute existierenden Code-Vokabular
//!   (`InteractionKind`, Demo-Plan-Kinds) auf die kanonischen Namen
//!   aus [`CAPABILITY_VOCABULARY.md` §5](../../../docs/contracts/CAPABILITY_VOCABULARY.md).
//! - Kleine `*_by_default`-Helper, die das im Vokabular dokumentierte
//!   Soll-Verhalten **beschreiben**.
//!
//! **Was diese Datei _nicht_ ist:**
//!
//! - Keine Policy-Engine. Approval-Entscheidungen bleiben in
//!   [`crate::approvals`] und [`crate::config`]; die Default-Linie
//!   aus Policy v0 bleibt führend.
//! - Keine Runtime-Registry. Es gibt keine Lade-/Schreibe-Datei,
//!   keine dynamische Erweiterung, kein Plug-in.
//! - Kein Cross-Repo-Wire. Smolit-Assistant ruft AdminBot- /
//!   OceanData- / ABrain-Capabilities **nicht** unter ihren
//!   kanonischen Namen auf — die Konstanten existieren, damit
//!   Smolit-Assistant-eigene Audit-/Approval-Pfade einen stabilen
//!   Bezeichner kennen.
//! - Kein Permission-Check. Eine Funktion `is_executable_today`
//!   liefert ein Faktum aus diesem Repo-Stand; sie ist keine
//!   Sicherheitsgrenze.
#![allow(dead_code)]

use crate::approvals::{RISK_HIGH, RISK_LOW, RISK_MEDIUM};

// ---------------------------------------------------------------------------
// Format constraints (from CAPABILITY_VOCABULARY.md §3).
// ---------------------------------------------------------------------------

/// Maximale Länge einer Capability-ID inkl. Punkt-Separatoren.
pub const MAX_CAPABILITY_ID_LEN: usize = 64;

/// Mindestanzahl an Segmenten in einer Capability-ID
/// (`category.action`).
pub const MIN_CAPABILITY_SEGMENTS: usize = 2;

/// Maximalanzahl an Segmenten (`category.subcategory.action.qualifier`).
pub const MAX_CAPABILITY_SEGMENTS: usize = 4;

// ---------------------------------------------------------------------------
// Canonical IDs (from CAPABILITY_VOCABULARY.md §5).
// ---------------------------------------------------------------------------

// 5.1 Interaction
pub const INTERACTION_OPEN_APPLICATION: &str = "interaction.open_application";
pub const INTERACTION_FOCUS_WINDOW: &str = "interaction.focus_window";
pub const INTERACTION_TYPE_TEXT: &str = "interaction.type_text";
pub const INTERACTION_SEND_SHORTCUT: &str = "interaction.send_shortcut";

// 5.2 Assistant (Demo / Planner)
pub const ASSISTANT_PLAN_DEMO_ACTION: &str = "assistant.plan_demo_action";
pub const ASSISTANT_DEMO_ECHO: &str = "assistant.demo.echo";
pub const ASSISTANT_DEMO_WAIT: &str = "assistant.demo.wait";

// 5.3 Admin (alle zukünftig — siehe ADR-0005)
pub const ADMIN_STATUS_READ: &str = "admin.status.read";
pub const ADMIN_CAPABILITY_DESCRIBE: &str = "admin.capability.describe";
pub const ADMIN_ACTION_DRY_RUN: &str = "admin.action.dry_run";
pub const ADMIN_ACTION_EXECUTE: &str = "admin.action.execute";

// 5.4 Data (alle zukünftig — siehe ADR-0004 + ADR-0006)
pub const DATA_CONTEXT_QUERY: &str = "data.context.query";
pub const DATA_CONTEXT_SUMMARY: &str = "data.context.summary";
pub const DATA_DECIDE_ACCESS: &str = "data.decide_access";

// 5.5 Provider (heute live)
pub const PROVIDER_TEXT_GENERATE: &str = "provider.text.generate";
pub const PROVIDER_STT_TRANSCRIBE: &str = "provider.stt.transcribe";
pub const PROVIDER_TTS_SPEAK: &str = "provider.tts.speak";

// 5.6 Audit (heute live, read-only)
pub const AUDIT_READ_RECENT: &str = "audit.read_recent";

/// Alle in [`CAPABILITY_VOCABULARY.md` §5](../../../docs/contracts/CAPABILITY_VOCABULARY.md)
/// dokumentierten IDs. Reihenfolge spiegelt die Spec-Reihenfolge — neue
/// Einträge werden hinten angehängt, bestehende dürfen nie umbenannt
/// werden (siehe §3 *Stabilität*).
pub const KNOWN_CAPABILITY_IDS: &[&str] = &[
    INTERACTION_OPEN_APPLICATION,
    INTERACTION_FOCUS_WINDOW,
    INTERACTION_TYPE_TEXT,
    INTERACTION_SEND_SHORTCUT,
    ASSISTANT_PLAN_DEMO_ACTION,
    ASSISTANT_DEMO_ECHO,
    ASSISTANT_DEMO_WAIT,
    ADMIN_STATUS_READ,
    ADMIN_CAPABILITY_DESCRIBE,
    ADMIN_ACTION_DRY_RUN,
    ADMIN_ACTION_EXECUTE,
    DATA_CONTEXT_QUERY,
    DATA_CONTEXT_SUMMARY,
    DATA_DECIDE_ACCESS,
    PROVIDER_TEXT_GENERATE,
    PROVIDER_STT_TRANSCRIBE,
    PROVIDER_TTS_SPEAK,
    AUDIT_READ_RECENT,
];

/// Heute lokal in Smolit-Assistant ausführbare Capabilities.
/// Admin/Data sind ausschließlich Dokumentations-Konstanten — sie
/// sind in dieser Liste **bewusst** nicht enthalten.
const EXECUTABLE_TODAY: &[&str] = &[
    INTERACTION_OPEN_APPLICATION,
    INTERACTION_FOCUS_WINDOW,
    ASSISTANT_PLAN_DEMO_ACTION,
    ASSISTANT_DEMO_ECHO,
    ASSISTANT_DEMO_WAIT,
    PROVIDER_TEXT_GENERATE,
    PROVIDER_STT_TRANSCRIBE,
    PROVIDER_TTS_SPEAK,
    AUDIT_READ_RECENT,
];

// ---------------------------------------------------------------------------
// Mapping helpers.
// ---------------------------------------------------------------------------

/// Liefert die kanonische Capability-ID für einen
/// [`crate::interaction::InteractionKind`].
///
/// `Noop` und `Unknown` haben keine Capability-ID — Aktionen ohne
/// Aktionsbedeutung werden nicht klassifiziert.
pub fn capability_id_for_interaction(
    kind: crate::interaction::InteractionKind,
) -> Option<&'static str> {
    use crate::interaction::InteractionKind;
    match kind {
        InteractionKind::OpenApplication => Some(INTERACTION_OPEN_APPLICATION),
        InteractionKind::FocusWindow => Some(INTERACTION_FOCUS_WINDOW),
        InteractionKind::TypeText => Some(INTERACTION_TYPE_TEXT),
        InteractionKind::SendShortcut => Some(INTERACTION_SEND_SHORTCUT),
        InteractionKind::Noop | InteractionKind::Unknown => None,
    }
}

/// Liefert die kanonische Capability-ID für einen Demo-Plan-Kind
/// ([`crate::actions::DEMO_KIND_ECHO`] / `_WAIT` / `_NOOP`).
///
/// Unbekannte / leere Kinds liefern `None`, damit
/// [`crate::actions::sanitize_kind`]-Fallbacks transparent bleiben.
pub fn capability_id_for_demo_kind(kind: &str) -> Option<&'static str> {
    use crate::actions::{DEMO_KIND_ECHO, DEMO_KIND_NOOP, DEMO_KIND_WAIT};
    match kind.trim() {
        k if k == DEMO_KIND_ECHO => Some(ASSISTANT_DEMO_ECHO),
        k if k == DEMO_KIND_WAIT => Some(ASSISTANT_DEMO_WAIT),
        // `noop` ist der Default-Kind und hat keine eigene Capability —
        // der Planner-Lifecycle wird über `assistant.plan_demo_action`
        // geführt.
        k if k == DEMO_KIND_NOOP => Some(ASSISTANT_PLAN_DEMO_ACTION),
        _ => None,
    }
}

/// Liefert die kanonische Capability-ID für einen Demo-Plan-Lifecycle
/// inklusive Fallback auf [`ASSISTANT_PLAN_DEMO_ACTION`], wenn der
/// Kind nicht im Vokabular steht. Wird vom Planner-Pfad genutzt,
/// damit jeder `plan_demo_action`-Lifecycle eine Capability-ID trägt.
pub fn capability_id_for_plan(kind: &str) -> &'static str {
    capability_id_for_demo_kind(kind).unwrap_or(ASSISTANT_PLAN_DEMO_ACTION)
}

// ---------------------------------------------------------------------------
// Metadata helpers (descriptive — NOT policy enforcement).
// ---------------------------------------------------------------------------

/// `true`, wenn die Capability-ID in [`KNOWN_CAPABILITY_IDS`] geführt
/// wird.
pub fn is_known_capability_id(id: &str) -> bool {
    KNOWN_CAPABILITY_IDS.iter().any(|c| *c == id)
}

/// `true`, wenn der Smolit-Assistant Core diese Capability **heute
/// lokal** ausführen kann. Admin- und Data-Capabilities sind im
/// Repo-Stand des Spike grundsätzlich `false` — sie existieren nur
/// als Dokumentations-Konstanten.
///
/// Diese Funktion ist **kein** Permission-Check; sie beschreibt
/// lediglich den Implementations-Status.
pub fn is_executable_today(id: &str) -> bool {
    EXECUTABLE_TODAY.iter().any(|c| *c == id)
}

/// Liefert das in [`CAPABILITY_VOCABULARY.md` §5](../../../docs/contracts/CAPABILITY_VOCABULARY.md)
/// dokumentierte `risk_level` für eine Capability — als kanonische
/// Smolit-Assistant-Risk-Konstante (`low` / `medium` / `high`,
/// vergleiche [`crate::approvals::KNOWN_RISKS`]).
///
/// Unbekannte IDs liefern `None`; **die Funktion verändert keine
/// Approval-Entscheidung**. Sie reflektiert nur das Soll.
pub fn risk_for_capability(id: &str) -> Option<&'static str> {
    Some(match id {
        // Interaction: open/focus = medium (Policy v0); type_text /
        // send_shortcut = high laut Vokabular §5.1 (heute ohnehin
        // BackendUnsupported).
        INTERACTION_OPEN_APPLICATION | INTERACTION_FOCUS_WINDOW => RISK_MEDIUM,
        INTERACTION_TYPE_TEXT | INTERACTION_SEND_SHORTCUT => RISK_HIGH,

        // Assistant: Planner = konfigurierbar (low/medium); die Demos
        // sind low.
        ASSISTANT_PLAN_DEMO_ACTION => RISK_MEDIUM,
        ASSISTANT_DEMO_ECHO | ASSISTANT_DEMO_WAIT => RISK_LOW,

        // Admin: §5.3.
        ADMIN_STATUS_READ | ADMIN_CAPABILITY_DESCRIBE => RISK_LOW,
        ADMIN_ACTION_DRY_RUN => RISK_MEDIUM,
        ADMIN_ACTION_EXECUTE => RISK_HIGH,

        // Data: §5.4 — lokaler Read = low; sensiblere Pfade gelten
        // contextual als medium, das ist Folgearbeit.
        DATA_CONTEXT_QUERY | DATA_CONTEXT_SUMMARY | DATA_DECIDE_ACCESS => RISK_LOW,

        // Provider: §5.5 — lokal = low.
        PROVIDER_TEXT_GENERATE | PROVIDER_STT_TRANSCRIBE | PROVIDER_TTS_SPEAK => RISK_LOW,

        // Audit-Read: §5.6.
        AUDIT_READ_RECENT => RISK_LOW,

        _ => return None,
    })
}

/// Spiegelt das `approval_required`-Soll aus
/// [`CAPABILITY_VOCABULARY.md` §5](../../../docs/contracts/CAPABILITY_VOCABULARY.md).
///
/// **Beschreibend, nicht enforcend.** Der Approval-Pfad bleibt in
/// [`crate::app::App::dispatch_interaction`] / Policy v0; diese
/// Funktion liefert nur die dokumentierte Default-Linie.
pub fn requires_approval_by_default(id: &str) -> Option<bool> {
    Some(match id {
        INTERACTION_OPEN_APPLICATION
        | INTERACTION_FOCUS_WINDOW
        | INTERACTION_TYPE_TEXT
        | INTERACTION_SEND_SHORTCUT => true,

        ASSISTANT_PLAN_DEMO_ACTION => true, // konfigurierbar im Planner
        ASSISTANT_DEMO_ECHO | ASSISTANT_DEMO_WAIT => false,

        ADMIN_STATUS_READ | ADMIN_CAPABILITY_DESCRIBE => false,
        ADMIN_ACTION_DRY_RUN | ADMIN_ACTION_EXECUTE => true,

        DATA_CONTEXT_QUERY | DATA_CONTEXT_SUMMARY | DATA_DECIDE_ACCESS => false,

        PROVIDER_TEXT_GENERATE | PROVIDER_STT_TRANSCRIBE | PROVIDER_TTS_SPEAK => false,

        AUDIT_READ_RECENT => false,

        _ => return None,
    })
}

/// Spiegelt das `audit_required`-Soll aus
/// [`CAPABILITY_VOCABULARY.md` §5](../../../docs/contracts/CAPABILITY_VOCABULARY.md).
/// `audit.read_recent` ist hier **bewusst** `false` — Anti-Rekursion
/// (siehe `AUDIT_CORRELATION_ID_SPEC.md` §9).
pub fn audit_required_by_default(id: &str) -> Option<bool> {
    Some(match id {
        AUDIT_READ_RECENT => false,
        // Provider-Lifecycle ist heute nicht audit-erfasst
        // (Future-Work; siehe Vocab §5.5 "optional").
        PROVIDER_TEXT_GENERATE | PROVIDER_STT_TRANSCRIBE | PROVIDER_TTS_SPEAK => false,
        // Alle übrigen bekannten Capabilities sind Soll-audited.
        other if is_known_capability_id(other) => true,
        _ => return None,
    })
}

/// Spiegelt das `correlation_id_required`-Soll aus
/// [`CAPABILITY_VOCABULARY.md` §5](../../../docs/contracts/CAPABILITY_VOCABULARY.md).
/// PR 54 hat lokal nur **empfohlen**; Pflicht entsteht erst, wenn
/// AdminBot-Mutationen (FA-3) und Cross-Repo-Wire (FA-4) bauen.
pub fn correlation_required_by_default(id: &str) -> Option<bool> {
    Some(match id {
        // High-risk Mutationen sind in der Spec Pflicht.
        ADMIN_ACTION_EXECUTE
        | ADMIN_ACTION_DRY_RUN
        | INTERACTION_TYPE_TEXT
        | INTERACTION_SEND_SHORTCUT => true,
        // Audit-Read ist Anti-Rekursion → nie korreliert.
        AUDIT_READ_RECENT => false,
        // Alles andere bleibt im Spike "empfohlen, aber nicht Pflicht".
        other if is_known_capability_id(other) => false,
        _ => return None,
    })
}

// ---------------------------------------------------------------------------
// Sanitization.
// ---------------------------------------------------------------------------

/// Validiert eine `capability_id` gegen die Naming-Regeln
/// ([`CAPABILITY_VOCABULARY.md` §3](../../../docs/contracts/CAPABILITY_VOCABULARY.md)) **und**
/// gegen die [`KNOWN_CAPABILITY_IDS`]-Whitelist. Unbekannte Werte
/// werden auf `None` geklemmt; das stellt sicher, dass keine
/// User-Strings als Capability-Identitäten in den Audit-Store
/// landen.
pub fn sanitize_capability_id(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let trimmed = s.trim();
    if trimmed.is_empty() || trimmed.len() > MAX_CAPABILITY_ID_LEN {
        return None;
    }
    // Charset + Segmentregeln.
    let segments: Vec<&str> = trimmed.split('.').collect();
    if segments.len() < MIN_CAPABILITY_SEGMENTS || segments.len() > MAX_CAPABILITY_SEGMENTS {
        return None;
    }
    for seg in &segments {
        if seg.is_empty() {
            return None;
        }
        if !seg
            .chars()
            .all(|c| matches!(c, 'a'..='z' | '0'..='9' | '_'))
        {
            return None;
        }
    }
    // Whitelist gegen das dokumentierte Vokabular.
    if !is_known_capability_id(trimmed) {
        return None;
    }
    Some(trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_capability_ids_match_documented_values() {
        // Anker aus CAPABILITY_VOCABULARY.md §5 — wenn die Spec
        // aktualisiert wird, muss dieser Test brechen, damit jemand
        // bewusst eine neue Konstante eintippen muss.
        let expected: &[&str] = &[
            "interaction.open_application",
            "interaction.focus_window",
            "interaction.type_text",
            "interaction.send_shortcut",
            "assistant.plan_demo_action",
            "assistant.demo.echo",
            "assistant.demo.wait",
            "admin.status.read",
            "admin.capability.describe",
            "admin.action.dry_run",
            "admin.action.execute",
            "data.context.query",
            "data.context.summary",
            "data.decide_access",
            "provider.text.generate",
            "provider.stt.transcribe",
            "provider.tts.speak",
            "audit.read_recent",
        ];
        assert_eq!(KNOWN_CAPABILITY_IDS, expected);
    }

    #[test]
    fn capability_ids_match_naming_rules() {
        for id in KNOWN_CAPABILITY_IDS {
            assert!(
                id.len() <= MAX_CAPABILITY_ID_LEN,
                "capability `{id}` exceeds {MAX_CAPABILITY_ID_LEN} chars",
            );
            let segments: Vec<&str> = id.split('.').collect();
            assert!(
                segments.len() >= MIN_CAPABILITY_SEGMENTS
                    && segments.len() <= MAX_CAPABILITY_SEGMENTS,
                "capability `{id}` has {} segments, expected {MIN_CAPABILITY_SEGMENTS}..={MAX_CAPABILITY_SEGMENTS}",
                segments.len(),
            );
            for seg in segments {
                assert!(
                    !seg.is_empty(),
                    "capability `{id}` has an empty segment",
                );
                for c in seg.chars() {
                    assert!(
                        matches!(c, 'a'..='z' | '0'..='9' | '_'),
                        "capability `{id}` segment `{seg}` has invalid char `{c}`",
                    );
                }
            }
        }
    }

    #[test]
    fn interaction_kind_maps_to_expected_capability_ids() {
        use crate::interaction::InteractionKind;
        assert_eq!(
            capability_id_for_interaction(InteractionKind::OpenApplication),
            Some(INTERACTION_OPEN_APPLICATION),
        );
        assert_eq!(
            capability_id_for_interaction(InteractionKind::FocusWindow),
            Some(INTERACTION_FOCUS_WINDOW),
        );
        assert_eq!(
            capability_id_for_interaction(InteractionKind::TypeText),
            Some(INTERACTION_TYPE_TEXT),
        );
        assert_eq!(
            capability_id_for_interaction(InteractionKind::SendShortcut),
            Some(INTERACTION_SEND_SHORTCUT),
        );
        assert_eq!(
            capability_id_for_interaction(InteractionKind::Noop),
            None,
        );
        assert_eq!(
            capability_id_for_interaction(InteractionKind::Unknown),
            None,
        );
    }

    #[test]
    fn demo_kind_maps_to_expected_capability_ids() {
        use crate::actions::{DEMO_KIND_ECHO, DEMO_KIND_NOOP, DEMO_KIND_WAIT};
        assert_eq!(
            capability_id_for_demo_kind(DEMO_KIND_ECHO),
            Some(ASSISTANT_DEMO_ECHO),
        );
        assert_eq!(
            capability_id_for_demo_kind(DEMO_KIND_WAIT),
            Some(ASSISTANT_DEMO_WAIT),
        );
        assert_eq!(
            capability_id_for_demo_kind(DEMO_KIND_NOOP),
            Some(ASSISTANT_PLAN_DEMO_ACTION),
        );
    }

    #[test]
    fn unknown_demo_kind_has_no_capability_id() {
        assert_eq!(capability_id_for_demo_kind("rm_rf_slash"), None);
        assert_eq!(capability_id_for_demo_kind(""), None);
        assert_eq!(capability_id_for_demo_kind("   "), None);
        // `capability_id_for_plan` fällt auf den Planner-Sammler.
        assert_eq!(
            capability_id_for_plan("rm_rf_slash"),
            ASSISTANT_PLAN_DEMO_ACTION,
        );
    }

    #[test]
    fn executable_today_is_false_for_admin_and_data_capabilities() {
        for id in [
            ADMIN_STATUS_READ,
            ADMIN_CAPABILITY_DESCRIBE,
            ADMIN_ACTION_DRY_RUN,
            ADMIN_ACTION_EXECUTE,
            DATA_CONTEXT_QUERY,
            DATA_CONTEXT_SUMMARY,
            DATA_DECIDE_ACCESS,
        ] {
            assert!(
                is_known_capability_id(id),
                "{id} must be in KNOWN_CAPABILITY_IDS",
            );
            assert!(
                !is_executable_today(id),
                "{id} must NOT be executable in this Smolit-Assistant build",
            );
        }
    }

    #[test]
    fn executable_today_is_true_for_local_live_capabilities() {
        for id in [
            INTERACTION_OPEN_APPLICATION,
            INTERACTION_FOCUS_WINDOW,
            ASSISTANT_PLAN_DEMO_ACTION,
            ASSISTANT_DEMO_ECHO,
            ASSISTANT_DEMO_WAIT,
            PROVIDER_TEXT_GENERATE,
            PROVIDER_STT_TRANSCRIBE,
            PROVIDER_TTS_SPEAK,
            AUDIT_READ_RECENT,
        ] {
            assert!(
                is_executable_today(id),
                "{id} must be executable in this build",
            );
        }
    }

    #[test]
    fn requires_approval_metadata_matches_current_interaction_policy() {
        // Policy v0 (PR 25): open_application / focus_window sind
        // approval-gegated; type_text / send_shortcut sind im
        // BackendUnsupported-Default + bleiben approval-pflichtig
        // laut Vocab §5.1.
        assert_eq!(
            requires_approval_by_default(INTERACTION_OPEN_APPLICATION),
            Some(true),
        );
        assert_eq!(
            requires_approval_by_default(INTERACTION_FOCUS_WINDOW),
            Some(true),
        );
        assert_eq!(
            requires_approval_by_default(INTERACTION_TYPE_TEXT),
            Some(true),
        );
        assert_eq!(
            requires_approval_by_default(INTERACTION_SEND_SHORTCUT),
            Some(true),
        );
        // Demos: kein Approval per Default.
        assert_eq!(
            requires_approval_by_default(ASSISTANT_DEMO_ECHO),
            Some(false),
        );
        assert_eq!(
            requires_approval_by_default(ASSISTANT_DEMO_WAIT),
            Some(false),
        );
        // Provider/Audit-Read: kein Approval.
        assert_eq!(
            requires_approval_by_default(PROVIDER_TEXT_GENERATE),
            Some(false),
        );
        assert_eq!(
            requires_approval_by_default(AUDIT_READ_RECENT),
            Some(false),
        );
    }

    #[test]
    fn audit_metadata_marks_real_interactions_audit_required() {
        // Reale Interactions + Demos sind audit-pflichtig.
        for id in [
            INTERACTION_OPEN_APPLICATION,
            INTERACTION_FOCUS_WINDOW,
            ASSISTANT_PLAN_DEMO_ACTION,
            ASSISTANT_DEMO_ECHO,
            ASSISTANT_DEMO_WAIT,
        ] {
            assert_eq!(
                audit_required_by_default(id),
                Some(true),
                "{id} must be audit-required by default",
            );
        }
        // Audit-Read selbst ist Anti-Rekursion → false.
        assert_eq!(
            audit_required_by_default(AUDIT_READ_RECENT),
            Some(false),
        );
        // Provider sind heute nicht audit-erfasst.
        assert_eq!(
            audit_required_by_default(PROVIDER_TEXT_GENERATE),
            Some(false),
        );
    }

    #[test]
    fn correlation_required_metadata_marks_high_risk_capabilities() {
        for id in [
            ADMIN_ACTION_EXECUTE,
            ADMIN_ACTION_DRY_RUN,
            INTERACTION_TYPE_TEXT,
            INTERACTION_SEND_SHORTCUT,
        ] {
            assert_eq!(
                correlation_required_by_default(id),
                Some(true),
                "{id} must require correlation",
            );
        }
        // Audit-Read: explizit nicht.
        assert_eq!(
            correlation_required_by_default(AUDIT_READ_RECENT),
            Some(false),
        );
        // Live-Interaction-Pfade: empfohlen, aber im Spike nicht
        // Pflicht — die PR-54-Wiring spiegelt das.
        assert_eq!(
            correlation_required_by_default(INTERACTION_OPEN_APPLICATION),
            Some(false),
        );
    }

    #[test]
    fn sanitize_capability_id_accepts_known_values() {
        for id in KNOWN_CAPABILITY_IDS {
            assert_eq!(
                sanitize_capability_id(Some((*id).to_string())).as_deref(),
                Some(*id),
            );
        }
    }

    #[test]
    fn invalid_capability_id_is_not_accepted() {
        // Camel-Case
        assert!(sanitize_capability_id(Some("OpenApp".into())).is_none());
        // Bindestrich statt Punkt
        assert!(
            sanitize_capability_id(Some("interaction-open-application".into())).is_none(),
        );
        // Leere Eingabe
        assert!(sanitize_capability_id(None).is_none());
        assert!(sanitize_capability_id(Some(String::new())).is_none());
        assert!(sanitize_capability_id(Some("   ".into())).is_none());
        // Unbekannter Wert mit korrektem Format
        assert!(
            sanitize_capability_id(Some("interaction.format_disk".into())).is_none(),
        );
        // Zu viele Segmente
        assert!(
            sanitize_capability_id(Some("a.b.c.d.e".into())).is_none(),
        );
        // Leeres Segment
        assert!(sanitize_capability_id(Some("interaction..foo".into())).is_none());
        // Zu lang
        let long = "a".repeat(MAX_CAPABILITY_ID_LEN + 1);
        assert!(sanitize_capability_id(Some(long)).is_none());
    }

    #[test]
    fn risk_for_capability_uses_known_risk_constants() {
        use crate::approvals::KNOWN_RISKS;
        for id in KNOWN_CAPABILITY_IDS {
            let risk = risk_for_capability(id)
                .unwrap_or_else(|| panic!("missing risk for {id}"));
            assert!(
                KNOWN_RISKS.iter().any(|r| *r == risk),
                "{id} → unknown risk `{risk}`",
            );
        }
    }
}
