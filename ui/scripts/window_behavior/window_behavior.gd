extends RefCounted
## Linux Window Behavior — schmale Fassade
##
## Einziger Einstiegspunkt aus `main.gd` in die
## `ui/scripts/window_behavior/`-Schicht. Die Schicht ist intern nach
## vier Rollen getrennt:
##
##   * **Detection / Capability** — `window_capabilities.gd`.
##   * **Probe / Verification**   — `window_probe.gd` (opt-in,
##                                   reversibel, diagnostisch).
##   * **Activation**             — drei unabhängige Controller mit
##                                   eigenen Env-Flags:
##                                   `overlay_controller.gd`
##                                   (`SMOLIT_UI_OVERLAY=1`),
##                                   `overlay_click_through_controller.gd`
##                                   (`SMOLIT_UI_CLICK_THROUGH=1`),
##                                   `overlay_always_on_top_controller.gd`
##                                   (`SMOLIT_UI_ALWAYS_ON_TOP=1`).
##   * **Reporting**              — `overlay_runtime_report.gd`
##                                   (opt-in, `SMOLIT_WINDOW_REPORT=1`).
##
## Alle Aktivierungspfade teilen ein gemeinsames Ergebnis-Vokabular
## (`requested / capable / applied / observed / active / reason`),
## definiert in `window_behavior_result.gd`. Pfad-spezifische Achsen
## (Bounds, Zonen, Session-Details, …) bleiben erhalten.
##
## Leitregeln:
##   * kein Autoload, kein Node, kein Singleton-State; alles
##     funktionsbasiert, Rückgabe per Dictionary.
##   * keine Business-/Presence-Entscheidungen.
##   * kein stiller Nebeneffekt: jedes Feature hat ein eigenes
##     Env-Flag und verweigert ehrlich, wenn die Vorbedingungen
##     nicht stimmen.
##   * keine IPC-/EventBus-Anbindung.

class_name SmolitWindowBehavior

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")
const _ProbeRef := preload("res://scripts/window_behavior/window_probe.gd")
const _OverlayRef := preload("res://scripts/window_behavior/overlay_controller.gd")
const _ClickThroughRef := preload("res://scripts/window_behavior/overlay_click_through_controller.gd")
const _AlwaysOnTopRef := preload("res://scripts/window_behavior/overlay_always_on_top_controller.gd")
const _RuntimeReportRef := preload("res://scripts/window_behavior/overlay_runtime_report.gd")
const _ResultRef := preload("res://scripts/window_behavior/window_behavior_result.gd")
const _BackendResolverRef := preload("res://scripts/window_behavior/backend_resolver.gd")


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


## Convenience-Einstiegspunkt: führt Probe, dann die drei
## Aktivierungspfade (Overlay, Click-through, X11-AOT) in der
## kanonischen Reihenfolge aus und schließt mit dem opt-in Runtime-
## Report ab. Die drei Aktivierungen laufen über ein intern
## aufgelöstes **Backend** (`backend_x11` / `backend_wayland_generic` /
## `backend_noop`), das aktuell fast nur Delegation ist — die
## plattformseitige Realität liegt weiter in den Controller-Gates.
## Das Backend-Routing ist die Struktur, auf die spätere
## Compositor-spezifische Pfade aufsetzen könnten.
##
## Rückgabe ist ein Dict mit den drei Aktivierungsergebnissen, dem
## Probe-Ergebnis und dem gewählten `backend_id` (Diagnosehilfe).
## `main.gd` hält wie bisher den Click-through-Controller-Ref über
## `click_through_result["controller"]` am Leben.
##
## Der explizite Pfad (ein Call je Controller) bleibt gleichwertig
## unterstützt, siehe die einzelnen Fassadenfunktionen oben.
static func apply_all(anchor: Node) -> Dictionary:
	var probe_result: Dictionary = _ProbeRef.run_if_enabled()
	# Capability-Snapshot einmal holen und weitergeben — der Resolver
	# braucht ihn, der Report kann ihn über overlay_result aufgreifen.
	var capabilities: Dictionary = _CapabilitiesRef.detect()
	var backend: RefCounted = _BackendResolverRef.resolve(capabilities)
	var overlay_result: Dictionary = backend.activate_overlay_if_requested(anchor)
	var click_through_result: Dictionary = \
		backend.activate_click_through_if_requested(anchor, overlay_result)
	var always_on_top_result: Dictionary = \
		backend.activate_always_on_top_if_requested(anchor)
	_RuntimeReportRef.print_if_requested(
		overlay_result, click_through_result, always_on_top_result
	)
	return {
		"probe": probe_result,
		"backend_id": backend.backend_id,
		"backend_description": backend.backend_description,
		"overlay": overlay_result,
		"click_through": click_through_result,
		"always_on_top": always_on_top_result,
	}


## Diagnose-Hilfe: welches Backend würde für einen gegebenen (oder
## frischen) Capability-Snapshot aktuell gewählt? Nützlich für Docs,
## Verifikation und Tooling, ohne den ganzen `apply_all()`-Lauf
## auszuführen.
static func resolve_backend(capabilities: Dictionary = {}) -> RefCounted:
	return _BackendResolverRef.resolve(capabilities)


## Zeigt das gemeinsame Aktivierungs-Schema (siehe
## `window_behavior_result.gd`). Nützlich für Tools / Tests, die das
## Vokabular programmatisch referenzieren wollen.
static func activation_result_schema() -> Array:
	return _ResultRef.ACTIVATION_KEYS
