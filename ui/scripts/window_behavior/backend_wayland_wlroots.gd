extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — Wayland/wlroots-Backend
##
## Benannter Platzhalter für wlroots-basierte Wayland-Compositoren
## (Sway, Hyprland, Wayfire, river, …). Das Backend delegiert
## aktuell an die existierenden Controller und führt **keine**
## layer-shell-spezifische Aktivierung durch. Es dokumentiert nur:
## dies ist die Stelle, an der eine spätere
## `wlr-layer-shell-unstable-v1`-Integration aufsetzen würde, wenn
## wlroots-Sessions ein relevantes Nutzersegment werden.
##
## Aktuelle wlroots-Realität bei Smolit (unverändert durch diesen PR):
##   * Overlay (Transparenz + Borderless) funktioniert regulär über
##     den Overlay-Controller.
##   * Click-through mit Bounding-Union ebenfalls regulär; die
##     Capability-Analyse markiert Wayland als `experimental`, was
##     auch hier gilt.
##   * Always-on-top ist weiterhin **nicht** Teil dieses Backends.
##     Ein echter wlroots-AOT-/Overlay-Layer-Pfad erforderte eine
##     layer-shell-Wrapping-Schicht — bewusst nicht dieser PR (siehe
##     Leitplanken in `ROADMAP.md`).
##
## Architektureinordnung:
##   * Differenzierung gegenüber `backend_wayland_mutter` ist heute
##     rein dokumentarisch. Der Unterschied wird erst sichtbar, wenn
##     entweder hier layer-shell dazukommt oder dort eine GNOME-
##     Extension — beides ausdrücklich zurückgestellt.
##   * Die Klasse bleibt dünn, damit sie ein klarer Zielort für
##     spätere Arbeit ist und nicht zu einer zweiten „macht alles"-
##     Schicht mutiert.

class_name SmolitWindowBackendWaylandWlroots


func _init() -> void:
	backend_id = "wayland-wlroots"
	backend_description = "Wayland/wlroots-family compositor — overlay/click-through delegate; always-on-top refuses by design; no layer-shell yet"
