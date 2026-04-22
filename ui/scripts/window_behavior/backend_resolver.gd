extends RefCounted
## Linux Window Behavior — Backend-Resolver
##
## Wählt für einen gegebenen Capability-/Session-Snapshot das passende
## interne Backend. Seit der Wayland-Aufteilung (siehe
## `docs/ui_architecture.md` §9.0 und §F.1 in
## `docs/linux_window_overlay_architecture.md`) ist die Auswahl feiner:
##
##   * `session_type == "x11"`        → `backend_x11`
##   * `session_type == "wayland"`    → einer der Wayland-Pfade
##     (siehe unten)
##   * alles andere (`"unknown"` / leer / exotisch) → `backend_noop`
##
## Innerhalb von Wayland:
##
##   * **XWayland-Sonderfall.** `session_type == "wayland"` +
##     `display_driver == "x11"` → `backend_xwayland`. Damit ist
##     ausdrücklich erkennbar, dass Godot als X11-Client in einer
##     Wayland-Login-Session läuft. Das Stacking-Verhalten entscheidet
##     weiter der Wayland-Compositor; aber der Code-Pfad hat jetzt
##     einen dokumentierten Zielort.
##   * **GNOME/Mutter.** GNOME-artiger Desktop → `backend_wayland_mutter`.
##     Erkennung über denselben GNOME-Token-Vergleich wie in
##     `window_capabilities.gd::_is_gnome_like` (konservativ, damit
##     „KDE-Classic" nicht versehentlich als GNOME matcht).
##   * **wlroots-Familie** (Sway, Hyprland, Wayfire, river, …) →
##     `backend_wayland_wlroots`. Erkennung über eine kleine
##     explizite Allowlist an Desktop-Token; bewusst konservativ,
##     damit keine „clevere Heuristik" entsteht.
##   * **Alles andere unter Wayland** (z. B. KDE/Wayland, unbekannte
##     Compositoren, Remote-Setups) → `backend_wayland_generic` als
##     ehrlicher Fallback. Keine neuen Feature-Versprechen.
##
## Driver-Spezifika (`"headless"` vs. echter Driver) sind nur beim
## XWayland-Sonderfall relevant. Für die normale x11-/wayland-
## Auswahl werden sie ignoriert — die bestehenden Controller-Gates
## lehnen unter `headless` sowieso selbst ab.

class_name SmolitWindowBackendResolver

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")
const _BackendX11Ref := preload("res://scripts/window_behavior/backend_x11.gd")
const _BackendWaylandGenericRef := preload("res://scripts/window_behavior/backend_wayland_generic.gd")
const _BackendWaylandMutterRef := preload("res://scripts/window_behavior/backend_wayland_mutter.gd")
const _BackendWaylandWlrootsRef := preload("res://scripts/window_behavior/backend_wayland_wlroots.gd")
const _BackendXWaylandRef := preload("res://scripts/window_behavior/backend_xwayland.gd")
const _BackendNoopRef := preload("res://scripts/window_behavior/backend_noop.gd")

## Explizite, bewusst kleine Allowlist bekannter wlroots-Compositoren.
## Wird *token-weise* gegen `XDG_CURRENT_DESKTOP` verglichen — kein
## Substring-Match, damit z. B. „wayfire" nicht zufällig in einem
## längeren Identifier steckenbleibt.
const _WLROOTS_DESKTOP_TOKENS: Array[String] = [
	"sway",
	"hyprland",
	"wayfire",
	"river",
	"labwc",
]


## Wählt ein Backend basierend auf einem Capability-Snapshot. Falls
## kein Snapshot übergeben wird, holt der Resolver selbst einen
## frischen.
static func resolve(capabilities: Dictionary = {}) -> RefCounted:
	var snapshot: Dictionary = capabilities
	if snapshot.is_empty():
		snapshot = _CapabilitiesRef.detect()
	var session: String = str(snapshot.get("session_type", "unknown"))
	var driver: String = str(snapshot.get("display_driver", "unknown"))
	var desktop: String = str(snapshot.get("desktop_environment", "unknown"))

	if session == "x11":
		return _BackendX11Ref.new()

	if session == "wayland":
		# XWayland zuerst: wenn Godot als X11-Driver in einer Wayland-
		# Session läuft, ist das ein distinkter Pfad und verdient
		# seinen eigenen Backend-Namen.
		if driver == "x11":
			return _BackendXWaylandRef.new()
		if _is_gnome_like(desktop):
			return _BackendWaylandMutterRef.new()
		if _is_wlroots_like(desktop):
			return _BackendWaylandWlrootsRef.new()
		return _BackendWaylandGenericRef.new()

	return _BackendNoopRef.new()


# --- helpers -------------------------------------------------------------


## Token-Vergleich analog zu `SmolitWindowCapabilities._is_gnome_like`.
## Wir halten das hier eigen, damit der Resolver nicht in den
## internen `_`-Namespace von `window_capabilities.gd` greift.
static func _is_gnome_like(desktop: String) -> bool:
	if desktop == "":
		return false
	var lower := desktop.to_lower()
	for token in lower.split(":"):
		if token == "gnome" or token == "ubuntu" or token == "unity":
			return true
	return false


static func _is_wlroots_like(desktop: String) -> bool:
	if desktop == "":
		return false
	var lower := desktop.to_lower()
	for token in lower.split(":"):
		for wlroots_token in _WLROOTS_DESKTOP_TOKENS:
			if token == wlroots_token:
				return true
	return false
