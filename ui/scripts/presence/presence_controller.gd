extends Node
## Presence Controller (Phase 3.3 MVP).
##
## Zentraler, kleiner Zustand für die UI-Präsenz. Hört auf EventBus und
## setzt die Presence zwischen Docked / Expanded / Action / Disconnected.
##
## Trennung:
##   * Presence-State (hier) = wie viel UI
##   * Avatar-State (`avatar_controller.gd`) = wie der Avatar gerade wirkt
## Beide laufen unabhängig voneinander.
##
## Kein Transport, keine Business-Logik, keine Animationen — nur Zustand
## + Signale. Layout-Anwendung übernimmt die Main-Szene.

const PresenceStateRef := preload("res://scripts/presence/presence_state.gd")

## Zeit, die eine Action nach Abschluss sichtbar „nachhallen" darf,
## bevor die UI zurück in den Base-Mode fällt.
const ACTION_COMPLETE_HOLD_SECONDS: float = 1.0
const ACTION_FAILED_HOLD_SECONDS: float = 1.6
const ACTION_CANCELLED_HOLD_SECONDS: float = 0.6

## Wird emittiert, wenn sich der sichtbare Presence-Mode ändert.
signal presence_changed(mode: int)

## Kontext einer aktuell sichtbaren Action. Keys:
##   active:        bool     — gibt es gerade eine Action?
##   action_id:     String
##   action_kind:   String
##   title:         String   — Titel aus action_planned
##   step:          String   — letzter action_step.title
##   target_text:   String   — symbolische Kurzbeschreibung
##   status:        String   — "" | "completed" | "failed" | "cancelled"
##   status_message:String   — optionaler Fehler-/Infotext
signal action_context_changed(info: Dictionary)

var _base_mode: int = PresenceStateRef.DEFAULT_BASE
var _current_mode: int = PresenceStateRef.Mode.DISCONNECTED
var _connected: bool = false

var _action_active: bool = false
var _action_id: String = ""
var _action_kind: String = ""
var _action_title: String = ""
var _action_step: String = ""
var _action_target_text: String = ""
var _action_status: String = ""
var _action_status_message: String = ""

var _hold_timer: Timer = null


func _ready() -> void:
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)

	EventBus.ipc_connected.connect(_on_connected)
	EventBus.ipc_disconnected.connect(_on_disconnected)

	EventBus.action_planned_received.connect(_on_action_planned)
	EventBus.action_started_received.connect(_on_action_started)
	EventBus.action_step_received.connect(_on_action_step)
	EventBus.action_progress_received.connect(_on_action_progress)
	EventBus.action_verification_received.connect(_on_action_verification)
	EventBus.action_completed_received.connect(_on_action_completed)
	EventBus.action_failed_received.connect(_on_action_failed)
	EventBus.action_cancelled_received.connect(_on_action_cancelled)

	_connected = IpcClient.is_connected_to_core()
	_apply_presence(_resolve_mode_when_idle())
	_emit_context()


## Öffentliche API für manuelle Umschaltung (Docked ↔ Expanded).
func set_base_mode(mode: int) -> void:
	if not PresenceStateRef.is_base_mode(mode):
		return
	_base_mode = mode
	if not _action_active and _connected:
		_apply_presence(mode)


func toggle_base_mode() -> void:
	var next := PresenceStateRef.Mode.EXPANDED \
		if _base_mode == PresenceStateRef.Mode.DOCKED \
		else PresenceStateRef.Mode.DOCKED
	set_base_mode(next)


func current_mode() -> int:
	return _current_mode


func base_mode() -> int:
	return _base_mode


func _resolve_mode_when_idle() -> int:
	if not _connected:
		return PresenceStateRef.Mode.DISCONNECTED
	return _base_mode


func _apply_presence(mode: int) -> void:
	if mode == _current_mode:
		return
	_current_mode = mode
	presence_changed.emit(mode)


func _emit_context() -> void:
	action_context_changed.emit({
		"active": _action_active,
		"action_id": _action_id,
		"action_kind": _action_kind,
		"title": _action_title,
		"step": _action_step,
		"target_text": _action_target_text,
		"status": _action_status,
		"status_message": _action_status_message,
	})


func _reset_action() -> void:
	_action_active = false
	_action_id = ""
	_action_kind = ""
	_action_title = ""
	_action_step = ""
	_action_target_text = ""
	_action_status = ""
	_action_status_message = ""


func _on_connected() -> void:
	_connected = true
	_hold_timer.stop()
	if not _action_active:
		_apply_presence(_base_mode)


func _on_disconnected() -> void:
	_connected = false
	_hold_timer.stop()
	_reset_action()
	_apply_presence(PresenceStateRef.Mode.DISCONNECTED)
	_emit_context()


# --- Action Events --------------------------------------------------------

func _on_action_planned(payload: Dictionary) -> void:
	_action_active = true
	_action_id = str(payload.get("action_id", ""))
	_action_kind = str(payload.get("action_kind", ""))
	_action_title = str(payload.get("title", "action"))
	_action_step = ""
	_action_target_text = _target_text_of(payload.get("target", {}))
	_action_status = ""
	_action_status_message = ""
	_emit_context()


func _on_action_started(_payload: Dictionary) -> void:
	_action_active = true
	_hold_timer.stop()
	if _connected:
		_apply_presence(PresenceStateRef.Mode.ACTION)
	_emit_context()


func _on_action_step(payload: Dictionary) -> void:
	if not _action_active:
		# Event ohne vorheriges `planned` — trotzdem sichtbar machen.
		_action_active = true
		_action_id = str(payload.get("action_id", ""))
	_action_step = str(payload.get("title", ""))
	if _connected and _current_mode != PresenceStateRef.Mode.ACTION:
		_apply_presence(PresenceStateRef.Mode.ACTION)
	_emit_context()


func _on_action_progress(payload: Dictionary) -> void:
	if not _action_active:
		return
	var msg := str(payload.get("message", ""))
	if msg != "":
		_action_step = msg
		_emit_context()


func _on_action_verification(payload: Dictionary) -> void:
	if not _action_active:
		_action_active = true
	_action_step = str(payload.get("title", "verifying"))
	_emit_context()


func _on_action_completed(payload: Dictionary) -> void:
	_action_status = "completed"
	_action_status_message = str(payload.get("message", ""))
	_emit_context()
	_start_hold(ACTION_COMPLETE_HOLD_SECONDS)


func _on_action_failed(payload: Dictionary) -> void:
	_action_status = "failed"
	_action_status_message = str(payload.get("message", "action failed"))
	_emit_context()
	_start_hold(ACTION_FAILED_HOLD_SECONDS)


func _on_action_cancelled(payload: Dictionary) -> void:
	_action_status = "cancelled"
	_action_status_message = str(payload.get("message", ""))
	_emit_context()
	_start_hold(ACTION_CANCELLED_HOLD_SECONDS)


func _start_hold(seconds: float) -> void:
	_hold_timer.stop()
	_hold_timer.wait_time = max(seconds, 0.01)
	_hold_timer.start()


func _on_hold_timeout() -> void:
	_reset_action()
	_emit_context()
	_apply_presence(_resolve_mode_when_idle())


## Symbolisches Visual Mapping: sehr kleine Zeichenkette für die
## Banner-Anzeige. Keine Geometrie, keine Pixel.
func _target_text_of(target: Variant) -> String:
	if typeof(target) != TYPE_DICTIONARY:
		return ""
	var kind := str(target.get("type", ""))
	match kind:
		"application":
			return "→ %s" % str(target.get("name", "application"))
		"window":
			var title := str(target.get("title", ""))
			var app := str(target.get("app", ""))
			if title != "":
				return "→ %s" % title
			if app != "":
				return "→ %s" % app
			return "→ window"
		"ui_element":
			var role := str(target.get("role", "element"))
			var label := str(target.get("label", ""))
			if label != "":
				return "→ %s (%s)" % [label, role]
			return "→ %s" % role
		"region":
			var name := str(target.get("name", ""))
			if name != "":
				return "→ %s" % name
			return "→ region"
		"unknown", "":
			return ""
		_:
			return "→ %s" % kind
