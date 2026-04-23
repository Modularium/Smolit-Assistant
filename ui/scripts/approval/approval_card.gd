extends PanelContainer
## Approval Card UX v1 (PR 17) — read-only + choice UI.
##
## Zeigt einen einzelnen pending Approval-Request an (Titel, Summary,
## Risk-Badge) und bietet zwei Buttons: **Approve** und **Deny**. Der
## Klick sendet direkt das passende IPC-Kommando (`approval_approve`
## bzw. `approval_deny`) über den bestehenden `IpcClient`. Das
## `approval_resolved`-Envelope des Cores beendet den Zyklus —
## gewonnen wird die Entscheidung genau einmal; doppelte Klicks sind
## durch die Core-Registry idempotent gesichert.
##
## Bindende Grenzen:
##
##   * **Keine Aktion nach dem Klick außer dem IPC-Frame.** Die Card
##     selbst führt nichts aus, öffnet keine Anwendung, schickt
##     keinen Shell-Befehl, wählt keinen Provider.
##   * **Keine sensiblen Full-Payloads im UI.** Summary ist auf
##     `MAX_SUMMARY_CHARS = 140` gekürzt; Titel auf 80. Lange Texte
##     werden mit Ellipsis abgeschnitten.
##   * **Single-Slot.** Genau ein Approval ist gleichzeitig sichtbar.
##     Ein neues `approval_requested` ersetzt den bisherigen Inhalt.
##   * **Defensiv bei Disconnect.** `ipc_disconnected` deaktiviert
##     die Buttons, schließt die Card aber nicht hart — der Core kann
##     nach Reconnect ein `approval_resolved` mit `source: timeout`
##     nachreichen.
##   * **Kein Persistenz-/Logging-System.** Sichtbarkeit lebt nur
##     für die aktuelle Card.

const _ModelRef := preload("res://scripts/approval/approval_model.gd")

signal approve_pressed(approval_id: String)
signal deny_pressed(approval_id: String)

## Aktuell gehaltener Approval-Slot. Leer, wenn nichts offen ist.
var _approval_id: String = ""
var _resolving: bool = false

var _title_label: Label = null
var _risk_badge: Label = null
var _summary_label: Label = null
var _status_label: Label = null
var _approve_button: Button = null
var _deny_button: Button = null


func _ready() -> void:
	# Card fängt selbst keine Mauseingaben außerhalb der Buttons.
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false

	_ensure_ui_built()
	_connect_event_bus()
	_refresh_buttons()


## PR 17 — Smoke-freundliche Lazy-UI. Godot im `--script`-Modus
## dispatcht `_ready` nicht immer synchron mit `add_child`, bevor wir
## handler-nahe Funktionen aufrufen. Wir bauen die UI deshalb beim
## ersten Zugriff auf, damit der Smoke ohne Heartbeat-Frame stabil
## läuft. Im Normalbetrieb greift der Build in `_ready`, und der
## Lazy-Pfad ist ein No-op.
func _ensure_ui_built() -> void:
	if _title_label != null:
		return
	_build_ui()


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(outer)

	# Header row: Title + Risk badge.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Confirm action"
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_title_label)

	_risk_badge = Label.new()
	_risk_badge.text = "medium"
	_risk_badge.add_theme_font_size_override("font_size", 10)
	_risk_badge.modulate = _ModelRef.risk_color(_ModelRef.DEFAULT_RISK)
	_risk_badge.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_risk_badge)

	_summary_label = Label.new()
	_summary_label.text = ""
	_summary_label.add_theme_font_size_override("font_size", 11)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.modulate = Color(1, 1, 1, 0.9)
	_summary_label.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(_summary_label)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 9)
	_status_label.modulate = Color(1, 1, 1, 0.5)
	_status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(_status_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	outer.add_child(button_row)

	_approve_button = Button.new()
	_approve_button.text = "Approve"
	_approve_button.pressed.connect(_on_approve_pressed)
	button_row.add_child(_approve_button)

	_deny_button = Button.new()
	_deny_button.text = "Deny"
	_deny_button.pressed.connect(_on_deny_pressed)
	button_row.add_child(_deny_button)


func _connect_event_bus() -> void:
	# Laufzeit-Lookup, damit das Script auch in Smoke-Kontexten ohne
	# Autoload-Registrierung sauber durchläuft — dann bleibt die Card
	# still (kein Crash).
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("approval_card: EventBus autoload not available; card stays hidden.")
		return
	if bus.has_signal("approval_requested_received"):
		bus.approval_requested_received.connect(_on_approval_requested)
	if bus.has_signal("approval_resolved_received"):
		bus.approval_resolved_received.connect(_on_approval_resolved)
	if bus.has_signal("ipc_disconnected"):
		bus.ipc_disconnected.connect(_on_ipc_disconnected)
	if bus.has_signal("ipc_connected"):
		bus.ipc_connected.connect(_on_ipc_connected)


# --- Event handlers -----------------------------------------------------


func _on_approval_requested(payload: Dictionary) -> void:
	_ensure_ui_built()
	var approval_id: String = str(payload.get("approval_id", ""))
	if approval_id.is_empty():
		# Defensiv: ohne id gibt es keine sinnvolle Entscheidung.
		return
	_approval_id = approval_id
	_resolving = false
	_title_label.text = _ModelRef.trim_title(payload.get("title", "Confirm action"))
	_summary_label.text = _ModelRef.trim_summary(payload.get("message", ""))
	var risk: String = _ModelRef.sanitize_risk(payload.get("risk", _ModelRef.DEFAULT_RISK))
	_risk_badge.text = _ModelRef.risk_label(risk)
	_risk_badge.modulate = _ModelRef.risk_color(risk)
	_status_label.text = ""
	visible = true
	_refresh_buttons()


func _on_approval_resolved(payload: Dictionary) -> void:
	_ensure_ui_built()
	var resolved_id: String = str(payload.get("approval_id", ""))
	if resolved_id != _approval_id:
		# Ein Resolved für eine andere Card (ältere Banner-Flow o. ä.)
		# lassen wir ignorieren — wir räumen nur unseren eigenen Slot.
		return
	var decision: String = str(payload.get("decision", ""))
	var source: String = str(payload.get("source", _ModelRef.SOURCE_USER))
	_status_label.text = "resolved: %s (%s)" % [decision, source]
	_approval_id = ""
	_resolving = false
	_refresh_buttons()
	# Card bleibt noch kurz sichtbar mit dem finalen Status, damit der
	# User die Entscheidung quittiert sieht. Das Ausblenden übernimmt
	# das nächste `approval_requested` oder ein expliziter `hide()`
	# durch den Host — wir lassen den Zustand bewusst stehen.
	_approve_button.modulate = Color(1, 1, 1, 0.5)
	_deny_button.modulate = Color(1, 1, 1, 0.5)


func _on_ipc_disconnected() -> void:
	_ensure_ui_built()
	_resolving = false
	_approval_id = ""
	_status_label.text = "offline — buttons disabled"
	_refresh_buttons()


func _on_ipc_connected() -> void:
	# Nach Reconnect darf die Card wieder reagieren, falls der Core
	# noch einen Approval emittiert. Der eigene Slot ist beim
	# Disconnect bereits geleert worden.
	_ensure_ui_built()
	_status_label.text = ""
	_approve_button.modulate = Color(1, 1, 1, 1)
	_deny_button.modulate = Color(1, 1, 1, 1)
	_refresh_buttons()


# --- Button handlers ----------------------------------------------------


func _on_approve_pressed() -> void:
	_ensure_ui_built()
	if _approval_id.is_empty() or _resolving:
		return
	_resolving = true
	_status_label.text = "waiting for core…"
	_refresh_buttons()
	_send_decision(true)
	approve_pressed.emit(_approval_id)


func _on_deny_pressed() -> void:
	_ensure_ui_built()
	if _approval_id.is_empty() or _resolving:
		return
	_resolving = true
	_status_label.text = "waiting for core…"
	_refresh_buttons()
	_send_decision(false)
	deny_pressed.emit(_approval_id)


func _send_decision(approved: bool) -> void:
	if not is_inside_tree():
		# Smoke-/Dev-Kontext ohne aktiven Tree: Signal wurde bereits
		# emittiert, der tatsächliche IPC-Send entfällt still.
		return
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null:
		# Ohne Autoload können wir nur das Signal emittieren —
		# bringt uns in Smoke-Kontexten nicht aus dem Tritt.
		return
	if approved:
		if client.has_method("approval_approve"):
			client.call("approval_approve", _approval_id)
		elif client.has_method("send_approval_response"):
			# Fallback auf den älteren kombinierten Command-Pfad.
			client.call("send_approval_response", _approval_id, "approved")
	else:
		if client.has_method("approval_deny"):
			client.call("approval_deny", _approval_id)
		elif client.has_method("send_approval_response"):
			client.call("send_approval_response", _approval_id, "denied")


# --- Helpers ------------------------------------------------------------


func _refresh_buttons() -> void:
	var have_slot: bool = not _approval_id.is_empty()
	var connected: bool = _is_connected()
	var can_act: bool = have_slot and connected and not _resolving
	if _approve_button != null:
		_approve_button.disabled = not can_act
	if _deny_button != null:
		_deny_button.disabled = not can_act


func _is_connected() -> bool:
	# Smoke-Kontexte können das Script-Instanz ohne aktiven Tree
	# aufrufen; absolute Pfade sind dann ungültig. Defensiv: kein
	# Tree → als offline behandeln.
	if not is_inside_tree():
		return false
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null:
		return false
	if client.has_method("is_connected_to_core"):
		return bool(client.call("is_connected_to_core"))
	return true


# --- Public API for Smokes / Dev-Controls --------------------------------


## Schmaler Lese-Hook für Tests und Dev-Inspektor.
func current_snapshot() -> Dictionary:
	return {
		"visible": visible,
		"approval_id": _approval_id,
		"title": _title_label.text if _title_label != null else "",
		"summary": _summary_label.text if _summary_label != null else "",
		"risk_label": _risk_badge.text if _risk_badge != null else "",
		"status": _status_label.text if _status_label != null else "",
		"approve_disabled": _approve_button.disabled if _approve_button != null else true,
		"deny_disabled": _deny_button.disabled if _deny_button != null else true,
		"resolving": _resolving,
	}


## Setzt die Card intern zurück — Smoke-/Dev-Zwecke. Im Normalbetrieb
## genügt das nächste `approval_requested` bzw. `approval_resolved`
## zum Aufräumen.
func reset_for_tests() -> void:
	_approval_id = ""
	_resolving = false
	if _title_label != null:
		_title_label.text = "Confirm action"
	if _summary_label != null:
		_summary_label.text = ""
	if _status_label != null:
		_status_label.text = ""
	if _risk_badge != null:
		_risk_badge.text = _ModelRef.DEFAULT_RISK
		_risk_badge.modulate = _ModelRef.risk_color(_ModelRef.DEFAULT_RISK)
	visible = false
	_refresh_buttons()
