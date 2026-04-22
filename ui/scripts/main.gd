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
const _WindowBehaviorRef := preload("res://scripts/window_behavior/window_behavior.gd")

## Wird gesetzt, wenn der opt-in Click-through-Folgeschritt wirklich aktiv
## geworden ist. Reiner Lifetime-Anker — `main.gd` spricht den Controller
## nicht an, er hält nur seine eigene Signal-Subscription am Leben. Ohne
## diesen Verweis würde das `RefCounted` sofort nach `_ready()` freigegeben.
var _click_through_controller: RefCounted = null

@onready var _presence: Node = $PresenceController

@onready var _status: Label = $VBox/HeaderRow/StatusLabel

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

@onready var _dock_panel: PanelContainer = $VBox/DockPanel
@onready var _log: RichTextLabel = $VBox/DockPanel/DockVBox/Log
@onready var _input_row: HBoxContainer = $VBox/DockPanel/DockVBox/InputRow
@onready var _input: LineEdit = $VBox/DockPanel/DockVBox/InputRow/Input
@onready var _send_button: Button = $VBox/DockPanel/DockVBox/InputRow/SendButton
@onready var _ping_button: Button = $VBox/DockPanel/DockVBox/InputRow/PingButton

@onready var _avatar: Control = $Avatar

## Compact Input UX (Presence Interaction Layer).
##
## Leichtgewichtige Schnellinteraktion am Docked-Avatar: ein kleines
## Popup-Panel mit Text / Voice / Add Files / Show Commands. Es teilt
## sich Send- und Voice-Pfad mit der bestehenden Expanded-Eingabe und
## hält *keine* eigene Business-Logik — das ist bewusst ein UI-Substate,
## nicht ein neuer globaler Presence-Mode.
@onready var _compact_panel: PanelContainer = $CompactInputPanel
@onready var _compact_input: LineEdit = $CompactInputPanel/CompactVBox/CompactInputRow/CompactInput
@onready var _compact_send_button: Button = $CompactInputPanel/CompactVBox/CompactInputRow/CompactSendButton
@onready var _compact_voice_button: Button = $CompactInputPanel/CompactVBox/CompactActionsRow/CompactVoiceButton
@onready var _compact_add_files_button: Button = $CompactInputPanel/CompactVBox/CompactActionsRow/CompactAddFilesButton
@onready var _compact_commands_button: Button = $CompactInputPanel/CompactVBox/CompactActionsRow/CompactCommandsButton
@onready var _compact_close_button: Button = $CompactInputPanel/CompactVBox/CompactHeaderRow/CompactCloseButton
@onready var _compact_hint: Label = $CompactInputPanel/CompactVBox/CompactHint
@onready var _compact_commands_hint: Label = $CompactInputPanel/CompactVBox/CompactCommandsHint

var _compact_input_open: bool = false

const _COMPACT_COMMANDS_TEXT: String = "help · voice · audio-status · interaction_probe_accessibility · interaction_discover_accessibility"


func _ready() -> void:
	_send_button.pressed.connect(_on_send_pressed)
	_ping_button.pressed.connect(_on_ping_pressed)
	_input.text_submitted.connect(_on_text_submitted)

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

	_compact_send_button.pressed.connect(_on_compact_send_pressed)
	_compact_voice_button.pressed.connect(_on_compact_voice_pressed)
	_compact_add_files_button.pressed.connect(_on_compact_add_files_pressed)
	_compact_commands_button.pressed.connect(_on_compact_commands_pressed)
	_compact_close_button.pressed.connect(_on_compact_close_pressed)
	_compact_input.text_submitted.connect(_on_compact_text_submitted)
	_avatar.clicked.connect(_on_avatar_clicked)
	_avatar.toggle_dock.connect(_on_avatar_toggle_dock)
	_avatar.moved.connect(_on_avatar_moved)

	_presence.presence_changed.connect(_on_presence_changed)
	_presence.action_context_changed.connect(_on_action_context_changed)

	_set_connected(IpcClient.is_connected_to_core())
	_apply_presence_mode(_presence.current_mode())
	_action_banner.visible = false
	_approval_banner.visible = false
	_discovery_panel.visible = false
	_selected_target_row.visible = false
	_approval_selected_target.visible = false
	_compact_panel.visible = false

	# Linux Window Behavior Spike (Phase 3b). No-op unless the user opts
	# in via `SMOLIT_WINDOW_PROBE=1`. Lives outside the presence/avatar
	# state machines by design; it only reports and (opt-in) probes the
	# host window, never changes scene logic.
	_WindowBehaviorRef.run_probe_if_enabled()

	# Overlay MVP Phase B — opt-in transparent presence window. No-op
	# unless `SMOLIT_UI_OVERLAY=1` is set and the current session
	# advertises transparency as available/experimental. Honest fallback
	# to the normal window otherwise; no scene or presence change.
	var overlay_result: Dictionary = _WindowBehaviorRef.activate_overlay_if_requested(self)

	# Overlay click-through follow-up. Additional opt-in via
	# `SMOLIT_UI_CLICK_THROUGH=1`; only takes effect on top of an
	# already-active overlay, and only when interactive zones can be
	# derived from the current layout. Honest no-op in every other
	# case — reason goes to the log.
	var click_through_result: Dictionary = \
		_WindowBehaviorRef.activate_click_through_if_requested(self, overlay_result)
	var controller_variant: Variant = click_through_result.get("controller", null)
	if controller_variant is RefCounted:
		_click_through_controller = controller_variant

	# X11-only Always-on-top Sonderpfad (SMOLIT_UI_ALWAYS_ON_TOP=1).
	# Unabhängig von Overlay und Click-through. Unter GNOME/Wayland,
	# unknown Session oder headless ein ehrlicher No-op — siehe
	# `docs/linux_always_on_top_decision.md`.
	var always_on_top_result: Dictionary = \
		_WindowBehaviorRef.activate_always_on_top_if_requested(self)

	# Opt-in diagnostic runtime report (SMOLIT_WINDOW_REPORT=1). Prints
	# a consolidated block on session/capability/overlay/click-through/
	# always-on-top status — diagnostic-only, no behaviour change. See
	# `docs/linux_overlay_verification_matrix.md` for usage.
	_WindowBehaviorRef.print_runtime_report_if_enabled(
		overlay_result, click_through_result, always_on_top_result
	)


func _set_connected(ok: bool) -> void:
	_status.text = "connected" if ok else "disconnected"
	_send_button.disabled = not ok
	_ping_button.disabled = not ok
	_compact_send_button.disabled = not ok
	_compact_voice_button.disabled = not ok


func _on_avatar_toggle_dock() -> void:
	# Der erste Click eines Doppelklicks hat den Compact-Panel bereits
	# geöffnet — beim Dock-Toggle soll das Quick-Popup nicht als Rest
	# stehen bleiben.
	_close_compact_input()
	_presence.toggle_base_mode()


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
	match mode:
		PresenceStateRef.Mode.DOCKED:
			_dock_panel.visible = false
		PresenceStateRef.Mode.EXPANDED:
			_dock_panel.visible = true
			# Expanded bringt bereits eine Volltext-Eingabe mit — das
			# kleine Compact Panel wird damit überflüssig und würde
			# nur doppelte UI erzeugen.
			_close_compact_input()
		PresenceStateRef.Mode.ACTION:
			# Während einer Action bleibt das zuletzt gewählte Base-Layout
			# sichtbar; wir heben nur den Banner hervor (siehe
			# _on_action_context_changed).
			pass
		PresenceStateRef.Mode.DISCONNECTED:
			_dock_panel.visible = true
			_close_compact_input()


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


# --- Compact Input UX ----------------------------------------------------

## Klick auf den Avatar öffnet / schließt das kleine Compact-Panel —
## aber nur im Docked-Modus. In Expanded existiert die volle Eingabe
## bereits; in Action / Disconnected soll die Schnellinteraktion nicht
## zusätzliche UI erzeugen.
func _on_avatar_clicked() -> void:
	if _presence.current_mode() != PresenceStateRef.Mode.DOCKED:
		return
	_toggle_compact_input()


func _toggle_compact_input() -> void:
	if _compact_input_open:
		_close_compact_input()
	else:
		_open_compact_input()


func _open_compact_input() -> void:
	if _compact_input_open:
		return
	_compact_input_open = true
	_compact_panel.visible = true
	_compact_hint.visible = false
	_compact_commands_hint.visible = false
	_compact_input.text = ""
	_compact_input.grab_focus()
	_reposition_compact_panel()


## Sitzt das Panel seitlich am Avatar: rechts, wenn der Avatar in der
## linken Bildschirmhälfte steht — sonst links. Vertikal wird die
## Panel-Mitte mit der Avatar-Mitte ausgerichtet und anschließend in den
## Viewport geklammert, damit das Panel nicht oben/unten abgeschnitten
## wird.
const _PANEL_GAP: float = 7.0


func _reposition_compact_panel() -> void:
	if not _compact_panel.visible:
		return
	# Layout-Pass erzwingen, damit size die tatsächlich benötigte Größe
	# widerspiegelt (sonst liegt size direkt nach dem Einblenden evtl.
	# noch auf dem initialen Offset des Scenes).
	_compact_panel.reset_size()
	var panel_size: Vector2 = _compact_panel.size
	if panel_size.x <= 0 or panel_size.y <= 0:
		panel_size = _compact_panel.get_combined_minimum_size()
	var viewport: Vector2 = get_viewport_rect().size
	var avatar_rect: Rect2 = Rect2(_avatar.position, _avatar.size)
	var avatar_center_x: float = avatar_rect.position.x + avatar_rect.size.x * 0.5

	var target_x: float
	if avatar_center_x < viewport.x * 0.5:
		target_x = avatar_rect.position.x + avatar_rect.size.x + _PANEL_GAP
	else:
		target_x = avatar_rect.position.x - panel_size.x - _PANEL_GAP

	var target_y: float = avatar_rect.position.y + avatar_rect.size.y * 0.5 - panel_size.y * 0.5

	var max_x: float = maxf(0.0, viewport.x - panel_size.x)
	var max_y: float = maxf(0.0, viewport.y - panel_size.y)
	_compact_panel.position = Vector2(
		clampf(target_x, 0.0, max_x),
		clampf(target_y, 0.0, max_y),
	)


func _on_avatar_moved(_pos: Vector2) -> void:
	_reposition_compact_panel()


func _close_compact_input() -> void:
	if not _compact_input_open:
		# Halte das Panel trotzdem konsistent versteckt, auch wenn der
		# Zustand bereits geschlossen war (z. B. initiales Setup).
		_compact_panel.visible = false
		return
	_compact_input_open = false
	_compact_panel.visible = false
	_compact_hint.visible = false
	_compact_commands_hint.visible = false


func _on_compact_close_pressed() -> void:
	_close_compact_input()


func _on_compact_send_pressed() -> void:
	var text := _compact_input.text.strip_edges()
	if text.is_empty():
		return
	IpcClient.submit_text(text)
	_append("[b]> %s[/b]" % text)
	_compact_input.text = ""
	# Panel bleibt bewusst offen, damit der Nutzer schnell nachreichen
	# kann — Schließen läuft über Close-Button, Escape oder Wechsel
	# in Expanded/Disconnected.
	_compact_input.grab_focus()


func _on_compact_text_submitted(_text: String) -> void:
	_on_compact_send_pressed()


func _on_compact_voice_pressed() -> void:
	if not IpcClient.is_connected_to_core():
		return
	IpcClient.voice_once()
	_append("[i]voice →[/i]")


func _on_compact_add_files_pressed() -> void:
	# Ehrlicher Platzhalter: der Button existiert, damit das Compact-UX
	# vollständig wirkt, aber das Backend für Dateianhänge ist in dieser
	# Phase nicht gelandet. Keine Pseudo-Dateiauswahl.
	_compact_hint.text = "Datei-Anhänge noch nicht implementiert."
	_compact_hint.visible = true
	_append("[color=gray]◦ add files: not implemented yet[/color]")


func _on_compact_commands_pressed() -> void:
	# Kleine, ehrliche Mini-Hilfe. Listet nur Flows, die es heute wirklich
	# gibt — keine zukünftigen Features vortäuschen.
	if _compact_commands_hint.visible:
		_compact_commands_hint.visible = false
		return
	_compact_commands_hint.text = _COMPACT_COMMANDS_TEXT
	_compact_commands_hint.visible = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not _compact_input_open:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_close_compact_input()
			accept_event()
