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

var _current_approval_id: String = ""

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

	_approve_button.pressed.connect(_on_approve_pressed)
	_deny_button.pressed.connect(_on_deny_pressed)

	_presence.presence_changed.connect(_on_presence_changed)
	_presence.action_context_changed.connect(_on_action_context_changed)

	_set_connected(IpcClient.is_connected_to_core())
	_apply_presence_mode(_presence.current_mode())
	_action_banner.visible = false
	_approval_banner.visible = false


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
