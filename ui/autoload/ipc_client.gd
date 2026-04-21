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
		_:
			if _debug:
				push_warning("[ipc] unknown message type: %s" % type)


func _extract_text(parsed: Dictionary) -> String:
	var payload: Variant = parsed.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		return ""
	return str(payload.get("text", ""))
