extends RefCounted
## Linux Window Behavior — Overlay Runtime Report (opt-in Diagnostik)
##
## Rein diagnostischer, opt-in Konsolenblock. Keine Nutzerfunktion,
## keine Scene-Logik, keine Business-Entscheidung — nur ein
## konsolidierter Snapshot dessen, was die bestehende Window-Behavior-
## Linie beim aktuellen Run ohnehin weiß.
##
## Zweck:
##   * Auf realer Wayland-/X11-Session auf einen Blick sehen,
##     - welche Session/Desktop/Display-Driver erkannt wurden,
##     - welche Capabilities gemeldet werden,
##     - ob Overlay tatsächlich aktiv geworden ist,
##     - ob Click-through aktiv geworden ist und mit welchen Zonen,
##     - welche Bounding-Box aktuell für Passthrough verwendet wird.
##   * Basis für die Verifikationsmatrix in
##     `docs/linux_overlay_verification_matrix.md` — der Nutzer muss
##     nur schauen, was dieser Block sagt.
##
## Was der Report bewusst **nicht** tut:
##   * Keine neuen Flags setzen, kein Eingriff in DisplayServer.
##   * Keine IPC-Nachricht, kein EventBus-Event.
##   * Keine Presence-/Avatar-/Scene-Änderung.
##   * Kein Dauer-Log — genau *eine* Ausgabe pro Aufruf,
##     call-site-gesteuert (aktuell: Ende von `main.gd::_ready()`).
##   * Kein Default-Verhalten. Ohne `SMOLIT_WINDOW_REPORT=1` passiert
##     nichts.
##
## Der Block ist absichtlich textlich — kein Markdown, kein JSON, keine
## Parser-Verträge. Wer ihn zuverlässig weiterverarbeiten will, soll
## die bestehenden Statuslogs pro Controller auswerten.

class_name SmolitOverlayRuntimeReport

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")
const _ResultRef := preload("res://scripts/window_behavior/window_behavior_result.gd")

const ENABLE_ENV_VAR: String = "SMOLIT_WINDOW_REPORT"


static func is_requested() -> bool:
	var raw := OS.get_environment(ENABLE_ENV_VAR).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


## Call-site aus `main.gd::_ready()`, direkt nach den Overlay- und
## Click-through-Aktivierungen. `overlay_result` / `click_through_result`
## sind die Rückgabedicts der beiden Fassadenpunkte; beide können leer
## oder „nicht angefordert" sein — der Report geht damit sauber um.
static func print_if_requested(
	overlay_result: Dictionary,
	click_through_result: Dictionary,
	always_on_top_result: Dictionary = {},
) -> void:
	if not is_requested():
		return
	print_now(overlay_result, click_through_result, always_on_top_result)


## Für manuelle Debugsitzungen: Report auch ohne Env-Flag ausgeben.
## Nicht als Default-Pfad gedacht.
static func print_now(
	overlay_result: Dictionary,
	click_through_result: Dictionary,
	always_on_top_result: Dictionary = {},
) -> void:
	var caps: Dictionary = overlay_result.get("capabilities", _CapabilitiesRef.detect())
	var lines := PackedStringArray()
	lines.append("─── overlay runtime report ───────────────────────────────")
	_append_session_lines(lines, caps)
	_append_capability_lines(lines, caps)
	_append_overlay_lines(lines, overlay_result)
	_append_click_through_lines(lines, click_through_result)
	_append_always_on_top_lines(lines, always_on_top_result)
	lines.append("──────────────────────────────────────────────────────────")
	print("\n".join(lines))


# --- Section: session / display driver ----------------------------------


static func _append_session_lines(lines: PackedStringArray, caps: Dictionary) -> void:
	lines.append("[report] session_type        = %s" % str(caps.get("session_type", "unknown")))
	lines.append("[report] display_driver      = %s" % str(caps.get("display_driver", "unknown")))
	lines.append("[report] desktop_environment = %s" % str(caps.get("desktop_environment", "unknown")))
	# Rohe Env-Variablen sind oft aussagekräftiger als die abgeleiteten
	# Kurzformen — vor allem auf atypischen Sessions (remote, XWayland,
	# flatpak). Leere Werte ehrlich als „(unset)" markieren.
	lines.append("[report]   XDG_SESSION_TYPE    = %s" % _env_or_unset("XDG_SESSION_TYPE"))
	lines.append("[report]   XDG_CURRENT_DESKTOP = %s" % _env_or_unset("XDG_CURRENT_DESKTOP"))
	lines.append("[report]   WAYLAND_DISPLAY     = %s" % _env_or_unset("WAYLAND_DISPLAY"))
	lines.append("[report]   DISPLAY             = %s" % _env_or_unset("DISPLAY"))


static func _env_or_unset(name: String) -> String:
	var value := OS.get_environment(name)
	return value if value != "" else "(unset)"


# --- Section: capabilities ---------------------------------------------


static func _append_capability_lines(lines: PackedStringArray, caps: Dictionary) -> void:
	for key in ["transparency", "click_through", "always_on_top"]:
		var cap: Dictionary = caps.get(key, {})
		var status_id := int(cap.get("status", _CapabilitiesRef.Status.UNKNOWN))
		lines.append("[report] capability.%-14s = %s — %s" % [
			key,
			_CapabilitiesRef.name_of_status(status_id),
			str(cap.get("reason", "")),
		])


# --- Section: overlay ---------------------------------------------------


static func _append_overlay_lines(lines: PackedStringArray, overlay_result: Dictionary) -> void:
	if overlay_result.is_empty():
		lines.append("[report] overlay              = (no result — not invoked?)")
		return
	lines.append("[report] overlay.requested     = %s" % bool(overlay_result.get("requested", false)))
	lines.append("[report] overlay.active        = %s" % bool(overlay_result.get("active", false)))
	var transparency: Dictionary = overlay_result.get("transparency", {})
	if not transparency.is_empty():
		lines.append("[report] overlay.transparency  = applied=%s observed_flag=%s status=%s" % [
			bool(transparency.get("applied", false)),
			bool(transparency.get("observed_flag", false)),
			str(transparency.get("status", "")),
		])
	var borderless: Dictionary = overlay_result.get("borderless", {})
	if not borderless.is_empty():
		lines.append("[report] overlay.borderless    = applied=%s" % [
			bool(borderless.get("applied", false)),
		])


# --- Section: click-through --------------------------------------------


static func _append_click_through_lines(lines: PackedStringArray, result: Dictionary) -> void:
	if result.is_empty():
		lines.append("[report] click_through        = (no result — not invoked?)")
		return
	lines.append("[report] click_through.requested        = %s" % bool(result.get("requested", false)))
	lines.append("[report] click_through.overlay_active   = %s" % bool(result.get("overlay_active", false)))
	lines.append("[report] click_through.capable          = %s" % bool(result.get("capable", false)))
	lines.append("[report] click_through.zones_derived    = %d" % int(result.get("zones_derived", 0)))
	lines.append("[report] click_through.zones_valid      = %d" % int(result.get("zones_valid", 0)))
	lines.append("[report] click_through.active           = %s" % bool(result.get("active", false)))
	var bounds_variant: Variant = result.get("bounds", null)
	if typeof(bounds_variant) == TYPE_RECT2:
		# Darstellung via gemeinsamem Rect-Formatter — selbe
		# Klammerung wie im Click-through-Controller-Log.
		lines.append("[report] click_through.bounds_union     = %s" % _ResultRef.format_rect(bounds_variant))
		lines.append("[report] click_through.region_model     = bounding-union (single-polygon MVP — empty space inside stays clickable)")
	else:
		lines.append("[report] click_through.bounds_union     = (none)")
	var zones: Array = result.get("zones", [])
	if zones.is_empty():
		lines.append("[report] click_through.zones            = (none)")
	else:
		lines.append("[report] click_through.zones (%d):" % zones.size())
		for zone_variant in zones:
			if typeof(zone_variant) != TYPE_DICTIONARY:
				continue
			var zone: Dictionary = zone_variant
			var rect_text := _ResultRef.format_rect(zone.get("rect", null))
			lines.append("[report]   • %-22s rect=%s (%s)" % [
				str(zone.get("path", "")),
				rect_text,
				str(zone.get("purpose", "")),
			])
	var reason := str(result.get("reason", ""))
	if reason != "":
		lines.append("[report] click_through.reason           = %s" % reason)


# --- Section: always-on-top (X11-only special path) --------------------


static func _append_always_on_top_lines(
	lines: PackedStringArray, result: Dictionary
) -> void:
	if result.is_empty():
		lines.append("[report] always_on_top       = (no result — not invoked?)")
		return
	lines.append("[report] always_on_top.requested         = %s" % bool(result.get("requested", false)))
	lines.append("[report] always_on_top.session_type      = %s" % str(result.get("session_type", "")))
	lines.append("[report] always_on_top.display_driver    = %s" % str(result.get("display_driver", "")))
	var cap_status: String = str(result.get("capability_status", ""))
	if cap_status != "":
		lines.append("[report] always_on_top.capability        = %s (%s)" % [
			cap_status,
			str(result.get("capability_reason", "")),
		])
	lines.append("[report] always_on_top.candidate         = %s" % bool(result.get("candidate", false)))
	lines.append("[report] always_on_top.applied           = %s" % bool(result.get("applied", false)))
	lines.append("[report] always_on_top.observed          = %s" % bool(result.get("observed", false)))
	lines.append("[report] always_on_top.active            = %s" % bool(result.get("active", false)))
	lines.append("[report] always_on_top.scope             = X11-only special path; GNOME/Wayland intentionally not targeted")
	var reason := str(result.get("reason", ""))
	if reason != "":
		lines.append("[report] always_on_top.reason            = %s" % reason)
