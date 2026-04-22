extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — X11-Backend
##
## Schmaler delegierender Pfad für echte X11-Sessions
## (`session_type == "x11"`, nicht headless). Das Backend hält keine
## X11-Magie — es bildet nur einen benannten Rahmen, unter dem die
## drei bestehenden Aktivierungspfade für X11-Umgebungen laufen.
##
## Zweck (Architektur):
##   * Spätere X11-spezifische Feinpfade (z. B. XShape-Multirect für
##     Click-through-Passthrough, `_NET_WM_WINDOW_TYPE_DOCK` für AOT-
##     Varianten) hätten hier einen klaren Platz, ohne die Controller
##     selbst mit einer Session-Fallunterscheidung zu belasten.
##   * Der Runtime-Report kann die X11-Session am `backend_id`
##     erkennen und entsprechend markieren.
##
## Aktueller Stand:
##   * Kein Override nötig — die Default-Implementierung der
##     Basisklasse delegiert bereits an Overlay-, Click-through- und
##     AOT-Controller. Die Gates in den Controllern gelten weiterhin.
##   * Keine neue Plattformlogik, keine neuen Flags.

class_name SmolitWindowBackendX11


func _init() -> void:
	backend_id = "x11"
	backend_description = "real X11 session — delegates to existing controllers"
