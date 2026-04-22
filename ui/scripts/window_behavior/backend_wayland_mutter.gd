extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — Wayland/Mutter-Backend (GNOME)
##
## Benannter Platzhalter für Sessions unter GNOME/Mutter im
## Wayland-Modus (Ubuntu 24.04 Default-Ziel). Das Backend trifft
## *keine* GNOME-spezifische Plattformentscheidung — es delegiert
## weiterhin an die existierenden Controller. Es dokumentiert nur:
## dies ist die Stelle, an der spätere Mutter-spezifische
## Strategien ankommen würden (z. B. eine offizielle Smolit-GNOME-
## Extension, falls jemals nötig).
##
## Aktuelle Wayland/GNOME-Realität:
##   * Overlay (Transparenz + Borderless) funktioniert unter Mutter
##     — liefert der Overlay-Controller capability-gesteuert.
##   * Click-through ist protokollseitig möglich
##     (`wl_surface.set_input_region`), der Controller markiert es
##     als `experimental` und übernimmt die Gates selbst.
##   * Always-on-top bleibt bewusst **ohne Zusage**. Der X11-only
##     AOT-Controller verweigert unter Wayland automatisch (siehe
##     `docs/linux_always_on_top_decision.md`). Dieses Backend
##     ändert daran nichts.
##
## Architektureinordnung:
##   * `backend_wayland_mutter` ist absichtlich NICHT der Platz für
##     eine GNOME-Extension-Integration. Diese Entscheidung ist in
##     `docs/linux_always_on_top_decision.md` §B.2 getroffen und
##     bleibt zurückgestellt.
##   * Die Klasse ist bewusst dünn: sie existiert damit zukünftige
##     compositor-spezifische Feinpfade hier landen, ohne die
##     Aufrufseite (Fassade / `main.gd`) erneut anfassen zu müssen.

class_name SmolitWindowBackendWaylandMutter


func _init() -> void:
	backend_id = "wayland-mutter"
	backend_description = "Wayland/GNOME (Mutter) — overlay/click-through delegate; always-on-top refuses by design"
