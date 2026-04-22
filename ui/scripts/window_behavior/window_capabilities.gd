extends RefCounted
## Linux Window Behavior — Capability Detection (Phase 3b Spike v1)
##
## Liefert eine *ehrliche*, klein gehaltene Capability-Aussage für
## Transparenz, Click-through und Always-on-top am aktuellen Godot-
## Hostfenster. Die Klasse führt **keine** Fensteroperationen durch,
## sie beobachtet nur. Änderungen am Fenster laufen über
## `window_probe.gd` — und auch nur opt-in.
##
## Scope:
##   * Session-Typ (Wayland/X11/unknown) aus Umgebungsvariablen +
##     DisplayServer.
##   * Compositor-Hinweis aus `XDG_CURRENT_DESKTOP` (rein informativ).
##   * Project-Setting `per_pixel_transparency/allowed` prüfen.
##   * Pro Fähigkeit einen getaggten Status ausgeben:
##       `available`   — plausibel verfügbar
##       `experimental`— Godot-Flag existiert, Resultat aber
##                       compositor-/protokollabhängig
##       `unsupported` — im aktuellen Setup nicht vorgesehen
##       `unknown`     — kann aus Client-Sicht nicht entschieden werden
##
## Nicht im Scope:
##   * keine Portal-Aufrufe
##   * keine X11-/Wayland-Objekte
##   * keine Versprechen zu Always-on-top unter GNOME/Wayland
##   * keine Persistenz, kein State — jede Abfrage ist frisch

class_name SmolitWindowCapabilities

enum Status {
	AVAILABLE,
	EXPERIMENTAL,
	UNSUPPORTED,
	UNKNOWN,
}


static func name_of_status(status: int) -> String:
	match status:
		Status.AVAILABLE: return "available"
		Status.EXPERIMENTAL: return "experimental"
		Status.UNSUPPORTED: return "unsupported"
		Status.UNKNOWN: return "unknown"
		_: return "unknown"


## Ein einfaches Snapshot-Dict. Bewusst Dictionary statt Resource —
## der Spike soll nicht neue Typen in die UI-Scene ziehen.
static func detect() -> Dictionary:
	var session := _detect_session_type()
	var display_driver := _detect_display_driver()
	var desktop := _detect_desktop_environment()

	var transparency := _detect_transparency(session)
	var click_through := _detect_click_through(session)
	var always_on_top := _detect_always_on_top(session, desktop)

	return {
		"session_type": session,
		"display_driver": display_driver,
		"desktop_environment": desktop,
		"transparency": transparency,
		"click_through": click_through,
		"always_on_top": always_on_top,
	}


## Gibt einen kompakten, menschenlesbaren Report zurück — praktisch für
## Log-Ausgabe in `main.gd`, wenn der Probe-Modus aktiv ist.
static func format_report(snapshot: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("[window_behavior] session=%s driver=%s desktop=%s" % [
		snapshot.get("session_type", "unknown"),
		snapshot.get("display_driver", "unknown"),
		snapshot.get("desktop_environment", "unknown"),
	])
	for capability_name in ["transparency", "click_through", "always_on_top"]:
		var cap: Dictionary = snapshot.get(capability_name, {})
		lines.append("[window_behavior] %s: %s — %s" % [
			capability_name,
			name_of_status(int(cap.get("status", Status.UNKNOWN))),
			str(cap.get("reason", "")),
		])
	return "\n".join(lines)


# --- Environment / host detection ----------------------------------------

static func _detect_session_type() -> String:
	var session_env := OS.get_environment("XDG_SESSION_TYPE").to_lower()
	if session_env == "wayland" or session_env == "x11":
		return session_env
	if OS.get_environment("WAYLAND_DISPLAY") != "":
		return "wayland"
	if OS.get_environment("DISPLAY") != "":
		return "x11"
	return "unknown"


static func _detect_display_driver() -> String:
	# DisplayServer.get_name() liefert unter Godot 4.x etwa "Wayland",
	# "X11" oder "headless". Wir normalisieren lowercase und fallen
	# still auf "unknown" zurück, wenn nichts Sinnvolles kommt.
	var name := DisplayServer.get_name().to_lower()
	if name == "":
		return "unknown"
	return name


static func _detect_desktop_environment() -> String:
	var desktop := OS.get_environment("XDG_CURRENT_DESKTOP")
	if desktop == "":
		desktop = OS.get_environment("DESKTOP_SESSION")
	return desktop if desktop != "" else "unknown"


# --- Per-capability heuristics -------------------------------------------

static func _detect_transparency(session: String) -> Dictionary:
	# Godot entscheidet Per-Pixel-Transparenz *zur Projektladezeit* über
	# `display/window/per_pixel_transparency/allowed`. Ohne dieses
	# Projekt-Setting bleibt der Root-Viewport undurchsichtig, egal was
	# wir zur Laufzeit am Window-Flag setzen.
	var allowed := bool(ProjectSettings.get_setting(
		"display/window/per_pixel_transparency/allowed", false,
	))
	if not allowed:
		return _status_dict(
			Status.UNSUPPORTED,
			"ProjectSettings display/window/per_pixel_transparency/allowed = false (opt-in required at project load)",
		)

	match session:
		"x11":
			return _status_dict(
				Status.AVAILABLE,
				"X11 + Compositing: ARGB-Visual typischerweise verfügbar",
			)
		"wayland":
			return _status_dict(
				Status.AVAILABLE,
				"Wayland: Alpha-Buffer ist protokollkonform; einzelne Compositor-/Treiber-Edge-Cases möglich",
			)
		_:
			return _status_dict(
				Status.UNKNOWN,
				"Session-Typ unbekannt — Transparenz kann aus Client-Sicht nicht sicher beurteilt werden",
			)


static func _detect_click_through(session: String) -> Dictionary:
	# Godot kennt WINDOW_FLAG_MOUSE_PASSTHROUGH seit 4.x, aber das
	# Verhalten unter Wayland ist compositor-abhängig. Der flag-Wert
	# lässt sich setzen und wieder auslesen; das reicht als „Godot weiß
	# zumindest, was gemeint ist"-Signal.
	var flag_known := _godot_knows_flag("WINDOW_FLAG_MOUSE_PASSTHROUGH")
	if not flag_known:
		return _status_dict(
			Status.UNSUPPORTED,
			"Godot-Build kennt WINDOW_FLAG_MOUSE_PASSTHROUGH nicht",
		)
	match session:
		"x11":
			return _status_dict(
				Status.AVAILABLE,
				"X11: XShape-basiertes Input-Region-Shaping ist etabliert",
			)
		"wayland":
			return _status_dict(
				Status.EXPERIMENTAL,
				"Wayland: wl_surface.set_input_region ist im Kernprotokoll, praktische Zuverlässigkeit compositor-abhängig",
			)
		_:
			return _status_dict(
				Status.UNKNOWN,
				"Session-Typ unbekannt — Mouse-Passthrough nicht pauschal zusicherbar",
			)


static func _detect_always_on_top(session: String, desktop: String) -> Dictionary:
	# Always-on-top ist der Punkt, an dem wir am ehrlichsten sein müssen:
	# Godot kann das Flag setzen, aber Mutter/GNOME unter Wayland
	# respektiert Client-seitige Stacking-Hints nicht.
	var flag_known := _godot_knows_flag("WINDOW_FLAG_ALWAYS_ON_TOP")
	if not flag_known:
		return _status_dict(
			Status.UNSUPPORTED,
			"Godot-Build kennt WINDOW_FLAG_ALWAYS_ON_TOP nicht",
		)
	match session:
		"x11":
			return _status_dict(
				Status.AVAILABLE,
				"X11: _NET_WM_STATE_ABOVE wird von gängigen WMs respektiert",
			)
		"wayland":
			if _is_gnome_like(desktop):
				return _status_dict(
					Status.UNSUPPORTED,
					"Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels",
				)
			return _status_dict(
				Status.EXPERIMENTAL,
				"Wayland: compositor-abhängig (wlr-layer-shell für wlroots, sonst meist nicht zuverlässig)",
			)
		_:
			return _status_dict(
				Status.UNKNOWN,
				"Session-Typ unbekannt — Always-on-top nicht pauschal zusicherbar",
			)


# --- helpers -------------------------------------------------------------

static func _status_dict(status: int, reason: String) -> Dictionary:
	return {"status": status, "reason": reason}


static func _is_gnome_like(desktop: String) -> bool:
	if desktop == "":
		return false
	var lower := desktop.to_lower()
	# XDG_CURRENT_DESKTOP ist typischerweise ein `:`-separierter
	# Identifier-Stack ("ubuntu:GNOME"). Token-Vergleich statt `in`,
	# damit "KDE" nicht zufällig "GNOME-Classic" matcht.
	for token in lower.split(":"):
		if token == "gnome" or token == "ubuntu" or token == "unity":
			return true
	return false


static func _godot_knows_flag(flag_name: String) -> bool:
	# ClassDB hat für enum-Werte keine direkte Lookup-API; stattdessen
	# fragen wir DisplayServer über die globale Konstanten-Liste ab.
	# Wenn das fehlschlägt, gehen wir konservativ auf `false`.
	if not ClassDB.class_exists("DisplayServer"):
		return false
	for constant_name in ClassDB.class_get_integer_constant_list("DisplayServer"):
		if constant_name == flag_name:
			return true
	return false
