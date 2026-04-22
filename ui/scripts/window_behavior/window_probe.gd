extends RefCounted
## Linux Window Behavior — Transparency / Click-through Probe (Phase 3b Spike v1)
##
## Opt-in-Testpfad. Läuft **nur**, wenn `SMOLIT_WINDOW_PROBE=1` gesetzt
## ist. Zweck: ehrlich herausfinden, was der aktuelle Godot-Build unter
## der aktuellen Linux-Session mit Transparenz und Click-through
## *tatsächlich* tut — ohne der restlichen Presence-Logik etwas
## aufzuzwingen.
##
## Wichtige Selbstbeschränkungen:
##   * kein zweites State-System, kein neuer Presence-Mode
##   * keine dauerhafte Fensteränderung: Flags werden gesetzt,
##     ausgelesen und optional nach kurzer Zeit wieder zurückgesetzt
##   * keine IPC-/Core-Interaktion, keine Emissions auf dem EventBus
##   * keine Portal-Aufrufe, keine X11-/Wayland-Objekte
##   * Always-on-top wird in dieser Phase bewusst *nicht* gesetzt —
##     die Capability-Analyse markiert es zu Recht als unzuverlässig
##     unter GNOME/Wayland, und wir wollen dieses Versprechen nicht
##     faken.
##
## Kapazitäts-Snapshot vor dem Probe, Ergebnis-Snapshot nach jedem
## Flag-Write. Alles landet im Log — kein UI-Artefakt.

class_name SmolitWindowProbe

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")

const ENABLE_ENV_VAR: String = "SMOLIT_WINDOW_PROBE"
const REVERT_ENV_VAR: String = "SMOLIT_WINDOW_PROBE_REVERT"


## Führt den Probe aus, falls der Nutzer ihn aktiviert hat. Rückgabe:
## leeres Dict, wenn nichts passiert ist; sonst das Probe-Ergebnis.
static func run_if_enabled() -> Dictionary:
	if not is_enabled():
		return {}
	return run_now()


static func is_enabled() -> bool:
	var raw := OS.get_environment(ENABLE_ENV_VAR).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


## Revert-Default ist `true`: ein Probe soll die laufende UI nicht
## dauerhaft click-through machen. Wer den Effekt stehen lassen will,
## setzt `SMOLIT_WINDOW_PROBE_REVERT=0`.
static func _should_revert() -> bool:
	var raw := OS.get_environment(REVERT_ENV_VAR).strip_edges().to_lower()
	if raw == "":
		return true
	return not (raw == "0" or raw == "false" or raw == "no")


## Führt den Probe unabhängig vom Env-Flag aus — hilfreich für
## Debug-Aufrufe aus einer Konsole / aus main.gd. Der normale Pfad
## bleibt `run_if_enabled()`.
static func run_now() -> Dictionary:
	var capabilities: Dictionary = _CapabilitiesRef.detect()

	print(_CapabilitiesRef.format_report(capabilities))
	print("[window_behavior] probe: start (revert=%s)" % _should_revert())

	var transparency_probe := _probe_transparency(capabilities)
	var passthrough_probe := _probe_click_through(capabilities)

	if _should_revert():
		_revert_probe_changes(transparency_probe, passthrough_probe)

	var result := {
		"capabilities": capabilities,
		"transparency": transparency_probe,
		"click_through": passthrough_probe,
		"reverted": _should_revert(),
	}
	print("[window_behavior] probe: done")
	return result


# --- Transparency --------------------------------------------------------

static func _probe_transparency(capabilities: Dictionary) -> Dictionary:
	var cap: Dictionary = capabilities.get("transparency", {})
	var status := int(cap.get("status", _CapabilitiesRef.Status.UNKNOWN))
	if status == _CapabilitiesRef.Status.UNSUPPORTED:
		# Ohne `per_pixel_transparency/allowed` hat ein Runtime-Set keinen
		# sichtbaren Effekt — wir schreiben das nur ins Log und lassen
		# das Flag in Ruhe.
		return {
			"attempted": false,
			"requested": false,
			"observed": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT),
			"note": "project setting required at load time; runtime toggle alone is not enough",
		}

	var previous: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var observed: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT)
	print("[window_behavior] transparency: requested=true observed=%s" % observed)
	return {
		"attempted": true,
		"previous": previous,
		"requested": true,
		"observed": observed,
		"note": "flag reflects Godot-side state; actual pixel alpha still depends on viewport transparent_bg + compositor",
	}


# --- Click-through / mouse passthrough -----------------------------------

static func _probe_click_through(capabilities: Dictionary) -> Dictionary:
	var cap: Dictionary = capabilities.get("click_through", {})
	var status := int(cap.get("status", _CapabilitiesRef.Status.UNKNOWN))
	if status == _CapabilitiesRef.Status.UNSUPPORTED:
		return {
			"attempted": false,
			"requested": false,
			"observed": false,
			"note": "flag not known to this Godot build",
		}

	var previous: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	var observed: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH)
	print("[window_behavior] click_through: requested=true observed=%s (status=%s)" % [
		observed,
		_CapabilitiesRef.name_of_status(status),
	])
	return {
		"attempted": true,
		"previous": previous,
		"requested": true,
		"observed": observed,
		"note": "status=%s; observed=true only confirms Godot accepted the flag, not that the compositor honors it" % _CapabilitiesRef.name_of_status(status),
	}


# --- Revert --------------------------------------------------------------

static func _revert_probe_changes(transparency_probe: Dictionary, passthrough_probe: Dictionary) -> void:
	if bool(passthrough_probe.get("attempted", false)):
		DisplayServer.window_set_flag(
			DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH,
			bool(passthrough_probe.get("previous", false)),
		)
	if bool(transparency_probe.get("attempted", false)):
		DisplayServer.window_set_flag(
			DisplayServer.WINDOW_FLAG_TRANSPARENT,
			bool(transparency_probe.get("previous", false)),
		)
