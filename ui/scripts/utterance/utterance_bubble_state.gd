extends RefCounted
## Utterance-Bubble — pure Helfer für Text-Shaping und Kind-Semantik.
##
## Kleine Datenstruktur + pure static Helper, die der
## `utterance_bubble_controller` aus den bestehenden EventBus-Signalen
## `heard_received` / `response_received` ableitet. Enthält bewusst
## **keine Scene-/Tween-Logik** — dieses Modul ist rein sprachlich /
## text-normalisierend und aus dem Smoketest ohne Scene-Tree prüfbar.
##
## Grenzen (bindend):
##   * Kein Konversationsverlauf, keine Nachrichtenliste.
##   * Keine Persistenz, kein Log.
##   * Kein Chat-Rendering — die Bubble ist Presence-UI, kein
##     Transcript-Renderer.
##   * Keine Stage-C-/Appearance-/Policy-Kopplung.

class_name SmolitUtteranceBubbleState


## Welche Art Utterance wird aktuell angezeigt. `NONE` heißt „keine
## Bubble sichtbar"; der Controller nutzt diesen Zustand als Initial-
## und Clear-Wert. `HEARD` zeigt, was Smolit verstanden hat; `RESPONSE`
## zeigt die Antwort des Assistants.
enum Kind {
	NONE,
	HEARD,
	RESPONSE,
}


## Obere Zeichengrenze, damit die Bubble nicht zu einer Textwand wird.
## Bewusst großzügig genug für 2–3 lesbare Zeilen, aber nicht für einen
## ganzen Absatz. Längere Texte werden mit Ellipsis abgeschnitten —
## das ist eine Anzeigegrenze, keine Zensur, der Core bleibt Wahrheit.
const MAX_CHARS: int = 240


## Ellipsis-Suffix bei Abschnitt. Unicode-Ellipsis statt drei Punkten,
## damit die Kürzung optisch klar ist.
const ELLIPSIS: String = "…"


## Anzeigedauer (Sekunden) pro Kind, ab dem Moment, in dem der Text
## gesetzt ist. `RESPONSE` bleibt etwas länger stehen, weil die Antwort
## in der Regel der für den Nutzer relevantere Text ist; `HEARD` fadet
## schneller wieder aus, um die Bubble nicht zu überladen, wenn direkt
## eine Antwort folgt. Werte bleiben klein und ausdrücklich im
## Sekundenbereich — kein Log-Fenster.
const DISPLAY_SECONDS_HEARD: float = 3.5
const DISPLAY_SECONDS_RESPONSE: float = 6.0


## Fade-Timings. Bewusst kurze In-Animation, etwas längerer Fade-out,
## damit die Bubble nicht schlagartig verschwindet. Keine Dauern über
## 0.5 s — die Bubble soll ruhig wirken, nicht theatralisch.
const FADE_IN_SECONDS: float = 0.12
const FADE_OUT_SECONDS: float = 0.30


static func kind_name(kind: int) -> String:
	match kind:
		Kind.NONE: return "none"
		Kind.HEARD: return "heard"
		Kind.RESPONSE: return "response"
		_: return "none"


## Normalisiert einen eingehenden Utterance-Text:
##   * strip_edges (führender/nachgestellter Whitespace),
##   * harte Zeichengrenze `MAX_CHARS` inkl. Ellipsis,
##   * leere Eingabe bleibt leer (Controller blendet dann aus).
##
## Kein Markdown, kein BBCode, kein HTML — die Bubble ist Label-basiert,
## nicht RichText-basiert. Das hält die Vertrauensoberfläche klein:
## eingehender Text wird nicht als Formatierung interpretiert.
static func normalize_text(raw: String) -> String:
	var trimmed: String = raw.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.length() <= MAX_CHARS:
		return trimmed
	# Ellipsis frisst die letzten Zeichen, damit Gesamtlänge ≤ MAX_CHARS bleibt.
	var cut: int = MAX_CHARS - ELLIPSIS.length()
	if cut < 1:
		return ELLIPSIS
	return trimmed.substr(0, cut) + ELLIPSIS


## Hilfsprädikat für den Controller: ist in diesem Kind/Text-Paar
## überhaupt etwas Sichtbares? Leerer Text oder `Kind.NONE` führen zu
## `false` — die Bubble bleibt dann ausgeblendet.
static func has_content(kind: int, text: String) -> bool:
	if kind == Kind.NONE:
		return false
	return not text.is_empty()


## Anzeigedauer pro Kind. Unbekannte Kinds fallen defensiv auf die
## kurze HEARD-Dauer zurück; da `Kind.NONE` nie sichtbar wird, ist das
## nur Absicherung gegen zukünftige Enum-Erweiterungen.
static func display_seconds_for(kind: int) -> float:
	match kind:
		Kind.HEARD: return DISPLAY_SECONDS_HEARD
		Kind.RESPONSE: return DISPLAY_SECONDS_RESPONSE
		_: return DISPLAY_SECONDS_HEARD


## Kleines Label für den Chip („heard" / „response"). Leer bei NONE.
## Wird nur zur Unterscheidung genutzt — kein Konversationsprotokoll.
static func chip_label_for(kind: int) -> String:
	match kind:
		Kind.HEARD: return "heard"
		Kind.RESPONSE: return "response"
		_: return ""
