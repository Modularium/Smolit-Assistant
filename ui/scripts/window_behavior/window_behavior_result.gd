extends RefCounted
## Linux Window Behavior — gemeinsamer Ergebnis-Schema-Helper
##
## Die Schicht in `ui/scripts/window_behavior/` besteht aus vier
## klar getrennten Rollen (siehe `docs/ui_architecture.md` §9 und
## `docs/linux_window_overlay_architecture.md` §F):
##
##   * **Detection / Capability** — `window_capabilities.gd`.
##   * **Probe / Verification**   — `window_probe.gd` (opt-in,
##                                   reversibel, keine Produktaktivierung).
##   * **Activation**             — `overlay_controller.gd`,
##                                   `overlay_click_through_controller.gd`,
##                                   `overlay_always_on_top_controller.gd`.
##   * **Reporting**              — `overlay_runtime_report.gd`.
##
## Jeder Aktivierungspfad hat bisher sein eigenes Status-Dictionary
## aufgebaut. Die Achsen waren kompatibel, aber nicht formal geteilt.
## Dieser Helper macht das gemeinsame Vokabular explizit, **ohne**
## existierendes Log-Format zu brechen: Controller fangen mit dem
## standardisierten Skeleton an und reichern es path-spezifisch an.
##
## Gemeinsame Achsen:
##
##   * `requested` (bool) — Nutzer hat den Pfad per Env explizit
##     angefordert.
##   * `capable` (bool)   — Vorbedingungen (Capability-Status,
##     Session, Flag-bekannt, Anchor-Typ) sind erfüllt; der Pfad
##     hätte aktivieren können.
##   * `applied` (bool)   — DisplayServer-Seite wurde tatsächlich
##     geschrieben (Flag gesetzt, Passthrough-Region übergeben, …).
##   * `observed` (bool)  — Rücklesewert / Zustandsprobe bestätigt die
##     Schreibung. Unter Headless oder strikter Gating oft `false`,
##     auch wenn `applied=false` — siehe pfad-spezifische Semantik.
##   * `active` (bool)    — Konsolidierter Endzustand. Smolit
##     betrachtet den Pfad nur dann als „läuft", wenn dieses Flag
##     `true` ist.
##   * `reason` (String)  — Einzeiler, der den Zustand erklärt.
##
## Path-spezifische Zusatzachsen bleiben erlaubt und sind pro
## Controller dokumentiert (z. B. Overlay: `transparency{}`,
## `borderless{}`; Click-through: `zones_derived`, `zones_valid`,
## `bounds`, `zones[]`; AOT: `session_type`, `display_driver`,
## `capability_status`, `capability_reason`, `candidate`).
##
## Wichtig: dieser Helper ist **ein Vokabular-/Bauhelfer**, kein
## neuer State-Container. Es gibt weiterhin keinen globalen
## Window-Behavior-State. Alle Aufrufe bleiben pro `_ready()`
## einmalig und returngebunden.

class_name SmolitWindowBehaviorResult


## Kanonische Reihenfolge der gemeinsamen Achsen. Genutzt zur
## Dokumentation und zur Konstruktion standardisierter Log-Zeilen
## (dort bereichert um path-spezifische Felder vor dem `active`-Tag).
const ACTIVATION_KEYS: Array = [
	"requested",
	"capable",
	"applied",
	"observed",
	"active",
	"reason",
]


## Factory: liefert ein frisches Status-Dict mit allen gemeinsamen
## Achsen auf ihren Default-Werten. Controller füllen path-spezifische
## Felder zusätzlich ein.
static func new_activation_status() -> Dictionary:
	return {
		"requested": false,
		"capable": false,
		"applied": false,
		"observed": false,
		"active": false,
		"reason": "",
	}


## Hilfsfunktion: standardisierte Kurzzeile für Pfade, die *nicht*
## bereits aufwendige Summary-Zeilen mit path-spezifischen Feldern
## haben. Aktuell verwendet der Runtime-Report diese Zeile als
## Zusatzüberschrift pro Aktivierungspfad.
static func format_standard_summary(path_prefix: String, status: Dictionary) -> String:
	return "[%s] requested=%s capable=%s applied=%s observed=%s active=%s" % [
		path_prefix,
		bool(status.get("requested", false)),
		bool(status.get("capable", false)),
		bool(status.get("applied", false)),
		bool(status.get("observed", false)),
		bool(status.get("active", false)),
	]


## Kleine Parser-freundliche Formatierung einer `Rect2`-Bounding-Box.
## Wird an mehreren Stellen (Click-through, Report) identisch
## gebraucht; vereinheitlicht hier die Darstellung.
static func format_rect(rect_variant: Variant) -> String:
	if typeof(rect_variant) != TYPE_RECT2:
		return "—"
	var rect: Rect2 = rect_variant
	return "(%.0f,%.0f %.0fx%.0f)" % [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]
