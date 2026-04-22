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
##   * Always-on-top wird **produktiv** bewusst *nicht* gesetzt — die
##     Capability-Analyse markiert es unter GNOME/Wayland zu Recht als
##     unzuverlässig, und wir wollen dieses Versprechen nicht faken.
##     Der Probe führt allerdings einen kurzen, reversiblen Flag-
##     Versuch durch, um empirisch festzuhalten, ob Godot das Flag
##     akzeptiert. Log macht ausdrücklich klar: *„Flag accepted by
##     API — this is not a user-visible guarantee under Mutter."*
##     Das stützt die Entscheidungsdokumentation in
##     `docs/linux_always_on_top_decision.md`, erzeugt aber keinen
##     produktiven AOT-Zustand.
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
	var always_on_top_probe := _probe_always_on_top(capabilities)

	if _should_revert():
		_revert_probe_changes(
			transparency_probe, passthrough_probe, always_on_top_probe
		)

	var result := {
		"capabilities": capabilities,
		"transparency": transparency_probe,
		"click_through": passthrough_probe,
		"always_on_top": always_on_top_probe,
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


# --- Always-on-top (rein diagnostisch) ----------------------------------


## Kurzer, reversibler AOT-Flag-Versuch. Liefert empirisches Material
## für `docs/linux_always_on_top_decision.md`: Godot akzeptiert das
## Flag meistens API-seitig, aber unter Mutter übersetzt sich das
## nicht in sichtbares Stacking-Verhalten. Das wird hier nicht
## entschieden, sondern nur ehrlich dokumentiert.
##
## Wichtig:
##   * Kein produktiver Pfad. Auch wenn der Flag-Rücklesewert `true`
##     ist, zieht Smolit daraus keinen „AOT aktiv"-Schluss.
##   * Wird per Default mit `_should_revert()` zurückgesetzt.
static func _probe_always_on_top(capabilities: Dictionary) -> Dictionary:
	var cap: Dictionary = capabilities.get("always_on_top", {})
	var status := int(cap.get("status", _CapabilitiesRef.Status.UNKNOWN))

	# Anders als bei Transparenz/Click-through wollen wir hier auch dann
	# probieren, wenn die Capability den Fall als `unsupported` markiert —
	# der springende Punkt der AOT-Diagnostik ist ja genau zu zeigen,
	# dass Godot das Flag akzeptiert, der Compositor es aber (z. B. unter
	# Mutter) nicht in sichtbares Stacking übersetzt. Übersprungen wird
	# nur, wenn der Godot-Build das Flag gar nicht kennt.
	if not _godot_knows_flag("WINDOW_FLAG_ALWAYS_ON_TOP"):
		return {
			"attempted": false,
			"requested": false,
			"observed": false,
			"note": "flag not known to this Godot build",
		}

	var previous: bool = DisplayServer.window_get_flag(
		DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP
	)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var observed: bool = DisplayServer.window_get_flag(
		DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP
	)
	print("[window_behavior] always_on_top: requested=true observed=%s (status=%s) — flag accepted by API; this is NOT a user-visible guarantee under Mutter (see docs/linux_always_on_top_decision.md)" % [
		observed,
		_CapabilitiesRef.name_of_status(status),
	])
	return {
		"attempted": true,
		"previous": previous,
		"requested": true,
		"observed": observed,
		"note": "observed=true only means Godot accepted the flag; not a user-visible guarantee under GNOME/Wayland — see docs/linux_always_on_top_decision.md",
	}


static func _godot_knows_flag(flag_name: String) -> bool:
	if not ClassDB.class_exists("DisplayServer"):
		return false
	for constant_name in ClassDB.class_get_integer_constant_list("DisplayServer"):
		if constant_name == flag_name:
			return true
	return false


# --- Revert --------------------------------------------------------------

static func _revert_probe_changes(
	transparency_probe: Dictionary,
	passthrough_probe: Dictionary,
	always_on_top_probe: Dictionary,
) -> void:
	if bool(always_on_top_probe.get("attempted", false)):
		DisplayServer.window_set_flag(
			DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,
			bool(always_on_top_probe.get("previous", false)),
		)
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
