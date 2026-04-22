extends RefCounted
## Workflow-Overlay — lokales UI-Projektions-Modell
##
## Kleine Datenstruktur, die der `workflow_overlay_controller` aus den
## bestehenden Action Events ableitet. Der State ist **reiner Renderer-
## State**: keine Wahrheit, keine Persistenz, keine Eingabe-Schnittstelle
## zum Core. Er wird beim Start einer neuen Action frisch aufgebaut und
## bei Disconnect sauber zurückgesetzt.
##
## Entwurfsprinzipien:
##   * Keine Graph-DSL, keine Knotenkennungen aus dem Core, keine
##     Pflichtfelder am Event. Unbekannte / fehlende Felder werden
##     still durch neutrale Defaults ersetzt.
##   * Genau drei feste UI-Knoten: Trigger → Action → Result. Das ist
##     bewusst keine allgemeine Graph-Struktur — das MVP zeigt eine
##     Kurzprojektion, keinen vollständigen Flow.
##   * Phase und Knotenzustände werden heuristisch aus `action_*`-
##     Events abgeleitet (`planned` → planned, `started` → active, …).
##     Der Controller kommentiert die Heuristik an den jeweiligen
##     Einsprungstellen.

class_name SmolitWorkflowOverlayState

## Gesamtphase eines Flows. `HIDDEN` = kein Flow aktiv, Overlay wird
## nicht gezeigt. Alle anderen Zustände bedeuten: wir haben kürzlich
## mindestens ein `action_*`-Event beobachtet.
enum Phase {
	HIDDEN,
	PLANNED,
	ACTIVE,
	COMPLETED,
	FAILED,
	UNKNOWN,
}


## Zustand eines einzelnen UI-Knotens. Bewusst das gleiche Vokabular
## wie `Phase`, damit Render-Code einheitlich bleibt — kein Mapping
## zwischen zwei Begriffswelten.
enum NodeState {
	IDLE,     # noch nicht erreicht / zurückgesetzt
	PLANNED,  # wird erwartet / ausgegraut
	ACTIVE,   # aktuell im Fokus
	COMPLETED,
	FAILED,
	UNKNOWN,
}


## Rolle des Knotens im Kurz-Flow. Drei feste Rollen genügen für MVP.
enum NodeRole {
	TRIGGER,
	ACTION,
	RESULT,
}


static func phase_name(phase: int) -> String:
	match phase:
		Phase.HIDDEN: return "hidden"
		Phase.PLANNED: return "planned"
		Phase.ACTIVE: return "active"
		Phase.COMPLETED: return "completed"
		Phase.FAILED: return "failed"
		Phase.UNKNOWN: return "unknown"
		_: return "unknown"


static func node_state_name(state: int) -> String:
	match state:
		NodeState.IDLE: return "idle"
		NodeState.PLANNED: return "planned"
		NodeState.ACTIVE: return "active"
		NodeState.COMPLETED: return "completed"
		NodeState.FAILED: return "failed"
		NodeState.UNKNOWN: return "unknown"
		_: return "unknown"


static func role_name(role: int) -> String:
	match role:
		NodeRole.TRIGGER: return "trigger"
		NodeRole.ACTION: return "action"
		NodeRole.RESULT: return "result"
		_: return "unknown"


## Neues Skeleton für einen Flow. Drei Knoten in fester Reihenfolge,
## zwei Kanten. Labels sind zunächst leer; der Controller füllt sie
## aus den bekannten Event-Feldern. Fehlende Felder bleiben leer.
static func new_flow() -> Dictionary:
	return {
		"phase": Phase.HIDDEN,
		"action_id": "",
		"nodes": [
			{"role": NodeRole.TRIGGER, "state": NodeState.IDLE, "label": ""},
			{"role": NodeRole.ACTION, "state": NodeState.IDLE, "label": ""},
			{"role": NodeRole.RESULT, "state": NodeState.IDLE, "label": ""},
		],
		"edges": [
			{"from": 0, "to": 1, "active": false},
			{"from": 1, "to": 2, "active": false},
		],
		"last_reason": "",
	}


## Einfache Feld-Extraktion mit Fallback. Action-Events können je
## nach Quelle unterschiedlich vollständig sein; wir ziehen nur die
## Felder, die das MVP braucht.
static func safe_string(d: Dictionary, key: String, fallback: String = "") -> String:
	if not d.has(key):
		return fallback
	var value: Variant = d[key]
	if typeof(value) != TYPE_STRING:
		return fallback
	return str(value).strip_edges()
