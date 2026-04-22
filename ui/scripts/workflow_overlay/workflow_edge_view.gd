extends Control
## Workflow-Overlay — kleiner, read-only Kanten-Renderer.
##
## Zeichnet eine einfache horizontale Linie zwischen zwei Knoten, plus
## einen optionalen kleinen Aktivitäts-Puls, wenn der Controller die
## Kante als `active` markiert. Keine Pfeilspitzen, keine Krümmung,
## keine Beschriftung — bewusst MVP.
##
## PR 2 passt das Verhalten leicht an:
##   * Zweistufige Darstellungsmodus-Unterstützung (`COLLAPSED` /
##     `EXPANDED`), analog zum Node-View. Im EXPANDED-Modus wird
##     die Kante etwas breiter (Mindestlänge) und die Linie minimal
##     kräftiger. Kein Designexzess — der Unterschied ist dezent.
##   * Ruhigere Aktivitätsanimation (längere Pulsdauer, leiseres
##     Färbe-Delta).
##
## Designregeln (unverändert):
##   * Kein eigener State über das hinaus, was der Controller per
##     `apply()` mitteilt.
##   * Kein externer Input, kein Signal nach außen.
##   * Die Puls-Animation läuft über einen internen Tween, der beim
##     Deaktivieren sauber zurückgesetzt wird.
##   * Kein Anspruch auf Markenfarben — die Linie verwendet eine
##     dezente neutrale Tönung.

class_name SmolitWorkflowEdgeView

const _StateRef := preload("res://scripts/workflow_overlay/workflow_overlay_state.gd")

const _LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.32)
const _LINE_COLOR_ACTIVE: Color = Color(0.80, 0.88, 1.00, 0.80)
const _PULSE_RADIUS: float = 3.0
## Aktivitätsgeschwindigkeit in Sekunden pro Laufdurchgang. Bewusst
## nicht hektisch — der Puls soll Aktivität andeuten, nicht Alarm.
## PR 2 verlängert die Dauer leicht, damit sich die Bewegung ruhiger
## anfühlt.
const _PULSE_DURATION: float = 1.45

const _MIN_SIZE_COLLAPSED: Vector2 = Vector2(24, 10)
const _MIN_SIZE_EXPANDED: Vector2  = Vector2(36, 12)
const _LINE_WIDTH_COLLAPSED: float = 1.25
const _LINE_WIDTH_EXPANDED: float  = 1.65

var _active: bool = false
var _display_mode: int = _StateRef.DisplayMode.COLLAPSED
var _pulse_progress: float = 0.0
var _pulse_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = _MIN_SIZE_COLLAPSED


## Steuert Aktivitätszustand und Darstellungsmodus der Kante.
## `display_mode` ist optional — fehlt er, wird der zuletzt gesetzte
## Modus beibehalten, damit ein bloßes „active → inactive"-Update die
## Größe nicht unnötig zurücksetzt.
func apply(active: bool, display_mode: int = -1) -> void:
	if display_mode == _StateRef.DisplayMode.COLLAPSED \
			or display_mode == _StateRef.DisplayMode.EXPANDED:
		if display_mode != _display_mode:
			_display_mode = display_mode
			_apply_display_mode_size()
			queue_redraw()

	if active == _active:
		# Auch ohne Zustandswechsel ggf. Mode-Update (oben) anwenden.
		return
	_active = active
	if _active:
		_start_pulse()
	else:
		_stop_pulse()
	queue_redraw()


func _apply_display_mode_size() -> void:
	custom_minimum_size = _MIN_SIZE_EXPANDED \
		if _display_mode == _StateRef.DisplayMode.EXPANDED \
		else _MIN_SIZE_COLLAPSED


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
	var width: float = _LINE_WIDTH_EXPANDED \
		if _display_mode == _StateRef.DisplayMode.EXPANDED \
		else _LINE_WIDTH_COLLAPSED
	draw_line(line_from, line_to, color, width, true)
	if _active:
		# Ein einzelner kleiner Puls läuft von links nach rechts.
		var x: float = lerp(0.0, rect.size.x, _pulse_progress)
		draw_circle(Vector2(x, y), _PULSE_RADIUS, color)
