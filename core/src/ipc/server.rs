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
        IncomingMessage::ApprovalResponse {
            approval_id,
            decision,
        } => handle_approval_response(app, approval_id, decision),
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

    if !app.tts.is_available() {
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

    if !app.stt.is_available() {
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

    fn test_app() -> Arc<App> {
        test_app_with(InteractionConfig {
            enabled: true,
            backend: "command".into(),
            allow_open_application: true,
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
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
        let config = Config {
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
            },
            ipc: IpcConfig {
                enabled: true,
                bind: "127.0.0.1:0".into(),
            },
            interaction,
            approval,
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
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
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
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: false,
            open_app_cmd_template: Some("/bin/true".into()),
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
            allow_type_text: false,
            allow_shortcuts: false,
            require_confirmation: true,
            open_app_cmd_template: Some("/bin/true".into()),
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
}
