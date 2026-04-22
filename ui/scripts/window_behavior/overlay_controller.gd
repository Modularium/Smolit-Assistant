extends RefCounted
## Linux Window Behavior — Overlay MVP (Phase 3b, Phase B)
##
## Opt-in transparenter Presence-Modus. Aktiv nur, wenn
## `SMOLIT_UI_OVERLAY=1` gesetzt ist. Alles läuft capability-gesteuert —
## fehlt die Transparenz-Fähigkeit, bleibt das Fenster im normalen Modus
## und der Controller meldet das ehrlich im Log.
##
## Was der Overlay-MVP wirklich tut (nur im Erfolgspfad):
##   * `Viewport.transparent_bg = true` auf dem Root-Window
##   * `DisplayServer.WINDOW_FLAG_TRANSPARENT = true`
##   * `DisplayServer.WINDOW_FLAG_BORDERLESS = true`
##
## Was er bewusst **nicht** tut:
##   * kein Always-on-top — unter GNOME/Wayland nicht zuverlässig; unter
##     X11 zwar machbar, aber in Phase B nicht Teil des Versprechens.
##   * kein produktives Click-through. Ein naives
##     `WINDOW_FLAG_MOUSE_PASSTHROUGH=true` würde das ganze Fenster für
##     Eingaben durchlässig machen, inklusive Avatar, Banner und
##     Eingabefeldern. Eine ehrliche Click-through-Stufe braucht
##     definierte interaktive Zonen (Passthrough-Polygone) — das ist
##     Folgearbeit.
##   * keine Snap-to-Edge, kein Multi-Monitor-Heuristik, keine
##     Compositor-spezifischen Pfade (layer-shell, GNOME-Extension).
##   * keine neue Presence-Wahrheit, keine Scene-Eingriffe, keine
##     IPC-Nachrichten, keine Autoloads.
##
## Capability-/Fallback-Semantik:
##   * Overlay requested + transparency `available`   → Overlay aktiv
##   * Overlay requested + transparency `experimental`→ Overlay aktiv
##                                                      (ehrliches
##                                                      Warn-Log)
##   * Overlay requested + transparency `unsupported` → normaler Modus,
##                                                      honest reason
##   * Overlay requested + transparency `unknown`     → normaler Modus,
##                                                      honest reason
##   * Overlay nicht requested                        → No-op

class_name SmolitOverlayController

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")

const ENABLE_ENV_VAR: String = "SMOLIT_UI_OVERLAY"


static func is_requested() -> bool:
	var raw := OS.get_environment(ENABLE_ENV_VAR).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


## Wird aus `main.gd::_ready()` aufgerufen. Ohne Opt-in passiert nichts —
## der Rückgabewert hält fest, dass der Modus nicht angefordert war.
static func activate_if_requested(anchor: Node) -> Dictionary:
	if not is_requested():
		return {
			"requested": false,
			"active": false,
			"reason": "SMOLIT_UI_OVERLAY not set",
		}
	return activate_now(anchor)


## Setzt den Overlay-Modus unabhängig vom Env-Flag. Primär für manuelle
## Tests / Debugsitzungen — der normale Pfad ist `activate_if_requested`.
static func activate_now(anchor: Node) -> Dictionary:
	var capabilities: Dictionary = _CapabilitiesRef.detect()
	print(_CapabilitiesRef.format_report(capabilities))

	var transparency_cap: Dictionary = capabilities.get("transparency", {})
	var transparency_status := int(
		transparency_cap.get("status", _CapabilitiesRef.Status.UNKNOWN)
	)
	var transparency_reason := str(transparency_cap.get("reason", ""))

	var result := {
		"requested": true,
		"active": false,
		"capabilities": capabilities,
		"transparency": {
			"requested": true,
			"applied": false,
			"status": _CapabilitiesRef.name_of_status(transparency_status),
			"reason": transparency_reason,
		},
		"borderless": {
			"requested": true,
			"applied": false,
			"reason": "",
		},
		"click_through": {
			"requested": false,
			"applied": false,
			"reason": "deferred — needs interactive-zone polygons to keep the avatar clickable",
		},
		"always_on_top": {
			"requested": false,
			"applied": false,
			"reason": "not promised in Phase B — see docs/linux_window_overlay_architecture.md §C.1 / §E",
		},
	}

	if transparency_status == _CapabilitiesRef.Status.UNSUPPORTED \
			or transparency_status == _CapabilitiesRef.Status.UNKNOWN:
		print("[overlay] transparency %s — falling back to normal window (reason: %s)" % [
			_CapabilitiesRef.name_of_status(transparency_status),
			transparency_reason,
		])
		result["transparency"]["reason"] = (
			"fallback: " + transparency_reason if transparency_reason != ""
			else "fallback: transparency unavailable"
		)
		return result

	if transparency_status == _CapabilitiesRef.Status.EXPERIMENTAL:
		print("[overlay] transparency experimental — activating with honest warning (reason: %s)" % transparency_reason)

	var viewport: Viewport = null
	if anchor != null:
		viewport = anchor.get_viewport()
	if viewport == null:
		# Last-resort fallback: the main window root. This is normally
		# identical to `anchor.get_viewport()` for a root Control.
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			viewport = (main_loop as SceneTree).root

	if viewport != null:
		viewport.transparent_bg = true
		result["transparency"]["applied_viewport_bg"] = true
	else:
		result["transparency"]["applied_viewport_bg"] = false
		result["transparency"]["reason"] = "no viewport found to toggle transparent_bg"

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var transparent_observed: bool = DisplayServer.window_get_flag(
		DisplayServer.WINDOW_FLAG_TRANSPARENT
	)
	result["transparency"]["applied"] = transparent_observed
	result["transparency"]["observed_flag"] = transparent_observed

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var borderless_observed: bool = DisplayServer.window_get_flag(
		DisplayServer.WINDOW_FLAG_BORDERLESS
	)
	result["borderless"]["applied"] = borderless_observed

	result["active"] = bool(result["transparency"]["applied"])

	print("[overlay] active=%s transparency=%s borderless=%s" % [
		result["active"],
		result["transparency"]["applied"],
		result["borderless"]["applied"],
	])
	print("[overlay] click_through: %s" % result["click_through"]["reason"])
	print("[overlay] always_on_top: %s" % result["always_on_top"]["reason"])

	return result
