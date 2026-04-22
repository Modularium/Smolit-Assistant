extends RefCounted
## Workflow-Overlay — lokales UI-Projektions-Modell
##
## Kleine Datenstruktur + pure Helper, die der
## `workflow_overlay_controller` aus den bestehenden Action Events
## ableitet. Der State ist **reiner Renderer-State**: keine Wahrheit,
## keine Persistenz, keine Eingabe-Schnittstelle zum Core. Er wird
## beim Start einer neuen Action frisch aufgebaut und bei Disconnect
## sauber zurückgesetzt.
##
## PR 2 schärft dieses Modul in drei Punkten nach:
##   * `DisplayMode` (COLLAPSED / EXPANDED) als bewusst kleine
##     Zwei-Stufen-Semantik. Der Controller leitet den Modus aus der
##     Phase ab; es gibt keine neue globale Presence-State-Maschine
##     und keinen Nutzerschalter.
##   * Label-Auflösung als pure static Helper in diesem Modul, damit
##     sie unabhängig vom Scene-Tree testbar ist (siehe
##     `scripts/workflow_overlay_smoke.gd`) und der Controller
##     einheitliche Defaults erhält.
##   * `step_count` auf Flow-Ebene — informativer Zähler laufender
##     `action_step`-Events für den Action-Knoten, *kein* History-
##     System. Wird bei neuem Flow zurückgesetzt.
##
## Entwurfsprinzipien bleiben:
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


## Darstellungsmodus. Bewusst nur zwei Stufen; kein freier
## Detaillevel-Slider. Der Modus moduliert Größe, Typo und Abstände
## der Renderer-Views — er ändert weder Node-Zahl noch Semantik.
##   * `COLLAPSED`: ruhige, sehr kompakte Kurzprojektion
##     (z. B. Phase.PLANNED oder ausklingende Endzustände).
##   * `EXPANDED`:  etwas mehr Höhe, lesbarer — wird bevorzugt, wenn
##     der Nutzer aktiv hinschaut (Phase.ACTIVE, Terminal-Zustände
##     mit Result-Text).
enum DisplayMode {
	COLLAPSED,
	EXPANDED,
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


static func display_mode_name(mode: int) -> String:
	match mode:
		DisplayMode.COLLAPSED: return "collapsed"
		DisplayMode.EXPANDED: return "expanded"
		_: return "collapsed"


## Ableitung des Darstellungsmodus aus der aktuellen Phase. Bewusst
## klein: `ACTIVE` und alle Terminal-Phasen verdienen mehr
## Lesbarkeit, `PLANNED` bleibt bewusst ruhig-kompakt. `HIDDEN` ist
## sicherheitshalber `COLLAPSED`, obwohl der Overlay in diesem Fall
## ohnehin nicht sichtbar ist.
static func display_mode_for_phase(phase: int) -> int:
	match phase:
		Phase.ACTIVE, Phase.COMPLETED, Phase.FAILED, Phase.UNKNOWN:
			return DisplayMode.EXPANDED
		_:
			return DisplayMode.COLLAPSED


## Neues Skeleton für einen Flow. Drei Knoten in fester Reihenfolge,
## zwei Kanten. Labels sind zunächst leer; der Controller füllt sie
## aus den bekannten Event-Feldern. Fehlende Felder bleiben leer.
static func new_flow() -> Dictionary:
	return {
		"phase": Phase.HIDDEN,
		"display_mode": DisplayMode.COLLAPSED,
		"action_id": "",
		"step_count": 0,
		"nodes": [
			{"role": NodeRole.TRIGGER, "state": NodeState.IDLE, "label": ""},
			{"role": NodeRole.ACTION,  "state": NodeState.IDLE, "label": "", "hint": ""},
			{"role": NodeRole.RESULT,  "state": NodeState.IDLE, "label": ""},
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


# --- Label-Auflösung -----------------------------------------------------
# Pure static Helper. Jede Funktion liefert garantiert einen sauberen,
# nicht-leeren String. Mehrstufige Fallback-Ketten bevorzugen die
# spezifischsten Felder zuerst und fallen auf kurze, neutrale Defaults
# zurück. So bleibt die UI auch bei sehr dünnen Payloads lesbar.


## Trigger-Label aus `action_planned`-Payload. Bevorzugte Felder:
## `trigger` (wenn der Core ausdrücklich einen Trigger benennt),
## `origin` (z. B. `voice`, `text`, `cli`), sonst eine kurze,
## human-lesbare Kategorie aus `action_kind` (`speech` → "Voice",
## `query` → "User text"), sonst der generische Default "Start".
static func trigger_label_from_payload(payload: Dictionary) -> String:
	var explicit := safe_string(payload, "trigger")
	if explicit != "":
		return explicit
	var origin := safe_string(payload, "origin")
	if origin != "":
		return origin.capitalize()
	var kind := safe_string(payload, "action_kind")
	match kind.to_lower():
		"speech":
			return "Voice"
		"query":
			return "User text"
		"automation":
			return "Automation"
		"system":
			return "System"
		"":
			pass
		_:
			return kind.capitalize()
	return "Start"


## Action-Label aus einem `action_planned`- oder `action_started`-
## Payload. Bevorzugt `title` (menschlich formuliert), sonst
## `description`, sonst `action_kind` groß geschrieben, sonst
## "Working…".
static func action_label_from_payload(payload: Dictionary) -> String:
	var title := safe_string(payload, "title")
	if title != "":
		return title
	var description := safe_string(payload, "description")
	if description != "":
		return description
	var kind := safe_string(payload, "action_kind")
	if kind != "":
		return kind.capitalize()
	return "Working…"


## Step-Label aus `action_step`-Payload. Gibt leeren String zurück,
## wenn nichts Aussagekräftiges da ist — der Controller behält in
## dem Fall das bisherige Action-Label, damit nicht plötzlich ein
## schwächerer Text erscheint. Kein Default.
static func step_label_from_payload(payload: Dictionary) -> String:
	var title := safe_string(payload, "title")
	if title != "":
		return title
	var description := safe_string(payload, "description")
	if description != "":
		return description
	return ""


## Result-Label aus `action_completed` / `action_failed`. `fallback`
## ist ein kurzer, neutraler Text für den Terminal-Zustand
## ("Done" / "Failed"). Bevorzugte Felder: `message` (spezifisch),
## sonst `status` (z. B. "completed"), sonst der Fallback.
static func result_label_from_payload(payload: Dictionary, fallback: String) -> String:
	var message := safe_string(payload, "message")
	if message != "":
		return message
	var status := safe_string(payload, "status")
	if status != "":
		return status.capitalize()
	return fallback


## Cancel-Label aus `action_cancelled`. Bevorzugt `message`, sonst
## "Cancelled".
static func cancel_label_from_payload(payload: Dictionary) -> String:
	var message := safe_string(payload, "message")
	if message != "":
		return message
	return "Cancelled"


## Optionaler kleiner Hinweis-Text für den Action-Knoten im
## EXPANDED-Modus: zeigt an, wieviele `action_step`-Events wir im
## laufenden Flow gezählt haben. Unter 2 Schritten: leerer String
## (nichts anzuzeigen).
static func step_hint_from_count(step_count: int) -> String:
	if step_count <= 1:
		return ""
	return "Step %d" % step_count
