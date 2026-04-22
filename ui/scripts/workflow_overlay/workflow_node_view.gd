extends PanelContainer
## Workflow-Overlay — kleiner, read-only Knoten-Renderer.
##
## Jede Instanz zeigt *eine* Station des Kurz-Flows (Trigger / Action /
## Result). Der Node-View kennt kein Graph-Framework, keine Layout-
## Algorithmen — er rendert nur das, was ihm der Controller über
## `apply()` mitteilt.
##
## PR 2 fügt hinzu:
##   * Zwei visuelle Dichtestufen (`COLLAPSED` / `EXPANDED`) aus
##     `workflow_overlay_state.gd::DisplayMode`. Sie steuern
##     min-Größen, Padding und Schriftgrad, **nicht** die
##     Node-Anzahl oder Semantik.
##   * Optionales sekundäres Hint-Label (z. B. „Step 3" für den
##     Action-Knoten bei mehreren `action_step`-Events). Leerer Hint
##     wird sauber ausgeblendet — keine Leerzeile.
##   * Saubere Darstellung, wenn der Controller kein Titel-Label
##     liefert: statt leerer zweiter Zeile wird der Rollenname groß
##     gezeigt, damit der Knoten nie wie „kaputt" aussieht.
##
## Designregeln (unverändert):
##   * Rein visuelle Kapsel: kleine PanelContainer mit zwei/drei
##     Labels, dezente Modulation je nach Zustand. Keine
##     Interaktion, keine Buttons, kein Signal nach außen.
##   * Zustandsfarben sind **Tönungen** (modulate), keine festen
##     Markenfarben. Das MVP bleibt zurückhaltend und dokumentiert
##     *keine* verbindliche Farbzusage als API.

class_name SmolitWorkflowNodeView

const _StateRef := preload("res://scripts/workflow_overlay/workflow_overlay_state.gd")

## Tönungen pro Zustand — bewusst leise. Werden auf `self.modulate`
## angewandt, damit die Panel-Basisfarbe aus dem Theme erhalten bleibt.
const _STATE_TINT: Dictionary = {
	_StateRef.NodeState.IDLE:       Color(1.0, 1.0, 1.0, 0.32),
	_StateRef.NodeState.PLANNED:    Color(1.0, 1.0, 1.0, 0.58),
	_StateRef.NodeState.ACTIVE:     Color(0.80, 0.88, 1.00, 1.00),
	_StateRef.NodeState.COMPLETED:  Color(0.72, 0.90, 0.75, 1.00),
	_StateRef.NodeState.FAILED:     Color(0.95, 0.65, 0.65, 1.00),
	_StateRef.NodeState.UNKNOWN:    Color(1.0, 1.0, 1.0, 0.55),
}

## Feste Größenangaben pro Darstellungsmodus. Werte sind bewusst
## konservativ — der Overlay bleibt klein und ruhig; der Unterschied
## zwischen den Modi ist deutlich genug für „geplant vs. laufend",
## aber nicht marktschreierisch.
const _MIN_SIZE_COLLAPSED: Vector2 = Vector2(84, 36)
const _MIN_SIZE_EXPANDED: Vector2  = Vector2(110, 50)

const _ROLE_FONT_SIZE_COLLAPSED: int = 9
const _ROLE_FONT_SIZE_EXPANDED: int  = 10
const _TITLE_FONT_SIZE_COLLAPSED: int = 11
const _TITLE_FONT_SIZE_EXPANDED: int  = 12
const _HINT_FONT_SIZE: int            = 9

var _role_label: Label = null
var _title_label: Label = null
var _hint_label: Label = null

var _current_display_mode: int = _StateRef.DisplayMode.COLLAPSED


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = _MIN_SIZE_COLLAPSED

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	add_child(vbox)

	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", _ROLE_FONT_SIZE_COLLAPSED)
	_role_label.modulate = Color(1, 1, 1, 0.55)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_role_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", _TITLE_FONT_SIZE_COLLAPSED)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_title_label)

	# Hint-Label wird nur sichtbar, wenn der Controller einen Hinweis
	# setzt (z. B. „Step 3"). Standardmäßig ausgeblendet, damit der
	# Knoten in Ruhe bleibt.
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", _HINT_FONT_SIZE)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.modulate = Color(1, 1, 1, 0.55)
	_hint_label.visible = false
	vbox.add_child(_hint_label)


## Hauptschnittstelle. Wird vom Controller aufgerufen, wenn sich
## Zustand, Label oder Darstellungsmodus ändern. Unbekannte
## Zustände werden auf eine ruhige Default-Tönung abgebildet —
## kein Crash, kein Rauschen.
##
## `title_text` darf leer sein. In dem Fall wird die zweite Zeile
## ausgeblendet und stattdessen die Rollen-Zeile etwas prominenter
## dargestellt — so wirkt ein Knoten ohne Label nicht „kaputt".
## `hint_text` ist optional und erscheint im EXPANDED-Modus unter
## dem Titel; im COLLAPSED-Modus bleibt der Hint versteckt.
func apply(role: int, state: int, title_text: String, display_mode: int, hint_text: String = "") -> void:
	if _role_label == null or _title_label == null or _hint_label == null:
		return

	_current_display_mode = display_mode
	_apply_display_mode(display_mode)

	# Rollenzeile immer in GROSSBUCHSTABEN für semantische Lesbarkeit.
	_role_label.text = _StateRef.role_name(role).to_upper()

	# Titel-Handling mit Fallback-Freundlichkeit.
	var has_title: bool = title_text != ""
	_title_label.text = title_text if has_title else ""
	_title_label.visible = has_title

	# Hint nur im EXPANDED-Modus und nur, wenn der Controller
	# tatsächlich etwas mitgibt — verhindert leere Zeilen und
	# flackernde Höhensprünge im COLLAPSED-Modus.
	var show_hint: bool = display_mode == _StateRef.DisplayMode.EXPANDED and hint_text != ""
	_hint_label.text = hint_text if show_hint else ""
	_hint_label.visible = show_hint

	# Tönung pro Zustand.
	var tint_variant: Variant = _STATE_TINT.get(state, null)
	if tint_variant is Color:
		modulate = tint_variant
	else:
		modulate = _STATE_TINT[_StateRef.NodeState.UNKNOWN]


func _apply_display_mode(mode: int) -> void:
	var min_size: Vector2 = _MIN_SIZE_EXPANDED \
		if mode == _StateRef.DisplayMode.EXPANDED \
		else _MIN_SIZE_COLLAPSED
	custom_minimum_size = min_size

	var role_size: int = _ROLE_FONT_SIZE_EXPANDED \
		if mode == _StateRef.DisplayMode.EXPANDED \
		else _ROLE_FONT_SIZE_COLLAPSED
	var title_size: int = _TITLE_FONT_SIZE_EXPANDED \
		if mode == _StateRef.DisplayMode.EXPANDED \
		else _TITLE_FONT_SIZE_COLLAPSED

	_role_label.add_theme_font_size_override("font_size", role_size)
	_title_label.add_theme_font_size_override("font_size", title_size)
