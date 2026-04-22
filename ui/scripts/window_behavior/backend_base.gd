extends RefCounted
## Linux Window Behavior — Backend-Basisklasse (interne Vorbereitung)
##
## Die Schicht in `ui/scripts/window_behavior/` hat inzwischen drei
## opt-in Aktivierungspfade (Overlay, Click-through, X11-only AOT),
## die pro Lauf durchlaufen werden. Bisher wurden sie vom Fassaden-
## `apply_all(anchor)` direkt und fest verdrahtet aufgerufen.
##
## Dieser Basistyp bereitet eine **interne** Backend-Familie vor:
## `backend_noop`, `backend_x11`, `backend_wayland_generic` (und
## später potenziell `backend_wayland_wlroots`). Jedes Backend
## entscheidet, *wie* die drei Aktivierungen auf einer konkreten
## Session abgebildet werden.
##
## Wichtige Abgrenzung:
##
##   * **Keine neue Plattform-API.** Die Signatur jeder Methode ist
##     identisch zur bisherigen Fassadenfunktion, und die Default-
##     Implementierung delegiert 1:1 an die existierenden Controller.
##     Dadurch ist das eingeführte Routing default-verhaltensgleich
##     zum vorherigen Direktaufruf.
##   * **Kein Feature-Träger.** Ein Backend ist kein Ort, um neue
##     Operationen dazuzupacken (Snap-to-edge, Positionierung,
##     Multi-Monitor, …). Scope-Grenzen stehen in
##     `docs/linux_window_overlay_architecture.md` §F.
##   * **Kein Zustand über Aufrufe hinweg.** Ein Backend entsteht pro
##     `apply_all()`-Aufruf neu, trägt keine persistente Verbindung
##     zu einem Compositor, keine Session-Subscriptions.
##
## Subklassen differenzieren sich momentan fast nur über `backend_id`
## und die Dokumentation — das ist Absicht. Die Strukturarbeit legt
## das Fundament für spätere echte Differenzierung (z. B. wlr-layer-
## shell, GDExtension) ohne die Aufrufseite (main.gd / Fassade / Runtime-
## Report) erneut anfassen zu müssen.

class_name SmolitWindowBackend

const _OverlayRef := preload("res://scripts/window_behavior/overlay_controller.gd")
const _ClickThroughRef := preload("res://scripts/window_behavior/overlay_click_through_controller.gd")
const _AlwaysOnTopRef := preload("res://scripts/window_behavior/overlay_always_on_top_controller.gd")


## Kurzname des Backends, landet im Runtime-Report / Debug-Log.
## Subklassen überschreiben dies.
var backend_id: String = "base"


## Kurzer, menschenlesbarer Satz, was dieses Backend tut. Wird vom
## Runtime-Report gezeigt; keine maschinelle Verarbeitung.
var backend_description: String = "default delegating base"


## Optionaler Einzeiler, der angibt, ob dieses Backend einen
## **experimentellen** Sonderpfad trägt, der noch nicht produktiv
## aktiv ist (z. B. `wlroots`-Spezialvorbereitung). Leer bei
## Backends, die einfach delegieren und keinen Sonderstatus
## beanspruchen. Der Runtime-Report zeigt diesen String nur, wenn
## er gesetzt ist — kein Default-Log-Spam.
var experimental_stance: String = ""


## Führt die Overlay-Aktivierung durch. Default-Implementierung ist
## identisch zum bisherigen Fassadenpfad: sie ruft den existierenden
## Overlay-Controller auf und gibt dessen Status-Dict weiter.
## Subklassen dürfen dies überschreiben — wichtig ist, dass das
## Ergebnis-Dict weiterhin die in `window_behavior_result.gd`
## definierten Achsen trägt.
func activate_overlay_if_requested(anchor: Node) -> Dictionary:
	return _OverlayRef.activate_if_requested(anchor)


## Führt die Click-through-Aktivierung durch. `overlay_result` ist
## genau der Rückgabewert des vorherigen `activate_overlay_if_requested`-
## Calls — der Click-through-Pfad prüft darin, ob Overlay wirklich
## aktiv wurde, bevor er sich aufschaltet.
func activate_click_through_if_requested(
	anchor: Node, overlay_result: Dictionary
) -> Dictionary:
	return _ClickThroughRef.activate_if_requested(anchor, overlay_result)


## Führt den X11-only Always-on-top-Sonderpfad durch. Der Controller
## verweigert unter GNOME/Wayland, headless und unknown Session
## ausdrücklich — das gilt weiterhin; das Backend-Level ist nur
## Routing, keine neue Policy.
func activate_always_on_top_if_requested(anchor: Node) -> Dictionary:
	return _AlwaysOnTopRef.activate_if_requested(anchor)
