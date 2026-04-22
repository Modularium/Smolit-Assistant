extends RefCounted
## Linux Window Behavior — Overlay Click-through MVP (Phase 3b, Phase B Folge)
##
## Opt-in Folgeschritt auf den Overlay-MVP. Aktiv **nur**, wenn
## * `SMOLIT_UI_OVERLAY=1` gesetzt ist (Voraussetzung aus §F.2),
## * `SMOLIT_UI_CLICK_THROUGH=1` gesetzt ist,
## * der Overlay-Controller einen wirklich aktiven Overlay-Modus meldet,
## * die Click-through-Capability tragfähig ist (`available`/`experimental`),
## * und sich mindestens eine *gültige* interaktive Zone aus dem
##   aktuellen Layout ableiten lässt.
##
## Was dieser Schritt wirklich tut (nur im Erfolgspfad):
##   * pro bewusst gelistetem UI-Anker-Knoten (Allowlist unten) ein Rect
##     in Anchor-/Viewport-Koordinaten snapshotten,
##   * Rects validieren: Rect muss sichtbar + größer als Mindestgröße
##     sein, sonst fallen sie raus,
##   * Rects am Viewport clampen, sichtbar ragende Geometrie wird auf
##     den gültigen Bereich reduziert,
##   * alle gültigen Zonen zu *einer* Bounding-Rect-Union vereinigen,
##   * daraus ein einzelnes Rechteckpolygon bauen und
##     `DisplayServer.window_set_mouse_passthrough(region)` setzen.
##
## Was er bewusst **nicht** tut:
##   * keine neue IPC-Nachricht, kein neuer EventBus-Kanal, keine neue
##     Presence-/Avatar-Wahrheit. Click-through lebt ausschließlich in
##     der Fensterhülle, nicht im Zustandsmodell.
##   * keine compositor-spezifischen Pfade (layer-shell, GNOME-Extension).
##   * kein Always-on-top — in dieser Phase ausdrücklich nicht
##     versprochen.
##   * **keine Multi-Polygon-Passthrough-Shapes.** Godots
##     `DisplayServer.window_set_mouse_passthrough` kennt pro Fenster
##     genau *einen* Polygonpfad. Der MVP vereinigt alle aktuell
##     sichtbaren Zonen daher zur Bounding-Rect-Union. Leerer Raum
##     *innerhalb* dieser Union bleibt klickbar — das ist ehrlich
##     gröber als XShape-Multirect und ausdrücklich noch nicht das
##     finale Interaktionsmodell. Multi-Polygon / präzisere Input-
##     Regionen bleiben Folgearbeit (§F.3 "Offene Punkte").
##   * keine Wiederherstellung der vorherigen Passthrough-Region beim
##     Verlassen der Anwendung. Godot räumt beim Window-Close selbst auf.
##
## Lebenszyklus kurz:
##   1. `_try_activate()` validiert Env + Overlay + Capability. Schlägt
##      *eine* dieser Vorbedingungen fehl, geht der Controller nicht in
##      den aktiven Zustand — keine Signale, keine deferred-Arbeit, er
##      wird nicht persistiert.
##   2. Bei tragfähigen Vorbedingungen werden die Tracked-Nodes
##      gesammelt, Signale (`visibility_changed`, `resized`) verbunden
##      und eine erste Zonen-/Rect-Berechnung versucht.
##   3. Zusätzlich schedult der Controller **einmalig** einen
##      `call_deferred`-Refresh. Der fängt den Fall, dass einzelne
##      Panel-Sizes zu `_ready()`-Zeit noch nicht final berechnet sind
##      und erst nach dem ersten Layout-Pass stabil stehen.
##   4. Spätere Änderungen (neues Banner erscheint, Window resized)
##      fließen über die verbundenen Signale in `_refresh_region()`.
##
## Capability-/Fallback-Semantik (zusammen mit `SmolitOverlayController`)
## und die zugehörigen Log-Zeilen sind in `_log_summary` dokumentiert.

class_name SmolitOverlayClickThroughController

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")

const ENABLE_ENV_VAR: String = "SMOLIT_UI_CLICK_THROUGH"

## Mindestkantenlänge in Pixeln, unter der eine Zone als degeneriert
## verworfen wird. Fängt u.a. den Fall ab, dass ein Control zur
## `_ready()`-Zeit noch mit Größe (0,0) anliegt, bevor der erste
## Layout-Pass seine tatsächliche Ausdehnung bestimmt hat.
const _MIN_ZONE_DIMENSION: float = 2.0

## Explizite Allowlist interaktiver Zonen. Reihenfolge spielt keine
## Rolle — wir vereinen ohnehin zu einer Bounding-Union. Der `purpose`
## taucht nur im Log auf, erklärt dort aber warum der Knoten klickbar
## bleiben muss. Nicht gelistete Knoten werden absichtlich *nicht*
## passthrough-geschützt.
const _TRACKED_ZONES: Array = [
	{"path": "Avatar", "purpose": "presence avatar"},
	{"path": "VBox/HeaderRow", "purpose": "status + header controls"},
	{"path": "VBox/ActionBanner", "purpose": "action/target banner"},
	{"path": "VBox/ApprovalBanner", "purpose": "approve/deny buttons"},
	{"path": "VBox/DiscoveryPanel", "purpose": "accessibility discovery list"},
	{"path": "VBox/DockPanel", "purpose": "log + expanded input"},
	{"path": "CompactInputPanel", "purpose": "compact quick input"},
]

var _anchor: Control = null
## Liste von {node, path, purpose}-Einträgen. Gefüllt genau dann, wenn
## der Controller in den aktiven Lebenszyklus eintritt.
var _tracked: Array = []
var _active: bool = false
var _signals_connected: bool = false
var _initial_refresh_scheduled: bool = false
var _last_bounds: Rect2 = Rect2()
var _last_has_bounds: bool = false


static func is_requested() -> bool:
	var raw := OS.get_environment(ENABLE_ENV_VAR).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


## Erzeugt eine frische Controller-Instanz und versucht — wenn angefordert
## und möglich — den Click-through-Modus zu aktivieren. Der Controller
## wird in `status["controller"]` nur zurückgegeben, wenn er noch
## laufende Arbeit hat (Signale, geplantes deferred-Refresh). `main.gd`
## muss diese Referenz halten, damit die Subscriptions am Leben bleiben.
static func activate_if_requested(anchor: Node, overlay_result: Dictionary) -> Dictionary:
	var controller := SmolitOverlayClickThroughController.new()
	var status := controller._try_activate(anchor, overlay_result)
	if controller._should_persist():
		status["controller"] = controller
	return status


## Der Controller soll nur dann am Leben gehalten werden, wenn er noch
## laufende Subscriptions / geplante Refresh-Arbeit hat. In allen frühen
## Abbruchpfaden (fehlende Env, Overlay nicht aktiv, Capability nicht
## tragfähig) halten wir ihn nicht künstlich — er wird mit dem Status-
## Dict verworfen.
func _should_persist() -> bool:
	return _signals_connected or _initial_refresh_scheduled


# --- Activation ----------------------------------------------------------


func _try_activate(anchor: Node, overlay_result: Dictionary) -> Dictionary:
	var requested := is_requested()
	var overlay_requested: bool = bool(overlay_result.get("requested", false))
	var overlay_active: bool = bool(overlay_result.get("active", false))

	var summary := {
		"requested": requested,
		"overlay_requested": overlay_requested,
		"overlay_active": overlay_active,
		"capable": false,
		"zones_derived": 0,
		"zones_valid": 0,
		"active": false,
		"bounds": null,
		"zones": [],
		"reason": "",
	}

	if not overlay_requested:
		summary["reason"] = "overlay not requested (SMOLIT_UI_OVERLAY unset)"
		_log_summary(summary)
		return summary

	if not requested:
		summary["reason"] = "click-through not requested (SMOLIT_UI_CLICK_THROUGH unset)"
		_log_summary(summary)
		return summary

	if not overlay_active:
		summary["reason"] = "overlay inactive — click-through would leave avatar over an opaque window"
		_log_summary(summary)
		return summary

	var capabilities: Dictionary = overlay_result.get("capabilities", _CapabilitiesRef.detect())
	var click_cap: Dictionary = capabilities.get("click_through", {})
	var click_status := int(click_cap.get("status", _CapabilitiesRef.Status.UNKNOWN))
	var click_reason := str(click_cap.get("reason", ""))
	summary["capability_status"] = _CapabilitiesRef.name_of_status(click_status)
	summary["capability_reason"] = click_reason

	if click_status == _CapabilitiesRef.Status.UNSUPPORTED \
			or click_status == _CapabilitiesRef.Status.UNKNOWN:
		summary["reason"] = "click-through capability %s: %s" % [
			_CapabilitiesRef.name_of_status(click_status),
			click_reason,
		]
		_log_summary(summary)
		return summary

	if not (anchor is Control):
		summary["reason"] = "anchor is not a Control; cannot derive interactive zones"
		_log_summary(summary)
		return summary

	summary["capable"] = true
	if click_status == _CapabilitiesRef.Status.EXPERIMENTAL:
		print("[click-through] capability experimental — activating with honest warning (%s)" % click_reason)

	_anchor = anchor
	_tracked = _collect_tracked_nodes(_anchor)
	if _tracked.is_empty():
		summary["reason"] = "no tracked UI nodes found under anchor — layout may have changed"
		_log_summary(summary)
		return summary

	# Signale werden bereits jetzt verbunden — auch für aktuell
	# unsichtbare Panels. So triggert ein später erscheinendes
	# Action-/Approval-Banner seinen Refresh selbst, ohne dass wir eine
	# eigene Überwachungsschleife brauchen.
	_connect_signals()

	var report := _derive_zones()
	summary["zones_derived"] = int(report["derived_count"])
	summary["zones_valid"] = int(report["valid_count"])
	summary["bounds"] = report["bounds"]
	summary["zones"] = report["zones"]

	if int(report["valid_count"]) > 0 and typeof(report["bounds"]) == TYPE_RECT2:
		var bounds: Rect2 = report["bounds"]
		if _apply_passthrough(bounds):
			_active = true
			_last_bounds = bounds
			_last_has_bounds = true
			summary["active"] = true
			summary["reason"] = "active with %d zone(s)" % int(report["valid_count"])
		else:
			summary["reason"] = "DisplayServer.window_set_mouse_passthrough not available on this build"
	else:
		summary["reason"] = "no valid interactive zones yet — waiting for first stable layout"

	_log_summary(summary)

	# Einmaliger post-layout Nachzieher. `_ready()` läuft vor dem ersten
	# Idle-Frame; einige Panel-Größen (z. B. DockPanel im VBox) werden
	# erst dort stabil. `call_deferred` wartet bis Ende des aktuellen
	# Frames, d. h. nach dem ersten Layout-Pass.
	_schedule_initial_refresh()

	return summary


# --- Zone collection & validation ---------------------------------------


static func _collect_tracked_nodes(anchor: Control) -> Array:
	var found: Array = []
	for entry_variant in _TRACKED_ZONES:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var path := str(entry.get("path", ""))
		if path == "":
			continue
		var node := anchor.get_node_or_null(path)
		if node is Control:
			found.append({
				"node": node,
				"path": path,
				"purpose": str(entry.get("purpose", "")),
			})
	return found


## Bildet pro sichtbarem + gültigem Tracked-Node einen Rect2 in
## Anchor-Koordinaten und die gemeinsame Bounding-Box. Ungültige Rects
## werden *still* übersprungen (Mini-/Null-Size, Layout-noch-nicht-
## stabil) — das ist Absicht, damit der Single-Polygon-Union nicht durch
## Degenerate-Rects unsichtbar aufgebläht wird.
func _derive_zones() -> Dictionary:
	var zones: Array = []
	var derived_count := 0
	var bounds: Rect2 = Rect2()
	var has_bounds := false

	if _anchor == null:
		return {
			"zones": zones,
			"derived_count": 0,
			"valid_count": 0,
			"bounds": null,
		}

	var anchor_origin: Vector2 = _anchor.get_global_position()
	var viewport_size: Vector2 = _anchor.get_viewport_rect().size
	# Root-Control mit preset=15 ⇒ Anchor-Koordinaten = Viewport-
	# Koordinaten. Wir clampen daher an das Viewport-Rect, um off-screen
	# Geometrie (z. B. vorübergehend falsch positionierte Panels) nicht
	# in die Passthrough-Region zu übernehmen.
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)

	for entry_variant in _tracked:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var node: Control = entry.get("node", null) as Control
		if node == null or not is_instance_valid(node):
			continue
		if not node.is_visible_in_tree():
			continue
		derived_count += 1

		var raw_size: Vector2 = node.size
		if raw_size.x <= 0.0 or raw_size.y <= 0.0:
			# Layout noch nicht stabil oder Control absichtlich
			# zusammengeklappt — tragen wir nichts bei.
			continue

		var local_pos: Vector2 = node.get_global_position() - anchor_origin
		var raw_rect := Rect2(local_pos, raw_size)
		var clamped := _clamp_to_viewport(raw_rect, viewport_rect)
		if not _is_valid_rect(clamped):
			continue

		zones.append({
			"path": entry.get("path", ""),
			"purpose": entry.get("purpose", ""),
			"rect": clamped,
		})
		if not has_bounds:
			bounds = clamped
			has_bounds = true
		else:
			bounds = bounds.merge(clamped)

	var result := {
		"zones": zones,
		"derived_count": derived_count,
		"valid_count": zones.size(),
		"bounds": null,
	}
	if has_bounds:
		result["bounds"] = bounds
	return result


## Rect ∩ Viewport. Rect2.intersection liefert `Rect2()` (Size = 0), wenn
## die Rects sich nicht schneiden — dieser Fall wird über
## `_is_valid_rect` ausgefiltert.
static func _clamp_to_viewport(rect: Rect2, viewport_rect: Rect2) -> Rect2:
	return rect.intersection(viewport_rect)


static func _is_valid_rect(rect: Rect2) -> bool:
	return rect.size.x >= _MIN_ZONE_DIMENSION and rect.size.y >= _MIN_ZONE_DIMENSION


# --- Passthrough application --------------------------------------------


func _apply_passthrough(bounds: Rect2) -> bool:
	if not DisplayServer.has_method("window_set_mouse_passthrough"):
		return false
	# Vier Ecken im Uhrzeigersinn ⇒ geschlossenes Rechteck. Godots
	# DisplayServer akzeptiert pro Fenster genau einen Polygonpfad.
	var polygon := PackedVector2Array([
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + bounds.size,
		bounds.position + Vector2(0.0, bounds.size.y),
	])
	DisplayServer.window_set_mouse_passthrough(polygon)
	return true


func _clear_passthrough() -> void:
	if DisplayServer.has_method("window_set_mouse_passthrough"):
		# Leere Region ⇒ Godot-Fenster nimmt wieder alle Mouse-Events an
		# (Standardverhalten). Kein Click-through mehr.
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


# --- Refresh on layout / visibility changes -----------------------------


func _connect_signals() -> void:
	if _signals_connected:
		return
	for entry_variant in _tracked:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var node: Control = entry.get("node", null) as Control
		if node == null or not is_instance_valid(node):
			continue
		if not node.visibility_changed.is_connected(_on_tracked_visibility_changed):
			node.visibility_changed.connect(_on_tracked_visibility_changed)
		if not node.resized.is_connected(_on_tracked_resized):
			node.resized.connect(_on_tracked_resized)
	if is_instance_valid(_anchor):
		if not _anchor.resized.is_connected(_on_anchor_resized):
			_anchor.resized.connect(_on_anchor_resized)
	_signals_connected = true


func _schedule_initial_refresh() -> void:
	if _initial_refresh_scheduled:
		return
	_initial_refresh_scheduled = true
	# call_deferred wartet bis zum Ende des aktuellen Idle-Frames — nach
	# dem ersten Layout-Pass. Kein Polling, kein Timer-Loop.
	call_deferred("_initial_refresh")


func _initial_refresh() -> void:
	_refresh_region("initial")


func _on_tracked_visibility_changed() -> void:
	_refresh_region("visibility_changed")


func _on_tracked_resized() -> void:
	_refresh_region("tracked_resized")


func _on_anchor_resized() -> void:
	_refresh_region("anchor_resized")


## Zentraler Refresh-Pfad. Aktualisiert die Passthrough-Region nur bei
## echter Änderung (Dedup über `_last_bounds`) und loggt entsprechend
## knapp. Alle Branches behandeln beide Zustände (aktiv/inaktiv), damit
## der Controller sauber aus dem „keine Zonen"-Tal herauskommt, sobald
## wieder eine sichtbare Zone vorhanden ist.
func _refresh_region(cause: String) -> void:
	if not _signals_connected:
		return
	var report := _derive_zones()
	var bounds_variant: Variant = report["bounds"]
	var valid_count := int(report["valid_count"])

	if valid_count <= 0 or typeof(bounds_variant) != TYPE_RECT2:
		if _active:
			_clear_passthrough()
			_active = false
			_last_has_bounds = false
			print("[click-through] refresh (%s): no valid zones — passthrough cleared (overlay remains interactive)" % cause)
		# Kein Log, wenn wir ohnehin nicht aktiv waren — kein Rauschen.
		return

	var bounds: Rect2 = bounds_variant

	# Dedup: gleiche Bounding-Box wie beim letzten Apply ⇒ nichts zu tun,
	# kein Log. Spart das Log-Rauschen, wenn ein Resize von mehreren
	# Nodes gleichzeitig feuert, aber die Union-Box gleich bleibt.
	if _active and _last_has_bounds \
			and _last_bounds.position.is_equal_approx(bounds.position) \
			and _last_bounds.size.is_equal_approx(bounds.size):
		return

	if not _apply_passthrough(bounds):
		# Sollte in der Praxis nicht passieren, wenn wir zuvor aktiviert
		# waren — aber ehrlich loggen statt stumm bleiben.
		print("[click-through] refresh (%s): DisplayServer.window_set_mouse_passthrough unavailable" % cause)
		return

	_active = true
	_last_bounds = bounds
	_last_has_bounds = true
	print("[click-through] refresh (%s): zones_valid=%d bounds=%s" % [
		cause,
		valid_count,
		_format_rect(bounds),
	])


# --- Logging -------------------------------------------------------------


## Kompakte Phasen-Zusammenfassung. Eine Zeile für die Statusachsen,
## optional Capability-Details, optional Zonenliste, optional Reason.
## Ziel: aus *einer* Log-Ausgabe ablesbar, warum der Controller
## aktiviert wurde — oder warum nicht.
func _log_summary(summary: Dictionary) -> void:
	print("[click-through] requested=%s overlay_requested=%s overlay_active=%s capable=%s zones_derived=%d zones_valid=%d active=%s" % [
		bool(summary.get("requested", false)),
		bool(summary.get("overlay_requested", false)),
		bool(summary.get("overlay_active", false)),
		bool(summary.get("capable", false)),
		int(summary.get("zones_derived", 0)),
		int(summary.get("zones_valid", 0)),
		bool(summary.get("active", false)),
	])
	var capability_status: Variant = summary.get("capability_status", null)
	if capability_status != null:
		print("[click-through] capability=%s (%s)" % [
			capability_status,
			summary.get("capability_reason", ""),
		])
	if int(summary.get("zones_valid", 0)) > 0:
		var bounds_variant: Variant = summary.get("bounds", null)
		if typeof(bounds_variant) == TYPE_RECT2:
			print("[click-through] bounds=%s" % _format_rect(bounds_variant))
		for zone_variant in summary.get("zones", []):
			if typeof(zone_variant) != TYPE_DICTIONARY:
				continue
			var zone: Dictionary = zone_variant
			print("[click-through]   zone: path=%s rect=%s (%s)" % [
				zone.get("path", ""),
				_format_rect(zone.get("rect", Rect2())),
				zone.get("purpose", ""),
			])
	var reason := str(summary.get("reason", ""))
	if reason != "":
		print("[click-through] reason: %s" % reason)


static func _format_rect(rect_variant: Variant) -> String:
	if typeof(rect_variant) != TYPE_RECT2:
		return "—"
	var rect: Rect2 = rect_variant
	return "(%.0f,%.0f %.0fx%.0f)" % [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]
