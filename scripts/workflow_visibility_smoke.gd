extends SceneTree
## Workflow-Visibility-Overlay-Smoketest (PR 16).
##
## Zwei Ebenen:
##
##   * **Pure Modell-Ebene** — `SmolitWorkflowVisibilityModel` ist
##     reiner RefCounted-State. Wir prüfen Enums, Snippet-Kürzung,
##     Event-Mapping (heard/thinking/response + action_*/speaking_*),
##     Terminal-Semantik, Disconnect-Verhalten und die Resilienz
##     gegenüber unbekannter Reihenfolge.
##   * **Panel-Ebene** — Scene-Spawn der
##     `workflow_visibility_panel.tscn`, Snapshot-Check und Toggle.
##     Ein Headless-`--script`-Lauf registriert die EventBus-Autoloads
##     nicht, also hört das Panel keine echten Signale — wir prüfen
##     nur, dass es ohne Autoload kein Crash verursacht, den
##     Sichtbarkeits-Default `hidden` hält und die Public-API
##     (`set_overlay_visible`, `snapshot`, `reset_for_tests`)
##     funktioniert.
##
## Lauf:
##   godot --headless --path ui --script scripts/workflow_visibility_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh workflow-visibility-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _ModelRef := preload("res://scripts/workflow/workflow_visibility_model.gd")
const _PanelScene := preload("res://scenes/workflow/workflow_visibility_panel.tscn")

var _fail: int = 0


func _init() -> void:
	_check_enum_helpers()
	_check_snippet_trim()
	_check_empty_model_snapshot()
	_check_happy_path_voice_interaction()
	_check_speak_text_flow_with_speaking_lifecycle()
	_check_speaking_ended_failure_marks_step_failed()
	_check_action_failed_marks_terminal()
	_check_new_action_id_resets_workflow()
	_check_disconnect_skips_active_steps()
	_check_unknown_event_order_does_not_crash()
	_check_long_text_gets_trimmed_in_step_snippet()
	_check_approval_requested_renders_active_step()
	_check_approval_resolved_outcomes()
	_check_plan_gated_happy_path()
	_check_plan_gated_denied_path()
	_check_panel_scene_defaults_to_hidden()
	_check_panel_toggle_roundtrip()
	_check_panel_reset_for_tests_clears_model()

	print("---")
	if _fail == 0:
		print("workflow_visibility smoke: PASS")
		quit(0)
	else:
		print("workflow_visibility smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Pure model ---------------------------------------------------------


func _check_enum_helpers() -> void:
	_assert(_ModelRef.kind_name(_ModelRef.StepKind.HEARD) == "heard",
		"kind_name(HEARD) == 'heard'")
	_assert(_ModelRef.kind_name(_ModelRef.StepKind.COMPLETED) == "completed",
		"kind_name(COMPLETED) == 'completed'")
	_assert(_ModelRef.kind_name(9999) == "heard",
		"kind_name(unknown) falls back to default")
	_assert(_ModelRef.status_name(_ModelRef.Status.ACTIVE) == "active",
		"status_name(ACTIVE) == 'active'")
	_assert(_ModelRef.status_name(9999) == "pending",
		"status_name(unknown) falls back to 'pending'")
	_assert(_ModelRef.kind_label(_ModelRef.StepKind.THINKING) == "Thinking",
		"kind_label(THINKING) == 'Thinking'")
	_assert(_ModelRef.is_terminal_kind(_ModelRef.StepKind.COMPLETED),
		"is_terminal_kind(COMPLETED) == true")
	_assert(_ModelRef.is_terminal_kind(_ModelRef.StepKind.FAILED),
		"is_terminal_kind(FAILED) == true")
	_assert(not _ModelRef.is_terminal_kind(_ModelRef.StepKind.STEP),
		"is_terminal_kind(STEP) == false")
	var kinds: Array = _ModelRef.all_kinds()
	# PR 17 fügt APPROVAL hinzu → 9 Kategorien.
	_assert(kinds.size() == 9,
		"all_kinds() contains nine categories (PR 17 added APPROVAL)")
	_assert(kinds.has(_ModelRef.StepKind.APPROVAL),
		"all_kinds() includes APPROVAL")


func _check_snippet_trim() -> void:
	_assert(_ModelRef.trim_snippet("  hello  ") == "hello",
		"trim_snippet strips whitespace")
	_assert(_ModelRef.trim_snippet("") == "",
		"trim_snippet passes empty through")
	var long_text: String = ""
	for i in range(200):
		long_text += "a"
	var trimmed: String = _ModelRef.trim_snippet(long_text)
	_assert(trimmed.length() == _ModelRef.MAX_SNIPPET_CHARS,
		"trim_snippet truncates long text to MAX_SNIPPET_CHARS")
	_assert(trimmed.ends_with(_ModelRef.ELLIPSIS),
		"trim_snippet adds ellipsis on truncation")


func _check_empty_model_snapshot() -> void:
	var model = _ModelRef.new()
	var snap: Dictionary = model.snapshot()
	_assert(snap.has("steps") and (snap["steps"] as Array).is_empty(),
		"fresh model has no steps")
	_assert(not bool(snap["terminal"]),
		"fresh model is not terminal")
	_assert(not bool(snap["offline"]),
		"fresh model is not offline")
	_assert(int(snap["step_count"]) == 0,
		"fresh model has step_count == 0")
	_assert(model.is_empty(),
		"fresh model reports is_empty() == true")


func _check_happy_path_voice_interaction() -> void:
	var model = _ModelRef.new()
	model.apply_heard("turn on the light")
	model.apply_thinking()
	model.apply_response("Light is on.")
	model.apply_speaking_started({"source": "auto_speak", "provider": "command"})
	model.apply_speaking_ended({"source": "auto_speak", "provider": "command", "ok": true})
	model.apply_action_completed({"action_id": "act_000001"})

	var snap: Dictionary = model.snapshot()
	var kinds: Array = _collect_kinds(snap["steps"])
	_assert(kinds == [
			_ModelRef.StepKind.HEARD,
			_ModelRef.StepKind.THINKING,
			_ModelRef.StepKind.RESPONSE,
			_ModelRef.StepKind.SPEAKING,
			_ModelRef.StepKind.COMPLETED,
		],
		"voice happy-path renders heard → thinking → response → speaking → completed")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.THINKING) == _ModelRef.Status.DONE,
		"thinking becomes DONE after response")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.SPEAKING) == _ModelRef.Status.DONE,
		"speaking becomes DONE after speaking_ended(ok)")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.COMPLETED) == _ModelRef.Status.DONE,
		"COMPLETED terminal is DONE")
	_assert(bool(snap["terminal"]),
		"workflow is terminal after action_completed")


func _check_speak_text_flow_with_speaking_lifecycle() -> void:
	var model = _ModelRef.new()
	model.apply_action_planned({"action_id": "act_000002", "title": "Speak text"})
	model.apply_action_step({"action_id": "act_000002", "label": "TTS playback"})
	model.apply_speaking_started({"action_id": "act_000002", "source": "speak_text"})
	model.apply_speaking_ended({"action_id": "act_000002", "ok": true})
	model.apply_action_completed({"action_id": "act_000002"})

	var snap: Dictionary = model.snapshot()
	var kinds: Array = _collect_kinds(snap["steps"])
	_assert(kinds == [
			_ModelRef.StepKind.ACTION,
			_ModelRef.StepKind.STEP,
			_ModelRef.StepKind.SPEAKING,
			_ModelRef.StepKind.COMPLETED,
		],
		"speak_text flow renders action → step → speaking → completed")
	_assert(int(snap["step_count"]) == 1,
		"step_count increments with each action_step")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.ACTION) == _ModelRef.Status.DONE,
		"ACTION marked DONE after completed")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.STEP) == _ModelRef.Status.DONE,
		"STEP marked DONE after completed")


func _check_speaking_ended_failure_marks_step_failed() -> void:
	var model = _ModelRef.new()
	model.apply_speaking_started({"action_id": "act_000003"})
	model.apply_speaking_ended({"action_id": "act_000003", "ok": false,
			"error_class": "exit_nonzero"})
	var snap: Dictionary = model.snapshot()
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.SPEAKING) == _ModelRef.Status.FAILED,
		"speaking step is FAILED after speaking_ended(!ok)")
	var snippet: String = _snippet_for(snap["steps"], _ModelRef.StepKind.SPEAKING)
	_assert(snippet == "exit_nonzero",
		"speaking snippet carries error_class on failure")
	# Speaking_ended(!ok) wird am Modell nicht als Terminal gewertet —
	# ein nachfolgendes `action_failed` übernimmt das Terminal-Flag.
	_assert(not bool(snap["terminal"]),
		"speaking_ended(!ok) alone is not a terminal state")


func _check_action_failed_marks_terminal() -> void:
	var model = _ModelRef.new()
	model.apply_action_planned({"action_id": "act_000004", "title": "Open calendar"})
	model.apply_action_step({"action_id": "act_000004", "label": "Dispatch"})
	model.apply_action_failed({"action_id": "act_000004", "message": "Permission denied"})
	var snap: Dictionary = model.snapshot()
	_assert(bool(snap["terminal"]),
		"action_failed sets terminal")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.ACTION) == _ModelRef.Status.FAILED,
		"active ACTION becomes FAILED on action_failed")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.STEP) == _ModelRef.Status.FAILED,
		"active STEP becomes FAILED on action_failed")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.FAILED) == _ModelRef.Status.FAILED,
		"terminal FAILED step is FAILED")


func _check_new_action_id_resets_workflow() -> void:
	var model = _ModelRef.new()
	model.apply_action_planned({"action_id": "act_000010", "title": "first"})
	model.apply_action_step({"action_id": "act_000010", "label": "step"})
	# Neuer Workflow mit anderer action_id → Reset.
	model.apply_action_planned({"action_id": "act_000011", "title": "second"})
	var snap: Dictionary = model.snapshot()
	var action_ids: Array = _collect_action_ids(snap["steps"])
	_assert(action_ids.size() == 1,
		"new action_id resets previous workflow (single step left)")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.STEP) == -1,
		"step kind from previous workflow is gone after reset")
	_assert(int(snap["step_count"]) == 0,
		"step_count is reset when workflow restarts")


func _check_disconnect_skips_active_steps() -> void:
	var model = _ModelRef.new()
	model.apply_heard("hello")
	model.apply_thinking()
	model.apply_disconnected()
	var snap: Dictionary = model.snapshot()
	_assert(bool(snap["offline"]),
		"disconnect sets offline")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.THINKING) == _ModelRef.Status.SKIPPED,
		"active thinking becomes SKIPPED on disconnect")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.HEARD) == _ModelRef.Status.DONE,
		"done heard stays DONE through disconnect")
	_assert(not bool(snap["terminal"]),
		"disconnect does not set terminal (reconnect can resume)")


func _check_unknown_event_order_does_not_crash() -> void:
	var model = _ModelRef.new()
	# Unsinnige Reihenfolgen — vor `action_planned` kommt bereits ein
	# `action_step`; vor jedem `heard` ein `speaking_ended`. Das Modell
	# muss das tolerieren.
	model.apply_speaking_ended({"ok": true})
	model.apply_action_step({"label": "orphan step"})
	model.apply_response("stray response")
	model.apply_heard("late heard")
	var snap: Dictionary = model.snapshot()
	_assert(not (snap["steps"] as Array).is_empty(),
		"model accumulates steps even in weird order (no crash)")
	_assert(int(snap["step_count"]) >= 1,
		"step_count increments on orphan action_step")
	# Leere Payloads für action_planned dürfen nichts werfen.
	model.apply_action_planned({})
	model.apply_action_completed({})
	_assert(bool(model.is_terminal()),
		"apply_action_completed with empty payload still marks terminal")


func _check_long_text_gets_trimmed_in_step_snippet() -> void:
	var model = _ModelRef.new()
	var long_text: String = ""
	for i in range(400):
		long_text += "x"
	model.apply_response(long_text)
	var snap: Dictionary = model.snapshot()
	var snippet: String = _snippet_for(snap["steps"], _ModelRef.StepKind.RESPONSE)
	_assert(snippet.length() == _ModelRef.MAX_SNIPPET_CHARS,
		"response snippet is trimmed to MAX_SNIPPET_CHARS")
	_assert(snippet.ends_with(_ModelRef.ELLIPSIS),
		"response snippet ends with ellipsis when truncated")


func _check_approval_requested_renders_active_step() -> void:
	var model = _ModelRef.new()
	model.apply_approval_requested({
		"approval_id": "apr_000001",
		"title": "Open calendar",
		"message": "Open calendar?",
		"risk": "high",
	})
	var snap: Dictionary = model.snapshot()
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.APPROVAL) == _ModelRef.Status.ACTIVE,
		"APPROVAL step is ACTIVE after approval_requested")
	var snippet: String = _snippet_for(snap["steps"], _ModelRef.StepKind.APPROVAL)
	_assert(snippet.contains("high") and snippet.contains("Open calendar"),
		"APPROVAL snippet carries risk + title")
	# Modell-Label für APPROVAL ist stabil.
	_assert(_ModelRef.kind_label(_ModelRef.StepKind.APPROVAL) == "Approval",
		"kind_label(APPROVAL) == 'Approval'")


func _check_approval_resolved_outcomes() -> void:
	# approved → DONE
	var model_ok = _ModelRef.new()
	model_ok.apply_approval_requested({"approval_id": "apr_ok", "title": "t", "risk": "low"})
	model_ok.apply_approval_resolved({"approval_id": "apr_ok", "decision": "approved",
			"source": "user"})
	_assert(_status_for(model_ok.snapshot()["steps"], _ModelRef.StepKind.APPROVAL)
			== _ModelRef.Status.DONE,
		"approved → APPROVAL status DONE")
	# denied → FAILED
	var model_deny = _ModelRef.new()
	model_deny.apply_approval_requested({"approval_id": "apr_no", "title": "t"})
	model_deny.apply_approval_resolved({"approval_id": "apr_no", "decision": "denied",
			"source": "user"})
	_assert(_status_for(model_deny.snapshot()["steps"], _ModelRef.StepKind.APPROVAL)
			== _ModelRef.Status.FAILED,
		"denied → APPROVAL status FAILED")
	# timed_out → SKIPPED
	var model_to = _ModelRef.new()
	model_to.apply_approval_requested({"approval_id": "apr_to", "title": "t"})
	model_to.apply_approval_resolved({"approval_id": "apr_to", "decision": "timed_out",
			"source": "timeout"})
	_assert(_status_for(model_to.snapshot()["steps"], _ModelRef.StepKind.APPROVAL)
			== _ModelRef.Status.SKIPPED,
		"timed_out → APPROVAL status SKIPPED")
	# Unbekannte Decision → SKIPPED (defensive, kein Leak auf DONE).
	var model_unknown = _ModelRef.new()
	model_unknown.apply_approval_requested({"approval_id": "apr_x", "title": "t"})
	model_unknown.apply_approval_resolved({"approval_id": "apr_x", "decision": "weird"})
	_assert(_status_for(model_unknown.snapshot()["steps"], _ModelRef.StepKind.APPROVAL)
			== _ModelRef.Status.SKIPPED,
		"unknown decision defaults to SKIPPED")


# --- Panel scene --------------------------------------------------------


func _check_plan_gated_happy_path() -> void:
	# PR 18 — Approval-Gated Demo-Action-Planner. Die gesamte Kette
	# läuft durch die bestehenden Projektions-Hooks; das Modell muss
	# ACTION, APPROVAL, STEP und COMPLETED konsistent tragen.
	var model = _ModelRef.new()
	model.apply_action_planned({"action_id": "act_plan_1", "title": "Gated plan"})
	model.apply_approval_requested({
		"approval_id": "apr_plan_1",
		"action_id": "act_plan_1",
		"title": "Gated plan",
		"risk": "medium",
	})
	model.apply_approval_resolved({
		"approval_id": "apr_plan_1",
		"action_id": "act_plan_1",
		"decision": "approved",
		"source": "user",
	})
	model.apply_action_step({"action_id": "act_plan_1", "label": "Demo step"})
	model.apply_action_completed({"action_id": "act_plan_1"})

	var snap: Dictionary = model.snapshot()
	var kinds: Array = _collect_kinds(snap["steps"])
	_assert(kinds == [
			_ModelRef.StepKind.ACTION,
			_ModelRef.StepKind.APPROVAL,
			_ModelRef.StepKind.STEP,
			_ModelRef.StepKind.COMPLETED,
		],
		"plan→approval→approved→completed renders full chain")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.APPROVAL) == _ModelRef.Status.DONE,
		"APPROVAL DONE after approved in plan flow")
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.ACTION) == _ModelRef.Status.DONE,
		"ACTION DONE after completed in plan flow")
	_assert(bool(snap["terminal"]),
		"plan flow is terminal after action_completed")


func _check_plan_gated_denied_path() -> void:
	# PR 18 — Bei Deny darf der Executor nicht laufen. Das Modell
	# spiegelt das: APPROVAL → FAILED, ACTION kippt durch das
	# anschließende `action_cancelled` auf FAILED.
	var model = _ModelRef.new()
	model.apply_action_planned({"action_id": "act_plan_2", "title": "Gated plan"})
	model.apply_approval_requested({
		"approval_id": "apr_plan_2",
		"action_id": "act_plan_2",
		"title": "Gated plan",
	})
	model.apply_approval_resolved({
		"approval_id": "apr_plan_2",
		"action_id": "act_plan_2",
		"decision": "denied",
		"source": "user",
	})
	model.apply_action_cancelled({"action_id": "act_plan_2",
			"message": "Action denied by user"})

	var snap: Dictionary = model.snapshot()
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.APPROVAL) == _ModelRef.Status.FAILED,
		"APPROVAL FAILED after denied in plan flow")
	# `apply_action_cancelled` in PR 16 appends a FAILED terminal step
	# (wird intern auf `apply_action_failed` umgebogen); ACTION selbst
	# wird auf FAILED gekippt.
	_assert(_status_for(snap["steps"], _ModelRef.StepKind.ACTION) == _ModelRef.Status.FAILED,
		"ACTION FAILED after cancel in plan-denied flow")
	_assert(bool(snap["terminal"]),
		"plan-denied flow is terminal after cancel")


func _check_panel_scene_defaults_to_hidden() -> void:
	var panel := _spawn_panel()
	if panel == null:
		_assert(false, "workflow_visibility_panel failed to spawn")
		return
	# Ohne `SMOLIT_WORKFLOW_OVERLAY=1` muss das Panel hidden sein, auch
	# wenn es im Tree hängt. Events dürfen trotzdem akzeptiert werden.
	_assert(not panel.visible,
		"panel defaults to hidden (no SMOLIT_WORKFLOW_OVERLAY opt-in)")
	_assert(panel.has_method("snapshot"),
		"panel exposes snapshot()")
	var snap: Dictionary = panel.call("snapshot")
	_assert(snap.has("steps"),
		"panel snapshot carries steps key")
	_despawn(panel)


func _check_panel_toggle_roundtrip() -> void:
	var panel := _spawn_panel()
	if panel == null:
		_assert(false, "workflow_visibility_panel failed to spawn for toggle test")
		return
	_assert(panel.has_method("set_overlay_visible"),
		"panel exposes set_overlay_visible()")
	panel.call("set_overlay_visible", true)
	_assert(panel.visible,
		"set_overlay_visible(true) makes panel visible")
	_assert(bool(panel.call("is_overlay_visible")),
		"is_overlay_visible reports true after toggle")
	panel.call("set_overlay_visible", false)
	_assert(not panel.visible,
		"set_overlay_visible(false) hides panel")
	_despawn(panel)


func _check_panel_reset_for_tests_clears_model() -> void:
	var panel := _spawn_panel()
	if panel == null:
		_assert(false, "workflow_visibility_panel failed to spawn for reset test")
		return
	_assert(panel.has_method("reset_for_tests"),
		"panel exposes reset_for_tests()")
	panel.call("reset_for_tests")
	var snap: Dictionary = panel.call("snapshot")
	_assert((snap["steps"] as Array).is_empty(),
		"reset_for_tests() empties the step list")
	_assert(not bool(snap["terminal"]),
		"reset_for_tests() clears terminal flag")
	_despawn(panel)


# --- Helpers ------------------------------------------------------------


func _collect_kinds(steps: Array) -> Array:
	var out: Array = []
	for step in steps:
		out.append(int((step as Dictionary).get("kind", -1)))
	return out


func _collect_action_ids(steps: Array) -> Array:
	var out: Array = []
	for step in steps:
		var id: String = String((step as Dictionary).get("action_id", ""))
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


func _status_for(steps: Array, kind: int) -> int:
	for step in steps:
		if int((step as Dictionary).get("kind", -1)) == kind:
			return int((step as Dictionary).get("status", -1))
	return -1


func _snippet_for(steps: Array, kind: int) -> String:
	for step in steps:
		if int((step as Dictionary).get("kind", -1)) == kind:
			return String((step as Dictionary).get("snippet", ""))
	return ""


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
