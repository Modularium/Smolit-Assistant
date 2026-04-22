extends RefCounted
## Linux Window Behavior — schmale Fassade (Phase 3b Spike v1)
##
## Koordiniert die beiden konkreten Bausteine (Capabilities + Probe)
## unter einer einzigen, einfachen Einstiegsklasse. Zweck: `main.gd`
## muss nur genau einen Aufruf kennen, um den opt-in Spike zu triggern.
##
## Absichtlich *kein* Autoload, *kein* Node, *kein* Singleton mit
## State. Die Fassade ist ein kleiner Funktionscontainer.
##
## Wichtig:
##   * keine Business-Logik, keine Presence-Entscheidungen
##   * kein Always-on-top in dieser Phase (siehe docs/linux_window_overlay_architecture.md §F)
##   * keine neue UI, keine neuen IPC-Events

class_name SmolitWindowBehavior

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")
const _ProbeRef := preload("res://scripts/window_behavior/window_probe.gd")
const _OverlayRef := preload("res://scripts/window_behavior/overlay_controller.gd")
const _ClickThroughRef := preload("res://scripts/window_behavior/overlay_click_through_controller.gd")
const _RuntimeReportRef := preload("res://scripts/window_behavior/overlay_runtime_report.gd")
const _AlwaysOnTopRef := preload("res://scripts/window_behavior/overlay_always_on_top_controller.gd")


## Cheap — nur Detection. Sicher, auch aus `_ready()` aufzurufen.
static func capabilities() -> Dictionary:
	return _CapabilitiesRef.detect()


## Opt-in Einstiegspunkt. Tut *nichts*, solange
## `SMOLIT_WINDOW_PROBE=1` nicht gesetzt ist.
static func run_probe_if_enabled() -> Dictionary:
	return _ProbeRef.run_if_enabled()


## Für manuelle Debugsitzungen / spätere Tests — ignoriert die
## Env-Variable und führt den Probe trotzdem aus. Nicht als Default-
## Pfad gedacht.
static func run_probe_now() -> Dictionary:
	return _ProbeRef.run_now()


## Opt-in Overlay-MVP (Phase B). Aktiviert einen transparenten
## Presence-Modus nur, wenn `SMOLIT_UI_OVERLAY=1` gesetzt ist *und* die
## Transparenz-Capability im aktuellen Setup tragfähig ist. Ohne Opt-in
## und bei unsupported-Umgebung bleibt das Fenster im normalen Modus.
static func activate_overlay_if_requested(anchor: Node) -> Dictionary:
	return _OverlayRef.activate_if_requested(anchor)


## Für manuelle Debugsitzungen — ignoriert das Env-Flag und aktiviert
## den Overlay-Modus. Nicht als Default-Pfad gedacht.
static func activate_overlay_now(anchor: Node) -> Dictionary:
	return _OverlayRef.activate_now(anchor)


## Opt-in Click-through-Folgeschritt auf den Overlay-MVP. Aktiviert
## Mouse-Passthrough außerhalb definierter interaktiver Zonen — nur,
## wenn `SMOLIT_UI_OVERLAY=1` *und* `SMOLIT_UI_CLICK_THROUGH=1` gesetzt
## sind, der übergebene `overlay_result` einen aktiven Overlay-Modus
## beschreibt und die Click-through-Capability tragfähig ist. Ohne
## Opt-in, ohne aktives Overlay oder ohne sinnvolle Zonen passiert
## nichts; der Grund landet im Log.
##
## `overlay_result` ist genau der Rückgabewert von
## `activate_overlay_if_requested` / `activate_overlay_now` — die
## Funktionen sind so entworfen, dass sie kettenbar sind, ohne dass
## `main.gd` irgendein Overlay-Detailwissen aufbauen muss.
static func activate_click_through_if_requested(
	anchor: Node, overlay_result: Dictionary
) -> Dictionary:
	return _ClickThroughRef.activate_if_requested(anchor, overlay_result)


## Opt-in X11-only Always-on-top-Sonderpfad. Aktiviert
## `WINDOW_FLAG_ALWAYS_ON_TOP` nur, wenn
## `SMOLIT_UI_ALWAYS_ON_TOP=1` gesetzt ist *und* die aktuelle Session
## wirklich X11 ist (nicht Wayland, nicht headless, nicht unknown).
## GNOME/Wayland bleibt ausdrücklich **ohne** AOT-Versprechen (siehe
## `docs/linux_always_on_top_decision.md`). Unabhängig vom Overlay-
## und vom Click-through-Pfad.
static func activate_always_on_top_if_requested(anchor: Node) -> Dictionary:
	return _AlwaysOnTopRef.activate_if_requested(anchor)


## Opt-in Diagnostik-Konsolidierung. Rein lesender Runtime-Report über
## Session, Capabilities, Overlay-, Click-through- und Always-on-top-
## Status. Kein-op, solange `SMOLIT_WINDOW_REPORT=1` nicht gesetzt ist.
## Ausschließlich für Verifikation auf realen Sessions gedacht (siehe
## `docs/linux_overlay_verification_matrix.md`) — keine neue Nutzer-
## funktion, keine IPC-/EventBus-Anbindung, kein Presence-Eingriff.
static func print_runtime_report_if_enabled(
	overlay_result: Dictionary,
	click_through_result: Dictionary,
	always_on_top_result: Dictionary = {},
) -> void:
	_RuntimeReportRef.print_if_requested(
		overlay_result, click_through_result, always_on_top_result
	)
