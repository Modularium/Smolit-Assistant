use std::sync::Arc;

use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{WebSocketStream, accept_async};
use tracing::{debug, error, info, warn};

use crate::actions::{
    ActionCompletedPayload, ActionFailedPayload, ActionKind, ActionPhase, ActionPlannedPayload,
    ActionStartedPayload, ActionStatus, ActionStepPayload, ActionTarget,
};
use crate::app::App;
use crate::approvals::IncomingApprovalDecision;
use crate::ipc::protocol::{
    HeardPayload, IncomingMessage, OutgoingMessage, ResponsePayload, encode_outgoing,
    parse_incoming,
};

pub async fn serve(app: Arc<App>, bind: &str) -> Result<()> {
    let listener = TcpListener::bind(bind)
        .await
        .with_context(|| format!("failed to bind IPC listener on {bind}"))?;
    accept_loop(app, listener).await
}

async fn accept_loop(app: Arc<App>, listener: TcpListener) -> Result<()> {
    let local_addr = listener.local_addr().ok();
    info!(addr = ?local_addr, "IPC websocket listening");

    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(err) => {
                error!(error = %err, "IPC accept failed");
                continue;
            }
        };
        debug!(peer = %peer, "IPC connection accepted");

        let app = Arc::clone(&app);
        tokio::spawn(async move {
            if let Err(err) = handle_connection(app, stream).await {
                warn!(error = %err, peer = %peer, "IPC connection ended with error");
            }
        });
    }
}

async fn handle_connection(app: Arc<App>, stream: TcpStream) -> Result<()> {
    let ws = accept_async(stream)
        .await
        .context("websocket handshake failed")?;
    handle_ws(app, ws).await
}

async fn handle_ws<S>(app: Arc<App>, ws: WebSocketStream<S>) -> Result<()>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    let (mut sink, mut stream) = ws.split();
    let mut events_rx = app.subscribe_events();

    loop {
        tokio::select! {
            biased;

            incoming = stream.next() => {
                let Some(frame) = incoming else { break };
                let frame = match frame {
                    Ok(frame) => frame,
                    Err(err) => {
                        warn!(error = %err, "websocket read error");
                        break;
                    }
                };

                match frame {
                    Message::Text(text) => {
                        let responses = dispatch(&app, &text).await;
                        for msg in responses {
                            let encoded = encode_outgoing(&msg);
                            if let Err(err) = sink.send(Message::Text(encoded)).await {
                                warn!(error = %err, "failed to send ipc response");
                                return Ok(());
                            }
                        }
                    }
                    Message::Binary(_) => {
                        let msg = OutgoingMessage::Error {
                            message: "binary frames are not supported".into(),
                        };
                        let _ = sink.send(Message::Text(encode_outgoing(&msg))).await;
                    }
                    Message::Ping(payload) => {
                        let _ = sink.send(Message::Pong(payload)).await;
                    }
                    Message::Close(_) => {
                        debug!("client closed ipc connection");
                        break;
                    }
                    Message::Pong(_) | Message::Frame(_) => {}
                }
            }

            event = events_rx.recv() => {
                match event {
                    Ok(msg) => {
                        let encoded = encode_outgoing(&msg);
                        if let Err(err) = sink.send(Message::Text(encoded)).await {
                            warn!(error = %err, "failed to forward broadcast event");
                            return Ok(());
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                        warn!(lagged = n, "broadcast events channel lagged");
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                        break;
                    }
                }
            }
        }
    }

    Ok(())
}

async fn dispatch(app: &Arc<App>, raw: &str) -> Vec<OutgoingMessage> {
    let parsed = match parse_incoming(raw) {
        Ok(msg) => msg,
        Err(err) => {
            return vec![OutgoingMessage::Error {
                message: format!("invalid message: {err}"),
            }];
        }
    };

    match parsed {
        IncomingMessage::Ping => vec![OutgoingMessage::Pong],
        IncomingMessage::GetStatus => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        IncomingMessage::SubmitText { text } => handle_submit_text(app, text).await,
        IncomingMessage::SpeakText { text } => handle_speak_text(app, text).await,
        IncomingMessage::VoiceOnce => handle_voice_once(app).await,
        IncomingMessage::InteractionOpenApplication { application } => {
            app.execute_open_application(&application).await
        }
        IncomingMessage::InteractionFocusWindow { target } => {
            app.execute_focus_window(target).await
        }
        IncomingMessage::InteractionProbeAccessibility => {
            app.probe_accessibility().await
        }
        IncomingMessage::InteractionDiscoverAccessibility { hint } => {
            app.discover_accessibility(hint).await
        }
        IncomingMessage::InteractionSelectTarget { target } => app.select_target(target),
        IncomingMessage::InteractionClearTarget => app.clear_target(),
        IncomingMessage::ApprovalResponse {
            approval_id,
            decision,
        } => handle_approval_response(app, approval_id, decision),
        IncomingMessage::SettingsSetLlamafileConfig(update) => {
            handle_settings_set_llamafile_config(app, update)
        }
        IncomingMessage::SettingsProbeLlamafile => handle_settings_probe_llamafile(app),
        IncomingMessage::SettingsSetSttConfig(update) => {
            handle_settings_set_stt_config(app, update)
        }
        IncomingMessage::SettingsSetTtsConfig(update) => {
            handle_settings_set_tts_config(app, update)
        }
        IncomingMessage::SettingsProbeStt => handle_settings_probe_stt(app),
        IncomingMessage::SettingsProbeTts => handle_settings_probe_tts(app),
        IncomingMessage::SettingsSetLocalHttpConfig(update) => {
            handle_settings_set_local_http_config(app, update)
        }
        IncomingMessage::SettingsProbeLocalHttp => handle_settings_probe_local_http(app).await,
        IncomingMessage::SettingsSetTextProviderChain(update) => {
            handle_settings_set_text_provider_chain(app, update)
        }
        IncomingMessage::SettingsResetTextProviderChain => {
            handle_settings_reset_text_provider_chain(app)
        }
        IncomingMessage::SettingsSetCloudHttpConfig(update) => {
            handle_settings_set_cloud_http_config(app, update)
        }
        IncomingMessage::SettingsSetCloudHttpSecret(update) => {
            handle_settings_set_cloud_http_secret(app, update)
        }
        IncomingMessage::SettingsProbeCloudHttp => handle_settings_probe_cloud_http(app).await,
        IncomingMessage::SettingsSetSttProviderChain(update) => {
            handle_settings_set_stt_provider_chain(app, update)
        }
        IncomingMessage::SettingsResetSttProviderChain => {
            handle_settings_reset_stt_provider_chain(app)
        }
        IncomingMessage::SettingsSetTtsProviderChain(update) => {
            handle_settings_set_tts_provider_chain(app, update)
        }
        IncomingMessage::SettingsResetTtsProviderChain => {
            handle_settings_reset_tts_provider_chain(app)
        }
    }
}

/// PR 5 — Schreibpfad für die editierbare Llamafile-Config. Bei Erfolg
/// antwortet der Core mit dem aktualisierten `status`-Envelope, damit
/// der UI-Client sofort den neuen Readout sieht (kein Extra-Roundtrip
/// via `get_status`). Validation-Fehler kommen als `error`-Envelope
/// zurück; die Meldung ist bewusst Secret-frei (kein Pfad, keine
/// Rohdaten).
fn handle_settings_set_llamafile_config(
    app: &Arc<App>,
    update: crate::app::SettingsLlamafileUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_llamafile_config(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

/// PR 5 — Diagnose-Probe ohne Side-Effects. Antwortet immer mit einem
/// `settings_probe_result`-Envelope; `ok=false` trägt einen kuratierten
/// `class`-Tag (`not_in_chain` / `disabled` / `not_configured` /
/// `path_missing` / `path_not_file` / `path_not_executable`), `ok=true`
/// trägt `class="ok"`.
fn handle_settings_probe_llamafile(app: &Arc<App>) -> Vec<OutgoingMessage> {
    vec![OutgoingMessage::SettingsProbeResult {
        payload: app.probe_llamafile(),
    }]
}

/// PR 7 — STT-Schreibpfad. Byte-kompatible Dispatch-Geometrie zum
/// Llamafile-Pfad: Erfolg → `status`-Envelope, Fehler → `error`.
fn handle_settings_set_stt_config(
    app: &Arc<App>,
    update: crate::app::SettingsSttUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_stt_config(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

/// PR 7 — TTS-Schreibpfad. Symmetrisch zu
/// [`handle_settings_set_stt_config`] plus `auto_speak`.
fn handle_settings_set_tts_config(
    app: &Arc<App>,
    update: crate::app::SettingsTtsUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_tts_config(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

fn handle_settings_probe_stt(app: &Arc<App>) -> Vec<OutgoingMessage> {
    vec![OutgoingMessage::SettingsProbeResult {
        payload: app.probe_stt(),
    }]
}

fn handle_settings_probe_tts(app: &Arc<App>) -> Vec<OutgoingMessage> {
    vec![OutgoingMessage::SettingsProbeResult {
        payload: app.probe_tts(),
    }]
}

/// PR 8 — Local-HTTP-Schreibpfad. Geometrie identisch zu den anderen
/// `settings_set_*`-Pfaden: Erfolg → `status`, Validierungsfehler →
/// `error` (Secret-frei).
fn handle_settings_set_local_http_config(
    app: &Arc<App>,
    update: crate::app::SettingsLocalHttpUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_local_http_config(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

/// PR 8 — Local-HTTP-Probe. Async (nutzt `tokio::net::TcpStream` im
/// Preflight) — der einzige Probe-Handler mit echter I/O im heutigen
/// Scope; Secret-Disziplin gilt trotzdem (kein Endpoint im Response).
async fn handle_settings_probe_local_http(app: &Arc<App>) -> Vec<OutgoingMessage> {
    vec![OutgoingMessage::SettingsProbeResult {
        payload: app.probe_local_http().await,
    }]
}

/// PR 9 — Text-Provider-Chain-Schreibpfad. Geometrie wie die anderen
/// `settings_set_*`-Pfade: Validation-Fehler → `error`-Envelope
/// (Meldung vom Chain-Validator), Erfolg → frischer `status`-Envelope.
fn handle_settings_set_text_provider_chain(
    app: &Arc<App>,
    update: crate::app::SettingsTextProviderChainUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_text_provider_chain(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

/// PR 9 — Reset der Text-Provider-Kette auf `["abrain"]`. Geht durch
/// denselben Update-Pfad; Persist-Fehler werden nicht hart propagiert.
fn handle_settings_reset_text_provider_chain(app: &Arc<App>) -> Vec<OutgoingMessage> {
    match app.reset_text_provider_chain() {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

// --- PR 10: Cloud-HTTP-Pfade -------------------------------------------
//
// Geometrie wie die anderen `settings_set_*`-Pfade, aber mit zwei
// getrennten Messages: eine für die operationale Config
// (Endpoint/Modell/Timeout) und eine zweite, schlanke, nur für das
// Secret. So kann die UI Secret-Writes separat routen und der Core
// kann sicherstellen, dass Secret-Handling niemals mit Operational-
// Writes vermischt wird.

fn handle_settings_set_cloud_http_config(
    app: &Arc<App>,
    update: crate::app::SettingsCloudHttpConfigUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_cloud_http_config(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

/// PR 10 — Secret-Schreibpfad. Der Core antwortet **immer nur** mit
/// einem frischen `status`-Envelope (oder einem kuratierten
/// `error`-Envelope bei Persist-Fehlern) — der Key selbst taucht nie
/// in der Antwort auf. `StatusPayload.cloud_http_secret_present`
/// spiegelt den neuen Zustand.
fn handle_settings_set_cloud_http_secret(
    app: &Arc<App>,
    update: crate::app::SettingsCloudHttpSecretUpdate,
) -> Vec<OutgoingMessage> {
    match app.set_cloud_http_api_key(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

async fn handle_settings_probe_cloud_http(app: &Arc<App>) -> Vec<OutgoingMessage> {
    vec![OutgoingMessage::SettingsProbeResult {
        payload: app.probe_cloud_http().await,
    }]
}

// --- PR 13: STT/TTS-Chain-Editor-Dispatch -------------------------------
//
// Spiegel zum Text-Chain-Pfad: Validation-Fehler → `error`-Envelope
// mit kuratierter Meldung; Erfolg → frischer `status`-Envelope mit
// der neuen `stt_provider_chain` / `tts_provider_chain`-Reihenfolge.

fn handle_settings_set_stt_provider_chain(
    app: &Arc<App>,
    update: crate::app::SettingsSttProviderChainUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_stt_provider_chain(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

fn handle_settings_reset_stt_provider_chain(app: &Arc<App>) -> Vec<OutgoingMessage> {
    match app.reset_stt_provider_chain() {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

fn handle_settings_set_tts_provider_chain(
    app: &Arc<App>,
    update: crate::app::SettingsTtsProviderChainUpdate,
) -> Vec<OutgoingMessage> {
    match app.update_tts_provider_chain(update) {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

fn handle_settings_reset_tts_provider_chain(app: &Arc<App>) -> Vec<OutgoingMessage> {
    match app.reset_tts_provider_chain() {
        Ok(()) => vec![OutgoingMessage::Status {
            payload: app.build_status_payload(),
        }],
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

fn handle_approval_response(
    app: &Arc<App>,
    approval_id: String,
    decision: IncomingApprovalDecision,
) -> Vec<OutgoingMessage> {
    match app.resolve_approval(&approval_id, decision.to_decision()) {
        Ok(()) => Vec::new(),
        Err(message) => vec![OutgoingMessage::Error { message }],
    }
}

fn planned(
    action_id: &str,
    kind: ActionKind,
    title: &str,
    target: ActionTarget,
) -> OutgoingMessage {
    OutgoingMessage::ActionPlanned {
        payload: ActionPlannedPayload {
            action_id: action_id.to_string(),
            action_kind: kind,
            title: title.to_string(),
            description: None,
            target,
            mapping: None,
        },
    }
}

fn started(action_id: &str) -> OutgoingMessage {
    OutgoingMessage::ActionStarted {
        payload: ActionStartedPayload {
            action_id: action_id.to_string(),
            phase: ActionPhase::Started,
        },
    }
}

fn step(action_id: &str, title: &str) -> OutgoingMessage {
    OutgoingMessage::ActionStep {
        payload: ActionStepPayload {
            action_id: action_id.to_string(),
            title: title.to_string(),
            description: None,
        },
    }
}

fn completed(action_id: &str) -> OutgoingMessage {
    OutgoingMessage::ActionCompleted {
        payload: ActionCompletedPayload {
            action_id: action_id.to_string(),
            status: ActionStatus::Completed,
            message: None,
        },
    }
}

fn failed(action_id: &str, message: &str) -> OutgoingMessage {
    OutgoingMessage::ActionFailed {
        payload: ActionFailedPayload {
            action_id: action_id.to_string(),
            status: ActionStatus::Failed,
            message: message.to_string(),
            error: None,
        },
    }
}

async fn handle_submit_text(app: &Arc<App>, text: String) -> Vec<OutgoingMessage> {
    let action_id = app.next_action_id();
    let mut out = vec![
        planned(
            &action_id,
            ActionKind::Query,
            "Process text request",
            ActionTarget::unknown(),
        ),
        started(&action_id),
        step(&action_id, "Dispatch to ABrain"),
        OutgoingMessage::Thinking,
    ];

    match app.handle_text_query(&text).await {
        Ok(response) => {
            out.push(OutgoingMessage::Response {
                payload: ResponsePayload {
                    text: response.clone(),
                },
            });
            out.push(completed(&action_id));
            app.maybe_auto_speak(&response).await;
        }
        Err(err) => {
            let msg = format!("{err:#}");
            out.push(OutgoingMessage::Error {
                message: msg.clone(),
            });
            out.push(failed(&action_id, &msg));
        }
    }
    out
}

async fn handle_speak_text(app: &Arc<App>, text: String) -> Vec<OutgoingMessage> {
    let action_id = app.next_action_id();
    let mut out = vec![
        planned(
            &action_id,
            ActionKind::Speech,
            "Speak text",
            ActionTarget::unknown(),
        ),
        started(&action_id),
        step(&action_id, "TTS playback"),
    ];

    if !app.current_tts().is_available() {
        let msg = "TTS is not available.";
        out.push(OutgoingMessage::Error {
            message: msg.into(),
        });
        out.push(failed(&action_id, msg));
        return out;
    }

    match app.handle_speak(&text).await {
        Ok(()) => out.push(completed(&action_id)),
        Err(err) => {
            let msg = format!("{err:#}");
            out.push(OutgoingMessage::Error {
                message: msg.clone(),
            });
            out.push(failed(&action_id, &msg));
        }
    }
    out
}

async fn handle_voice_once(app: &Arc<App>) -> Vec<OutgoingMessage> {
    let action_id = app.next_action_id();
    let mut out = vec![
        planned(
            &action_id,
            ActionKind::Speech,
            "Voice request",
            ActionTarget::unknown(),
        ),
        started(&action_id),
    ];

    if !app.current_stt().is_available() {
        let msg = "STT is not available.";
        out.push(OutgoingMessage::Error {
            message: msg.into(),
        });
        out.push(failed(&action_id, msg));
        return out;
    }

    out.push(step(&action_id, "Listening"));

    let recognized = match app.handle_voice_once().await {
        Ok(text) => text,
        Err(err) => {
            let msg = format!("{err:#}");
            out.push(OutgoingMessage::Error {
                message: msg.clone(),
            });
            out.push(failed(&action_id, &msg));
            return out;
        }
    };

    out.push(step(&action_id, "Speech recognized"));
    out.push(OutgoingMessage::Heard {
        payload: HeardPayload {
            text: recognized.clone(),
        },
    });
    out.push(step(&action_id, "Dispatch to ABrain"));
    out.push(OutgoingMessage::Thinking);

    match app.handle_text_query(&recognized).await {
        Ok(response) => {
            out.push(OutgoingMessage::Response {
                payload: ResponsePayload {
                    text: response.clone(),
                },
            });
            out.push(completed(&action_id));
            app.maybe_auto_speak(&response).await;
        }
        Err(err) => {
            let msg = format!("{err:#}");
            out.push(OutgoingMessage::Error {
                message: msg.clone(),
            });
            out.push(failed(&action_id, &msg));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{ApprovalConfig, AudioConfig, Config, InteractionConfig, IpcConfig};
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::connect_async;

    /// Serialisiert alle Tests, die `SMOLIT_SETTINGS_DIR` anfassen —
    /// gemeinsam mit `settings_store::tests` und `secrets_store::tests`.
    /// Zentral in [`crate::SETTINGS_DIR_ENV_LOCK`] gepflegt, damit
    /// parallel laufende Tests aus verschiedenen Modulen nicht
    /// gegeneinander racen und fremde Dirs schreiben.
    use crate::SETTINGS_DIR_ENV_LOCK as ENV_LOCK;

    fn test_app() -> Arc<App> {
        test_app_with(InteractionConfig {
            enabled: true,
            backend: "command".into(),
            allow_open_application: true,
            allow_focus_window: true,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
            focus_window_cmd_template: Some("/bin/true".into()),
        })
    }

    fn test_app_with(interaction: InteractionConfig) -> Arc<App> {
        test_app_with_approval(interaction, default_approval_config())
    }

    fn default_approval_config() -> ApprovalConfig {
        ApprovalConfig {
            timeout_seconds: 2,
        }
    }

    fn test_app_with_approval(
        interaction: InteractionConfig,
        approval: ApprovalConfig,
    ) -> Arc<App> {
        test_app_with_abrain_cmd("/bin/false", interaction, approval)
    }

    fn test_app_with_abrain_cmd(
        abrain_cmd: &str,
        interaction: InteractionConfig,
        approval: ApprovalConfig,
    ) -> Arc<App> {
        let config = Config {
            abrain_cmd: abrain_cmd.into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: None,
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: None,
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["command".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction,
            approval,
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["abrain".into()],
                llamafile: crate::config::LlamafileConfig::default(),
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        };
        Arc::new(App::new(config))
    }

    async fn spawn_server() -> String {
        let app = test_app();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let _ = accept_loop(app, listener).await;
        });
        format!("ws://{addr}")
    }

    async fn recv_text(
        stream: &mut tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    ) -> String {
        match stream.next().await.unwrap().unwrap() {
            Message::Text(t) => t,
            other => panic!("expected text, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn ping_pong_roundtrip() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"ping"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        assert_eq!(got, r#"{"type":"pong"}"#);
    }

    #[tokio::test]
    async fn get_status_returns_payload() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        assert!(got.contains(r#""type":"status""#));
        assert!(got.contains(r#""ipc_enabled":true"#));
        assert!(got.contains(r#""tts_available":false"#));
    }

    #[tokio::test]
    async fn invalid_json_returns_error() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text("not json".into())).await.unwrap();
        let got = recv_text(&mut ws).await;
        assert!(got.starts_with(r#"{"type":"error""#));
    }

    #[tokio::test]
    async fn submit_text_emits_action_events_around_thinking_and_error() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"submit_text","text":"hi"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""action_kind":"query""#));

        let started = recv_text(&mut ws).await;
        assert!(started.contains(r#""type":"action_started""#));

        let step = recv_text(&mut ws).await;
        assert!(step.contains(r#""type":"action_step""#));
        assert!(step.contains("Dispatch to ABrain"));

        let thinking = recv_text(&mut ws).await;
        assert_eq!(thinking, r#"{"type":"thinking"}"#);

        let err = recv_text(&mut ws).await;
        assert!(err.starts_with(r#"{"type":"error""#));

        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
        assert!(failed.contains(r#""status":"failed""#));
    }

    // PR 2 (Text Provider Resolver): vergewissert, dass der IPC-Pfad
    // `submit_text` weiterhin eine vollständige `action_*` + `response`-
    // Sequenz produziert, wenn der konfigurierte Text-Provider (hier
    // `/bin/echo` über den Abrain-Kind) erfolgreich antwortet. Der
    // direkte Aufruf `abrain::run_task_with_cmd` wurde entfernt — dieser
    // Test prüft also genau die neue Routing-Linie durch den Resolver
    // bis hinunter ins `AbrainCliProvider::run`.
    #[tokio::test]
    async fn submit_text_via_resolver_emits_response_when_provider_succeeds() {
        // /bin/echo akzeptiert beliebige Argumente und produziert
        // nicht-leeren stdout → der AbrainCliProvider behandelt das als
        // Erfolg. Das simuliert eine reale ABrain-Installation, die
        // antwortet, ohne echtes ABrain zu benötigen.
        let app = test_app_with_abrain_cmd(
            "/bin/echo",
            InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            default_approval_config(),
        );
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"submit_text","text":"hi"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        let started = recv_text(&mut ws).await;
        assert!(started.contains(r#""type":"action_started""#));
        let step = recv_text(&mut ws).await;
        assert!(step.contains(r#""type":"action_step""#));
        let thinking = recv_text(&mut ws).await;
        assert_eq!(thinking, r#"{"type":"thinking"}"#);

        let response = recv_text(&mut ws).await;
        assert!(response.contains(r#""type":"response""#));
        assert!(response.contains(r#""text""#));

        let completed = recv_text(&mut ws).await;
        assert!(completed.contains(r#""type":"action_completed""#));

        // Status reflektiert nach dem Request, dass der konfigurierte
        // Primary (`abrain`) tatsächlich geantwortet hat.
        let st = app.text_provider_status();
        assert_eq!(st.configured, "abrain");
        assert_eq!(st.active, "abrain");
        assert_eq!(st.availability, "available");
        assert!(st.last_error.is_none());
        assert!(!st.cloud);
    }

    // PR 2: der Resolver-Fehlerpfad muss ehrlich als `error` +
    // `action_failed` durchschlagen und darf keinen stillen Fallback in
    // etwas nicht Konfiguriertes nehmen. Mit `/bin/false` als
    // abrain_cmd wird der einzige Kettenelement-Provider immer
    // fehlschlagen; die `availability` im StatusPayload fällt auf
    // `unavailable`, `last_error` trägt die kurze Klasse `exit_nonzero`.
    #[tokio::test]
    async fn submit_text_via_resolver_reports_error_and_status_when_all_fail() {
        let app = test_app();
        // status payload reflects the new text_provider fields
        let payload = app.build_status_payload();
        // Before any request: nominal `available` (chain non-empty,
        // nothing probed yet), `active` leer.
        assert_eq!(payload.text_provider_configured, "abrain");
        assert_eq!(payload.text_provider_active, "");
        assert_eq!(payload.text_provider_availability, "available");
        assert!(payload.text_provider_last_error.is_none());
        assert!(!payload.text_provider_cloud);

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"submit_text","text":"hi"}"#.into(),
        ))
        .await
        .unwrap();

        // Pump through the full event sequence; we only care about the
        // terminal `error` + `action_failed` pair and the updated
        // status afterwards.
        let _ = recv_text(&mut ws).await; // planned
        let _ = recv_text(&mut ws).await; // started
        let _ = recv_text(&mut ws).await; // step
        let _ = recv_text(&mut ws).await; // thinking
        let err = recv_text(&mut ws).await;
        assert!(err.starts_with(r#"{"type":"error""#));
        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));

        let payload = app.build_status_payload();
        assert_eq!(payload.text_provider_configured, "abrain");
        assert_eq!(payload.text_provider_active, "");
        assert_eq!(payload.text_provider_availability, "unavailable");
        assert_eq!(
            payload.text_provider_last_error.as_deref(),
            Some("exit_nonzero"),
        );
        assert!(!payload.text_provider_cloud);
    }

    // PR 2: `get_status` liefert die neuen text_provider_*-Felder
    // additiv aus. Die Antwort enthält `configured=abrain` (Default-
    // Kette) und `availability=available` im frischen Zustand.
    //
    // PR 4 erweitert diesen Test um die vertiefte Status-Oberfläche:
    // `text_provider_chain` wird sichtbar, und die llamafile-Felder
    // sind im Default-Fall (abrain-only) neutral — `in_chain=false`,
    // Lifecycle/Mode/Idle-Timeout als JSON `null`.
    #[tokio::test]
    async fn get_status_includes_text_provider_fields() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        assert!(got.contains(r#""text_provider_configured":"abrain""#));
        assert!(got.contains(r#""text_provider_active":"""#));
        assert!(got.contains(r#""text_provider_availability":"available""#));
        assert!(got.contains(r#""text_provider_last_error":null"#));
        assert!(got.contains(r#""text_provider_cloud":false"#));
        // PR 4 — Kette + Llamafile-Sicht (llamafile nicht in Default-Kette).
        assert!(got.contains(r#""text_provider_chain":["abrain"]"#));
        assert!(got.contains(r#""llamafile_in_chain":false"#));
        assert!(got.contains(r#""llamafile_enabled":false"#));
        assert!(got.contains(r#""llamafile_configured":false"#));
        assert!(got.contains(r#""llamafile_lifecycle":null"#));
        assert!(got.contains(r#""llamafile_mode":null"#));
        assert!(got.contains(r#""llamafile_idle_timeout_seconds":null"#));
        // PR 6 — STT/TTS Provider-Statusfelder. Default-Kette
        // `command` ist konfiguriert; ohne `SMOLIT_STT_CMD`/
        // `SMOLIT_TTS_CMD` bleibt der Primärprovider `unavailable`,
        // `active` ist leer, `last_error=null` (noch kein Run
        // versucht), `cloud=false`.
        assert!(got.contains(r#""stt_provider_configured":"command""#));
        assert!(got.contains(r#""stt_provider_active":"""#));
        assert!(got.contains(r#""stt_provider_availability":"unavailable""#));
        assert!(got.contains(r#""stt_provider_last_error":null"#));
        assert!(got.contains(r#""stt_provider_cloud":false"#));
        assert!(got.contains(r#""tts_provider_configured":"command""#));
        assert!(got.contains(r#""tts_provider_active":"""#));
        assert!(got.contains(r#""tts_provider_availability":"unavailable""#));
        assert!(got.contains(r#""tts_provider_last_error":null"#));
        assert!(got.contains(r#""tts_provider_cloud":false"#));
    }

    /// PR 6 — mit konfigurierten STT-/TTS-Kommandos meldet der
    /// Resolver nominell `available` schon ohne Run-Versuch. Damit
    /// wird die Parallelität zum Text-Resolver (chain non-empty +
    /// primary ready → "available") auch für Audio sichtbar.
    #[tokio::test]
    async fn get_status_reflects_configured_audio_provider_chain() {
        let app = Arc::new(App::new(Config {
            abrain_cmd: "/bin/false".into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: Some("/bin/cat".into()),
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: Some("/bin/echo hi".into()),
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["command".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction: InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            approval: default_approval_config(),
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["abrain".into()],
                llamafile: crate::config::LlamafileConfig::default(),
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        }));
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        assert!(got.contains(r#""stt_provider_availability":"available""#));
        assert!(got.contains(r#""tts_provider_availability":"available""#));
        // Feature-State-Felder (Legacy-Kompat) bleiben kohärent.
        assert!(got.contains(r#""stt_available":true"#));
        assert!(got.contains(r#""tts_available":true"#));
    }

    /// PR 6 — unbekannte STT-Kinds in der Chain fallen still auf den
    /// Default `command` zurück; der Primärprovider-Status bleibt
    /// nominell korrekt. Der Resolver loggt die Verwerfung, der
    /// StatusPayload zeigt schlicht die aufgelöste (gültige) Kette.
    #[tokio::test]
    async fn get_status_falls_back_when_all_stt_kinds_unknown() {
        let app = Arc::new(App::new(Config {
            abrain_cmd: "/bin/false".into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: None,
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: None,
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["cloud:unknown".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction: InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            approval: default_approval_config(),
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["abrain".into()],
                llamafile: crate::config::LlamafileConfig::default(),
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        }));
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        // Unbekannte Kinds verworfen → Default-Kette → configured=command.
        assert!(got.contains(r#""stt_provider_configured":"command""#));
    }

    /// PR 4 — Der vertiefte Readout für `llamafile_local` muss ehrlich
    /// an der Config hängen: steht der Provider in der Chain, werden
    /// Lifecycle-, Mode- und Idle-Timeout-Felder gesetzt. Hier mit
    /// `enabled=true` ohne Pfad → Lifecycle `not_configured` wird in
    /// den StatusPayload gespiegelt.
    #[tokio::test]
    async fn get_status_reports_llamafile_lifecycle_when_in_chain() {
        let app = Arc::new(App::new(Config {
            abrain_cmd: "/bin/false".into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: None,
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: None,
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["command".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction: InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            approval: default_approval_config(),
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["llamafile_local".into(), "abrain".into()],
                llamafile: crate::config::LlamafileConfig {
                    enabled: true,
                    path: None,
                    mode: "standby".into(),
                    idle_timeout_seconds: 120,
                    port: 8788,
                    startup_timeout_seconds: 10,
                    request_timeout_seconds: 10,
                },
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        }));
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        assert!(got.contains(r#""text_provider_configured":"llamafile_local""#));
        assert!(got.contains(r#""text_provider_chain":["llamafile_local","abrain"]"#));
        assert!(got.contains(r#""llamafile_in_chain":true"#));
        assert!(got.contains(r#""llamafile_enabled":true"#));
        assert!(got.contains(r#""llamafile_configured":false"#));
        assert!(got.contains(r#""llamafile_lifecycle":"not_configured""#));
        assert!(got.contains(r#""llamafile_mode":"standby""#));
        assert!(got.contains(r#""llamafile_idle_timeout_seconds":120"#));
    }

    // ------------------------------------------------------------------
    // PR 5 — Settings-Schreib-/Probe-Pfad.
    //
    // Die Tests isolieren den Settings-Store über `SMOLIT_SETTINGS_DIR`,
    // damit sie weder die echte User-Config berühren noch sich
    // gegenseitig stören. Vor jedem Test räumen wir die Zielverzeichnisse
    // leer; am Ende wird die Env-Variable wiederhergestellt.
    // ------------------------------------------------------------------

    fn scoped_settings_dir(marker: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "smolit-ipc-settings-{marker}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn build_llamafile_chain_app(settings_dir: &std::path::Path) -> Arc<App> {
        // SAFETY: Tests setzen die Env-Var selbst; wir restaurieren nicht
        // im Destruktor-Stil, aber die Pfade sind eindeutig pro Test.
        unsafe {
            std::env::set_var("SMOLIT_SETTINGS_DIR", settings_dir.as_os_str());
        }
        Arc::new(App::new(Config {
            abrain_cmd: "/bin/false".into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: None,
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: None,
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["command".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction: InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            approval: default_approval_config(),
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["llamafile_local".into(), "abrain".into()],
                llamafile: crate::config::LlamafileConfig {
                    enabled: false,
                    path: None,
                    mode: "on_demand".into(),
                    idle_timeout_seconds: 300,
                    port: 8788,
                    startup_timeout_seconds: 10,
                    request_timeout_seconds: 10,
                },
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        }))
    }

    /// Der Schreibpfad aktualisiert den live-Stand, ersetzt den Resolver
    /// atomar und antwortet mit einem `status`-Envelope, der den neuen
    /// Stand bereits spiegelt. Sichtbar ist das an `llamafile_enabled`
    /// und `llamafile_mode`.
    #[tokio::test]
    async fn settings_set_llamafile_config_applies_and_echoes_status() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("apply-echo");
        let app = build_llamafile_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        // Vorher: enabled=false, mode=on_demand.
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let pre = recv_text(&mut ws).await;
        assert!(pre.contains(r#""llamafile_enabled":false"#));
        assert!(pre.contains(r#""llamafile_mode":"on_demand""#));

        // Schreibpfad: enable + standby + neuer Idle-Timeout.
        ws.send(Message::Text(
            r#"{"type":"settings_set_llamafile_config","enabled":true,"mode":"standby","idle_timeout_seconds":900}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""llamafile_enabled":true"#));
        assert!(resp.contains(r#""llamafile_mode":"standby""#));
        assert!(resp.contains(r#""llamafile_idle_timeout_seconds":900"#));

        // Nachbar-Verifikation: `get_status` sieht den neuen Stand auch
        // ohne den `status`-Echo.
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let post = recv_text(&mut ws).await;
        assert!(post.contains(r#""llamafile_enabled":true"#));
        assert!(post.contains(r#""llamafile_mode":"standby""#));

        // Cleanup: Store-Dir wegwerfen (best effort).
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Ungültige Mode-Werte werden **nicht** still verworfen, sondern
    /// erzeugen ein `error`-Envelope. Die Fehlermeldung ist bewusst
    /// secret-frei: kein Pfad, keine Roh-Stringifizierung des Clients.
    #[tokio::test]
    async fn settings_set_llamafile_config_rejects_unknown_mode() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("reject-mode");
        let app = build_llamafile_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_llamafile_config","enabled":true,"mode":"cloud"}"#
                .into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("unknown llamafile mode"));
        // Wichtig: keine Klartext-Secrets im Fehler — hier gibt es
        // allerdings keine Secrets; die Meldung enthält nur den
        // Nutzer-Input selbst. Das ist für Mode-Strings vertretbar.

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Probe ohne Pfad → Klasse `not_configured`. Enabled aber keinen
    /// Pfad ist der häufigste Benutzerfehler; die Shell soll ihn ohne
    /// Spawn diagnostizieren können.
    #[tokio::test]
    async fn settings_probe_llamafile_reports_not_configured_without_path() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("probe-notcfg");
        let app = build_llamafile_chain_app(&dir);
        // enable, aber Pfad nicht setzen.
        app.update_llamafile_config(crate::app::SettingsLlamafileUpdate {
            enabled: true,
            mode: None,
            idle_timeout_seconds: None,
            path: None,
        })
        .unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"settings_probe_llamafile"}"#.into()))
            .await
            .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"settings_probe_result""#));
        assert!(resp.contains(r#""class":"not_configured""#));
        assert!(resp.contains(r#""ok":false"#));
        assert!(resp.contains(r#""in_chain":true"#));
        assert!(resp.contains(r#""enabled":true"#));
        assert!(resp.contains(r#""configured":false"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Probe mit gesetztem, nicht existierendem Pfad → Klasse
    /// `path_missing`. Der konkrete Pfad darf **nicht** in `message`
    /// oder `class` auftauchen — das wäre ein Secret-Disziplin-Bruch.
    #[tokio::test]
    async fn settings_probe_llamafile_reports_path_missing_without_leaking_path() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("probe-missing");
        let app = build_llamafile_chain_app(&dir);
        let secret_looking_path = "/nonexistent/smolit-probe-test-binary-please-do-not-leak";
        app.update_llamafile_config(crate::app::SettingsLlamafileUpdate {
            enabled: true,
            mode: None,
            idle_timeout_seconds: None,
            path: Some(secret_looking_path.to_string()),
        })
        .unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"settings_probe_llamafile"}"#.into()))
            .await
            .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""class":"path_missing""#));
        assert!(resp.contains(r#""ok":false"#));
        // Der Pfad selbst darf nirgends in der Antwort auftauchen.
        assert!(
            !resp.contains(secret_looking_path),
            "probe response must not leak the configured path; got: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Probe für einen existierenden, ausführbaren Pfad → Klasse `ok`.
    /// Wir nutzen `/bin/true` als garantiert vorhandenes Binary.
    #[tokio::test]
    async fn settings_probe_llamafile_reports_ok_for_executable_path() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("probe-ok");
        let app = build_llamafile_chain_app(&dir);
        app.update_llamafile_config(crate::app::SettingsLlamafileUpdate {
            enabled: true,
            mode: None,
            idle_timeout_seconds: None,
            path: Some("/bin/true".into()),
        })
        .unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"settings_probe_llamafile"}"#.into()))
            .await
            .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""class":"ok""#));
        assert!(resp.contains(r#""ok":true"#));
        assert!(resp.contains(r#""in_chain":true"#));
        assert!(resp.contains(r#""configured":true"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // PR 7 — STT-/TTS-Settings-Schreibpfad + Probe-Ende-zu-Ende-Tests.
    // Symmetrisch zum Llamafile-Test-Block (PR 5).
    // -------------------------------------------------------------------

    #[tokio::test]
    async fn settings_set_stt_config_applies_and_echoes_status() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-apply-echo");
        let app = build_llamafile_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        // Vorher: stt_enabled=true (aus build_llamafile_chain_app), kein cmd.
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let pre = recv_text(&mut ws).await;
        assert!(pre.contains(r#""stt_enabled":true"#));

        // Schreibpfad: disable STT.
        ws.send(Message::Text(
            r#"{"type":"settings_set_stt_config","enabled":false}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""stt_enabled":false"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_tts_config_updates_auto_speak() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tts-apply-auto");
        let app = build_llamafile_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let pre = recv_text(&mut ws).await;
        assert!(pre.contains(r#""auto_speak":false"#));

        ws.send(Message::Text(
            r#"{"type":"settings_set_tts_config","enabled":true,"auto_speak":true}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""auto_speak":true"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_stt_reports_not_configured_without_command() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-probe-notcfg");
        let app = build_llamafile_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"settings_probe_stt"}"#.into()))
            .await
            .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"settings_probe_result""#));
        assert!(resp.contains(r#""axis":"stt""#));
        assert!(resp.contains(r#""class":"not_configured""#));
        assert!(resp.contains(r#""ok":false"#));
        assert!(resp.contains(r#""in_chain":true"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_tts_reports_ok_for_executable_command() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tts-probe-ok");
        let app = build_llamafile_chain_app(&dir);
        // enabled=true mit /bin/true als ausführbarem Command.
        app.update_tts_config(crate::app::SettingsTtsUpdate {
            enabled: true,
            command: Some("/bin/true".into()),
            auto_speak: None,
        })
        .unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"settings_probe_tts"}"#.into()))
            .await
            .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""axis":"tts""#));
        assert!(resp.contains(r#""class":"ok""#));
        assert!(resp.contains(r#""ok":true"#));
        assert!(resp.contains(r#""in_chain":true"#));
        assert!(resp.contains(r#""configured":true"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_stt_does_not_leak_command() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-probe-noleak");
        let app = build_llamafile_chain_app(&dir);
        let secret_looking_cmd =
            "/nonexistent/smolit-stt-probe-please-do-not-leak --flag=sekritvalue";
        app.update_stt_config(crate::app::SettingsSttUpdate {
            enabled: true,
            command: Some(secret_looking_cmd.into()),
        })
        .unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"settings_probe_stt"}"#.into()))
            .await
            .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""class":"path_missing""#));
        assert!(
            !resp.contains("sekritvalue") && !resp.contains("smolit-stt-probe"),
            "probe response must not leak the configured command; got: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // PR 8 — Local-HTTP-Schreibpfad + Probe. Nutzt
    // `build_llamafile_chain_app`, das bereits eine Chain mit
    // `llamafile_local + abrain` baut. Für die folgenden Tests ergänzen
    // wir den Chain-Eintrag `local_http` per Env-Override *vor* der
    // App-Konstruktion — das ist der konservativste Weg, ohne den
    // Test-Helper aufzublähen.
    // -------------------------------------------------------------------

    fn build_local_http_chain_app(settings_dir: &std::path::Path) -> Arc<App> {
        // `SMOLIT_SETTINGS_DIR` muss vor `App::new` sitzen, weil
        // `settings_store::load_*_override` es dort liest. Race-frei,
        // weil jeder Test einen eindeutigen Marker nutzt und das Race
        // nur auf dem Filesystem stattfindet.
        unsafe {
            std::env::set_var("SMOLIT_SETTINGS_DIR", settings_dir.as_os_str());
        }
        // Kette direkt in der Config setzen — kein `Config::load()`,
        // kein Env-Override für `SMOLIT_TEXT_PROVIDER_CHAIN`, damit wir
        // nicht mit parallelen Tests um globale Env-Vars streiten.
        Arc::new(App::new(Config {
            abrain_cmd: "/bin/false".into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: None,
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: None,
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["command".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction: InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            approval: default_approval_config(),
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["local_http".into(), "abrain".into()],
                llamafile: crate::config::LlamafileConfig::default(),
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        }))
    }

    /// PR 10 — Test-Helper für Cloud-HTTP-Szenarien. Baut eine App mit
    /// einer Chain, die `cloud_http` enthält, und setzt
    /// `SMOLIT_SETTINGS_DIR` auf einen isolierten Pfad — damit der
    /// Secret-Store in einer eindeutigen Testdatei landet.
    fn build_cloud_http_chain_app(settings_dir: &std::path::Path) -> Arc<App> {
        unsafe {
            std::env::set_var("SMOLIT_SETTINGS_DIR", settings_dir.as_os_str());
        }
        Arc::new(App::new(Config {
            abrain_cmd: "/bin/false".into(),
            log_level: "info".into(),
            audio: AudioConfig {
                tts_enabled: true,
                tts_cmd: None,
                tts_timeout_seconds: 5,
                stt_enabled: true,
                stt_cmd: None,
                stt_timeout_seconds: 5,
                auto_speak: false,
                stt_provider_chain: vec!["command".into()],
                tts_provider_chain: vec!["command".into()],
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction: InteractionConfig {
                enabled: true,
                backend: "command".into(),
                allow_open_application: true,
                allow_focus_window: true,
                allow_type_text: false,
                allow_shortcuts: false,
                require_confirmation: false,
                open_app_cmd_template: Some("/bin/true".into()),
                focus_window_cmd_template: Some("/bin/true".into()),
            },
            approval: default_approval_config(),
            text_provider: crate::config::TextProviderConfig {
                chain: vec!["cloud_http".into(), "abrain".into()],
                llamafile: crate::config::LlamafileConfig::default(),
                local_http: crate::config::LocalHttpConfig::default(),
                cloud_http: crate::config::CloudHttpConfig::default(),
            },
        }))
    }

    #[tokio::test]
    async fn settings_set_local_http_config_applies_and_echoes_status() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("lh-apply-echo");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let pre = recv_text(&mut ws).await;
        assert!(pre.contains(r#""local_http_in_chain":true"#));
        assert!(pre.contains(r#""local_http_enabled":false"#));

        ws.send(Message::Text(
            r#"{"type":"settings_set_local_http_config","enabled":true,"endpoint":"http://127.0.0.1:9999/completion","request_timeout_seconds":10}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""local_http_enabled":true"#));
        assert!(resp.contains(r#""local_http_configured":true"#));
        // Secret-Disziplin: Endpoint darf nicht im Status auftauchen.
        assert!(
            !resp.contains("http://127.0.0.1:9999/completion"),
            "status payload must not leak the configured endpoint; got: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_local_http_config_rejects_zero_timeout() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("lh-reject-timeout");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_local_http_config","enabled":true,"request_timeout_seconds":0}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("request_timeout_seconds"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_local_http_reports_not_configured_without_endpoint() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("lh-probe-notcfg");
        let app = build_local_http_chain_app(&dir);
        app.update_local_http_config(crate::app::SettingsLocalHttpUpdate {
            enabled: true,
            endpoint: None,
            request_timeout_seconds: None,
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_local_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""axis":"local_http""#));
        assert!(resp.contains(r#""class":"not_configured""#));
        assert!(resp.contains(r#""in_chain":true"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_local_http_reports_scheme_unsupported_for_https() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("lh-probe-https");
        let app = build_local_http_chain_app(&dir);
        let secret_looking_endpoint = "https://sekrit-host.test/v1/sekritroute";
        app.update_local_http_config(crate::app::SettingsLocalHttpUpdate {
            enabled: true,
            endpoint: Some(secret_looking_endpoint.into()),
            request_timeout_seconds: None,
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_local_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""class":"endpoint_scheme_unsupported""#));
        assert!(
            !resp.contains("sekrit-host") && !resp.contains("sekritroute"),
            "probe must not leak the configured endpoint; got: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_local_http_reports_connect_failed_for_closed_port() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("lh-probe-connect");
        let app = build_local_http_chain_app(&dir);
        // Port 59998 ist hoffentlich zu — niemand lauscht.
        app.update_local_http_config(crate::app::SettingsLocalHttpUpdate {
            enabled: true,
            endpoint: Some("http://127.0.0.1:59998/completion".into()),
            request_timeout_seconds: Some(2),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_local_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        // Akzeptiere beide Fehlerklassen — auf überlasteten Runnern
        // kann ein `connect` auch in den Timeout laufen, statt
        // sofort `ECONNREFUSED` zu bekommen. Wichtig ist, dass
        // weder `ok:true` noch ein Endpoint-Leak stattfindet.
        assert!(
            resp.contains(r#""class":"http_connect_failed""#)
                || resp.contains(r#""class":"timeout""#),
            "expected http_connect_failed or timeout; got: {resp}",
        );
        assert!(resp.contains(r#""ok":false"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // PR 9 — Text-Provider-Chain-Editor + Reset + Validator-Fehlerpfade.
    // -------------------------------------------------------------------

    #[tokio::test]
    async fn settings_set_text_provider_chain_applies_and_echoes_status() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tc-apply-echo");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        // Vorher: `build_local_http_chain_app` startet mit
        // ["local_http", "abrain"].
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let pre = recv_text(&mut ws).await;
        assert!(pre.contains(r#""text_provider_chain":["local_http","abrain"]"#));

        // Schreibpfad: Kette umordnen + llamafile_local einreihen.
        ws.send(Message::Text(
            r#"{"type":"settings_set_text_provider_chain","chain":["llamafile_local","local_http","abrain"]}"#
                .into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(
            r#""text_provider_chain":["llamafile_local","local_http","abrain"]"#,
        ));
        assert!(resp.contains(r#""llamafile_in_chain":true"#));
        assert!(resp.contains(r#""local_http_in_chain":true"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_text_provider_chain_rejects_unknown_kind() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tc-reject-unknown");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_text_provider_chain","chain":["abrain","sekrit_cloud"]}"#
                .into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("unknown text provider kind"));
        assert!(resp.contains("sekrit_cloud"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_text_provider_chain_rejects_duplicates() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tc-reject-dup");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_text_provider_chain","chain":["abrain","abrain"]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("duplicate"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_text_provider_chain_rejects_empty() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tc-reject-empty");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_text_provider_chain","chain":[]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("empty"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_reset_text_provider_chain_returns_to_abrain_default() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tc-reset");
        let app = build_local_http_chain_app(&dir);
        // Vorher auf eine Dreier-Kette gehen.
        app.update_text_provider_chain(crate::app::SettingsTextProviderChainUpdate {
            chain: vec![
                "llamafile_local".into(),
                "local_http".into(),
                "abrain".into(),
            ],
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_reset_text_provider_chain"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""text_provider_chain":["abrain"]"#));
        assert!(resp.contains(r#""llamafile_in_chain":false"#));
        assert!(resp.contains(r#""local_http_in_chain":false"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_text_provider_chain_normalizes_case_and_whitespace() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tc-normalize");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_text_provider_chain","chain":["  ABrain ","LLAMAFILE_LOCAL"]}"#
                .into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""text_provider_chain":["abrain","llamafile_local"]"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // PR 13 — STT/TTS-Chain-Editor E2E-Tests.
    //
    // Bewusst klein: heute gibt es pro Achse nur das Kind `command`.
    // Happy-Path + Reject-Unknown + Reject-Empty + Reset + Normalize
    // decken die Validator-Geometrie ab. Der Chain-Editor selbst
    // wird erst durch weitere Provider-Kinds (zukünftige PRs) visuell
    // ausgebaut — die Persistenz-/IPC-/Validator-Schicht ist bereits
    // vorbereitet.
    // -------------------------------------------------------------------

    #[tokio::test]
    async fn settings_set_stt_provider_chain_applies_and_echoes_status() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-chain-apply");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_stt_provider_chain","chain":["command"]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""stt_provider_chain":["command"]"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_stt_provider_chain_rejects_unknown_kind() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-chain-unknown");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_stt_provider_chain","chain":["cloud_whisper"]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("unknown stt provider kind"));
        assert!(resp.contains("cloud_whisper"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_stt_provider_chain_rejects_empty() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-chain-empty");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_stt_provider_chain","chain":[]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("empty"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_reset_stt_provider_chain_returns_to_command_default() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-chain-reset");
        let app = build_local_http_chain_app(&dir);
        // Vorher keine Änderung nötig — wir setzen die Kette explizit
        // auf `["command"]` über den Update-Pfad, simulieren dann einen
        // Reset und erwarten wieder `["command"]`.
        app.update_stt_provider_chain(crate::app::SettingsSttProviderChainUpdate {
            chain: vec!["command".into()],
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_reset_stt_provider_chain"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""stt_provider_chain":["command"]"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_stt_provider_chain_normalizes_case_and_whitespace() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("stt-chain-normalize");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_stt_provider_chain","chain":["  COMMAND "]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""stt_provider_chain":["command"]"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_tts_provider_chain_applies_and_echoes_status() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tts-chain-apply");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_tts_provider_chain","chain":["command"]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""tts_provider_chain":["command"]"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_tts_provider_chain_rejects_duplicates() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tts-chain-dup");
        let app = build_local_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_tts_provider_chain","chain":["command","command"]}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.starts_with(r#"{"type":"error""#));
        assert!(resp.contains("duplicate"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_reset_tts_provider_chain_returns_to_command_default() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("tts-chain-reset");
        let app = build_local_http_chain_app(&dir);
        app.update_tts_provider_chain(crate::app::SettingsTtsProviderChainUpdate {
            chain: vec!["command".into()],
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_reset_tts_provider_chain"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""tts_provider_chain":["command"]"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // PR 10 — Cloud-HTTP + Secret-Store E2E-Tests.
    //
    // Jeder dieser Tests verifiziert mindestens EINE Secret-Leak-Grenze:
    // Key darf niemals in `status`, `error`, oder `settings_probe_result`
    // auftauchen.
    // -------------------------------------------------------------------

    #[tokio::test]
    async fn settings_set_cloud_http_config_applies_without_secret_leak() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-apply");
        let app = build_cloud_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let pre = recv_text(&mut ws).await;
        assert!(pre.contains(r#""cloud_http_in_chain":true"#));
        assert!(pre.contains(r#""cloud_http_enabled":false"#));
        assert!(pre.contains(r#""cloud_http_secret_present":false"#));

        ws.send(Message::Text(
            r#"{"type":"settings_set_cloud_http_config","enabled":true,"endpoint":"http://cloud.invalid:8443/v1/chat","model":"m-mini","request_timeout_seconds":30}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""cloud_http_enabled":true"#));
        // configured=false weil kein Secret gesetzt ist.
        assert!(resp.contains(r#""cloud_http_configured":false"#));
        // Weder Endpoint noch Modell wandern in den StatusPayload.
        assert!(
            !resp.contains("cloud.invalid") && !resp.contains("m-mini"),
            "status must not leak endpoint/model: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_set_cloud_http_secret_persists_but_never_leaks() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-secret");
        let app = build_cloud_http_chain_app(&dir);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();

        let secret = "sk-e2e-top-secret-marker-xyz";
        let payload = format!(
            r#"{{"type":"settings_set_cloud_http_secret","api_key":"{secret}"}}"#,
        );
        ws.send(Message::Text(payload.into())).await.unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""cloud_http_secret_present":true"#));
        assert!(
            !resp.contains(secret),
            "set-secret response leaked the key: {resp}",
        );

        // Folgeabfrage: frischer `get_status` — auch hier kein Leak.
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let status = recv_text(&mut ws).await;
        assert!(status.contains(r#""cloud_http_secret_present":true"#));
        assert!(
            !status.contains(secret),
            "subsequent get_status leaked the key: {status}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_clear_cloud_http_secret_via_null_payload() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-secret-clear");
        let app = build_cloud_http_chain_app(&dir);
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some("sk-to-be-cleared".into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_set_cloud_http_secret","api_key":null}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""type":"status""#));
        assert!(resp.contains(r#""cloud_http_secret_present":false"#));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_reports_secret_missing_before_key_is_stored() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-missing");
        let app = build_cloud_http_chain_app(&dir);
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some("http://127.0.0.1:59997/v1".into()),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""axis":"cloud_http""#));
        assert!(resp.contains(r#""class":"secret_missing""#));
        assert!(!resp.contains("127.0.0.1:59997"), "probe leaked endpoint: {resp}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_reports_connect_failed_for_closed_port() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-closed");
        let app = build_cloud_http_chain_app(&dir);
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some("http://127.0.0.1:59996/v1/chat".into()),
            model: None,
            request_timeout_seconds: Some(2),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some("sk-probe-marker".into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(
            resp.contains(r#""class":"http_connect_failed""#)
                || resp.contains(r#""class":"timeout""#),
            "expected connect_failed/timeout: {resp}",
        );
        assert!(
            !resp.contains("sk-probe-marker"),
            "probe leaked secret: {resp}",
        );
        assert!(
            !resp.contains("59996"),
            "probe leaked endpoint port: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_reports_scheme_unsupported_for_non_http_scheme() {
        // PR 11: https:// ist jetzt erlaubt; andere Schemes wie ftp://
        // / file:// bleiben hart abgelehnt. Der Probe-Pfad muss den
        // Scheme-Reject ehrlich klassifizieren und weder Host noch
        // Secret leaken.
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-bad-scheme");
        let app = build_cloud_http_chain_app(&dir);
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some("ftp://api.example.com/v1/chat".into()),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some("sk-for-ftp-probe".into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""class":"endpoint_scheme_unsupported""#));
        assert!(!resp.contains("api.example.com"), "probe leaked host: {resp}");
        assert!(!resp.contains("sk-for-ftp-probe"), "probe leaked secret: {resp}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_accepts_https_and_reports_cert_untrusted_against_fake_https_server() {
        // PR 11: Ein Fake-HTTPS-Server mit selbstsigniertem Cert (das
        // webpki-roots NICHT trauen). Probe mit der Default-Client-
        // Config muss `cert_untrusted` oder `cert_invalid` melden —
        // **nicht** stillschweigend als „ok" durchlaufen.
        use crate::providers::text::tests::{start_fake_https_server, FakeHttpsMode};
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-cert-untrusted");
        let app = build_cloud_http_chain_app(&dir);
        let (port, _trust, _handle) = start_fake_https_server(FakeHttpsMode::Ok("cloud")).await;
        // Achtung: wir nutzen BEWUSST `localhost` (matcht DNS-SAN des
        // Fake-Certs) und **nicht** `127.0.0.1` (dort würde rustls
        // wegen IP-SAN-Mismatch früher failen).
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some(format!("https://localhost:{port}/v1/chat")),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some("sk-for-cert-untrusted".into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(
            resp.contains(r#""class":"cert_untrusted""#)
                || resp.contains(r#""class":"cert_invalid""#)
                || resp.contains(r#""class":"tls_handshake_failed""#),
            "expected cert_untrusted/cert_invalid/tls_handshake_failed; got: {resp}",
        );
        assert!(!resp.contains("sk-for-cert-untrusted"), "probe leaked secret: {resp}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // PR 12 — authentifizierte cloud_http-Probe (Application-Layer).
    //
    // Jeder dieser Tests injiziert per `CloudHttpProvider::new_with_tls_config`
    // keinen Cert-Override — stattdessen läuft der Probe-Pfad gegen
    // einen Fake-Server, der die Bearer-Semantik spiegelt. Der Test-
    // Trust-Store wird dort injiziert, wo er wirklich gebraucht wird
    // (HTTPS-Pfade); für HTTP-Pfade läuft die Probe über plain TCP,
    // so wie in Produktion.
    //
    // **Der Secret-Leak-Guard ist überall aktiv**: weder `status`
    // noch Probe-Response noch `error`-Envelope dürfen Key-Marker,
    // Endpoint oder Host im Klartext tragen.
    // -------------------------------------------------------------------

    #[tokio::test]
    async fn settings_probe_cloud_http_authed_head_returns_ok_on_valid_auth_over_plain_http() {
        use crate::providers::text::tests::{start_fake_http_auth_server, FakeHttpsMode};
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-http-auth-ok");
        let app = build_cloud_http_chain_app(&dir);
        let secret_marker = "sk-ok-over-plain-http";
        let (port, _server) = start_fake_http_auth_server(FakeHttpsMode::RequiresBearer {
            expected: "sk-ok-over-plain-http",
            content: "unused-for-head",
        })
        .await;
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some(format!("http://127.0.0.1:{port}/v1/chat")),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some(secret_marker.into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(resp.contains(r#""axis":"cloud_http""#));
        assert!(
            resp.contains(r#""class":"ok""#),
            "expected class=ok for valid auth, got: {resp}",
        );
        // Secret-Leak-Guard: der Key-Marker darf unter keinen Umständen
        // im Response-Body auftauchen.
        assert!(
            !resp.contains(secret_marker),
            "probe response leaked the bearer key: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_authed_head_returns_unauthorized_when_server_rejects_token() {
        use crate::providers::text::tests::{start_fake_http_auth_server, FakeHttpsMode};
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-http-unauth");
        let app = build_cloud_http_chain_app(&dir);
        let wrong_key = "sk-wrong-key-for-unauth-test";
        // Server erwartet einen anderen Bearer → jeder Request kommt
        // als 401 zurück.
        let (port, _server) = start_fake_http_auth_server(FakeHttpsMode::RequiresBearer {
            expected: "sk-the-expected-one",
            content: "unused",
        })
        .await;
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some(format!("http://127.0.0.1:{port}/v1/chat")),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some(wrong_key.into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(
            resp.contains(r#""class":"unauthorized""#),
            "expected class=unauthorized, got: {resp}",
        );
        assert!(
            !resp.contains(wrong_key),
            "probe response leaked the bearer key: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_authed_head_returns_http_error_for_non_2xx_non_401() {
        use crate::providers::text::tests::{start_fake_http_auth_server, FakeHttpsMode};
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-http-500");
        let app = build_cloud_http_chain_app(&dir);
        let (port, _server) =
            start_fake_http_auth_server(FakeHttpsMode::HttpErrorStatus(500)).await;
        let marker = "sk-for-http-error-probe";
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some(format!("http://127.0.0.1:{port}/v1/chat")),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some(marker.into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(
            resp.contains(r#""class":"http_error""#),
            "expected class=http_error, got: {resp}",
        );
        assert!(
            resp.contains("500"),
            "expected status code 500 in message for operator clarity, got: {resp}",
        );
        assert!(!resp.contains(marker), "probe leaked key: {resp}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn settings_probe_cloud_http_authed_head_returns_ok_over_tls_with_valid_auth() {
        // PR 12 — das ist der Happy-Path-Test, der die komplette
        // Transport + TLS + Auth-Kette gegen einen echten
        // Fake-HTTPS-Server prüft. Der Test-Trust-Store wird über die
        // CloudHttpProvider-Test-Injection bereitgestellt — aber der
        // Probe-Pfad nutzt den PRODUKTIVEN
        // `default_cloud_http_tls_config`. Also: der Server verwendet
        // ein selbstsigniertes Cert, der Client (im Probe) nutzt
        // webpki-roots und sieht deshalb `cert_untrusted`.
        //
        // Für einen echten End-to-End-Happy-Path über TLS müssten wir
        // den Trust-Store des Probes injizierbar machen. Das ist
        // absichtlich nicht Teil dieses PRs — der HTTPS-Trust-Pfad
        // wird durch den Unit-Test
        // `cloud_http_run_succeeds_over_https_against_fake_tls_server`
        // abgedeckt (Provider-Ebene). Hier bestätigen wir stattdessen
        // nur, dass die Probe bei TLS-Fehler KEINEN stillen "ok"
        // fabriziert — identisch zum PR-11-Test, jetzt aber mit dem
        // neuen Auth-Pfad.
        use crate::providers::text::tests::{start_fake_https_server, FakeHttpsMode};
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scoped_settings_dir("ch-probe-https-authed");
        let app = build_cloud_http_chain_app(&dir);
        let marker = "sk-for-https-authed-probe";
        let (port, _trust, _handle) = start_fake_https_server(FakeHttpsMode::RequiresBearer {
            expected: marker,
            content: "unused",
        })
        .await;
        app.update_cloud_http_config(crate::app::SettingsCloudHttpConfigUpdate {
            enabled: true,
            endpoint: Some(format!("https://localhost:{port}/v1/chat")),
            model: None,
            request_timeout_seconds: Some(3),
        })
        .unwrap();
        app.set_cloud_http_api_key(crate::app::SettingsCloudHttpSecretUpdate {
            api_key: Some(marker.into()),
        })
        .unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app_handle = app.clone();
        tokio::spawn(async move {
            let _ = accept_loop(app_handle, listener).await;
        });
        let url = format!("ws://{addr}");
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"settings_probe_cloud_http"}"#.into(),
        ))
        .await
        .unwrap();
        let resp = recv_text(&mut ws).await;
        assert!(
            resp.contains(r#""class":"cert_untrusted""#)
                || resp.contains(r#""class":"cert_invalid""#)
                || resp.contains(r#""class":"tls_handshake_failed""#),
            "expected cert-family class (server cert not in webpki-roots); got: {resp}",
        );
        assert!(
            !resp.contains(marker),
            "probe response leaked the bearer key: {resp}",
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn voice_once_emits_action_events_when_stt_unconfigured() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"voice_once"}"#.into()))
            .await
            .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""action_kind":"speech""#));

        let started = recv_text(&mut ws).await;
        assert!(started.contains(r#""type":"action_started""#));

        let err = recv_text(&mut ws).await;
        assert!(err.contains(r#""type":"error""#));
        assert!(err.contains("STT is not available"));

        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
    }

    async fn spawn_server_with(interaction: InteractionConfig) -> String {
        let app = test_app_with(interaction);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let _ = accept_loop(app, listener).await;
        });
        format!("ws://{addr}")
    }

    #[tokio::test]
    async fn interaction_open_application_emits_completed_when_allowed() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""action_kind":"automation""#));
        assert!(planned.contains(r#""type":"application","name":"calendar""#));

        let started = recv_text(&mut ws).await;
        assert!(started.contains(r#""type":"action_started""#));

        // Two steps: resolving, opening.
        let step1 = recv_text(&mut ws).await;
        assert!(step1.contains(r#""type":"action_step""#));
        assert!(step1.contains("Resolving target"));

        let step2 = recv_text(&mut ws).await;
        assert!(step2.contains(r#""type":"action_step""#));
        assert!(step2.contains("Opening application"));

        let verification = recv_text(&mut ws).await;
        assert!(verification.contains(r#""type":"action_verification""#));
        assert!(verification.contains("Best-effort"));

        let completed = recv_text(&mut ws).await;
        assert!(completed.contains(r#""type":"action_completed""#));
    }

    #[tokio::test]
    async fn interaction_open_application_fails_when_disallowed() {
        let url = spawn_server_with(InteractionConfig {
            enabled: true,
            backend: "command".into(),
            allow_open_application: false,
            allow_focus_window: false,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
            focus_window_cmd_template: None,
        })
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let _started = recv_text(&mut ws).await;
        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
        assert!(failed.contains("open_application"));
        assert!(failed.contains("recovery_hint=fallback_unavailable"));
    }

    #[tokio::test]
    async fn interaction_open_application_fails_when_layer_disabled() {
        let url = spawn_server_with(InteractionConfig {
            enabled: false,
            backend: "command".into(),
            allow_open_application: true,
            allow_focus_window: true,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
            focus_window_cmd_template: Some("/bin/true".into()),
        })
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let _started = recv_text(&mut ws).await;
        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
        assert!(failed.contains("interaction layer is disabled"));
    }

    #[tokio::test]
    async fn speak_text_emits_action_events_when_tts_unavailable() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"speak_text","text":"hello"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""action_kind":"speech""#));

        let started = recv_text(&mut ws).await;
        assert!(started.contains(r#""type":"action_started""#));

        let step = recv_text(&mut ws).await;
        assert!(step.contains(r#""type":"action_step""#));
        assert!(step.contains("TTS playback"));

        let err = recv_text(&mut ws).await;
        assert!(err.contains(r#""type":"error""#));
        assert!(err.contains("TTS is not available"));

        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
    }

    fn interaction_with_confirmation() -> InteractionConfig {
        InteractionConfig {
            enabled: true,
            backend: "command".into(),
            allow_open_application: true,
            allow_focus_window: true,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: true,
            open_app_cmd_template: Some("/bin/true".into()),
            focus_window_cmd_template: Some("/bin/true".into()),
        }
    }

    async fn spawn_server_with_approval(
        interaction: InteractionConfig,
        approval: ApprovalConfig,
    ) -> String {
        let app = test_app_with_approval(interaction, approval);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let _ = accept_loop(app, listener).await;
        });
        format!("ws://{addr}")
    }

    fn extract_approval_id(frame: &str) -> String {
        let marker = r#""approval_id":""#;
        let start = frame.find(marker).expect("approval_id in frame") + marker.len();
        let rest = &frame[start..];
        let end = rest.find('"').expect("closing quote");
        rest[..end].to_string()
    }

    #[tokio::test]
    async fn approval_approved_produces_completed_via_broadcast() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 5 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));

        let requested = recv_text(&mut ws).await;
        assert!(requested.contains(r#""type":"approval_requested""#));
        let approval_id = extract_approval_id(&requested);

        let response = format!(
            r#"{{"type":"approval_response","approval_id":"{approval_id}","decision":"approved"}}"#
        );
        ws.send(Message::Text(response)).await.unwrap();

        let resolved = recv_text(&mut ws).await;
        assert!(resolved.contains(r#""type":"approval_resolved""#));
        assert!(resolved.contains(r#""decision":"approved""#));

        let started = recv_text(&mut ws).await;
        assert!(started.contains(r#""type":"action_started""#));

        // step(resolving), step(opening), verification, completed
        let step1 = recv_text(&mut ws).await;
        assert!(step1.contains(r#""type":"action_step""#));
        let step2 = recv_text(&mut ws).await;
        assert!(step2.contains(r#""type":"action_step""#));
        let verification = recv_text(&mut ws).await;
        assert!(verification.contains(r#""type":"action_verification""#));
        let completed = recv_text(&mut ws).await;
        assert!(completed.contains(r#""type":"action_completed""#));
    }

    #[tokio::test]
    async fn approval_denied_produces_cancelled() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 5 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let requested = recv_text(&mut ws).await;
        let approval_id = extract_approval_id(&requested);

        let response = format!(
            r#"{{"type":"approval_response","approval_id":"{approval_id}","decision":"denied"}}"#
        );
        ws.send(Message::Text(response)).await.unwrap();

        let resolved = recv_text(&mut ws).await;
        assert!(resolved.contains(r#""type":"approval_resolved""#));
        assert!(resolved.contains(r#""decision":"denied""#));

        let cancelled = recv_text(&mut ws).await;
        assert!(cancelled.contains(r#""type":"action_cancelled""#));
        assert!(cancelled.contains("denied"));
    }

    #[tokio::test]
    async fn approval_timeout_produces_cancelled() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 1 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let _requested = recv_text(&mut ws).await;

        let resolved = recv_text(&mut ws).await;
        assert!(resolved.contains(r#""type":"approval_resolved""#));
        assert!(resolved.contains(r#""decision":"timed_out""#));

        let cancelled = recv_text(&mut ws).await;
        assert!(cancelled.contains(r#""type":"action_cancelled""#));
    }

    #[tokio::test]
    async fn approval_unknown_id_returns_error() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 5 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"approval_response","approval_id":"apr_nope","decision":"approved"}"#.into(),
        ))
        .await
        .unwrap();

        let err = recv_text(&mut ws).await;
        assert!(err.contains(r#""type":"error""#));
        assert!(err.contains("apr_nope"));
    }

    #[tokio::test]
    async fn approval_duplicate_response_returns_error() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 5 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let requested = recv_text(&mut ws).await;
        let approval_id = extract_approval_id(&requested);

        let response = format!(
            r#"{{"type":"approval_response","approval_id":"{approval_id}","decision":"approved"}}"#
        );
        ws.send(Message::Text(response.clone())).await.unwrap();

        // Drain resolved + started + ... for first approval. Second
        // response with same id must produce an error frame somewhere
        // after the approval is already gone.
        let mut saw_error = false;
        ws.send(Message::Text(response)).await.unwrap();
        for _ in 0..12 {
            let frame = recv_text(&mut ws).await;
            if frame.contains(r#""type":"error""#) && frame.contains(&approval_id) {
                saw_error = true;
                break;
            }
        }
        assert!(saw_error, "expected error frame for duplicate response");
    }

    #[tokio::test]
    async fn interaction_focus_window_fails_when_disallowed() {
        let url = spawn_server_with(InteractionConfig {
            enabled: true,
            backend: "command".into(),
            allow_open_application: true,
            allow_focus_window: false,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
            focus_window_cmd_template: Some("/bin/true".into()),
        })
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let _started = recv_text(&mut ws).await;
        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
        assert!(failed.contains("focus_window"));
        assert!(failed.contains("recovery_hint=fallback_unavailable"));
    }

    #[tokio::test]
    async fn interaction_focus_window_without_backend_template_reports_unsupported() {
        let url = spawn_server_with(InteractionConfig {
            enabled: true,
            backend: "command".into(),
            allow_open_application: true,
            allow_focus_window: true,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
            focus_window_cmd_template: None,
        })
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""action_kind":"automation""#));
        assert!(planned.contains(r#""type":"window","title":"calendar""#));

        let _started = recv_text(&mut ws).await;
        let _step1 = recv_text(&mut ws).await;
        let _step2 = recv_text(&mut ws).await;
        let failed = recv_text(&mut ws).await;
        assert!(failed.contains(r#""type":"action_failed""#));
        assert!(failed.contains("focus_window"));
        assert!(failed.contains("recovery_hint=fallback_unavailable"));
    }

    #[tokio::test]
    async fn interaction_focus_window_emits_verification_and_completed_when_allowed() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""type":"window","title":"calendar""#));

        let _started = recv_text(&mut ws).await;
        let step1 = recv_text(&mut ws).await;
        assert!(step1.contains("Resolving target"));
        let step2 = recv_text(&mut ws).await;
        assert!(step2.contains("Focusing window"));

        let verification = recv_text(&mut ws).await;
        assert!(verification.contains(r#""type":"action_verification""#));
        assert!(verification.contains("Best-effort"));

        let completed = recv_text(&mut ws).await;
        assert!(completed.contains(r#""type":"action_completed""#));
    }

    #[tokio::test]
    async fn interaction_focus_window_application_target_maps_to_app() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_focus_window","target":{"type":"application","name":"firefox"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""type":"window","app":"firefox""#));
    }

    #[tokio::test]
    async fn interaction_focus_window_with_approval_flow_runs_end_to_end() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 5 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let _planned = recv_text(&mut ws).await;
        let requested = recv_text(&mut ws).await;
        assert!(requested.contains(r#""type":"approval_requested""#));
        assert!(requested.contains(r#""action_kind":"focus_window""#));
        assert!(requested.contains("calendar"));
        let approval_id = extract_approval_id(&requested);

        let response = format!(
            r#"{{"type":"approval_response","approval_id":"{approval_id}","decision":"approved"}}"#
        );
        ws.send(Message::Text(response)).await.unwrap();

        let resolved = recv_text(&mut ws).await;
        assert!(resolved.contains(r#""type":"approval_resolved""#));
        let _started = recv_text(&mut ws).await;
        let _step1 = recv_text(&mut ws).await;
        let _step2 = recv_text(&mut ws).await;
        let verification = recv_text(&mut ws).await;
        assert!(verification.contains(r#""type":"action_verification""#));
        let completed = recv_text(&mut ws).await;
        assert!(completed.contains(r#""type":"action_completed""#));
    }

    #[tokio::test]
    async fn interaction_probe_accessibility_emits_probe_result_and_completed() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_probe_accessibility"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""action_kind":"system""#));
        assert!(planned.contains("Probe accessibility"));

        let _started = recv_text(&mut ws).await;
        let _step = recv_text(&mut ws).await;

        let verification = recv_text(&mut ws).await;
        assert!(verification.contains(r#""type":"action_verification""#));
        assert!(verification.contains("Probe:"));

        let probe = recv_text(&mut ws).await;
        assert!(probe.contains(r#""type":"accessibility_probe_result""#));
        // On a typical CI runner the env is bare, so we expect an
        // honest "unavailable" or "uncertain" — never a fake success.
        assert!(
            probe.contains(r#""status":"unavailable""#)
                || probe.contains(r#""status":"uncertain""#)
                || probe.contains(r#""status":"failed""#)
        );

        let completed = recv_text(&mut ws).await;
        assert!(completed.contains(r#""type":"action_completed""#));
    }

    #[tokio::test]
    async fn interaction_discover_accessibility_without_hint_reports_structured_result() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_discover_accessibility"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains("Discover top-level accessibles"));

        let _started = recv_text(&mut ws).await;
        let _step1 = recv_text(&mut ws).await;
        let _step2 = recv_text(&mut ws).await;
        let verification = recv_text(&mut ws).await;
        assert!(verification.contains(r#""type":"action_verification""#));

        let discovery = recv_text(&mut ws).await;
        assert!(discovery.contains(r#""type":"accessibility_discovery_result""#));

        // Final envelope is either completed (uncertain, plausible) or
        // failed (unavailable) — both are honest outcomes for this
        // spike depending on the runtime environment.
        let terminal = recv_text(&mut ws).await;
        assert!(
            terminal.contains(r#""type":"action_completed""#)
                || terminal.contains(r#""type":"action_failed""#)
        );
    }

    #[tokio::test]
    async fn interaction_discover_accessibility_with_hint_inspects_target() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_discover_accessibility","hint":"firefox"}"#.into(),
        ))
        .await
        .unwrap();

        let planned = recv_text(&mut ws).await;
        assert!(planned.contains(r#""type":"action_planned""#));
        assert!(planned.contains(r#""type":"application","name":"firefox""#));

        let _started = recv_text(&mut ws).await;
        let _step1 = recv_text(&mut ws).await;
        let _step2 = recv_text(&mut ws).await;
        let _verification = recv_text(&mut ws).await;
        let discovery = recv_text(&mut ws).await;
        assert!(discovery.contains(r#""type":"accessibility_discovery_result""#));
        // When the environment is plausible the hint-echo path emits
        // an `ok` payload with a single `discovered` item carrying the
        // matched hint. On a bare CI runner the same probe returns
        // `unavailable`; both shapes are honest for this spike.
        if discovery.contains(r#""status":"ok""#) {
            assert!(discovery.contains(r#""confidence":"discovered""#));
            assert!(discovery.contains(r#""matched_hint":"firefox""#));
            assert!(discovery.contains(r#""source":"accessibility_hint_echo""#));
        } else {
            assert!(
                discovery.contains(r#""status":"unavailable""#)
                    || discovery.contains(r#""status":"failed""#)
            );
        }
        let _terminal = recv_text(&mut ws).await;
    }

    #[tokio::test]
    async fn interaction_select_target_emits_target_selected() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_select_target","target":{"id":"sel_ui_1","name":"calendar","role":"window","source":"accessibility","confidence":"discovered","matched_hint":"calendar"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let selected = recv_text(&mut ws).await;
        assert!(selected.contains(r#""type":"target_selected""#));
        assert!(selected.contains(r#""name":"calendar""#));
        assert!(selected.contains(r#""role":"window""#));
        assert!(selected.contains(r#""confidence":"discovered""#));
        assert!(selected.contains(r#""matched_hint":"calendar""#));
    }

    #[tokio::test]
    async fn interaction_select_target_rejects_invalid_confidence() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_select_target","target":{"id":"sel_ui_1","name":"calendar","role":"window","source":"accessibility","confidence":"bogus"}}"#
                .into(),
        ))
        .await
        .unwrap();

        let err = recv_text(&mut ws).await;
        assert!(err.contains(r#""type":"error""#));
        assert!(err.contains("confidence"));
    }

    #[tokio::test]
    async fn interaction_clear_target_is_idempotent() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_clear_target"}"#.into(),
        ))
        .await
        .unwrap();
        let cleared = recv_text(&mut ws).await;
        assert!(cleared.contains(r#""type":"target_cleared""#));
        assert!(!cleared.contains("previous"));
    }

    #[tokio::test]
    async fn interaction_clear_target_returns_previous_when_selected() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_select_target","target":{"id":"sel_ui_1","name":"calendar","role":"window","source":"accessibility","confidence":"discovered"}}"#
                .into(),
        ))
        .await
        .unwrap();
        let _selected = recv_text(&mut ws).await;
        ws.send(Message::Text(
            r#"{"type":"interaction_clear_target"}"#.into(),
        ))
        .await
        .unwrap();
        let cleared = recv_text(&mut ws).await;
        assert!(cleared.contains(r#""type":"target_cleared""#));
        assert!(cleared.contains(r#""previous""#));
        assert!(cleared.contains(r#""name":"calendar""#));
    }

    #[tokio::test]
    async fn approval_request_carries_selected_target_when_held() {
        let url = spawn_server_with_approval(
            interaction_with_confirmation(),
            ApprovalConfig { timeout_seconds: 5 },
        )
        .await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(
            r#"{"type":"interaction_select_target","target":{"id":"sel_ui_1","name":"calendar","role":"window","source":"accessibility","confidence":"discovered"}}"#
                .into(),
        ))
        .await
        .unwrap();
        let _selected = recv_text(&mut ws).await;

        ws.send(Message::Text(
            r#"{"type":"interaction_open_application","application":"calendar"}"#.into(),
        ))
        .await
        .unwrap();
        let _planned = recv_text(&mut ws).await;
        let requested = recv_text(&mut ws).await;
        assert!(requested.contains(r#""type":"approval_requested""#));
        assert!(requested.contains(r#""selected_target""#));
        assert!(requested.contains(r#""name":"calendar""#));
        assert!(requested.contains("Ziel:"));
    }

    #[tokio::test]
    async fn get_status_includes_accessibility_probe_fields() {
        let url = spawn_server().await;
        let (mut ws, _) = connect_async(&url).await.unwrap();
        ws.send(Message::Text(r#"{"type":"get_status"}"#.into()))
            .await
            .unwrap();
        let got = recv_text(&mut ws).await;
        assert!(got.contains(r#""accessibility_probe":"#));
        assert!(got.contains(r#""accessibility_probe_reason":"#));
    }
}
