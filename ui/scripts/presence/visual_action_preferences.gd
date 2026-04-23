extends RefCounted
## Visual Action Mode — lokale UI-Preferences.
##
## Kleiner symmetrischer Nachbau zu
## `ui/scripts/avatar/avatar_preferences.gd`, aber für Presence-Seite.
## Persistiert **ausschließlich** den gewählten Visual Action Mode —
## nicht mehr, nicht weniger. Kein Settings-System, kein Profil-Store,
## kein Cloud-Sync.
##
## Datei:
##   `user://smolit_ui.cfg`, Sektion `[presence]`, Key `visual_action_mode`.
##   Das ist dieselbe Datei, in der Avatar-Position und -Appearance
##   bereits liegen. Eigener Abschnitt, damit Keys sich nicht
##   überlappen.
##
## Prioritätsreihenfolge (bindend, wird im Aufrufer realisiert):
##
##   1. Env-Variable `SMOLIT_UI_VISUAL_ACTION_MODE`. Unbekannte Werte
##      fallen im Parser auf Default.
##   2. Lokal gespeicherte Preference.
##   3. Harter Default (`VisualActionMode.DEFAULT`).
##
## Robustheit:
##   * Datei fehlt / lässt sich nicht laden → leeres Dict zurück.
##   * Ungültiger Wert in der Datei → Key wird verworfen, `push_warning`
##     dokumentiert den Fall. Aufrufer fällt zurück.

class_name SmolitVisualActionPreferences

const _ModeRef := preload("res://scripts/presence/visual_action_mode.gd")

const DEFAULT_PATH: String = "user://smolit_ui.cfg"
const SECTION: String = "presence"
const KEY_VISUAL_ACTION_MODE: String = "visual_action_mode"


## Lädt die gespeicherte Präferenz. Gibt ein Dict mit — wenn gesetzt —
## dem Key `visual_action_mode` (int) zurück. Fehlende / ungültige
## Einträge resultieren in einem leeren Dict, damit der Aufrufer sicher
## auf Env / Default zurückfallen kann.
static func load_preferences(path: String = DEFAULT_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return {}
	if not cfg.has_section(SECTION):
		return {}
	if not cfg.has_section_key(SECTION, KEY_VISUAL_ACTION_MODE):
		return {}
	var raw: Variant = cfg.get_value(SECTION, KEY_VISUAL_ACTION_MODE)
	if typeof(raw) != TYPE_STRING:
		push_warning("visual_action_preferences: value is not a string in %s — ignored." % path)
		return {}
	var as_str := String(raw)
	if not _is_known_name(as_str):
		push_warning("visual_action_preferences: unknown mode '%s' in %s — ignored." % [as_str, path])
		return {}
	return {KEY_VISUAL_ACTION_MODE: _ModeRef.mode_from_string(as_str)}


## Schreibt den Modus. Unbekannte int-Werte werden defensiv geklemmt
## (coerce → Default), damit eine kaputte Live-Eingabe nicht als
## kaputter Wert landet. Erhält andere Sektionen (Appearance, Avatar-
## Position) in derselben Datei.
static func save_preferences(mode: int, path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	# Vorhandene Datei laden, damit andere Sektionen erhalten bleiben.
	# Fehler hier ignorieren — wir schreiben dann eine neue Datei.
	cfg.load(path)
	var clean_mode: int = _ModeRef.coerce(mode)
	cfg.set_value(SECTION, KEY_VISUAL_ACTION_MODE, _ModeRef.name_of(clean_mode))
	return cfg.save(path)


## Aufräum-Utility (analog `avatar_preferences.clear_preferences`).
## Entfernt nur den Presence-Abschnitt, andere Sektionen bleiben.
static func clear_preferences(path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return OK
	if not cfg.has_section(SECTION):
		return OK
	cfg.erase_section(SECTION)
	return cfg.save(path)


# --- Internals -----------------------------------------------------------


static func _is_known_name(value: String) -> bool:
	# Kanonische Namen. Alias-Eingaben (`off`, `min`, `guide`, `demo`)
	# sind im Env-Parser erlaubt, aber als persistierter Wert sollen nur
	# kanonische Namen landen — das verhindert, dass eine alte
	# Alias-Datei unbemerkt als Referenz durchschlägt.
	match value.strip_edges().to_lower():
		"none", "minimal_feedback", "guided_movement", "full_theatrical":
			return true
		_:
			return false
