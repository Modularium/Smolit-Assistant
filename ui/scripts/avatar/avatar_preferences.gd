extends RefCounted
## Avatar Appearance Preferences (Phase A — Smolit Salamander only).
##
## Sehr kleine lokale UI-Persistenz für die drei Appearance-Felder, die
## Phase A überhaupt hat: Theme / Behavior Profile / Intensity. Nichts
## anderes. Kein Nutzerprofil, kein Account, kein Sync, keine Templates.
##
## Persistiert wird in `user://smolit_ui.cfg` — derselben Datei, in der
## der Avatar schon seine Position ablegt. Appearance bekommt dort
## eigenen Abschnitt `[avatar_appearance]`, damit Positions-Keys
## (`[avatar] x/y`) und Appearance-Keys sich nicht kollidieren.
##
## Prioritätsreihenfolge (wichtig und bindend):
##
##   1. Explizite Env-Variable (`SMOLIT_AVATAR_THEME` / `…_PROFILE` /
##      `…_INTENSITY`). Env hat immer das letzte Wort.
##   2. Lokal gespeicherte Preference.
##   3. Harter Default (`ThemePreset.DEFAULT` / `BehaviorProfile.CALM` /
##      `intensity=1.0`).
##
## Diese Reihenfolge wird im Avatar-Controller realisiert; dieses Modul
## liefert nur den Preferences-Teil. Ohne Config-Datei und ohne Env
## verhält sich der Avatar byte-identisch zum vor-PR-Stand.
##
## Robustheit:
##   * Datei fehlt / lässt sich nicht lesen → leeres Dict (keine Keys
##     gesetzt), Aufrufer fällt auf Default zurück.
##   * Einzelne Werte ungültig oder falsch getypt → genau dieser Key
##     fehlt im Ergebnis-Dict; eine `push_warning`-Zeile dokumentiert
##     den Fall, ohne den Start zu verzögern.
##   * Save-Pfad sanitisiert (Enum-Clamping via make_appearance-
##     Helpers, Intensity via clampf), damit eine kaputte Live-Eingabe
##     niemals als kaputter Wert landet.

class_name SmolitAvatarPreferences

const _AppearanceRef := preload("res://scripts/avatar/avatar_appearance.gd")

const DEFAULT_PATH: String = "user://smolit_ui.cfg"
const SECTION: String = "avatar_appearance"
const KEY_THEME: String = "theme"
const KEY_PROFILE: String = "profile"
const KEY_INTENSITY: String = "intensity"


## Lädt die gespeicherten Appearance-Preferences. Gibt ein (ggf.
## teilweise gefülltes) Dict zurück mit den Keys `theme` (int),
## `profile` (int) und/oder `intensity` (float). Fehlende / ungültige
## Felder sind schlicht nicht enthalten — der Aufrufer fällt dann auf
## Env oder harten Default zurück.
##
## `path` ist per Default `user://smolit_ui.cfg`; der Parameter ist
## für Tests expliziert (headless Smoke kann so eine temporäre Datei
## verwenden, ohne die echte Nutzerkonfiguration anzufassen).
static func load_preferences(path: String = DEFAULT_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return {}
	if not cfg.has_section(SECTION):
		return {}

	var result: Dictionary = {}

	if cfg.has_section_key(SECTION, KEY_THEME):
		var raw: Variant = cfg.get_value(SECTION, KEY_THEME)
		if typeof(raw) == TYPE_STRING:
			var as_str := String(raw)
			# `theme_from_string` fällt bei unbekannten Strings selbst auf
			# DEFAULT zurück; wir nehmen das Ergebnis nur auf, wenn der
			# gespeicherte String auch wirklich einer der bekannten Namen
			# war. Sonst fehlt `theme` im Ergebnis, und der Aufrufer
			# entscheidet (Env / Default).
			if _is_known_theme_name(as_str):
				result[KEY_THEME] = _AppearanceRef.theme_from_string(as_str)
			else:
				push_warning("avatar_preferences: unknown theme '%s' in %s — ignored." % [as_str, path])
		else:
			push_warning("avatar_preferences: theme is not a string in %s — ignored." % path)

	if cfg.has_section_key(SECTION, KEY_PROFILE):
		var raw_p: Variant = cfg.get_value(SECTION, KEY_PROFILE)
		if typeof(raw_p) == TYPE_STRING:
			var as_str_p := String(raw_p)
			if _is_known_profile_name(as_str_p):
				result[KEY_PROFILE] = _AppearanceRef.profile_from_string(as_str_p)
			else:
				push_warning("avatar_preferences: unknown profile '%s' in %s — ignored." % [as_str_p, path])
		else:
			push_warning("avatar_preferences: profile is not a string in %s — ignored." % path)

	if cfg.has_section_key(SECTION, KEY_INTENSITY):
		var raw_i: Variant = cfg.get_value(SECTION, KEY_INTENSITY)
		if typeof(raw_i) == TYPE_FLOAT or typeof(raw_i) == TYPE_INT:
			var v := float(raw_i)
			if v >= _AppearanceRef.INTENSITY_MIN - 0.0001 \
					and v <= _AppearanceRef.INTENSITY_MAX + 0.0001:
				result[KEY_INTENSITY] = clampf(
					v, _AppearanceRef.INTENSITY_MIN, _AppearanceRef.INTENSITY_MAX,
				)
			else:
				push_warning(
					"avatar_preferences: intensity %.3f outside [%.2f, %.2f] in %s — ignored." % [
						v, _AppearanceRef.INTENSITY_MIN, _AppearanceRef.INTENSITY_MAX, path,
					],
				)
		else:
			push_warning("avatar_preferences: intensity is not a number in %s — ignored." % path)

	return result


## Schreibt theme / profile / intensity in den Appearance-Abschnitt.
## Bestehende andere Sektionen (`[avatar]` mit x/y) bleiben erhalten,
## weil wir die Datei vor dem Schreiben laden. Gibt den `ConfigFile.save`-
## Statuscode zurück (OK bei Erfolg).
static func save_preferences(
	theme: int, profile: int, intensity: float, path: String = DEFAULT_PATH,
) -> int:
	var cfg := ConfigFile.new()
	# Vorhandene Datei laden, damit `[avatar] x=…/y=…` nicht verloren
	# geht. Fehler hier sind egal — wir schreiben dann eine neue Datei.
	cfg.load(path)

	var clean_theme := theme if _AppearanceRef.theme_from_string(
		_AppearanceRef.theme_name(theme),
	) == theme else _AppearanceRef.DEFAULT_THEME
	var clean_profile := profile if _AppearanceRef.profile_from_string(
		_AppearanceRef.profile_name(profile),
	) == profile else _AppearanceRef.DEFAULT_PROFILE
	var clean_intensity := clampf(
		intensity, _AppearanceRef.INTENSITY_MIN, _AppearanceRef.INTENSITY_MAX,
	)

	cfg.set_value(SECTION, KEY_THEME, _AppearanceRef.theme_name(clean_theme))
	cfg.set_value(SECTION, KEY_PROFILE, _AppearanceRef.profile_name(clean_profile))
	cfg.set_value(SECTION, KEY_INTENSITY, clean_intensity)

	return cfg.save(path)


## Entfernt den Appearance-Abschnitt wieder, falls jemand die
## Preferences zurücksetzen will. Keine UI nutzt das im MVP; es ist
## als kleines Aufräum-Utility da, damit spätere Tools / Tests die
## Datei sauber leeren können, ohne `[avatar] x/y` zu verlieren.
static func clear_preferences(path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return OK
	if not cfg.has_section(SECTION):
		return OK
	cfg.erase_section(SECTION)
	return cfg.save(path)


# --- Internals -----------------------------------------------------------


static func _is_known_theme_name(value: String) -> bool:
	match value.strip_edges().to_lower():
		"default", "soft", "tech", "minimal":
			return true
		_:
			return false


static func _is_known_profile_name(value: String) -> bool:
	match value.strip_edges().to_lower():
		"calm", "lively", "reserved":
			return true
		_:
			return false
