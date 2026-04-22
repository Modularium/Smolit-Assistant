extends Control
## Workflow-Overlay — read-only UI-Projektion der Core-Action-Events
##
## MVP-Spike der in `docs/ui_architecture.md` §6a/§8a beschriebenen
## Workflow-Overlay-Linie. Der Controller konsumiert die bestehenden
## Action Events aus dem EventBus und projiziert daraus einen kleinen
## symbolischen Kurz-Flow mit drei Knoten: Trigger → Action → Result.
##
## PR 2 schärft die Projektion in vier Punkten nach:
##   * **Collapse / Expand** — zweistufiger Darstellungsmodus
##     (`COLLAPSED` / `EXPANDED`), abgeleitet aus der aktuellen Phase
##     (siehe `workflow_overlay_state.gd::display_mode_for_phase`).
##     Kein Nutzerschalter, keine zweite Presence-State-Maschine.
##   * **Bessere Label-Auflösung** — alle Label-Defaults leben jetzt
##     als pure static Helper im State-Modul und haben klare
##     Fallback-Ketten. Der Controller ruft sie nur auf.
##   * **Robuste Event-Rekonstruktion** — mehrere `action_step`-
##     Events werden gezählt (informativer `step_count`) und
##     aktualisieren das Label nur bei belastbaren Payloads; leere
##     Felder überschreiben kein bestehendes Label mehr. Ein
##     `action_step`, der vor `action_planned`/`action_started`
##     eintrifft, promotet den Flow still auf `ACTIVE`.
##   * **Ruhigerer visueller Rhythmus** — Node/Edge-Views reagieren
##     auf den Darstellungsmodus mit größeren Mindestgrößen und
##     etwas lesbareren Schriftgrößen im EXPANDED-Zustand.
##
## Bindende Grenzen (unverändert):
##   * **Read-only / core-driven.** Der Controller sendet *keine*
##     neuen IPC-Nachrichten.
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
## Sichtbarkeit: Overlay bleibt standardmäßig unsichtbar. Er zeigt
## sich beim ersten `action_planned` (oder bei einem frühen
## `action_step`/`action_started`, falls kein `action_planned`
## vorausging) und versteckt sich bei `ipc_disconnected`. Nach
## terminalen Events bleibt der Flow kurz sichtbar, bis der nächste
## `action_planned` ihn überschreibt.

const _StateRef := preload("res://scripts/workflow_overlay/workflow_overlay_state.gd")
const _NodeViewRef := preload("res://scripts/workflow_overlay/workflow_node_view.gd")
const _EdgeViewRef := preload("res://scripts/workflow_overlay/workflow_edge_view.gd")

## Kurze Default-Beschriftungen pro Rolle, falls der Controller keinen
## Titel auflösen kann. Die Rollen selbst stehen immer im kleinen
## Role-Label über dem Titel (UPPERCASE) — das hier sind bewusste
## Fallback-Titel, damit ein unbeschrifteter Knoten nicht wie „kaputt"
## aussieht.
const _DEFAULT_ROLE_LABEL: Dictionary = {
	_StateRef.NodeRole.TRIGGER: "Start",
	_StateRef.NodeRole.ACTION: "Working…",
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
	if not _has_autoload("EventBus"):
		push_warning("workflow_overlay: EventBus autoload not available; overlay stays hidden.")
		return
	EventBus.ipc_disconnected.connect(_on_ipc_disconnected)
	EventBus.action_planned_received.connect(_on_action_planned)
	EventBus.action_started_received.connect(_on_action_started)
	EventBus.action_step_received.connect(_on_action_step)
	EventBus.action_completed_received.connect(_on_action_completed)
	EventBus.action_failed_received.connect(_on_action_failed)
	# `action_cancelled` wird als „unknown-Abschluss" behandelt, damit
	# ein Abbruch optisch einen klaren Endzustand bekommt.
	EventBus.action_cancelled_received.connect(_on_action_cancelled)


static func _has_autoload(autoload_name: String) -> bool:
	var root := Engine.get_main_loop()
	if root is SceneTree:
		var tree := root as SceneTree
		return tree.root.has_node("/root/" + autoload_name)
	return false


# --- Event handlers ------------------------------------------------------


func _on_ipc_disconnected() -> void:
	# Verbindung weg → kein bekannter Flow mehr. Neutralisieren.
	_reset_flow("ipc disconnected")
	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_planned(payload: Dictionary) -> void:
	# Neuer Flow beginnt. Ein neuer `action_planned` überschreibt
	# immer — für unseren Kurzprojektionszweck reicht das. action_id
	# wird informativ gespeichert, aber kein Queue-/History-System
	# aufgebaut (bewusst außerhalb MVP-Scope).
	_flow = _StateRef.new_flow()
	_flow["phase"] = _StateRef.Phase.PLANNED
	_flow["action_id"] = _StateRef.safe_string(payload, "action_id")

	var trigger_label := _StateRef.trigger_label_from_payload(payload)
	var action_label := _StateRef.action_label_from_payload(payload)
	_set_node(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.PLANNED, trigger_label)
	_set_node(_ROLE_INDEX_ACTION, _StateRef.NodeState.PLANNED, action_label)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.PLANNED, "")
	_set_edges(false, false)

	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_started(payload: Dictionary) -> void:
	# Trigger gilt als „passiert", Action ist jetzt aktiv, die Kante
	# zwischen beiden wird animiert. Wenn kein vorheriges
	# `action_planned` gesehen wurde (z. B. spätes Verbinden), bauen
	# wir einen minimalen Flow auf — die Rekonstruktion bleibt
	# stabil.
	if int(_flow.get("phase", _StateRef.Phase.HIDDEN)) == _StateRef.Phase.HIDDEN:
		_flow = _StateRef.new_flow()
		_flow["action_id"] = _StateRef.safe_string(payload, "action_id")
		_set_node(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.PLANNED,
			_StateRef.trigger_label_from_payload(payload))
		_set_node(_ROLE_INDEX_ACTION, _StateRef.NodeState.PLANNED,
			_StateRef.action_label_from_payload(payload))
		_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.PLANNED, "")

	_flow["phase"] = _StateRef.Phase.ACTIVE
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.ACTIVE)
	_set_node_state(_ROLE_INDEX_RESULT, _StateRef.NodeState.PLANNED)
	_set_edges(true, false)

	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_step(payload: Dictionary) -> void:
	# Step-Zähler hochzählen — dient nur als optionaler Hint im
	# EXPANDED-Modus („Step 3"), kein History-Log.
	_flow["step_count"] = int(_flow.get("step_count", 0)) + 1

	# Label nur dann überschreiben, wenn das Event belastbaren Text
	# liefert. Ein leeres Event-Payload behält das bisherige Label —
	# kein Flackern, kein „Working…" nach sinnvollem Titel.
	var step_label := _StateRef.step_label_from_payload(payload)
	if step_label != "":
		_set_node_label(_ROLE_INDEX_ACTION, step_label)

	# Ein `action_step` vor `action_started` sollte die UI nicht still
	# lassen — Phase auf ACTIVE promoten, Trigger als bereits „passiert"
	# markieren. Existierende Terminal-Zustände werden nicht
	# zurückgedreht; sie markieren das Ende eines vorherigen Flows.
	var phase := int(_flow.get("phase", _StateRef.Phase.HIDDEN))
	match phase:
		_StateRef.Phase.HIDDEN, _StateRef.Phase.PLANNED:
			_flow["phase"] = _StateRef.Phase.ACTIVE
			_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
			_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.ACTIVE)
			_set_node_state(_ROLE_INDEX_RESULT, _StateRef.NodeState.PLANNED)
		_:
			# Im laufenden Flow halten wir Action aktiv.
			_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.ACTIVE)
	_set_edges(true, false)

	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_completed(payload: Dictionary) -> void:
	_flow["phase"] = _StateRef.Phase.COMPLETED
	var result_label := _StateRef.result_label_from_payload(payload, "Done")
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.COMPLETED)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.COMPLETED, result_label)
	# Beide Kanten ruhen — die Ergebnis-Färbung reicht als Signal.
	_set_edges(false, true)
	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_failed(payload: Dictionary) -> void:
	_flow["phase"] = _StateRef.Phase.FAILED
	var result_label := _StateRef.result_label_from_payload(payload, "Failed")
	# Der mittlere Knoten bleibt „active, aber fehlgeschlagen" —
	# visuell markieren wir ihn deshalb ebenfalls als FAILED.
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.FAILED)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.FAILED, result_label)
	_set_edges(false, false)
	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


func _on_action_cancelled(payload: Dictionary) -> void:
	_flow["phase"] = _StateRef.Phase.UNKNOWN
	var reason := _StateRef.cancel_label_from_payload(payload)
	_set_node_state(_ROLE_INDEX_TRIGGER, _StateRef.NodeState.COMPLETED)
	_set_node_state(_ROLE_INDEX_ACTION, _StateRef.NodeState.UNKNOWN)
	_set_node(_ROLE_INDEX_RESULT, _StateRef.NodeState.UNKNOWN, reason)
	_set_edges(false, false)
	_refresh_display_mode()
	_apply_flow_to_views()
	_apply_visibility()


# --- State-Mutationen ----------------------------------------------------


func _reset_flow(reason: String) -> void:
	_flow = _StateRef.new_flow()
	_flow["last_reason"] = reason


func _refresh_display_mode() -> void:
	_flow["display_mode"] = _StateRef.display_mode_for_phase(
		int(_flow.get("phase", _StateRef.Phase.HIDDEN))
	)


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
	# Leere Strings überschreiben kein bestehendes Label — dafür sind
	# die Label-Auflöser im State-Modul verantwortlich. Wer hier
	# expliziten Reset will, nutzt `_set_node(index, state, "")`.
	if label_text == "":
		return
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


# --- Rendering / Visibility ---------------------------------------------


func _apply_flow_to_views() -> void:
	var mode := int(_flow.get("display_mode", _StateRef.DisplayMode.COLLAPSED))

	_apply_node_view(_trigger_view, _ROLE_INDEX_TRIGGER, mode)
	_apply_node_view(_action_view, _ROLE_INDEX_ACTION, mode)
	_apply_node_view(_result_view, _ROLE_INDEX_RESULT, mode)

	var edges: Array = _flow["edges"]
	if _edge_a != null and edges.size() >= 1:
		_edge_a.apply(bool((edges[0] as Dictionary).get("active", false)), mode)
	if _edge_b != null and edges.size() >= 2:
		_edge_b.apply(bool((edges[1] as Dictionary).get("active", false)), mode)

	# Kleine Feinheit: im EXPANDED-Modus die Zeilen-Trennung leicht
	# aufweiten, damit die Nodes nicht visuell aneinanderkleben.
	if _row != null:
		var separation := 8 if mode == _StateRef.DisplayMode.EXPANDED else 5
		_row.add_theme_constant_override("separation", separation)


func _apply_node_view(view: PanelContainer, index: int, mode: int) -> void:
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
		# Gute Defaults je Rolle, damit ein unbeschrifteter Knoten nicht
		# „kaputt" aussieht. Die Role-Zeile steht immer in UPPERCASE,
		# der Title-Fallback ist eine menschenlesbare Kurzform.
		label = _DEFAULT_ROLE_LABEL.get(role, "")

	# Hint-Text nur für den Action-Knoten im laufenden/fortschreitenden
	# Flow, und nur wenn wir mehrere `action_step`-Events gezählt haben.
	var hint := ""
	if role == _StateRef.NodeRole.ACTION:
		hint = _StateRef.step_hint_from_count(int(_flow.get("step_count", 0)))

	view.apply(role, state, label, mode, hint)


## Sichtbarkeit: Overlay bleibt versteckt, solange wir keinen Flow
## beobachten. Jeder Terminal-Zustand (`completed`, `failed`,
## `unknown`) hält den Flow sichtbar, bis der nächste `action_planned`
## ihn überschreibt oder der Nutzer die Verbindung verliert.
func _apply_visibility() -> void:
	var phase := int(_flow.get("phase", _StateRef.Phase.HIDDEN))
	visible = (phase != _StateRef.Phase.HIDDEN)
