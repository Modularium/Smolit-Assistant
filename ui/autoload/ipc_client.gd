extends Node
## Local WebSocket client for the Smolit Rust core.
##
## Mirrors the protocol defined in core/src/ipc/protocol.rs. The UI
## consumes outgoing events via EventBus; this node is the single
## producer of those signals. Reconnect with exponential backoff; on
## every successful connect, auto-issue `get_status` as handshake.

const _CONFIG_PATH := "res://config.cfg"
const _DEFAULT_URL := "ws://127.0.0.1:8787"
const _DEFAULT_MIN_BACKOFF_MS := 500
const _DEFAULT_MAX_BACKOFF_MS := 5000

var _ws: WebSocketPeer = WebSocketPeer.new()
var _url: String = _DEFAULT_URL
var _min_backoff_ms: int = _DEFAULT_MIN_BACKOFF_MS
var _max_backoff_ms: int = _DEFAULT_MAX_BACKOFF_MS
var _debug: bool = false

var _last_state: int = -1
var _next_backoff_ms: int = _DEFAULT_MIN_BACKOFF_MS
var _reconnect_wait_s: float = 0.0
var _waiting_for_reconnect: bool = false


func _ready() -> void:
	_load_config()
	_next_backoff_ms = _min_backoff_ms
	_start_connect()


func is_connected_to_core() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func ping() -> void:
	_send({"type": "ping"})


func get_status() -> void:
	_send({"type": "get_status"})


func submit_text(text: String) -> void:
	_send({"type": "submit_text", "text": text})


func speak_text(text: String) -> void:
	_send({"type": "speak_text", "text": text})


func voice_once() -> void:
	_send({"type": "voice_once"})


## Replies to a pending `approval_requested` from the core.
## `decision` must be one of "approved", "denied", "cancelled".
func send_approval_response(approval_id: String, decision: String) -> void:
	_send({
		"type": "approval_response",
		"approval_id": approval_id,
		"decision": decision,
	})


## PR 17 — schmaler Approve-Pfad; wire-äquivalent zu
## `send_approval_response(..., "approved")`, nur mit separatem
## `type`-Wert. Der Core akzeptiert beide.
func approval_approve(approval_id: String) -> void:
	_send({
		"type": "approval_approve",
		"approval_id": approval_id,
	})


## PR 17 — schmaler Deny-Pfad. Siehe [method approval_approve].
func approval_deny(approval_id: String) -> void:
	_send({
		"type": "approval_deny",
		"approval_id": approval_id,
	})


## PR 17 — harmloser Demo-Auslöser. Keine Systemaktion danach. Dient
## nur zur Evaluation der Approval-Card-UX. Alle Argumente sind
## optional; der Core kuratiert kurze Defaults, wenn sie fehlen. Die
## UI reicht Strings unverändert durch — *keine* lokale Sanitisierung
## sensibler Inhalte; der Aufrufer ist verantwortlich, ausschließlich
## harmlose Demo-Texte mitzugeben.
func request_approval_demo(
	title: Variant = null,
	summary: Variant = null,
	risk: Variant = null,
) -> void:
	var payload: Dictionary = {"type": "request_approval_demo"}
	if typeof(title) == TYPE_STRING:
		payload["title"] = String(title)
	if typeof(summary) == TYPE_STRING:
		payload["summary"] = String(summary)
	if typeof(risk) == TYPE_STRING:
		payload["risk"] = String(risk)
	_send(payload)


## PR 18 — Approval-Gated Demo-Action-Planner. Erzeugt einen
## harmlosen `DemoPlan` am Core; der Core führt einen reinen Mock
## aus (action_started → action_step → action_completed) — **keine**
## Systemaktion, keine Shell, keine Dateisystem-Operation. Wenn
## `requires_approval=true`, wartet der Core auf `approval_approve`
## bzw. `approval_deny` via der Approval-Card (PR 17).
##
## Alle Felder sind optional; der Core füllt sichere Defaults ein
## (Titel „Demo action", Summary-Hinweis, Kind `noop`, Risk `medium`).
func plan_demo_action(
	title: Variant = null,
	summary: Variant = null,
	risk: Variant = null,
	kind: Variant = null,
	requires_approval: Variant = null,
) -> void:
	var payload: Dictionary = {"type": "plan_demo_action"}
	if typeof(title) == TYPE_STRING:
		payload["title"] = String(title)
	if typeof(summary) == TYPE_STRING:
		payload["summary"] = String(summary)
	if typeof(risk) == TYPE_STRING:
		payload["risk"] = String(risk)
	if typeof(kind) == TYPE_STRING:
		payload["kind"] = String(kind)
	if typeof(requires_approval) == TYPE_BOOL:
		payload["requires_approval"] = bool(requires_approval)
	_send(payload)


## Select a discovered target as the current Interaction context. The
## core validates and echoes back a `target_selected` envelope (or an
## `error` frame when the payload is malformed). Selection is *not*
## permission — follow-up actions still require approval.
func select_target(target: Dictionary) -> void:
	_send({
		"type": "interaction_select_target",
		"target": target,
	})


## Clear the current Interaction context. Idempotent on the core — a
## `target_cleared` envelope is always returned.
func clear_target() -> void:
	_send({"type": "interaction_clear_target"})


## PR 5 — Schreibpfad für die editierbare `llamafile_local`-Config.
## Der Core validiert, rebuildet den Resolver und antwortet entweder
## mit einem `status`-Envelope (neuer Stand) oder einem `error` (bei
## ungültigem Mode / Idle-Timeout). Optionen mit `null` bleiben
## unverändert; `path=""` löscht den Pfad explizit.
##
## Der Binary-Pfad wird nicht geloggt — die UI reicht ihn nur direkt
## an den Core weiter und behält ihn nicht in EventBus-Readouts.
func settings_set_llamafile_config(
	enabled: bool,
	mode: Variant = null,
	idle_timeout_seconds: Variant = null,
	path: Variant = null,
) -> void:
	var payload: Dictionary = {
		"type": "settings_set_llamafile_config",
		"enabled": enabled,
	}
	if typeof(mode) == TYPE_STRING and String(mode) != "":
		payload["mode"] = String(mode)
	if typeof(idle_timeout_seconds) == TYPE_INT:
		payload["idle_timeout_seconds"] = int(idle_timeout_seconds)
	if typeof(path) == TYPE_STRING:
		# Leere oder nur-whitespace-Strings reichen wir als "" durch —
		# der Core interpretiert das als "Pfad löschen".
		payload["path"] = String(path)
	_send(payload)


## PR 5 — Diagnose-Probe für `llamafile_local`. Keine Side-Effects
## (kein Spawn, kein HTTP). Antwort kommt als
## `settings_probe_result_received`-Signal am EventBus.
func settings_probe_llamafile() -> void:
	_send({"type": "settings_probe_llamafile"})


## PR 7 — Schreibpfad für die editierbaren STT-Settings. Der Core
## rebuildet den STT-Resolver atomar; ein Erfolg spiegelt sich sofort
## im nachfolgenden `status`-Envelope. `command=null` lässt den
## bisherigen Wert stehen, `command=""` löscht ihn.
func settings_set_stt_config(enabled: bool, command: Variant = null) -> void:
	var payload: Dictionary = {
		"type": "settings_set_stt_config",
		"enabled": enabled,
	}
	if typeof(command) == TYPE_STRING:
		payload["command"] = String(command)
	_send(payload)


## PR 7 — Schreibpfad für die editierbaren TTS-Settings. Spiegel zu
## `settings_set_stt_config`; zusätzlich `auto_speak` als optionales
## Flag (null → unverändert).
func settings_set_tts_config(
	enabled: bool,
	command: Variant = null,
	auto_speak: Variant = null,
) -> void:
	var payload: Dictionary = {
		"type": "settings_set_tts_config",
		"enabled": enabled,
	}
	if typeof(command) == TYPE_STRING:
		payload["command"] = String(command)
	if typeof(auto_speak) == TYPE_BOOL:
		payload["auto_speak"] = bool(auto_speak)
	_send(payload)


## PR 7 — Diagnose-Probe für die STT-Achse. Kein Mikrofon-Zugriff,
## keine Audio-Aufnahme. Antwort kommt als
## `settings_probe_result_received` mit `axis="stt"`.
func settings_probe_stt() -> void:
	_send({"type": "settings_probe_stt"})


## PR 7 — Diagnose-Probe für die TTS-Achse.
func settings_probe_tts() -> void:
	_send({"type": "settings_probe_tts"})


## PR 8 — Schreibpfad für die editierbaren `local_http`-Settings.
## `endpoint=null` lässt den bisherigen Wert stehen, `endpoint=""`
## löscht ihn. `request_timeout_seconds=null` lässt den Wert
## unverändert; `0` wird vom Core abgelehnt.
func settings_set_local_http_config(
	enabled: bool,
	endpoint: Variant = null,
	request_timeout_seconds: Variant = null,
) -> void:
	var payload: Dictionary = {
		"type": "settings_set_local_http_config",
		"enabled": enabled,
	}
	if typeof(endpoint) == TYPE_STRING:
		payload["endpoint"] = String(endpoint)
	if typeof(request_timeout_seconds) == TYPE_INT:
		payload["request_timeout_seconds"] = int(request_timeout_seconds)
	_send(payload)


## PR 8 — Diagnose-Probe für den `local_http`-Provider. Der Core
## macht einen TCP-Connect auf den geparsten Endpoint, **nicht** mehr.
## Antwort kommt als `settings_probe_result_received` mit
## `axis="local_http"`.
func settings_probe_local_http() -> void:
	_send({"type": "settings_probe_local_http"})


## PR 9 — Text-Provider-Chain-Editor. `chain` ist eine geordnete Liste
## bekannter Kind-Namen (`abrain` / `llamafile_local` / `local_http`).
## Der Core validiert (Whitelist, Duplikate, Empty-Reject) und
## antwortet mit `status` bei Erfolg bzw. `error` bei Validation-
## Fehlern.
func settings_set_text_provider_chain(chain: Array) -> void:
	var normalized: Array[String] = []
	for entry in chain:
		normalized.append(String(entry))
	_send({
		"type": "settings_set_text_provider_chain",
		"chain": normalized,
	})


## PR 9 — Reset auf den Default `["abrain"]`. Löscht den
## persistierten Override im Core.
func settings_reset_text_provider_chain() -> void:
	_send({"type": "settings_reset_text_provider_chain"})


## PR 13 — STT-Provider-Chain-Editor. `chain` ist eine geordnete
## Liste bekannter Audio-Kind-Namen (heute nur `command`). Der Core
## validiert gegen `KNOWN_STT_KINDS`.
func settings_set_stt_provider_chain(chain: Array) -> void:
	var normalized: Array[String] = []
	for entry in chain:
		normalized.append(String(entry))
	_send({
		"type": "settings_set_stt_provider_chain",
		"chain": normalized,
	})


## PR 13 — Reset der STT-Kette auf Default `["command"]`.
func settings_reset_stt_provider_chain() -> void:
	_send({"type": "settings_reset_stt_provider_chain"})


## PR 13 — TTS-Provider-Chain-Editor. Spiegel zum STT-Pfad.
func settings_set_tts_provider_chain(chain: Array) -> void:
	var normalized: Array[String] = []
	for entry in chain:
		normalized.append(String(entry))
	_send({
		"type": "settings_set_tts_provider_chain",
		"chain": normalized,
	})


func settings_reset_tts_provider_chain() -> void:
	_send({"type": "settings_reset_tts_provider_chain"})


## PR 10 — operationale Cloud-HTTP-Config (Endpoint / Model / Timeout /
## Enabled). **Enthält keinen API-Key** — der läuft über
## `settings_set_cloud_http_secret`.
func settings_set_cloud_http_config(
	enabled: bool,
	endpoint: Variant = null,
	model: Variant = null,
	request_timeout_seconds: Variant = null,
) -> void:
	var payload := {
		"type": "settings_set_cloud_http_config",
		"enabled": enabled,
	}
	if endpoint != null:
		payload["endpoint"] = String(endpoint)
	if model != null:
		payload["model"] = String(model)
	if request_timeout_seconds != null:
		payload["request_timeout_seconds"] = int(request_timeout_seconds)
	_send(payload)


## PR 10 — Cloud-HTTP-Secret schreiben oder löschen. Der Key verlässt
## diese Funktion auf direktem Weg über die IPC-Pipe zum Core; der
## Core persistiert ihn in `secrets.json` (0600). Leerer String oder
## `null` → Key wird gelöscht.
func settings_set_cloud_http_secret(api_key: Variant) -> void:
	var payload := {"type": "settings_set_cloud_http_secret"}
	if api_key == null:
		payload["api_key"] = null
	else:
		payload["api_key"] = String(api_key)
	_send(payload)


## PR 10 — Cloud-HTTP-Probe. TCP-Connect gegen den geparsten Endpoint,
## kein Completion-Request, kein Bearer-Header auf der Leitung.
## Antwort: `settings_probe_result_received` mit `axis="cloud_http"`.
func settings_probe_cloud_http() -> void:
	_send({"type": "settings_probe_cloud_http"})


func _load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_CONFIG_PATH)
	if err != OK:
		push_warning("ipc_client: %s not found, using defaults" % _CONFIG_PATH)
		return
	_url = str(cfg.get_value("ipc", "websocket_url", _url))
	_min_backoff_ms = int(cfg.get_value("reconnect", "min_backoff_ms", _min_backoff_ms))
	_max_backoff_ms = int(cfg.get_value("reconnect", "max_backoff_ms", _max_backoff_ms))
	_debug = bool(cfg.get_value("debug", "verbose", false))


func _start_connect() -> void:
	_waiting_for_reconnect = false
	_ws = WebSocketPeer.new()
	_last_state = -1
	if _debug:
		print("[ipc] connecting to %s" % _url)
	var err := _ws.connect_to_url(_url)
	if err != OK:
		push_warning("[ipc] connect_to_url failed: %d" % err)
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	_waiting_for_reconnect = true
	_reconnect_wait_s = float(_next_backoff_ms) / 1000.0
	_next_backoff_ms = min(_next_backoff_ms * 2, _max_backoff_ms)
	if _debug:
		print("[ipc] reconnect in %.2fs (next backoff %dms)" % [_reconnect_wait_s, _next_backoff_ms])


func _process(delta: float) -> void:
	if _waiting_for_reconnect:
		_reconnect_wait_s -= delta
		if _reconnect_wait_s <= 0.0:
			_start_connect()
		return

	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state != _last_state:
		_last_state = state
		match state:
			WebSocketPeer.STATE_OPEN:
				_next_backoff_ms = _min_backoff_ms
				EventBus.ipc_connected.emit()
				get_status()
			WebSocketPeer.STATE_CLOSED:
				EventBus.ipc_disconnected.emit()
				_schedule_reconnect()
				return

	if state == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			_handle_frame(raw)


func _send(msg: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		EventBus.error_received.emit("not connected")
		return
	var err := _ws.send_text(JSON.stringify(msg))
	if err != OK:
		EventBus.error_received.emit("send failed: %d" % err)


func _handle_frame(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		EventBus.error_received.emit("invalid JSON frame from core")
		return
	var type := str(parsed.get("type", ""))
	match type:
		"pong":
			EventBus.pong_received.emit()
		"status":
			var payload: Variant = parsed.get("payload", {})
			if typeof(payload) == TYPE_DICTIONARY:
				EventBus.status_received.emit(payload)
		"thinking":
			EventBus.thinking_received.emit()
		"response":
			EventBus.response_received.emit(_extract_text(parsed))
		"heard":
			EventBus.heard_received.emit(_extract_text(parsed))
		"error":
			EventBus.error_received.emit(str(parsed.get("message", "unknown error")))
		"action_planned":
			EventBus.action_planned_received.emit(_extract_payload(parsed))
		"action_started":
			EventBus.action_started_received.emit(_extract_payload(parsed))
		"action_progress":
			EventBus.action_progress_received.emit(_extract_payload(parsed))
		"action_step":
			EventBus.action_step_received.emit(_extract_payload(parsed))
		"action_verification":
			EventBus.action_verification_received.emit(_extract_payload(parsed))
		"action_completed":
			EventBus.action_completed_received.emit(_extract_payload(parsed))
		"action_failed":
			EventBus.action_failed_received.emit(_extract_payload(parsed))
		"action_cancelled":
			EventBus.action_cancelled_received.emit(_extract_payload(parsed))
		"approval_requested":
			EventBus.approval_requested_received.emit(_extract_payload(parsed))
		"approval_resolved":
			EventBus.approval_resolved_received.emit(_extract_payload(parsed))
		"accessibility_probe_result":
			EventBus.accessibility_probe_result_received.emit(_extract_payload(parsed))
		"accessibility_discovery_result":
			EventBus.accessibility_discovery_result_received.emit(_extract_payload(parsed))
		"target_selected":
			EventBus.target_selected_received.emit(_extract_payload(parsed))
		"target_cleared":
			EventBus.target_cleared_received.emit(_extract_payload(parsed))
		"settings_probe_result":
			EventBus.settings_probe_result_received.emit(_extract_payload(parsed))
		"speaking_started":
			EventBus.speaking_started_received.emit(_extract_payload(parsed))
		"speaking_ended":
			EventBus.speaking_ended_received.emit(_extract_payload(parsed))
		_:
			if _debug:
				push_warning("[ipc] unknown message type: %s" % type)


func _extract_payload(parsed: Dictionary) -> Dictionary:
	var payload: Variant = parsed.get("payload", {})
	if typeof(payload) == TYPE_DICTIONARY:
		return payload
	return {}


func _extract_text(parsed: Dictionary) -> String:
	var payload: Variant = parsed.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		return ""
	return str(payload.get("text", ""))
