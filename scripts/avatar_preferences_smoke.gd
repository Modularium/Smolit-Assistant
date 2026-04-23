extends SceneTree
## Avatar-Preferences-Smoketest (Phase A).
##
## Prüft die kleine lokale UI-Persistenz aus
## `ui/scripts/avatar/avatar_preferences.gd` ohne Scene-Tree. Fokus:
##
##   * Fehlende Datei → leeres Dict (fällt auf Default zurück).
##   * Round-Trip: save → load liefert die gleichen Werte zurück.
##   * Ungültige Werte (falsche Typen, unbekannte Strings, out-of-range
##     Intensity) werden ignoriert; gültige Werte aus derselben Datei
##     bleiben erhalten.
##   * Sanitisierung beim Speichern: unbekannter Int-Enum → Default.
##   * Fremder Config-Abschnitt (`[avatar] x/y`) überlebt einen
##     Appearance-Save.
##   * `clear_preferences` entfernt nur den Appearance-Abschnitt.
##
## Lauf:
##   godot --headless --path ui --script scripts/avatar_preferences_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh avatar-preferences-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _PrefsRef := preload("res://scripts/avatar/avatar_preferences.gd")
const _AppearanceRef := preload("res://scripts/avatar/avatar_appearance.gd")
const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")

var _fail: int = 0
var _path: String = "user://smolit_preferences_smoke.cfg"


func _init() -> void:
	_reset_file()

	_check_missing_file()
	_check_round_trip()
	_check_invalid_values_ignored()
	_check_partial_file()
	_check_save_sanitizes_enums()
	_check_save_preserves_foreign_section()
	_check_clear_preferences()
	_check_intensity_clamp_on_save()
	_check_identity_invalid_values_ignored()
	_check_identity_alias_not_accepted_as_stored()

	_reset_file()

	print("---")
	if _fail == 0:
		print("avatar_preferences smoke: PASS")
		quit(0)
	else:
		print("avatar_preferences smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


func _reset_file() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


# --- Cases ---------------------------------------------------------------


func _check_missing_file() -> void:
	_reset_file()
	var prefs := _PrefsRef.load_preferences(_path)
	_assert(prefs.is_empty(),
		"missing file → empty dict (no keys)")


func _check_round_trip() -> void:
	_reset_file()
	var err: int = _PrefsRef.save_preferences(
		_AppearanceRef.ThemePreset.TECH,
		_AppearanceRef.BehaviorProfile.LIVELY,
		1.3,
		_IdentityRef.Identity.ROBOT_HEAD,
		_path,
	)
	_assert(err == OK, "save_preferences returns OK")

	var prefs := _PrefsRef.load_preferences(_path)
	_assert(int(prefs.get("theme", -1)) == _AppearanceRef.ThemePreset.TECH,
		"round-trip: theme TECH")
	_assert(int(prefs.get("profile", -1)) == _AppearanceRef.BehaviorProfile.LIVELY,
		"round-trip: profile LIVELY")
	_assert(abs(float(prefs.get("intensity", -1.0)) - 1.3) < 0.001,
		"round-trip: intensity 1.3")
	_assert(int(prefs.get("identity", -1)) == _IdentityRef.Identity.ROBOT_HEAD,
		"round-trip: identity ROBOT_HEAD")


func _check_invalid_values_ignored() -> void:
	# Manuell eine kaputte Datei bauen: unbekanntes theme-String,
	# profile als Int statt String, intensity out-of-range.
	_reset_file()
	var cfg := ConfigFile.new()
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_THEME, "purple-polkadot")
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_PROFILE, 42)
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_INTENSITY, 99.0)
	var saved := cfg.save(_path)
	_assert(saved == OK, "invalid-file setup: wrote test config")

	var prefs := _PrefsRef.load_preferences(_path)
	_assert(not prefs.has("theme"),
		"invalid theme string → key absent from result")
	_assert(not prefs.has("profile"),
		"non-string profile → key absent from result")
	_assert(not prefs.has("intensity"),
		"out-of-range intensity → key absent from result")


func _check_partial_file() -> void:
	# Nur ein gültiger Key; die anderen beiden bleiben im Ergebnis leer,
	# damit der Caller pro Feld auf Env / Default fallen kann.
	_reset_file()
	var cfg := ConfigFile.new()
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_PROFILE, "reserved")
	cfg.save(_path)

	var prefs := _PrefsRef.load_preferences(_path)
	_assert(not prefs.has("theme"),
		"partial file: theme absent")
	_assert(int(prefs.get("profile", -1)) == _AppearanceRef.BehaviorProfile.RESERVED,
		"partial file: profile RESERVED loaded")
	_assert(not prefs.has("intensity"),
		"partial file: intensity absent")


func _check_save_sanitizes_enums() -> void:
	_reset_file()
	# Unbekannter Theme-Int (z. B. aus zukünftigem Build) → Default.
	var err: int = _PrefsRef.save_preferences(99, 99, 1.0, 99, _path)
	_assert(err == OK, "save_preferences with unknown ints: OK")

	var prefs := _PrefsRef.load_preferences(_path)
	_assert(int(prefs.get("theme", -1)) == _AppearanceRef.DEFAULT_THEME,
		"save sanitizes unknown theme int → DEFAULT")
	_assert(int(prefs.get("profile", -1)) == _AppearanceRef.DEFAULT_PROFILE,
		"save sanitizes unknown profile int → CALM")
	_assert(int(prefs.get("identity", -1)) == _IdentityRef.DEFAULT,
		"save sanitizes unknown identity int → SMOLIT_SALAMANDER")


func _check_save_preserves_foreign_section() -> void:
	# Die Appearance-Persistenz teilt sich `user://smolit_ui.cfg` mit
	# der Avatar-Position (Sektion `[avatar]`). Der Save darf Fremd-
	# Sektionen nicht mitlöschen.
	_reset_file()
	var cfg := ConfigFile.new()
	cfg.set_value("avatar", "x", 123.0)
	cfg.set_value("avatar", "y", 456.0)
	cfg.save(_path)

	_PrefsRef.save_preferences(
		_AppearanceRef.ThemePreset.SOFT,
		_AppearanceRef.BehaviorProfile.CALM,
		1.0,
		_IdentityRef.DEFAULT,
		_path,
	)

	var after := ConfigFile.new()
	after.load(_path)
	_assert(after.has_section_key("avatar", "x")
			and abs(float(after.get_value("avatar", "x", -1.0)) - 123.0) < 0.001,
		"save preserves foreign [avatar] x")
	_assert(after.has_section_key("avatar", "y")
			and abs(float(after.get_value("avatar", "y", -1.0)) - 456.0) < 0.001,
		"save preserves foreign [avatar] y")
	_assert(after.has_section_key(_PrefsRef.SECTION, _PrefsRef.KEY_THEME),
		"save writes appearance section alongside foreign")


func _check_clear_preferences() -> void:
	_reset_file()
	var cfg := ConfigFile.new()
	cfg.set_value("avatar", "x", 10.0)
	cfg.save(_path)
	_PrefsRef.save_preferences(
		_AppearanceRef.ThemePreset.MINIMAL,
		_AppearanceRef.BehaviorProfile.RESERVED,
		0.8,
		_IdentityRef.DEFAULT,
		_path,
	)
	var err: int = _PrefsRef.clear_preferences(_path)
	_assert(err == OK, "clear_preferences returns OK")

	var after := ConfigFile.new()
	after.load(_path)
	_assert(not after.has_section(_PrefsRef.SECTION),
		"clear removes appearance section")
	_assert(after.has_section_key("avatar", "x"),
		"clear keeps foreign [avatar] section")


func _check_intensity_clamp_on_save() -> void:
	# Input-Intensity jenseits des erlaubten Bereichs wird beim Save
	# auf Min/Max gedrückt — keine kaputten Werte landen in der Datei.
	_reset_file()
	_PrefsRef.save_preferences(
		_AppearanceRef.ThemePreset.DEFAULT,
		_AppearanceRef.BehaviorProfile.CALM,
		99.0,
		_IdentityRef.DEFAULT,
		_path,
	)
	var prefs_hi := _PrefsRef.load_preferences(_path)
	_assert(abs(float(prefs_hi.get("intensity", -1.0)) - _AppearanceRef.INTENSITY_MAX) < 0.001,
		"save clamps intensity 99.0 → INTENSITY_MAX")

	_reset_file()
	_PrefsRef.save_preferences(
		_AppearanceRef.ThemePreset.DEFAULT,
		_AppearanceRef.BehaviorProfile.CALM,
		-5.0,
		_IdentityRef.DEFAULT,
		_path,
	)
	var prefs_lo := _PrefsRef.load_preferences(_path)
	_assert(abs(float(prefs_lo.get("intensity", -1.0)) - _AppearanceRef.INTENSITY_MIN) < 0.001,
		"save clamps intensity -5.0 → INTENSITY_MIN")


func _check_identity_invalid_values_ignored() -> void:
	# Zusätzliche Phase-B-Robustheit: ein kaputter identity-Eintrag
	# (unbekannter String, falscher Typ) darf beim Laden nicht zu
	# einer stillen Figur-Änderung führen. Stattdessen wird der Key
	# aus dem Ergebnis-Dict weggelassen und der Controller fällt auf
	# Env / Default zurück.
	_reset_file()
	var cfg := ConfigFile.new()
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_IDENTITY, "purple-dragon")
	cfg.save(_path)
	var prefs_unknown := _PrefsRef.load_preferences(_path)
	_assert(not prefs_unknown.has("identity"),
		"invalid identity string → key absent from result")

	_reset_file()
	var cfg2 := ConfigFile.new()
	cfg2.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_IDENTITY, 7)
	cfg2.save(_path)
	var prefs_typed := _PrefsRef.load_preferences(_path)
	_assert(not prefs_typed.has("identity"),
		"non-string identity → key absent from result")


func _check_identity_alias_not_accepted_as_stored() -> void:
	# Aliasse wie "smolit" oder "robot" werden vom Parser akzeptiert
	# (Komfort für Env-Variable), aber nicht als kanonisch gespeicherte
	# Form. So verhindern wir, dass eine manuell gepflegte Config-Datei
	# mit Alias-Name unbemerkt als valider Preference-Eintrag durch-
	# schlägt — stattdessen erzwingen wir die kanonische Schreibweise.
	_reset_file()
	var cfg := ConfigFile.new()
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_IDENTITY, "smolit")
	cfg.save(_path)
	var prefs := _PrefsRef.load_preferences(_path)
	_assert(not prefs.has("identity"),
		"alias 'smolit' (non-canonical) → key absent from result")

	# Aber die kanonische Schreibweise funktioniert sauber.
	_reset_file()
	var cfg2 := ConfigFile.new()
	cfg2.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_IDENTITY, "orb")
	cfg2.save(_path)
	var prefs2 := _PrefsRef.load_preferences(_path)
	_assert(int(prefs2.get("identity", -1)) == _IdentityRef.Identity.ORB,
		"canonical identity 'orb' → loaded as ORB")

	# Phase-B-Hardening: auch das vierte kuratierte Template (humanoid_head)
	# läuft sauber als Preference-String hin und zurück.
	_reset_file()
	_PrefsRef.save_preferences(
		_AppearanceRef.ThemePreset.SOFT,
		_AppearanceRef.BehaviorProfile.CALM,
		1.0,
		_IdentityRef.Identity.HUMANOID_HEAD,
		_path,
	)
	var prefs_humanoid := _PrefsRef.load_preferences(_path)
	_assert(int(prefs_humanoid.get("identity", -1)) == _IdentityRef.Identity.HUMANOID_HEAD,
		"round-trip: identity HUMANOID_HEAD")
