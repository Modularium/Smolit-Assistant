extends Control
## Avatar MVP controller.
##
## Subscribes to EventBus and maps core events onto a small state set
## (idle / thinking / talking / disconnected / error). Rendering stays
## inside this scene; no transport, no business logic, no ABrain.
##
## Core-driven: the UI does not decide when to leave `talking`; it uses
## a short deterministic timer as a stand-in until the protocol gains
## speaking_started / speaking_ended events (then this can be swapped
## without touching the rest of the UI).

const AvatarStateRef := preload("res://scripts/avatar/avatar_state.gd")

const TALK_HOLD_SECONDS: float = 1.8
const ERROR_HOLD_SECONDS: float = 1.2

const IDLE_COLOR: Color = Color(0.32, 0.55, 0.78)
const THINKING_COLOR: Color = Color(0.85, 0.70, 0.25)
const TALKING_COLOR: Color = Color(0.35, 0.78, 0.52)
const DISCONNECTED_COLOR: Color = Color(0.45, 0.45, 0.50)
const ERROR_COLOR: Color = Color(0.82, 0.32, 0.32)

@onready var _body: ColorRect = $VisualRoot/Body
@onready var _mouth: ColorRect = $VisualRoot/Face/Mouth
@onready var _thinking_indicator: ColorRect = $Effects/ThinkingIndicator
@onready var _state_label: Label = $VisualRoot/StateLabel
@onready var _debug_label: Label = $Debug/CurrentStateLabel

var _state: int = AvatarStateRef.State.DISCONNECTED
var _thinking_tween: Tween = null
var _talking_tween: Tween = null
var _hold_timer: Timer = null


func _ready() -> void:
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)

	EventBus.ipc_connected.connect(_on_connected)
	EventBus.ipc_disconnected.connect(_on_disconnected)
	EventBus.thinking_received.connect(_on_thinking)
	EventBus.response_received.connect(_on_response)
	EventBus.error_received.connect(_on_error)

	var initial: int = AvatarStateRef.State.IDLE if IpcClient.is_connected_to_core() \
		else AvatarStateRef.State.DISCONNECTED
	_set_state(initial)


func _set_state(new_state: int) -> void:
	if new_state == _state:
		_apply_state_visuals()
		return
	_state = new_state
	_apply_state_visuals()


func _apply_state_visuals() -> void:
	_stop_thinking_tween()
	_stop_talking_tween()
	_mouth.scale = Vector2.ONE
	_thinking_indicator.visible = false
	_thinking_indicator.modulate.a = 1.0

	var label := AvatarStateRef.name_of(_state)
	_state_label.text = label
	_debug_label.text = "state: %s" % label

	match _state:
		AvatarStateRef.State.IDLE:
			_body.color = IDLE_COLOR
		AvatarStateRef.State.THINKING:
			_body.color = THINKING_COLOR
			_thinking_indicator.visible = true
			_start_thinking_tween()
		AvatarStateRef.State.TALKING:
			_body.color = TALKING_COLOR
			_start_talking_tween()
		AvatarStateRef.State.DISCONNECTED:
			_body.color = DISCONNECTED_COLOR
		AvatarStateRef.State.ERROR:
			_body.color = ERROR_COLOR


func _start_thinking_tween() -> void:
	_thinking_tween = create_tween().set_loops()
	_thinking_tween.tween_property(_thinking_indicator, "modulate:a", 0.25, 0.45)
	_thinking_tween.tween_property(_thinking_indicator, "modulate:a", 1.0, 0.45)


func _stop_thinking_tween() -> void:
	if _thinking_tween and _thinking_tween.is_valid():
		_thinking_tween.kill()
	_thinking_tween = null


func _start_talking_tween() -> void:
	_talking_tween = create_tween().set_loops()
	_talking_tween.tween_property(_mouth, "scale", Vector2(1.0, 0.4), 0.18)
	_talking_tween.tween_property(_mouth, "scale", Vector2(1.0, 1.0), 0.18)


func _stop_talking_tween() -> void:
	if _talking_tween and _talking_tween.is_valid():
		_talking_tween.kill()
	_talking_tween = null


func _start_hold(seconds: float) -> void:
	_hold_timer.stop()
	_hold_timer.wait_time = seconds
	_hold_timer.start()


func _on_hold_timeout() -> void:
	if _state == AvatarStateRef.State.TALKING or _state == AvatarStateRef.State.ERROR:
		var next: int = AvatarStateRef.State.IDLE if IpcClient.is_connected_to_core() \
			else AvatarStateRef.State.DISCONNECTED
		_set_state(next)


func _on_connected() -> void:
	_hold_timer.stop()
	_set_state(AvatarStateRef.State.IDLE)


func _on_disconnected() -> void:
	_hold_timer.stop()
	_set_state(AvatarStateRef.State.DISCONNECTED)


func _on_thinking() -> void:
	_hold_timer.stop()
	_set_state(AvatarStateRef.State.THINKING)


func _on_response(_text: String) -> void:
	_set_state(AvatarStateRef.State.TALKING)
	_start_hold(TALK_HOLD_SECONDS)


func _on_error(_message: String) -> void:
	_set_state(AvatarStateRef.State.ERROR)
	_start_hold(ERROR_HOLD_SECONDS)
