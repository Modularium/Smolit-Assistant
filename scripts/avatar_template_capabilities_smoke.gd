extends SceneTree
## Avatar-Template-Capabilities-Smoketest (Phase B hardening).
##
## Prüft den neuen Capability-Contract aus
## `ui/scripts/avatar/avatar_template_capabilities.gd` ohne Scene-Tree.
## Fokus:
##
##   * Smolit bleibt Referenzlinie: alle States voll unterstützt, keine
##     Fallbacks, alle Ausdrucks-Achsen `FULL`.
##   * State-Auflösung ist deterministisch:
##     - unterstützter State → identisch zurück;
##     - `orb.TALKING` → `ACTING` (dokumentierter Fallback);
##     - fehlender Fallback → `IDLE` (End-Fallback-Garantie).
##   * Capability-Lookups liefern exakt einen `ExpressionLevel`-Wert
##     pro Achse; fehlende Keys werden konservativ als `FULL` gelesen.
##   * Multiplier-Mapping ist stabil: `FULL` → 1.0, `REDUCED` → 0.5,
##     `NONE` → 0.0 (keine Zwischenwerte).
##   * Unbekannte Identity-IDs fallen beim Lookup still auf Smolit
##     zurück — kein Crash, kein undefinierter Zustand.
##
## Lauf:
##   godot --headless --path ui --script scripts/avatar_template_capabilities_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh avatar-template-capabilities-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _CapsRef := preload("res://scripts/avatar/avatar_template_capabilities.gd")
const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const _StateRef := preload("res://scripts/avatar/avatar_state.gd")

var _fail: int = 0


func _init() -> void:
	_check_smolit_is_reference()
	_check_robot_head_contract()
	_check_orb_contract_and_state_fallback()
	_check_humanoid_contract()
	_check_resolve_state_end_fallback()
	_check_unknown_identity_clamps_to_smolit()
	_check_expression_level_full_for_missing_key()
	_check_multiplier_mapping()
	_check_all_known_identities_have_entries()

	print("---")
	if _fail == 0:
		print("avatar_template_capabilities smoke: PASS")
		quit(0)
	else:
		print("avatar_template_capabilities smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Cases ---------------------------------------------------------------


func _check_smolit_is_reference() -> void:
	var smolit: int = _IdentityRef.Identity.SMOLIT_SALAMANDER
	for s in _all_states():
		_assert(_CapsRef.supports_state(smolit, s),
			"smolit supports state %s" % _StateRef.name_of(s))
		_assert(_CapsRef.resolve_state(smolit, s) == s,
			"smolit resolves %s to itself (reference line)" % _StateRef.name_of(s))
	for expr in _all_expressions():
		_assert(_CapsRef.expression_level(smolit, expr) == _CapsRef.ExpressionLevel.FULL,
			"smolit expression '%s' is FULL" % expr)


func _check_robot_head_contract() -> void:
	var robot: int = _IdentityRef.Identity.ROBOT_HEAD
	for s in _all_states():
		_assert(_CapsRef.supports_state(robot, s),
			"robot_head supports state %s" % _StateRef.name_of(s))
		_assert(_CapsRef.resolve_state(robot, s) == s,
			"robot_head resolves %s to itself" % _StateRef.name_of(s))
	# Wiggle ist reduziert — alles andere voll.
	_assert(_CapsRef.expression_level(robot, _CapsRef.EXPR_WIGGLE)
			== _CapsRef.ExpressionLevel.REDUCED,
		"robot_head wiggle is REDUCED")
	_assert(_CapsRef.expression_level(robot, _CapsRef.EXPR_STATE_PULSE)
			== _CapsRef.ExpressionLevel.FULL,
		"robot_head state_pulse is FULL")
	_assert(_CapsRef.expression_level(robot, _CapsRef.EXPR_ERROR_STARTLE)
			== _CapsRef.ExpressionLevel.FULL,
		"robot_head error_startle is FULL")


func _check_orb_contract_and_state_fallback() -> void:
	var orb: int = _IdentityRef.Identity.ORB
	# Orb unterstützt alles außer TALKING.
	_assert(not _CapsRef.supports_state(orb, _StateRef.State.TALKING),
		"orb does NOT support TALKING (no mouth)")
	_assert(_CapsRef.supports_state(orb, _StateRef.State.IDLE),
		"orb supports IDLE")
	_assert(_CapsRef.supports_state(orb, _StateRef.State.ACTING),
		"orb supports ACTING")
	_assert(_CapsRef.supports_state(orb, _StateRef.State.ERROR),
		"orb supports ERROR")

	# Dokumentierter Fallback: TALKING → ACTING.
	_assert(_CapsRef.resolve_state(orb, _StateRef.State.TALKING)
			== _StateRef.State.ACTING,
		"orb.resolve_state(TALKING) == ACTING (documented fallback)")

	# Ausdruck: Wiggle komplett aus; Startle/Pulse voll.
	_assert(_CapsRef.expression_level(orb, _CapsRef.EXPR_WIGGLE)
			== _CapsRef.ExpressionLevel.NONE,
		"orb wiggle is NONE (no head-nod on an abstract circle)")
	_assert(_CapsRef.expression_level(orb, _CapsRef.EXPR_STATE_PULSE)
			== _CapsRef.ExpressionLevel.FULL,
		"orb state_pulse is FULL (glow breathes)")
	_assert(_CapsRef.expression_level(orb, _CapsRef.EXPR_ERROR_STARTLE)
			== _CapsRef.ExpressionLevel.FULL,
		"orb error_startle is FULL")


func _check_humanoid_contract() -> void:
	var human: int = _IdentityRef.Identity.HUMANOID_HEAD
	for s in _all_states():
		_assert(_CapsRef.supports_state(human, s),
			"humanoid_head supports state %s" % _StateRef.name_of(s))
	_assert(_CapsRef.expression_level(human, _CapsRef.EXPR_WIGGLE)
			== _CapsRef.ExpressionLevel.REDUCED,
		"humanoid_head wiggle is REDUCED (quieter than Smolit)")
	_assert(_CapsRef.expression_level(human, _CapsRef.EXPR_STATE_PULSE)
			== _CapsRef.ExpressionLevel.FULL,
		"humanoid_head state_pulse is FULL")
	_assert(_CapsRef.expression_level(human, _CapsRef.EXPR_ERROR_STARTLE)
			== _CapsRef.ExpressionLevel.FULL,
		"humanoid_head error_startle is FULL")


func _check_resolve_state_end_fallback() -> void:
	# Ein Template, das einen State weder unterstützt noch explizit
	# remappt, muss auf IDLE zurückfallen — die Garantie, dass
	# `resolve_state` immer einen renderbaren State liefert.
	var orb: int = _IdentityRef.Identity.ORB
	# Ein synthetischer unbekannter State (außerhalb des Enums).
	var resolved: int = _CapsRef.resolve_state(orb, 999)
	_assert(resolved == _StateRef.State.IDLE,
		"resolve_state on unknown state falls back to IDLE")


func _check_unknown_identity_clamps_to_smolit() -> void:
	# 99 ist kein bekannter Identity-Int. Das Capability-Modul klemmt
	# vor dem Lookup auf Smolit — alle anschließenden Antworten sollen
	# dieselben Werte liefern wie für Smolit selbst.
	var smolit: int = _IdentityRef.Identity.SMOLIT_SALAMANDER
	_assert(_CapsRef.supports_state(99, _StateRef.State.TALKING)
			== _CapsRef.supports_state(smolit, _StateRef.State.TALKING),
		"unknown identity → supports_state matches Smolit")
	_assert(_CapsRef.resolve_state(99, _StateRef.State.THINKING)
			== _StateRef.State.THINKING,
		"unknown identity → resolve_state behaves like Smolit (THINKING unchanged)")
	_assert(_CapsRef.expression_level(99, _CapsRef.EXPR_WIGGLE)
			== _CapsRef.ExpressionLevel.FULL,
		"unknown identity → wiggle FULL (Smolit reference)")


func _check_expression_level_full_for_missing_key() -> void:
	# Robustheits-Anforderung: eine Achse, die in der Spec nicht
	# explizit aufgeführt wäre, soll als `FULL` interpretiert werden.
	# Wir fragen bewusst einen String ab, der kein bekannter Key ist.
	var smolit: int = _IdentityRef.Identity.SMOLIT_SALAMANDER
	var level: int = _CapsRef.expression_level(smolit, "not_in_contract")
	_assert(level == _CapsRef.ExpressionLevel.FULL,
		"unknown expression key → FULL fallback")


func _check_multiplier_mapping() -> void:
	# Die drei Levels müssen genau auf drei Multiplier-Werte mappen.
	# Keine Zwischenwerte, kein Drift.
	_assert(abs(_CapsRef.multiplier(_IdentityRef.Identity.SMOLIT_SALAMANDER,
			_CapsRef.EXPR_WIGGLE) - 1.0) < 0.001,
		"multiplier(smolit, wiggle) == 1.0 (FULL)")
	_assert(abs(_CapsRef.multiplier(_IdentityRef.Identity.ROBOT_HEAD,
			_CapsRef.EXPR_WIGGLE) - 0.5) < 0.001,
		"multiplier(robot_head, wiggle) == 0.5 (REDUCED)")
	_assert(abs(_CapsRef.multiplier(_IdentityRef.Identity.ORB,
			_CapsRef.EXPR_WIGGLE) - 0.0) < 0.001,
		"multiplier(orb, wiggle) == 0.0 (NONE)")


func _check_all_known_identities_have_entries() -> void:
	# Regression-Stopper: jede im Katalog bekannte Identity MUSS im
	# Capability-Modul eine Zeile haben. Fehlt eine, würde der
	# _safe_identity-Clamp sie als Smolit behandeln — ein leiser Bug,
	# den wir hier laut machen.
	for ident in _IdentityRef.all_ids():
		var caps: Dictionary = _CapsRef.capabilities_for(int(ident))
		_assert(caps.has("states_supported"),
			"capabilities_for(%s) has states_supported" % _IdentityRef.identity_name(int(ident)))
		_assert(caps.has("expression"),
			"capabilities_for(%s) has expression map" % _IdentityRef.identity_name(int(ident)))


# --- Helpers -------------------------------------------------------------


func _all_states() -> Array:
	return [
		_StateRef.State.IDLE,
		_StateRef.State.THINKING,
		_StateRef.State.TALKING,
		_StateRef.State.ACTING,
		_StateRef.State.DISCONNECTED,
		_StateRef.State.ERROR,
	]


func _all_expressions() -> Array:
	return [
		_CapsRef.EXPR_THEME_TINT,
		_CapsRef.EXPR_BEHAVIOR_PROFILE,
		_CapsRef.EXPR_STATE_PULSE,
		_CapsRef.EXPR_WIGGLE,
		_CapsRef.EXPR_ERROR_STARTLE,
	]
