extends Control
## Avatar Rim Accent — dünner prozeduraler State-Ring am Silhouetten-Rand.
##
## Zeichnet einen sehr schlanken Kreisring am Rand des Avatar-Layouts und
## färbt ihn passend zum aktuellen `AvatarState`. Der Ring ist:
##
##   * rein visuell — keine Animation, keine Logik, keine Eingabe-Annahme,
##   * identitäts-neutral — Smolit-Texture wie kuratierte Alternativen
##     teilen sich denselben Rim. Der Capability-Contract bleibt die
##     einzige Ausdruckslogik, die sich pro Template verzweigen darf; der
##     Rim ist Presence-Polish, kein Template-Feature.
##   * stumm beim State-Wechsel — `set_state` triggert genau ein
##     `queue_redraw`. Keine Tweens, keine Timer.
##
## Die Farbwahl ist bewusst moderat (niedrige Alpha), damit der Rim die
## bestehende Avatar-Figur nicht überdeckt; er setzt nur einen kleinen
## zusätzlichen State-Akzent an der Silhouette.

class_name SmolitAvatarRimAccent

const _StateRef := preload("res://scripts/avatar/avatar_state.gd")


## Ring-Geometrie: Inset vom Layout-Rand und Linienstärke — jeweils als
## Ratio zur kürzeren Layout-Kante, damit der Rim bei Scale-Varianten
## mitskaliert. Werte sind klein gewählt, damit der Rim sich visuell wie
## eine zurückhaltende Silhouetten-Fassung anfühlt und nicht wie ein
## dominanter Rahmen.
const RING_INSET_RATIO: float = 0.02    # ~1.8 px auf 88 px Avatar-Body
const RING_THICKNESS_RATIO: float = 0.025  # ~2.2 px auf 88 px Avatar-Body
const ARC_SEGMENTS: int = 96            # anti-aliased Kreisringe


## Farben pro State. Bewusst harmonisch zur bestehenden Modulate-Kette
## (NORMAL / THINKING / ERROR / DISCONNECTED / ACTING-by-Target) gewählt,
## aber jeweils etwas gedeckter. Der Ring soll den Zustand *akzentuieren*,
## nicht erzwingen.
const COLOR_IDLE: Color = Color(0.70, 0.85, 1.00, 0.28)
const COLOR_THINKING: Color = Color(0.80, 0.82, 1.00, 0.42)
const COLOR_TALKING: Color = Color(1.00, 0.90, 0.65, 0.55)
const COLOR_ACTING: Color = Color(0.78, 1.00, 0.82, 0.55)
const COLOR_DISCONNECTED: Color = Color(0.60, 0.60, 0.66, 0.18)
const COLOR_ERROR: Color = Color(1.00, 0.55, 0.55, 0.70)


var _state: int = _StateRef.DEFAULT


func _ready() -> void:
	# Der Avatar-Controller (`AvatarRoot`) behält den Klick-/Drag-Flow.
	# Wir sind Presence-Polish, kein Klickziel.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## Setzt den anzuzeigenden State und triggert (bei Änderung) genau ein
## Re-Draw. Unbekannte Werte fallen auf `IDLE` zurück (siehe
## `color_for_state`), aber der State selbst wird trotzdem gespeichert —
## so bleibt `current_state()` ehrlich zu dem, was der Controller
## angefragt hat.
func set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	queue_redraw()


func current_state() -> int:
	return _state


## Pure Lookup — trennt die Farbzuordnung vom Scene-Draw und macht sie
## ohne Scene-Tree testbar. Unbekannte States werden defensiv auf IDLE-
## Farbe geklemmt; der Ring bleibt damit immer definiert.
static func color_for_state(state: int) -> Color:
	match state:
		_StateRef.State.IDLE: return COLOR_IDLE
		_StateRef.State.THINKING: return COLOR_THINKING
		_StateRef.State.TALKING: return COLOR_TALKING
		_StateRef.State.ACTING: return COLOR_ACTING
		_StateRef.State.DISCONNECTED: return COLOR_DISCONNECTED
		_StateRef.State.ERROR: return COLOR_ERROR
		_: return COLOR_IDLE


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var color := color_for_state(_state)
	var center: Vector2 = size * 0.5
	var short_edge: float = minf(size.x, size.y)
	var radius: float = short_edge * (0.5 - RING_INSET_RATIO)
	var width: float = maxf(1.0, short_edge * RING_THICKNESS_RATIO)
	# Godot hat kein `draw_ring`; ein voller Bogen mit definierter
	# Linienstärke liefert denselben Effekt, inkl. Anti-Aliasing.
	draw_arc(center, radius, 0.0, TAU, ARC_SEGMENTS, color, width, true)
