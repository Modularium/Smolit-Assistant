extends RefCounted
## Linux Window Behavior — Backend-Resolver
##
## Wählt für einen gegebenen Capability-/Session-Snapshot das passende
## interne Backend (`backend_x11`, `backend_wayland_generic`,
## `backend_noop`). Die Auswahl ist bewusst flach und dokumentiert:
##
##   * `session_type == "x11"`     → X11-Backend
##   * `session_type == "wayland"` → generisches Wayland-Backend
##   * alles andere (`"unknown"` /
##     leer / exotisch)            → Noop-Backend
##
## Die Unterscheidung passiert ausschließlich anhand der vom
## Capability-Modul gemeldeten `session_type`. Driver-Spezifika
## (`"headless"` vs. echter Display-Driver) werden bewusst **nicht**
## zur Backend-Auswahl herangezogen — die bestehenden Controller-
## Gates lehnen unter `headless` sowieso selbst ab. So bleibt die
## Backend-Auswahl vorhersagbar auch für Dev-/CI-Szenarien, in denen
## ein echter X11-Server auf dem Host existiert, aber Godot gerade
## headless läuft.

class_name SmolitWindowBackendResolver

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")
const _BackendX11Ref := preload("res://scripts/window_behavior/backend_x11.gd")
const _BackendWaylandGenericRef := preload("res://scripts/window_behavior/backend_wayland_generic.gd")
const _BackendNoopRef := preload("res://scripts/window_behavior/backend_noop.gd")


## Wählt ein Backend basierend auf einem Capability-Snapshot. Falls
## kein Snapshot übergeben wird, holt der Resolver selbst einen
## frischen.
static func resolve(capabilities: Dictionary = {}) -> RefCounted:
	var snapshot: Dictionary = capabilities
	if snapshot.is_empty():
		snapshot = _CapabilitiesRef.detect()
	var session: String = str(snapshot.get("session_type", "unknown"))
	match session:
		"x11":
			return _BackendX11Ref.new()
		"wayland":
			return _BackendWaylandGenericRef.new()
		_:
			return _BackendNoopRef.new()
