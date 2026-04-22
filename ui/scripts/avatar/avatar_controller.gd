extends Control
## Avatar MVP controller.
##
## Subscribes to EventBus and maps core events onto a small state set
## (idle / thinking / talking / disconnected / error / acting). Rendering
## is a simple texture swap between two hand-drawn Smolit images plus
## light modulate/scale accents — no sprite sheets, no frame system.
##
## The avatar floats: the user can drag it anywhere inside the viewport,
## and the position is persisted between sessions via ConfigFile. A click
## (press + release without significant motion) emits `clicked` and is
## the UX hook for opening the side panel.
##
## Micro-Animation / Personality Layer v1
## --------------------------------------
## Expression lives on three deliberately orthogonal transform layers so
## hover, state-cycle pulses and rare personality cues never fight each
## other for the same property:
##
##   * Root `self.scale`  → hover pop (short tween on enter/leave).
##   * `_body.scale`      → state-cycle: idle breathing, thinking breath,
##                          acting pulse, talking pulse, error startle.
##                          Exactly one such tween is alive at a time —
##                          `_apply_state_visuals` swaps them on state
##                          changes.
##   * `_body.rotation`   → occasional "curious wiggle" while idle. Fires
##                          rarely via a one-shot timer that re-arms with
##                          a randomized interval.
##   * `_body.modulate:a` → thinking alpha breathing (kept from MVP).
##
## Idle stays cheap: only one scale tween + a long re-arming timer.
## State transitions always reset `_body.scale`, `_body.rotation` and
## kill prior tweens, so leaving a state never leaves dangling animation
## residue.

const AvatarStateRef := preload("res://scripts/avatar/avatar_state.gd")

signal clicked
signal toggle_dock
signal moved(position: Vector2)

const TALK_HOLD_SECONDS: float = 1.8
const ERROR_HOLD_SECONDS: float = 1.2
const ACTING_SUCCESS_HOLD_SECONDS: float = 0.9

const IDLE_TEXTURE: Texture2D = preload("res://assets/avatar/smolit_idle.png")
const ACTIVE_TEXTURE: Texture2D = preload("res://assets/avatar/smolit_active.png")

const NORMAL_MODULATE: Color = Color(1, 1, 1, 1)
const THINKING_MODULATE: Color = Color(0.85, 0.85, 0.95, 0.85)
const DISCONNECTED_MODULATE: Color = Color(0.70, 0.70, 0.75, 0.75)
const ERROR_MODULATE: Color = Color(1.0, 0.55, 0.55, 1.0)

const HOVER_SCALE: Vector2 = Vector2(1.06, 1.06)
const BASE_SCALE: Vector2 = Vector2.ONE

# --- Micro-animation timings ---------------------------------------------
# Idle breathing: very subtle scale pulse on the body. Half a cycle is a
# full inhale *or* exhale, so the full breath period is ~2 * half.
const IDLE_BREATH_AMPLITUDE: Vector2 = Vector2(1.015, 1.015)
const IDLE_BREATH_HALF_SECONDS: float = 1.6  # ≈3.2 s full cycle

# Thinking breath: tighter and slower — "holding focus", not "relaxed".
const THINKING_BREATH_AMPLITUDE: Vector2 = Vector2(1.008, 1.008)
const THINKING_BREATH_HALF_SECONDS: float = 2.1

# Acting pulse: slightly more purposeful than idle, still very small.
const ACTING_PULSE_AMPLITUDE: Vector2 = Vector2(1.02, 1.02)
const ACTING_PULSE_HALF_SECONDS: float = 0.9

# Talking pulse: rhythmic, noticeable but not comic.
const TALKING_PULSE_AMPLITUDE: Vector2 = Vector2(1.04, 1.04)
const TALKING_PULSE_HALF_SECONDS: float = 0.22

# Error startle: single non-looping bump that returns to rest.
const ERROR_STARTLE_DOWN: Vector2 = Vector2(0.94, 0.94)
const ERROR_STARTLE_UP: Vector2 = Vector2(1.03, 1.03)
const ERROR_STARTLE_DOWN_SECONDS: float = 0.09
const ERROR_STARTLE_UP_SECONDS: float = 0.12
const ERROR_STARTLE_SETTLE_SECONDS: float = 0.18

# Curious wiggle: a rare, short rotation nudge while idle.
const WIGGLE_INTERVAL_MIN_SECONDS: float = 14.0
const WIGGLE_INTERVAL_MAX_SECONDS: float = 28.0
const WIGGLE_ANGLE_RAD: float = 0.035  # ≈ 2°

const HOVER_TWEEN_SECONDS: float = 0.12

const DRAG_THRESHOLD: float = 4.0
const CONFIG_PATH: String = "user://smolit_ui.cfg"
const CONFIG_SECTION: String = "avatar"

const ACTING_TINT_BY_TARGET: Dictionary = {
	"application": Color(1.05, 1.0, 1.1, 1.0),
	"window": Color(0.95, 1.0, 1.1, 1.0),
	"ui_element": Color(1.1, 1.0, 1.05, 1.0),
	"region": Color(1.0, 0.95, 1.1, 1.0),
	"unknown": Color(1.0, 1.0, 1.05, 1.0),
}

@onready var _body: TextureRect = $Body

var _state: int = AvatarStateRef.State.DISCONNECTED
var _thinking_tween: Tween = null       # _body.modulate:a loop (keeps MVP feel)
var _body_scale_tween: Tween = null     # state-cycle pulse on _body.scale
var _startle_tween: Tween = null        # one-shot error startle on _body.scale
var _hover_tween: Tween = null          # hover pop on self.scale
var _wiggle_tween: Tween = null         # curious wiggle on _body.rotation
var _wiggle_timer: Timer = null
var _hold_timer: Timer = null
var _last_target_kind: String = ""
var _hovered: bool = false

var _pressing: bool = false
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _press_global: Vector2 = Vector2.ZERO


func _ready() -> void:
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)

	_wiggle_timer = Timer.new()
	_wiggle_timer.one_shot = true
	_wiggle_timer.timeout.connect(_on_wiggle_timeout)
	add_child(_wiggle_timer)

	EventBus.ipc_connected.connect(_on_connected)
	EventBus.ipc_disconnected.connect(_on_disconnected)
	EventBus.thinking_received.connect(_on_thinking)
	EventBus.response_received.connect(_on_response)
	EventBus.error_received.connect(_on_error)

	EventBus.action_planned_received.connect(_on_action_planned)
	EventBus.action_started_received.connect(_on_action_started)
	EventBus.action_step_received.connect(_on_action_step)
	EventBus.action_completed_received.connect(_on_action_completed)
	EventBus.action_failed_received.connect(_on_action_failed)
	EventBus.action_cancelled_received.connect(_on_action_cancelled)

	var initial: int = AvatarStateRef.State.IDLE if IpcClient.is_connected_to_core() \
		else AvatarStateRef.State.DISCONNECTED
	_set_state(initial)

	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_restore_saved_position.call_deferred()


func _restore_saved_position() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_place_default_position()
		return
	var saved_x: float = cfg.get_value(CONFIG_SECTION, "x", -1.0)
	var saved_y: float = cfg.get_value(CONFIG_SECTION, "y", -1.0)
	if saved_x < 0 or saved_y < 0:
		_place_default_position()
		return
	position = _clamp_to_viewport(Vector2(saved_x, saved_y))
	moved.emit(position)


func _place_default_position() -> void:
	var viewport := get_viewport_rect().size
	position = Vector2(viewport.x - size.x - 16.0, viewport.y - size.y - 16.0)
	moved.emit(position)


func _save_position() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECTION, "x", position.x)
	cfg.set_value(CONFIG_SECTION, "y", position.y)
	cfg.save(CONFIG_PATH)


func _clamp_to_viewport(candidate: Vector2) -> Vector2:
	var viewport := get_viewport_rect().size
	var max_x := maxf(0.0, viewport.x - size.x)
	var max_y := maxf(0.0, viewport.y - size.y)
	return Vector2(clampf(candidate.x, 0.0, max_x), clampf(candidate.y, 0.0, max_y))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		# Double-click takes precedence over the normal press/release flow:
		# Godot delivers a dedicated event with `double_click = true` on
		# the second press, so we swallow it without starting a drag and
		# route it to the dock toggle. The preceding single-click has
		# already fired — main.gd is responsible for reconciling (i.e.
		# re-closing the compact panel that a single-click just opened).
		if mb.pressed and mb.double_click:
			_pressing = false
			_dragging = false
			toggle_dock.emit()
			accept_event()
			return
		if mb.pressed:
			_pressing = true
			_dragging = false
			_press_global = mb.global_position
			_drag_offset = mb.global_position - global_position
			accept_event()
		else:
			# Release without a matching tracked press (e.g. the press was
			# swallowed by double-click handling) — nothing to do here.
			if not _pressing:
				accept_event()
				return
			var was_drag := _dragging
			_pressing = false
			_dragging = false
			if was_drag:
				_save_position()
			else:
				clicked.emit()
			accept_event()
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if not _dragging:
			if mm.global_position.distance_to(_press_global) >= DRAG_THRESHOLD:
				_dragging = true
		if _dragging:
			var target := mm.global_position - _drag_offset
			position = _clamp_to_viewport(target)
			moved.emit(position)
			accept_event()


func _on_mouse_entered() -> void:
	_hovered = true
	_apply_hover_visual()


func _on_mouse_exited() -> void:
	_hovered = false
	_apply_hover_visual()


func _apply_hover_visual() -> void:
	# Kill the prior hover tween so rapid enter/leave doesn't accumulate
	# overlapping scale animations on the root.
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	var target_scale := HOVER_SCALE if _hovered else BASE_SCALE
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", target_scale, HOVER_TWEEN_SECONDS)


func _set_state(new_state: int) -> void:
	if new_state == _state:
		_apply_state_visuals()
		return
	_state = new_state
	_apply_state_visuals()


func _apply_state_visuals() -> void:
	# Every state transition starts from a clean transform slate: any
	# cycling or transient tween on _body is killed, scale/rotation reset.
	# Thinking alpha tween is handled separately because it targets
	# modulate:a, not scale.
	_stop_thinking_tween()
	_stop_body_scale_tween()
	_stop_startle_tween()
	_stop_wiggle()
	_body.scale = Vector2.ONE
	_body.rotation = 0.0

	match _state:
		AvatarStateRef.State.IDLE:
			_body.texture = IDLE_TEXTURE
			_body.modulate = NORMAL_MODULATE
			_start_breath_tween(IDLE_BREATH_AMPLITUDE, IDLE_BREATH_HALF_SECONDS)
			_arm_wiggle_timer()
		AvatarStateRef.State.THINKING:
			_body.texture = IDLE_TEXTURE
			_body.modulate = THINKING_MODULATE
			_start_thinking_tween()
			_start_breath_tween(THINKING_BREATH_AMPLITUDE, THINKING_BREATH_HALF_SECONDS)
		AvatarStateRef.State.TALKING:
			_body.texture = ACTIVE_TEXTURE
			_body.modulate = NORMAL_MODULATE
			_start_breath_tween(TALKING_PULSE_AMPLITUDE, TALKING_PULSE_HALF_SECONDS)
		AvatarStateRef.State.DISCONNECTED:
			# Sleeping: matte tint, no animation — low power, low noise.
			_body.texture = IDLE_TEXTURE
			_body.modulate = DISCONNECTED_MODULATE
		AvatarStateRef.State.ERROR:
			_body.modulate = ERROR_MODULATE
			_start_error_startle()
		AvatarStateRef.State.ACTING:
			_body.texture = ACTIVE_TEXTURE
			_body.modulate = ACTING_TINT_BY_TARGET.get(_last_target_kind, NORMAL_MODULATE)
			_start_breath_tween(ACTING_PULSE_AMPLITUDE, ACTING_PULSE_HALF_SECONDS)


func _start_thinking_tween() -> void:
	_thinking_tween = create_tween().set_loops()
	_thinking_tween.tween_property(_body, "modulate:a", 0.55, 0.55)
	_thinking_tween.tween_property(_body, "modulate:a", THINKING_MODULATE.a, 0.55)


func _stop_thinking_tween() -> void:
	if _thinking_tween and _thinking_tween.is_valid():
		_thinking_tween.kill()
	_thinking_tween = null


## Shared looping scale animator for idle / thinking / acting / talking.
## All these states want a single, unambiguous scale oscillation on
## `_body.scale`; only amplitude and period change. Keeping it in one
## helper means we never accidentally run two competing scale loops.
func _start_breath_tween(amplitude: Vector2, half_seconds: float) -> void:
	_body_scale_tween = create_tween().set_loops()
	_body_scale_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_body_scale_tween.tween_property(_body, "scale", amplitude, half_seconds)
	_body_scale_tween.tween_property(_body, "scale", Vector2.ONE, half_seconds)


func _stop_body_scale_tween() -> void:
	if _body_scale_tween and _body_scale_tween.is_valid():
		_body_scale_tween.kill()
	_body_scale_tween = null


func _start_error_startle() -> void:
	# Short, non-looping startle: small flinch down, small rebound, settle.
	_startle_tween = create_tween()
	_startle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_startle_tween.tween_property(_body, "scale", ERROR_STARTLE_DOWN, ERROR_STARTLE_DOWN_SECONDS)
	_startle_tween.tween_property(_body, "scale", ERROR_STARTLE_UP, ERROR_STARTLE_UP_SECONDS)
	_startle_tween.tween_property(_body, "scale", Vector2.ONE, ERROR_STARTLE_SETTLE_SECONDS)


func _stop_startle_tween() -> void:
	if _startle_tween and _startle_tween.is_valid():
		_startle_tween.kill()
	_startle_tween = null


# --- Curious wiggle (idle-only personality cue) --------------------------

func _arm_wiggle_timer() -> void:
	# Re-arm with a fresh random delay so cues don't feel mechanical.
	_wiggle_timer.stop()
	_wiggle_timer.wait_time = randf_range(
		WIGGLE_INTERVAL_MIN_SECONDS, WIGGLE_INTERVAL_MAX_SECONDS
	)
	_wiggle_timer.start()


func _stop_wiggle() -> void:
	if _wiggle_timer:
		_wiggle_timer.stop()
	if _wiggle_tween and _wiggle_tween.is_valid():
		_wiggle_tween.kill()
	_wiggle_tween = null


func _on_wiggle_timeout() -> void:
	# Only play the cue if we are still idle and no drag/startle is
	# currently owning the transform.
	if _state != AvatarStateRef.State.IDLE or _dragging:
		_arm_wiggle_timer()
		return
	_play_wiggle()
	_arm_wiggle_timer()


func _play_wiggle() -> void:
	if _wiggle_tween and _wiggle_tween.is_valid():
		_wiggle_tween.kill()
	_wiggle_tween = create_tween()
	_wiggle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wiggle_tween.tween_property(_body, "rotation", WIGGLE_ANGLE_RAD, 0.18)
	_wiggle_tween.tween_property(_body, "rotation", -WIGGLE_ANGLE_RAD * 0.5, 0.22)
	_wiggle_tween.tween_property(_body, "rotation", 0.0, 0.22)


func _start_hold(seconds: float) -> void:
	_hold_timer.stop()
	_hold_timer.wait_time = seconds
	_hold_timer.start()


func _on_hold_timeout() -> void:
	if _state == AvatarStateRef.State.TALKING \
			or _state == AvatarStateRef.State.ERROR \
			or _state == AvatarStateRef.State.ACTING:
		var next: int = AvatarStateRef.State.IDLE if IpcClient.is_connected_to_core() \
			else AvatarStateRef.State.DISCONNECTED
		_set_state(next)


func _on_connected() -> void:
	_hold_timer.stop()
	_set_state(AvatarStateRef.State.IDLE)


func _on_disconnected() -> void:
	_hold_timer.stop()
	_last_target_kind = ""
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


func _on_action_planned(payload: Dictionary) -> void:
	var target: Variant = payload.get("target", null)
	if typeof(target) == TYPE_DICTIONARY:
		_last_target_kind = str(target.get("type", ""))
	else:
		_last_target_kind = ""


func _on_action_started(_payload: Dictionary) -> void:
	if _state == AvatarStateRef.State.TALKING or _state == AvatarStateRef.State.THINKING:
		return
	_hold_timer.stop()
	_set_state(AvatarStateRef.State.ACTING)


func _on_action_step(_payload: Dictionary) -> void:
	if _state == AvatarStateRef.State.TALKING or _state == AvatarStateRef.State.THINKING:
		return
	_hold_timer.stop()
	_set_state(AvatarStateRef.State.ACTING)


func _on_action_completed(_payload: Dictionary) -> void:
	_last_target_kind = ""
	if _state == AvatarStateRef.State.TALKING:
		return
	_set_state(AvatarStateRef.State.TALKING)
	_start_hold(ACTING_SUCCESS_HOLD_SECONDS)


func _on_action_failed(_payload: Dictionary) -> void:
	_last_target_kind = ""
	_set_state(AvatarStateRef.State.ERROR)
	_start_hold(ERROR_HOLD_SECONDS)


func _on_action_cancelled(_payload: Dictionary) -> void:
	_last_target_kind = ""
	if _state != AvatarStateRef.State.ACTING:
		return
	var next: int = AvatarStateRef.State.IDLE if IpcClient.is_connected_to_core() \
		else AvatarStateRef.State.DISCONNECTED
	_set_state(next)
