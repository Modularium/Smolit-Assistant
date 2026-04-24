extends PanelContainer
## Dev-only Audit Trail View (PR 19).
##
## Zeigt die letzten Audit-Einträge aus dem Core-Ring-Buffer in einer
## schmalen Liste. Das Panel ist **standardmäßig hidden** und wird
## nur bei `SMOLIT_UI_DEV_CONTROLS=1` sichtbar geschaltet. Kein
## Export, kein Copy, kein Persistenz-Pfad.
##
## Harte Grenzen:
##
##   * **Kein Produkt-UI.** Diese Ansicht ist ein Dev-/Debug-Tool.
##   * **Keine Seiteneffekte außer einem `audit_recent`-Request.**
##     Refresh sendet einen IPC-Command, nichts sonst.
##   * **Keine Redaktion über den Core hinaus.** Die Liste spiegelt
##     nur, was der Core bereits sanitisiert geliefert hat.

const _ModelRef := preload("res://scripts/audit/audit_model.gd")

## Standardlimit für einen Refresh. Bewusst klein — die UI soll keine
## Log-Wand werden.
const DEFAULT_LIMIT: int = 20

const ENV_ENABLE: String = "SMOLIT_UI_DEV_CONTROLS"

var _list_box: VBoxContainer = null
var _refresh_button: Button = null
var _status_label: Label = null
var _header_label: Label = null
var _last_payload: Dictionary = {"events": []}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = _env_enabled()

	_ensure_ui_built()
	_connect_event_bus()
	_render(_last_payload)


## Lazy-UI-Guard. Godot im `--script`-Modus dispatcht `_ready` nicht
## immer synchron mit `add_child`, bevor externe Aufrufer (Smoke) die
## Render-Pfade anwerfen. Wir bauen die UI deshalb beim ersten
## Zugriff auf.
func _ensure_ui_built() -> void:
	if _list_box != null:
		return
	_build_ui()


func _env_enabled() -> bool:
	var raw: String = OS.get_environment(ENV_ENABLE).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(outer)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	outer.add_child(header_row)

	_header_label = Label.new()
	_header_label.text = "Audit trail (dev)"
	_header_label.add_theme_font_size_override("font_size", 10)
	_header_label.modulate = Color(1, 1, 1, 0.6)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_label)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.tooltip_text = "Fetch the %d most recent audit entries." % DEFAULT_LIMIT
	_refresh_button.pressed.connect(_on_refresh_pressed)
	header_row.add_child(_refresh_button)

	_status_label = Label.new()
	_status_label.text = "No entries yet."
	_status_label.add_theme_font_size_override("font_size", 9)
	_status_label.modulate = Color(1, 1, 1, 0.4)
	outer.add_child(_status_label)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 1)
	_list_box.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(_list_box)


func _connect_event_bus() -> void:
	# Defensiver Laufzeit-Lookup, damit der Smoke ohne Autoload nicht
	# crasht. Ohne EventBus fehlt nur der Auto-Refresh-Hook —
	# `set_payload` bleibt direkt nutzbar.
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("audit_panel: EventBus autoload not available; panel stays idle.")
		return
	if bus.has_signal("audit_recent_received"):
		bus.audit_recent_received.connect(_on_audit_recent)
	if bus.has_signal("ipc_disconnected"):
		bus.ipc_disconnected.connect(_on_ipc_disconnected)


# --- Public API (Smoke, Dev-Inspektion) ---------------------------------


## Sichtbarkeit zur Laufzeit umschalten — nur für Dev/Smoke.
func set_panel_visible(flag: bool) -> void:
	_ensure_ui_built()
	visible = flag


func is_panel_visible() -> bool:
	return visible


## Direkt ein Payload einspielen. Nutzt den gleichen Pfad wie der
## EventBus-Handler; bleibt robust gegen Null und Nicht-Dictionaries.
func set_payload(payload: Variant) -> void:
	_ensure_ui_built()
	_on_audit_recent(payload)


func current_snapshot() -> Dictionary:
	_ensure_ui_built()
	return {
		"visible": visible,
		"event_count": _list_box.get_child_count() if _list_box != null else 0,
		"status": _status_label.text if _status_label != null else "",
	}


func reset_for_tests() -> void:
	_ensure_ui_built()
	_last_payload = {"events": []}
	_render(_last_payload)


# --- Event handlers -----------------------------------------------------


func _on_refresh_pressed() -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null:
		push_warning("audit_panel: IpcClient autoload missing; cannot refresh.")
		return
	if not client.has_method("audit_recent"):
		push_warning("audit_panel: IpcClient.audit_recent() missing (older build).")
		return
	client.call("audit_recent", DEFAULT_LIMIT)


func _on_audit_recent(payload: Variant) -> void:
	if typeof(payload) == TYPE_DICTIONARY:
		_last_payload = payload
	else:
		_last_payload = {"events": []}
	_render(_last_payload)


func _on_ipc_disconnected() -> void:
	if _status_label != null:
		_status_label.text = "offline — refresh disabled"


# --- Rendering ----------------------------------------------------------


func _render(payload: Variant) -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()

	var events: Array = _ModelRef.events_from_payload(payload)
	if _status_label != null:
		if events.is_empty():
			_status_label.text = "No entries yet."
		else:
			_status_label.text = "%d entries" % events.size()

	# Neueste zuerst anzeigen, damit neueste Aktion oben erscheint.
	for i in range(events.size() - 1, -1, -1):
		var row_source: Variant = events[i]
		if row_source is Dictionary:
			_list_box.add_child(_build_row(row_source))


func _build_row(event: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var time_label := Label.new()
	time_label.text = _ModelRef.short_time(event.get("timestamp_ms", 0))
	time_label.add_theme_font_size_override("font_size", 9)
	time_label.modulate = Color(1, 1, 1, 0.45)
	row.add_child(time_label)

	var kind_label := Label.new()
	kind_label.text = _ModelRef.kind_label(event.get("kind", ""))
	kind_label.add_theme_font_size_override("font_size", 10)
	kind_label.modulate = _ModelRef.result_color(event.get("result", ""))
	row.add_child(kind_label)

	var risk_raw: Variant = event.get("risk", "")
	if typeof(risk_raw) == TYPE_STRING and String(risk_raw) != "":
		var risk_label := Label.new()
		risk_label.text = String(risk_raw)
		risk_label.add_theme_font_size_override("font_size", 9)
		risk_label.modulate = _ModelRef.risk_color(risk_raw)
		row.add_child(risk_label)

	var id_raw: Variant = event.get("action_id", event.get("approval_id", ""))
	if typeof(id_raw) == TYPE_STRING and String(id_raw) != "":
		var id_label := Label.new()
		id_label.text = _ModelRef.short_id(id_raw)
		id_label.add_theme_font_size_override("font_size", 9)
		id_label.modulate = Color(1, 1, 1, 0.5)
		row.add_child(id_label)

	var summary_raw: Variant = event.get("summary", "")
	if typeof(summary_raw) == TYPE_STRING and String(summary_raw) != "":
		var summary_label := Label.new()
		summary_label.text = _ModelRef.short_summary(summary_raw)
		summary_label.add_theme_font_size_override("font_size", 9)
		summary_label.modulate = Color(1, 1, 1, 0.7)
		summary_label.clip_text = true
		summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(summary_label)

	return row
