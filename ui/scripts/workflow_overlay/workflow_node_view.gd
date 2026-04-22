extends PanelContainer
## Workflow-Overlay — kleiner, read-only Knoten-Renderer.
##
## Jedes Instanz zeigt *eine* Station des Kurz-Flows (Trigger / Action /
## Result). Der Node-View kennt kein Graph-Framework, keine Layout-
## Algorithmen — er rendert nur das, was ihm der Controller über
## `apply()` mitteilt.
##
## Designregeln:
##   * Rein visuelle Kapsel: kleine PanelContainer mit einem Label,
##     dezente Modulation je nach Zustand. Keine Interaktion, keine
##     Buttons.
##   * Zustandsfarben sind **Tönungen** (modulate), keine festen
##     Markenfarben. Das MVP bleibt bewusst zurückhaltend und
##     dokumentiert *keine* verbindliche Farbzusage als API.
##   * Keine Eventhandler, keine Signale nach außen.
##
## Erwartete Szenenstruktur (wird vom Controller in Code aufgebaut,
## um Designrauschen in `workflow_overlay_root.tscn` klein zu halten):
##   PanelContainer (= self)
##   └── VBoxContainer
##       ├── Label (role, klein und dezent)
##       └── Label (main label, optional)

class_name SmolitWorkflowNodeView

const _StateRef := preload("res://scripts/workflow_overlay/workflow_overlay_state.gd")

## Tönungen pro Zustand — bewusst leise. Werden auf `self.modulate`
## angewandt, damit die Panel-Basisfarbe aus dem Theme erhalten bleibt.
const _STATE_TINT: Dictionary = {
	_StateRef.NodeState.IDLE:       Color(1.0, 1.0, 1.0, 0.35),
	_StateRef.NodeState.PLANNED:    Color(1.0, 1.0, 1.0, 0.55),
	_StateRef.NodeState.ACTIVE:     Color(0.80, 0.88, 1.00, 1.00),
	_StateRef.NodeState.COMPLETED:  Color(0.70, 0.90, 0.75, 1.00),
	_StateRef.NodeState.FAILED:     Color(0.95, 0.65, 0.65, 1.00),
	_StateRef.NodeState.UNKNOWN:    Color(1.0, 1.0, 1.0, 0.50),
}

var _role_label: Label = null
var _title_label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(84, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	add_child(vbox)

	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", 9)
	_role_label.modulate = Color(1, 1, 1, 0.55)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_role_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_title_label)


## Hauptschnittstelle. Wird vom Controller aufgerufen, wenn sich
## Zustand oder Label ändern. Unbekannte Zustände werden auf eine
## ruhige Default-Tönung abgebildet — kein Crash, kein Rauschen.
func apply(role: int, state: int, label_text: String) -> void:
	if _role_label == null or _title_label == null:
		# Noch nicht im SceneTree → stille Ignoranz; der Controller
		# ruft `apply()` nach `_ready()` erneut auf.
		return
	_role_label.text = _StateRef.role_name(role).to_upper()
	_title_label.text = label_text
	_title_label.visible = label_text != ""
	var tint_variant: Variant = _STATE_TINT.get(state, null)
	if tint_variant is Color:
		modulate = tint_variant
	else:
		modulate = _STATE_TINT[_StateRef.NodeState.UNKNOWN]
