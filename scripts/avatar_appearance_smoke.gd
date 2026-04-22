extends SceneTree
## Avatar-Appearance-Smoketest (Phase A).
##
## Prüft die pure Logik in
## `ui/scripts/avatar/avatar_appearance.gd` ohne Scene-Tree. Deckt
## Parser-/Fallback-Verhalten, Clamping, resolve-Funktionen und die
## **Identitätsgarantie** ab: DEFAULT-Theme + CALM-Profile + Unity-
## Overrides reproduzieren 1:1 die vor-PR-Werte, d. h. jeder
## resolve-Helfer gibt bei dieser Kombination den Basiswert zurück.
##
## Lauf:
##   godot --headless --path ui --script scripts/avatar_appearance_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh avatar-appearance-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _AppearanceRef := preload("res://scripts/avatar/avatar_appearance.gd")

var _fail: int = 0


func _init() -> void:
	_check_parsers()
	_check_make_appearance_clamping()
	_check_identity_under_defaults()
	_check_theme_effects()
	_check_profile_effects()
	_check_override_effects()
	_check_wiggle_bounds()

	print("---")
	if _fail == 0:
		print("avatar_appearance smoke: PASS")
		quit(0)
	else:
		print("avatar_appearance smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


func _color_close(a: Color, b: Color, eps: float = 0.001) -> bool:
	return abs(a.r - b.r) < eps and abs(a.g - b.g) < eps \
		and abs(a.b - b.b) < eps and abs(a.a - b.a) < eps


func _vec_close(a: Vector2, b: Vector2, eps: float = 0.001) -> bool:
	return abs(a.x - b.x) < eps and abs(a.y - b.y) < eps


func _float_close(a: float, b: float, eps: float = 0.001) -> bool:
	return abs(a - b) < eps


# --- Cases ---------------------------------------------------------------


func _check_parsers() -> void:
	# Theme parser
	_assert(_AppearanceRef.theme_from_string("default") == _AppearanceRef.ThemePreset.DEFAULT,
		"theme: default → DEFAULT")
	_assert(_AppearanceRef.theme_from_string("SOFT") == _AppearanceRef.ThemePreset.SOFT,
		"theme: SOFT (case-insensitive) → SOFT")
	_assert(_AppearanceRef.theme_from_string(" tech ") == _AppearanceRef.ThemePreset.TECH,
		"theme: ' tech ' stripped → TECH")
	_assert(_AppearanceRef.theme_from_string("nonsense") == _AppearanceRef.ThemePreset.DEFAULT,
		"theme: unknown → DEFAULT fallback")
	_assert(_AppearanceRef.theme_from_string("") == _AppearanceRef.ThemePreset.DEFAULT,
		"theme: empty → DEFAULT")
	# Profile parser
	_assert(_AppearanceRef.profile_from_string("calm") == _AppearanceRef.BehaviorProfile.CALM,
		"profile: calm → CALM")
	_assert(_AppearanceRef.profile_from_string("Lively") == _AppearanceRef.BehaviorProfile.LIVELY,
		"profile: Lively → LIVELY")
	_assert(_AppearanceRef.profile_from_string("Reserved") == _AppearanceRef.BehaviorProfile.RESERVED,
		"profile: Reserved → RESERVED")
	_assert(_AppearanceRef.profile_from_string("zzz") == _AppearanceRef.BehaviorProfile.CALM,
		"profile: unknown → CALM fallback")
	# Name round-trips
	_assert(_AppearanceRef.theme_name(_AppearanceRef.ThemePreset.MINIMAL) == "minimal",
		"theme_name MINIMAL")
	_assert(_AppearanceRef.profile_name(_AppearanceRef.BehaviorProfile.RESERVED) == "reserved",
		"profile_name RESERVED")


func _check_make_appearance_clamping() -> void:
	var a := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT,
		_AppearanceRef.BehaviorProfile.CALM,
		Color(1, 1, 1, 1),
		999.0,   # over max
		-5.0,    # under min
	)
	var overrides: Dictionary = a["overrides"]
	_assert(_float_close(float(overrides["intensity"]), _AppearanceRef.INTENSITY_MAX),
		"make_appearance: intensity clamped to max")
	_assert(_float_close(float(overrides["scale"]), _AppearanceRef.SCALE_MIN),
		"make_appearance: scale clamped to min")

	# Unknown theme/profile integers fall back
	var b := _AppearanceRef.make_appearance(99, 99, Color(1, 1, 1, 1), 1.0, 1.0)
	_assert(int(b["theme"]) == _AppearanceRef.ThemePreset.DEFAULT,
		"make_appearance: unknown theme int → DEFAULT")
	_assert(int(b["profile"]) == _AppearanceRef.BehaviorProfile.CALM,
		"make_appearance: unknown profile int → CALM")


func _check_identity_under_defaults() -> void:
	# The key invariant of Phase A: under default appearance (no env
	# set anywhere), every resolve helper must return the base value
	# unchanged. This keeps the pre-PR avatar rendering byte-identical.
	var a := _AppearanceRef.new_appearance()

	# Tints: multiplying by identity color leaves base unchanged.
	var base_color := Color(0.85, 0.85, 0.95, 0.85)  # mimics THINKING_MODULATE
	_assert(_color_close(_AppearanceRef.resolved_tint(a, base_color), base_color),
		"identity: resolved_tint == base_color")

	# Amplitudes: CALM multiplier 1.0 → delta from 1.0 unchanged.
	var base_amp := Vector2(1.02, 1.02)
	_assert(_vec_close(_AppearanceRef.resolved_amplitude(a, base_amp), base_amp),
		"identity: resolved_amplitude == base")

	# Half-seconds: CALM tempo 1.0 → unchanged.
	_assert(_float_close(_AppearanceRef.resolved_half_seconds(a, 1.6), 1.6),
		"identity: resolved_half_seconds == base")

	# Scale: override 1.0 → base unchanged.
	_assert(_vec_close(_AppearanceRef.resolved_scale(a, Vector2.ONE), Vector2.ONE),
		"identity: resolved_scale BASE == BASE")
	_assert(_vec_close(_AppearanceRef.resolved_scale(a, Vector2(1.06, 1.06)), Vector2(1.06, 1.06)),
		"identity: resolved_scale HOVER == HOVER")

	# Wiggle interval: CALM multiplier 1.0 → unchanged (and above 1.0 clamp).
	_assert(_float_close(_AppearanceRef.resolved_wiggle_interval(a, 14.0), 14.0),
		"identity: resolved_wiggle_interval(14) == 14")
	_assert(_float_close(_AppearanceRef.resolved_wiggle_interval(a, 28.0), 28.0),
		"identity: resolved_wiggle_interval(28) == 28")


func _check_theme_effects() -> void:
	# TECH tint multiplies blue channel up, red down — result is
	# not equal to the base color when applied to identity-white.
	var a_default := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT,
		_AppearanceRef.BehaviorProfile.CALM,
		Color(1, 1, 1, 1), 1.0, 1.0,
	)
	var a_tech := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.TECH,
		_AppearanceRef.BehaviorProfile.CALM,
		Color(1, 1, 1, 1), 1.0, 1.0,
	)
	var base := Color(1, 1, 1, 1)
	var default_result := _AppearanceRef.resolved_tint(a_default, base)
	var tech_result := _AppearanceRef.resolved_tint(a_tech, base)
	_assert(_color_close(default_result, base),
		"theme DEFAULT: resolved_tint white == white (identity)")
	_assert(not _color_close(tech_result, base),
		"theme TECH: shifts tint away from white")
	_assert(tech_result.b > default_result.b,
		"theme TECH: blue channel higher than DEFAULT")


func _check_profile_effects() -> void:
	var base_amp := Vector2(1.04, 1.04)   # like TALKING_PULSE_AMPLITUDE
	var a_calm := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.CALM,
		Color(1, 1, 1, 1), 1.0, 1.0,
	)
	var a_lively := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.LIVELY,
		Color(1, 1, 1, 1), 1.0, 1.0,
	)
	var a_reserved := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.RESERVED,
		Color(1, 1, 1, 1), 1.0, 1.0,
	)
	var amp_calm := _AppearanceRef.resolved_amplitude(a_calm, base_amp)
	var amp_lively := _AppearanceRef.resolved_amplitude(a_lively, base_amp)
	var amp_reserved := _AppearanceRef.resolved_amplitude(a_reserved, base_amp)

	# Delta from 1.0 grows with LIVELY, shrinks with RESERVED.
	var delta_calm := amp_calm.x - 1.0
	var delta_lively := amp_lively.x - 1.0
	var delta_reserved := amp_reserved.x - 1.0
	_assert(delta_lively > delta_calm and delta_calm > delta_reserved,
		"profile: LIVELY > CALM > RESERVED in amplitude delta")

	# Tempo: LIVELY faster (smaller half_seconds), RESERVED slower.
	var tempo_calm := _AppearanceRef.resolved_half_seconds(a_calm, 1.6)
	var tempo_lively := _AppearanceRef.resolved_half_seconds(a_lively, 1.6)
	var tempo_reserved := _AppearanceRef.resolved_half_seconds(a_reserved, 1.6)
	_assert(tempo_lively < tempo_calm and tempo_calm < tempo_reserved,
		"profile: LIVELY faster < CALM < RESERVED slower")

	# Wiggle: LIVELY shorter interval, RESERVED longer.
	var wig_calm := _AppearanceRef.resolved_wiggle_interval(a_calm, 14.0)
	var wig_lively := _AppearanceRef.resolved_wiggle_interval(a_lively, 14.0)
	var wig_reserved := _AppearanceRef.resolved_wiggle_interval(a_reserved, 14.0)
	_assert(wig_lively < wig_calm and wig_calm < wig_reserved,
		"profile: wiggle LIVELY < CALM < RESERVED")


func _check_override_effects() -> void:
	# Intensity override amplifies profile delta.
	var a_lively_hot := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.LIVELY,
		Color(1, 1, 1, 1), 1.5, 1.0,
	)
	var a_lively_neutral := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.LIVELY,
		Color(1, 1, 1, 1), 1.0, 1.0,
	)
	var base := Vector2(1.04, 1.04)
	var amp_hot := _AppearanceRef.resolved_amplitude(a_lively_hot, base)
	var amp_neutral := _AppearanceRef.resolved_amplitude(a_lively_neutral, base)
	_assert(amp_hot.x - 1.0 > amp_neutral.x - 1.0,
		"intensity 1.5 amplifies LIVELY further than 1.0")

	# Primary tint override multiplies onto theme tint.
	var a_primary := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.CALM,
		Color(0.5, 0.5, 0.5, 1.0), 1.0, 1.0,
	)
	var base_color := Color(1, 1, 1, 1)
	var result := _AppearanceRef.resolved_tint(a_primary, base_color)
	_assert(_color_close(result, Color(0.5, 0.5, 0.5, 1.0)),
		"primary_tint 0.5 darkens white baseline")

	# Scale override stays clamped.
	var a_bigscale := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.CALM,
		Color(1, 1, 1, 1), 1.0, 99.0,
	)
	var scaled := _AppearanceRef.resolved_scale(a_bigscale, Vector2(1.0, 1.0))
	_assert(_vec_close(scaled, Vector2(_AppearanceRef.SCALE_MAX, _AppearanceRef.SCALE_MAX)),
		"scale 99 clamped to SCALE_MAX")


func _check_wiggle_bounds() -> void:
	# Even with LIVELY + high intensity, wiggle interval never drops
	# below the 1.0 s lower clamp in resolved_wiggle_interval.
	var a := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.DEFAULT, _AppearanceRef.BehaviorProfile.LIVELY,
		Color(1, 1, 1, 1), 1.5, 1.0,
	)
	var interval := _AppearanceRef.resolved_wiggle_interval(a, 0.5)
	_assert(interval >= 1.0, "wiggle interval always >= 1.0 (lower clamp)")
