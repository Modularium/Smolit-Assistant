extends RefCounted
## Approval UX v1 (PR 17) — pure Modell-Helfer.
##
## Die Approval-Card rendert live das aktuell offene Approval. Das
## Modell selbst hält keine Historie, keine Session-Speicherung und
## keine neuen IPC-Envelopes; es bündelt nur die kleinen Helfer, die
## Card und Smoke gemeinsam brauchen (Risk-Vokabular, Summary-
## Kürzung, Pairing mit PR-16-Workflow-Kategorien).
##
## Harte Grenzen:
##
##   * **Kein Logik-Block über der bestehenden Core-Approval-Engine.**
##     Der Core bleibt Source of Truth — das Modell formatiert nur.
##   * **Keine langen Inhalte.** `MAX_SUMMARY_CHARS = 140` — die
##     Approval-Card ist keine Detail-Payload-Anzeige. Sensible
##     Langtexte gehören nicht in die UX.
##   * **Keine Desktop-/Shell-/AdminBot-Verdrahtung.** Die Schicht
##     weiß nichts über Action-Ausführung, Provider, Settings oder
##     Policy. Sie rendert nur eine Frage und gibt Approve/Deny
##     weiter.

class_name SmolitApprovalModel


const RISK_LOW: String = "low"
const RISK_MEDIUM: String = "medium"
const RISK_HIGH: String = "high"
const DEFAULT_RISK: String = RISK_MEDIUM

const KNOWN_RISKS: Array = [RISK_LOW, RISK_MEDIUM, RISK_HIGH]

const RISK_LABEL: Dictionary = {
	RISK_LOW: "low",
	RISK_MEDIUM: "medium",
	RISK_HIGH: "high",
}

const RISK_COLOR: Dictionary = {
	RISK_LOW: Color(0.70, 0.95, 0.75, 1.0),
	RISK_MEDIUM: Color(1.00, 0.92, 0.60, 1.0),
	RISK_HIGH: Color(1.00, 0.65, 0.65, 1.0),
}

const DECISION_APPROVED: String = "approved"
const DECISION_DENIED: String = "denied"
const DECISION_CANCELLED: String = "cancelled"
const DECISION_TIMED_OUT: String = "timed_out"
const DECISION_EXPIRED: String = "expired"

const SOURCE_USER: String = "user"
const SOURCE_TIMEOUT: String = "timeout"
const SOURCE_SYSTEM: String = "system"

## Maximale Länge einer sichtbaren Summary (inkl. Ellipsis). Bewusst
## klein — sensible Full-Payloads dürfen nicht auf die Oberfläche
## leaken.
const MAX_SUMMARY_CHARS: int = 140
const ELLIPSIS: String = "…"

## Titel-Obergrenze. Die Core-Engine kuratiert Titel bereits; wir
## kappen trotzdem, damit ein defektes Payload nicht das Layout
## sprengt.
const MAX_TITLE_CHARS: int = 80


static func sanitize_risk(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return DEFAULT_RISK
	var normalized: String = String(raw).strip_edges().to_lower()
	if normalized.is_empty():
		return DEFAULT_RISK
	for known in KNOWN_RISKS:
		if normalized == String(known):
			return normalized
	return DEFAULT_RISK


static func risk_label(raw: Variant) -> String:
	var key: String = sanitize_risk(raw)
	return String(RISK_LABEL.get(key, RISK_LABEL[DEFAULT_RISK]))


static func risk_color(raw: Variant) -> Color:
	var key: String = sanitize_risk(raw)
	var value: Variant = RISK_COLOR.get(key, RISK_COLOR[DEFAULT_RISK])
	if value is Color:
		return value
	return Color(1, 1, 1, 1)


## Kürzt rohen Summary-Text auf die sichtbare Länge. Whitespace außen
## wird gestrippt; längere Texte werden mit Ellipsis abgeschnitten.
static func trim_summary(raw: Variant) -> String:
	return _trim_to(raw, MAX_SUMMARY_CHARS)


static func trim_title(raw: Variant) -> String:
	return _trim_to(raw, MAX_TITLE_CHARS)


## Liefert `true`, wenn ein Payload-Feld als Decision-Finale gewertet
## werden kann. Alle unbekannten Werte fallen defensiv auf `false`,
## damit ein verbogener Core nicht versehentlich die Card schließt.
static func is_terminal_decision(decision: Variant) -> bool:
	if typeof(decision) != TYPE_STRING:
		return false
	match String(decision):
		DECISION_APPROVED, DECISION_DENIED, DECISION_CANCELLED, DECISION_TIMED_OUT, DECISION_EXPIRED:
			return true
		_:
			return false


## Einheitliche Klassifizierung für Workflow-Visibility und Avatar-
## Expression: ein Decision-Label wird auf `"approved" | "failed" |
## "skipped" | "unknown"` gemappt. `timed_out` / `expired` zählen als
## `skipped` (weiche Form), `denied` / `cancelled` als `failed`.
static func decision_outcome(decision: Variant) -> String:
	if typeof(decision) != TYPE_STRING:
		return "unknown"
	match String(decision):
		DECISION_APPROVED:
			return "approved"
		DECISION_DENIED, DECISION_CANCELLED:
			return "failed"
		DECISION_TIMED_OUT, DECISION_EXPIRED:
			return "skipped"
		_:
			return "unknown"


static func _trim_to(raw: Variant, limit: int) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var text: String = String(raw).strip_edges()
	if text.length() <= limit:
		return text
	return text.substr(0, max(1, limit - ELLIPSIS.length())) + ELLIPSIS
