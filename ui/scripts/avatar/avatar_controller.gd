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
const AvatarAppearanceRef := preload("res://scripts/avatar/avatar_appearance.gd")
const AvatarPreferencesRef := preload("res://scripts/avatar/avatar_preferences.gd")
const AvatarIdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const AvatarTemplateCapsRef := preload("res://scripts/avatar/avatar_template_capabilities.gd")

signal clicked
signal toggle_dock
signal moved(position: Vector2)

## Optionale Env-Variablen für Avatar Appearance Phase A/B. Sie haben
## die höchste Priorität — wer sie setzt, übersteuert gespeicherte
## Preferences und harten Default. Unbekannte / leere Werte werden
## behandelt, als wären sie nicht gesetzt (der nächste Schritt in der
## Kette greift: Preferences, dann Default).
const ENV_APPEARANCE_THEME: String = "SMOLIT_AVATAR_THEME"
const ENV_APPEARANCE_PROFILE: String = "SMOLIT_AVATAR_PROFILE"
const ENV_APPEARANCE_INTENSITY: String = "SMOLIT_AVATAR_INTENSITY"
## Phase B: kuratierte Identity-Auswahl. Ohne Env bleibt Smolit
## Default (oder der gespeicherte Preference-Wert, falls vorhanden).
const ENV_APPEARANCE_IDENTITY: String = "SMOLIT_AVATAR_IDENTITY"

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
## Prozeduraler Zweitrenderer für kuratierte Phase-B-Identities
## (Robot-Head, Orb). Bleibt für Smolit unsichtbar und tut gar nichts.
## Wenn aktiv, spiegelt der Controller jeden Frame `_body.modulate`,
## `_body.scale` und `_body.rotation` auf diesen Node — so bleibt die
## bestehende Tween-Logik byte-identisch zu Phase A.
@onready var _identity_shape: Control = $IdentityShape
## Rim Accent — dünner prozeduraler State-Ring an der Silhouette.
## Identitäts-neutral (Smolit wie kuratierte Alternativen teilen den
## Ring); keine Tween-Animation, keine Eingabe. Der Controller stupst
## ihn in jedem `_apply_state_visuals`-Durchlauf per `set_state` an.
@onready var _rim_accent: Control = $RimAccent

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

## Appearance-Konfiguration (Phase A + Phase-B-Identity-Spike). Das
## Dict ist ein reines UI-Render-Modul — Identity, Theme, Behavior
## Profile und Overrides. Wird in `_ready()` aus Env/Preferences
## gebaut und kann per `set_appearance()` zur Laufzeit ersetzt werden.
## Identitätsgarantie gilt weiterhin: Default-Smolit + DEFAULT +
## CALM + Unity-Overrides reproduziert das vor-PR-Verhalten.
var _appearance: Dictionary = AvatarAppearanceRef.new_appearance()

## Aufgelöste Identity-ID aus `_appearance["identity"]`. Wird im
## `_ready()` einmalig berechnet und nach jedem `set_appearance`
## aktualisiert. Bestimmt, welcher Visual-Pfad aktiv ist
## (Smolit-TextureRect vs. prozeduraler Identity-Shape).
var _identity_id: int = AvatarIdentityRef.DEFAULT


func _ready() -> void:
	_load_appearance()
	_apply_identity_visual_config()
	# Root-Scale einmalig auf den Appearance-Scale setzen. Hover-Pops
	# und State-Pulse bauen darauf auf (siehe `_apply_hover_visual`
	# und `_start_breath_tween`).
	scale = AvatarAppearanceRef.resolved_scale(_appearance, BASE_SCALE)

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
	var base := HOVER_SCALE if _hovered else BASE_SCALE
	# Appearance-scale-Override skaliert beide Referenz-Scales
	# uniform, damit HOVER-Pop als relativer Effekt erhalten bleibt.
	var target_scale := AvatarAppearanceRef.resolved_scale(_appearance, base)
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

	# Template-Capability-Contract: bevor wir den Zustand rendern, fragen
	# wir die Capability-Schicht, welchen tatsächlich renderbaren State
	# die aktive Identity trägt. Für Smolit ist das immer 1:1 der
	# Eingangs-State; `orb` mappt `TALKING` → `ACTING`, weil die Figur
	# keinen Mund hat. Siehe `avatar_template_capabilities.gd::resolve_state`.
	var effective_state: int = AvatarTemplateCapsRef.resolve_state(_identity_id, _state)

	# Rim-Accent zeigt die Silhouetten-Kante in State-Farbe — unabhängig
	# davon, ob Body oder IdentityShape aktiv rendert. Wir setzen den
	# *tatsächlich* gerenderten State (nach Template-Fallback), damit
	# z. B. `orb.TALKING → ACTING` den passenden Acting-Rim zeigt statt
	# eines Talking-Rims, der mit dem sichtbaren Ausdruck nicht
	# übereinstimmen würde.
	if _rim_accent != null and _rim_accent.has_method("set_state"):
		_rim_accent.call("set_state", effective_state)

	match effective_state:
		AvatarStateRef.State.IDLE:
			_body.texture = IDLE_TEXTURE
			_body.modulate = _appearance_tint(NORMAL_MODULATE)
			_start_breath_tween(IDLE_BREATH_AMPLITUDE, IDLE_BREATH_HALF_SECONDS)
			_arm_wiggle_timer()
		AvatarStateRef.State.THINKING:
			_body.texture = IDLE_TEXTURE
			_body.modulate = _appearance_tint(THINKING_MODULATE)
			_start_thinking_tween()
			_start_breath_tween(THINKING_BREATH_AMPLITUDE, THINKING_BREATH_HALF_SECONDS)
		AvatarStateRef.State.TALKING:
			_body.texture = ACTIVE_TEXTURE
			_body.modulate = _appearance_tint(NORMAL_MODULATE)
			_start_breath_tween(TALKING_PULSE_AMPLITUDE, TALKING_PULSE_HALF_SECONDS)
		AvatarStateRef.State.DISCONNECTED:
			# Sleeping: matte tint, no animation — low power, low noise.
			_body.texture = IDLE_TEXTURE
			_body.modulate = _appearance_tint(DISCONNECTED_MODULATE)
		AvatarStateRef.State.ERROR:
			_body.modulate = _appearance_tint(ERROR_MODULATE)
			_start_error_startle()
		AvatarStateRef.State.ACTING:
			_body.texture = ACTIVE_TEXTURE
			var acting_base: Color = ACTING_TINT_BY_TARGET.get(_last_target_kind, NORMAL_MODULATE)
			_body.modulate = _appearance_tint(acting_base)
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
## Amplitude und Periode werden durch die Appearance (Profile +
## Intensity-Override) moduliert — CALM + Unity-Overrides lässt das
## Original-Timing unverändert (Identitätsgarantie).
##
## Phase-B-Hardening: die Template-Capability-Schicht skaliert die
## Amplitude zusätzlich. `state_pulse = NONE` verzichtet komplett auf
## den Tween (Body bleibt ruhig auf `Vector2.ONE`), `REDUCED` halbiert
## das Delta zur Ruhelage. Für Smolit/Referenz ist der Pfad unverändert.
func _start_breath_tween(amplitude: Vector2, half_seconds: float) -> void:
	var pulse_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_STATE_PULSE,
	)
	if pulse_mult <= 0.0:
		# Template deklariert `state_pulse = NONE` — Body bleibt still.
		# Identity-Shape wird weiterhin durch das _process-Mirror von
		# `_body` gespiegelt und zeigt damit ebenfalls keine Bewegung.
		_body.scale = Vector2.ONE
		return
	var profile_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_BEHAVIOR_PROFILE,
	)
	var resolved_amp: Vector2 = _apply_profile_vector(
		AvatarAppearanceRef.resolved_amplitude(_appearance, amplitude),
		amplitude,
		profile_mult,
	)
	var resolved_half: float = _apply_profile_scalar(
		AvatarAppearanceRef.resolved_half_seconds(_appearance, half_seconds),
		half_seconds,
		profile_mult,
	)
	var scaled_amp: Vector2 = _scale_around_one(resolved_amp, pulse_mult)
	_body_scale_tween = create_tween().set_loops()
	_body_scale_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_body_scale_tween.tween_property(_body, "scale", scaled_amp, resolved_half)
	_body_scale_tween.tween_property(_body, "scale", Vector2.ONE, resolved_half)


func _stop_body_scale_tween() -> void:
	if _body_scale_tween and _body_scale_tween.is_valid():
		_body_scale_tween.kill()
	_body_scale_tween = null


func _start_error_startle() -> void:
	# Short, non-looping startle: small flinch down, small rebound, settle.
	# Phase-B-Hardening: `error_startle = NONE` unterdrückt den Tween
	# komplett (nur der rote Tint bleibt); `REDUCED` halbiert die
	# Auslenkungen rund um die Ruhelage `Vector2.ONE`.
	var startle_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_ERROR_STARTLE,
	)
	if startle_mult <= 0.0:
		return
	_startle_tween = create_tween()
	_startle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_startle_tween.tween_property(_body, "scale",
		_scale_around_one(ERROR_STARTLE_DOWN, startle_mult), ERROR_STARTLE_DOWN_SECONDS)
	_startle_tween.tween_property(_body, "scale",
		_scale_around_one(ERROR_STARTLE_UP, startle_mult), ERROR_STARTLE_UP_SECONDS)
	_startle_tween.tween_property(_body, "scale",
		Vector2.ONE, ERROR_STARTLE_SETTLE_SECONDS)


func _stop_startle_tween() -> void:
	if _startle_tween and _startle_tween.is_valid():
		_startle_tween.kill()
	_startle_tween = null


# --- Curious wiggle (idle-only personality cue) --------------------------

func _arm_wiggle_timer() -> void:
	# Re-arm with a fresh random delay so cues don't feel mechanical.
	# Die Bandbreite wird durch das Behavior-Profile moduliert (LIVELY
	# häufiger, RESERVED seltener). Das Untergrenzen-Clamp in
	# `resolved_wiggle_interval` verhindert hektische Cues.
	#
	# Phase-B-Hardening: deklariert ein Template `wiggle = NONE`
	# (z. B. der abstrakte `orb`), wird der Timer gar nicht erst
	# gestartet — kein Tick, kein versehentlicher Cue. `REDUCED` senkt
	# nur den Winkel in `_play_wiggle`, nicht das Intervall (das Timing
	# liefert bereits das Behavior-Profile).
	_wiggle_timer.stop()
	var wiggle_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_WIGGLE,
	)
	if wiggle_mult <= 0.0:
		return
	var profile_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_BEHAVIOR_PROFILE,
	)
	var min_s: float = _apply_profile_scalar(
		AvatarAppearanceRef.resolved_wiggle_interval(_appearance, WIGGLE_INTERVAL_MIN_SECONDS),
		WIGGLE_INTERVAL_MIN_SECONDS,
		profile_mult,
	)
	var max_s: float = _apply_profile_scalar(
		AvatarAppearanceRef.resolved_wiggle_interval(_appearance, WIGGLE_INTERVAL_MAX_SECONDS),
		WIGGLE_INTERVAL_MAX_SECONDS,
		profile_mult,
	)
	_wiggle_timer.wait_time = randf_range(min_s, max_s)
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
	# Capability-Multiplier skaliert den Ausschlag (`FULL` = 1.0, `REDUCED`
	# = 0.5, `NONE` wurde bereits in `_arm_wiggle_timer` gefiltert).
	var angle_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_WIGGLE,
	)
	var angle: float = WIGGLE_ANGLE_RAD * angle_mult
	_wiggle_tween = create_tween()
	_wiggle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wiggle_tween.tween_property(_body, "rotation", angle, 0.18)
	_wiggle_tween.tween_property(_body, "rotation", -angle * 0.5, 0.22)
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


# --- Template-Capability-Helfer -----------------------------------------


## Skaliert einen Puls-/Startle-Zielwert (Vector2) um den Ruhepunkt
## `Vector2.ONE` herum. Beispiel: `_scale_around_one(Vector2(1.04,
## 1.04), 0.5)` ergibt `Vector2(1.02, 1.02)`. Damit bleibt die Richtung
## der Animation erhalten, nur das Delta schrumpft. Multiplier ≥ 1.0
## heißt „unverändert oder stärker"; ≤ 0.0 heißt „keine Bewegung"
## (wird in den Call-Sites ohnehin als Early-Return behandelt).
func _scale_around_one(value: Vector2, multiplier: float) -> Vector2:
	return Vector2.ONE + (value - Vector2.ONE) * multiplier


## Lerpt einen Profile-resolvten Vector2 zwischen der Basis (kein
## Profil-Effekt) und dem vollen Profil-Ergebnis. Multiplier == 1.0 →
## full profile, 0.5 → halb, 0.0 → Basis. Für `behavior_profile`-
## Downgrades in kuratierten Templates.
func _apply_profile_vector(resolved: Vector2, base: Vector2, multiplier: float) -> Vector2:
	if multiplier >= 0.999:
		return resolved
	return base.lerp(resolved, clampf(multiplier, 0.0, 1.0))


## Wie `_apply_profile_vector`, aber für Tempo-/Intervall-Skalare.
func _apply_profile_scalar(resolved: float, base: float, multiplier: float) -> float:
	if multiplier >= 0.999:
		return resolved
	return lerpf(base, resolved, clampf(multiplier, 0.0, 1.0))


# --- Appearance (Phase A) ------------------------------------------------


## Dünner Wrapper um `AvatarAppearanceRef.resolved_tint`. Vereinfacht
## die Call-Sites in `_apply_state_visuals` und bündelt den Default-
## Fallback (sicherheitshalber).
##
## Phase-B-Hardening: die Template-Capability-Schicht kann den Theme-
## Effekt pro Identity abschwächen. `theme_tint = FULL` entspricht
## dem unveränderten Phase-A-Verhalten (Themes wirken 1:1). `REDUCED`
## lerpt die Theme-Farbe 50 % zurück zur identitätsneutralen Basis,
## `NONE` ignoriert den Theme-Beitrag komplett und lässt nur den
## Override-Tint wirken. Aktuelle Templates deklarieren alle `FULL` —
## die Schicht ist als kontrollierter Fallback-Pfad vorhanden, falls
## ein zukünftiges Template den Theme-Effekt nicht tragen kann.
func _appearance_tint(base_color: Color) -> Color:
	var full_tint: Color = AvatarAppearanceRef.resolved_tint(_appearance, base_color)
	var tint_mult: float = AvatarTemplateCapsRef.multiplier(
		_identity_id, AvatarTemplateCapsRef.EXPR_THEME_TINT,
	)
	if tint_mult >= 0.999:
		return full_tint
	# Den Theme-Beitrag lerpen wir in Richtung „nur Override-Tint auf
	# Basis angewandt" — so bleibt ein identitätsneutraler Fallback
	# erhalten, ohne den Override-Tint selbst zu beschädigen.
	var neutral_identity := AvatarAppearanceRef.new_appearance()
	var overrides: Dictionary = _appearance.get("overrides", {})
	neutral_identity["overrides"]["primary_tint"] = overrides.get(
		"primary_tint", Color(1, 1, 1, 1),
	)
	var neutral_tint: Color = AvatarAppearanceRef.resolved_tint(neutral_identity, base_color)
	return neutral_tint.lerp(full_tint, tint_mult)


## Persistiert Theme / Profile / Intensity des aktuellen Appearance-
## Dicts in `user://smolit_ui.cfg` (Sektion `[avatar_appearance]`).
## Dünner Wrapper um den Preferences-Helper — so kann die kleine Dev-
## Steuerung persistieren, ohne selbst eine zweite Wahrheit über den
## Pfad oder die Sanitisierungsregeln zu halten. Gibt den
## `ConfigFile.save`-Statuscode zurück (OK bei Erfolg).
func save_current_preferences() -> int:
	var overrides: Dictionary = _appearance.get("overrides", {})
	return AvatarPreferencesRef.save_preferences(
		int(_appearance.get("theme", AvatarAppearanceRef.DEFAULT_THEME)),
		int(_appearance.get("profile", AvatarAppearanceRef.DEFAULT_PROFILE)),
		float(overrides.get("intensity", 1.0)),
		_identity_id,
	)


## Liefert eine flache Kopie des aktuellen Appearance-Dicts. Primär
## für Dev-/Preview-Steuerungen gedacht (siehe
## `ui/scripts/dev_controls/`) — der Rückgabewert ist eine Kopie,
## damit Konsumenten den State nicht versehentlich mutieren.
func get_appearance() -> Dictionary:
	# Dictionary.duplicate(true) liefert eine tiefe Kopie inkl.
	# verschachteltem `overrides`-Dict. Für Color-Werte ist das
	# unkritisch (Color ist value-type in GDScript).
	return _appearance.duplicate(true)


## Dev-/Preview-Hook für die kleine MVP-Steuerung. Ersetzt die
## aktuelle Appearance zur Laufzeit, aktualisiert Root-Scale und
## startet die State-Visuals neu, damit Theme-Tints und Profile-
## Animationen sofort sichtbar werden. Kein Speichern, keine
## Persistenz — die Änderung gilt nur für die laufende Session.
##
## Phase B erlaubt explizit einen Identity-Wechsel innerhalb der
## kuratierten Liste (Smolit / Robot-Head / Orb). Unbekannte
## `identity`-Einträge fallen still auf Smolit zurück — damit eine
## kaputte Caller-Konfiguration die Figur nicht unsichtbar machen
## kann.
##
## Nicht-Ziele:
##   * Keine Core-/IPC-Kommunikation.
##   * Keine User-supplied Identities — nur Einträge aus
##     `avatar_identity.gd` sind gültig.
##   * Keine Auswirkung auf die Avatar-State-Maschine, auf Events,
##     auf Presence oder auf Approval/Action-Banner.
func set_appearance(new_appearance: Dictionary) -> void:
	if new_appearance.is_empty():
		return
	# Identity durch den kuratierten Parser schicken: unbekannte oder
	# fehlende Werte werden sauber auf Smolit geklemmt.
	var requested: String = String(new_appearance.get("identity", "smolit_salamander"))
	var resolved_id: int = AvatarIdentityRef.identity_from_string(requested)
	new_appearance["identity"] = AvatarIdentityRef.identity_name(resolved_id)
	_appearance = new_appearance
	_identity_id = resolved_id
	_apply_identity_visual_config()
	# Root-Scale sofort an den Override anpassen (Hover-Tween bleibt
	# relativer Puff auf dem neuen Ausgangspunkt).
	scale = AvatarAppearanceRef.resolved_scale(_appearance, BASE_SCALE)
	# State-Visuals neu applizieren, damit Theme-Tint und Profile-
	# Animationen sofort greifen, statt erst beim nächsten State-
	# Wechsel.
	_apply_state_visuals()


## Baut `_appearance` nach der Prioritätskette
##   Env > gespeicherte UI-Preferences > harter Default
## pro Feld (theme / profile / intensity) auf. Die Kette ist
## absichtlich feldweise, nicht blockweise: wer nur `SMOLIT_AVATAR_THEME`
## setzt, bekommt das Env-Theme **plus** die gespeicherten Werte für
## Profile und Intensity (sofern vorhanden).
##
## Ohne Env und ohne gespeicherte Datei reproduziert diese Funktion
## *exakt* das vor-PR-Verhalten — DEFAULT-Theme + CALM-Profile +
## Unity-Overrides, kein Log-Output, byte-kompatibel zu den bisherigen
## Harness-Cases.
func _load_appearance() -> void:
	var theme_env := OS.get_environment(ENV_APPEARANCE_THEME).strip_edges()
	var profile_env := OS.get_environment(ENV_APPEARANCE_PROFILE).strip_edges()
	var intensity_env := OS.get_environment(ENV_APPEARANCE_INTENSITY).strip_edges()
	var identity_env := OS.get_environment(ENV_APPEARANCE_IDENTITY).strip_edges()

	var prefs: Dictionary = AvatarPreferencesRef.load_preferences()

	var theme: int = AvatarAppearanceRef.DEFAULT_THEME
	var theme_source := "default"
	if theme_env != "":
		theme = AvatarAppearanceRef.theme_from_string(theme_env)
		theme_source = "env"
	elif prefs.has(AvatarPreferencesRef.KEY_THEME):
		theme = int(prefs[AvatarPreferencesRef.KEY_THEME])
		theme_source = "prefs"

	var profile: int = AvatarAppearanceRef.DEFAULT_PROFILE
	var profile_source := "default"
	if profile_env != "":
		profile = AvatarAppearanceRef.profile_from_string(profile_env)
		profile_source = "env"
	elif prefs.has(AvatarPreferencesRef.KEY_PROFILE):
		profile = int(prefs[AvatarPreferencesRef.KEY_PROFILE])
		profile_source = "prefs"

	var intensity: float = 1.0
	var intensity_source := "default"
	if intensity_env != "":
		if intensity_env.is_valid_float():
			intensity = float(intensity_env)
			intensity_source = "env"
		else:
			push_warning("avatar_appearance: SMOLIT_AVATAR_INTENSITY is not a number — falling back.")
			if prefs.has(AvatarPreferencesRef.KEY_INTENSITY):
				intensity = float(prefs[AvatarPreferencesRef.KEY_INTENSITY])
				intensity_source = "prefs"
	elif prefs.has(AvatarPreferencesRef.KEY_INTENSITY):
		intensity = float(prefs[AvatarPreferencesRef.KEY_INTENSITY])
		intensity_source = "prefs"

	# Identity (Phase B) — gleiche Prioritätskette. Unbekannte Werte
	# fallen im Parser / `load_preferences` still auf Smolit zurück.
	var identity_id: int = AvatarIdentityRef.DEFAULT
	var identity_source := "default"
	if identity_env != "":
		identity_id = AvatarIdentityRef.identity_from_string(identity_env)
		identity_source = "env"
	elif prefs.has(AvatarPreferencesRef.KEY_IDENTITY):
		identity_id = int(prefs[AvatarPreferencesRef.KEY_IDENTITY])
		identity_source = "prefs"

	_appearance = AvatarAppearanceRef.make_appearance(
		theme, profile, Color(1, 1, 1, 1), intensity, 1.0,
	)
	_appearance["identity"] = AvatarIdentityRef.identity_name(identity_id)
	_identity_id = identity_id

	# Nur loggen, wenn irgendetwas aktiv gesetzt wurde — der pure
	# Default-Start bleibt byte-kompatibel stumm.
	var touched: bool = theme_source != "default" \
		or profile_source != "default" \
		or intensity_source != "default" \
		or identity_source != "default"
	if touched:
		var overrides: Dictionary = _appearance["overrides"]
		print("[avatar-appearance] identity=%s(%s) theme=%s(%s) profile=%s(%s) intensity=%.2f(%s) scale=%.2f" % [
			AvatarIdentityRef.identity_name(_identity_id),
			identity_source,
			AvatarAppearanceRef.theme_name(int(_appearance["theme"])),
			theme_source,
			AvatarAppearanceRef.profile_name(int(_appearance["profile"])),
			profile_source,
			float(overrides["intensity"]),
			intensity_source,
			float(overrides["scale"]),
		])


## Setzt Sichtbarkeit und Content der beiden Visual-Pfade entsprechend
## der aktuellen `_identity_id`:
##
##   * Smolit → `_body` sichtbar (TextureRect mit Circle-Mask-Shader),
##     `_identity_shape` unsichtbar. Verhalten byte-identisch zu Phase A.
##   * Kuratierte Alternative → `_body` unsichtbar (Tween-Targets und
##     `_body.modulate:a` laufen trotzdem, aber rendern nichts),
##     `_identity_shape` sichtbar und zeichnet die Grundform. Der
##     `_process`-Hook spiegelt jeden Frame die Transform-/Modulate-
##     Werte vom `_body` auf den Shape, damit alle State-Tweens ohne
##     Umbau weiter greifen.
func _apply_identity_visual_config() -> void:
	if _body == null or _identity_shape == null:
		return
	var is_smolit := AvatarIdentityRef.is_smolit(_identity_id)
	_body.visible = is_smolit
	_identity_shape.visible = not is_smolit
	if _identity_shape.has_method("set_identity"):
		_identity_shape.call("set_identity", _identity_id)
	if is_smolit:
		# Sicherheitsreset — für den Fall, dass die Identity vorher eine
		# kuratierte Alternative war, soll Smolit nicht mit verschleppten
		# Scale/Rotate-Werten zurückkommen.
		_identity_shape.scale = Vector2.ONE
		_identity_shape.rotation = 0.0
		_identity_shape.modulate = NORMAL_MODULATE


func _process(_delta: float) -> void:
	# Mirror-Only-Pfad: wenn eine kuratierte Identity aktiv ist,
	# spiegelt dieser Tick `_body`'s Transform-/Modulate-Werte auf den
	# Identity-Shape. Für Smolit (`_body` sichtbar, `_identity_shape`
	# hidden) macht der Block nichts — insbesondere greift das
	# `visible`-Gate, damit wir keine unnötigen Writes auf ein
	# Node pro Frame erzeugen.
	if _identity_shape == null or not _identity_shape.visible:
		return
	_identity_shape.scale = _body.scale
	_identity_shape.rotation = _body.rotation
	_identity_shape.modulate = _body.modulate
