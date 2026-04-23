extends SceneTree
## Approval Card UX v1 Smoketest (PR 17).
##
## Zwei Ebenen:
##
##   * **Pure Ebene** — `SmolitApprovalModel` ist reine RefCounted-
##     Logik (Risk-Sanitizer, Summary-/Title-Kürzung, Decision-
##     Outcome-Mapping). Diese Tests laufen ohne Scene-Tree.
##   * **Card-Ebene** — Scene-Spawn der `approval_card.tscn`, direkt
##     in den SceneTree gehängt. `--script`-Mode registriert die
##     Autoloads nicht; die Card erkennt das, bleibt ohne
##     Autoload-Bus still. Wir füttern sie direkt über die
##     Handler-Funktionen, prüfen den sichtbaren Snapshot, den
##     Resolving-Zustand und das Disconnect-Verhalten.
##
## Die IPC-Kommandos (`approval_approve`, `approval_deny`,
## `request_approval_demo`) werden zusätzlich als Quelltext-Assertion
## am `ipc_client.gd` geprüft, damit ein versehentliches Umbenennen
## auffällt.
##
## Lauf:
##   godot --headless --path ui --script scripts/approval_card_smoke.gd
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _ModelRef := preload("res://scripts/approval/approval_model.gd")
const _CardScene := preload("res://scenes/approval/approval_card.tscn")

var _fail: int = 0


func _init() -> void:
	_check_risk_sanitizer()
	_check_risk_label_and_color()
	_check_title_and_summary_trim()
	_check_decision_outcome_mapping()
	_check_is_terminal_decision()

	_check_ipc_client_has_new_commands()

	_check_card_defaults_hidden()
	_check_card_rendering_on_requested()
	_check_card_trims_long_summary()
	_check_card_resolving_flow_approve()
	_check_card_resolving_flow_deny()
	_check_card_resolved_mismatch_does_not_mutate()
	_check_card_ipc_disconnected_disables_buttons()
	_check_card_tolerates_missing_fields()
	_check_card_reset_for_tests()

	print("---")
	if _fail == 0:
		print("approval_card smoke: PASS")
		quit(0)
	else:
		print("approval_card smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Pure helpers -------------------------------------------------------


func _check_risk_sanitizer() -> void:
	_assert(_ModelRef.sanitize_risk("low") == "low",
		"sanitize_risk('low') == 'low'")
	_assert(_ModelRef.sanitize_risk("HIGH") == "high",
		"sanitize_risk('HIGH') == 'high'")
	_assert(_ModelRef.sanitize_risk("  medium  ") == "medium",
		"sanitize_risk trims whitespace")
	_assert(_ModelRef.sanitize_risk("") == _ModelRef.DEFAULT_RISK,
		"sanitize_risk('') falls back to medium")
	_assert(_ModelRef.sanitize_risk("critical") == _ModelRef.DEFAULT_RISK,
		"sanitize_risk('critical') falls back to medium")
	_assert(_ModelRef.sanitize_risk(null) == _ModelRef.DEFAULT_RISK,
		"sanitize_risk(null) falls back to medium")
	_assert(_ModelRef.sanitize_risk(42) == _ModelRef.DEFAULT_RISK,
		"sanitize_risk(non-string) falls back to medium")


func _check_risk_label_and_color() -> void:
	_assert(_ModelRef.risk_label("high") == "high",
		"risk_label('high') == 'high'")
	_assert(_ModelRef.risk_label("bogus") == _ModelRef.DEFAULT_RISK,
		"risk_label('bogus') falls back to medium")
	var color_low: Color = _ModelRef.risk_color("low")
	var color_high: Color = _ModelRef.risk_color("high")
	_assert(color_low != color_high,
		"risk_color distinguishes low from high")
	var color_default: Color = _ModelRef.risk_color("nonsense")
	_assert(color_default == _ModelRef.risk_color(_ModelRef.DEFAULT_RISK),
		"risk_color(unknown) == risk_color(default)")


func _check_title_and_summary_trim() -> void:
	_assert(_ModelRef.trim_title("  hello  ") == "hello",
		"trim_title strips whitespace")
	var long_title: String = ""
	for i in range(_ModelRef.MAX_TITLE_CHARS + 20):
		long_title += "a"
	var trimmed_title: String = _ModelRef.trim_title(long_title)
	_assert(trimmed_title.length() == _ModelRef.MAX_TITLE_CHARS,
		"trim_title truncates to MAX_TITLE_CHARS")
	_assert(trimmed_title.ends_with(_ModelRef.ELLIPSIS),
		"trim_title adds ellipsis on truncation")
	_assert(_ModelRef.trim_summary("") == "",
		"trim_summary('') == ''")
	var long_summary: String = ""
	for i in range(_ModelRef.MAX_SUMMARY_CHARS + 50):
		long_summary += "x"
	var trimmed_summary: String = _ModelRef.trim_summary(long_summary)
	_assert(trimmed_summary.length() == _ModelRef.MAX_SUMMARY_CHARS,
		"trim_summary truncates to MAX_SUMMARY_CHARS")
	_assert(trimmed_summary.ends_with(_ModelRef.ELLIPSIS),
		"trim_summary adds ellipsis on truncation")
	_assert(_ModelRef.trim_summary(null) == "",
		"trim_summary(null) == ''")


func _check_decision_outcome_mapping() -> void:
	_assert(_ModelRef.decision_outcome("approved") == "approved",
		"decision_outcome('approved') == 'approved'")
	_assert(_ModelRef.decision_outcome("denied") == "failed",
		"decision_outcome('denied') == 'failed'")
	_assert(_ModelRef.decision_outcome("cancelled") == "failed",
		"decision_outcome('cancelled') == 'failed'")
	_assert(_ModelRef.decision_outcome("timed_out") == "skipped",
		"decision_outcome('timed_out') == 'skipped'")
	_assert(_ModelRef.decision_outcome("expired") == "skipped",
		"decision_outcome('expired') == 'skipped'")
	_assert(_ModelRef.decision_outcome("bogus") == "unknown",
		"decision_outcome('bogus') == 'unknown'")


func _check_is_terminal_decision() -> void:
	for d in ["approved", "denied", "cancelled", "timed_out", "expired"]:
		_assert(_ModelRef.is_terminal_decision(d),
			"is_terminal_decision('%s') == true" % d)
	_assert(not _ModelRef.is_terminal_decision(""),
		"is_terminal_decision('') == false")
	_assert(not _ModelRef.is_terminal_decision("bogus"),
		"is_terminal_decision('bogus') == false")
	_assert(not _ModelRef.is_terminal_decision(null),
		"is_terminal_decision(null) == false")


# --- IpcClient wiring ---------------------------------------------------


func _check_ipc_client_has_new_commands() -> void:
	var text: String = _read_file("res://autoload/ipc_client.gd")
	_assert(text.find("func approval_approve") >= 0,
		"ipc_client.gd exposes approval_approve()")
	_assert(text.find("func approval_deny") >= 0,
		"ipc_client.gd exposes approval_deny()")
	_assert(text.find("func request_approval_demo") >= 0,
		"ipc_client.gd exposes request_approval_demo()")
	_assert(text.find("\"approval_approve\"") >= 0,
		"ipc_client.gd emits `approval_approve` frame type")
	_assert(text.find("\"approval_deny\"") >= 0,
		"ipc_client.gd emits `approval_deny` frame type")
	_assert(text.find("\"request_approval_demo\"") >= 0,
		"ipc_client.gd emits `request_approval_demo` frame type")


# --- Card scene ---------------------------------------------------------


func _check_card_defaults_hidden() -> void:
	var card := _spawn_card()
	if card == null:
		_assert(false, "approval_card scene failed to instantiate")
		return
	_assert(not card.visible,
		"approval_card starts hidden")
	var snap: Dictionary = card.call("current_snapshot")
	_assert(String(snap.get("approval_id", "x")) == "",
		"snapshot carries empty approval_id when idle")
	_assert(bool(snap.get("approve_disabled", false)),
		"approve button is disabled when no approval is open")
	_assert(bool(snap.get("deny_disabled", false)),
		"deny button is disabled when no approval is open")
	_despawn(card)


func _check_card_rendering_on_requested() -> void:
	var card := _spawn_card()
	card.call("_on_approval_requested", {
		"approval_id": "apr_000001",
		"title": "Open calendar",
		"message": "Open the calendar app?",
		"risk": "high",
	})
	_assert(card.visible,
		"approval_card becomes visible after approval_requested")
	var snap: Dictionary = card.call("current_snapshot")
	_assert(String(snap["approval_id"]) == "apr_000001",
		"snapshot carries approval_id after request")
	_assert(String(snap["title"]) == "Open calendar",
		"snapshot carries title")
	_assert(String(snap["summary"]) == "Open the calendar app?",
		"snapshot carries summary (short enough, no ellipsis)")
	_assert(String(snap["risk_label"]) == "high",
		"snapshot carries risk label 'high'")
	_despawn(card)


func _check_card_trims_long_summary() -> void:
	var card := _spawn_card()
	var long_text: String = ""
	for i in range(_ModelRef.MAX_SUMMARY_CHARS + 100):
		long_text += "z"
	card.call("_on_approval_requested", {
		"approval_id": "apr_long",
		"title": "t",
		"message": long_text,
		"risk": "medium",
	})
	var snap: Dictionary = card.call("current_snapshot")
	var summary: String = String(snap["summary"])
	_assert(summary.length() == _ModelRef.MAX_SUMMARY_CHARS,
		"approval_card trims long summary to MAX_SUMMARY_CHARS")
	_assert(summary.ends_with(_ModelRef.ELLIPSIS),
		"approval_card long summary ends with ellipsis")
	_despawn(card)


func _check_card_resolving_flow_approve() -> void:
	var card := _spawn_card()
	card.call("_on_approval_requested", {
		"approval_id": "apr_resolve_ok",
		"title": "t",
		"message": "s",
		"risk": "low",
	})
	# Klick → intern setzen wir `_resolving = true` und den Status.
	card.call("_on_approve_pressed")
	var snap: Dictionary = card.call("current_snapshot")
	_assert(bool(snap["resolving"]),
		"resolving == true after approve pressed")
	# Zweiter Klick während resolving darf nichts mehr triggern; wir
	# prüfen über die Signal-Zähler via eigener Verbindung.
	var approve_count: int = 0
	card.approve_pressed.connect(func(_id): approve_count += 1)
	card.call("_on_approve_pressed")
	_assert(approve_count == 0,
		"approve_pressed is idempotent while resolving")
	# Eingehender Resolve-Event räumt den Slot auf.
	card.call("_on_approval_resolved", {
		"approval_id": "apr_resolve_ok",
		"decision": "approved",
		"source": "user",
	})
	snap = card.call("current_snapshot")
	_assert(String(snap["approval_id"]) == "",
		"approval_id cleared after resolved")
	_assert(String(snap["status"]).contains("approved"),
		"status line reflects decision 'approved'")
	_despawn(card)


func _check_card_resolving_flow_deny() -> void:
	var card := _spawn_card()
	card.call("_on_approval_requested", {
		"approval_id": "apr_resolve_deny",
		"title": "t",
		"message": "s",
		"risk": "medium",
	})
	card.call("_on_deny_pressed")
	var snap: Dictionary = card.call("current_snapshot")
	_assert(bool(snap["resolving"]),
		"resolving == true after deny pressed")
	card.call("_on_approval_resolved", {
		"approval_id": "apr_resolve_deny",
		"decision": "denied",
		"source": "user",
	})
	snap = card.call("current_snapshot")
	_assert(String(snap["status"]).contains("denied"),
		"status line reflects decision 'denied'")
	_despawn(card)


func _check_card_resolved_mismatch_does_not_mutate() -> void:
	var card := _spawn_card()
	card.call("_on_approval_requested", {
		"approval_id": "apr_target",
		"title": "t",
		"message": "s",
		"risk": "low",
	})
	# Anderes approval_id → Card-Slot bleibt unverändert.
	card.call("_on_approval_resolved", {
		"approval_id": "apr_wrong",
		"decision": "approved",
		"source": "user",
	})
	var snap: Dictionary = card.call("current_snapshot")
	_assert(String(snap["approval_id"]) == "apr_target",
		"mismatched approval_id leaves the held slot untouched")
	_despawn(card)


func _check_card_ipc_disconnected_disables_buttons() -> void:
	var card := _spawn_card()
	card.call("_on_approval_requested", {
		"approval_id": "apr_disc",
		"title": "t",
		"message": "s",
		"risk": "low",
	})
	card.call("_on_ipc_disconnected")
	var snap: Dictionary = card.call("current_snapshot")
	_assert(bool(snap["approve_disabled"]),
		"approve button disabled after ipc_disconnected")
	_assert(bool(snap["deny_disabled"]),
		"deny button disabled after ipc_disconnected")
	_assert(String(snap["status"]).contains("offline"),
		"status line reflects offline state")
	_despawn(card)


func _check_card_tolerates_missing_fields() -> void:
	var card := _spawn_card()
	# Payload ohne title/message/risk — Card muss defaulten, nicht
	# crashen, und den Slot trotzdem halten.
	card.call("_on_approval_requested", {"approval_id": "apr_bare"})
	var snap: Dictionary = card.call("current_snapshot")
	_assert(card.visible,
		"card still renders with minimal payload")
	_assert(String(snap["approval_id"]) == "apr_bare",
		"approval_id held from minimal payload")
	_assert(String(snap["risk_label"]) == _ModelRef.DEFAULT_RISK,
		"risk defaults to medium for missing field")
	# Payload ohne approval_id wird defensiv ignoriert.
	card.call("_on_approval_requested", {"title": "orphan"})
	snap = card.call("current_snapshot")
	_assert(String(snap["approval_id"]) == "apr_bare",
		"payload without approval_id does not replace the held slot")
	_despawn(card)


func _check_card_reset_for_tests() -> void:
	var card := _spawn_card()
	card.call("_on_approval_requested", {
		"approval_id": "apr_reset",
		"title": "t",
		"message": "s",
		"risk": "low",
	})
	card.call("reset_for_tests")
	_assert(not card.visible,
		"reset_for_tests hides the card")
	var snap: Dictionary = card.call("current_snapshot")
	_assert(String(snap["approval_id"]) == "",
		"reset_for_tests clears approval_id")
	_despawn(card)


# --- Helpers ------------------------------------------------------------


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("approval_card_smoke: cannot open %s" % path)
		return ""
	return f.get_as_text()


func _spawn_card() -> Node:
	var instance: Node = _CardScene.instantiate()
	if instance == null:
		return null
	root.add_child(instance)
	return instance


func _despawn(instance: Node) -> void:
	if instance == null:
		return
	root.remove_child(instance)
	instance.queue_free()
