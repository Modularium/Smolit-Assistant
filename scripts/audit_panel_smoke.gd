extends SceneTree
## Local Audit Trail v1 Smoketest (PR 19).
##
## Zwei Ebenen:
##
##   * **Pure Ebene** — `SmolitAuditModel` ist reine RefCounted-
##     Logik: kuratierte Kind-Labels, Color-Tabellen, defensive
##     Payload-Lesung, kosmetisches Kürzen von IDs/Summaries und
##     kurzes `HH:MM:SS`-Format.
##   * **Panel-Ebene** — Scene-Spawn der `audit_panel.tscn`. Ohne
##     `SMOLIT_UI_DEV_CONTROLS=1` bleibt das Panel hidden. Wir
##     prüfen das Render-Verhalten: leere Liste → Statuszeile
##     „No entries yet"; mehrere Events → eine Kind-Zeile pro
##     Event; fehlende Felder crashen nicht; lange Summaries werden
##     optisch gekürzt; `set_panel_visible` erlaubt Toggle.
##
## Scope-Grenzen:
##
##   * Keine echten EventBus-Roundtrips (Headless-`--script` lädt
##     die Autoloads nicht).
##   * Keine Persistenz-, Export- oder Kopierfunktion wird getestet,
##     weil sie nicht existiert.
##
## Lauf:
##   godot --headless --path ui --script scripts/audit_panel_smoke.gd
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _ModelRef := preload("res://scripts/audit/audit_model.gd")
const _PanelScene := preload("res://scenes/audit/audit_panel.tscn")

var _fail: int = 0


func _init() -> void:
	_check_kind_labels()
	_check_is_known_kind()
	_check_result_and_risk_colors()
	_check_short_id_and_summary()
	_check_short_time()
	_check_events_from_payload_is_defensive()

	_check_ipc_client_and_event_bus_wired()

	_check_panel_defaults_to_hidden()
	_check_panel_renders_events()
	_check_panel_tolerates_missing_fields()
	_check_panel_truncates_long_summary_in_row()
	_check_panel_toggle_visibility()
	_check_panel_reset_for_tests()

	print("---")
	if _fail == 0:
		print("audit_panel smoke: PASS")
		quit(0)
	else:
		print("audit_panel smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Pure helpers -------------------------------------------------------


func _check_kind_labels() -> void:
	_assert(_ModelRef.kind_label("action_planned") == "planned",
		"kind_label('action_planned') == 'planned'")
	_assert(_ModelRef.kind_label("approval_requested") == "apr req",
		"kind_label('approval_requested') == 'apr req'")
	_assert(_ModelRef.kind_label("ipc_command_rejected") == "cmd rej",
		"kind_label('ipc_command_rejected') == 'cmd rej'")
	# Unknown kind → pass-through lowercase.
	_assert(_ModelRef.kind_label("mystery") == "mystery",
		"kind_label('mystery') passes the raw value through")
	_assert(_ModelRef.kind_label(null) == "?",
		"kind_label(null) renders as '?'")
	_assert(_ModelRef.kind_label("") == "?",
		"kind_label('') renders as '?'")


func _check_is_known_kind() -> void:
	for k in _ModelRef.KNOWN_KINDS:
		_assert(_ModelRef.is_known_kind(k),
			"is_known_kind('%s') == true" % k)
	_assert(not _ModelRef.is_known_kind("bogus"),
		"is_known_kind('bogus') == false")


func _check_result_and_risk_colors() -> void:
	var approved := _ModelRef.result_color("approved")
	var denied := _ModelRef.result_color("denied")
	_assert(approved != denied,
		"result_color distinguishes approved from denied")
	_assert(_ModelRef.result_color("unknown") == Color(1, 1, 1, 0.6),
		"result_color falls back to neutral for unknown")
	_assert(_ModelRef.risk_color("high") != _ModelRef.risk_color("low"),
		"risk_color distinguishes low from high")
	_assert(_ModelRef.risk_color("nope") == Color(1, 1, 1, 0.55),
		"risk_color falls back to neutral for unknown")


func _check_short_id_and_summary() -> void:
	_assert(_ModelRef.short_id("") == "",
		"short_id('') == ''")
	_assert(_ModelRef.short_id("aud_000001") == "aud_000001",
		"short_id does not truncate short ids")
	var long_id: String = "a".repeat(40)
	var trimmed_id: String = _ModelRef.short_id(long_id)
	_assert(trimmed_id.length() <= _ModelRef.MAX_ID_CHARS,
		"short_id truncates to MAX_ID_CHARS")
	_assert(trimmed_id.ends_with(_ModelRef.ELLIPSIS),
		"short_id ends with ellipsis when truncated")

	var long_summary: String = "x".repeat(200)
	var trimmed_sum: String = _ModelRef.short_summary(long_summary)
	_assert(trimmed_sum.length() <= _ModelRef.MAX_SUMMARY_CHARS,
		"short_summary truncates to MAX_SUMMARY_CHARS")
	_assert(trimmed_sum.ends_with(_ModelRef.ELLIPSIS),
		"short_summary ends with ellipsis when truncated")
	_assert(_ModelRef.short_summary(null) == "",
		"short_summary(null) == ''")


func _check_short_time() -> void:
	_assert(_ModelRef.short_time(0) == "",
		"short_time(0) == '' (treats 0 as unset)")
	_assert(_ModelRef.short_time(-1) == "",
		"short_time(<0) returns empty string")
	# 1970-01-01 00:00:01 UTC → "00:00:01"
	_assert(_ModelRef.short_time(1000) == "00:00:01",
		"short_time(1000 ms) == '00:00:01'")
	# Regression-sanity: 01:02:03 → hours mod 24 applied.
	var ms: int = (1 * 3600 + 2 * 60 + 3) * 1000
	_assert(_ModelRef.short_time(ms) == "01:02:03",
		"short_time(3723 s) == '01:02:03'")


func _check_events_from_payload_is_defensive() -> void:
	_assert(_ModelRef.events_from_payload(null).is_empty(),
		"events_from_payload(null) is empty")
	_assert(_ModelRef.events_from_payload(42).is_empty(),
		"events_from_payload(non-dict) is empty")
	_assert(_ModelRef.events_from_payload({}).is_empty(),
		"events_from_payload({}) is empty")
	_assert(_ModelRef.events_from_payload({"events": "not-an-array"}).is_empty(),
		"events_from_payload({events:non-array}) is empty")
	var payload: Dictionary = {"events": [{"kind": "action_planned"}, "junk", 42,
			{"kind": "action_completed"}]}
	_assert(_ModelRef.events_from_payload(payload).size() == 2,
		"events_from_payload drops non-dictionary entries")


# --- IpcClient / EventBus wiring ---------------------------------------


func _check_ipc_client_and_event_bus_wired() -> void:
	var ipc_text: String = _read_file("res://autoload/ipc_client.gd")
	_assert(ipc_text.find("func audit_recent") >= 0,
		"ipc_client.gd exposes audit_recent()")
	_assert(ipc_text.find("\"audit_recent\"") >= 0,
		"ipc_client.gd emits `audit_recent` frame type")
	_assert(ipc_text.find("audit_recent_received.emit") >= 0,
		"ipc_client.gd routes `audit_recent` to EventBus")
	var bus_text: String = _read_file("res://autoload/event_bus.gd")
	_assert(bus_text.find("signal audit_recent_received") >= 0,
		"event_bus.gd declares audit_recent_received signal")


# --- Panel scene --------------------------------------------------------


func _check_panel_defaults_to_hidden() -> void:
	var panel := _spawn_panel()
	if panel == null:
		_assert(false, "audit_panel scene failed to instantiate")
		return
	_assert(not panel.visible,
		"audit_panel defaults to hidden without SMOLIT_UI_DEV_CONTROLS")
	var snap: Dictionary = panel.call("current_snapshot")
	_assert(int(snap.get("event_count", -1)) == 0,
		"panel snapshot reports zero events at startup")
	_despawn(panel)


func _check_panel_renders_events() -> void:
	var panel := _spawn_panel()
	panel.call("set_payload", {"events": [
		{"audit_id": "aud_1", "timestamp_ms": 1000, "kind": "action_planned",
			"action_id": "act_1", "risk": "medium", "summary": "Plan"},
		{"audit_id": "aud_2", "timestamp_ms": 2000, "kind": "action_completed",
			"action_id": "act_1", "result": "completed", "summary": "Done"},
	]})
	var snap: Dictionary = panel.call("current_snapshot")
	_assert(int(snap["event_count"]) == 2,
		"panel renders one row per event")
	_assert(String(snap["status"]).contains("2"),
		"panel status label reports event count")
	_despawn(panel)


func _check_panel_tolerates_missing_fields() -> void:
	var panel := _spawn_panel()
	# Alle Felder fehlen außer kind → Panel rendert trotzdem ohne
	# Crash (kein Null-Access).
	panel.call("set_payload", {"events": [
		{"kind": "approval_requested"},
		{},  # leer
		{"kind": "unknown_kind_x"},
	]})
	var snap: Dictionary = panel.call("current_snapshot")
	_assert(int(snap["event_count"]) == 3,
		"panel renders rows for sparse payloads (no crash)")
	_despawn(panel)


func _check_panel_truncates_long_summary_in_row() -> void:
	# Wir prüfen die Helper-Funktion direkt — Panel-interne
	# Labels sind nicht vom Smoke lesbar.
	var long: String = "y".repeat(200)
	var trimmed: String = _ModelRef.short_summary(long)
	_assert(trimmed.length() < long.length(),
		"long summaries are visually truncated by short_summary")
	_assert(trimmed.ends_with(_ModelRef.ELLIPSIS),
		"truncated summaries end with ellipsis")


func _check_panel_toggle_visibility() -> void:
	var panel := _spawn_panel()
	_assert(not panel.visible, "panel starts hidden")
	panel.call("set_panel_visible", true)
	_assert(panel.visible, "set_panel_visible(true) shows the panel")
	_assert(bool(panel.call("is_panel_visible")),
		"is_panel_visible reports true after toggle on")
	panel.call("set_panel_visible", false)
	_assert(not panel.visible, "set_panel_visible(false) hides the panel")
	_despawn(panel)


func _check_panel_reset_for_tests() -> void:
	var panel := _spawn_panel()
	panel.call("set_payload", {"events": [{"kind": "action_planned"}]})
	panel.call("reset_for_tests")
	var snap: Dictionary = panel.call("current_snapshot")
	_assert(int(snap["event_count"]) == 0,
		"reset_for_tests clears rendered rows")
	_despawn(panel)


# --- Helpers ------------------------------------------------------------


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("audit_panel_smoke: cannot open %s" % path)
		return ""
	return f.get_as_text()


func _spawn_panel() -> Node:
	var instance: Node = _PanelScene.instantiate()
	if instance == null:
		return null
	root.add_child(instance)
	return instance


func _despawn(instance: Node) -> void:
	if instance == null:
		return
	root.remove_child(instance)
	instance.queue_free()
