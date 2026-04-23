extends SceneTree
## Behavioral-Expression-Smoketest (PR 15).
##
## Zwei Ebenen:
##
##   * **Pure Ebene** — `AvatarExpression` ist reine RefCounted-Logik:
##     Enum, Namen, Multiplier, Tint-Shifts, `default_for_state` sowie
##     Hold-Semantik (sticky vs. transient). Diese Assertions laufen
##     ohne Scene-Tree.
##   * **Controller-Verdrahtung** — wir prüfen den Quelltext von
##     `ui/scripts/avatar/avatar_controller.gd` auf die erwarteten
##     Hooks: Multiplier-Fold in Puls-/Wiggle-/Tint-Pfad, Handler pro
##     Event (thinking, response, speaking_started/ended, heard,
##     error, disconnected), Preview-Hook für Dev-Controls. Eine
##     echte Scene-Spawn-Integration läuft nicht in `--script`-Mode
##     (der Godot-Headless-Kontext registriert die `EventBus`-/
##     `IpcClient`-Autoloads nicht); die volle Laufzeit-Integration
##     wird beim regulären Start der Main-Scene geprüft.
##
## Ausdrücklich **nicht** Teil des Smokes:
##
##   * kein realer IPC-Roundtrip (kein Core, kein WebSocket);
##   * keine Tween-/Timer-Zeitmessung — Multiplier werden nur
##     gelesen, nicht in ihrer Render-Auswirkung beobachtet;
##   * keine Phonem-/Lip-Sync-/Audio-Timeline-Verifikation;
##   * kein Emotion-Protokoll-Test — der Layer hat keinen Core-Hook.
##
## Lauf:
##   godot --headless --path ui --script scripts/avatar_expression_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh avatar-expression-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _ExprRef := preload("res://scripts/avatar/avatar_expression.gd")
const _StateRef := preload("res://scripts/avatar/avatar_state.gd")
const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const _CapsRef := preload("res://scripts/avatar/avatar_template_capabilities.gd")

var _fail: int = 0
var _controller_source: String = ""


func _init() -> void:
	_controller_source = _read_file("res://scripts/avatar/avatar_controller.gd")

	_check_enum_names_and_parser()
	_check_all_kinds_stable()
	_check_hold_seconds_invariants()
	_check_multiplier_ranges()
	_check_tint_shift_shape()
	_check_default_for_state_mapping()
	_check_default_for_state_when_disconnected()

	_check_controller_imports_and_signal()
	_check_controller_multiplier_folding()
	_check_controller_event_handlers()
	_check_controller_event_to_expression_mapping()
	_check_controller_speaking_guard_preserves_acting_and_error()
	_check_controller_preview_and_template_capability_safety()

	print("---")
	if _fail == 0:
		print("avatar_expression smoke: PASS")
		quit(0)
	else:
		print("avatar_expression smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Pure helpers -------------------------------------------------------


func _check_enum_names_and_parser() -> void:
	var pairs := [
		[_ExprRef.Kind.NEUTRAL, "neutral"],
		[_ExprRef.Kind.FOCUSED, "focused"],
		[_ExprRef.Kind.CURIOUS, "curious"],
		[_ExprRef.Kind.SPEAKING, "speaking"],
		[_ExprRef.Kind.PLEASED, "pleased"],
		[_ExprRef.Kind.ERROR_SOFT, "error_soft"],
	]
	for pair in pairs:
		var kind: int = int(pair[0])
		var name: String = String(pair[1])
		_assert(_ExprRef.name_of(kind) == name,
			"name_of(%s) → '%s'" % [str(kind), name])
		_assert(_ExprRef.from_string(name) == kind,
			"from_string('%s') → %s" % [name, str(kind)])
		_assert(_ExprRef.is_known(kind),
			"is_known(%s) = true" % str(kind))

	_assert(_ExprRef.from_string("") == _ExprRef.Kind.NEUTRAL,
		"from_string('') → NEUTRAL (default)")
	_assert(_ExprRef.from_string("  Pleased ") == _ExprRef.Kind.PLEASED,
		"from_string normalizes whitespace + case")
	_assert(_ExprRef.from_string("bogus") == _ExprRef.Kind.NEUTRAL,
		"from_string('bogus') → NEUTRAL (fallback)")
	_assert(not _ExprRef.is_known(9999),
		"is_known(9999) = false")


func _check_all_kinds_stable() -> void:
	var kinds: Array = _ExprRef.all_kinds()
	_assert(kinds.size() == 6,
		"all_kinds() contains six expressions")
	_assert(kinds[0] == _ExprRef.Kind.NEUTRAL,
		"all_kinds()[0] == NEUTRAL (stable head)")
	_assert(kinds[-1] == _ExprRef.Kind.ERROR_SOFT,
		"all_kinds()[-1] == ERROR_SOFT (stable tail)")


func _check_hold_seconds_invariants() -> void:
	for sticky in [_ExprRef.Kind.NEUTRAL, _ExprRef.Kind.FOCUSED, _ExprRef.Kind.SPEAKING]:
		_assert(_ExprRef.hold_seconds(sticky) == 0.0,
			"hold_seconds(%s) == 0.0 (sticky)" % _ExprRef.name_of(sticky))
		_assert(not _ExprRef.is_transient(sticky),
			"is_transient(%s) == false" % _ExprRef.name_of(sticky))

	for transient in [_ExprRef.Kind.CURIOUS, _ExprRef.Kind.PLEASED, _ExprRef.Kind.ERROR_SOFT]:
		_assert(_ExprRef.hold_seconds(transient) > 0.0,
			"hold_seconds(%s) > 0.0 (transient)" % _ExprRef.name_of(transient))
		_assert(_ExprRef.is_transient(transient),
			"is_transient(%s) == true" % _ExprRef.name_of(transient))
		_assert(_ExprRef.hold_seconds(transient) <= 1.5,
			"hold_seconds(%s) ≤ 1.5s (micro-cue budget)"
				% _ExprRef.name_of(transient))


func _check_multiplier_ranges() -> void:
	for k in _ExprRef.all_kinds():
		var p: float = _ExprRef.pulse_multiplier(k)
		_assert(p >= 0.5 and p <= 1.5,
			"pulse_multiplier(%s) in [0.5, 1.5]" % _ExprRef.name_of(k))
		var w: float = _ExprRef.wiggle_multiplier(k)
		_assert(w >= 0.0 and w <= 2.0,
			"wiggle_multiplier(%s) in [0.0, 2.0]" % _ExprRef.name_of(k))
	_assert(_ExprRef.pulse_multiplier(_ExprRef.Kind.NEUTRAL) == 1.0,
		"neutral pulse multiplier is identity")
	_assert(_ExprRef.wiggle_multiplier(_ExprRef.Kind.NEUTRAL) == 1.0,
		"neutral wiggle multiplier is identity")
	_assert(_ExprRef.wiggle_multiplier(_ExprRef.Kind.ERROR_SOFT) == 0.0,
		"error_soft wiggle multiplier is 0.0 (no startle overlay)")


func _check_tint_shift_shape() -> void:
	var neutral_shift: Color = _ExprRef.tint_shift(_ExprRef.Kind.NEUTRAL)
	_assert(neutral_shift == Color(1.0, 1.0, 1.0, 1.0),
		"neutral tint shift is identity Color(1,1,1,1)")
	for k in _ExprRef.all_kinds():
		var c: Color = _ExprRef.tint_shift(k)
		_assert(c.r >= 0.8 and c.r <= 1.2,
			"tint_shift(%s).r within ±20%%" % _ExprRef.name_of(k))
		_assert(c.g >= 0.8 and c.g <= 1.2,
			"tint_shift(%s).g within ±20%%" % _ExprRef.name_of(k))
		_assert(c.b >= 0.8 and c.b <= 1.2,
			"tint_shift(%s).b within ±20%%" % _ExprRef.name_of(k))
		_assert(c.a == 1.0,
			"tint_shift(%s).a == 1.0 (no alpha shift)" % _ExprRef.name_of(k))


func _check_default_for_state_mapping() -> void:
	_assert(_ExprRef.default_for_state(_StateRef.State.IDLE, true) == _ExprRef.Kind.NEUTRAL,
		"default_for_state(IDLE, connected) == NEUTRAL")
	_assert(_ExprRef.default_for_state(_StateRef.State.THINKING, true) == _ExprRef.Kind.FOCUSED,
		"default_for_state(THINKING, connected) == FOCUSED")
	_assert(_ExprRef.default_for_state(_StateRef.State.TALKING, true) == _ExprRef.Kind.SPEAKING,
		"default_for_state(TALKING, connected) == SPEAKING")
	_assert(_ExprRef.default_for_state(_StateRef.State.ACTING, true) == _ExprRef.Kind.NEUTRAL,
		"default_for_state(ACTING, connected) == NEUTRAL (no own expression)")
	_assert(_ExprRef.default_for_state(_StateRef.State.ERROR, true) == _ExprRef.Kind.ERROR_SOFT,
		"default_for_state(ERROR, connected) == ERROR_SOFT")
	_assert(_ExprRef.default_for_state(_StateRef.State.DISCONNECTED, true) == _ExprRef.Kind.NEUTRAL,
		"default_for_state(DISCONNECTED, connected) == NEUTRAL")


func _check_default_for_state_when_disconnected() -> void:
	# `connected=false` dominiert: offline bleibt neutral, egal welcher
	# State gerade gemeldet wird.
	for s in [_StateRef.State.IDLE, _StateRef.State.THINKING, _StateRef.State.TALKING,
			_StateRef.State.ACTING, _StateRef.State.ERROR, _StateRef.State.DISCONNECTED]:
		_assert(_ExprRef.default_for_state(s, false) == _ExprRef.Kind.NEUTRAL,
			"default_for_state(%s, disconnected) == NEUTRAL"
				% _StateRef.name_of(s))


# --- Controller-Quelltext / Verdrahtung ---------------------------------
#
# Wir lesen `avatar_controller.gd` als Text und verifizieren die
# Verdrahtungs-Punkte. Das ist bewusst robuster als eine Scene-Spawn-
# Simulation: Godot im `--script`-Mode registriert die Autoloads
# (`EventBus`, `IpcClient`) nicht, also würde ein echter Scene-Load den
# Controller nicht kompilieren. Der Quelltext-Check deckt die gleichen
# Verdrahtungs-Regressionen ab (jede Umbenennung, jedes versehentliche
# Löschen eines Handlers) ohne auf einen halb-initialisierten Tree
# angewiesen zu sein.


func _check_controller_imports_and_signal() -> void:
	_assert(_controller_source.find("AvatarExpressionRef") >= 0,
		"avatar_controller imports AvatarExpressionRef")
	_assert(_controller_source.find("signal expression_changed") >= 0,
		"avatar_controller declares expression_changed signal")
	_assert(_controller_source.find("current_expression()") >= 0
			or _controller_source.find("func current_expression") >= 0,
		"avatar_controller exposes current_expression()")


func _check_controller_multiplier_folding() -> void:
	_assert(_controller_source.find("pulse_multiplier(_expression)") >= 0,
		"breath tween folds expression pulse multiplier")
	_assert(_controller_source.find("wiggle_multiplier(_expression)") >= 0,
		"wiggle tween folds expression wiggle multiplier")
	_assert(_controller_source.find("_apply_expression_tint") >= 0,
		"appearance tint folds expression tint shift")
	# Der Expression-Multiplier darf die Kapazitätsgrenze nicht
	# umgehen: state_pulse bleibt in der Kette, `wiggle` filtert
	# `_arm_wiggle_timer` vor-early-out weiter.
	_assert(_controller_source.find("pulse_mult * expression_pulse") >= 0,
		"breath tween composes template + expression pulse multiplicatively")


func _check_controller_event_handlers() -> void:
	for handler in ["_on_heard", "_set_expression", "_refresh_expression_from_state",
			"_on_expression_hold_timeout", "preview_expression"]:
		_assert(_controller_source.find("func %s" % handler) >= 0,
			"avatar_controller defines %s" % handler)

	_assert(_controller_source.find("EventBus.heard_received.connect") >= 0,
		"avatar_controller subscribes to heard_received")


func _check_controller_event_to_expression_mapping() -> void:
	# Die Event → Expression-Kanten werden im Quelltext durch die
	# `_set_expression(AvatarExpressionRef.Kind.X)`-Aufrufe festgelegt.
	# Wir kontrollieren die vier kritischen Stellen deterministisch.
	_assert(_controller_source.find(
		"_set_expression(AvatarExpressionRef.Kind.PLEASED)") >= 0,
		"response+speaking_ended(ok) path uses PLEASED cue")
	_assert(_controller_source.find(
		"_set_expression(AvatarExpressionRef.Kind.SPEAKING)") >= 0,
		"speaking_started path pins SPEAKING (sticky)")
	_assert(_controller_source.find(
		"_set_expression(AvatarExpressionRef.Kind.CURIOUS)") >= 0,
		"heard path emits CURIOUS cue")
	_assert(_controller_source.find(
		"_set_expression(AvatarExpressionRef.Kind.ERROR_SOFT)") >= 0,
		"speaking_ended(!ok) path uses ERROR_SOFT cue")
	# thinking / disconnected / error / idle übernehmen die Expression
	# aus `default_for_state`; wir prüfen, dass `_refresh_expression_from_state`
	# in `_set_state` eingehängt ist.
	_assert(_controller_source.find("_refresh_expression_from_state()") >= 0,
		"_set_state refreshes expression from state default")


func _check_controller_speaking_guard_preserves_acting_and_error() -> void:
	# PR 14-Guard: speaking_started steigt NICHT in ACTING/ERROR ein.
	# Ohne diesen Guard würde ein spätes `speaking_started` einen
	# laufenden Desktop- oder Fehler-Cue überschreiben — das wäre ein
	# UX-Knick und ein Regress gegen PR 14.
	var guard_marker := "if _state == AvatarStateRef.State.ERROR or _state == AvatarStateRef.State.ACTING:"
	_assert(_controller_source.find(guard_marker) >= 0,
		"_on_speaking_started preserves ACTING/ERROR state (PR 14 guard intact)")
	# speaking_ended bleibt TALKING-only — gleiche Regel, andere Seite.
	_assert(_controller_source.find("if _state != AvatarStateRef.State.TALKING:") >= 0,
		"_on_speaking_ended only reacts while state == TALKING")


func _check_controller_preview_and_template_capability_safety() -> void:
	# Der Expression-Layer schaltet Cues rein über Multiplier; er darf
	# nicht an der Capability-Schicht vorbeidrehen. Wir prüfen, dass
	# die `_arm_wiggle_timer`-Filterung weiterhin die primäre Gate
	# gegen `wiggle = NONE` ist (diese Funktion existiert seit Phase B
	# und ruft `AvatarTemplateCapsRef.multiplier(..., EXPR_WIGGLE)` ab).
	_assert(_controller_source.find("EXPR_WIGGLE") >= 0,
		"wiggle path still consults template capability EXPR_WIGGLE")
	_assert(_controller_source.find("EXPR_STATE_PULSE") >= 0,
		"breath path still consults template capability EXPR_STATE_PULSE")
	_assert(_controller_source.find("EXPR_THEME_TINT") >= 0,
		"expression tint path still consults template capability EXPR_THEME_TINT")

	# Gleichzeitig prüfen wir, dass der Expression-Wiggle-Multiplier
	# _nicht_ die Kapazitätsgrenze umgeht, indem er vor dem Capability-
	# Multiplier stünde — die multiplikative Komposition hält die
	# NONE-Grenze bindend.
	_assert(_controller_source.find("angle_mult * expression_wiggle") >= 0,
		"wiggle composes template cap × expression multiplier (cap remains binding)")


# --- Helpers ------------------------------------------------------------


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("avatar_expression_smoke: cannot open %s" % path)
		return ""
	return f.get_as_text()
