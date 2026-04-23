extends PanelContainer
## Dev-/MVP-Steuerung für die neuen UI-Linien (Workflow-Overlay und
## Avatar-Appearance-Phase-A).
##
## Ausdrücklich kein Settings-System und kein User-Customization-
## Panel. Das Panel ist eine **kleine Hilfsschicht für Testbarkeit
## und Vorschau**:
##
##   * gated per `SMOLIT_UI_DEV_CONTROLS=1` — ohne Env-Opt-in ist das
##     Panel versteckt und stumm (keine Log-Ausgabe, kein Input-Steal),
##     bestehende UI verhält sich wie vor diesem PR;
##   * keine Persistenz — Änderungen gelten nur für die laufende
##     Session; Default-Werte kommen aus Env / Appearance-Modul;
##   * keine Core-/IPC-Kommunikation — das Panel spricht nur lokal
##     mit den beiden UI-Controllern (Avatar, Workflow-Overlay);
##   * keine neuen Action-Events — Workflow-Preview setzt den
##     internen Flow-Zustand direkt über
##     `workflow_overlay_controller.preview_phase()`, ohne EventBus-
##     Injection.
##
## Scope dieses MVP-Panels:
##
##   * Avatar-Appearance: Theme / Profile / Intensity live
##     umschalten, direkt an `avatar_controller.set_appearance()`
##     weiterreichen. Identity bleibt `smolit_salamander`.
##   * Workflow-Overlay: sechs Preview-Knöpfe (Hidden / Planned /
##     Active / Completed / Failed / Cancelled), die die
##     Darstellung durchschalten.
##
## Explizit **nicht** im Scope:
##
##   * Kein Avatar-Upload, keine Template-Auswahl, kein Character-
##     Creator.
##   * Kein Workflow-Editor, kein Action-Auslöser, kein Debugger.
##   * Kein Mehrfenstersystem, kein neuer Presence-Mode.
##   * Kein Speichern / Laden auf Disk.

const _AppearanceRef := preload("res://scripts/avatar/avatar_appearance.gd")
const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const _VisualActionModeRef := preload("res://scripts/presence/visual_action_mode.gd")
const _ExpressionRef := preload("res://scripts/avatar/avatar_expression.gd")

const ENV_ENABLE: String = "SMOLIT_UI_DEV_CONTROLS"

## Kleiner kuratierter Identity-Selector (Phase-B-Spike). Reihenfolge
## folgt `avatar_identity.gd::all_ids` — Smolit bleibt als erste
## Option sichtbarer Default, alternative Figuren kommen danach.
const _IDENTITY_OPTIONS: Array = [
	{"id": _IdentityRef.Identity.SMOLIT_SALAMANDER, "label": "Smolit Salamander"},
	{"id": _IdentityRef.Identity.ROBOT_HEAD,        "label": "Robot Head"},
	{"id": _IdentityRef.Identity.HUMANOID_HEAD,     "label": "Humanoid Head"},
	{"id": _IdentityRef.Identity.ORB,               "label": "Orb"},
]

const _THEME_OPTIONS: Array = [
	{"id": _AppearanceRef.ThemePreset.DEFAULT, "label": "Default"},
	{"id": _AppearanceRef.ThemePreset.SOFT,    "label": "Soft"},
	{"id": _AppearanceRef.ThemePreset.TECH,    "label": "Tech"},
	{"id": _AppearanceRef.ThemePreset.MINIMAL, "label": "Minimal"},
]

const _PROFILE_OPTIONS: Array = [
	{"id": _AppearanceRef.BehaviorProfile.CALM,     "label": "Calm"},
	{"id": _AppearanceRef.BehaviorProfile.LIVELY,   "label": "Lively"},
	{"id": _AppearanceRef.BehaviorProfile.RESERVED, "label": "Reserved"},
]

const _PHASE_PREVIEWS: Array = [
	"hidden", "planned", "active", "completed", "failed", "cancelled",
]

## Visual-Action-Mode-Picker (Phase 3.3 MVP). Reihenfolge folgt der
## Produktachse aus `docs/presence_desktop_interaction.md §7`
## (aufsteigende UI-Sichtbarkeit). Kein Smolit-First hier — das ist
## kein Identity-Selektor, sondern eine UI-Intensitäts-Achse.
const _VISUAL_ACTION_MODE_OPTIONS: Array = [
	{"id": _VisualActionModeRef.Mode.NONE,             "label": "None"},
	{"id": _VisualActionModeRef.Mode.MINIMAL_FEEDBACK, "label": "Minimal feedback"},
	{"id": _VisualActionModeRef.Mode.GUIDED_MOVEMENT,  "label": "Guided movement"},
	{"id": _VisualActionModeRef.Mode.FULL_THEATRICAL,  "label": "Full theatrical"},
]

## NodePaths zu den beiden UI-Zielen in `main.tscn`. Werden im
## `_ready` einmalig aufgelöst; fehlen sie (z. B. unter headless),
## bleibt das Panel still.
@export var avatar_path: NodePath = ^"../Avatar"
@export var workflow_overlay_path: NodePath = ^"../WorkflowOverlay"
@export var main_controller_path: NodePath = ^".."
## PR 16: optionaler Zugriff auf das Workflow-Visibility-Panel für den
## Toggle. Fehlt der Knoten (älterer Build), bleibt der Toggle-Button
## stumm — keine Crash-Gefahr.
@export var workflow_visibility_path: NodePath = ^"../WorkflowVisibilityPanel"

var _avatar: Node = null
var _workflow_overlay: Node = null
var _main_controller: Node = null
var _workflow_visibility: Node = null
var _workflow_visibility_toggle: CheckBox = null

var _identity_picker: OptionButton = null
var _theme_picker: OptionButton = null
var _profile_picker: OptionButton = null
var _intensity_slider: HSlider = null
var _intensity_value: Label = null
var _save_button: Button = null
var _save_status: Label = null
var _phase_buttons: Array = []
var _visual_action_mode_picker: OptionButton = null
var _visual_action_mode_save_button: Button = null
var _visual_action_mode_save_status: Label = null


static func is_enabled() -> bool:
	var raw := OS.get_environment(ENV_ENABLE).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


func _ready() -> void:
	# Ohne Opt-in: Panel schlicht verbergen und nichts verdrahten.
	# Keine Log-Zeile, kein Side-Effect.
	if not is_enabled():
		visible = false
		return

	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = true

	_avatar = get_node_or_null(avatar_path)
	_workflow_overlay = get_node_or_null(workflow_overlay_path)
	_main_controller = get_node_or_null(main_controller_path)
	_workflow_visibility = get_node_or_null(workflow_visibility_path)

	_build_ui()
	_sync_from_live_appearance()
	_sync_from_live_visual_action_mode()
	_sync_from_live_workflow_visibility()

	print("[dev-controls] enabled — avatar+overlay+visual-action preview hooks active")


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# Header
	var header := Label.new()
	header.text = "Dev Controls (MVP)"
	header.modulate = Color(1, 1, 1, 0.75)
	header.add_theme_font_size_override("font_size", 11)
	root.add_child(header)

	# Avatar section
	root.add_child(_build_avatar_section())

	# Separator
	var sep_expr := HSeparator.new()
	sep_expr.modulate = Color(1, 1, 1, 0.3)
	root.add_child(sep_expr)

	# Expression preview section (PR 15).
	root.add_child(_build_expression_section())

	# Separator
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.3)
	root.add_child(sep)

	# Visual Action Mode section
	root.add_child(_build_visual_action_mode_section())

	# Separator
	var sep_wf := HSeparator.new()
	sep_wf.modulate = Color(1, 1, 1, 0.3)
	root.add_child(sep_wf)

	# Workflow Visibility toggle (PR 16).
	root.add_child(_build_workflow_visibility_section())

	# Separator
	var sep_appr := HSeparator.new()
	sep_appr.modulate = Color(1, 1, 1, 0.3)
	root.add_child(sep_appr)

	# Approval demo trigger (PR 17).
	root.add_child(_build_approval_demo_section())

	# Separator
	var sep2 := HSeparator.new()
	sep2.modulate = Color(1, 1, 1, 0.3)
	root.add_child(sep2)

	# Overlay preview section
	root.add_child(_build_overlay_section())


func _build_avatar_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Avatar appearance"
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(1, 1, 1, 0.6)
	box.add_child(title)

	# Identity-Row (Phase B). Kleiner kuratierter Selector, bewusst als
	# erste Zeile der Avatar-Sektion, weil Identity den gröbsten Effekt
	# hat — Theme/Profile/Intensity sind Feinjustierung darüber.
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 6)
	box.add_child(identity_row)
	var identity_label := Label.new()
	identity_label.text = "Identity"
	identity_label.custom_minimum_size = Vector2(64, 0)
	identity_row.add_child(identity_label)
	_identity_picker = OptionButton.new()
	for option in _IDENTITY_OPTIONS:
		_identity_picker.add_item(str(option["label"]), int(option["id"]))
	_identity_picker.item_selected.connect(_on_identity_selected)
	identity_row.add_child(_identity_picker)

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 6)
	box.add_child(theme_row)
	var theme_label := Label.new()
	theme_label.text = "Theme"
	theme_label.custom_minimum_size = Vector2(64, 0)
	theme_row.add_child(theme_label)
	_theme_picker = OptionButton.new()
	for option in _THEME_OPTIONS:
		_theme_picker.add_item(str(option["label"]), int(option["id"]))
	_theme_picker.item_selected.connect(_on_theme_selected)
	theme_row.add_child(_theme_picker)

	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 6)
	box.add_child(profile_row)
	var profile_label := Label.new()
	profile_label.text = "Profile"
	profile_label.custom_minimum_size = Vector2(64, 0)
	profile_row.add_child(profile_label)
	_profile_picker = OptionButton.new()
	for option in _PROFILE_OPTIONS:
		_profile_picker.add_item(str(option["label"]), int(option["id"]))
	_profile_picker.item_selected.connect(_on_profile_selected)
	profile_row.add_child(_profile_picker)

	var intensity_row := HBoxContainer.new()
	intensity_row.add_theme_constant_override("separation", 6)
	box.add_child(intensity_row)
	var intensity_label := Label.new()
	intensity_label.text = "Intensity"
	intensity_label.custom_minimum_size = Vector2(64, 0)
	intensity_row.add_child(intensity_label)
	_intensity_slider = HSlider.new()
	_intensity_slider.min_value = _AppearanceRef.INTENSITY_MIN
	_intensity_slider.max_value = _AppearanceRef.INTENSITY_MAX
	_intensity_slider.step = 0.05
	_intensity_slider.value = 1.0
	_intensity_slider.custom_minimum_size = Vector2(120, 0)
	_intensity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intensity_slider.value_changed.connect(_on_intensity_changed)
	intensity_row.add_child(_intensity_slider)
	_intensity_value = Label.new()
	_intensity_value.text = "1.00"
	_intensity_value.custom_minimum_size = Vector2(40, 0)
	_intensity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intensity_row.add_child(_intensity_value)

	# Persist-Row: ein einziger "Save as default"-Button. Bewusst kein
	# Save/Reset/Profile-Menü — das wäre schon Scope-Creep im Sinne der
	# PR-Leitplanken. Persistiert werden nur die drei Appearance-Felder
	# in `user://smolit_ui.cfg` (Sektion `[avatar_appearance]`).
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	box.add_child(save_row)
	_save_button = Button.new()
	_save_button.text = "Save as default"
	_save_button.tooltip_text = "Persist current theme / profile / intensity as the local UI default (user://smolit_ui.cfg)."
	_save_button.pressed.connect(_on_save_pressed)
	save_row.add_child(_save_button)
	_save_status = Label.new()
	_save_status.text = ""
	_save_status.modulate = Color(1, 1, 1, 0.55)
	_save_status.add_theme_font_size_override("font_size", 9)
	save_row.add_child(_save_status)

	return box


## Visual Action Mode (Phase 3.3 MVP). Eine Zeile mit OptionButton +
## kleinem "Save as default"-Button, symmetrisch zur Appearance-
## Sektion. Bewusst ohne Advanced-Slider: die vier Produktstufen sind
## diskret, nicht kontinuierlich.
func _build_visual_action_mode_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Visual action mode"
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(1, 1, 1, 0.6)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var label := Label.new()
	label.text = "Mode"
	label.custom_minimum_size = Vector2(64, 0)
	row.add_child(label)
	_visual_action_mode_picker = OptionButton.new()
	for option in _VISUAL_ACTION_MODE_OPTIONS:
		_visual_action_mode_picker.add_item(str(option["label"]), int(option["id"]))
	_visual_action_mode_picker.item_selected.connect(_on_visual_action_mode_selected)
	row.add_child(_visual_action_mode_picker)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	box.add_child(save_row)
	_visual_action_mode_save_button = Button.new()
	_visual_action_mode_save_button.text = "Save as default"
	_visual_action_mode_save_button.tooltip_text = "Persist the current visual action mode locally (user://smolit_ui.cfg, section [presence])."
	_visual_action_mode_save_button.pressed.connect(_on_visual_action_mode_save_pressed)
	save_row.add_child(_visual_action_mode_save_button)
	_visual_action_mode_save_status = Label.new()
	_visual_action_mode_save_status.text = ""
	_visual_action_mode_save_status.modulate = Color(1, 1, 1, 0.55)
	_visual_action_mode_save_status.add_theme_font_size_override("font_size", 9)
	save_row.add_child(_visual_action_mode_save_status)

	var hint := Label.new()
	hint.text = "MVP staging only: banner/overlay visibility — no real desktop path."
	hint.add_theme_font_size_override("font_size", 9)
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	return box


func _build_overlay_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Workflow overlay preview"
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(1, 1, 1, 0.6)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)

	_phase_buttons.clear()
	for phase_name in _PHASE_PREVIEWS:
		var btn := Button.new()
		btn.text = str(phase_name).capitalize()
		btn.pressed.connect(_on_phase_preview_pressed.bind(phase_name))
		row.add_child(btn)
		_phase_buttons.append(btn)

	var hint := Label.new()
	hint.text = "Preview is local to this overlay; no Core events are sent."
	hint.add_theme_font_size_override("font_size", 9)
	hint.modulate = Color(1, 1, 1, 0.45)
	box.add_child(hint)

	return box


# --- Live-Sync des Pickers mit dem Avatar -------------------------------


func _sync_from_live_appearance() -> void:
	if _avatar == null or not _avatar.has_method("get_appearance"):
		return
	var current: Dictionary = _avatar.get_appearance()
	var theme := int(current.get("theme", _AppearanceRef.DEFAULT_THEME))
	var profile := int(current.get("profile", _AppearanceRef.DEFAULT_PROFILE))
	var overrides: Dictionary = current.get("overrides", {})
	var intensity := float(overrides.get("intensity", 1.0))
	var identity_id: int = _IdentityRef.identity_from_string(
		String(current.get("identity", "smolit_salamander")),
	)

	_select_by_id(_identity_picker, identity_id)
	_select_by_id(_theme_picker, theme)
	_select_by_id(_profile_picker, profile)
	if _intensity_slider != null:
		_intensity_slider.set_value_no_signal(intensity)
		_intensity_value.text = "%.2f" % intensity


func _sync_from_live_visual_action_mode() -> void:
	if _main_controller == null or not _main_controller.has_method("visual_action_mode"):
		return
	var current: int = int(_main_controller.call("visual_action_mode"))
	_select_by_id(_visual_action_mode_picker, current)


static func _select_by_id(picker: OptionButton, id: int) -> void:
	if picker == null:
		return
	for i in range(picker.item_count):
		if picker.get_item_id(i) == id:
			picker.select(i)
			return
	picker.select(0)


# --- Handlers -----------------------------------------------------------


func _on_identity_selected(_index: int) -> void:
	_clear_save_status()
	_apply_current_appearance()


func _on_theme_selected(_index: int) -> void:
	_clear_save_status()
	_apply_current_appearance()


func _on_profile_selected(_index: int) -> void:
	_clear_save_status()
	_apply_current_appearance()


func _on_intensity_changed(value: float) -> void:
	if _intensity_value != null:
		_intensity_value.text = "%.2f" % value
	_clear_save_status()
	_apply_current_appearance()


func _clear_save_status() -> void:
	if _save_status == null:
		return
	_save_status.text = ""


func _apply_current_appearance() -> void:
	if _avatar == null or not _avatar.has_method("set_appearance"):
		return
	var identity_id := _identity_picker.get_selected_id() if _identity_picker != null else int(_IdentityRef.DEFAULT)
	var theme_id := _theme_picker.get_selected_id() if _theme_picker != null else int(_AppearanceRef.DEFAULT_THEME)
	var profile_id := _profile_picker.get_selected_id() if _profile_picker != null else int(_AppearanceRef.DEFAULT_PROFILE)
	var intensity := float(_intensity_slider.value) if _intensity_slider != null else 1.0
	# Scale-Override lassen wir im MVP-Panel auf 1.0 — das Appearance-
	# Modul unterstützt es, ein UI-Schalter dafür wäre aber schon
	# Scope-Creep.
	var appearance := _AppearanceRef.make_appearance(
		theme_id, profile_id, Color(1, 1, 1, 1), intensity, 1.0,
	)
	# Identity wird im set_appearance-Hook des Avatar-Controllers
	# kuratiert und bei Unbekanntem auf Smolit geklemmt.
	appearance["identity"] = _IdentityRef.identity_name(identity_id)
	_avatar.set_appearance(appearance)
	print("[dev-controls] avatar: identity=%s theme=%s profile=%s intensity=%.2f" % [
		_IdentityRef.identity_name(identity_id),
		_AppearanceRef.theme_name(theme_id),
		_AppearanceRef.profile_name(profile_id),
		intensity,
	])


func _on_save_pressed() -> void:
	if _avatar == null or not _avatar.has_method("save_current_preferences"):
		_show_save_status("unavailable", Color(1, 0.6, 0.6, 0.8))
		return
	# `_apply_current_appearance` wurde bei jeder Änderung schon auf den
	# Avatar gepusht; wir speichern daher einfach den aktuellen
	# Avatar-Zustand. Kein paralleler Persistenz-Zustand im Panel.
	var err: int = int(_avatar.call("save_current_preferences"))
	if err == OK:
		_show_save_status("saved", Color(0.7, 1, 0.7, 0.8))
		print("[dev-controls] preferences saved (user://smolit_ui.cfg)")
	else:
		_show_save_status("error %d" % err, Color(1, 0.6, 0.6, 0.8))
		push_warning("[dev-controls] save_current_preferences failed with error %d" % err)


func _show_save_status(text: String, color: Color) -> void:
	if _save_status == null:
		return
	_save_status.text = text
	_save_status.modulate = color


func _on_phase_preview_pressed(phase_name: String) -> void:
	if _workflow_overlay == null or not _workflow_overlay.has_method("preview_phase"):
		return
	_workflow_overlay.preview_phase(phase_name)
	print("[dev-controls] overlay preview: %s" % phase_name)


func _on_visual_action_mode_selected(_index: int) -> void:
	_clear_visual_action_mode_save_status()
	if _main_controller == null or not _main_controller.has_method("set_visual_action_mode"):
		return
	if _visual_action_mode_picker == null:
		return
	var mode_id: int = _visual_action_mode_picker.get_selected_id()
	_main_controller.call("set_visual_action_mode", mode_id)
	print("[dev-controls] visual action mode = %s" % _VisualActionModeRef.name_of(mode_id))


func _on_visual_action_mode_save_pressed() -> void:
	if _main_controller == null or not _main_controller.has_method("save_visual_action_preference"):
		_show_visual_action_mode_save_status("unavailable", Color(1, 0.6, 0.6, 0.8))
		return
	var err: int = int(_main_controller.call("save_visual_action_preference"))
	if err == OK:
		_show_visual_action_mode_save_status("saved", Color(0.7, 1, 0.7, 0.8))
		print("[dev-controls] visual-action-mode preference saved (user://smolit_ui.cfg)")
	else:
		_show_visual_action_mode_save_status("error %d" % err, Color(1, 0.6, 0.6, 0.8))
		push_warning("[dev-controls] save_visual_action_preference failed with error %d" % err)


func _clear_visual_action_mode_save_status() -> void:
	if _visual_action_mode_save_status == null:
		return
	_visual_action_mode_save_status.text = ""


func _show_visual_action_mode_save_status(text: String, color: Color) -> void:
	if _visual_action_mode_save_status == null:
		return
	_visual_action_mode_save_status.text = text
	_visual_action_mode_save_status.modulate = color


# --- PR 15: Behavioral Expression Layer Preview ---------------------------
#
# Dev-Only-Vorschau, identisch zur anderen MVP-Hilfschicht: ein Klick
# setzt die Expression live auf dem Avatar-Controller, kein Auto-Save,
# keine Persistenz. Nach dem Hold-Timer (für `curious` / `pleased` /
# `error_soft`) fällt der Cue über `_refresh_expression_from_state()`
# wieder auf den State-Default zurück — genau wie bei echten Events
# aus dem EventBus.


func _build_expression_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Avatar expression (preview)"
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(1, 1, 1, 0.6)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)

	for kind in _ExpressionRef.all_kinds():
		var btn := Button.new()
		btn.text = _ExpressionRef.name_of(kind)
		btn.tooltip_text = "Preview expression: %s" % _ExpressionRef.name_of(kind)
		btn.pressed.connect(_on_expression_preview_pressed.bind(kind))
		row.add_child(btn)

	var hint := Label.new()
	hint.text = "Preview only; no save. Transient cues fall back after hold."
	hint.add_theme_font_size_override("font_size", 9)
	hint.modulate = Color(1, 1, 1, 0.4)
	box.add_child(hint)

	return box


func _on_expression_preview_pressed(kind: int) -> void:
	if _avatar == null:
		return
	if not _avatar.has_method("preview_expression"):
		# Älterer Build ohne PR 15: lautlos ignorieren, wie wir es bei
		# den anderen Preview-Hooks auch machen.
		return
	_avatar.call("preview_expression", kind)


# --- PR 16: Workflow Visibility Overlay toggle ---------------------------
#
# Einzelner CheckBox-Toggle (Session-only). Wenn das Panel fehlt
# (z. B. älterer Build), bleibt die Zeile still — gleiches Muster wie
# beim Expression-Preview.


func _build_workflow_visibility_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Workflow visibility"
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(1, 1, 1, 0.6)
	box.add_child(title)

	_workflow_visibility_toggle = CheckBox.new()
	_workflow_visibility_toggle.text = "Show workflow overlay"
	_workflow_visibility_toggle.tooltip_text = "Session-only toggle. Env default is SMOLIT_WORKFLOW_OVERLAY=0."
	_workflow_visibility_toggle.toggled.connect(_on_workflow_visibility_toggled)
	box.add_child(_workflow_visibility_toggle)

	var hint := Label.new()
	hint.text = "No save. Events keep flowing even when hidden."
	hint.add_theme_font_size_override("font_size", 9)
	hint.modulate = Color(1, 1, 1, 0.4)
	box.add_child(hint)

	return box


func _sync_from_live_workflow_visibility() -> void:
	if _workflow_visibility == null or _workflow_visibility_toggle == null:
		return
	if not _workflow_visibility.has_method("is_overlay_visible"):
		_workflow_visibility_toggle.disabled = true
		return
	_workflow_visibility_toggle.set_pressed_no_signal(
		bool(_workflow_visibility.call("is_overlay_visible"))
	)


func _on_workflow_visibility_toggled(pressed: bool) -> void:
	if _workflow_visibility == null:
		return
	if not _workflow_visibility.has_method("set_overlay_visible"):
		return
	_workflow_visibility.call("set_overlay_visible", pressed)


# --- PR 17: Approval UX demo trigger -----------------------------------
#
# Ein Button, der ein harmloses Demo-Approval am Core auslöst. Kein
# Systemaufruf, kein AdminBot, kein Shell. Der Core antwortet mit
# `approval_requested` → die Approval-Card rendert. Nach Approve/Deny
# resolvet der Core ohne Side-Effect.


func _build_approval_demo_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Approval demo (harmless)"
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(1, 1, 1, 0.6)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)

	for risk in ["low", "medium", "high"]:
		var btn := Button.new()
		btn.text = "Demo %s" % risk
		btn.tooltip_text = "Request a harmless demo approval at risk=%s." % risk
		btn.pressed.connect(_on_approval_demo_pressed.bind(risk))
		row.add_child(btn)

	var hint := Label.new()
	hint.text = "Core runs no action. UX only."
	hint.add_theme_font_size_override("font_size", 9)
	hint.modulate = Color(1, 1, 1, 0.4)
	box.add_child(hint)

	return box


func _on_approval_demo_pressed(risk: String) -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null:
		push_warning("[dev-controls] IpcClient autoload missing; cannot fire demo approval")
		return
	if not client.has_method("request_approval_demo"):
		push_warning("[dev-controls] IpcClient missing request_approval_demo (older build)")
		return
	client.call("request_approval_demo",
		"Demo approval",
		"Harmless UX demo. The core will not run any action after this decision.",
		risk)
