extends Node
## Central signal hub for UI ↔ IPC communication.
##
## Scenes listen on EventBus only. IpcClient is the sole producer of these
## signals — swapping out the transport in the future means changing
## IpcClient, not the scenes. No business logic lives here.

signal ipc_connected
signal ipc_disconnected
signal pong_received
signal status_received(payload: Dictionary)
signal thinking_received
signal response_received(text: String)
signal heard_received(text: String)
signal error_received(message: String)

## Action Event Model v1 (see docs/api.md §2.5). Payload shapes match the
## core emission 1:1; scenes may read any field they need. Unknown
## variants degrade gracefully — the UI only reads fields it knows.
signal action_planned_received(payload: Dictionary)
signal action_started_received(payload: Dictionary)
signal action_progress_received(payload: Dictionary)
signal action_step_received(payload: Dictionary)
signal action_verification_received(payload: Dictionary)
signal action_completed_received(payload: Dictionary)
signal action_failed_received(payload: Dictionary)
signal action_cancelled_received(payload: Dictionary)

## Approval / Confirmation Flow (see docs/api.md). Core emits
## `approval_requested` when an action is gated by confirmation and
## `approval_resolved` once the decision is final (approved, denied,
## cancelled, or timed_out). The UI reacts to both and sends an
## `approval_response` frame via IpcClient.send_approval_response().
signal approval_requested_received(payload: Dictionary)
signal approval_resolved_received(payload: Dictionary)

## Accessibility / AT-SPI spike (see docs/api.md §2.8). Both envelopes
## are additive to the existing Action Event stream — the UI may render
## them in parallel with `action_*` phases. Payload shape is honest:
## `status` is one of `ok` / `uncertain` / `unavailable` / `failed`,
## per-item `confidence` is `verified` / `discovered`. UI never
## upgrades a `discovered` to `verified` itself; that is the core's
## call.
signal accessibility_probe_result_received(payload: Dictionary)
signal accessibility_discovery_result_received(payload: Dictionary)

## Target Selection (see docs/api.md §2.9). UI sends
## `interaction_select_target` / `interaction_clear_target` frames; the
## core confirms with `target_selected` / `target_cleared`. Selection
## is *not* permission — every follow-up action still goes through the
## approval flow, and the UI must never derive implicit rights from a
## held target.
signal target_selected_received(payload: Dictionary)
signal target_cleared_received(payload: Dictionary)

## Settings / Secrets / Probe (PR 5, siehe docs/api.md §2.10 bzw.
## docs/provider_fallback_and_settings_architecture.md §9). Das Panel
## sendet `settings_set_llamafile_config` / `settings_probe_llamafile`
## über IpcClient; der Core antwortet entweder mit einem frischen
## `status`-Envelope (auf erfolgreiche Schreibaktion), einem
## `settings_probe_result` (auf Probe) oder einem `error`-Envelope
## (auf Validation-Fehler). Read-only: die UI trifft keine Provider-
## Entscheidung, sie spiegelt den Core-Stand und zeigt Probe-Ergebnisse.
signal settings_probe_result_received(payload: Dictionary)

## TTS-Lebenszyklus (PR 14, siehe docs/api.md §2.11). Der Core
## emittiert genau dann `speaking_started` / `speaking_ended`, wenn
## ein TTS-Provider tatsächlich anläuft — sowohl im aktiven
## `speak_text`-Pfad als auch im passiven `auto_speak`-Pfad nach einer
## `response`. Payload-Felder: `source` (`"speak_text"` | `"auto_speak"`),
## `provider` (primärer bzw. tatsächlich aktiver Kind-Name, heute nur
## `"command"`), optional `action_id`. `speaking_ended` ergänzt
## `ok: bool` und optional `error_class`. UI-Konsumenten müssen
## defensiv sein: bleibt ein `speaking_ended` aus (z. B. abgebrochene
## Verbindung), fallen die bestehenden Hold-Timer weiterhin korrekt
## zurück auf `idle`.
signal speaking_started_received(payload: Dictionary)
signal speaking_ended_received(payload: Dictionary)

## Local Audit Trail v1 (PR 19). Dev-/Debug-Hilfe. Die UI
## konsumiert `audit_recent`-Envelopes und rendert sie im optionalen
## Audit-Panel. Kein Produkt-Feature; kein Export, kein Copy. Der
## Core liefert ausschließlich bereits sanitisierte Einträge.
signal audit_recent_received(payload: Dictionary)
