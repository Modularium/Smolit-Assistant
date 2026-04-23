extends RefCounted
## Visual Action Mode — MVP-Interpretation der Produktachse aus
## `docs/presence_desktop_interaction.md §7`.
##
## Die Produktachse kennt vier Modi (`none` / `minimal_feedback` /
## `guided_movement` / `full_theatrical`) und beschreibt, **wie viel**
## Smolit von einer laufenden Aktion sichtbar macht. Das endgültige
## Produktziel umfasst z. B. eine Zielkoordinate und eine echte
## Bewegungsbahn des Avatars (§7.3 / §7.4). Dieses Modul liefert
## **bewusst nur** den MVP-Anteil:
##
##   * Die vier Mode-Namen der Produktachse bleiben unverändert.
##   * Die Unterschiede zwischen den Modi werden als **UI-Staging-Achse
##     innerhalb der bestehenden Presence-Hülle** interpretiert: Action-
##     Banner und Workflow-Overlay werden pro Modus sichtbar / still /
##     ganz aus. Keine Bildschirmwanderung, keine Pixel-Ziele, keine
##     Choreografie über Fremdfenster — das würde Produktversprechen
##     einlösen, die wir heute architektonisch nicht haben.
##
## Was dieses Modul ist:
##
##   * Ein kleines, rein deklaratives Modul. Keine Scene, kein Tween,
##     kein Event-Subscriber.
##   * Ein Parser für Mode-Strings, der unbekannte Eingaben still auf
##     den Default (`MINIMAL_FEEDBACK`) zurückfallen lässt.
##   * Eine pure Staging-Tabelle (`staging_for`), die pro Modus genau
##     vier Flags / Intensitäten liefert: Action-Banner-Sichtbarkeit
##     und -Alpha, Workflow-Overlay-Freigabe und -Alpha.
##
## Was dieses Modul **nicht** ist:
##
##   * Keine neue State-Maschine. Presence-State (Docked/Expanded/
##     Action/Disconnected) und Avatar-State (Idle/Thinking/Talking/
##     Acting/Disconnected/Error) bleiben die maßgeblichen Achsen.
##   * Keine neue Action-Wahrheit. Der Modus moduliert nur, wie laut
##     die bestehenden Action Events im UI wirken — er erzeugt keine
##     Events, filtert sie nicht und ändert nichts am Event-Schema.
##   * Keine Desktop-Automation, keine Pixel-Geometrie, keine Policy-
##     oder Approval-Kopplung. Der Modus darf niemals Grundlage für
##     „darf Smolit das tun?" werden.

class_name SmolitVisualActionMode


## Produkt-Modi aus `docs/presence_desktop_interaction.md §7`.
## Reihenfolge ist UI-relevant (Dev-Picker zeigt sie in dieser Folge).
enum Mode {
	NONE,
	MINIMAL_FEEDBACK,
	GUIDED_MOVEMENT,
	FULL_THEATRICAL,
}


## Ehrlicher, konservativer Default: `minimal_feedback` — dezente
## Action-Sichtbarkeit, wie sie das heutige Presence-MVP ohnehin
## anzeigt. Der Default soll den aktuellen Ist-Stand reproduzieren,
## damit Nutzer ohne Konfiguration dieselbe UI sehen wie bisher.
const DEFAULT: int = Mode.MINIMAL_FEEDBACK


## Kanonische Namen pro Modus. Werden sowohl für Env-Parsing als auch
## für Preferences-Persistenz verwendet.
const _NAME_NONE: String = "none"
const _NAME_MINIMAL: String = "minimal_feedback"
const _NAME_GUIDED: String = "guided_movement"
const _NAME_FULL: String = "full_theatrical"


static func name_of(mode: int) -> String:
	match mode:
		Mode.NONE: return _NAME_NONE
		Mode.MINIMAL_FEEDBACK: return _NAME_MINIMAL
		Mode.GUIDED_MOVEMENT: return _NAME_GUIDED
		Mode.FULL_THEATRICAL: return _NAME_FULL
		_: return _NAME_MINIMAL


## Robuster Parser. Akzeptiert pro Modus eine kleine Alias-Liste
## (kurze Kommandozeilen-freundliche Varianten), aber *nie*
## Freiformtexte. Unbekannte Eingaben fallen still auf den Default
## zurück — kein Crash, kein Log-Spam.
static func mode_from_string(value: String) -> int:
	match value.strip_edges().to_lower():
		"none", "off", "silent":
			return Mode.NONE
		"minimal_feedback", "minimal", "min":
			return Mode.MINIMAL_FEEDBACK
		"guided_movement", "guided", "guide":
			return Mode.GUIDED_MOVEMENT
		"full_theatrical", "theatrical", "full", "demo":
			return Mode.FULL_THEATRICAL
		_:
			return DEFAULT


## Ein bekannter int-Wert → derselbe Wert; sonst Default. Schützt
## Caller, die direkt mit Enum-Integer-Eingaben arbeiten (z. B. aus
## einer alten Preferences-Datei).
static func coerce(mode: int) -> int:
	match mode:
		Mode.NONE, Mode.MINIMAL_FEEDBACK, Mode.GUIDED_MOVEMENT, Mode.FULL_THEATRICAL:
			return mode
		_:
			return DEFAULT


## Listet alle Modi in UI-Picker-Reihenfolge. Smolit-First gilt hier
## nicht — die Achse ist ein UI-Intensitäts-Slider, kein Identity-
## Selektor. Stattdessen folgt die Reihenfolge der Produktachse aus
## §7 (aufsteigende Sichtbarkeit).
static func all_modes() -> Array:
	return [
		Mode.NONE,
		Mode.MINIMAL_FEEDBACK,
		Mode.GUIDED_MOVEMENT,
		Mode.FULL_THEATRICAL,
	]


## Menschlich lesbare Labels für Dev-Controls / Doku-Ausgaben.
static func label_of(mode: int) -> String:
	match mode:
		Mode.NONE: return "None"
		Mode.MINIMAL_FEEDBACK: return "Minimal feedback"
		Mode.GUIDED_MOVEMENT: return "Guided movement"
		Mode.FULL_THEATRICAL: return "Full theatrical"
		_: return "Minimal feedback"


## Staging-Tabelle. Pro Modus genau vier deterministische Werte:
##
##   * `banner_visible` (bool) — soll das Action-Banner überhaupt
##     während aktiver Actions angezeigt werden?
##   * `banner_alpha` (float, 0.0..1.0) — zusätzlicher Alpha-
##     Multiplikator auf das Banner-`modulate`. Nur wenn
##     `banner_visible` gilt.
##   * `workflow_overlay_allowed` (bool) — darf das Workflow-Overlay
##     überhaupt sichtbar werden? Seine interne Flow-Sichtbarkeit
##     wird davon **gate**d (nicht gekillt) — bei `false` bleibt das
##     Overlay zwangsweise versteckt.
##   * `workflow_overlay_alpha` (float, 0.0..1.0) — zusätzlicher
##     Alpha-Multiplikator auf den Overlay-Root. Nur wenn
##     `workflow_overlay_allowed` gilt.
##
## Werte sind bewusst klein: `none` versteckt alles, die drei anderen
## Stufen unterscheiden sich nur in Nuancen. Das ist ehrlich — das
## heutige UI-System kann weder echte Bewegungsbahnen noch Ziel-
## koordinaten inszenieren; `guided_movement` und `full_theatrical`
## bleiben hier **reine In-Place-Intensitätsstufen**.
static func staging_for(mode: int) -> Dictionary:
	match coerce(mode):
		Mode.NONE:
			return {
				"banner_visible": false,
				"banner_alpha": 0.0,
				"workflow_overlay_allowed": false,
				"workflow_overlay_alpha": 0.0,
			}
		Mode.MINIMAL_FEEDBACK:
			return {
				"banner_visible": true,
				"banner_alpha": 0.75,
				"workflow_overlay_allowed": false,
				"workflow_overlay_alpha": 0.0,
			}
		Mode.GUIDED_MOVEMENT:
			return {
				"banner_visible": true,
				"banner_alpha": 0.92,
				"workflow_overlay_allowed": true,
				"workflow_overlay_alpha": 0.80,
			}
		Mode.FULL_THEATRICAL:
			return {
				"banner_visible": true,
				"banner_alpha": 1.00,
				"workflow_overlay_allowed": true,
				"workflow_overlay_alpha": 1.00,
			}
		_:
			# coerce sollte das nie produzieren; defensiver Fallback.
			return staging_for(DEFAULT)
