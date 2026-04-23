extends RefCounted
## Workflow Visibility Overlay v1 (PR 16) — pure Modell.
##
## Das Modell projiziert bestehende UI-Events in eine **kleine lineare
## Kette** sichtbarer Workflow-Schritte (heard → thinking → response →
## action → step → speaking → completed/failed). Es ist reiner
## Renderer-State; es sendet nichts, hält keine Historie über die
## aktuelle Interaktion hinaus und kennt keine neuen IPC-Events.
##
## Abgrenzungen:
##
##   * **Keine zweite Wahrheit.** Das Modell dupliziert weder den
##     Avatar-State noch die Action-Event-Timeline. Es ist eine
##     zusammenfassende Kurzanzeige.
##   * **Kein Editor.** Keine Drag/Drop-Knoten, keine Graph-DSL, kein
##     Action-Trigger — PR 16 ist ausdrücklich kein n8n-Ersatz.
##   * **Keine langen Texte.** Snippets werden hart auf
##     `MAX_SNIPPET_CHARS = 60` gekürzt; vertrauliche Inhalte dürfen
##     nicht im Overlay landen.
##   * **Kein Core-/Protokoll-Hook.** Der gesamte Layer konsumiert
##     ausschließlich die bereits existierenden EventBus-Signale
##     (`heard_received`, `thinking_received`, `response_received`,
##     `action_*_received`, `speaking_*_received`, `ipc_disconnected`).
##   * **Kein neuer Speicherort.** Ein `reset()` startet einen frischen
##     Workflow; Terminalzustände (`completed` / `failed`) werden beim
##     nächsten relevanten Event wieder durch einen neuen Workflow
##     überschrieben.

class_name SmolitWorkflowVisibilityModel


## Kuratierte Auswahl an Schritt-Kategorien, abgeleitet aus den
## bestehenden Events. `COMPLETED` / `FAILED` sind Terminalzustände
## des Workflows, nicht zusätzliche Aktionen.
enum StepKind {
	HEARD,
	THINKING,
	RESPONSE,
	ACTION,
	STEP,
	SPEAKING,
	APPROVAL,
	COMPLETED,
	FAILED,
}

const DEFAULT_KIND: int = StepKind.HEARD


## Status eines einzelnen Schritts. `SKIPPED` markiert Schritte, die
## durch einen Disconnect oder einen Terminal-Event unsauber
## übersprungen wurden — so bleibt die Kette ehrlich lesbar.
enum Status {
	PENDING,
	ACTIVE,
	DONE,
	FAILED,
	SKIPPED,
}


## Hartes Snippet-Limit. Bewusst klein — das Overlay ist keine
## Transcript-Wand. Längere Texte werden mit Ellipsis abgeschnitten.
const MAX_SNIPPET_CHARS: int = 60
const ELLIPSIS: String = "…"


const _KIND_NAMES: Dictionary = {
	StepKind.HEARD: "heard",
	StepKind.THINKING: "thinking",
	StepKind.RESPONSE: "response",
	StepKind.ACTION: "action",
	StepKind.STEP: "step",
	StepKind.SPEAKING: "speaking",
	StepKind.APPROVAL: "approval",
	StepKind.COMPLETED: "completed",
	StepKind.FAILED: "failed",
}

const _STATUS_NAMES: Dictionary = {
	Status.PENDING: "pending",
	Status.ACTIVE: "active",
	Status.DONE: "done",
	Status.FAILED: "failed",
	Status.SKIPPED: "skipped",
}

const _KIND_LABELS: Dictionary = {
	StepKind.HEARD: "Heard",
	StepKind.THINKING: "Thinking",
	StepKind.RESPONSE: "Response",
	StepKind.ACTION: "Action",
	StepKind.STEP: "Step",
	StepKind.SPEAKING: "Speaking",
	StepKind.APPROVAL: "Approval",
	StepKind.COMPLETED: "Done",
	StepKind.FAILED: "Failed",
}


# --- Enum helpers -------------------------------------------------------


static func kind_name(kind: int) -> String:
	if _KIND_NAMES.has(kind):
		return String(_KIND_NAMES[kind])
	return String(_KIND_NAMES[DEFAULT_KIND])


static func status_name(status: int) -> String:
	if _STATUS_NAMES.has(status):
		return String(_STATUS_NAMES[status])
	return "pending"


static func kind_label(kind: int) -> String:
	if _KIND_LABELS.has(kind):
		return String(_KIND_LABELS[kind])
	return "Step"


static func is_known_kind(kind: int) -> bool:
	return _KIND_NAMES.has(kind)


static func is_known_status(status: int) -> bool:
	return _STATUS_NAMES.has(status)


static func is_terminal_kind(kind: int) -> bool:
	return kind == StepKind.COMPLETED or kind == StepKind.FAILED


## Alle Kategorien in stabiler Reihenfolge (Smoke-Kontrakt + optionaler
## Dev-Inspektor).
static func all_kinds() -> Array:
	var out: Array = []
	for k in _KIND_NAMES:
		out.append(int(k))
	out.sort()
	return out


## Kürzt rohen User-/Response-Text auf die sichtbare Länge. Whitespace
## außen wird gestrippt; längere Texte werden mit Ellipsis
## abgeschnitten. Die Snippet-Länge ist bewusst klein — dieses Panel
## zeigt den Kontext, nicht den Inhalt.
static func trim_snippet(raw: String) -> String:
	var trimmed: String = raw.strip_edges()
	if trimmed.length() <= MAX_SNIPPET_CHARS:
		return trimmed
	return trimmed.substr(0, MAX_SNIPPET_CHARS - ELLIPSIS.length()) + ELLIPSIS


# --- Instance state ------------------------------------------------------


var _steps: Array = []
var _terminal: bool = false
var _offline: bool = false
var _step_count: int = 0
var _action_id: String = ""


func _init() -> void:
	_reset()


## Setzt das Modell zurück. Nur für Tests und den Disconnect-Pfad —
## normale Event-Handler rufen intern bei Bedarf auf.
func reset() -> void:
	_reset()


## Schmaler Lese-Hook für Panel + Smoke. Liefert eine tiefe Kopie, um
## versehentliche Mutationen durch den Renderer auszuschließen.
func snapshot() -> Dictionary:
	var steps_copy: Array = []
	for step in _steps:
		steps_copy.append((step as Dictionary).duplicate(true))
	return {
		"steps": steps_copy,
		"terminal": _terminal,
		"offline": _offline,
		"step_count": _step_count,
		"action_id": _action_id,
	}


func step_count() -> int:
	return _step_count


func is_terminal() -> bool:
	return _terminal


func is_offline() -> bool:
	return _offline


func is_empty() -> bool:
	return _steps.is_empty()


# --- Event application ---------------------------------------------------


func apply_heard(text: String, timestamp_ms: int = 0) -> void:
	_start_new_workflow_if_terminal()
	_offline = false
	_upsert(StepKind.HEARD, Status.DONE, trim_snippet(text), "", timestamp_ms)


func apply_thinking(timestamp_ms: int = 0) -> void:
	_start_new_workflow_if_terminal()
	_offline = false
	# Thinking ersetzt den aktiven State des Upstreams (heard done
	# bleibt, thinking wird active). Nachgelagerte Schritte werden
	# nicht vorausgeplant — zu viel Vorwegnahme würde PR-Scope sprengen.
	_upsert(StepKind.THINKING, Status.ACTIVE, "", "", timestamp_ms)


func apply_response(text: String, timestamp_ms: int = 0) -> void:
	_start_new_workflow_if_terminal()
	_offline = false
	_mark_done(StepKind.THINKING)
	_upsert(StepKind.RESPONSE, Status.DONE, trim_snippet(text), "", timestamp_ms)


func apply_action_planned(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	var action_id: String = _str_field(payload, "action_id")
	if _action_id != "" and action_id != "" and action_id != _action_id:
		# Neue Action — frischer Workflow.
		_reset()
	if _terminal:
		_reset()
	_action_id = action_id
	var title: String = _str_field(payload, "title")
	_upsert(StepKind.ACTION, Status.ACTIVE, trim_snippet(title), action_id, timestamp_ms)


func apply_action_step(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	_start_new_workflow_if_terminal()
	var label: String = _str_field(payload, "label")
	if label.is_empty():
		label = _str_field(payload, "step")
	_step_count += 1
	var snippet: String = trim_snippet(label)
	if snippet.is_empty():
		snippet = "#%d" % _step_count
	_upsert(StepKind.STEP, Status.ACTIVE, snippet, _str_field(payload, "action_id"), timestamp_ms)


func apply_action_completed(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	_mark_done(StepKind.ACTION)
	_mark_done(StepKind.STEP)
	_mark_done(StepKind.SPEAKING)
	_upsert(StepKind.COMPLETED, Status.DONE, "", _str_field(payload, "action_id"), timestamp_ms)
	_terminal = true


func apply_action_failed(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	_mark_active_as(Status.FAILED)
	var message: String = _str_field(payload, "message")
	_upsert(StepKind.FAILED, Status.FAILED, trim_snippet(message), _str_field(payload, "action_id"), timestamp_ms)
	_terminal = true


func apply_action_cancelled(payload: Dictionary, timestamp_ms: int = 0) -> void:
	# Behandeln wir wie ein stilles Failed — der Avatar-Controller macht
	# es genauso (Kurzer roter Startle ist dort reserviert, hier ist es
	# ein ehrlicher `FAILED`-Terminal).
	apply_action_failed(payload, timestamp_ms)


func apply_speaking_started(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	_start_new_workflow_if_terminal()
	_upsert(StepKind.SPEAKING, Status.ACTIVE, "", _str_field(payload, "action_id"), timestamp_ms)


func apply_speaking_ended(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	var ok: bool = bool(payload.get("ok", true))
	var status: int = Status.DONE if ok else Status.FAILED
	var snippet: String = ""
	if not ok:
		snippet = trim_snippet(_str_field(payload, "error_class"))
	_upsert(StepKind.SPEAKING, status, snippet, _str_field(payload, "action_id"), timestamp_ms)


## PR 17 — Approval UX v1. Ein eingehendes `approval_requested` wird
## als eigene APPROVAL-Karte gerendert; Risk und Titel landen im
## Snippet, damit die Workflow-Kurzanzeige neben der Approval-Card
## einen ehrlichen Kontext hat. Der Schritt ist aktiv, bis das
## `approval_resolved`-Envelope eintrifft.
func apply_approval_requested(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	_start_new_workflow_if_terminal()
	var title: String = _str_field(payload, "title")
	if title.is_empty():
		title = _str_field(payload, "message")
	var risk: String = _str_field(payload, "risk")
	if risk.is_empty():
		risk = "medium"
	var summary: String = trim_snippet("[%s] %s" % [risk, title])
	_upsert(
		StepKind.APPROVAL,
		Status.ACTIVE,
		summary,
		_str_field(payload, "approval_id"),
		timestamp_ms,
	)


## PR 17 — Zusammen mit [method apply_approval_requested] bildet
## diese Funktion das APPROVAL-Kapitel auf die bestehenden Status-
## Stufen ab:
##
##   * `approved` → DONE
##   * `denied` / `cancelled` → FAILED
##   * `timed_out` / `expired` → SKIPPED
##   * unbekannt → SKIPPED (defensiv, kein DONE-Leak)
##
## Der Schritt bleibt in der Kette sichtbar; ein neues Approval
## überschreibt ihn später upsert-basiert.
func apply_approval_resolved(payload: Dictionary, timestamp_ms: int = 0) -> void:
	_offline = false
	var decision: String = _str_field(payload, "decision")
	var status: int = Status.SKIPPED
	match decision:
		"approved":
			status = Status.DONE
		"denied", "cancelled":
			status = Status.FAILED
		"timed_out", "expired":
			status = Status.SKIPPED
		_:
			status = Status.SKIPPED
	var source: String = _str_field(payload, "source")
	var snippet: String
	if source.is_empty():
		snippet = trim_snippet(decision)
	else:
		snippet = trim_snippet("%s (%s)" % [decision, source])
	_upsert(
		StepKind.APPROVAL,
		status,
		snippet,
		_str_field(payload, "approval_id"),
		timestamp_ms,
	)


func apply_disconnected() -> void:
	# Verbindung weg → der aktuelle Workflow ist nicht mehr
	# vertrauenswürdig. Aktive Schritte werden auf `SKIPPED` gesetzt
	# (ehrlicher Abschluss), das Modell flaggt `offline=true`, der
	# Workflow gilt nicht als terminal (damit ein Reconnect sofort
	# wieder ein frisches heard/thinking rendern kann).
	_mark_active_as(Status.SKIPPED)
	_offline = true


# --- Internals -----------------------------------------------------------


func _reset() -> void:
	_steps = []
	_terminal = false
	_offline = false
	_step_count = 0
	_action_id = ""


func _start_new_workflow_if_terminal() -> void:
	if _terminal:
		_reset()


func _upsert(kind: int, status: int, snippet: String, action_id: String, timestamp_ms: int) -> void:
	if not is_known_kind(kind):
		return
	if not is_known_status(status):
		status = Status.PENDING
	var idx: int = _find_index(kind)
	if idx == -1:
		_steps.append({
			"kind": kind,
			"label": kind_label(kind),
			"status": status,
			"snippet": snippet,
			"action_id": action_id,
			"timestamp_ms": timestamp_ms,
		})
	else:
		var existing: Dictionary = _steps[idx]
		existing["status"] = status
		# Snippet nur überschreiben, wenn der Aufrufer etwas
		# sinnvolles mitschickt — so bleiben einmal gerenderte
		# Kontexte stabil, selbst wenn später ein leeres Event
		# ankommt.
		if not snippet.is_empty():
			existing["snippet"] = snippet
		if not action_id.is_empty():
			existing["action_id"] = action_id
		if timestamp_ms > 0:
			existing["timestamp_ms"] = timestamp_ms
		_steps[idx] = existing


func _find_index(kind: int) -> int:
	for i in range(_steps.size()):
		if int((_steps[i] as Dictionary).get("kind", -1)) == kind:
			return i
	return -1


func _mark_done(kind: int) -> void:
	var idx: int = _find_index(kind)
	if idx == -1:
		return
	var step: Dictionary = _steps[idx]
	# ACTIVE / PENDING werden zu DONE befördert; FAILED bleibt als
	# ehrlicher Endzustand bestehen.
	var current: int = int(step.get("status", Status.PENDING))
	if current == Status.ACTIVE or current == Status.PENDING:
		step["status"] = Status.DONE
		_steps[idx] = step


func _mark_active_as(status: int) -> void:
	for i in range(_steps.size()):
		var step: Dictionary = _steps[i]
		if int(step.get("status", Status.PENDING)) == Status.ACTIVE:
			step["status"] = status
			_steps[i] = step


func _str_field(payload: Dictionary, key: String) -> String:
	var value: Variant = payload.get(key, "")
	if value == null:
		return ""
	return str(value)
