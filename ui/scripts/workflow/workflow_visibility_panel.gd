extends PanelContainer
## Workflow Visibility Overlay v1 (PR 16) — Panel-Controller.
##
## Konsumiert bestehende EventBus-Signale und rendert sie in eine
## kleine vertikale Kartenliste. Das Panel ist read-only, kein Editor,
## keine Eingabe. Es sendet keine IPC-Nachrichten, es speichert nichts
## über die aktuelle Interaktion hinaus, und es blockiert den Avatar
## nie — `mouse_filter = MOUSE_FILTER_IGNORE` ist bindend.
##
## Sichtbarkeit:
##
##   * Standardmäßig **hidden** (`visible = false`). Ein Opt-in per
##     `SMOLIT_WORKFLOW_OVERLAY=1` (oder der kleine Dev-Controls-
##     Toggle) schaltet es auf sichtbar.
##   * Auch ohne Opt-in laufen die Event-Handler mit — der State bleibt
##     also frisch, und ein späteres Sichtbar-Machen rendert die
##     aktuelle Interaktion korrekt.
##
## Bindende Grenzen (zum Mitnehmen):
##
##   * Keine neuen IPC-Events, kein Core-Hook, kein Emotion-Kanal.
##   * Keine Persistenz, kein Export, keine Historie über die aktuelle
##     Interaktion hinaus.
##   * Keine langen Texte — das Modell kürzt Snippets hart auf
##     `MAX_SNIPPET_CHARS = 60`.
##   * Kein Desktop-Automation-Pfad, kein Approval-/Interaction-Hook.

const _ModelRef := preload("res://scripts/workflow/workflow_visibility_model.gd")

const ENV_ENABLE: String = "SMOLIT_WORKFLOW_OVERLAY"

## Visuelle Tints pro Status. Bewusst klein gehalten: der Status wird
## über Farbtint + kurzen Textbadge kommuniziert, nicht über animierte
## Spinner oder Icons.
const _STATUS_COLOR: Dictionary = {
	_ModelRef.Status.PENDING: Color(0.75, 0.75, 0.75, 0.6),
	_ModelRef.Status.ACTIVE: Color(0.70, 0.90, 1.00, 1.0),
	_ModelRef.Status.DONE: Color(0.70, 1.00, 0.75, 0.95),
	_ModelRef.Status.FAILED: Color(1.00, 0.70, 0.70, 1.0),
	_ModelRef.Status.SKIPPED: Color(0.70, 0.70, 0.70, 0.55),
}

const _STATUS_BADGE: Dictionary = {
	_ModelRef.Status.PENDING: "·",
	_ModelRef.Status.ACTIVE: "▶",
	_ModelRef.Status.DONE: "✓",
	_ModelRef.Status.FAILED: "✕",
	_ModelRef.Status.SKIPPED: "—",
}


var _model: _ModelRef = null
var _cards_box: VBoxContainer = null
var _empty_label: Label = null
var _header_label: Label = null
var _enabled: bool = false


func _ready() -> void:
	# Presence-Panel: nimmt keine Eingaben. Klicks sollen immer durch
	# zum Avatar / CompactInput.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_model = _ModelRef.new()
	_build_ui()

	_enabled = _env_enabled()
	visible = _enabled

	_connect_event_bus()
	_render()


func _env_enabled() -> bool:
	var raw: String = OS.get_environment(ENV_ENABLE).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


# --- UI construction ----------------------------------------------------


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer)

	_header_label = Label.new()
	_header_label.text = "Workflow"
	_header_label.add_theme_font_size_override("font_size", 10)
	_header_label.modulate = Color(1, 1, 1, 0.6)
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_header_label)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 2)
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_cards_box)

	_empty_label = Label.new()
	_empty_label.text = "Idle — no workflow yet."
	_empty_label.add_theme_font_size_override("font_size", 10)
	_empty_label.modulate = Color(1, 1, 1, 0.4)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_empty_label)


# --- EventBus wiring ---------------------------------------------------


func _connect_event_bus() -> void:
	# Laufzeit-Lookup (keine statische `EventBus.…`-Verzweigung), damit
	# das Script auch in Smoke-/Test-Kontexten ohne Autoload parsen und
	# `_ready` durchlaufen kann. Ohne Bus bleibt das Panel hidden und
	# die Event-Handler sind still — genau wie im Normalbetrieb ohne
	# Opt-in.
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("workflow_visibility: EventBus autoload not available; panel stays quiet.")
		return
	if bus.has_signal("heard_received"):
		bus.heard_received.connect(_on_heard)
	if bus.has_signal("thinking_received"):
		bus.thinking_received.connect(_on_thinking)
	if bus.has_signal("response_received"):
		bus.response_received.connect(_on_response)
	if bus.has_signal("action_planned_received"):
		bus.action_planned_received.connect(_on_action_planned)
	if bus.has_signal("action_started_received"):
		# `action_started` promotet den ACTION-Step aus PENDING auf
		# ACTIVE, wenn bereits ein `action_planned` eingegangen ist.
		# Ansonsten behandeln wir es wie ein Planned-ohne-Payload.
		bus.action_started_received.connect(_on_action_started)
	if bus.has_signal("action_step_received"):
		bus.action_step_received.connect(_on_action_step)
	if bus.has_signal("action_completed_received"):
		bus.action_completed_received.connect(_on_action_completed)
	if bus.has_signal("action_failed_received"):
		bus.action_failed_received.connect(_on_action_failed)
	if bus.has_signal("action_cancelled_received"):
		bus.action_cancelled_received.connect(_on_action_cancelled)
	if bus.has_signal("speaking_started_received"):
		bus.speaking_started_received.connect(_on_speaking_started)
	if bus.has_signal("speaking_ended_received"):
		bus.speaking_ended_received.connect(_on_speaking_ended)
	if bus.has_signal("ipc_disconnected"):
		bus.ipc_disconnected.connect(_on_ipc_disconnected)


func _ts_ms() -> int:
	return int(Time.get_ticks_msec())


func _on_heard(text: String) -> void:
	_model.apply_heard(text, _ts_ms())
	_render()


func _on_thinking() -> void:
	_model.apply_thinking(_ts_ms())
	_render()


func _on_response(text: String) -> void:
	_model.apply_response(text, _ts_ms())
	_render()


func _on_action_planned(payload: Dictionary) -> void:
	_model.apply_action_planned(payload, _ts_ms())
	_render()


func _on_action_started(payload: Dictionary) -> void:
	# Wenn vorher kein `action_planned` kam, behandeln wir `started`
	# konservativ als Einstieg: wir upserten ACTION in ACTIVE und
	# merken uns die action_id. Das deckt Flows ab, in denen der Core
	# direkt mit `started` startet, ohne uns zu zerbrechen.
	_model.apply_action_planned(payload, _ts_ms())
	_render()


func _on_action_step(payload: Dictionary) -> void:
	_model.apply_action_step(payload, _ts_ms())
	_render()


func _on_action_completed(payload: Dictionary) -> void:
	_model.apply_action_completed(payload, _ts_ms())
	_render()


func _on_action_failed(payload: Dictionary) -> void:
	_model.apply_action_failed(payload, _ts_ms())
	_render()


func _on_action_cancelled(payload: Dictionary) -> void:
	_model.apply_action_cancelled(payload, _ts_ms())
	_render()


func _on_speaking_started(payload: Dictionary) -> void:
	_model.apply_speaking_started(payload, _ts_ms())
	_render()


func _on_speaking_ended(payload: Dictionary) -> void:
	_model.apply_speaking_ended(payload, _ts_ms())
	_render()


func _on_ipc_disconnected() -> void:
	_model.apply_disconnected()
	_render()


# --- Rendering ----------------------------------------------------------


func _render() -> void:
	if _cards_box == null:
		return

	for child in _cards_box.get_children():
		_cards_box.remove_child(child)
		child.queue_free()

	var snap: Dictionary = _model.snapshot()
	var steps: Array = snap.get("steps", [])
	if _empty_label != null:
		_empty_label.visible = steps.is_empty()

	for step in steps:
		_cards_box.add_child(_build_card(step as Dictionary))

	if _header_label != null:
		var suffix: String = ""
		if snap.get("offline", false):
			suffix = "  (offline)"
		elif snap.get("terminal", false):
			suffix = "  (done)"
		_header_label.text = "Workflow%s" % suffix


func _build_card(step: Dictionary) -> Control:
	var kind: int = int(step.get("kind", -1))
	var status: int = int(step.get("status", _ModelRef.Status.PENDING))
	var snippet: String = String(step.get("snippet", ""))
	var label_text: String = String(step.get("label", _ModelRef.kind_label(kind)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge := Label.new()
	badge.text = String(_STATUS_BADGE.get(status, "·"))
	badge.add_theme_font_size_override("font_size", 11)
	badge.modulate = _STATUS_COLOR.get(status, Color(1, 1, 1, 0.8))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)

	var kind_label := Label.new()
	kind_label.text = label_text
	kind_label.add_theme_font_size_override("font_size", 10)
	kind_label.modulate = _STATUS_COLOR.get(status, Color(1, 1, 1, 0.8))
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(kind_label)

	if not snippet.is_empty():
		var snippet_label := Label.new()
		snippet_label.text = "— %s" % snippet
		snippet_label.add_theme_font_size_override("font_size", 9)
		snippet_label.modulate = Color(1, 1, 1, 0.55)
		snippet_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		snippet_label.clip_text = true
		snippet_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(snippet_label)

	return row


# --- Public API --------------------------------------------------------


## Öffentlicher Lese-Hook für Tests und optionale Dev-Controls.
func snapshot() -> Dictionary:
	if _model == null:
		return {"steps": [], "terminal": false, "offline": false,
				"step_count": 0, "action_id": ""}
	return _model.snapshot()


## Toggle-Hook für Dev-Controls. Keine Persistenz, keine Env-Schreib-
## operation — das Flag lebt nur in der laufenden Session.
func set_overlay_visible(flag: bool) -> void:
	_enabled = flag
	visible = flag


func is_overlay_visible() -> bool:
	return _enabled


## Rein interner Reset — für Dev-/Smoke-Zwecke. Der normale Betrieb
## räumt beim nächsten Workflow automatisch auf.
func reset_for_tests() -> void:
	if _model == null:
		return
	_model.reset()
	_render()
