extends Control
## Workflow-Overlay — kleiner, read-only Kanten-Renderer.
##
## Zeichnet eine einfache horizontale Linie zwischen zwei Knoten, plus
## einen optionalen kleinen Aktivitäts-Puls, wenn der Controller die
## Kante als `active` markiert. Keine Pfeilspitzen, keine Krümmung,
## keine Beschriftung — bewusst MVP.
##
## Designregeln:
##   * Kein eigener State über das hinaus, was der Controller per
##     `apply()` mitteilt.
##   * Kein externer Input, kein Signal nach außen.
##   * Die Puls-Animation läuft über einen internen Tween, der beim
##     Deaktivieren sauber zurückgesetzt wird.
##   * Kein Anspruch auf Markenfarben — die Linie verwendet eine
##     dezente neutrale Tönung.

class_name SmolitWorkflowEdgeView

const _LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
const _LINE_COLOR_ACTIVE: Color = Color(0.80, 0.88, 1.00, 0.85)
const _PULSE_RADIUS: float = 3.5
## Aktivitätsgeschwindigkeit in Sekunden pro Laufdurchgang. Bewusst
## nicht hektisch — der Puls soll Aktivität andeuten, nicht Alarm.
const _PULSE_DURATION: float = 1.1

var _active: bool = false
var _pulse_progress: float = 0.0
var _pulse_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 12)


func apply(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if _active:
		_start_pulse()
	else:
		_stop_pulse()
	queue_redraw()


func _start_pulse() -> void:
	_stop_pulse()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_method(
		Callable(self, "_on_pulse_tick"), 0.0, 1.0, _PULSE_DURATION
	)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_pulse_progress = 0.0
	queue_redraw()


func _on_pulse_tick(progress: float) -> void:
	_pulse_progress = progress
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var y: float = rect.size.y * 0.5
	var line_from := Vector2(0.0, y)
	var line_to := Vector2(rect.size.x, y)
	var color := _LINE_COLOR_ACTIVE if _active else _LINE_COLOR
	draw_line(line_from, line_to, color, 1.5, true)
	if _active:
		# Ein einzelner kleiner Puls läuft von links nach rechts.
		var x: float = lerp(0.0, rect.size.x, _pulse_progress)
		draw_circle(Vector2(x, y), _PULSE_RADIUS, color)
