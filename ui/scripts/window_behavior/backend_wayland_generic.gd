extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — generisches Wayland-Backend (Fallback)
##
## **Rolle nach der Wayland-Aufteilung:** Dieses Backend bleibt als
## bewusster Fallback erhalten und wird vom Resolver nur noch dann
## gewählt, wenn `session_type == "wayland"` ist, aber **keiner** der
## spezifischeren Compositor-Pfade greift — also weder GNOME/Mutter
## (`backend_wayland_mutter`), noch wlroots-Familie
## (`backend_wayland_wlroots`), noch XWayland
## (`backend_xwayland`). Das deckt u. a. KDE/Wayland (KWin) und
## unbekannte Compositoren ab.
##
## Rationale: unbekannte Wayland-Compositoren bekommen dieselbe
## konservative Stance wie bisher — kein stiller Feature-Override
## ohne klare Zielumgebung. `backend_noop` bleibt für Sessions
## reserviert, in denen schon der `session_type` selbst unklar ist.
##
## Wayland-Stance (unverändert, entspricht
## `docs/linux_always_on_top_decision.md` + `docs/linux_window_overlay_architecture.md`):
##   * Overlay (Transparenz + Borderless) wird weiterhin unter Wayland
##     unterstützt — das liefert der existierende Overlay-Controller
##     capability-gesteuert.
##   * Click-through mit Bounding-Union unter Wayland ist
##     `experimental` (siehe Capability-Modul) und bleibt
##     verantwortungsgebunden am Click-through-Controller.
##   * Always-on-top ist ausdrücklich **kein** Wayland-Versprechen.
##     Der X11-only AOT-Controller verweigert unter Wayland von sich
##     aus. Dieses Backend ändert daran nichts.

class_name SmolitWindowBackendWaylandGeneric


func _init() -> void:
	backend_id = "wayland-generic"
	backend_description = "generic Wayland fallback (no known compositor family) — overlay/click-through delegate; always-on-top refuses by design"
