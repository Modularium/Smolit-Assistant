extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — Wayland/wlroots-Backend (experimenteller Pfad)
##
## Benannter Platzhalter für wlroots-basierte Wayland-Compositoren
## (Sway, Hyprland, Wayfire, river, labwc). Dieses Backend ist **der
## einzige**, der einen `experimental_stance` trägt — es markiert
## die Stelle, an der ein späterer echter wlroots-Overlay-/Dock-
## Layer-Pfad (`wlr-layer-shell-unstable-v1` + verwandte Protokolle)
## aufsetzen würde, wenn wlroots-Sessions ein relevantes Nutzer-
## segment werden.
##
## Status heute (bewusst klein):
##   * Das Backend **delegiert weiterhin** an die existierenden
##     Controller. Overlay / Click-through laufen über ihre
##     regulären Pfade, AOT wird wie überall unter Wayland
##     verweigert.
##   * Es wird **nichts** layer-shell-spezifisches gesetzt, es gibt
##     **keine** neue Plattformaktivierung.
##   * Die Aktivierungs-Dicts werden lediglich *additiv* um einen
##     `wlroots_research`-Marker ergänzt, damit der Runtime-Report
##     sichtbar machen kann, dass dieser experimentelle Sonder-
##     platzhalter vorhanden ist, ohne ihn als funktional zu
##     verkaufen.
##
## Forschungs-/Decision-Dokument zum späteren echten Pfad:
##   * `docs/wlroots_overlay_path.md`
##
## Architektureinordnung:
##   * Differenzierung gegenüber `backend_wayland_mutter` ist heute
##     primär dokumentarisch + dieser Stance-Marker. Der Unterschied
##     wird erst funktional sichtbar, wenn hier layer-shell
##     dazukommt. Das ist ausdrücklich **nicht** dieser PR.
##   * Kein Scope-Creep: kein Snap-to-edge, kein Multi-Monitor, kein
##     produktives AOT-Versprechen.

class_name SmolitWindowBackendWaylandWlroots

## Kleiner, unveränderlicher Marker, den das Backend in die
## Aktivierungs-Ergebnis-Dicts einträgt. Rein diagnostisch — die
## bestehenden Achsen (`requested/capable/applied/observed/active/
## reason`) werden dadurch nicht verändert, ergänzt nur.
const _RESEARCH_MARKER: Dictionary = {
	"target_family": "wlroots",
	"target_protocol": "wlr-layer-shell-unstable-v1",
	"state": "prepared, not implemented",
	"reference": "docs/wlroots_overlay_path.md",
}


func _init() -> void:
	backend_id = "wayland-wlroots"
	backend_description = "Wayland/wlroots-family compositor — overlay/click-through delegate; always-on-top refuses by design; no layer-shell yet"
	experimental_stance = "experimental seat for a future wlr-layer-shell-unstable-v1 path — not active today, see docs/wlroots_overlay_path.md"


func activate_overlay_if_requested(anchor: Node) -> Dictionary:
	return _annotate(super.activate_overlay_if_requested(anchor))


func activate_click_through_if_requested(
	anchor: Node, overlay_result: Dictionary
) -> Dictionary:
	return _annotate(super.activate_click_through_if_requested(anchor, overlay_result))


func activate_always_on_top_if_requested(anchor: Node) -> Dictionary:
	return _annotate(super.activate_always_on_top_if_requested(anchor))


## Ergänzt das vom Base-Delegationspfad zurückgelieferte Dict um
## einen `wlroots_research`-Block. Keine Überschreibung bestehender
## Felder — dadurch bleiben Verifikations-Snapshots und Log-Output
## der Basis-Delegation stabil; neue Konsumenten (z. B. Runtime-
## Report) können das Feld optional auslesen.
static func _annotate(result: Dictionary) -> Dictionary:
	# Wenn das Ergebnis aus irgendeinem Grund leer/nicht-Dictionary
	# ist, geben wir es unverändert zurück — kein Stolperdraht für
	# zukünftige Varianten des Basispfads.
	if typeof(result) != TYPE_DICTIONARY:
		return result
	# Bereits vorhandener Marker (z. B. durch verschachtelte Aufrufe)
	# bleibt bestehen; Base-Delegationen erzeugen keinen, daher ist
	# das Setzen hier im Normalfall additiv.
	if not result.has("wlroots_research"):
		result["wlroots_research"] = _RESEARCH_MARKER
	return result
