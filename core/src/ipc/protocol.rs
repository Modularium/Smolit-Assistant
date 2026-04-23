use serde::{Deserialize, Serialize};

use crate::actions::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionPlannedPayload,
    ActionProgressPayload, ActionStartedPayload, ActionStepPayload, ActionVerificationPayload,
};
use crate::app::{
    SettingsCloudHttpConfigUpdate, SettingsCloudHttpSecretUpdate, SettingsLlamafileUpdate,
    SettingsLocalHttpUpdate, SettingsProbeResultPayload, SettingsSttProviderChainUpdate,
    SettingsSttUpdate, SettingsTextProviderChainUpdate, SettingsTtsProviderChainUpdate,
    SettingsTtsUpdate, StatusPayload,
};
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
    /// PR 17 — narrow split of `approval_response`. `approval_approve`
    /// and `approval_deny` are functionally equivalent to their
    /// unified counterpart; the UI may use whichever matches its code
    /// style. Idempotency is handled by the pending-approval registry:
    /// a second arrival for the same `approval_id` is rejected with
    /// an `error` envelope (never a second `approval_resolved`).
    ApprovalApprove { approval_id: String },
    /// PR 17 — see [`IncomingMessage::ApprovalApprove`].
    ApprovalDeny { approval_id: String },
    /// PR 17 — harmless demo-approval trigger. Creates a pending
    /// approval **without** running any backend action afterwards.
    /// All fields are optional; the core fills sensible, short
    /// defaults if they are missing. The payload is bounded (no long
    /// free-form content is expected here) — the UI must still tolerate
    /// arbitrary strings from the core's side but the demo trigger
    /// itself never exposes sensitive data. No Desktop Automation, no
    /// shell, no provider call follows.
    RequestApprovalDemo {
        #[serde(default)]
        title: Option<String>,
        #[serde(default)]
        summary: Option<String>,
        #[serde(default)]
        risk: Option<String>,
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
    /// PR 7 — editierbare STT-Settings (`enabled` + optionaler
    /// `command`). Antwort: `status` bei Erfolg, `error` bei
    /// Validierungsfehler.
    SettingsSetSttConfig(SettingsSttUpdate),
    /// PR 7 — editierbare TTS-Settings (`enabled`, optionaler `command`,
    /// optionales `auto_speak`).
    SettingsSetTtsConfig(SettingsTtsUpdate),
    /// PR 7 — Diagnoseprobe für die STT-Achse. Kein Mikrofon-Zugriff,
    /// nur Filesystem-Check des konfigurierten Commands. Antwort:
    /// `settings_probe_result` mit `axis="stt"`.
    SettingsProbeStt,
    /// PR 7 — Diagnoseprobe für die TTS-Achse. Kein Audio-Output,
    /// nur Filesystem-Check. Antwort: `settings_probe_result` mit
    /// `axis="tts"`.
    SettingsProbeTts,
    /// PR 8 — editierbare `local_http`-Settings. Pflichtfeld
    /// `enabled`. Optional: `endpoint` (leer löscht),
    /// `request_timeout_seconds` (`0` wird abgelehnt).
    SettingsSetLocalHttpConfig(SettingsLocalHttpUpdate),
    /// PR 8 — Diagnoseprobe für den `local_http`-Provider. TCP-
    /// Connect auf den geparsten Endpoint, kein Completion-Request,
    /// keine Prompt-Daten. Antwort: `settings_probe_result` mit
    /// `axis="local_http"`.
    SettingsProbeLocalHttp,
    /// PR 9 — Text-Provider-Chain-Editor. Der Core validiert
    /// (Whitelist, Duplikate, Empty-Reject) und ersetzt den
    /// `TextProviderResolver` atomar bei Erfolg. Validation-Fehler
    /// kommen als `error`-Envelope zurück; bei Erfolg sendet der
    /// Core einen frischen `status`-Envelope.
    SettingsSetTextProviderChain(SettingsTextProviderChainUpdate),
    /// PR 9 — Reset auf den Compile-Zeit-Default `["abrain"]`. Löscht
    /// den persistierten Override im Settings-Store und rebuildet den
    /// Resolver. Antwort: `status` bei Erfolg.
    SettingsResetTextProviderChain,
    /// PR 10 — operationale Cloud-HTTP-Config. **Enthält keinen
    /// API-Key** — der läuft über `settings_set_cloud_http_secret`.
    SettingsSetCloudHttpConfig(SettingsCloudHttpConfigUpdate),
    /// PR 10 — Cloud-HTTP-Secret (API-Key). Einziger IPC-Pfad, der
    /// den Key-Wert trägt. Der Core antwortet bei Erfolg mit einem
    /// `status`-Envelope, der nur `cloud_http_secret_present: bool`
    /// trägt — nie den Key selbst.
    SettingsSetCloudHttpSecret(SettingsCloudHttpSecretUpdate),
    /// PR 10 — Diagnose-Probe für den `cloud_http`-Provider. TCP-
    /// Connect gegen den geparsten Endpoint, kein Completion-
    /// Request, kein Bearer-Header auf der Leitung. Antwort:
    /// `settings_probe_result` mit `axis="cloud_http"`.
    SettingsProbeCloudHttp,
    /// PR 13 — STT-Provider-Chain-Editor. Validierung analog zu
    /// `settings_set_text_provider_chain` (Whitelist, Duplikate,
    /// Empty-Reject) gegen
    /// [`crate::providers::stt::KNOWN_STT_KINDS`]. Bei Erfolg
    /// frischer `status`-Envelope; bei Validation-Fehler kuratiertes
    /// `error`-Envelope.
    SettingsSetSttProviderChain(SettingsSttProviderChainUpdate),
    /// PR 13 — Reset der STT-Kette auf den Compile-Zeit-Default
    /// `["command"]`. Löscht den persistierten Override.
    SettingsResetSttProviderChain,
    /// PR 13 — TTS-Provider-Chain-Editor. Spiegel zur STT-Message.
    SettingsSetTtsProviderChain(SettingsTtsProviderChainUpdate),
    /// PR 13 — Reset der TTS-Kette auf Default `["command"]`.
    SettingsResetTtsProviderChain,
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
    /// PR 14 — TTS-Lebenszyklus. Wird vom Core genau einmal emittiert,
    /// wenn ein TTS-Provider tatsächlich anläuft. Kein Audio-Timing,
    /// kein Phonem-Stream, keine Text-Payload — der Core behält den
    /// Text bei sich und veröffentlicht nur den Source-/Provider-
    /// Kontext. Zu jedem `speaking_started` gibt es genau ein
    /// `speaking_ended`; ältere UIs ignorieren beide Varianten.
    SpeakingStarted { payload: SpeakingStartedPayload },
    /// PR 14 — Gegenstück zu [`OutgoingMessage::SpeakingStarted`].
    /// Kommt im Erfolgs- wie im Fehlerfall (jeweils mit `ok=true` bzw.
    /// `ok=false` + kuratierter `error_class`). Fällt die Kette in
    /// einen Fallback, zeigt `provider` den tatsächlich aktiven Kind-
    /// Namen; bei Start steht dort der primäre Kind-Name.
    SpeakingEnded { payload: SpeakingEndedPayload },
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

/// PR 14 — Payload für [`OutgoingMessage::SpeakingStarted`].
///
/// `source` trennt Nutzeranstöße (`speak_text`) vom automatischen
/// Ausspielen nach einer `response` (`auto_speak`); die UI darf darauf
/// unterschiedlich reagieren, muss aber nicht. `provider` ist der
/// primäre Kind-Name aus der TTS-Kette (heute nur `command`) — nie
/// ein Binary-Pfad, nie ein Command-String. `action_id` ist nur
/// gesetzt, wenn der Event aus einem Action-Event-Flow stammt
/// (`speak_text`); beim passiven `auto_speak` bleibt das Feld leer.
#[derive(Debug, Clone, Serialize)]
pub struct SpeakingStartedPayload {
    pub source: String,
    pub provider: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action_id: Option<String>,
}

/// PR 14 — Payload für [`OutgoingMessage::SpeakingEnded`]. `ok=true`
/// heißt „Kette hat erfolgreich gesprochen" (ggf. über einen
/// Fallback); `ok=false` trägt einen kuratierten `error_class`-Tag
/// (`empty_chain` / `timeout` / `process_missing` / …), identisch zu
/// den bestehenden TTS-Probe-Klassen.
#[derive(Debug, Clone, Serialize)]
pub struct SpeakingEndedPayload {
    pub source: String,
    pub provider: String,
    pub ok: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_class: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action_id: Option<String>,
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

    // PR 17 — new Approval UX commands.

    #[test]
    fn parses_approval_approve_and_deny_commands() {
        match parse_incoming(r#"{"type":"approval_approve","approval_id":"apr_000001"}"#).unwrap() {
            IncomingMessage::ApprovalApprove { approval_id } => {
                assert_eq!(approval_id, "apr_000001");
            }
            other => panic!("unexpected: {other:?}"),
        }
        match parse_incoming(r#"{"type":"approval_deny","approval_id":"apr_000002"}"#).unwrap() {
            IncomingMessage::ApprovalDeny { approval_id } => {
                assert_eq!(approval_id, "apr_000002");
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn parses_request_approval_demo_full_payload() {
        let raw = r#"{"type":"request_approval_demo","title":"Demo","summary":"Test the card.","risk":"high"}"#;
        match parse_incoming(raw).unwrap() {
            IncomingMessage::RequestApprovalDemo { title, summary, risk } => {
                assert_eq!(title.as_deref(), Some("Demo"));
                assert_eq!(summary.as_deref(), Some("Test the card."));
                assert_eq!(risk.as_deref(), Some("high"));
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn parses_request_approval_demo_empty_payload() {
        let raw = r#"{"type":"request_approval_demo"}"#;
        match parse_incoming(raw).unwrap() {
            IncomingMessage::RequestApprovalDemo { title, summary, risk } => {
                assert!(title.is_none());
                assert!(summary.is_none());
                assert!(risk.is_none());
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn encodes_approval_resolved_includes_source_and_decision() {
        let encoded = encode_outgoing(&OutgoingMessage::ApprovalResolved {
            payload: crate::approvals::ApprovalResolvedPayload {
                approval_id: "apr_000001".into(),
                action_id: "".into(),
                decision: "denied".into(),
                source: "user".into(),
            },
        });
        // Additive: `source` is present; existing receivers that
        // ignore the field still parse the frame.
        assert!(encoded.contains(r#""type":"approval_resolved""#));
        assert!(encoded.contains(r#""approval_id":"apr_000001""#));
        assert!(encoded.contains(r#""decision":"denied""#));
        assert!(encoded.contains(r#""source":"user""#));
    }

    #[test]
    fn encodes_approval_requested_includes_risk_default_medium() {
        use crate::actions::ActionTarget;
        use crate::approvals::{ApprovalRequest, RISK_MEDIUM};
        use crate::interaction::InteractionKind;
        let encoded = encode_outgoing(&OutgoingMessage::ApprovalRequested {
            payload: ApprovalRequest {
                approval_id: "apr_000001".into(),
                action_id: "act_000001".into(),
                action_kind: InteractionKind::OpenApplication,
                title: "Open calendar".into(),
                message: "Open calendar?".into(),
                target: ActionTarget::unknown(),
                reason: None,
                timeout_seconds: 20,
                selected_target: None,
                risk: RISK_MEDIUM.to_string(),
            },
        });
        assert!(encoded.contains(r#""type":"approval_requested""#));
        assert!(encoded.contains(r#""risk":"medium""#));
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
                axis: "llamafile".into(),
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
        // auf diese Tag-Strings. PR 7: zusätzlich `axis` für das
        // STT-/TTS-/Llamafile-Routing.
        assert!(encoded.contains(r#""type":"settings_probe_result""#));
        assert!(encoded.contains(r#""axis":"llamafile""#));
        assert!(encoded.contains(r#""class":"path_missing""#));
        assert!(encoded.contains(r#""in_chain":true"#));
        assert!(encoded.contains(r#""configured":true"#));
        assert!(encoded.contains(r#""lifecycle":"configured""#));
    }

    // PR 7 — Parser-Abdeckung für die neuen STT-/TTS-Settings-Messages.

    #[test]
    fn parses_settings_set_stt_config_full_payload() {
        let raw =
            r#"{"type":"settings_set_stt_config","enabled":true,"command":"whisper --model base"}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetSttConfig(update) => {
                assert!(update.enabled);
                assert_eq!(update.command.as_deref(), Some("whisper --model base"));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_stt_config_minimal_payload() {
        let msg = parse_incoming(r#"{"type":"settings_set_stt_config","enabled":false}"#).unwrap();
        match msg {
            IncomingMessage::SettingsSetSttConfig(update) => {
                assert!(!update.enabled);
                assert!(update.command.is_none());
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_tts_config_with_auto_speak() {
        let raw = r#"{"type":"settings_set_tts_config","enabled":true,"command":"espeak","auto_speak":true}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetTtsConfig(update) => {
                assert!(update.enabled);
                assert_eq!(update.command.as_deref(), Some("espeak"));
                assert_eq!(update.auto_speak, Some(true));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_tts_config_without_auto_speak() {
        let msg =
            parse_incoming(r#"{"type":"settings_set_tts_config","enabled":false}"#).unwrap();
        match msg {
            IncomingMessage::SettingsSetTtsConfig(update) => {
                assert!(!update.enabled);
                assert!(update.command.is_none());
                assert!(update.auto_speak.is_none());
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_probe_stt_and_tts() {
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_probe_stt"}"#).unwrap(),
            IncomingMessage::SettingsProbeStt
        ));
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_probe_tts"}"#).unwrap(),
            IncomingMessage::SettingsProbeTts
        ));
    }

    // PR 8 — Parser-Abdeckung für die neuen Local-HTTP-Messages.

    #[test]
    fn parses_settings_set_local_http_config_full_payload() {
        let raw = r#"{"type":"settings_set_local_http_config","enabled":true,"endpoint":"http://127.0.0.1:9000/completion","request_timeout_seconds":45}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetLocalHttpConfig(update) => {
                assert!(update.enabled);
                assert_eq!(
                    update.endpoint.as_deref(),
                    Some("http://127.0.0.1:9000/completion"),
                );
                assert_eq!(update.request_timeout_seconds, Some(45));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_local_http_config_minimal_payload() {
        let msg =
            parse_incoming(r#"{"type":"settings_set_local_http_config","enabled":false}"#)
                .unwrap();
        match msg {
            IncomingMessage::SettingsSetLocalHttpConfig(update) => {
                assert!(!update.enabled);
                assert!(update.endpoint.is_none());
                assert!(update.request_timeout_seconds.is_none());
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_probe_local_http() {
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_probe_local_http"}"#).unwrap(),
            IncomingMessage::SettingsProbeLocalHttp
        ));
    }

    // PR 9 — Parser-Abdeckung für den Text-Provider-Chain-Editor.

    #[test]
    fn parses_settings_set_text_provider_chain_full_payload() {
        let raw = r#"{"type":"settings_set_text_provider_chain","chain":["llamafile_local","local_http","abrain"]}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetTextProviderChain(update) => {
                assert_eq!(
                    update.chain,
                    vec!["llamafile_local", "local_http", "abrain"],
                );
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_text_provider_chain_empty_chain_parses_to_empty_vec() {
        // Leere Kette wird geparst — abgelehnt wird sie erst vom
        // Core-Validator. So bleibt der Schreibpfad ehrlich:
        // Protokoll akzeptiert das Feld, Semantik wird im Core
        // geprüft.
        let raw = r#"{"type":"settings_set_text_provider_chain","chain":[]}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetTextProviderChain(update) => {
                assert!(update.chain.is_empty());
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_reset_text_provider_chain() {
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_reset_text_provider_chain"}"#).unwrap(),
            IncomingMessage::SettingsResetTextProviderChain
        ));
    }

    // PR 10 — Cloud-HTTP-Parser-Tests.

    #[test]
    fn parses_settings_set_cloud_http_config_full_payload() {
        let raw = r#"{"type":"settings_set_cloud_http_config","enabled":true,"endpoint":"http://example.invalid:8443/v1/chat","model":"gpt-test","request_timeout_seconds":60}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetCloudHttpConfig(update) => {
                assert!(update.enabled);
                assert_eq!(
                    update.endpoint.as_deref(),
                    Some("http://example.invalid:8443/v1/chat"),
                );
                assert_eq!(update.model.as_deref(), Some("gpt-test"));
                assert_eq!(update.request_timeout_seconds, Some(60));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_cloud_http_secret_with_key() {
        let raw = r#"{"type":"settings_set_cloud_http_secret","api_key":"sk-test-abcdef"}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetCloudHttpSecret(update) => {
                assert_eq!(update.api_key.as_deref(), Some("sk-test-abcdef"));
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_set_cloud_http_secret_with_null_clears_key() {
        let raw = r#"{"type":"settings_set_cloud_http_secret","api_key":null}"#;
        let msg = parse_incoming(raw).unwrap();
        match msg {
            IncomingMessage::SettingsSetCloudHttpSecret(update) => {
                assert!(update.api_key.is_none());
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_probe_cloud_http() {
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_probe_cloud_http"}"#).unwrap(),
            IncomingMessage::SettingsProbeCloudHttp
        ));
    }

    // PR 13 — STT/TTS-Chain-Parser-Tests.

    #[test]
    fn parses_settings_set_stt_provider_chain_payload() {
        let raw = r#"{"type":"settings_set_stt_provider_chain","chain":["command"]}"#;
        match parse_incoming(raw).unwrap() {
            IncomingMessage::SettingsSetSttProviderChain(u) => {
                assert_eq!(u.chain, vec!["command"]);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_reset_stt_provider_chain() {
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_reset_stt_provider_chain"}"#).unwrap(),
            IncomingMessage::SettingsResetSttProviderChain
        ));
    }

    #[test]
    fn parses_settings_set_tts_provider_chain_payload() {
        let raw = r#"{"type":"settings_set_tts_provider_chain","chain":["command"]}"#;
        match parse_incoming(raw).unwrap() {
            IncomingMessage::SettingsSetTtsProviderChain(u) => {
                assert_eq!(u.chain, vec!["command"]);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn parses_settings_reset_tts_provider_chain() {
        assert!(matches!(
            parse_incoming(r#"{"type":"settings_reset_tts_provider_chain"}"#).unwrap(),
            IncomingMessage::SettingsResetTtsProviderChain
        ));
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

    // PR 14 — TTS-Lebenszyklus-Encoder.

    #[test]
    fn encodes_speaking_started_with_action_id() {
        let encoded = encode_outgoing(&OutgoingMessage::SpeakingStarted {
            payload: SpeakingStartedPayload {
                source: "speak_text".into(),
                provider: "command".into(),
                action_id: Some("act_000001".into()),
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"speaking_started","payload":{"source":"speak_text","provider":"command","action_id":"act_000001"}}"#
        );
    }

    #[test]
    fn encodes_speaking_started_without_action_id() {
        let encoded = encode_outgoing(&OutgoingMessage::SpeakingStarted {
            payload: SpeakingStartedPayload {
                source: "auto_speak".into(),
                provider: "command".into(),
                action_id: None,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"speaking_started","payload":{"source":"auto_speak","provider":"command"}}"#
        );
    }

    #[test]
    fn encodes_speaking_ended_ok() {
        let encoded = encode_outgoing(&OutgoingMessage::SpeakingEnded {
            payload: SpeakingEndedPayload {
                source: "speak_text".into(),
                provider: "command".into(),
                ok: true,
                error_class: None,
                action_id: Some("act_000001".into()),
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"speaking_ended","payload":{"source":"speak_text","provider":"command","ok":true,"action_id":"act_000001"}}"#
        );
    }

    #[test]
    fn encodes_speaking_ended_failure_carries_error_class() {
        let encoded = encode_outgoing(&OutgoingMessage::SpeakingEnded {
            payload: SpeakingEndedPayload {
                source: "auto_speak".into(),
                provider: "command".into(),
                ok: false,
                error_class: Some("exit_nonzero".into()),
                action_id: None,
            },
        });
        assert_eq!(
            encoded,
            r#"{"type":"speaking_ended","payload":{"source":"auto_speak","provider":"command","ok":false,"error_class":"exit_nonzero"}}"#
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
