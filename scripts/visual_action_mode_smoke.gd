extends SceneTree
## Visual Action Mode smoke (Phase 3.3 MVP UI-Staging).
##
## Prüft:
##   * Pure Helfer in `ui/scripts/presence/visual_action_mode.gd`:
##     Enum-Namen, Parser (kanonisch + Aliasse), `coerce` für unbekannte
##     Ints, `all_modes` Reihenfolge, Labels, Staging-Tabelle je Modus
##     (Flags + Alphas + Monotonie).
##   * `visual_action_preferences.gd`: Load/Save in eine temporäre
##     Config-Datei, Whitelist-Check für unbekannte Werte, Erhaltung
##     fremder Sektionen beim Save.
##   * Defensive Fallbacks: unbekannte Mode-Integer werden bei Save
##     auf den Default geklemmt, unbekannte Mode-Strings in der Datei
##     werden beim Load verworfen.
##
## Ausdrücklich *nicht* Teil dieses Smokes:
##   * keine Scene-Instanziierung der Main-Scene (die deckt der
##     Headless-Bootstrap in run_overlay_verification.sh ab),
##   * keine EventBus-Roundtrips,
##   * keine pixelgenaue Banner-/Overlay-Verifikation — die Staging-
##     Tabelle liefert diskrete Werte, nicht animierte Kurven.
##
## Lauf:
##   godot --headless --path ui --script scripts/visual_action_mode_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh visual-action-mode-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _ModeRef := preload("res://scripts/presence/visual_action_mode.gd")
const _PrefsRef := preload("res://scripts/presence/visual_action_preferences.gd")

const _TMP_CFG_PATH: String = "user://smolit_ui_visual_action_smoke.cfg"

var _fail: int = 0


func _init() -> void:
	_check_names_and_labels()
	_check_parser_canonical_and_aliases()
	_check_parser_unknown_and_empty()
	_check_coerce()
	_check_all_modes_order()
	_check_staging_none()
	_check_staging_minimal()
	_check_staging_guided()
	_check_staging_full()
	_check_staging_monotonicity()
	_check_preferences_roundtrip()
	_check_preferences_rejects_unknown_string()
	_check_preferences_rejects_non_string()
	_check_preferences_save_coerces_unknown_int()
	_check_preferences_preserves_other_section()
	_cleanup_tmp_cfg()

	print("---")
	if _fail == 0:
		print("visual_action_mode smoke: PASS")
		quit(0)
	else:
		print("visual_action_mode smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Enum names / labels -------------------------------------------------


func _check_names_and_labels() -> void:
	_assert(_ModeRef.name_of(_ModeRef.Mode.NONE) == "none",
		"name_of NONE")
	_assert(_ModeRef.name_of(_ModeRef.Mode.MINIMAL_FEEDBACK) == "minimal_feedback",
		"name_of MINIMAL_FEEDBACK")
	_assert(_ModeRef.name_of(_ModeRef.Mode.GUIDED_MOVEMENT) == "guided_movement",
		"name_of GUIDED_MOVEMENT")
	_assert(_ModeRef.name_of(_ModeRef.Mode.FULL_THEATRICAL) == "full_theatrical",
		"name_of FULL_THEATRICAL")
	_assert(_ModeRef.name_of(999) == "minimal_feedback",
		"name_of unknown int falls back to default (defensive)")
	_assert(_ModeRef.label_of(_ModeRef.Mode.MINIMAL_FEEDBACK) == "Minimal feedback",
		"label_of MINIMAL_FEEDBACK")
	_assert(_ModeRef.label_of(999) == "Minimal feedback",
		"label_of unknown int falls back to default (defensive)")


# --- Parser --------------------------------------------------------------


func _check_parser_canonical_and_aliases() -> void:
	# Kanonische Namen müssen funktionieren.
	_assert(_ModeRef.mode_from_string("none") == _ModeRef.Mode.NONE,
		"parser: 'none' → NONE")
	_assert(_ModeRef.mode_from_string("minimal_feedback") == _ModeRef.Mode.MINIMAL_FEEDBACK,
		"parser: 'minimal_feedback' → MINIMAL_FEEDBACK")
	_assert(_ModeRef.mode_from_string("guided_movement") == _ModeRef.Mode.GUIDED_MOVEMENT,
		"parser: 'guided_movement' → GUIDED_MOVEMENT")
	_assert(_ModeRef.mode_from_string("full_theatrical") == _ModeRef.Mode.FULL_THEATRICAL,
		"parser: 'full_theatrical' → FULL_THEATRICAL")
	# Aliasse — bewusst für Env-Convenience erlaubt.
	_assert(_ModeRef.mode_from_string("off") == _ModeRef.Mode.NONE,
		"parser: 'off' alias → NONE")
	_assert(_ModeRef.mode_from_string("min") == _ModeRef.Mode.MINIMAL_FEEDBACK,
		"parser: 'min' alias → MINIMAL_FEEDBACK")
	_assert(_ModeRef.mode_from_string("guide") == _ModeRef.Mode.GUIDED_MOVEMENT,
		"parser: 'guide' alias → GUIDED_MOVEMENT")
	_assert(_ModeRef.mode_from_string("demo") == _ModeRef.Mode.FULL_THEATRICAL,
		"parser: 'demo' alias → FULL_THEATRICAL")
	# Whitespace und case insensitivity.
	_assert(_ModeRef.mode_from_string("  GUIDED_MOVEMENT  ") == _ModeRef.Mode.GUIDED_MOVEMENT,
		"parser: whitespace + uppercase normalized")


func _check_parser_unknown_and_empty() -> void:
	_assert(_ModeRef.mode_from_string("") == _ModeRef.DEFAULT,
		"parser: empty → default")
	_assert(_ModeRef.mode_from_string("nonsense") == _ModeRef.DEFAULT,
		"parser: unknown string → default")
	_assert(_ModeRef.mode_from_string("42") == _ModeRef.DEFAULT,
		"parser: numeric string → default")


# --- coerce / all_modes --------------------------------------------------


func _check_coerce() -> void:
	_assert(_ModeRef.coerce(_ModeRef.Mode.NONE) == _ModeRef.Mode.NONE,
		"coerce: known int → unchanged")
	_assert(_ModeRef.coerce(_ModeRef.Mode.FULL_THEATRICAL) == _ModeRef.Mode.FULL_THEATRICAL,
		"coerce: FULL_THEATRICAL → unchanged")
	_assert(_ModeRef.coerce(-5) == _ModeRef.DEFAULT,
		"coerce: negative int → default")
	_assert(_ModeRef.coerce(99) == _ModeRef.DEFAULT,
		"coerce: overflow int → default")


func _check_all_modes_order() -> void:
	var modes: Array = _ModeRef.all_modes()
	_assert(modes.size() == 4, "all_modes returns four entries")
	_assert(modes[0] == _ModeRef.Mode.NONE, "all_modes[0] == NONE")
	_assert(modes[1] == _ModeRef.Mode.MINIMAL_FEEDBACK, "all_modes[1] == MINIMAL_FEEDBACK")
	_assert(modes[2] == _ModeRef.Mode.GUIDED_MOVEMENT, "all_modes[2] == GUIDED_MOVEMENT")
	_assert(modes[3] == _ModeRef.Mode.FULL_THEATRICAL, "all_modes[3] == FULL_THEATRICAL")


# --- Staging tables ------------------------------------------------------


func _check_staging_none() -> void:
	var s: Dictionary = _ModeRef.staging_for(_ModeRef.Mode.NONE)
	_assert(bool(s.get("banner_visible", true)) == false,
		"staging NONE: banner_visible=false")
	_assert(float(s.get("banner_alpha", 1.0)) == 0.0,
		"staging NONE: banner_alpha=0.0")
	_assert(bool(s.get("workflow_overlay_allowed", true)) == false,
		"staging NONE: workflow_overlay_allowed=false")
	_assert(float(s.get("workflow_overlay_alpha", 1.0)) == 0.0,
		"staging NONE: workflow_overlay_alpha=0.0")


func _check_staging_minimal() -> void:
	var s: Dictionary = _ModeRef.staging_for(_ModeRef.Mode.MINIMAL_FEEDBACK)
	_assert(bool(s.get("banner_visible", false)) == true,
		"staging MINIMAL: banner_visible=true")
	_assert(float(s.get("banner_alpha", 0.0)) > 0.0
		and float(s.get("banner_alpha", 0.0)) < 1.0,
		"staging MINIMAL: banner_alpha is in (0, 1) — dezent")
	_assert(bool(s.get("workflow_overlay_allowed", true)) == false,
		"staging MINIMAL: workflow_overlay_allowed=false (ruhig, nur Banner)")


func _check_staging_guided() -> void:
	var s: Dictionary = _ModeRef.staging_for(_ModeRef.Mode.GUIDED_MOVEMENT)
	_assert(bool(s.get("banner_visible", false)) == true,
		"staging GUIDED: banner_visible=true")
	_assert(bool(s.get("workflow_overlay_allowed", false)) == true,
		"staging GUIDED: workflow_overlay_allowed=true")
	_assert(float(s.get("workflow_overlay_alpha", 0.0)) > 0.0
		and float(s.get("workflow_overlay_alpha", 0.0)) <= 1.0,
		"staging GUIDED: workflow_overlay_alpha in (0, 1]")


func _check_staging_full() -> void:
	var s: Dictionary = _ModeRef.staging_for(_ModeRef.Mode.FULL_THEATRICAL)
	_assert(bool(s.get("banner_visible", false)) == true,
		"staging FULL: banner_visible=true")
	_assert(float(s.get("banner_alpha", 0.0)) == 1.0,
		"staging FULL: banner_alpha=1.0 (volle Intensität)")
	_assert(bool(s.get("workflow_overlay_allowed", false)) == true,
		"staging FULL: workflow_overlay_allowed=true")
	_assert(float(s.get("workflow_overlay_alpha", 0.0)) == 1.0,
		"staging FULL: workflow_overlay_alpha=1.0")


func _check_staging_monotonicity() -> void:
	# Banner-Alpha darf von NONE bis FULL nur monoton steigen.
	var banner_alphas: Array = [
		float(_ModeRef.staging_for(_ModeRef.Mode.NONE)["banner_alpha"]),
		float(_ModeRef.staging_for(_ModeRef.Mode.MINIMAL_FEEDBACK)["banner_alpha"]),
		float(_ModeRef.staging_for(_ModeRef.Mode.GUIDED_MOVEMENT)["banner_alpha"]),
		float(_ModeRef.staging_for(_ModeRef.Mode.FULL_THEATRICAL)["banner_alpha"]),
	]
	var monotonic: bool = true
	for i in range(banner_alphas.size() - 1):
		if banner_alphas[i] > banner_alphas[i + 1]:
			monotonic = false
			break
	_assert(monotonic,
		"staging: banner_alpha grows monotonically from NONE to FULL")

	# Overlay-Alpha darf ebenfalls nur monoton steigen.
	var overlay_alphas: Array = [
		float(_ModeRef.staging_for(_ModeRef.Mode.NONE)["workflow_overlay_alpha"]),
		float(_ModeRef.staging_for(_ModeRef.Mode.MINIMAL_FEEDBACK)["workflow_overlay_alpha"]),
		float(_ModeRef.staging_for(_ModeRef.Mode.GUIDED_MOVEMENT)["workflow_overlay_alpha"]),
		float(_ModeRef.staging_for(_ModeRef.Mode.FULL_THEATRICAL)["workflow_overlay_alpha"]),
	]
	var overlay_monotonic: bool = true
	for i in range(overlay_alphas.size() - 1):
		if overlay_alphas[i] > overlay_alphas[i + 1]:
			overlay_monotonic = false
			break
	_assert(overlay_monotonic,
		"staging: workflow_overlay_alpha grows monotonically from NONE to FULL")


# --- Preferences ---------------------------------------------------------


func _check_preferences_roundtrip() -> void:
	_cleanup_tmp_cfg()
	var err: int = _PrefsRef.save_preferences(_ModeRef.Mode.GUIDED_MOVEMENT, _TMP_CFG_PATH)
	_assert(err == OK, "save_preferences(GUIDED) returns OK")
	var loaded: Dictionary = _PrefsRef.load_preferences(_TMP_CFG_PATH)
	_assert(loaded.has(_PrefsRef.KEY_VISUAL_ACTION_MODE),
		"load_preferences: key present after save")
	_assert(int(loaded[_PrefsRef.KEY_VISUAL_ACTION_MODE]) == _ModeRef.Mode.GUIDED_MOVEMENT,
		"load_preferences: value matches what was saved")


func _check_preferences_rejects_unknown_string() -> void:
	_cleanup_tmp_cfg()
	# Eine Datei mit einem unbekannten Modus-Namen präparieren (und einem
	# kanonischen Namen daneben), um zu prüfen: der unbekannte Wert wird
	# verworfen, die Datei aber nicht „zerrissen".
	var cfg := ConfigFile.new()
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_VISUAL_ACTION_MODE, "nonsense_mode")
	cfg.save(_TMP_CFG_PATH)
	var loaded: Dictionary = _PrefsRef.load_preferences(_TMP_CFG_PATH)
	_assert(not loaded.has(_PrefsRef.KEY_VISUAL_ACTION_MODE),
		"load_preferences: unknown string value is ignored (no key in result)")


func _check_preferences_rejects_non_string() -> void:
	_cleanup_tmp_cfg()
	var cfg := ConfigFile.new()
	# Absichtlich als Integer statt String abgelegt — muss verworfen werden.
	cfg.set_value(_PrefsRef.SECTION, _PrefsRef.KEY_VISUAL_ACTION_MODE, 2)
	cfg.save(_TMP_CFG_PATH)
	var loaded: Dictionary = _PrefsRef.load_preferences(_TMP_CFG_PATH)
	_assert(not loaded.has(_PrefsRef.KEY_VISUAL_ACTION_MODE),
		"load_preferences: non-string value is ignored")


func _check_preferences_save_coerces_unknown_int() -> void:
	_cleanup_tmp_cfg()
	# Ein unbekannter Mode-Integer wird beim Speichern defensiv auf den
	# Default geklemmt — und anschließend auch wieder ladbar als Default.
	var err: int = _PrefsRef.save_preferences(999, _TMP_CFG_PATH)
	_assert(err == OK, "save_preferences(unknown int) returns OK")
	var loaded: Dictionary = _PrefsRef.load_preferences(_TMP_CFG_PATH)
	_assert(loaded.has(_PrefsRef.KEY_VISUAL_ACTION_MODE),
		"load after unknown-int save: key present")
	_assert(int(loaded[_PrefsRef.KEY_VISUAL_ACTION_MODE]) == _ModeRef.DEFAULT,
		"load after unknown-int save: value clamped to DEFAULT")


func _check_preferences_preserves_other_section() -> void:
	_cleanup_tmp_cfg()
	# Andere Sektion (z. B. [avatar] x/y) muss beim Save erhalten bleiben.
	var cfg := ConfigFile.new()
	cfg.set_value("avatar", "x", 123.0)
	cfg.set_value("avatar", "y", 456.0)
	cfg.save(_TMP_CFG_PATH)
	var err: int = _PrefsRef.save_preferences(_ModeRef.Mode.FULL_THEATRICAL, _TMP_CFG_PATH)
	_assert(err == OK, "save_preferences with pre-existing section: OK")

	var cfg2 := ConfigFile.new()
	cfg2.load(_TMP_CFG_PATH)
	_assert(cfg2.has_section("avatar"),
		"preserve: other section [avatar] still present after save")
	_assert(float(cfg2.get_value("avatar", "x", -1.0)) == 123.0,
		"preserve: [avatar] x unchanged")
	_assert(float(cfg2.get_value("avatar", "y", -1.0)) == 456.0,
		"preserve: [avatar] y unchanged")
	_assert(cfg2.has_section(_PrefsRef.SECTION),
		"preserve: new [presence] section written alongside")


func _cleanup_tmp_cfg() -> void:
	if FileAccess.file_exists(_TMP_CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TMP_CFG_PATH))
