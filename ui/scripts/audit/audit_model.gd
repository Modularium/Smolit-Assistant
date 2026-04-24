extends RefCounted
## Local Audit Trail v1 — UI-seitiger Formatter (PR 19).
##
## Reine RefCounted-Helfer für die Darstellung der `audit_recent`-
## Envelopes. Der Core liefert bereits sanitisierte Felder (kurze
## Summaries, kuratierte Vokabeln); das UI-Modul bringt sie in ein
## UI-freundliches Format.
##
## Grenzen (zum Mitnehmen):
##
##   * **Keine zusätzliche Redaktion.** Das Modul trimmt nur kosmetisch
##     auf die sichtbare Label-Länge; der Core ist für die sensible
##     Sanitisierung verantwortlich.
##   * **Keine Persistenz.** Die Liste wird bei jedem
##     `audit_recent_received` vollständig ersetzt.
##   * **Keine Export-/Kopierfunktion.** Die Audit-View ist Debug-
##     only und lebt hinter `SMOLIT_UI_DEV_CONTROLS=1`.

class_name SmolitAuditModel


## Visible label-length defaults. Der Core hat bereits hart gekürzt
## (80 Zeichen Summary), wir verengen optisch weiter.
const MAX_SUMMARY_CHARS: int = 60
const MAX_ID_CHARS: int = 12
const ELLIPSIS: String = "…"


const KNOWN_KINDS: Array = [
	"ipc_command_received",
	"ipc_command_rejected",
	"action_planned",
	"approval_requested",
	"approval_resolved",
	"action_started",
	"action_completed",
	"action_cancelled",
	"action_failed",
]

const _KIND_LABELS: Dictionary = {
	"ipc_command_received": "cmd in",
	"ipc_command_rejected": "cmd rej",
	"action_planned":       "planned",
	"approval_requested":   "apr req",
	"approval_resolved":    "apr res",
	"action_started":       "started",
	"action_completed":     "done",
	"action_cancelled":     "cancel",
	"action_failed":        "failed",
}

const _RESULT_COLOR: Dictionary = {
	"approved":  Color(0.70, 1.00, 0.75, 0.95),
	"completed": Color(0.70, 1.00, 0.75, 0.95),
	"denied":    Color(1.00, 0.70, 0.70, 1.00),
	"cancelled": Color(1.00, 0.70, 0.70, 1.00),
	"rejected":  Color(1.00, 0.70, 0.70, 1.00),
	"failed":    Color(1.00, 0.70, 0.70, 1.00),
	"expired":   Color(0.85, 0.80, 0.60, 0.90),
}

const _RISK_COLOR: Dictionary = {
	"low":    Color(0.70, 0.95, 0.75, 1.0),
	"medium": Color(1.00, 0.92, 0.60, 1.0),
	"high":   Color(1.00, 0.65, 0.65, 1.0),
}


static func kind_label(raw: Variant) -> String:
	var key: String = _lower(raw)
	if _KIND_LABELS.has(key):
		return String(_KIND_LABELS[key])
	return key if key != "" else "?"


static func is_known_kind(raw: Variant) -> bool:
	return KNOWN_KINDS.has(_lower(raw))


static func result_color(raw: Variant) -> Color:
	var key: String = _lower(raw)
	var value: Variant = _RESULT_COLOR.get(key, Color(1, 1, 1, 0.6))
	return value if value is Color else Color(1, 1, 1, 0.6)


static func risk_color(raw: Variant) -> Color:
	var key: String = _lower(raw)
	var value: Variant = _RISK_COLOR.get(key, Color(1, 1, 1, 0.55))
	return value if value is Color else Color(1, 1, 1, 0.55)


## Kürzt Audit-IDs (aud_000017 → aud_00001…) rein kosmetisch auf die
## sichtbare Label-Länge. Keine Sicherheits-Redaktion; der Core ist
## dafür zuständig, dass IDs keine sensiblen Daten tragen.
static func short_id(raw: Variant) -> String:
	var s: String = _string(raw).strip_edges()
	if s.length() <= MAX_ID_CHARS:
		return s
	return s.substr(0, max(1, MAX_ID_CHARS - ELLIPSIS.length())) + ELLIPSIS


static func short_summary(raw: Variant) -> String:
	var s: String = _string(raw).strip_edges()
	if s.length() <= MAX_SUMMARY_CHARS:
		return s
	return s.substr(0, max(1, MAX_SUMMARY_CHARS - ELLIPSIS.length())) + ELLIPSIS


## Formatiert einen relativen Zeitstempel (ms since epoch) in ein
## sehr kurzes `HH:MM:SS`-Label — nur informativ, kein Datum, keine
## Zeitzone.
static func short_time(raw: Variant) -> String:
	var ms: int = _int(raw)
	if ms <= 0:
		return ""
	var seconds: int = int(float(ms) / 1000.0)
	var hours: int = (seconds / 3600) % 24
	var minutes: int = (seconds / 60) % 60
	var secs: int = seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, secs]


## Defensive Payload-Lesung: erwartet ein Dictionary mit der Form
## `{ "events": [...] }`. Alles andere wird auf eine leere Liste
## geklemmt.
static func events_from_payload(payload: Variant) -> Array:
	if typeof(payload) != TYPE_DICTIONARY:
		return []
	var raw: Variant = (payload as Dictionary).get("events", [])
	if raw is Array:
		var safe: Array = []
		for entry in raw:
			if entry is Dictionary:
				safe.append(entry)
		return safe
	return []


static func _string(raw: Variant) -> String:
	if raw == null:
		return ""
	return String(raw)


static func _lower(raw: Variant) -> String:
	return _string(raw).strip_edges().to_lower()


static func _int(raw: Variant) -> int:
	if typeof(raw) == TYPE_INT:
		return int(raw)
	if typeof(raw) == TYPE_FLOAT:
		return int(raw)
	if typeof(raw) == TYPE_STRING:
		var s: String = String(raw)
		return int(s) if s.is_valid_int() else 0
	return 0
