extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — XWayland-Backend
##
## Sonderfall für Wayland-Login-Sessions, in denen Godot nicht mit
## dem Wayland-DisplayServer läuft, sondern als X11-Client über
## XWayland. Erkennbar daran, dass der Capability-Snapshot
## `session_type == "wayland"` zeigt, der DisplayServer aber als
## `"x11"` gemeldet wird.
##
## Ehrliche Einordnung (siehe auch
## `docs/x11_always_on_top_verification.md` §F.3):
##   * Technisch läuft Godot unter XWayland wie ein X11-Client, kann
##     also `_NET_WM_STATE_ABOVE` setzen und Transparenz/Input-Region
##     nach X11-Mustern bedienen.
##   * Das *sichtbare* Stacking-/Fenster-Verhalten entscheidet aber
##     der Wayland-Compositor (meist Mutter), und das Ergebnis ist
##     empirisch inkonsistent — „Flag gesetzt ≠ Nutzer sieht es
##     oben".
##   * Aus Produktsicht bleibt XWayland daher ein *Grau-Bereich*. Der
##     X11-only AOT-Controller orientiert sich an `session_type`,
##     das unter einer Wayland-Session `wayland` ist, also verweigert
##     er auch hier — mit der bekannten Refusal-Message.
##
## Dieses Backend ist ein benannter Zielort für spätere Feinpfade
## („unter XWayland könnten wir AOT-Flag setzen und Nutzern ehrlich
## sagen: WM-abhängig"), aber es baut *in diesem PR* keine neue
## Aktivierungslogik. Overlay/Click-through/AOT delegieren an die
## gleichen Controller wie überall.

class_name SmolitWindowBackendXWayland


func _init() -> void:
	backend_id = "xwayland"
	backend_description = "Wayland session with X11 display driver (XWayland) — delegates to controllers; behaviour remains session-gated"
