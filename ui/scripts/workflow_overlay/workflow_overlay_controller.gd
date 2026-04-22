extends Control
## Workflow-Overlay — read-only UI-Projektion der Core-Action-Events
##
## Erster MVP-Spike der in `docs/ui_architecture.md` §6a/§8a
## beschriebenen Workflow-Overlay-Linie. Der Controller konsumiert die
## bestehenden Action Events (`action_planned` / `action_started` /
## `action_step` / `action_completed` / `action_failed`) aus dem
## EventBus und projiziert daraus einen kleinen symbolischen Kurz-Flow
## mit drei Knoten: Trigger → Action → Result.
##
## Bindende Grenzen (siehe auch ROADMAP Phase 3.4 und
## `docs/api.md` „UI-Projektion: Workflow Overlay"):
##   * **Read-only / core-driven.** Der Controller sendet *keine*
##     neuen IPC-Nachrichten. Er konsumiert ausschließlich vorhandene
##     Signale des `EventBus`.
##   * **Kein eigenes Logiksystem.** Keine Entscheidungen, kein
##     Workflow-Authoring, keine Graph-Struktur. Drei feste UI-Knoten
##     reichen für die Kurzprojektion.
##   * **Lokaler State nur als Projektion.** Keine Persistenz, keine
##     Session-übergreifende Wahrheit, keine neue Core-API.
##   * **Graceful fallback.** Unvollständige Events werden mit
##     neutralen Defaults behandelt; fehlende Felder werden still
##     ignoriert.
##   * **Keine Desktop-Automation in der UI.** Selbstverständlich.
##
## Sichtbarkeit: der Overlay ist standardmäßig unsichtbar. Er zeigt
## sich beim ersten `action_planned` und versteckt sich nach einem
## Disconnect. Nach terminalen Events (`completed` / `failed`) bleibt
## der Flow kurz sichtbar, damit der Nutzer das Ergebnis sieht; der
## nächste `action_planned` überschreibt den Zustand.

const _StateRef := preload("res://scripts/workflow_overlay/workflow_overlay_state.gd")
const _NodeViewRef := preload("res://scripts/workflow_overlay/workflow_node_view.gd")
const _EdgeViewRef := preload("res://scripts/workflow_overlay/workflow_edge_view.gd")

## Kurze Default-Beschriftungen pro Rolle, falls das Event keine
## nutzbaren Textfelder liefert. Bewusst generisch.
const _DEFAULT_ROLE_LABEL: Dictionary = {
	_StateRef.NodeRole.TRIGGER: "Trigger",
	_StateRef.NodeRole.ACTION: "Action",
	_StateRef.NodeRole.RESULT: "Result",
}

## Feste Schlüsselreihenfolge innerhalb der Dreier-Struktur.
const _ROLE_INDEX_TRIGGER: int = 0
const _ROLE_INDEX_ACTION: int = 1
const _ROLE_INDEX_RESULT: int = 2

var _flow: Dictionary = _StateRef.new_flow()

@onready var _row: HBoxContainer = $Row
@onready var _trigger_view: PanelContainer = $Row/TriggerNode
@onready var _edge_a: Control = $Row/EdgeA
@onready var _action_view: PanelContainer = $Row/ActionNode
@onready var _edge_b: Control = $Row/EdgeB
@onready var _result_view: PanelContainer = $Row/ResultNode


func _ready() -> void:
	# Mouse-Passthrough: der Overlay darf keine Klicks fangen. Er ist
	# rein Anzeige — der Avatar und andere Panels bleiben klickbar.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_connect_event_bus()
	_apply_flow_to_views()
	_apply_visibility()


func _connect_event_bus() -> void:
	# Defensiv: falls der Autoload unerwarteterweise fehlt, bleibt der
	# Overlay still statt zu crashen.
	if not Engine.has_singleton("EventBus") and not _has_autoload("EventBus"):
		push_warning("workflow_overlay: EventBus autoload not available; overlay stays hidden.")
		return
	EventBus.ipc_disconnected.connect(_on_ipc_disconnected)
	EventBus.action_planned_received.connect(_on_action_planned)
	EventBus.action_started_received.connect(_on_action_started)
	EventBus.action_step_received.connect(_on_action_step)
	EventBus.action_completed_received.connect(_on_action_completed)
	EventBus.action_failed_received.connect(_on_action_failed)
	# `action_cancelled` behandeln wir als „unknown-Abschluss", damit
	# ein Abbruch optisch einen klaren Endzustand bekommt.
	EventBus.action_cancelled_received.connect(_on_action_cancelled)


static func _has_autoload(name: String) -> bool:
	var root := Engine.get_main_loop()
	if root is SceneTree:
		var tree := root as SceneTree
		return tree.root.has_node("/root/" + name)
	return false


# --- Event handlers ------------------------------------------------------


func _on_ipc_disconnected() -> void:
	# Verbindung weg → kein bekannter Flow mehr. Neutralisieren.
	_reset_flow("ipc disconnected")
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_planned(payload: Dictionary) -> void:
	# Neuer Flow beginnt. Wir überschreiben immer frisch — eine
	# laufende Action kann durch einen neuen `action_planned` implizit
	# abgelöst werden (Core-Semantik), und für unseren Kurzprojektions-
	# Zweck reicht das.
	_flow = _StateRef.new_flow()
	_flow["phase"] = _StateRef.Phase.PLANNED
	_flow["action_id"] = _StateRef.safe_string(payload, "action_id")

	var trigger_label := _choose_trigger_label(payload)
	var action_label := _choose_action_label(payload)
	_set_node(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.PLANNED, trigger_label)
	_set_node(_ROLE_INDEX_ACTION, _StateRef.NodeState.PLANNED, action_label)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.PLANNED, "")
	_set_edges(false, false)

	_apply_flow_to_views()
	_apply_visibility()


func _on_action_started(_payload: Dictionary) -> void:
	# Trigger gilt als „passiert", Action ist jetzt aktiv, die Kante
	# zwischen beiden wird animiert.
	_flow["phase"] = _StateRef.Phase.ACTIVE
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.ACTIVE)
	_set_node_state(_ROLE_INDEX_RESULT, _StateRef.NodeState.PLANNED)
	_set_edges(true, false)

	_apply_flow_to_views()
	_apply_visibility()


func _on_action_step(payload: Dictionary) -> void:
	# Aktueller Step aktualisiert das Action-Node-Label. Fehlt ein
	# Titel, bleibt das bisherige Label stehen — kein leeres Flackern.
	var step_title := _StateRef.safe_string(payload, "title")
	if step_title != "":
		_set_node_label(_ROLE_INDEX_ACTION, step_title)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.ACTIVE)
	_set_edges(true, false)

	_apply_flow_to_views()


func _on_action_completed(payload: Dictionary) -> void:
	_flow["phase"] = _StateRef.Phase.COMPLETED
	var result_label := _choose_result_label(payload, "Done")
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.COMPLETED)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.COMPLETED, result_label)
	_set_edges(false, true)
	# Ein kurzer Puls auf der letzten Kante reicht; beide Kanten
	# werden durch den ruhenden Completed-Zustand neutralisiert.
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_failed(payload: Dictionary) -> void:
	_flow["phase"] = _StateRef.Phase.FAILED
	var result_label := _choose_result_label(payload, "Failed")
	# Der mittlere Knoten bleibt „active, aber fehlgeschlagen" —
	# visuell markieren wir ihn deshalb ebenfalls als FAILED.
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.FAILED)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.FAILED, result_label)
	_set_edges(false, false)
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_cancelled(payload: Dictionary) -> void:
	_flow["phase"] = _StateRef.Phase.UNKNOWN
	var reason := _StateRef.safe_string(payload, "message", "Cancelled")
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.UNKNOWN)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.UNKNOWN, reason)
	_set_edges(false, false)
	_apply_flow_to_views()
	_apply_visibility()


# --- State-Mutationen ----------------------------------------------------


func _reset_flow(reason: String) -> void:
	_flow = _StateRef.new_flow()
	_flow["last_reason"] = reason


func _set_node(index: int, state: int, label_text: String) -> void:
	var nodes: Array = _flow["nodes"]
	if index < 0 or index >= nodes.size():
		return
	var node_entry: Dictionary = nodes[index]
	node_entry["state"] = state
	node_entry["label"] = label_text
	nodes[index] = node_entry


func _set_node_state(index: int, state: int) -> void:
	var nodes: Array = _flow["nodes"]
	if index < 0 or index >= nodes.size():
		return
	var node_entry: Dictionary = nodes[index]
	node_entry["state"] = state
	nodes[index] = node_entry


func _set_node_label(index: int, label_text: String) -> void:
	var nodes: Array = _flow["nodes"]
	if index < 0 or index >= nodes.size():
		return
	var node_entry: Dictionary = nodes[index]
	node_entry["label"] = label_text
	nodes[index] = node_entry


func _set_edges(a_active: bool, b_active: bool) -> void:
	var edges: Array = _flow["edges"]
	if edges.size() >= 1:
		var entry_a: Dictionary = edges[0]
		entry_a["active"] = a_active
		edges[0] = entry_a
	if edges.size() >= 2:
		var entry_b: Dictionary = edges[1]
		entry_b["active"] = b_active
		edges[1] = entry_b


# --- Label-Auswahl (Fallback-sicher) -------------------------------------


func _choose_trigger_label(payload: Dictionary) -> String:
	# Mögliche Quellen, in Reihenfolge: `trigger`, `origin`, ansonsten
	# ein generisches „Trigger".
	var candidate := _StateRef.safe_string(payload, "trigger")
	if candidate == "":
		candidate = _StateRef.safe_string(payload, "origin")
	if candidate == "":
		candidate = _DEFAULT_ROLE_LABEL[_StateRef.NodeRole.TRIGGER]
	return candidate


func _choose_action_label(payload: Dictionary) -> String:
	var title := _StateRef.safe_string(payload, "title")
	if title == "":
		title = _StateRef.safe_string(payload, "action_kind")
	if title == "":
		title = _DEFAULT_ROLE_LABEL[_StateRef.NodeRole.ACTION]
	return title


func _choose_result_label(payload: Dictionary, fallback: String) -> String:
	var candidate := _StateRef.safe_string(payload, "message")
	if candidate == "":
		candidate = _StateRef.safe_string(payload, "status")
	if candidate == "":
		candidate = fallback
	return candidate


# --- Rendering / Visibility ---------------------------------------------


func _apply_flow_to_views() -> void:
	_apply_node_view(_trigger_view, _ROLE_INDEX_TRIGGER)
	_apply_node_view(_action_view, _ROLE_INDEX_ACTION)
	_apply_node_view(_result_view, _ROLE_INDEX_RESULT)

	var edges: Array = _flow["edges"]
	if _edge_a != null and edges.size() >= 1:
		_edge_a.apply(bool((edges[0] as Dictionary).get("active", false)))
	if _edge_b != null and edges.size() >= 2:
		_edge_b.apply(bool((edges[1] as Dictionary).get("active", false)))


func _apply_node_view(view: PanelContainer, index: int) -> void:
	if view == null:
		return
	var nodes: Array = _flow["nodes"]
	if index < 0 or index >= nodes.size():
		return
	var node_entry: Dictionary = nodes[index]
	var role := int(node_entry.get("role", _StateRef.NodeRole.TRIGGER))
	var state := int(node_entry.get("state", _StateRef.NodeState.IDLE))
	var label := str(node_entry.get("label", ""))
	if label == "":
		label = _DEFAULT_ROLE_LABEL.get(role, "")
	view.apply(role, state, label)


## Sichtbarkeit: Overlay bleibt versteckt, solange wir keinen Flow
## beobachten. Jeder Terminal-Zustand (`completed`, `failed`,
## `unknown`) hält den Flow sichtbar, bis der nächste `action_planned`
## ihn überschreibt oder der Nutzer die Verbindung verliert.
func _apply_visibility() -> void:
	var phase := int(_flow.get("phase", _StateRef.Phase.HIDDEN))
	visible = (phase != _StateRef.Phase.HIDDEN)
