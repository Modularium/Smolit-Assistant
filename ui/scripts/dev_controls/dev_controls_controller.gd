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

const ENV_ENABLE: String = "SMOLIT_UI_DEV_CONTROLS"

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

## NodePaths zu den beiden UI-Zielen in `main.tscn`. Werden im
## `_ready` einmalig aufgelöst; fehlen sie (z. B. unter headless),
## bleibt das Panel still.
@export var avatar_path: NodePath = ^"../Avatar"
@export var workflow_overlay_path: NodePath = ^"../WorkflowOverlay"

var _avatar: Node = null
var _workflow_overlay: Node = null

var _theme_picker: OptionButton = null
var _profile_picker: OptionButton = null
var _intensity_slider: HSlider = null
var _intensity_value: Label = null
var _save_button: Button = null
var _save_status: Label = null
var _phase_buttons: Array = []


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

	_build_ui()
	_sync_from_live_appearance()

	print("[dev-controls] enabled — avatar+overlay preview hooks active")


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
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.3)
	root.add_child(sep)

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

	_select_by_id(_theme_picker, theme)
	_select_by_id(_profile_picker, profile)
	if _intensity_slider != null:
		_intensity_slider.set_value_no_signal(intensity)
		_intensity_value.text = "%.2f" % intensity


static func _select_by_id(picker: OptionButton, id: int) -> void:
	if picker == null:
		return
	for i in range(picker.item_count):
		if picker.get_item_id(i) == id:
			picker.select(i)
			return
	picker.select(0)


# --- Handlers -----------------------------------------------------------


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
	var theme_id := _theme_picker.get_selected_id() if _theme_picker != null else int(_AppearanceRef.DEFAULT_THEME)
	var profile_id := _profile_picker.get_selected_id() if _profile_picker != null else int(_AppearanceRef.DEFAULT_PROFILE)
	var intensity := float(_intensity_slider.value) if _intensity_slider != null else 1.0
	# Scale-Override lassen wir im MVP-Panel auf 1.0 — das Appearance-
	# Modul unterstützt es, ein UI-Schalter dafür wäre aber schon
	# Scope-Creep.
	var appearance := _AppearanceRef.make_appearance(
		theme_id, profile_id, Color(1, 1, 1, 1), intensity, 1.0,
	)
	_avatar.set_appearance(appearance)
	print("[dev-controls] avatar: theme=%s profile=%s intensity=%.2f" % [
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
