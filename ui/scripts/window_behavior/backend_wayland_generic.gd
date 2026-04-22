extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — generisches Wayland-Backend
##
## Für Sessions mit `session_type == "wayland"` unabhängig vom konkreten
## Compositor (GNOME/Mutter, KDE/KWin-Wayland, wlroots, …). Das Backend
## führt **keine** compositor-spezifischen Pfade aus und hebt
## **nichts** auf einen echten Layer-Shell-/Extension-Pfad an.
##
## Wayland-Stance (entspricht
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
##
## Dieses Backend existiert als benannter Platzhalter für „unter
## Wayland bewusst zurückhaltend". Spätere Forks
## (`backend_wayland_wlroots` mit echter layer-shell-Integration,
## `backend_wayland_gnome_extension`, …) können hier abgezweigt
## werden, ohne die Aufrufseite neu zu verkabeln.

class_name SmolitWindowBackendWaylandGeneric


func _init() -> void:
	backend_id = "wayland-generic"
	backend_description = "generic Wayland session — overlay/click-through pass through, always-on-top refuses by design"
