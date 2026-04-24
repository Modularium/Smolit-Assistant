extends SceneTree
## Dev-Controls-Smoketest.
##
## Verifiziert die Dev-Hooks der kleinen MVP-Steuerung aus
## `ui/scripts/dev_controls/` *ohne* die UI-Szene zu laden:
##
##   * `avatar_appearance.make_appearance(…)` produziert für alle
##     Theme/Profile/Intensity-Kombinationen, die das Dev-Panel
##     bietet, ein konsistentes Appearance-Dict.
##
## **PR 33** hat den Workflow-Overlay-Preview-Hook zusammen mit dem
## alten Drei-Knoten-Overlay entfernt; die frühere
## `_check_phase_names`-Case wandert mit diesem PR aus dem Smoke
## (der Phase-State-Enum existiert nicht mehr).
##
## Der Controller selbst braucht einen Scene-Tree (er greift auf
## @onready NodePaths zu) und wird daher hier NICHT instanziiert —
## wir testen die reine Übersetzungslogik, die zwischen Panel und
## Ziel-Controller liegt.
##
## Lauf:
##   godot --headless --path ui --script scripts/dev_controls_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh dev-controls-smoke

const _AppearanceRef := preload("res://scripts/avatar/avatar_appearance.gd")

var _fail: int = 0


func _init() -> void:
	_check_theme_profile_coverage()
	_check_make_appearance_matrix()
	_check_identity_preserved()

	print("---")
	if _fail == 0:
		print("dev_controls smoke: PASS")
		quit(0)
	else:
		print("dev_controls smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Cases ---------------------------------------------------------------


func _check_theme_profile_coverage() -> void:
	# Jeder Theme-/Profile-ID, den das Panel anbietet, muss durch die
	# Parser/Name-Helper des Appearance-Moduls erkannt werden.
	var themes := [
		_AppearanceRef.ThemePreset.DEFAULT,
		_AppearanceRef.ThemePreset.SOFT,
		_AppearanceRef.ThemePreset.TECH,
		_AppearanceRef.ThemePreset.MINIMAL,
	]
	for t in themes:
		var name: String = _AppearanceRef.theme_name(int(t))
		_assert(_AppearanceRef.theme_from_string(name) == t,
			"theme round-trip: %s → id → %s" % [name, name])
	var profiles := [
		_AppearanceRef.BehaviorProfile.CALM,
		_AppearanceRef.BehaviorProfile.LIVELY,
		_AppearanceRef.BehaviorProfile.RESERVED,
	]
	for p in profiles:
		var name: String = _AppearanceRef.profile_name(int(p))
		_assert(_AppearanceRef.profile_from_string(name) == p,
			"profile round-trip: %s" % name)


func _check_make_appearance_matrix() -> void:
	# Vier Themes × drei Profiles × drei Intensities = 36 Kombinationen.
	# Jede muss ein gültiges Appearance-Dict liefern, ohne Crash, ohne
	# Identitätswechsel.
	var themes := [
		_AppearanceRef.ThemePreset.DEFAULT,
		_AppearanceRef.ThemePreset.SOFT,
		_AppearanceRef.ThemePreset.TECH,
		_AppearanceRef.ThemePreset.MINIMAL,
	]
	var profiles := [
		_AppearanceRef.BehaviorProfile.CALM,
		_AppearanceRef.BehaviorProfile.LIVELY,
		_AppearanceRef.BehaviorProfile.RESERVED,
	]
	var intensities := [0.5, 1.0, 1.5]
	var total := 0
	var ok := 0
	for t in themes:
		for p in profiles:
			for i in intensities:
				total += 1
				var a := _AppearanceRef.make_appearance(
					int(t), int(p), Color(1, 1, 1, 1), float(i), 1.0,
				)
				var overrides: Dictionary = a.get("overrides", {})
				var has_overrides: bool = overrides.has("intensity") \
					and overrides.has("scale") \
					and overrides.has("primary_tint")
				var correct_intensity: bool = abs(float(overrides["intensity"]) - float(i)) < 0.01
				var correct_identity: bool = str(a.get("identity", "")) == "smolit_salamander"
				var correct_theme: bool = int(a.get("theme", -1)) == int(t)
				var correct_profile: bool = int(a.get("profile", -1)) == int(p)
				if has_overrides and correct_intensity and correct_identity \
						and correct_theme and correct_profile:
					ok += 1
	_assert(ok == total,
		"make_appearance 4x3x3 matrix all consistent (%d/%d)" % [ok, total])


func _check_identity_preserved() -> void:
	# Die Dev-Steuerung darf in keiner Kombination die Identity
	# ändern — Phase A bleibt brand-safe, Smolit Salamander only.
	var a := _AppearanceRef.make_appearance(
		_AppearanceRef.ThemePreset.TECH,
		_AppearanceRef.BehaviorProfile.LIVELY,
		Color(0.5, 0.5, 0.5, 1.0),
		1.3,
		1.0,
	)
	_assert(str(a.get("identity", "")) == "smolit_salamander",
		"identity remains smolit_salamander across dev-panel combos")
