use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, RwLock};
use std::time::Duration;

use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tokio::time::timeout;
use tracing::{info, warn};

use crate::actions::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionKind, ActionPhase,
    ActionPlannedPayload, ActionStartedPayload, ActionStatus, ActionStepPayload, ActionTarget,
    ActionVerificationPayload,
};
use crate::approvals::{
    ApprovalDecision, ApprovalRequest, ApprovalResolvedPayload, PendingApprovalError,
    PendingApprovalRegistry,
};
use crate::audio::{SttService, TtsService};
use crate::config::{validate_llamafile_mode, Config, LlamafileConfig};
use crate::interaction::{
    AccessibilityDiscovery, AccessibilityProbe, CommandBackend, CommandBackendConfig,
    InteractionAction, InteractionExecutor, InteractionKind, InteractionPolicy, SelectedTarget,
    discover_top_level, inspect_target,
};
use crate::ipc::protocol::{
    InteractionFocusTarget, OutgoingMessage, TargetClearedPayload, TargetSelectedPayload,
};
use crate::providers::text::{
    LlamafileConfigView, TextProviderChainItem, TextProviderError, TextProviderResolver,
};
#[cfg(test)]
use crate::providers::text::TextProviderRuntimeStatus;
use crate::settings_store;

const EVENTS_CHANNEL_CAPACITY: usize = 256;

pub struct App {
    pub config: Config,
    pub tts: TtsService,
    pub stt: SttService,
    interaction: InteractionExecutor<CommandBackend>,
    action_counter: AtomicU64,
    approval_counter: AtomicU64,
    selection_counter: AtomicU64,
    pending_approvals: Arc<PendingApprovalRegistry>,
    /// Current Interaction target, if any. Held in-memory only —
    /// cleared on explicit `interaction_clear_target`. No persistence,
    /// no cross-session memory.
    selected_target: Mutex<Option<SelectedTarget>>,
    events_tx: broadcast::Sender<OutgoingMessage>,
    /// Text/Reasoning-Provider-Resolver. PR 2 der Provider-Fallback-
    /// Linie: `handle_text_query` routet ab jetzt ausschließlich über
    /// diesen Resolver. ABrain bleibt Default-Provider — der Resolver
    /// kapselt den CLI-Aufruf.
    ///
    /// Seit PR 5 hinter einem `RwLock`, damit `settings_set_llamafile_config`
    /// den Resolver atomar durch einen frisch gebauten ersetzen kann.
    /// `handle_text_query` klont den `Arc` unter dem Read-Lock kurz
    /// heraus und hält das Lock **nicht** über den `await`-Punkt
    /// (kein Deadlock, kein Lock-Halten während Provider-Aufrufen).
    text_provider: RwLock<Arc<TextProviderResolver>>,
    /// Kanonische Chain-Items — unverändert seit Startup. Wird bei einem
    /// Rebuild des Resolvers (PR 5) mit einer aktualisierten Llamafile-
    /// Config neu instanziiert; die Chain selbst bleibt Read-only in
    /// dieser Stufe (keine UI-Editieroberfläche für Chain-Reihenfolge).
    text_provider_chain: Vec<TextProviderChainItem>,
    /// ABrain-CLI-Kommando, wird beim Resolver-Rebuild wiederverwendet.
    abrain_cmd: String,
    /// Laufender editierbarer Stand der Llamafile-Config (PR 5). Startet
    /// als Kopie von `config.text_provider.llamafile`, bereits mit dem
    /// Override aus dem Settings-Store verschmolzen. Änderungen über
    /// `settings_set_llamafile_config` werden hier gespiegelt und in
    /// den StatusPayload projiziert.
    live_llamafile: Mutex<LlamafileConfig>,
}

#[derive(Debug, Clone, Serialize)]
pub struct StatusPayload {
    pub tts_enabled: bool,
    pub tts_available: bool,
    pub stt_enabled: bool,
    pub stt_available: bool,
    pub auto_speak: bool,
    pub ipc_enabled: bool,
    pub interaction_enabled: bool,
    pub interaction_backend: String,
    pub approval_timeout_seconds: u64,
    /// Honest, environment-based verdict from the AT-SPI spike at
    /// core start-up. One of `"uncertain"`, `"unavailable"`,
    /// `"failed"`. See
    /// [`crate::interaction::AccessibilityProbe`] for semantics.
    pub accessibility_probe: String,
    /// Short free-form reason accompanying `accessibility_probe`.
    pub accessibility_probe_reason: String,
    // --- Text / Reasoning Provider (PR 2, additiv) ------------------
    /// Primärer (konfigurierter) Text-Provider-Kind-Name. `"none"`
    /// wenn keine gültige Kette konfiguriert ist. Entspricht dem
    /// Feld `configured_provider` aus
    /// `docs/provider_fallback_and_settings_architecture.md` §8.
    pub text_provider_configured: String,
    /// Kind des Providers, der den **letzten** `submit_text` /
    /// `voice_once`-Request erfolgreich beantwortet hat. Leer,
    /// solange noch kein Request durchgelaufen ist.
    pub text_provider_active: String,
    /// `"available"` (nominell) / `"unavailable"` (keine Kette oder
    /// kompletter Fehlschlag) / `"fallback_active"` (ein Nicht-
    /// Primary-Provider hat zuletzt geantwortet). Enum-artiges Feld
    /// — additiv, damit spätere Provider-PRs `degraded` oder
    /// Ähnliches ergänzen können, ohne das Schema zu brechen.
    pub text_provider_availability: String,
    /// Kurze Fehlerklasse der letzten komplett fehlgeschlagenen
    /// Runde (`timeout`, `process_missing`, `empty_response`,
    /// `exit_nonzero`, `invalid_response`, `unknown`). `None` im
    /// Erfolgsfall. Keine Nutzerinhalte, keine Stacktraces, keine
    /// Secrets — Freitext-Fehler laufen weiterhin über das
    /// `error`-IPC-Envelope.
    pub text_provider_last_error: Option<String>,
    /// Ob der aktuell aktive Provider eine Cloud-Komponente hat. In
    /// PR 2 existiert kein Cloud-Provider; das Feld ist additiv
    /// vorhanden, damit der UI-Transparenz-Vertrag aus §7 der
    /// Architektur-Doku („Externe Provider klar sichtbar") ohne
    /// Protokoll-Revision einlösbar bleibt, sobald ein Cloud-Pfad
    /// existiert.
    pub text_provider_cloud: bool,
    // --- Text Provider — vertiefter Status (PR 4, additiv) ----------
    /// Geordnete Liste der Provider-Kinds in der aktuellen Kette. Hält
    /// genau die Namen, die der Resolver produktiv instanziiert hat
    /// — unbekannte Kinds aus der Config wurden bereits beim Bau
    /// verworfen. Die UI rendert daraus die Fallback-Reihenfolge;
    /// fehlt das Feld (ältere Cores), fällt die Shell stillschweigend
    /// auf `text_provider_configured` zurück.
    pub text_provider_chain: Vec<String>,
    /// Ob `llamafile_local` Teil der aktuellen Kette ist. Bei `false`
    /// sind alle weiteren `llamafile_*`-Felder bedeutungslos und werden
    /// mit neutralen Werten / `None` gefüllt.
    pub llamafile_in_chain: bool,
    /// `SMOLIT_LLAMAFILE_ENABLED` ausgewertet. Spiegelt, ob der Operator
    /// den Master-Schalter gezogen hat — unabhängig davon, ob der
    /// Provider aktuell in der Kette steht. So kann die UI „konfiguriert,
    /// aber nicht in der Kette" ehrlich sichtbar machen.
    pub llamafile_enabled: bool,
    /// `enabled` **und** ein nicht-leerer `SMOLIT_LLAMAFILE_PATH`. Das
    /// ist die ehrliche „in der Config bereit für Spawn"-Grenze. Ohne
    /// Path bleibt der Provider im Lifecycle `not_configured`.
    pub llamafile_configured: bool,
    /// Lifecycle-Tag aus
    /// [`crate::providers::text::LlamafileLifecycle::as_str`], nur gesetzt,
    /// wenn `llamafile_in_chain` gilt. `None` = nicht in der Kette.
    pub llamafile_lifecycle: Option<String>,
    /// `on_demand` / `standby`. Nur gesetzt, wenn `llamafile_in_chain`
    /// gilt. Spiegelt den normalisierten Config-Wert 1:1 — unbekannte
    /// Eingaben sind schon in der Config auf den Default gefallen.
    pub llamafile_mode: Option<String>,
    /// Idle-Timeout in Sekunden, nach dem der Watchdog einen idle
    /// llamafile-Prozess wieder stoppt. Nur gesetzt, wenn
    /// `llamafile_in_chain` gilt.
    pub llamafile_idle_timeout_seconds: Option<u64>,
}

/// Eingabe-Payload für `settings_set_llamafile_config` (PR 5).
/// Jedes Feld außer `enabled` ist optional — fehlende Felder bleiben
/// auf dem bisherigen Wert. `path` akzeptiert explizit den leeren
/// String zum Löschen.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsLlamafileUpdate {
    pub enabled: bool,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub idle_timeout_seconds: Option<u64>,
    /// `None`                → Pfad unverändert lassen.
    /// `Some("")` / nur Whitespace → Pfad löschen.
    /// `Some("/abs/path")`   → Pfad ersetzen.
    #[serde(default)]
    pub path: Option<String>,
}

/// Ergebnis einer `settings_probe_llamafile`-Anfrage (PR 5). Bewusst
/// schmal: keine Pfad-/Fehler-Freitexte, nur ein kleiner, stabiler
/// Tag plus eine kurze menschenlesbare Meldung, die **nie** den
/// Binary-Pfad oder andere sensitive Werte enthält.
#[derive(Debug, Clone, Serialize)]
pub struct SettingsProbeResultPayload {
    /// True nur, wenn der Provider in der Kette steht, enabled ist,
    /// einen Pfad hat, das Binary existiert und ausführbar ist.
    pub ok: bool,
    /// Kurzer, stabiler Klassen-Tag. Werte:
    ///
    ///   * `"ok"` — Binary vorhanden, ausführbar, Config konsistent.
    ///   * `"not_in_chain"` — `llamafile_local` steht nicht in der
    ///     aktuellen Provider-Kette.
    ///   * `"disabled"` — Master-Flag aus.
    ///   * `"not_configured"` — enabled, aber Pfad leer / unset.
    ///   * `"path_missing"` — Pfad gesetzt, aber Datei existiert nicht.
    ///   * `"path_not_file"` — Pfad zeigt auf ein Verzeichnis o. ä.
    ///   * `"path_not_executable"` — Datei existiert, aber ohne
    ///     Execute-Bit (Unix).
    pub class: String,
    /// Kurze, menschenlesbare Begründung. **Enthält keinen Pfad,
    /// kein Secret und keinen Roh-Fehlerstring.**
    pub message: String,
    /// Aktueller Lifecycle des Providers, falls er in der Kette steht.
    /// `null`, wenn nicht in der Kette.
    pub lifecycle: Option<String>,
    pub in_chain: bool,
    pub enabled: bool,
    pub configured: bool,
}

impl App {
    pub fn new(config: Config) -> Self {
        let tts = TtsService::new(&config.audio);
        let stt = SttService::new(&config.audio);

        let backend = CommandBackend::new(CommandBackendConfig {
            open_app_cmd_template: config.interaction.open_app_cmd_template.clone(),
            focus_window_cmd_template: config.interaction.focus_window_cmd_template.clone(),
        });
        let policy = InteractionPolicy {
            enabled: config.interaction.enabled,
            allow_open_application: config.interaction.allow_open_application,
            allow_focus_window: config.interaction.allow_focus_window,
            allow_type_text: config.interaction.allow_type_text,
            allow_shortcuts: config.interaction.allow_shortcuts,
            require_confirmation: config.interaction.require_confirmation,
        };
        let interaction = InteractionExecutor::new(backend, policy);
        let (events_tx, _) = broadcast::channel(EVENTS_CHANNEL_CAPACITY);

        let chain: Vec<TextProviderChainItem> = config
            .text_provider
            .chain
            .iter()
            .map(|k| TextProviderChainItem { kind: k.clone() })
            .collect();
        // PR 5: Persistierter Llamafile-Override aus dem Settings-Store
        // einlesen und über die Env-Defaults legen. Die Config selbst
        // bleibt unverändert (Immutable Snapshot der Startup-Werte);
        // der live-Stand lebt in `live_llamafile`.
        let override_file = settings_store::load_llamafile_override();
        let live_llamafile = settings_store::apply_llamafile_override(
            config.text_provider.llamafile.clone(),
            &override_file,
        );
        let llamafile_view = llamafile_view_from(&live_llamafile);
        let text_provider = Arc::new(TextProviderResolver::from_chain(
            &chain,
            &config.abrain_cmd,
            &llamafile_view,
        ));
        let abrain_cmd = config.abrain_cmd.clone();

        Self {
            config,
            tts,
            stt,
            interaction,
            action_counter: AtomicU64::new(0),
            approval_counter: AtomicU64::new(0),
            selection_counter: AtomicU64::new(0),
            pending_approvals: Arc::new(PendingApprovalRegistry::new()),
            selected_target: Mutex::new(None),
            events_tx,
            text_provider: RwLock::new(text_provider),
            text_provider_chain: chain,
            abrain_cmd,
            live_llamafile: Mutex::new(live_llamafile),
        }
    }

    /// Read-only-Snapshot des Text-Provider-Laufzeit-Status — für
    /// Tests und ggf. spätere Diagnostik-Endpoints. Kein Write-Pfad,
    /// kein Event-Fan-out; der Status wird exklusiv durch die
    /// `run`-Aufrufe in `handle_text_query` aktualisiert.
    #[cfg(test)]
    pub fn text_provider_status(&self) -> TextProviderRuntimeStatus {
        self.current_resolver().status()
    }

    /// Klon-Snapshot des aktuell aktiven Resolvers. Hält den Read-Lock
    /// nur kurz, klont den `Arc` und gibt ihn frei. Callsites dürfen
    /// das Ergebnis unbegrenzt behalten (z. B. für ein `await` auf
    /// `run`) — der Core rebuildet bei Config-Writes einen **neuen**
    /// Resolver und ersetzt die Referenz; alte Snapshots bleiben für
    /// ihre Lebensdauer konsistent.
    fn current_resolver(&self) -> Arc<TextProviderResolver> {
        self.text_provider
            .read()
            .expect("text provider lock poisoned")
            .clone()
    }

    pub fn next_action_id(&self) -> String {
        let n = self.action_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("act_{n:06}")
    }

    fn next_approval_id(&self) -> String {
        let n = self.approval_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("apr_{n:06}")
    }

    fn next_selection_id(&self) -> String {
        let n = self.selection_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("sel_{n:06}")
    }

    /// Read-only snapshot of the currently selected Interaction target.
    /// Used by the approval flow to embed the target in
    /// `approval_requested` and by tests.
    pub fn current_selected_target(&self) -> Option<SelectedTarget> {
        self.selected_target
            .lock()
            .expect("selected_target mutex poisoned")
            .clone()
    }

    /// Store `target` as the current Interaction context, replacing any
    /// previous selection. Returns a `target_selected` envelope the
    /// caller should flush to IPC. Validation failures produce an
    /// `Error` envelope instead — the previous selection is untouched.
    pub fn select_target(&self, target: SelectedTarget) -> Vec<OutgoingMessage> {
        let fallback_id = self.next_selection_id();
        let normalized = match target.normalize_with_fallback_id(fallback_id) {
            Ok(t) => t,
            Err(err) => {
                return vec![OutgoingMessage::Error {
                    message: err.message().to_string(),
                }];
            }
        };

        {
            let mut slot = self
                .selected_target
                .lock()
                .expect("selected_target mutex poisoned");
            *slot = Some(normalized.clone());
        }

        info!(
            target_id = %normalized.id,
            target_name = %normalized.name,
            target_role = %normalized.role,
            target_confidence = %normalized.confidence,
            "selected interaction target",
        );

        vec![OutgoingMessage::TargetSelected {
            payload: TargetSelectedPayload { target: normalized },
        }]
    }

    /// Clear the current Interaction context. Idempotent: always emits
    /// a `target_cleared` envelope, with `previous` set when a target
    /// was actually held.
    pub fn clear_target(&self) -> Vec<OutgoingMessage> {
        let previous = {
            let mut slot = self
                .selected_target
                .lock()
                .expect("selected_target mutex poisoned");
            slot.take()
        };

        if let Some(prev) = &previous {
            info!(target_id = %prev.id, "cleared interaction target");
        }

        vec![OutgoingMessage::TargetCleared {
            payload: TargetClearedPayload { previous },
        }]
    }

    /// Subscribe to async continuation events (approval outcomes,
    /// background-task progress). Used by IPC handlers to forward
    /// these to connected WS clients.
    pub fn subscribe_events(&self) -> broadcast::Receiver<OutgoingMessage> {
        self.events_tx.subscribe()
    }

    fn broadcast(&self, msg: OutgoingMessage) {
        // Ignore send errors: `broadcast::Sender::send` only errors
        // when there are zero receivers, which is a legitimate state
        // (no UI connected) rather than a bug.
        let _ = self.events_tx.send(msg);
    }

    pub async fn handle_text_query(&self, input: &str) -> Result<String> {
        // PR 2: geht ausschließlich über die Provider-Schicht. Der
        // alte direkte Aufruf in `adapters::abrain::run_task_with_cmd`
        // wohnt jetzt im `AbrainCliProvider` innerhalb des Resolvers.
        // Resolver-Fehler werden in den generischen `anyhow::Error`-
        // Rückgabetyp gemappt, damit sich die bestehende Callsite-
        // Semantik (CLI-Loop, IPC-`submit_text`) byte-identisch
        // verhält: ein Text-Antwort-Erfolg bleibt ein Erfolg, ein
        // Provider-Fehler bleibt ein `error`-Envelope mit
        // menschenlesbarer Meldung.
        let resolver = self.current_resolver();
        resolver
            .run(input)
            .await
            .map_err(|err: TextProviderError| anyhow::anyhow!(err))
    }

    pub async fn handle_voice_once(&self) -> Result<String> {
        self.stt.listen_once().await
    }

    pub async fn handle_speak(&self, text: &str) -> Result<()> {
        self.tts.speak(text).await
    }

    pub async fn maybe_auto_speak(&self, text: &str) {
        if !self.config.audio.auto_speak || !self.tts.is_available() {
            return;
        }
        if let Err(err) = self.tts.speak(text).await {
            warn!(error = %err, "auto-speak TTS failed");
        }
    }

    /// Deliver a decision submitted by the UI to the matching pending
    /// approval. Returns an error message suitable for an IPC
    /// `error` envelope when the approval id is unknown or stale.
    pub fn resolve_approval(
        &self,
        approval_id: &str,
        decision: ApprovalDecision,
    ) -> Result<(), String> {
        match self.pending_approvals.resolve(approval_id, decision) {
            Ok(()) => Ok(()),
            Err(PendingApprovalError::Unknown) => Err(format!(
                "no pending approval with id {approval_id} (already resolved or unknown)"
            )),
            Err(PendingApprovalError::Closed) => Err(format!(
                "approval {approval_id} was already closed"
            )),
        }
    }

    /// Entry point for IPC handlers. Plans the interaction, checks
    /// policy, and either:
    ///   * refuses the action (layer disabled / kind disallowed),
    ///   * runs the backend directly (no confirmation required), or
    ///   * emits `approval_requested` and spawns a background task
    ///     that awaits the UI decision (or a timeout) before running
    ///     the backend.
    ///
    /// Returns the *immediate* Action Events the IPC handler should
    /// flush to the caller. Any further continuation events (backend
    /// progress after approval, `approval_resolved`) arrive via the
    /// broadcast channel.
    pub async fn dispatch_interaction(
        self: &Arc<Self>,
        action: InteractionAction,
    ) -> Vec<OutgoingMessage> {
        let mut out = Vec::with_capacity(3);
        out.push(self.interaction.plan_event(&action));

        if let Err(err) = self.interaction.policy().allows(action.kind()) {
            out.extend(self.interaction.refusal_events(&action.action_id, &err));
            return out;
        }

        let needs_approval =
            action.requires_confirmation && self.interaction.policy().require_confirmation;

        if !needs_approval {
            out.extend(self.interaction.run_approved(action).await);
            return out;
        }

        let approval_id = self.next_approval_id();
        let timeout_seconds = self.config.approval.timeout_seconds;
        let selected_target = self.current_selected_target();
        let request = ApprovalRequest {
            approval_id: approval_id.clone(),
            action_id: action.action_id.clone(),
            action_kind: action.kind(),
            title: action.title.clone(),
            message: approval_message(&action, selected_target.as_ref()),
            target: action.target.clone(),
            reason: None,
            timeout_seconds,
            selected_target,
        };
        let rx = self.pending_approvals.register(&approval_id);
        out.push(OutgoingMessage::ApprovalRequested { payload: request });

        let app = Arc::clone(self);
        tokio::spawn(async move {
            app.await_and_continue(action, approval_id, rx, timeout_seconds)
                .await;
        });

        out
    }

    async fn await_and_continue(
        self: Arc<Self>,
        action: InteractionAction,
        approval_id: String,
        rx: tokio::sync::oneshot::Receiver<ApprovalDecision>,
        timeout_seconds: u64,
    ) {
        let decision = match timeout(Duration::from_secs(timeout_seconds), rx).await {
            Ok(Ok(decision)) => decision,
            Ok(Err(_)) => {
                // Sender dropped without sending — treat as cancelled.
                ApprovalDecision::Cancelled
            }
            Err(_) => {
                // Timed out: remove the pending entry ourselves so any
                // late `approval_response` is rejected as Unknown.
                let _ = self.pending_approvals.take(&approval_id);
                ApprovalDecision::TimedOut
            }
        };

        info!(
            approval_id = %approval_id,
            action_id = %action.action_id,
            decision = decision.as_str(),
            "approval resolved"
        );

        self.broadcast(OutgoingMessage::ApprovalResolved {
            payload: ApprovalResolvedPayload {
                approval_id: approval_id.clone(),
                action_id: action.action_id.clone(),
                decision: decision.as_str().to_string(),
            },
        });

        match decision {
            ApprovalDecision::Approved => {
                let msgs = self.interaction.run_approved(action).await;
                for msg in msgs {
                    self.broadcast(msg);
                }
            }
            ApprovalDecision::Denied
            | ApprovalDecision::Cancelled
            | ApprovalDecision::TimedOut => {
                let message = match decision {
                    ApprovalDecision::Denied => "Action denied by user",
                    ApprovalDecision::Cancelled => "Action cancelled",
                    ApprovalDecision::TimedOut => "Approval timed out",
                    ApprovalDecision::Approved => unreachable!(),
                };
                self.broadcast(OutgoingMessage::ActionCancelled {
                    payload: ActionCancelledPayload {
                        action_id: action.action_id.clone(),
                        status: ActionStatus::Cancelled,
                        message: Some(message.to_string()),
                    },
                });
            }
        }
    }

    pub async fn execute_open_application(
        self: &Arc<Self>,
        name: &str,
    ) -> Vec<OutgoingMessage> {
        let mut action = InteractionAction::open_application(self.next_action_id(), name);
        // `open_application` is the first action that goes through the
        // approval flow — flip the confirmation flag here rather than
        // inside the factory so pure executor tests stay deterministic.
        action.requires_confirmation = true;
        self.dispatch_interaction(action).await
    }

    /// Run the environment-based accessibility probe and wrap the
    /// result into a small Action-Event sequence plus a dedicated
    /// `accessibility_probe_result` envelope. Emission is read-only
    /// and does not require approval — the probe never touches the
    /// user's desktop.
    pub async fn probe_accessibility(self: &Arc<Self>) -> Vec<OutgoingMessage> {
        let action_id = self.next_action_id();
        let probe = AccessibilityProbe::detect();
        let reason = probe.reason().to_string();
        let status = probe.status_str();

        let mut out = Vec::with_capacity(6);
        out.push(planned(
            &action_id,
            ActionKind::System,
            "Probe accessibility backend",
            ActionTarget::unknown(),
        ));
        out.push(started(&action_id));
        out.push(step(&action_id, "Checking session environment"));
        out.push(OutgoingMessage::ActionVerification {
            payload: ActionVerificationPayload {
                action_id: action_id.clone(),
                title: format!("Probe: {status}"),
            },
        });
        out.push(OutgoingMessage::AccessibilityProbeResult {
            payload: probe.clone(),
        });
        out.push(OutgoingMessage::ActionCompleted {
            payload: ActionCompletedPayload {
                action_id,
                status: ActionStatus::Completed,
                message: Some(format!("{status}: {reason}")),
            },
        });
        out
    }

    /// Run the accessibility discovery / inspection spike. When `hint`
    /// is provided the spike inspects that symbolic target; otherwise
    /// it attempts a top-level discovery. In both cases the actual
    /// RPC walk is not yet wired up, so honest `uncertain` /
    /// `unavailable` results are expected.
    pub async fn discover_accessibility(
        self: &Arc<Self>,
        hint: Option<String>,
    ) -> Vec<OutgoingMessage> {
        let action_id = self.next_action_id();
        let trimmed_hint = hint
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string);

        let (title, step_label) = match &trimmed_hint {
            Some(name) => (
                format!("Inspect accessible target `{name}`"),
                format!("Inspecting `{name}` via accessibility probe"),
            ),
            None => (
                "Discover top-level accessibles".to_string(),
                "Discovering top-level accessibles via AT-SPI probe".to_string(),
            ),
        };

        let target = match &trimmed_hint {
            Some(name) => ActionTarget::application(name.clone()),
            None => ActionTarget::unknown(),
        };

        let result = match &trimmed_hint {
            Some(name) => inspect_target(name),
            None => discover_top_level(),
        };

        let status = result.status_str();
        let reason = result.reason().to_string();

        let mut out = Vec::with_capacity(7);
        out.push(planned(&action_id, ActionKind::System, &title, target));
        out.push(started(&action_id));
        out.push(step(&action_id, "Probing accessibility backend"));
        out.push(step(&action_id, &step_label));
        out.push(OutgoingMessage::ActionVerification {
            payload: ActionVerificationPayload {
                action_id: action_id.clone(),
                title: format!("Discovery: {status}"),
            },
        });
        out.push(OutgoingMessage::AccessibilityDiscoveryResult {
            payload: result.clone(),
        });

        match &result {
            AccessibilityDiscovery::Ok { items, .. } => {
                let summary = if items.is_empty() {
                    format!("{status}: {reason}")
                } else {
                    format!("{status}: {} item(s); {reason}", items.len())
                };
                out.push(OutgoingMessage::ActionCompleted {
                    payload: ActionCompletedPayload {
                        action_id,
                        status: ActionStatus::Completed,
                        message: Some(summary),
                    },
                });
            }
            AccessibilityDiscovery::Uncertain { .. } => {
                out.push(OutgoingMessage::ActionCompleted {
                    payload: ActionCompletedPayload {
                        action_id,
                        status: ActionStatus::Completed,
                        message: Some(format!("{status}: {reason}")),
                    },
                });
            }
            AccessibilityDiscovery::Unavailable { .. }
            | AccessibilityDiscovery::Failed { .. } => {
                out.push(OutgoingMessage::ActionFailed {
                    payload: ActionFailedPayload {
                        action_id,
                        status: ActionStatus::Failed,
                        message: format!("{status}: {reason}"),
                        error: Some("recovery_hint=fallback_unavailable".to_string()),
                    },
                });
            }
        }
        out
    }

    pub async fn execute_focus_window(
        self: &Arc<Self>,
        target: InteractionFocusTarget,
    ) -> Vec<OutgoingMessage> {
        let (title, app) = match target {
            InteractionFocusTarget::Window { name, title, app } => {
                // Accept either `name` (per-spec example) or `title`
                // as the window title — `title` takes precedence when
                // both are provided.
                (title.or(name), app)
            }
            InteractionFocusTarget::Application { name } => (None, Some(name)),
        };
        let mut action = InteractionAction::focus_window(self.next_action_id(), title, app);
        action.requires_confirmation = true;
        self.dispatch_interaction(action).await
    }

    pub fn build_status_payload(&self) -> StatusPayload {
        let tts = self.tts.state();
        let stt = self.stt.state();
        let probe = AccessibilityProbe::detect();
        let resolver = self.current_resolver();
        let text_provider = resolver.status();

        // Chain-Sicht (PR 4) kommt direkt aus dem Resolver — stabiler
        // als die Roh-Config, weil unbekannte Kinds beim Resolver-Bau
        // bereits verworfen wurden und die produktive Kette hier zählt.
        let chain: Vec<String> = resolver
            .chain_kinds()
            .into_iter()
            .map(|s| s.to_string())
            .collect();
        let llamafile_in_chain = chain.iter().any(|k| k == "llamafile_local");

        // Llamafile-Config-Sicht liest ab PR 5 den **live**-Stand aus,
        // nicht mehr den immutable Startup-Config-Snapshot: ein
        // `settings_set_llamafile_config`-Write spiegelt sich also im
        // nächsten `get_status` ohne Core-Neustart. `llamafile_configured`
        // ist nicht das Lifecycle-Wort `Configured`, sondern die
        // ehrliche „enabled + path gesetzt"-Grenze.
        let llamafile_cfg = self
            .live_llamafile
            .lock()
            .expect("live llamafile mutex poisoned")
            .clone();
        let llamafile_path_present = llamafile_cfg
            .path
            .as_deref()
            .map(|p| !p.trim().is_empty())
            .unwrap_or(false);
        let llamafile_configured = llamafile_cfg.enabled && llamafile_path_present;

        // Lifecycle wird nur dann exponiert, wenn llamafile tatsächlich
        // in der Kette steht. Sonst sagt das Feld nichts Wahres und
        // bleibt `None` — die UI unterscheidet dann ehrlich zwischen
        // „nicht in der Kette" und „Runtime kaputt".
        let (llamafile_lifecycle, llamafile_mode, llamafile_idle_timeout_seconds) =
            if llamafile_in_chain {
                let lifecycle = resolver
                    .llamafile_lifecycle()
                    .map(|lc| lc.as_str().to_string());
                (
                    lifecycle,
                    Some(llamafile_cfg.mode.clone()),
                    Some(llamafile_cfg.idle_timeout_seconds),
                )
            } else {
                (None, None, None)
            };

        StatusPayload {
            tts_enabled: tts.enabled,
            tts_available: tts.available,
            stt_enabled: stt.enabled,
            stt_available: stt.available,
            auto_speak: self.config.audio.auto_speak,
            ipc_enabled: self.config.ipc.enabled,
            interaction_enabled: self.config.interaction.enabled,
            interaction_backend: self.config.interaction.backend.clone(),
            approval_timeout_seconds: self.config.approval.timeout_seconds,
            accessibility_probe: probe.status_str().to_string(),
            accessibility_probe_reason: probe.reason().to_string(),
            text_provider_configured: text_provider.configured,
            text_provider_active: text_provider.active,
            text_provider_availability: text_provider.availability,
            text_provider_last_error: text_provider.last_error,
            text_provider_cloud: text_provider.cloud,
            text_provider_chain: chain,
            llamafile_in_chain,
            llamafile_enabled: llamafile_cfg.enabled,
            llamafile_configured,
            llamafile_lifecycle,
            llamafile_mode,
            llamafile_idle_timeout_seconds,
        }
    }

    /// Aktualisiert den live-Stand der Llamafile-Config (PR 5).
    ///
    /// Ablauf:
    ///
    ///   1. Validiert Mode (Whitelist) und Idle-Timeout (> 0). Bei
    ///      ungültigem Input `Err(...)` mit kurzer, Secret-freier
    ///      Meldung — der Aufrufer emittiert ein `error`-Envelope.
    ///   2. Merged die Eingabe mit dem bisherigen `live_llamafile`.
    ///      Fehlende Optionen bleiben unverändert; `path=Some("")`
    ///      löscht den Pfad.
    ///   3. Persistiert den neuen Stand im Settings-Store
    ///      ([`crate::settings_store`]). Persist-Fehler werden
    ///      geloggt, aber nicht hart propagiert — der In-Memory-Stand
    ///      ist für die laufende Session autoritativ.
    ///   4. Baut einen **neuen** `TextProviderResolver` mit der alten
    ///      Kette und der neuen Llamafile-View, ersetzt atomar die
    ///      `text_provider`-Referenz. Ein evtl. laufender alter
    ///      llamafile-Prozess wird beim Drop des alten Resolvers
    ///      beendet (`kill_on_drop`).
    ///   5. Der nächste `handle_text_query` / `build_status_payload`
    ///      sieht die neue Config; der nächste `get_status` spiegelt
    ///      sie in den UI-Readout.
    ///
    /// **Secret-/Log-Disziplin:** der Binary-Pfad taucht weder im
    /// `info!`-Pfad noch in der Rückgabe-Meldung auf — wir loggen nur,
    /// ob er gesetzt ist oder nicht.
    pub fn update_llamafile_config(
        &self,
        update: SettingsLlamafileUpdate,
    ) -> Result<(), String> {
        // Mode-Validierung: wenn Feld gesetzt, muss es aus der
        // Whitelist stammen. Im Schreibpfad lehnen wir unbekannte
        // Werte ausdrücklich ab (anders als der Startup-Parser, der
        // still auf den Default fällt).
        let mode_override: Option<String> = match update.mode.as_deref() {
            Some(raw) => match validate_llamafile_mode(raw) {
                Some(canonical) => Some(canonical.to_string()),
                None => {
                    return Err(format!(
                        "unknown llamafile mode `{raw}` — expected one of on_demand, standby",
                    ));
                }
            },
            None => None,
        };

        // Idle-Timeout-Validierung: 0 ist nicht sinnvoll (Watchdog
        // würde den Prozess sofort killen). Obergrenze lassen wir frei,
        // weil große Werte legitim sind (dauerhafter Betrieb).
        let idle_override: Option<u64> = match update.idle_timeout_seconds {
            Some(0) => {
                return Err("idle_timeout_seconds must be greater than 0".to_string());
            }
            Some(n) => Some(n),
            None => None,
        };

        // Merge mit bestehendem live-Stand.
        let mut merged: LlamafileConfig = self
            .live_llamafile
            .lock()
            .expect("live llamafile mutex poisoned")
            .clone();
        merged.enabled = update.enabled;
        if let Some(m) = mode_override {
            merged.mode = m;
        }
        if let Some(idle) = idle_override {
            merged.idle_timeout_seconds = idle;
        }
        if let Some(raw_path) = update.path {
            let trimmed = raw_path.trim();
            if trimmed.is_empty() {
                merged.path = None;
            } else {
                merged.path = Some(trimmed.to_string());
            }
        }

        // Persistieren. Fehler werden geloggt, nicht propagiert — ein
        // kaputter Settings-Store soll den In-Memory-Update-Pfad nicht
        // blockieren. Der Store selbst loggt keine Pfade.
        if let Err(err) = settings_store::save_llamafile_override(&merged) {
            warn!(error = %err, "failed to persist llamafile override");
        } else {
            info!(
                enabled = merged.enabled,
                mode = %merged.mode,
                idle_timeout_seconds = merged.idle_timeout_seconds,
                path_set = merged.path.is_some(),
                "llamafile override persisted",
            );
        }

        // Resolver rebuilden. Die Chain-Items sind immutable seit
        // Startup; nur die Llamafile-View ändert sich.
        let new_view = llamafile_view_from(&merged);
        let new_resolver = Arc::new(TextProviderResolver::from_chain(
            &self.text_provider_chain,
            &self.abrain_cmd,
            &new_view,
        ));

        // Atomar ersetzen. Der alte Arc lebt weiter, solange andere
        // Callsites (z. B. ein laufender `handle_text_query`) ihn
        // klonen; sobald er fällt, wird ein eventueller llamafile-
        // Prozess via `kill_on_drop` beendet.
        {
            let mut guard = self
                .text_provider
                .write()
                .expect("text provider lock poisoned");
            *guard = new_resolver;
        }

        // Live-Config aktualisieren (nach dem erfolgreichen Resolver-
        // Replace, damit ein paralleles `build_status_payload` zwischen
        // den beiden Locks einen kohärenten Stand sieht).
        {
            let mut guard = self
                .live_llamafile
                .lock()
                .expect("live llamafile mutex poisoned");
            *guard = merged;
        }

        Ok(())
    }

    /// Prüft defensiv, ob der `llamafile_local`-Provider startbereit
    /// aussieht. Kein Spawn, kein HTTP-Call — nur Config-Inspektion
    /// und eine Filesystem-Metadatenprüfung des Pfades. Gibt einen
    /// strukturierten `SettingsProbeResultPayload` zurück (PR 5).
    ///
    /// **Secret-Disziplin:** Weder Pfad noch andere sensitive Werte
    /// landen im Result — `message` und `class` sind ausschließlich
    /// kuratierte Tags und Kurzbeschreibungen.
    pub fn probe_llamafile(&self) -> SettingsProbeResultPayload {
        let cfg = self
            .live_llamafile
            .lock()
            .expect("live llamafile mutex poisoned")
            .clone();
        let resolver = self.current_resolver();
        let chain = resolver.chain_kinds();
        let in_chain = chain.iter().any(|k| *k == "llamafile_local");
        let enabled = cfg.enabled;
        let path_present = cfg
            .path
            .as_deref()
            .map(|p| !p.trim().is_empty())
            .unwrap_or(false);
        let configured = enabled && path_present;
        let lifecycle = if in_chain {
            resolver
                .llamafile_lifecycle()
                .map(|lc| lc.as_str().to_string())
        } else {
            None
        };

        if !in_chain {
            return SettingsProbeResultPayload {
                ok: false,
                class: "not_in_chain".into(),
                message: "llamafile_local is not in the configured text provider chain".into(),
                lifecycle,
                in_chain,
                enabled,
                configured,
            };
        }
        if !enabled {
            return SettingsProbeResultPayload {
                ok: false,
                class: "disabled".into(),
                message: "llamafile_local is disabled (master flag off)".into(),
                lifecycle,
                in_chain,
                enabled,
                configured,
            };
        }
        let Some(path_value) = cfg.path.as_deref().map(str::trim).filter(|p| !p.is_empty())
        else {
            return SettingsProbeResultPayload {
                ok: false,
                class: "not_configured".into(),
                message: "llamafile_local is enabled but has no binary path configured".into(),
                lifecycle,
                in_chain,
                enabled,
                configured,
            };
        };

        match std::fs::metadata(path_value) {
            Err(_) => SettingsProbeResultPayload {
                ok: false,
                class: "path_missing".into(),
                message: "configured binary path does not exist".into(),
                lifecycle,
                in_chain,
                enabled,
                configured,
            },
            Ok(meta) if !meta.is_file() => SettingsProbeResultPayload {
                ok: false,
                class: "path_not_file".into(),
                message: "configured binary path is not a regular file".into(),
                lifecycle,
                in_chain,
                enabled,
                configured,
            },
            Ok(meta) => {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if meta.permissions().mode() & 0o111 == 0 {
                        return SettingsProbeResultPayload {
                            ok: false,
                            class: "path_not_executable".into(),
                            message: "configured binary is present but not executable".into(),
                            lifecycle,
                            in_chain,
                            enabled,
                            configured,
                        };
                    }
                }
                let _ = meta; // silence unused on non-unix
                SettingsProbeResultPayload {
                    ok: true,
                    class: "ok".into(),
                    message: "llamafile_local looks ready (binary present, executable)".into(),
                    lifecycle,
                    in_chain,
                    enabled,
                    configured,
                }
            }
        }
    }
}

/// Baut eine `LlamafileConfigView` aus einer ausgewerteten
/// [`LlamafileConfig`]. Einzige Quelle der Wahrheit für die
/// Mapping-Regeln — sowohl der Startup-Konstruktor als auch der
/// PR-5-Schreibpfad gehen hier durch.
fn llamafile_view_from(cfg: &LlamafileConfig) -> LlamafileConfigView {
    LlamafileConfigView {
        enabled: cfg.enabled,
        path: cfg.path.clone(),
        mode: cfg.mode.clone(),
        idle_timeout_seconds: cfg.idle_timeout_seconds,
        port: cfg.port,
        startup_timeout_seconds: cfg.startup_timeout_seconds,
        request_timeout_seconds: cfg.request_timeout_seconds,
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

fn approval_message(
    action: &InteractionAction,
    selected_target: Option<&SelectedTarget>,
) -> String {
    let base = match action.kind() {
        InteractionKind::OpenApplication => format!("Smolit möchte {0}", action.title.to_lowercase()),
        InteractionKind::FocusWindow => {
            let label = action
                .title
                .strip_prefix("Focus ")
                .unwrap_or(&action.title);
            format!("Smolit möchte das Fenster \"{label}\" fokussieren.")
        }
        InteractionKind::TypeText => format!("Smolit möchte Text eingeben: {}", action.title),
        InteractionKind::SendShortcut => {
            format!("Smolit möchte einen Shortcut senden: {}", action.title)
        }
        InteractionKind::Noop | InteractionKind::Unknown => {
            format!("Confirm {kind}: {title}",
                kind = action.kind().as_str(),
                title = action.title
            )
        }
    };
    match selected_target {
        Some(target) => format!("{base} Ziel: {}", target.short_label()),
        None => base,
    }
}
