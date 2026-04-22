extends Control
## Phase 3.3 Presence MVP root.
##
## Wires the presence controller to the visible layout:
##   * Header shows connection + presence + toggle
##   * Docked mode hides log/input (ruhige Präsenz)
##   * Expanded mode shows log/input
##   * Action mode surfaces an ActionBanner with symbolic target info
##
## Presence-State (UI-Umfang) und Avatar-State (visueller Ausdruck) laufen
## bewusst getrennt — hier wird nur der Presence-Teil verkabelt.

const PresenceStateRef := preload("res://scripts/presence/presence_state.gd")

@onready var _presence: Node = $PresenceController

@onready var _status: Label = $VBox/HeaderRow/StatusLabel
@onready var _presence_label: Label = $VBox/HeaderRow/PresenceLabel
@onready var _presence_toggle: Button = $VBox/HeaderRow/PresenceToggle

@onready var _action_banner: PanelContainer = $VBox/ActionBanner
@onready var _action_title: Label = $VBox/ActionBanner/ActionVBox/ActionTitle
@onready var _target_row: HBoxContainer = $VBox/ActionBanner/ActionVBox/TargetRow
@onready var _target_kind_chip: Label = $VBox/ActionBanner/ActionVBox/TargetRow/TargetKindChip
@onready var _target_name: Label = $VBox/ActionBanner/ActionVBox/TargetRow/TargetName
@onready var _target_detail: Label = $VBox/ActionBanner/ActionVBox/TargetRow/TargetDetail
@onready var _mapping_chip: Label = $VBox/ActionBanner/ActionVBox/MappingChip
@onready var _action_step: Label = $VBox/ActionBanner/ActionVBox/ActionStep
@onready var _action_target: Label = $VBox/ActionBanner/ActionVBox/ActionTarget
@onready var _action_status: Label = $VBox/ActionBanner/ActionVBox/ActionStatus

@onready var _approval_banner: PanelContainer = $VBox/ApprovalBanner
@onready var _approval_title: Label = $VBox/ApprovalBanner/ApprovalVBox/ApprovalTitle
@onready var _approval_message: Label = $VBox/ApprovalBanner/ApprovalVBox/ApprovalMessage
@onready var _approval_timeout: Label = $VBox/ApprovalBanner/ApprovalVBox/ApprovalTimeout
@onready var _approve_button: Button = $VBox/ApprovalBanner/ApprovalVBox/ApprovalButtons/ApproveButton
@onready var _deny_button: Button = $VBox/ApprovalBanner/ApprovalVBox/ApprovalButtons/DenyButton

@onready var _discovery_panel: PanelContainer = $VBox/DiscoveryPanel
@onready var _discovery_title: Label = $VBox/DiscoveryPanel/DiscoveryVBox/DiscoveryHeader/DiscoveryTitle
@onready var _discovery_status_badge: Label = $VBox/DiscoveryPanel/DiscoveryVBox/DiscoveryHeader/DiscoveryStatusBadge
@onready var _discovery_reason: Label = $VBox/DiscoveryPanel/DiscoveryVBox/DiscoveryReason
@onready var _discovery_items: VBoxContainer = $VBox/DiscoveryPanel/DiscoveryVBox/DiscoveryItems
@onready var _discovery_empty: Label = $VBox/DiscoveryPanel/DiscoveryVBox/DiscoveryEmpty
@onready var _selected_target_row: HBoxContainer = $VBox/DiscoveryPanel/DiscoveryVBox/SelectedTargetRow
@onready var _selected_target_label: Label = $VBox/DiscoveryPanel/DiscoveryVBox/SelectedTargetRow/SelectedTargetLabel
@onready var _clear_target_button: Button = $VBox/DiscoveryPanel/DiscoveryVBox/SelectedTargetRow/ClearTargetButton
@onready var _approval_selected_target: Label = $VBox/ApprovalBanner/ApprovalVBox/ApprovalSelectedTarget

var _current_approval_id: String = ""

## The latest `target_selected` payload echoed by the core. Treated as
## purely symbolic: we render it, compare item rows to highlight the
## selected one, and clear it on disconnect / error / explicit clear.
## We never derive implicit permissions from its presence.
var _current_selected_target: Dictionary = {}

@onready var _log: RichTextLabel = $VBox/Log
@onready var _input_row: HBoxContainer = $VBox/InputRow
@onready var _input: LineEdit = $VBox/InputRow/Input
@onready var _send_button: Button = $VBox/InputRow/SendButton
@onready var _ping_button: Button = $VBox/InputRow/PingButton


func _ready() -> void:
	_send_button.pressed.connect(_on_send_pressed)
	_ping_button.pressed.connect(_on_ping_pressed)
	_input.text_submitted.connect(_on_text_submitted)
	_presence_toggle.pressed.connect(_on_presence_toggle_pressed)

	EventBus.ipc_connected.connect(_on_connected)
	EventBus.ipc_disconnected.connect(_on_disconnected)
	EventBus.pong_received.connect(_on_pong)
	EventBus.status_received.connect(_on_status)
	EventBus.thinking_received.connect(_on_thinking)
	EventBus.response_received.connect(_on_response)
	EventBus.heard_received.connect(_on_heard)
	EventBus.error_received.connect(_on_error)

	EventBus.action_planned_received.connect(_on_action_planned_log)
	EventBus.action_started_received.connect(_on_action_started_log)
	EventBus.action_step_received.connect(_on_action_step_log)
	EventBus.action_completed_received.connect(_on_action_completed_log)
	EventBus.action_failed_received.connect(_on_action_failed_log)
	EventBus.action_cancelled_received.connect(_on_action_cancelled_log)

	EventBus.approval_requested_received.connect(_on_approval_requested)
	EventBus.approval_resolved_received.connect(_on_approval_resolved)

	EventBus.accessibility_probe_result_received.connect(_on_accessibility_probe_result)
	EventBus.accessibility_discovery_result_received.connect(_on_accessibility_discovery_result)

	EventBus.target_selected_received.connect(_on_target_selected)
	EventBus.target_cleared_received.connect(_on_target_cleared)

	_approve_button.pressed.connect(_on_approve_pressed)
	_deny_button.pressed.connect(_on_deny_pressed)
	_clear_target_button.pressed.connect(_on_clear_target_pressed)

	_presence.presence_changed.connect(_on_presence_changed)
	_presence.action_context_changed.connect(_on_action_context_changed)

	_set_connected(IpcClient.is_connected_to_core())
	_apply_presence_mode(_presence.current_mode())
	_action_banner.visible = false
	_approval_banner.visible = false
	_discovery_panel.visible = false
	_selected_target_row.visible = false
	_approval_selected_target.visible = false


func _set_connected(ok: bool) -> void:
	_status.text = "connected" if ok else "disconnected"
	_send_button.disabled = not ok
	_ping_button.disabled = not ok


func _append(line: String) -> void:
	_log.append_text(line + "\n")


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	IpcClient.submit_text(text)
	_append("[b]> %s[/b]" % text)
	_input.text = ""


func _on_ping_pressed() -> void:
	IpcClient.ping()
	_append("[i]ping →[/i]")


func _on_text_submitted(_text: String) -> void:
	_on_send_pressed()


func _on_presence_toggle_pressed() -> void:
	_presence.toggle_base_mode()


func _on_connected() -> void:
	_set_connected(true)
	_append("[color=green]connected[/color]")


func _on_disconnected() -> void:
	_set_connected(false)
	_append("[color=orange]disconnected[/color]")
	# Drop any held Interaction target — the core forgets on its own
	# state, and a stale badge after a reconnect would be misleading.
	_reset_selected_target_ui()


func _on_pong() -> void:
	_append("[i]← pong[/i]")


func _on_status(payload: Dictionary) -> void:
	_append("[i]status: %s[/i]" % JSON.stringify(payload))


func _on_thinking() -> void:
	_append("[i]thinking…[/i]")


func _on_response(text: String) -> void:
	_append("[color=cyan]%s[/color]" % text)


func _on_heard(text: String) -> void:
	_append("[i]heard: %s[/i]" % text)


func _on_error(message: String) -> void:
	_append("[color=red]error: %s[/color]" % message)


# --- Presence wiring ------------------------------------------------------

func _on_presence_changed(mode: int) -> void:
	_apply_presence_mode(mode)


func _apply_presence_mode(mode: int) -> void:
	var label := PresenceStateRef.name_of(mode)
	_presence_label.text = "presence: %s" % label

	match mode:
		PresenceStateRef.Mode.DOCKED:
			_log.visible = false
			_input_row.visible = false
			_presence_toggle.text = "Expand"
			_presence_toggle.disabled = false
		PresenceStateRef.Mode.EXPANDED:
			_log.visible = true
			_input_row.visible = true
			_presence_toggle.text = "Dock"
			_presence_toggle.disabled = false
		PresenceStateRef.Mode.ACTION:
			# Während einer Action bleibt das zuletzt gewählte Base-Layout
			# sichtbar; wir heben nur den Banner hervor (siehe
			# _on_action_context_changed). Toggle bleibt bedienbar.
			_presence_toggle.disabled = false
		PresenceStateRef.Mode.DISCONNECTED:
			_log.visible = true
			_input_row.visible = true
			_presence_toggle.text = "Expand"
			_presence_toggle.disabled = true


func _on_action_context_changed(info: Dictionary) -> void:
	var active: bool = bool(info.get("active", false))
	if not active:
		_action_banner.visible = false
		return

	_action_banner.visible = true
	_action_title.text = str(info.get("title", "action"))
	_action_step.text = str(info.get("step", ""))
	_action_target.text = str(info.get("target_text", ""))

	_apply_target_row(info)
	_apply_mapping_chip(info)

	var status := str(info.get("status", ""))
	var message := str(info.get("status_message", ""))
	match status:
		"":
			_action_status.text = ""
			_action_status.modulate = Color(1, 1, 1, 0.85)
		"completed":
			_action_status.text = "✓ %s" % message if message != "" else "✓ completed"
			_action_status.modulate = Color(0.55, 0.85, 0.6)
		"failed":
			_action_status.text = "✗ %s" % message if message != "" else "✗ failed"
			_action_status.modulate = Color(0.9, 0.45, 0.45)
		"cancelled":
			_action_status.text = "– %s" % message if message != "" else "– cancelled"
			_action_status.modulate = Color(0.85, 0.75, 0.4)
		_:
			_action_status.text = message
			_action_status.modulate = Color(1, 1, 1, 0.85)


# --- Action log lines (kompakt, nur Info-Charakter) ----------------------

func _on_action_planned_log(payload: Dictionary) -> void:
	var title := str(payload.get("title", "action"))
	_append("[color=gray]▶ planned: %s[/color]" % title)


func _on_action_started_log(payload: Dictionary) -> void:
	var kind := str(payload.get("action_kind", ""))
	_append("[color=gray]▶ started (%s)[/color]" % kind)


func _on_action_step_log(payload: Dictionary) -> void:
	var title := str(payload.get("title", ""))
	if title != "":
		_append("[color=gray]• %s[/color]" % title)


func _on_action_completed_log(payload: Dictionary) -> void:
	var msg := str(payload.get("message", ""))
	if msg != "":
		_append("[color=green]✓ %s[/color]" % msg)
	else:
		_append("[color=green]✓ action completed[/color]")


func _on_action_failed_log(payload: Dictionary) -> void:
	var msg := str(payload.get("message", "action failed"))
	_append("[color=red]✗ %s[/color]" % msg)


func _on_action_cancelled_log(payload: Dictionary) -> void:
	var msg := str(payload.get("message", "action cancelled"))
	_append("[color=orange]– %s[/color]" % msg)


# --- Approval banner ------------------------------------------------------

func _on_approval_requested(payload: Dictionary) -> void:
	_current_approval_id = str(payload.get("approval_id", ""))
	_approval_title.text = str(payload.get("title", "Confirm action"))
	_approval_message.text = str(payload.get("message", ""))
	var timeout_s := int(payload.get("timeout_seconds", 0))
	if timeout_s > 0:
		_approval_timeout.text = "timeout: %d s" % timeout_s
	else:
		_approval_timeout.text = ""
	# If the core snapshotted a selected target at request time, render
	# it as an extra line — read-only context, does not imply consent.
	var selected_variant: Variant = payload.get("selected_target", null)
	if typeof(selected_variant) == TYPE_DICTIONARY:
		_approval_selected_target.text = "Target: %s" % _format_selected_target(selected_variant)
		_approval_selected_target.visible = true
	else:
		_approval_selected_target.text = ""
		_approval_selected_target.visible = false
	_approve_button.disabled = false
	_deny_button.disabled = false
	_approval_banner.visible = true
	_append("[color=yellow]? approval requested: %s[/color]" % _approval_message.text)


func _on_approval_resolved(payload: Dictionary) -> void:
	var decision := str(payload.get("decision", ""))
	var resolved_id := str(payload.get("approval_id", ""))
	if resolved_id == _current_approval_id:
		_current_approval_id = ""
		_approval_banner.visible = false
	_append("[color=gray]approval resolved: %s[/color]" % decision)


func _on_approve_pressed() -> void:
	_send_current_decision("approved")


func _on_deny_pressed() -> void:
	_send_current_decision("denied")


func _send_current_decision(decision: String) -> void:
	if _current_approval_id.is_empty():
		return
	IpcClient.send_approval_response(_current_approval_id, decision)
	_approve_button.disabled = true
	_deny_button.disabled = true


# --- Target & Mapping rendering ------------------------------------------

## Kleine Tint-Map pro Target-Kind. Nur symbolisch — keine Semantik
## daran hängen außer der Unterscheidbarkeit im Banner.
const TARGET_KIND_COLORS: Dictionary = {
	"application": Color(0.75, 0.85, 1.0, 0.9),
	"window": Color(0.6, 0.85, 0.75, 0.9),
	"ui_element": Color(0.95, 0.8, 0.6, 0.9),
	"region": Color(0.85, 0.75, 0.95, 0.9),
	"unknown": Color(1, 1, 1, 0.45),
}


func _apply_target_row(info: Dictionary) -> void:
	var kind := str(info.get("target_kind", ""))
	var name := str(info.get("target_name", ""))
	var detail := str(info.get("target_detail", ""))

	# Fallback: Wenn weder Kind noch Name vorliegen, Row ausblenden.
	# Die kompakte Ziel-Zeile (ActionTarget) bleibt davon unberührt.
	if kind == "" and name == "" and detail == "":
		_target_row.visible = false
		return

	_target_row.visible = true
	var chip_kind := kind if kind != "" else "unknown"
	_target_kind_chip.text = "[%s]" % chip_kind
	_target_kind_chip.modulate = TARGET_KIND_COLORS.get(chip_kind, TARGET_KIND_COLORS["unknown"])
	_target_name.text = name
	_target_detail.visible = detail != ""
	_target_detail.text = detail


func _apply_mapping_chip(info: Dictionary) -> void:
	var space := str(info.get("mapping_space", ""))
	var hint := str(info.get("mapping_hint", ""))
	var window := str(info.get("mapping_window", ""))

	if space == "" and hint == "" and window == "":
		_mapping_chip.visible = false
		return

	var parts := PackedStringArray()
	if space != "":
		parts.append("mapping: %s" % space)
	if hint != "":
		parts.append(hint)
	if window != "":
		parts.append("window: %s" % window)
	_mapping_chip.text = " · ".join(parts)
	_mapping_chip.visible = true


# --- Accessibility discovery rendering -----------------------------------

## Badge-Farben pro discovery-status. Rein visuell, keine Semantik
## außer der Unterscheidbarkeit im Panel.
const _DISCOVERY_STATUS_COLORS: Dictionary = {
	"ok": Color(0.55, 0.85, 0.6),
	"uncertain": Color(0.85, 0.8, 0.4),
	"unavailable": Color(0.85, 0.55, 0.55),
	"failed": Color(0.9, 0.45, 0.45),
}

## Badge-Farben pro item-confidence (verified/discovered).
const _DISCOVERY_CONFIDENCE_COLORS: Dictionary = {
	"verified": Color(0.55, 0.85, 0.6),
	"discovered": Color(0.75, 0.85, 1.0),
}


func _on_accessibility_probe_result(payload: Dictionary) -> void:
	var status := str(payload.get("status", ""))
	var reason := str(payload.get("reason", ""))
	if status == "" and reason == "":
		return
	if reason != "":
		_append("[color=gray]◇ a11y probe: %s — %s[/color]" % [status, reason])
	else:
		_append("[color=gray]◇ a11y probe: %s[/color]" % status)


func _on_accessibility_discovery_result(payload: Dictionary) -> void:
	var status := str(payload.get("status", ""))
	var reason := str(payload.get("reason", ""))
	var raw_items: Variant = payload.get("items", [])
	var items: Array = raw_items if typeof(raw_items) == TYPE_ARRAY else []

	_render_discovery_panel(status, reason, items)

	# Kompakter Log-Eintrag, unabhängig vom Panel.
	var summary := "[color=gray]◇ a11y discovery: %s" % status
	if items.size() > 0:
		summary += " (%d item%s)" % [items.size(), "" if items.size() == 1 else "s"]
	summary += "[/color]"
	_append(summary)


func _render_discovery_panel(status: String, reason: String, items: Array) -> void:
	_clear_discovery_items()
	_discovery_panel.visible = true

	var badge_text := "[—]"
	if status != "":
		badge_text = "[%s]" % status
	_discovery_status_badge.text = badge_text
	_discovery_status_badge.modulate = _DISCOVERY_STATUS_COLORS.get(
		status, Color(1, 1, 1, 0.6)
	)

	_discovery_reason.visible = reason != ""
	_discovery_reason.text = reason

	match status:
		"ok":
			if items.is_empty():
				_show_discovery_empty("no items")
			else:
				for raw_item in items:
					if typeof(raw_item) == TYPE_DICTIONARY:
						_discovery_items.add_child(_build_discovery_item_row(raw_item))
		"uncertain":
			if items.is_empty():
				_show_discovery_empty("probe plausible, no structured items yet")
			else:
				for raw_item in items:
					if typeof(raw_item) == TYPE_DICTIONARY:
						_discovery_items.add_child(_build_discovery_item_row(raw_item))
		"unavailable":
			_show_discovery_empty("accessibility pathway unavailable")
		"failed":
			_show_discovery_empty("discovery failed")
		_:
			_show_discovery_empty("")


func _clear_discovery_items() -> void:
	for child in _discovery_items.get_children():
		child.queue_free()
	_discovery_empty.visible = false


func _show_discovery_empty(text: String) -> void:
	_discovery_empty.text = text
	_discovery_empty.visible = text != ""


func _build_discovery_item_row(item: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var item_name := str(item.get("name", ""))
	var role := str(item.get("role", ""))
	var kind := str(item.get("kind", ""))
	var confidence := str(item.get("confidence", ""))
	var detail := str(item.get("detail", ""))
	var matched_hint := str(item.get("matched_hint", ""))
	var item_source := str(item.get("source", ""))

	var badge := Label.new()
	badge.text = "[%s]" % (confidence if confidence != "" else "?")
	badge.modulate = _DISCOVERY_CONFIDENCE_COLORS.get(
		confidence, Color(1, 1, 1, 0.5)
	)
	row.add_child(badge)

	var name_label := Label.new()
	if item_name != "":
		name_label.text = item_name
	else:
		name_label.text = "(unnamed)"
		name_label.modulate = Color(1, 1, 1, 0.5)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var role_label := Label.new()
	var role_text := role if role != "" else kind
	role_label.text = role_text
	role_label.modulate = Color(1, 1, 1, 0.55)
	row.add_child(role_label)

	# Optionale Zusatzinfo: matched_hint ≠ name, sonst detail, sonst source.
	var extra := ""
	if matched_hint != "" and matched_hint != item_name:
		extra = "hint=%s" % matched_hint
	elif detail != "":
		extra = detail
	elif item_source != "":
		extra = item_source
	if extra != "":
		var extra_label := Label.new()
		extra_label.text = extra
		extra_label.modulate = Color(1, 1, 1, 0.4)
		row.add_child(extra_label)

	# "Select" button — only meaningful when we have a non-empty name.
	# The button is the sole selection affordance; clicking it sends the
	# `interaction_select_target` frame and waits for the `target_selected`
	# echo before showing the badge.
	if item_name != "":
		var select_button := Button.new()
		var already_selected := _is_same_selected(item)
		select_button.text = "Selected" if already_selected else "Select"
		select_button.disabled = already_selected
		select_button.pressed.connect(_on_item_select_pressed.bind(item))
		row.add_child(select_button)

		if already_selected:
			name_label.modulate = Color(0.75, 0.85, 1, 1.0)

	return row


func _is_same_selected(item: Dictionary) -> bool:
	if _current_selected_target.is_empty():
		return false
	var sel_name := str(_current_selected_target.get("name", ""))
	var sel_role := str(_current_selected_target.get("role", ""))
	var item_name := str(item.get("name", ""))
	var item_role := str(item.get("role", ""))
	# Fall back to kind when the item has no explicit role (discovery
	# rows render kind as role when role is absent).
	if item_role == "":
		item_role = str(item.get("kind", ""))
	return sel_name != "" and sel_name == item_name and sel_role == item_role


func _on_item_select_pressed(item: Dictionary) -> void:
	var item_name := str(item.get("name", ""))
	if item_name == "":
		return
	var role := str(item.get("role", ""))
	if role == "":
		role = str(item.get("kind", ""))
	if role == "":
		role = "unknown"
	var confidence := str(item.get("confidence", "discovered"))
	var source := str(item.get("source", "accessibility"))
	var payload := {
		"name": item_name,
		"role": role,
		"confidence": confidence,
		"source": source,
	}
	var matched_hint := str(item.get("matched_hint", ""))
	if matched_hint != "":
		payload["matched_hint"] = matched_hint
	var app_name := str(item.get("app_name", ""))
	if app_name != "":
		payload["app_name"] = app_name
	# Let the core mint the id — the UI never synthesizes ids that the
	# core would overwrite on validation.
	payload["id"] = ""
	IpcClient.select_target(payload)


func _on_clear_target_pressed() -> void:
	IpcClient.clear_target()


# --- Target selection round-trip -----------------------------------------

func _on_target_selected(payload: Dictionary) -> void:
	var target_variant: Variant = payload.get("target", {})
	if typeof(target_variant) != TYPE_DICTIONARY:
		return
	var target: Dictionary = target_variant
	_current_selected_target = target
	_selected_target_label.text = _format_selected_target(target)
	_selected_target_row.visible = true
	_discovery_panel.visible = true
	_refresh_discovery_row_buttons()
	_append("[color=cyan]◉ target selected: %s[/color]" % _format_selected_target(target))


func _on_target_cleared(payload: Dictionary) -> void:
	var had_selection := not _current_selected_target.is_empty()
	_reset_selected_target_ui()
	if had_selection:
		var previous_variant: Variant = payload.get("previous", null)
		if typeof(previous_variant) == TYPE_DICTIONARY:
			_append("[color=gray]◌ target cleared: %s[/color]" % _format_selected_target(previous_variant))
		else:
			_append("[color=gray]◌ target cleared[/color]")


func _reset_selected_target_ui() -> void:
	_current_selected_target = {}
	_selected_target_label.text = ""
	_selected_target_row.visible = false
	_refresh_discovery_row_buttons()


func _format_selected_target(target: Dictionary) -> String:
	var tname := str(target.get("name", ""))
	var trole := str(target.get("role", ""))
	var tconf := str(target.get("confidence", ""))
	if tname == "":
		return "(unnamed)"
	if trole == "" and tconf == "":
		return tname
	var parts := PackedStringArray()
	if trole != "":
		parts.append(trole)
	if tconf != "":
		parts.append(tconf)
	return "%s (%s)" % [tname, ", ".join(parts)]


## Re-render the last-known discovery items so "Select"/"Selected"
## buttons reflect the current selection. The last payload is read
## directly from visible state: we keep no separate cache — if the
## panel is not showing items, there is nothing to refresh.
func _refresh_discovery_row_buttons() -> void:
	for row in _discovery_items.get_children():
		if not (row is HBoxContainer):
			continue
		var button: Button = null
		for child in row.get_children():
			if child is Button:
				button = child
				break
		if button == null:
			continue
		# Find the first Label sibling whose text is not a bracketed
		# badge; that is the name label we used at build time.
		var item_name := ""
		for child in row.get_children():
			if child is Label:
				var text_value := (child as Label).text
				if not text_value.begins_with("[") and text_value != "(unnamed)":
					item_name = text_value
					break
		if item_name == "":
			continue
		var selected_name := str(_current_selected_target.get("name", ""))
		var is_selected := selected_name != "" and selected_name == item_name
		button.text = "Selected" if is_selected else "Select"
		button.disabled = is_selected
