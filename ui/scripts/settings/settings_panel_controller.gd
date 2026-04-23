extends PanelContainer
## Settings-Shell (Phase 8c PR 3) — Controller.
##
## Eigenständiger, additiver UI-Substate im Expanded-Window. Der
## Controller ist ausdrücklich eine **Shell**: er rendert die
## kuratierten Bereiche aus `SettingsSections` read-only, öffnet
## und schließt sich auf `open()` / `close()`, und meldet per
## Signal `close_requested` zurück, wenn der Back-Knopf gedrückt
## wurde. Er kennt weder IPC-Schreibaktionen noch Provider-Logik.
##
## Rolle an der Main-Scene:
##   * Sitzt als eigener Knoten in `main.tscn` (versteckt per Default).
##   * Wird vom Main-Controller geöffnet, wenn Presence = Expanded und
##     der Settings-Button geklickt wurde.
##   * Erhält Status-Updates über `apply_status(payload)` und UI-
##     Extras (Visual-Action-Mode-Name, Presence-Mode-Name, Connected-
##     Bool) über `apply_extras(dict)`.
##
## Nicht-Ziele dieser Datei:
##   * Keine Provider-Entscheidungen oder Secrets in der UI.
##   * Keine Umschaltung zwischen Docked/Expanded/Action — das bleibt
##     beim Presence-Controller; Settings ist ein Substate von Expanded.
##
## Seit PR 5 schmale, **kuratierte** Schreibpfade für
## `llamafile_local`-Einstellungen. Die Editor-Zeilen (Enabled / Mode /
## Idle-Timeout / Binary-Pfad) sitzen direkt unter dem Read-only
## Text-Provider-Readout. Die UI hält keine zweite Wahrheit: alle
## Eingaben gehen als `settings_set_llamafile_config`-Nachricht an den
## Core; der Core antwortet mit einem frischen `status`-Envelope, und
## der Controller synchronisiert seine Widgets beim nächsten
## `apply_status`-Tick. Die Probe-Aktion (`settings_probe_llamafile`)
## ist Side-Effect-frei und landet im `settings_probe_result`-Signal.

const _SectionsRef := preload("res://scripts/settings/settings_sections.gd")

## Der Main-Controller hört diesen Signal-Pfad, um zur Haupt-Ansicht
## zurückzukehren. Wir synthetisieren keinen eigenen Presence-Mode-
## Wechsel — der Main-Controller bleibt Herr über die Sichtbarkeit.
signal close_requested

var _last_status: Dictionary = {}
var _last_extras: Dictionary = {}

var _title_label: Label = null
var _back_button: Button = null
var _content_vbox: VBoxContainer = null

## Schwacher Cache: wenn `apply_status` / `apply_extras` aufgerufen
## wird, ehe der Scene-Tree fertig ist, merken wir uns die Eingabe
## und rendern erst in `_ready()`.
var _pending_render: bool = false

## Single-Shot-Anschluss ans EventBus — verhindert mehrfaches Binden,
## wenn `_ensure_skeleton` mehr als einmal aufgerufen wird (z. B.
## durch `_ready` und einen vorgezogenen `open_panel`).
var _probe_signal_bound: bool = false

## PR 5 — Editor-Widgets für `llamafile_local`. Werden einmalig im
## `_render_sections()` aufgebaut und dort neu erzeugt, wenn sich das
## Layout ändert (kein separater Scene-Knoten, um die bestehende
## Additiv-Linie nicht aufzubrechen). Zustände werden bei jedem
## `apply_status` mit dem Core-Stand resynchronisiert — der Editor
## ist **nicht** die Wahrheit, der Core ist.
var _llamafile_enabled_check: CheckBox = null
var _llamafile_mode_picker: OptionButton = null
var _llamafile_idle_spinbox: SpinBox = null
var _llamafile_path_edit: LineEdit = null
var _llamafile_apply_button: Button = null
var _llamafile_probe_button: Button = null
var _llamafile_apply_status_label: Label = null
var _llamafile_probe_status_label: Label = null

## Verhindert, dass Sync-Writes der Editor-Widgets beim Rendering eine
## Cascade aus Change-Handlern auslösen.
var _syncing_llamafile_widgets: bool = false

const _LLAMAFILE_MODE_OPTIONS: Array = [
	{"id": 0, "value": "on_demand", "label": "On demand"},
	{"id": 1, "value": "standby", "label": "Standby"},
]

## Tag-basierte Farbgebung der Probe-Ergebnisse. Nur kuratierte Tags —
## unbekannte Klassen landen in `_neutral`.
const _PROBE_CLASS_COLORS: Dictionary = {
	"ok": Color(0.55, 0.85, 0.6, 1.0),
	"not_in_chain": Color(1, 1, 1, 0.55),
	"disabled": Color(0.85, 0.75, 0.4, 1.0),
	"not_configured": Color(0.85, 0.75, 0.4, 1.0),
	"path_missing": Color(0.9, 0.45, 0.45, 1.0),
	"path_not_file": Color(0.9, 0.45, 0.45, 1.0),
	"path_not_executable": Color(0.9, 0.45, 0.45, 1.0),
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# `_ensure_skeleton` baut das Skelett idempotent und bindet das
	# Probe-Signal an den EventBus (defensiver Runtime-Lookup — kein
	# statischer Identifier, damit das Script auch in SceneTree-
	# Kontexten ohne registrierten Autoload parsen kann).
	_ensure_skeleton()
	if _pending_render:
		_render_sections()
		_pending_render = false


## Öffnet das Panel. Erwartet, dass der Caller die Haupt-Inhalte
## (Dock-Panel, Compact-Input) bereits ausgeblendet hat — die Shell
## mischt sich bewusst nicht in die Presence-/Hauptlayout-Logik ein.
func open_panel() -> void:
	visible = true
	_ensure_skeleton()
	_render_sections()


func close_panel() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Übernimmt den letzten bekannten StatusPayload aus dem Core.
## Nicht-Dictionary-Eingaben werden ignoriert — das Panel bleibt
## rendering-fähig, zeigt dann aber nur Dash-Platzhalter.
func apply_status(payload: Variant) -> void:
	if typeof(payload) == TYPE_DICTIONARY:
		_last_status = payload
	else:
		_last_status = {}
	if visible:
		_ensure_skeleton()
		_render_sections()
	elif _content_vbox == null:
		_pending_render = true


## UI-Extras aus dem Main-Controller (Visual-Action-Mode-Name,
## Presence-Mode-Name, Connected-Flag). Werden bei jedem Open
## neu abgefragt, dürfen aber auch auf Signal-Basis nachgereicht
## werden.
func apply_extras(extras: Variant) -> void:
	if typeof(extras) == TYPE_DICTIONARY:
		_last_extras = extras
	else:
		_last_extras = {}
	if visible:
		_ensure_skeleton()
		_render_sections()
	elif _content_vbox == null:
		_pending_render = true


## Snapshot für Smoke-Tests — spiegelt den zuletzt gerenderten
## Zustand in einer stabilen Form. Keine Tree-Introspektion nötig.
func current_snapshot() -> Dictionary:
	return {
		"visible": visible,
		"sections": _slug_list(),
		"status_keys": _last_status.keys(),
		"extras_keys": _last_extras.keys(),
	}


## Snapshot des Llamafile-Editors für Smoke-Tests (PR 5). Trägt
## ausschließlich den UI-Widget-Stand, nicht den Core-Stand — so
## lässt sich die Sync-Richtung Core → UI deterministisch prüfen.
func llamafile_editor_snapshot() -> Dictionary:
	var built := _llamafile_enabled_check != null
	if not built:
		return {
			"built": false,
			"enabled": false,
			"mode": "",
			"idle_timeout_seconds": 0,
			"path": "",
			"apply_status": "",
			"probe_status": "",
		}
	var mode_id := _llamafile_mode_picker.get_selected_id() if _llamafile_mode_picker != null else -1
	var mode_value := ""
	for option in _LLAMAFILE_MODE_OPTIONS:
		if int(option["id"]) == mode_id:
			mode_value = String(option["value"])
			break
	return {
		"built": true,
		"enabled": _llamafile_enabled_check.button_pressed,
		"mode": mode_value,
		"idle_timeout_seconds": int(_llamafile_idle_spinbox.value) if _llamafile_idle_spinbox != null else 0,
		"path": _llamafile_path_edit.text if _llamafile_path_edit != null else "",
		"apply_status": _llamafile_apply_status_label.text if _llamafile_apply_status_label != null else "",
		"probe_status": _llamafile_probe_status_label.text if _llamafile_probe_status_label != null else "",
	}


## Test-Hook: simuliert einen eingehenden `settings_probe_result`-
## Envelope, ohne den EventBus-Autoload zu nutzen. Die echte
## IPC-Integration läuft im Core-Test — hier prüft der UI-Smoke nur,
## dass Renderer + Tint deterministisch auf strukturierte Payloads
## reagieren.
func inject_probe_result_for_test(payload: Dictionary) -> void:
	_on_settings_probe_result_received(payload)


func _slug_list() -> Array:
	var out: Array = []
	for section in _SectionsRef.all_sections():
		out.append(_SectionsRef.slug_for(section))
	return out


# --- UI-Aufbau ----------------------------------------------------------


## Idempotenter Bootstrap. `_ready()` fires unter bestimmten Godot-
## Setups (z. B. `SceneTree`-Smoke) erst im nächsten Frame — `open_panel`
## oder `apply_status` dürfen aber sofort nach `add_child` aufgerufen
## werden. Dieser Helfer baut das Skelett bei Bedarf nach und sorgt
## dafür, dass `_content_vbox` garantiert verfügbar ist.
func _ensure_skeleton() -> void:
	if _content_vbox != null:
		return
	_build_skeleton()
	# Probe-Signal einmalig abonnieren, falls noch nicht geschehen. Das
	# Einbinden ist idempotent — wir markieren den Anschluss in einem
	# Flag. Runtime-Lookup nur, wenn der Knoten bereits im Tree lebt:
	# `get_node_or_null` weist sonst absolute Pfade mit einem Error
	# zurück, auch wenn der Smoketest den Panel-Knoten bereits in
	# seinem `root` hängen hat (Godot 4: absolute Pfade erfordern
	# `is_inside_tree()`).
	if not _probe_signal_bound and is_inside_tree():
		var bus: Node = get_node_or_null("/root/EventBus")
		if bus != null and bus.has_signal("settings_probe_result_received"):
			bus.settings_probe_result_received.connect(
				_on_settings_probe_result_received,
			)
			_probe_signal_bound = true


func _build_skeleton() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_back_button = Button.new()
	_back_button.text = "← Back"
	_back_button.tooltip_text = "Zurück zur Hauptansicht."
	_back_button.pressed.connect(_on_back_pressed)
	header.add_child(_back_button)

	_title_label = Label.new()
	_title_label.text = "Settings (Shell)"
	_title_label.modulate = Color(1, 1, 1, 0.85)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var scope_hint := Label.new()
	scope_hint.text = "read-only"
	scope_hint.modulate = Color(1, 1, 1, 0.45)
	scope_hint.add_theme_font_size_override("font_size", 10)
	header.add_child(scope_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 10)
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content_vbox)


func _on_back_pressed() -> void:
	close_requested.emit()


# --- Rendering ----------------------------------------------------------


func _render_sections() -> void:
	if _content_vbox == null:
		return
	for child in _content_vbox.get_children():
		child.queue_free()
	# Kein lebender Editor mehr — bei jedem Re-Render werden die
	# Widgets neu aufgebaut. `_llamafile_*`-Referenzen werden beim
	# Bau in `_build_llamafile_editor_block()` gesetzt.
	_llamafile_enabled_check = null
	_llamafile_mode_picker = null
	_llamafile_idle_spinbox = null
	_llamafile_path_edit = null
	_llamafile_apply_button = null
	_llamafile_probe_button = null
	_llamafile_apply_status_label = null
	_llamafile_probe_status_label = null

	for section in _SectionsRef.all_sections():
		_content_vbox.add_child(_build_section(section))
		# Editor-Block direkt unter dem Text-Provider-Readout einhängen.
		# Read-only Sections bleiben ungestört; die Editor-Oberfläche ist
		# visuell klar als eigener Block erkennbar (eigener Titel +
		# Hintergrundton), damit sie nicht mit der Shell-Liste verwechselt
		# wird.
		if section == _SectionsRef.SectionId.TEXT_PROVIDER:
			_content_vbox.add_child(_build_llamafile_editor_block())


func _build_section(section: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = _SectionsRef.label_for(section)
	title.add_theme_font_size_override("font_size", 12)
	title.modulate = Color(1, 1, 1, 0.85)
	box.add_child(title)

	var hint := Label.new()
	hint.text = _SectionsRef.placeholder_for(section)
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.add_theme_font_size_override("font_size", 10)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var lines := _lines_for(section)
	for row in lines:
		box.add_child(_build_row(row))

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	return box


func _lines_for(section: int) -> Array:
	match section:
		_SectionsRef.SectionId.GENERAL:
			return _SectionsRef.general_lines(_last_status)
		_SectionsRef.SectionId.PRESENCE_UI:
			return _SectionsRef.presence_ui_lines(_last_extras)
		_SectionsRef.SectionId.TEXT_PROVIDER:
			return _SectionsRef.text_provider_lines(_last_status)
		_SectionsRef.SectionId.STT:
			return _SectionsRef.stt_lines(_last_status)
		_SectionsRef.SectionId.TTS:
			return _SectionsRef.tts_lines(_last_status)
		_SectionsRef.SectionId.PRIVACY:
			return _SectionsRef.privacy_lines(_last_status)
		_SectionsRef.SectionId.CONNECTION:
			return _SectionsRef.connection_lines(_last_status, _last_extras)
		_:
			return []


func _build_row(row: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = str(row.get("label", ""))
	label.custom_minimum_size = Vector2(160, 0)
	label.modulate = Color(1, 1, 1, 0.6)
	label.add_theme_font_size_override("font_size", 10)
	hbox.add_child(label)

	var value := Label.new()
	value.text = str(row.get("value", ""))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size", 10)
	var muted := bool(row.get("muted", false))
	value.modulate = Color(1, 1, 1, 0.55) if muted else Color(1, 1, 1, 0.85)
	hbox.add_child(value)

	return hbox


# --- Llamafile Editor (PR 5) --------------------------------------------


## Baut den schmalen Editor-Block für `llamafile_local`. Direkt unter
## dem Text-Provider-Readout platziert, damit die Kontext-Nähe klar ist.
##
## Der Block zeigt sich immer (auch wenn llamafile nicht in der Chain
## steht), damit Betreiber die Config vor der ersten Aktivierung
## vorbereiten können. Die Editoren schreiben aber **nur** über den
## Core (`IpcClient.settings_set_llamafile_config`) — keine lokale
## Persistenz, keine zweite Wahrheit.
func _build_llamafile_editor_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "llamafile_local · Edit"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1, 1, 1, 0.85)
	box.add_child(title)

	var note := Label.new()
	note.text = "Editierbare Felder für den lokalen Runtime-Provider. Änderungen werden vom Core validiert und persistiert; der Binary-Pfad bleibt außerhalb von Logs/Status."
	note.modulate = Color(1, 1, 1, 0.45)
	note.add_theme_font_size_override("font_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	# Enabled
	var enabled_row := HBoxContainer.new()
	enabled_row.add_theme_constant_override("separation", 6)
	box.add_child(enabled_row)
	var enabled_label := Label.new()
	enabled_label.text = "Enabled"
	enabled_label.custom_minimum_size = Vector2(160, 0)
	enabled_label.modulate = Color(1, 1, 1, 0.6)
	enabled_label.add_theme_font_size_override("font_size", 10)
	enabled_row.add_child(enabled_label)
	_llamafile_enabled_check = CheckBox.new()
	_llamafile_enabled_check.text = "SMOLIT_LLAMAFILE_ENABLED"
	_llamafile_enabled_check.toggled.connect(_on_llamafile_widget_changed_bool)
	enabled_row.add_child(_llamafile_enabled_check)

	# Mode
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	box.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Mode"
	mode_label.custom_minimum_size = Vector2(160, 0)
	mode_label.modulate = Color(1, 1, 1, 0.6)
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_row.add_child(mode_label)
	_llamafile_mode_picker = OptionButton.new()
	for option in _LLAMAFILE_MODE_OPTIONS:
		_llamafile_mode_picker.add_item(str(option["label"]), int(option["id"]))
	_llamafile_mode_picker.item_selected.connect(_on_llamafile_widget_changed_index)
	mode_row.add_child(_llamafile_mode_picker)

	# Idle timeout
	var idle_row := HBoxContainer.new()
	idle_row.add_theme_constant_override("separation", 6)
	box.add_child(idle_row)
	var idle_label := Label.new()
	idle_label.text = "Idle timeout (s)"
	idle_label.custom_minimum_size = Vector2(160, 0)
	idle_label.modulate = Color(1, 1, 1, 0.6)
	idle_label.add_theme_font_size_override("font_size", 10)
	idle_row.add_child(idle_label)
	_llamafile_idle_spinbox = SpinBox.new()
	_llamafile_idle_spinbox.min_value = 1
	_llamafile_idle_spinbox.max_value = 86_400
	_llamafile_idle_spinbox.step = 1
	_llamafile_idle_spinbox.value = 300
	_llamafile_idle_spinbox.value_changed.connect(_on_llamafile_widget_changed_number)
	idle_row.add_child(_llamafile_idle_spinbox)

	# Binary path — einziges „sensibilitätsnahes" Feld. Die UI
	# spiegelt den Wert aus dem Status, logt aber **nicht** den Pfad
	# und schickt ihn nur an den Core. Secret-Klasse: keine.
	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override("separation", 6)
	box.add_child(path_row)
	var path_label := Label.new()
	path_label.text = "Binary path"
	path_label.custom_minimum_size = Vector2(160, 0)
	path_label.modulate = Color(1, 1, 1, 0.6)
	path_label.add_theme_font_size_override("font_size", 10)
	path_row.add_child(path_label)
	_llamafile_path_edit = LineEdit.new()
	_llamafile_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_llamafile_path_edit.placeholder_text = "/absolute/path/to/llamafile"
	_llamafile_path_edit.tooltip_text = "Pfad zum llamafile-Binary. Leer lassen, um den Pfad zu löschen. Wird nicht in Logs ausgegeben."
	_llamafile_path_edit.text_changed.connect(_on_llamafile_widget_changed_text)
	path_row.add_child(_llamafile_path_edit)

	# Actions
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	box.add_child(actions_row)

	_llamafile_apply_button = Button.new()
	_llamafile_apply_button.text = "Apply"
	_llamafile_apply_button.tooltip_text = "Sendet die aktuellen Werte als settings_set_llamafile_config an den Core."
	_llamafile_apply_button.pressed.connect(_on_llamafile_apply_pressed)
	actions_row.add_child(_llamafile_apply_button)

	_llamafile_probe_button = Button.new()
	_llamafile_probe_button.text = "Probe"
	_llamafile_probe_button.tooltip_text = "Prüft Chain-Mitgliedschaft, Enabled-Flag, Path-Existenz und Execute-Bit — kein Spawn, kein HTTP."
	_llamafile_probe_button.pressed.connect(_on_llamafile_probe_pressed)
	actions_row.add_child(_llamafile_probe_button)

	_llamafile_apply_status_label = Label.new()
	_llamafile_apply_status_label.text = ""
	_llamafile_apply_status_label.modulate = Color(1, 1, 1, 0.6)
	_llamafile_apply_status_label.add_theme_font_size_override("font_size", 10)
	actions_row.add_child(_llamafile_apply_status_label)

	_llamafile_probe_status_label = Label.new()
	_llamafile_probe_status_label.text = ""
	_llamafile_probe_status_label.modulate = Color(1, 1, 1, 0.6)
	_llamafile_probe_status_label.add_theme_font_size_override("font_size", 10)
	_llamafile_probe_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_llamafile_probe_status_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	# Widgets initial mit dem zuletzt bekannten Status-Stand
	# synchronisieren. Keine Write-Cascade — `_syncing_*` deckt das ab.
	_sync_llamafile_widgets_from_status()

	return box


## Schreibt die Werte aus `_last_status` in die Editor-Widgets.
## Wird bei jedem Re-Render aufgerufen und nach erfolgreichen
## `settings_set_llamafile_config`-Rückmeldungen (via `apply_status`).
func _sync_llamafile_widgets_from_status() -> void:
	if _llamafile_enabled_check == null:
		return
	_syncing_llamafile_widgets = true

	var enabled_variant: Variant = _last_status.get("llamafile_enabled", false)
	var enabled := bool(enabled_variant) if typeof(enabled_variant) == TYPE_BOOL else false
	_llamafile_enabled_check.button_pressed = enabled

	var mode_raw := str(_last_status.get("llamafile_mode", ""))
	var mode_index := 0
	for i in range(_LLAMAFILE_MODE_OPTIONS.size()):
		if _LLAMAFILE_MODE_OPTIONS[i]["value"] == mode_raw:
			mode_index = i
			break
	if _llamafile_mode_picker != null:
		_llamafile_mode_picker.select(mode_index)

	var idle_variant: Variant = _last_status.get("llamafile_idle_timeout_seconds", null)
	if typeof(idle_variant) == TYPE_INT or typeof(idle_variant) == TYPE_FLOAT:
		var idle := int(idle_variant)
		if idle > 0 and _llamafile_idle_spinbox != null:
			_llamafile_idle_spinbox.value = idle

	# Pfad-Feld: der Status trägt den Pfad heute nicht (Secret-
	# Disziplin). Wir lassen das Eingabefeld leer, wenn der Status
	# keinen Pfad trägt — der Nutzer sieht anhand von
	# `llamafile_configured` = yes/no, ob einer gesetzt ist.
	if _llamafile_path_edit != null:
		var path_variant: Variant = _last_status.get("llamafile_path", null)
		if typeof(path_variant) == TYPE_STRING:
			_llamafile_path_edit.text = String(path_variant)

	_syncing_llamafile_widgets = false


func _on_llamafile_widget_changed_bool(_pressed: bool) -> void:
	_clear_apply_status()


func _on_llamafile_widget_changed_index(_index: int) -> void:
	_clear_apply_status()


func _on_llamafile_widget_changed_number(_value: float) -> void:
	_clear_apply_status()


func _on_llamafile_widget_changed_text(_text: String) -> void:
	_clear_apply_status()


func _clear_apply_status() -> void:
	if _syncing_llamafile_widgets:
		return
	if _llamafile_apply_status_label != null:
		_llamafile_apply_status_label.text = ""


func _on_llamafile_apply_pressed() -> void:
	if _llamafile_enabled_check == null:
		return
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		_llamafile_apply_status_label.text = "offline"
		_llamafile_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	var enabled := _llamafile_enabled_check.button_pressed
	var mode_index := _llamafile_mode_picker.get_selected_id() if _llamafile_mode_picker != null else 0
	var mode_value := "on_demand"
	for option in _LLAMAFILE_MODE_OPTIONS:
		if int(option["id"]) == mode_index:
			mode_value = String(option["value"])
			break
	var idle_value: int = int(_llamafile_idle_spinbox.value) if _llamafile_idle_spinbox != null else 300
	# Pfad: wenn das Feld leer ist, senden wir `null` (kein Change).
	# Eine bewusste Leere reicht der Nutzer über ein explizites
	# zweites „Clear path"-Affordance — für PR 5 bewusst ausgelassen,
	# damit ein versehentliches Entfernen nicht durch reines Leer-
	# Klicken passiert.
	var path_value: Variant = null
	if _llamafile_path_edit != null:
		var raw := _llamafile_path_edit.text
		if raw.strip_edges() != "":
			path_value = raw
	if client.has_method("settings_set_llamafile_config"):
		client.call(
			"settings_set_llamafile_config",
			enabled, mode_value, idle_value, path_value,
		)
	_llamafile_apply_status_label.text = "sent"
	_llamafile_apply_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_llamafile_probe_pressed() -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _llamafile_probe_status_label != null:
			_llamafile_probe_status_label.text = "probe: offline"
			_llamafile_probe_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_probe_llamafile"):
		client.call("settings_probe_llamafile")
	if _llamafile_probe_status_label != null:
		_llamafile_probe_status_label.text = "probe: pending…"
		_llamafile_probe_status_label.modulate = Color(1, 1, 1, 0.55)


## Verarbeitet das `settings_probe_result`-Signal aus dem EventBus.
## Rendert den `class`-Tag + die kurze Core-Meldung. Leakt keine
## Pfade oder Roh-Strings — wir zeigen genau das, was der Core uns
## schickt, nicht mehr.
func _on_settings_probe_result_received(payload: Dictionary) -> void:
	if _llamafile_probe_status_label == null:
		return
	# `ok` wird bewusst nicht für einen eigenen grünen Haken genutzt —
	# wir rendern den Klassen-Tag des Cores 1:1, damit die UI keine
	# eigene Erfolgssemantik setzt.
	var class_tag := str(payload.get("class", "unknown"))
	var message := str(payload.get("message", ""))
	var display := "probe: [%s] %s" % [class_tag, message]
	_llamafile_probe_status_label.text = display
	var tint: Color = _PROBE_CLASS_COLORS.get(class_tag, Color(1, 1, 1, 0.55))
	_llamafile_probe_status_label.modulate = tint
