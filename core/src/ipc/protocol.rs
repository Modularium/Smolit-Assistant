use serde::{Deserialize, Serialize};

use crate::actions::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionPlannedPayload,
    ActionProgressPayload, ActionStartedPayload, ActionStepPayload, ActionVerificationPayload,
};
use crate::app::{SettingsLlamafileUpdate, SettingsProbeResultPayload, StatusPayload};
use crate::approvals::{ApprovalRequest, ApprovalResolvedPayload, IncomingApprovalDecision};
use crate::interaction::{AccessibilityDiscovery, AccessibilityProbe, SelectedTarget};

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IncomingMessage {
    Ping,
    GetStatus,
    SubmitText {
        text: String,
    },
    SpeakText {
        text: String,
    },
    VoiceOnce,
    InteractionOpenApplication {
        application: String,
    },
    InteractionFocusWindow {
        target: InteractionFocusTarget,
    },
    /// Environment-based AT-SPI capability probe. Read-only: reports
    /// whether an accessibility-based pathway looks plausible in the
    /// current session. Does not touch the desktop.
    InteractionProbeAccessibility,
    /// Symbolic accessibility discovery spike. Attempts to list
    /// top-level accessible items when a `hint` is absent, or to
    /// inspect a target by name when one is provided. Honestly
    /// returns `unavailable` / `uncertain` until the full AT-SPI RPC
    /// client lands.
    InteractionDiscoverAccessibility {
        #[serde(default)]
        hint: Option<String>,
    },
    /// Select one symbolic target as the current Interaction context.
    /// Stored in-memory only; every follow-up action still goes through
    /// approval. See `docs/api.md` §2.9.
    InteractionSelectTarget { target: SelectedTarget },
    /// Clear any previously selected target. Returns a `target_cleared`
    /// envelope even when there was nothing to clear (idempotent).
    InteractionClearTarget,
    ApprovalResponse {
        approval_id: String,
        decision: IncomingApprovalDecision,
    },
    /// PR 5 — erster echter Schreibpfad für Settings. Aktualisiert die
    /// editierbaren Felder der `llamafile_local`-Provider-Config und
    /// rebuildet den Resolver. Core antwortet mit einem `status`-
    /// Envelope (das den Schreibeffekt im nächsten Readout sichtbar
    /// macht) oder einem `error`-Envelope (bei Validation-Fehler,
    /// z. B. unbekanntem Mode). Siehe
    /// [`SettingsLlamafileUpdate`] für die Feldsemantik.
    SettingsSetLlamafileConfig(SettingsLlamafileUpdate),
    /// PR 5 — schmale Diagnoseaktion: prüft Chain-Mitgliedschaft,
    /// Enabled-Flag, Path-Existenz und Execute-Bit (kein Spawn, kein
    /// HTTP). Antwort: `settings_probe_result`.
    SettingsProbeLlamafile,
}

/// Target shape accepted by the `interaction_focus_window` IPC request.
/// Intentionally narrower than `ActionTarget` so the wire contract is
/// obvious: either "a window" (optionally scoped by app) or
/// "the focused window of this application". The richer `ActionTarget`
/// is still used for rendering downstream events.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InteractionFocusTarget {
    Window {
        /// Short display name (e.g. `"calendar"`). Accepted as an
        /// alias for `title` so the wire contract matches the
        /// `{"type":"window","name":"calendar"}` example in docs.
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        title: Option<String>,
        #[serde(default)]
        app: Option<String>,
    },
    Application {
        name: String,
    },
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
#[allow(dead_code)]
pub enum OutgoingMessage {
    Pong,
    Status { payload: StatusPayload },
    Thinking,
    Response { payload: ResponsePayload },
    Heard { payload: HeardPayload },
    Error { message: String },
    ActionPlanned { payload: ActionPlannedPayload },
    ActionStarted { payload: ActionStartedPayload },
    ActionProgress { payload: ActionProgressPayload },
    ActionStep { payload: ActionStepPayload },
    ActionVerification { payload: ActionVerificationPayload },
    ActionCompleted { payload: ActionCompletedPayload },
    ActionFailed { payload: ActionFailedPayload },
    ActionCancelled { payload: ActionCancelledPayload },
    ApprovalRequested { payload: ApprovalRequest },
    ApprovalResolved { payload: ApprovalResolvedPayload },
    AccessibilityProbeResult { payload: AccessibilityProbe },
    AccessibilityDiscoveryResult { payload: AccessibilityDiscovery },
    /// Confirms that the core now holds `payload.target` as the current
    /// Interaction context. Selection is *not* a permission — every
    /// follow-up action still goes through the approval flow.
    TargetSelected { payload: TargetSelectedPayload },
    /// Confirms that the core cleared its current Interaction target.
    /// Idempotent: emitted even when there was nothing to clear.
    TargetCleared { payload: TargetClearedPayload },
    /// PR 5 — Antwort auf `settings_probe_llamafile`. Trägt einen
    /// kuratierten `class`-Tag und eine kurze, Secret-freie Meldung.
    /// Kein Binary-Pfad, kein Roh-Fehlerstring.
    SettingsProbeResult { payload: SettingsProbeResultPayload },
}

/// Payload for the `target_selected` outgoing envelope.
#[derive(Debug, Clone, Serialize)]
pub struct TargetSelectedPayload {
    pub target: SelectedTarget,
}

/// Payload for the `target_cleared` outgoing envelope. `previous` is
/// the target that was cleared, when one was held.
#[derive(Debug, Clone, Serialize)]
pub struct TargetClearedPayload {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub previous: Option<SelectedTarget>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ResponsePayload {
    pub text: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct HeardPayload {
    pub text: String,
}

pub fn parse_incoming(raw: &str) -> Result<IncomingMessage, serde_json::Error> {
    serde_json::from_str(raw)
}

pub fn encode_outgoing(msg: &OutgoingMessage) -> String {
    serde_json::to_string(msg).unwrap_or_else(|err| {
        format!(
            "{{\"type\":\"error\",\"message\":\"failed to encode outgoing message: {err}\"}}"
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actions::{ActionKind, ActionPhase, ActionStatus, ActionTarget};

    #[test]
    fn parses_ping() {
        let msg = parse_incoming(r#"{"type":"ping"}"#).unwrap();
        assert!(matches!(msg, IncomingMessage::Ping));
    }

    #[test]
    fn parses_submit_text() {
        let msg = parse_incoming(r#"{"type":"submit_text","text":"hi"}"#).unwrap();
        match msg {
            IncomingMessage::SubmitText { text } => assert_eq!(text, "hi"),
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_voice_once() {
        let msg = parse_incoming(r#"{"type":"voice_once"}"#).unwrap();
        assert!(matches!(msg, IncomingMessage::VoiceOnce));
    }

    #[test]
    fn rejects_unknown() {
        assert!(parse_incoming(r#"{"type":"nope"}"#).is_err());
    }

    #[test]
    fn parses_interaction_select_target() {
        let msg = parse_incoming(
            r#"{"type":"interaction_select_target","target":{"id":"sel_1","name":"calendar","role":"window","source":"accessibility","confidence":"discovered"}}"#,
        )
        .unwrap();
        match msg {
            IncomingMessage::InteractionSelectTarget { target } => {
                assert_eq!(target.id, "sel_1");
                assert_eq!(target.name, "calendar");
                assert_eq!(target.role, "window");
                assert_eq!(target.confidence, "discovered");
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_interaction_clear_target() {
        let msg = parse_incoming(r#"{"type":"interaction_clear_target"}"#).unwrap();
        assert!(matches!(msg, IncomingMessage::InteractionClearTarget));
    }

    // PR 5 — Parser-Abdeckung für die neuen Settings-Schreib-/
    // Diagnose-Messages. Die Tests frieren die Wire-Form ein, damit die
    // UI-Seite (`ui/autoload/ipc_client.gd`) einen stabilen Kontrakt hat.

    #[test]
    fn parses_settings_set_llamafile_config_full_payload() {
        let raw = r#"{"type":"settings_set_llamafile_config","enabled":true,"mode":"standby","idle_timeout_seconds":120,"path":"/opt/llamafile/server"}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetLlamafileConfig(update) => {
                assert!(update.enabled);
                assert_eq!(update.mode.as_deref(), Some("standby"));
                assert_eq!(update.idle_timeout_seconds, Some(120));
                assert_eq!(update.path.as_deref(), Some("/opt/llamafile/server"));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_llamafile_config_minimal_payload() {
        // Nur `enabled` ist Pflicht; fehlende Optionen bleiben `None`
        // (Merge-Semantik im App-Handler).
        let raw = r#"{"type":"settings_set_llamafile_config","enabled":false}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetLlamafileConfig(update) => {
                assert!(!update.enabled);
                assert!(update.mode.is_none());
                assert!(update.idle_timeout_seconds.is_none());
                assert!(update.path.is_none());
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_probe_llamafile() {
        let msg = parse_incoming(r#"{"type":"settings_probe_llamafile"}"#).unwrap();
        assert!(matches!(msg, IncomingMessage::SettingsProbeLlamafile));
    }

    #[test]
    fn encodes_settings_probe_result() {
        let encoded = encode_outgoing(&OutgoingMessage::SettingsProbeResult {
            payload: SettingsProbeResultPayload {
                ok: false,
                class: "path_missing".into(),
                message: "configured binary path does not exist".into(),
                lifecycle: Some("configured".into()),
                in_chain: true,
                enabled: true,
                configured: true,
            },
        });
        // Der Envelope trägt `type` und den Payload; der Tag-Wert
        // `path_missing` muss stabil bleiben — die UI verlässt sich
        // auf diese Tag-Strings.
        assert!(encoded.contains(r#""type":"settings_probe_result""#));
        assert!(encoded.contains(r#""class":"path_missing""#));
        assert!(encoded.contains(r#""in_chain":true"#));
        assert!(encoded.contains(r#""configured":true"#));
        assert!(encoded.contains(r#""lifecycle":"configured""#));
    }

    #[test]
    fn encodes_pong() {
        let encoded = encode_outgoing(&OutgoingMessage::Pong);
        assert_eq!(encoded, r#"{"type":"pong"}"#);
    }

    #[test]
    fn encodes_error() {
        let encoded = encode_outgoing(&OutgoingMessage::Error {
            message: "boom".into(),
        });
        assert_eq!(encoded, r#"{"type":"error","message":"boom"}"#);
    }

    #[test]
    fn encodes_response() {
        let encoded = encode_outgoing(&OutgoingMessage::Response {
            payload: ResponsePayload { text: "ok".into() },
        });
        assert_eq!(encoded, r#"{"type":"response","payload":{"text":"ok"}}"#);
    }

    #[test]
    fn encodes_action_planned() {
        let encoded = encode_outgoing(&OutgoingMessage::ActionPlanned {
            payload: ActionPlannedPayload {
                action_id: "act_000001".into(),
                action_kind: ActionKind::Query,
                title: "Process text request".into(),
                description: None,
                target: ActionTarget::unknown(),
                mapping: None,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"action_planned","payload":{"action_id":"act_000001","action_kind":"query","title":"Process text request","target":{"type":"unknown"}}}"#
        );
    }

    #[test]
    fn encodes_action_started() {
        let encoded = encode_outgoing(&OutgoingMessage::ActionStarted {
            payload: ActionStartedPayload {
                action_id: "act_000001".into(),
                phase: ActionPhase::Started,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"action_started","payload":{"action_id":"act_000001","phase":"started"}}"#
        );
    }

    #[test]
    fn encodes_action_failed() {
        let encoded = encode_outgoing(&OutgoingMessage::ActionFailed {
            payload: ActionFailedPayload {
                action_id: "act_000001".into(),
                status: ActionStatus::Failed,
                message: "ABrain command failed".into(),
                error: None,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"action_failed","payload":{"action_id":"act_000001","status":"failed","message":"ABrain command failed"}}"#
        );
    }
}
