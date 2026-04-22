extends SceneTree
## Workflow-Overlay-State-Smoketest.
##
## Prüft die pure Logik in
## `ui/scripts/workflow_overlay/workflow_overlay_state.gd` ohne
## Scene-Tree. Deckt Skeleton-Erzeugung, Fallback-Verhalten von
## `safe_string`, Label-Auflösungsketten, Step-Hint-Formatierung und
## die Phase→DisplayMode-Ableitung ab.
##
## Lauf:
##   godot --headless --path ui --script scripts/workflow_overlay_state_smoke.gd
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst. Der Test dient
## als schnelle Regressionsabsicherung für PR 2 (Collapse/Expand +
## robustere Label-Rekonstruktion) und ist bewusst klein — er
## instanziiert keine Szene und keinen Controller.

const _StateRef := preload("res://scripts/workflow_overlay/workflow_overlay_state.gd")

var _fail: int = 0


func _init() -> void:
	_check_skeleton()
	_check_safe_string()
	_check_phase_to_display_mode()
	_check_trigger_label_chain()
	_check_action_label_chain()
	_check_step_label_strict()
	_check_result_and_cancel_labels()
	_check_step_hint()
	_check_enum_names()

	print("---")
	if _fail == 0:
		print("workflow_overlay_state smoke: PASS")
		quit(0)
	else:
		print("workflow_overlay_state smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Cases ---------------------------------------------------------------


func _check_skeleton() -> void:
	var flow := _StateRef.new_flow()
	_assert(flow.get("phase") == _StateRef.Phase.HIDDEN, "new_flow phase is HIDDEN")
	_assert(flow.get("display_mode") == _StateRef.DisplayMode.COLLAPSED, "new_flow display_mode is COLLAPSED")
	_assert(int(flow.get("step_count", -1)) == 0, "new_flow step_count starts at 0")
	_assert(str(flow.get("action_id", "x")) == "", "new_flow action_id empty by default")

	var nodes: Array = flow["nodes"]
	_assert(nodes.size() == 3, "new_flow has three nodes")
	var expected_roles := [
		_StateRef.NodeRole.TRIGGER,
		_StateRef.NodeRole.ACTION,
		_StateRef.NodeRole.RESULT,
	]
	for i in range(nodes.size()):
		var entry: Dictionary = nodes[i]
		_assert(int(entry.get("role", -1)) == expected_roles[i],
			"node %d role == expected" % i)
		_assert(int(entry.get("state", -1)) == _StateRef.NodeState.IDLE,
			"node %d starts IDLE" % i)
	var edges: Array = flow["edges"]
	_assert(edges.size() == 2, "new_flow has two edges")


func _check_safe_string() -> void:
	_assert(_StateRef.safe_string({}, "title", "Fallback") == "Fallback",
		"safe_string missing key → fallback")
	_assert(_StateRef.safe_string({"title": "  Hallo  "}, "title") == "Hallo",
		"safe_string strips whitespace")
	_assert(_StateRef.safe_string({"title": 123}, "title", "x") == "x",
		"safe_string non-string → fallback")
	_assert(_StateRef.safe_string({"title": ""}, "title", "y") == "",
		"safe_string empty value (not fallback) returns empty string")


func _check_phase_to_display_mode() -> void:
	_assert(_StateRef.display_mode_for_phase(_StateRef.Phase.HIDDEN) == _StateRef.DisplayMode.COLLAPSED,
		"HIDDEN → COLLAPSED")
	_assert(_StateRef.display_mode_for_phase(_StateRef.Phase.PLANNED) == _StateRef.DisplayMode.COLLAPSED,
		"PLANNED → COLLAPSED")
	_assert(_StateRef.display_mode_for_phase(_StateRef.Phase.ACTIVE) == _StateRef.DisplayMode.EXPANDED,
		"ACTIVE → EXPANDED")
	_assert(_StateRef.display_mode_for_phase(_StateRef.Phase.COMPLETED) == _StateRef.DisplayMode.EXPANDED,
		"COMPLETED → EXPANDED")
	_assert(_StateRef.display_mode_for_phase(_StateRef.Phase.FAILED) == _StateRef.DisplayMode.EXPANDED,
		"FAILED → EXPANDED")
	_assert(_StateRef.display_mode_for_phase(_StateRef.Phase.UNKNOWN) == _StateRef.DisplayMode.EXPANDED,
		"UNKNOWN → EXPANDED")


func _check_trigger_label_chain() -> void:
	# Explicit `trigger` wins over everything else.
	_assert(_StateRef.trigger_label_from_payload({"trigger": "User"}) == "User",
		"trigger_label: explicit trigger wins")
	# `origin` is second.
	_assert(_StateRef.trigger_label_from_payload({"origin": "voice"}) == "Voice",
		"trigger_label: origin capitalized")
	# action_kind maps to friendly categories.
	_assert(_StateRef.trigger_label_from_payload({"action_kind": "speech"}) == "Voice",
		"trigger_label: action_kind=speech → Voice")
	_assert(_StateRef.trigger_label_from_payload({"action_kind": "query"}) == "User text",
		"trigger_label: action_kind=query → User text")
	_assert(_StateRef.trigger_label_from_payload({"action_kind": "automation"}) == "Automation",
		"trigger_label: action_kind=automation")
	_assert(_StateRef.trigger_label_from_payload({}) == "Start",
		"trigger_label: empty → Start")


func _check_action_label_chain() -> void:
	_assert(_StateRef.action_label_from_payload({"title": "Open calendar"}) == "Open calendar",
		"action_label: title wins")
	_assert(_StateRef.action_label_from_payload({"description": "Working on plan"}) == "Working on plan",
		"action_label: description when no title")
	_assert(_StateRef.action_label_from_payload({"action_kind": "speech"}) == "Speech",
		"action_label: action_kind capitalized")
	_assert(_StateRef.action_label_from_payload({}) == "Working…",
		"action_label: empty → Working…")


func _check_step_label_strict() -> void:
	# step_label returns empty on empty — the controller must not
	# overwrite the existing label with nothing.
	_assert(_StateRef.step_label_from_payload({}) == "",
		"step_label: empty payload → empty string")
	_assert(_StateRef.step_label_from_payload({"title": "Step one"}) == "Step one",
		"step_label: title honored")
	_assert(_StateRef.step_label_from_payload({"description": "detail"}) == "detail",
		"step_label: description fallback")


func _check_result_and_cancel_labels() -> void:
	_assert(_StateRef.result_label_from_payload({"message": "OK"}, "Done") == "OK",
		"result_label: message wins")
	_assert(_StateRef.result_label_from_payload({"status": "completed"}, "Done") == "Completed",
		"result_label: status capitalized")
	_assert(_StateRef.result_label_from_payload({}, "Failed") == "Failed",
		"result_label: empty → fallback")
	_assert(_StateRef.cancel_label_from_payload({"message": "User aborted"}) == "User aborted",
		"cancel_label: message wins")
	_assert(_StateRef.cancel_label_from_payload({}) == "Cancelled",
		"cancel_label: empty → Cancelled")


func _check_step_hint() -> void:
	_assert(_StateRef.step_hint_from_count(0) == "",
		"step_hint: 0 → empty")
	_assert(_StateRef.step_hint_from_count(1) == "",
		"step_hint: 1 → empty (no hint for single step)")
	_assert(_StateRef.step_hint_from_count(3) == "Step 3",
		"step_hint: 3 → Step 3")


func _check_enum_names() -> void:
	_assert(_StateRef.phase_name(_StateRef.Phase.FAILED) == "failed",
		"phase_name FAILED")
	_assert(_StateRef.node_state_name(_StateRef.NodeState.COMPLETED) == "completed",
		"node_state_name COMPLETED")
	_assert(_StateRef.role_name(_StateRef.NodeRole.ACTION) == "action",
		"role_name ACTION")
	_assert(_StateRef.display_mode_name(_StateRef.DisplayMode.EXPANDED) == "expanded",
		"display_mode_name EXPANDED")
