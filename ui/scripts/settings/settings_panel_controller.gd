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

## PR 7 — schmaler STT-Editor. Symmetrisch zum Llamafile-Block aber
## bewusst kleiner: enabled + command + Apply + Probe. Timeouts und
## Provider-Chain bleiben env-gesteuert und tauchen hier nicht auf.
var _stt_enabled_check: CheckBox = null
var _stt_command_edit: LineEdit = null
var _stt_apply_button: Button = null
var _stt_probe_button: Button = null
var _stt_apply_status_label: Label = null
var _stt_probe_status_label: Label = null

## PR 7 — TTS-Editor. Gleiches Layout wie STT plus `auto_speak`.
var _tts_enabled_check: CheckBox = null
var _tts_command_edit: LineEdit = null
var _tts_auto_speak_check: CheckBox = null
var _tts_apply_button: Button = null
var _tts_probe_button: Button = null
var _tts_apply_status_label: Label = null
var _tts_probe_status_label: Label = null

## PR 8 — `local_http`-Editor direkt unter dem Text-Provider-Readout.
## Bewusst klein: Enabled + Endpoint + Probe + Apply. Prompt-/Response-
## Feldnamen und Timeouts bleiben env-/Startup-gesteuert.
var _local_http_enabled_check: CheckBox = null
var _local_http_endpoint_edit: LineEdit = null
var _local_http_apply_button: Button = null
var _local_http_probe_button: Button = null
var _local_http_apply_status_label: Label = null
var _local_http_probe_status_label: Label = null

## PR 10 — Cloud-HTTP-Editor. Bewusst klein und security-first:
## Enabled + Endpoint + Modell + Secret + Probe + Apply. Der Secret-
## Wert wird **nie** aus dem Status rückgespiegelt — das Edit-Feld
## bleibt beim Rendering leer, ein separates Label zeigt nur
## „key saved ✓" vs. „key not set ✗" an.
var _cloud_http_enabled_check: CheckBox = null
var _cloud_http_endpoint_edit: LineEdit = null
var _cloud_http_model_edit: LineEdit = null
## Secret-Eingabefeld mit `secret = true` (Godot-Masking). Der Wert
## wird **nie** von `apply_status` befüllt — nur vom Nutzer.
var _cloud_http_secret_edit: LineEdit = null
var _cloud_http_apply_button: Button = null
var _cloud_http_save_secret_button: Button = null
var _cloud_http_clear_secret_button: Button = null
var _cloud_http_probe_button: Button = null
var _cloud_http_apply_status_label: Label = null
var _cloud_http_probe_status_label: Label = null
var _cloud_http_secret_status_label: Label = null
var _cloud_http_external_warning_label: Label = null

## PR 9 — Text-Provider-Chain-Editor. Bewusst klein: eine Liste der
## bekannten Kinds mit Enable-CheckBox + Up/Down-Buttons, Apply-Knopf
## und kleiner Reset-Knopf. Die UI hält keinen zweiten
## Wahrheitsanker — beim nächsten `apply_status`-Tick werden die
## Widgets aus `status.text_provider_chain` resynchronisiert.
var _text_chain_rows_vbox: VBoxContainer = null
var _text_chain_apply_button: Button = null
var _text_chain_reset_button: Button = null
var _text_chain_apply_status_label: Label = null
## Mirror der Widget-Reihenfolge. Jeder Eintrag ist ein Dictionary
## `{"kind": String, "in_chain": bool, "row_index": int}`; der Array-
## Index ist die aktuelle Position (wenn `in_chain=true`).
var _text_chain_state: Array = []

## Verhindert, dass Sync-Writes der Editor-Widgets beim Rendering eine
## Cascade aus Change-Handlern auslösen.
var _syncing_llamafile_widgets: bool = false
var _syncing_stt_widgets: bool = false
var _syncing_tts_widgets: bool = false
var _syncing_local_http_widgets: bool = false
var _syncing_text_chain_widgets: bool = false
var _syncing_cloud_http_widgets: bool = false

const _LLAMAFILE_MODE_OPTIONS: Array = [
	{"id": 0, "value": "on_demand", "label": "On demand"},
	{"id": 1, "value": "standby", "label": "Standby"},
]

## Whitelist der bekannten Text-Provider-Kinds. Muss mit
## [`crate::providers::text::KNOWN_TEXT_KINDS`] übereinstimmen; eine
## Abweichung wird im Core im `settings_set_text_provider_chain`-Pfad
## sichtbar (unknown kind) und beschädigt keine Persistenz.
const _KNOWN_TEXT_KINDS: Array[String] = ["abrain", "llamafile_local", "local_http"]

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
	# PR 8 — local_http-Klassen.
	"endpoint_scheme_unsupported": Color(0.85, 0.75, 0.4, 1.0),
	"endpoint_unparseable": Color(0.85, 0.75, 0.4, 1.0),
	"http_connect_failed": Color(0.9, 0.45, 0.45, 1.0),
	"timeout": Color(0.9, 0.45, 0.45, 1.0),
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
	# Widgets neu aufgebaut. `_llamafile_*`/`_stt_*`/`_tts_*`-Referenzen
	# werden beim Bau in den jeweiligen `_build_*_editor_block()`-
	# Helpern wieder gesetzt.
	_llamafile_enabled_check = null
	_llamafile_mode_picker = null
	_llamafile_idle_spinbox = null
	_llamafile_path_edit = null
	_llamafile_apply_button = null
	_llamafile_probe_button = null
	_llamafile_apply_status_label = null
	_llamafile_probe_status_label = null
	_stt_enabled_check = null
	_stt_command_edit = null
	_stt_apply_button = null
	_stt_probe_button = null
	_stt_apply_status_label = null
	_stt_probe_status_label = null
	_tts_enabled_check = null
	_tts_command_edit = null
	_tts_auto_speak_check = null
	_tts_apply_button = null
	_tts_probe_button = null
	_tts_apply_status_label = null
	_tts_probe_status_label = null
	_local_http_enabled_check = null
	_local_http_endpoint_edit = null
	_local_http_apply_button = null
	_local_http_probe_button = null
	_local_http_apply_status_label = null
	_local_http_probe_status_label = null
	_text_chain_rows_vbox = null
	_text_chain_apply_button = null
	_text_chain_reset_button = null
	_text_chain_apply_status_label = null
	_text_chain_state = []
	_cloud_http_enabled_check = null
	_cloud_http_endpoint_edit = null
	_cloud_http_model_edit = null
	_cloud_http_secret_edit = null
	_cloud_http_apply_button = null
	_cloud_http_save_secret_button = null
	_cloud_http_clear_secret_button = null
	_cloud_http_probe_button = null
	_cloud_http_apply_status_label = null
	_cloud_http_probe_status_label = null
	_cloud_http_secret_status_label = null
	_cloud_http_external_warning_label = null

	for section in _SectionsRef.all_sections():
		_content_vbox.add_child(_build_section(section))
		# Editor-Block direkt unter dem jeweiligen Read-only Readout
		# einhängen. Read-only Sections bleiben ungestört; die Editor-
		# Oberfläche ist visuell klar als eigener Block erkennbar
		# (eigener Titel), damit sie nicht mit der Shell-Liste
		# verwechselt wird. PR 8: der `local_http`-Block landet
		# **nach** dem Llamafile-Editor, weil beide unter Text Provider
		# leben.
		if section == _SectionsRef.SectionId.TEXT_PROVIDER:
			# PR 9: Chain-Editor zuerst, weil er die sichtbare
			# Reihenfolge kontrolliert; anschließend die Per-Kind-
			# Editoren (llamafile/local_http/cloud_http) in gewohnter
			# Reihenfolge. PR 10: cloud_http kommt zuletzt, damit die
			# externe/Cloud-Oberfläche visuell von den lokalen Blöcken
			# abgesetzt bleibt.
			_content_vbox.add_child(_build_text_chain_editor_block())
			_content_vbox.add_child(_build_llamafile_editor_block())
			_content_vbox.add_child(_build_local_http_editor_block())
			_content_vbox.add_child(_build_cloud_http_editor_block())
		elif section == _SectionsRef.SectionId.STT:
			_content_vbox.add_child(_build_stt_editor_block())
		elif section == _SectionsRef.SectionId.TTS:
			_content_vbox.add_child(_build_tts_editor_block())


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
## schickt, nicht mehr. Ab PR 7 routet `axis` das Ergebnis in den
## richtigen Editor-Block (`llamafile`/`stt`/`tts`); fehlt das Feld,
## fällt die Anzeige auf den Llamafile-Block zurück (Backwards-
## Kompatibilität zu einem Core ohne `axis`).
func _on_settings_probe_result_received(payload: Dictionary) -> void:
	var class_tag := str(payload.get("class", "unknown"))
	var message := str(payload.get("message", ""))
	var display := "probe: [%s] %s" % [class_tag, message]
	var tint: Color = _PROBE_CLASS_COLORS.get(class_tag, Color(1, 1, 1, 0.55))
	var axis := str(payload.get("axis", "llamafile"))
	var target: Label = null
	match axis:
		"stt":
			target = _stt_probe_status_label
		"tts":
			target = _tts_probe_status_label
		"local_http":
			target = _local_http_probe_status_label
		_:
			target = _llamafile_probe_status_label
	if target == null:
		return
	target.text = display
	target.modulate = tint


# --- STT/TTS Editor (PR 7) ----------------------------------------------


## Baut den schmalen STT-Editor-Block. Bewusst klein: Enabled +
## Command + Apply + Probe. Keine Timeouts, keine Chain-Umordnung —
## diese Hebel bleiben env-/Startup-gesteuert.
func _build_stt_editor_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "stt · Edit"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1, 1, 1, 0.85)
	box.add_child(title)

	var note := Label.new()
	note.text = "Editierbare Felder für den STT-Command-Provider. Probe prüft Chain/Enabled/Command ohne Mikrofon-Zugriff; Command-String wird nicht geloggt."
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
	_stt_enabled_check = CheckBox.new()
	_stt_enabled_check.text = "SMOLIT_STT_ENABLED"
	_stt_enabled_check.toggled.connect(_on_stt_widget_changed_bool)
	enabled_row.add_child(_stt_enabled_check)

	# Command
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 6)
	box.add_child(cmd_row)
	var cmd_label := Label.new()
	cmd_label.text = "Command"
	cmd_label.custom_minimum_size = Vector2(160, 0)
	cmd_label.modulate = Color(1, 1, 1, 0.6)
	cmd_label.add_theme_font_size_override("font_size", 10)
	cmd_row.add_child(cmd_label)
	_stt_command_edit = LineEdit.new()
	_stt_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stt_command_edit.placeholder_text = "whisper --model base"
	_stt_command_edit.tooltip_text = "STT-Kommando (wie SMOLIT_STT_CMD). Wird nicht in Logs ausgegeben."
	_stt_command_edit.text_changed.connect(_on_stt_widget_changed_text)
	cmd_row.add_child(_stt_command_edit)

	# Actions
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	box.add_child(actions_row)
	_stt_apply_button = Button.new()
	_stt_apply_button.text = "Apply"
	_stt_apply_button.tooltip_text = "Sendet die aktuellen STT-Werte als settings_set_stt_config an den Core."
	_stt_apply_button.pressed.connect(_on_stt_apply_pressed)
	actions_row.add_child(_stt_apply_button)
	_stt_probe_button = Button.new()
	_stt_probe_button.text = "Probe"
	_stt_probe_button.tooltip_text = "Prüft Chain/Enabled/Command ohne Side-Effects."
	_stt_probe_button.pressed.connect(_on_stt_probe_pressed)
	actions_row.add_child(_stt_probe_button)
	_stt_apply_status_label = Label.new()
	_stt_apply_status_label.text = ""
	_stt_apply_status_label.modulate = Color(1, 1, 1, 0.6)
	_stt_apply_status_label.add_theme_font_size_override("font_size", 10)
	actions_row.add_child(_stt_apply_status_label)

	_stt_probe_status_label = Label.new()
	_stt_probe_status_label.text = ""
	_stt_probe_status_label.modulate = Color(1, 1, 1, 0.6)
	_stt_probe_status_label.add_theme_font_size_override("font_size", 10)
	_stt_probe_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stt_probe_status_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	_sync_stt_widgets_from_status()
	return box


## Baut den TTS-Editor-Block. Spiegel zum STT-Block, plus auto_speak.
func _build_tts_editor_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "tts · Edit"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1, 1, 1, 0.85)
	box.add_child(title)

	var note := Label.new()
	note.text = "Editierbare Felder für den TTS-Command-Provider. Auto-speak ergänzt, ob Antworten automatisch gesprochen werden."
	note.modulate = Color(1, 1, 1, 0.45)
	note.add_theme_font_size_override("font_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	var enabled_row := HBoxContainer.new()
	enabled_row.add_theme_constant_override("separation", 6)
	box.add_child(enabled_row)
	var enabled_label := Label.new()
	enabled_label.text = "Enabled"
	enabled_label.custom_minimum_size = Vector2(160, 0)
	enabled_label.modulate = Color(1, 1, 1, 0.6)
	enabled_label.add_theme_font_size_override("font_size", 10)
	enabled_row.add_child(enabled_label)
	_tts_enabled_check = CheckBox.new()
	_tts_enabled_check.text = "SMOLIT_TTS_ENABLED"
	_tts_enabled_check.toggled.connect(_on_tts_widget_changed_bool)
	enabled_row.add_child(_tts_enabled_check)

	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 6)
	box.add_child(cmd_row)
	var cmd_label := Label.new()
	cmd_label.text = "Command"
	cmd_label.custom_minimum_size = Vector2(160, 0)
	cmd_label.modulate = Color(1, 1, 1, 0.6)
	cmd_label.add_theme_font_size_override("font_size", 10)
	cmd_row.add_child(cmd_label)
	_tts_command_edit = LineEdit.new()
	_tts_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tts_command_edit.placeholder_text = "espeak -v de"
	_tts_command_edit.tooltip_text = "TTS-Kommando (wie SMOLIT_TTS_CMD). Wird nicht in Logs ausgegeben."
	_tts_command_edit.text_changed.connect(_on_tts_widget_changed_text)
	cmd_row.add_child(_tts_command_edit)

	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 6)
	box.add_child(auto_row)
	var auto_label := Label.new()
	auto_label.text = "Auto-speak"
	auto_label.custom_minimum_size = Vector2(160, 0)
	auto_label.modulate = Color(1, 1, 1, 0.6)
	auto_label.add_theme_font_size_override("font_size", 10)
	auto_row.add_child(auto_label)
	_tts_auto_speak_check = CheckBox.new()
	_tts_auto_speak_check.text = "SMOLIT_AUTO_SPEAK"
	_tts_auto_speak_check.toggled.connect(_on_tts_widget_changed_bool)
	auto_row.add_child(_tts_auto_speak_check)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	box.add_child(actions_row)
	_tts_apply_button = Button.new()
	_tts_apply_button.text = "Apply"
	_tts_apply_button.tooltip_text = "Sendet die aktuellen TTS-Werte als settings_set_tts_config an den Core."
	_tts_apply_button.pressed.connect(_on_tts_apply_pressed)
	actions_row.add_child(_tts_apply_button)
	_tts_probe_button = Button.new()
	_tts_probe_button.text = "Probe"
	_tts_probe_button.tooltip_text = "Prüft Chain/Enabled/Command ohne Audio-Output."
	_tts_probe_button.pressed.connect(_on_tts_probe_pressed)
	actions_row.add_child(_tts_probe_button)
	_tts_apply_status_label = Label.new()
	_tts_apply_status_label.text = ""
	_tts_apply_status_label.modulate = Color(1, 1, 1, 0.6)
	_tts_apply_status_label.add_theme_font_size_override("font_size", 10)
	actions_row.add_child(_tts_apply_status_label)

	_tts_probe_status_label = Label.new()
	_tts_probe_status_label.text = ""
	_tts_probe_status_label.modulate = Color(1, 1, 1, 0.6)
	_tts_probe_status_label.add_theme_font_size_override("font_size", 10)
	_tts_probe_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tts_probe_status_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	_sync_tts_widgets_from_status()
	return box


func _sync_stt_widgets_from_status() -> void:
	if _stt_enabled_check == null:
		return
	_syncing_stt_widgets = true
	var enabled_variant: Variant = _last_status.get("stt_enabled", false)
	var enabled := bool(enabled_variant) if typeof(enabled_variant) == TYPE_BOOL else false
	_stt_enabled_check.button_pressed = enabled
	# Command wird aus Secret-Disziplin-Gründen nicht im Status
	# übertragen; wir lassen das Feld daher leer, wenn der Nutzer es
	# nicht eben selbst gesetzt hat. Das Probe-Ergebnis zeigt, ob der
	# Core einen Command konfiguriert findet (`configured`-Flag).
	_syncing_stt_widgets = false


func _sync_tts_widgets_from_status() -> void:
	if _tts_enabled_check == null:
		return
	_syncing_tts_widgets = true
	var enabled_variant: Variant = _last_status.get("tts_enabled", false)
	var enabled := bool(enabled_variant) if typeof(enabled_variant) == TYPE_BOOL else false
	_tts_enabled_check.button_pressed = enabled
	if _tts_auto_speak_check != null:
		var auto_variant: Variant = _last_status.get("auto_speak", false)
		var auto := bool(auto_variant) if typeof(auto_variant) == TYPE_BOOL else false
		_tts_auto_speak_check.button_pressed = auto
	_syncing_tts_widgets = false


func _on_stt_widget_changed_bool(_pressed: bool) -> void:
	if _syncing_stt_widgets:
		return
	if _stt_apply_status_label != null:
		_stt_apply_status_label.text = ""


func _on_stt_widget_changed_text(_text: String) -> void:
	if _syncing_stt_widgets:
		return
	if _stt_apply_status_label != null:
		_stt_apply_status_label.text = ""


func _on_tts_widget_changed_bool(_pressed: bool) -> void:
	if _syncing_tts_widgets:
		return
	if _tts_apply_status_label != null:
		_tts_apply_status_label.text = ""


func _on_tts_widget_changed_text(_text: String) -> void:
	if _syncing_tts_widgets:
		return
	if _tts_apply_status_label != null:
		_tts_apply_status_label.text = ""


func _on_stt_apply_pressed() -> void:
	if _stt_enabled_check == null:
		return
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _stt_apply_status_label != null:
			_stt_apply_status_label.text = "offline"
			_stt_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	var enabled := _stt_enabled_check.button_pressed
	# Command-Feld: nur senden, wenn der Nutzer etwas eingegeben hat.
	# Leerer Text → `null` (unverändert lassen), damit ein leeres
	# Eingabefeld den konfigurierten Command nicht versehentlich löscht.
	var cmd_value: Variant = null
	if _stt_command_edit != null:
		var raw := _stt_command_edit.text
		if raw.strip_edges() != "":
			cmd_value = raw
	if client.has_method("settings_set_stt_config"):
		client.call("settings_set_stt_config", enabled, cmd_value)
	if _stt_apply_status_label != null:
		_stt_apply_status_label.text = "sent"
		_stt_apply_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_tts_apply_pressed() -> void:
	if _tts_enabled_check == null:
		return
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _tts_apply_status_label != null:
			_tts_apply_status_label.text = "offline"
			_tts_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	var enabled := _tts_enabled_check.button_pressed
	var cmd_value: Variant = null
	if _tts_command_edit != null:
		var raw := _tts_command_edit.text
		if raw.strip_edges() != "":
			cmd_value = raw
	var auto_value: Variant = null
	if _tts_auto_speak_check != null:
		auto_value = _tts_auto_speak_check.button_pressed
	if client.has_method("settings_set_tts_config"):
		client.call("settings_set_tts_config", enabled, cmd_value, auto_value)
	if _tts_apply_status_label != null:
		_tts_apply_status_label.text = "sent"
		_tts_apply_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_stt_probe_pressed() -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _stt_probe_status_label != null:
			_stt_probe_status_label.text = "probe: offline"
			_stt_probe_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_probe_stt"):
		client.call("settings_probe_stt")
	if _stt_probe_status_label != null:
		_stt_probe_status_label.text = "probe: pending…"
		_stt_probe_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_tts_probe_pressed() -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _tts_probe_status_label != null:
			_tts_probe_status_label.text = "probe: offline"
			_tts_probe_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_probe_tts"):
		client.call("settings_probe_tts")
	if _tts_probe_status_label != null:
		_tts_probe_status_label.text = "probe: pending…"
		_tts_probe_status_label.modulate = Color(1, 1, 1, 0.55)


## Snapshot des STT-Editors für Smoke-Tests (PR 7). Spiegelt den UI-
## Widget-Stand, nicht den Core-Stand — wie `llamafile_editor_snapshot`.
func stt_editor_snapshot() -> Dictionary:
	var built := _stt_enabled_check != null
	if not built:
		return {
			"built": false,
			"enabled": false,
			"command": "",
			"apply_status": "",
			"probe_status": "",
		}
	return {
		"built": true,
		"enabled": _stt_enabled_check.button_pressed,
		"command": _stt_command_edit.text if _stt_command_edit != null else "",
		"apply_status": _stt_apply_status_label.text if _stt_apply_status_label != null else "",
		"probe_status": _stt_probe_status_label.text if _stt_probe_status_label != null else "",
	}


func tts_editor_snapshot() -> Dictionary:
	var built := _tts_enabled_check != null
	if not built:
		return {
			"built": false,
			"enabled": false,
			"command": "",
			"auto_speak": false,
			"apply_status": "",
			"probe_status": "",
		}
	return {
		"built": true,
		"enabled": _tts_enabled_check.button_pressed,
		"command": _tts_command_edit.text if _tts_command_edit != null else "",
		"auto_speak": _tts_auto_speak_check.button_pressed if _tts_auto_speak_check != null else false,
		"apply_status": _tts_apply_status_label.text if _tts_apply_status_label != null else "",
		"probe_status": _tts_probe_status_label.text if _tts_probe_status_label != null else "",
	}


# --- local_http Editor (PR 8) -------------------------------------------


## Baut den schmalen Editor-Block für den `local_http`-Text-Provider.
## Landet direkt nach dem Llamafile-Editor unter dem Text-Provider-
## Readout. Bewusst klein: Enabled + Endpoint + Apply + Probe.
## Prompt-/Response-Feldnamen und Timeouts bleiben env-gesteuert,
## damit diese Erst-Oberfläche ehrlich „loopback-first, HTTP-MVP"
## kommuniziert.
func _build_local_http_editor_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "local_http · Edit"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1, 1, 1, 0.85)
	box.add_child(title)

	var note := Label.new()
	note.text = "Allgemeiner lokaler HTTP-Text-Provider. Loopback-first, kein TLS, keine Secrets. Endpoint wird nicht in Logs ausgegeben."
	note.modulate = Color(1, 1, 1, 0.45)
	note.add_theme_font_size_override("font_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	var enabled_row := HBoxContainer.new()
	enabled_row.add_theme_constant_override("separation", 6)
	box.add_child(enabled_row)
	var enabled_label := Label.new()
	enabled_label.text = "Enabled"
	enabled_label.custom_minimum_size = Vector2(160, 0)
	enabled_label.modulate = Color(1, 1, 1, 0.6)
	enabled_label.add_theme_font_size_override("font_size", 10)
	enabled_row.add_child(enabled_label)
	_local_http_enabled_check = CheckBox.new()
	_local_http_enabled_check.text = "SMOLIT_LOCAL_HTTP_ENABLED"
	_local_http_enabled_check.toggled.connect(_on_local_http_widget_changed_bool)
	enabled_row.add_child(_local_http_enabled_check)

	var ep_row := HBoxContainer.new()
	ep_row.add_theme_constant_override("separation", 6)
	box.add_child(ep_row)
	var ep_label := Label.new()
	ep_label.text = "Endpoint"
	ep_label.custom_minimum_size = Vector2(160, 0)
	ep_label.modulate = Color(1, 1, 1, 0.6)
	ep_label.add_theme_font_size_override("font_size", 10)
	ep_row.add_child(ep_label)
	_local_http_endpoint_edit = LineEdit.new()
	_local_http_endpoint_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_local_http_endpoint_edit.placeholder_text = "http://127.0.0.1:8080/completion"
	_local_http_endpoint_edit.tooltip_text = "HTTP-Endpoint (kein https://). Wird nicht in Logs ausgegeben."
	_local_http_endpoint_edit.text_changed.connect(_on_local_http_widget_changed_text)
	ep_row.add_child(_local_http_endpoint_edit)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	box.add_child(actions_row)
	_local_http_apply_button = Button.new()
	_local_http_apply_button.text = "Apply"
	_local_http_apply_button.tooltip_text = "Sendet die aktuellen local_http-Werte als settings_set_local_http_config an den Core."
	_local_http_apply_button.pressed.connect(_on_local_http_apply_pressed)
	actions_row.add_child(_local_http_apply_button)
	_local_http_probe_button = Button.new()
	_local_http_probe_button.text = "Probe"
	_local_http_probe_button.tooltip_text = "TCP-Connect-Check (kein Completion-Roundtrip, kein Prompt)."
	_local_http_probe_button.pressed.connect(_on_local_http_probe_pressed)
	actions_row.add_child(_local_http_probe_button)
	_local_http_apply_status_label = Label.new()
	_local_http_apply_status_label.text = ""
	_local_http_apply_status_label.modulate = Color(1, 1, 1, 0.6)
	_local_http_apply_status_label.add_theme_font_size_override("font_size", 10)
	actions_row.add_child(_local_http_apply_status_label)

	_local_http_probe_status_label = Label.new()
	_local_http_probe_status_label.text = ""
	_local_http_probe_status_label.modulate = Color(1, 1, 1, 0.6)
	_local_http_probe_status_label.add_theme_font_size_override("font_size", 10)
	_local_http_probe_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_local_http_probe_status_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	_sync_local_http_widgets_from_status()
	return box


func _sync_local_http_widgets_from_status() -> void:
	if _local_http_enabled_check == null:
		return
	_syncing_local_http_widgets = true
	var enabled_variant: Variant = _last_status.get("local_http_enabled", false)
	var enabled := bool(enabled_variant) if typeof(enabled_variant) == TYPE_BOOL else false
	_local_http_enabled_check.button_pressed = enabled
	# Endpoint bleibt aus Secret-Disziplin-Gründen **nicht** im Status.
	# Der Nutzer sieht über `configured`-Flag, ob der Core einen
	# Endpoint konfiguriert findet.
	_syncing_local_http_widgets = false


func _on_local_http_widget_changed_bool(_pressed: bool) -> void:
	if _syncing_local_http_widgets:
		return
	if _local_http_apply_status_label != null:
		_local_http_apply_status_label.text = ""


func _on_local_http_widget_changed_text(_text: String) -> void:
	if _syncing_local_http_widgets:
		return
	if _local_http_apply_status_label != null:
		_local_http_apply_status_label.text = ""


func _on_local_http_apply_pressed() -> void:
	if _local_http_enabled_check == null:
		return
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _local_http_apply_status_label != null:
			_local_http_apply_status_label.text = "offline"
			_local_http_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	var enabled := _local_http_enabled_check.button_pressed
	var endpoint_value: Variant = null
	if _local_http_endpoint_edit != null:
		var raw := _local_http_endpoint_edit.text
		if raw.strip_edges() != "":
			endpoint_value = raw
	if client.has_method("settings_set_local_http_config"):
		client.call(
			"settings_set_local_http_config",
			enabled,
			endpoint_value,
			null,
		)
	if _local_http_apply_status_label != null:
		_local_http_apply_status_label.text = "sent"
		_local_http_apply_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_local_http_probe_pressed() -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _local_http_probe_status_label != null:
			_local_http_probe_status_label.text = "probe: offline"
			_local_http_probe_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_probe_local_http"):
		client.call("settings_probe_local_http")
	if _local_http_probe_status_label != null:
		_local_http_probe_status_label.text = "probe: pending…"
		_local_http_probe_status_label.modulate = Color(1, 1, 1, 0.55)


func local_http_editor_snapshot() -> Dictionary:
	var built := _local_http_enabled_check != null
	if not built:
		return {
			"built": false,
			"enabled": false,
			"endpoint": "",
			"apply_status": "",
			"probe_status": "",
		}
	return {
		"built": true,
		"enabled": _local_http_enabled_check.button_pressed,
		"endpoint": _local_http_endpoint_edit.text if _local_http_endpoint_edit != null else "",
		"apply_status": _local_http_apply_status_label.text if _local_http_apply_status_label != null else "",
		"probe_status": _local_http_probe_status_label.text if _local_http_probe_status_label != null else "",
	}


# --- Text-Provider-Chain-Editor (PR 9) ----------------------------------


## Baut den Chain-Editor direkt über dem Llamafile-Editor. Zeigt eine
## geordnete Liste der bekannten Text-Provider-Kinds; pro Zeile:
## Enable-Checkbox + Up/Down-Buttons. Darunter Apply/Reset + kleines
## Statuslabel. Bewusst klein: kein Drag-and-Drop, keine freie
## Namenseingabe.
func _build_text_chain_editor_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "text provider chain · Edit"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1, 1, 1, 0.85)
	box.add_child(title)

	var note := Label.new()
	note.text = "Reihenfolge der Text-Provider-Fallback-Kette. Aktiviere/Deaktiviere Kinds; Up/Down ordnen die aktiven Einträge. Nur bekannte Kinds."
	note.modulate = Color(1, 1, 1, 0.45)
	note.add_theme_font_size_override("font_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	_text_chain_rows_vbox = VBoxContainer.new()
	_text_chain_rows_vbox.add_theme_constant_override("separation", 2)
	box.add_child(_text_chain_rows_vbox)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	box.add_child(actions_row)
	_text_chain_apply_button = Button.new()
	_text_chain_apply_button.text = "Apply"
	_text_chain_apply_button.tooltip_text = "Sendet die aktuelle Reihenfolge als settings_set_text_provider_chain an den Core."
	_text_chain_apply_button.pressed.connect(_on_text_chain_apply_pressed)
	actions_row.add_child(_text_chain_apply_button)
	_text_chain_reset_button = Button.new()
	_text_chain_reset_button.text = "Reset"
	_text_chain_reset_button.tooltip_text = "Setzt die Kette auf den Default [\"abrain\"] zurück und löscht den persistierten Override."
	_text_chain_reset_button.pressed.connect(_on_text_chain_reset_pressed)
	actions_row.add_child(_text_chain_reset_button)
	_text_chain_apply_status_label = Label.new()
	_text_chain_apply_status_label.text = ""
	_text_chain_apply_status_label.modulate = Color(1, 1, 1, 0.6)
	_text_chain_apply_status_label.add_theme_font_size_override("font_size", 10)
	actions_row.add_child(_text_chain_apply_status_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	_sync_text_chain_widgets_from_status()
	return box


## Baut aus dem zuletzt bekannten Status `text_provider_chain` das
## lokale `_text_chain_state`-Modell und rendert die Rows. In-Chain-
## Kinds stehen oben in der Status-Reihenfolge, nicht-in-Chain-Kinds
## folgen darunter (disabled). Damit bleibt die visuelle Reihenfolge
## 1:1 die Chain-Reihenfolge.
func _sync_text_chain_widgets_from_status() -> void:
	if _text_chain_rows_vbox == null:
		return
	_syncing_text_chain_widgets = true
	_text_chain_state = []
	# 1) Kinds aus dem Status in ihrer Reihenfolge aufnehmen.
	var chain_raw: Variant = _last_status.get("text_provider_chain", null)
	var chain_kinds: Array[String] = []
	if typeof(chain_raw) == TYPE_ARRAY:
		for entry in chain_raw:
			var e := String(entry)
			if e in _KNOWN_TEXT_KINDS and not (e in chain_kinds):
				chain_kinds.append(e)
	# 2) Restliche bekannte Kinds anhängen (als nicht-in-Chain).
	for kind in _KNOWN_TEXT_KINDS:
		if not (kind in chain_kinds):
			_text_chain_state.append({"kind": kind, "in_chain": false})
	# Status-Reihenfolge zuerst in den State hineinziehen.
	var front: Array = []
	for kind in chain_kinds:
		front.append({"kind": kind, "in_chain": true})
	_text_chain_state = front + _text_chain_state
	_render_text_chain_rows()
	_syncing_text_chain_widgets = false


func _render_text_chain_rows() -> void:
	if _text_chain_rows_vbox == null:
		return
	for child in _text_chain_rows_vbox.get_children():
		child.queue_free()
	for i in range(_text_chain_state.size()):
		var entry: Dictionary = _text_chain_state[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_text_chain_rows_vbox.add_child(row)

		var enabled_check := CheckBox.new()
		enabled_check.text = String(entry.get("kind", "?"))
		enabled_check.button_pressed = bool(entry.get("in_chain", false))
		enabled_check.tooltip_text = "Provider in der Fallback-Kette aktiv."
		enabled_check.toggled.connect(_on_text_chain_row_toggled.bind(i))
		enabled_check.custom_minimum_size = Vector2(220, 0)
		row.add_child(enabled_check)

		var up_button := Button.new()
		up_button.text = "↑"
		up_button.disabled = i == 0 or not bool(entry.get("in_chain", false))
		up_button.tooltip_text = "Ein Slot nach oben."
		up_button.pressed.connect(_on_text_chain_row_move.bind(i, -1))
		row.add_child(up_button)

		var down_button := Button.new()
		down_button.text = "↓"
		# Down-Button darf nur klicken, wenn es unter diesem Eintrag
		# noch einen in-Chain-Eintrag gibt (sonst sinnlos).
		var has_in_chain_below := false
		for j in range(i + 1, _text_chain_state.size()):
			var next_entry: Dictionary = _text_chain_state[j]
			if bool(next_entry.get("in_chain", false)):
				has_in_chain_below = true
				break
		down_button.disabled = not has_in_chain_below or not bool(entry.get("in_chain", false))
		down_button.tooltip_text = "Ein Slot nach unten."
		down_button.pressed.connect(_on_text_chain_row_move.bind(i, 1))
		row.add_child(down_button)


func _on_text_chain_row_toggled(pressed: bool, row_index: int) -> void:
	if _syncing_text_chain_widgets:
		return
	if row_index < 0 or row_index >= _text_chain_state.size():
		return
	var entry: Dictionary = _text_chain_state[row_index]
	entry["in_chain"] = pressed
	_text_chain_state[row_index] = entry
	# Sortieren: in-Chain nach oben, disabled nach unten — ohne die
	# relative Reihenfolge innerhalb jeder Gruppe zu ändern.
	var enabled_rows: Array = []
	var disabled_rows: Array = []
	for e in _text_chain_state:
		if bool(e.get("in_chain", false)):
			enabled_rows.append(e)
		else:
			disabled_rows.append(e)
	_text_chain_state = enabled_rows + disabled_rows
	if _text_chain_apply_status_label != null:
		_text_chain_apply_status_label.text = ""
	_render_text_chain_rows()


func _on_text_chain_row_move(row_index: int, direction: int) -> void:
	if _syncing_text_chain_widgets:
		return
	var target := row_index + direction
	if row_index < 0 or row_index >= _text_chain_state.size():
		return
	if target < 0 or target >= _text_chain_state.size():
		return
	var tmp: Dictionary = _text_chain_state[row_index]
	_text_chain_state[row_index] = _text_chain_state[target]
	_text_chain_state[target] = tmp
	if _text_chain_apply_status_label != null:
		_text_chain_apply_status_label.text = ""
	_render_text_chain_rows()


func _on_text_chain_apply_pressed() -> void:
	if _text_chain_rows_vbox == null:
		return
	# UI-seitige First-Line-of-Defense: leere Ketten gar nicht erst
	# an den Core schicken. Der Core-Validator bleibt trotzdem aktiv
	# (Second-Line-of-Defense, siehe `validate_text_chain`).
	var chain: Array[String] = []
	for entry in _text_chain_state:
		if bool(entry.get("in_chain", false)):
			chain.append(String(entry.get("kind", "")))
	if chain.is_empty():
		if _text_chain_apply_status_label != null:
			_text_chain_apply_status_label.text = "chain empty — enable at least one provider"
			_text_chain_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _text_chain_apply_status_label != null:
			_text_chain_apply_status_label.text = "offline"
			_text_chain_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_set_text_provider_chain"):
		client.call("settings_set_text_provider_chain", chain)
	if _text_chain_apply_status_label != null:
		_text_chain_apply_status_label.text = "sent"
		_text_chain_apply_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_text_chain_reset_pressed() -> void:
	var client: Node = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _text_chain_apply_status_label != null:
			_text_chain_apply_status_label.text = "offline"
			_text_chain_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_reset_text_provider_chain"):
		client.call("settings_reset_text_provider_chain")
	if _text_chain_apply_status_label != null:
		_text_chain_apply_status_label.text = "reset sent"
		_text_chain_apply_status_label.modulate = Color(1, 1, 1, 0.55)


## Snapshot des Chain-Editors für Smoke-Tests. Spiegelt die aktuelle
## Widget-Reihenfolge + Enable-States.
func text_chain_editor_snapshot() -> Dictionary:
	var built := _text_chain_rows_vbox != null
	if not built:
		return {"built": false, "rows": [], "apply_status": ""}
	var rows: Array = []
	for entry in _text_chain_state:
		rows.append({
			"kind": String(entry.get("kind", "")),
			"in_chain": bool(entry.get("in_chain", false)),
		})
	return {
		"built": true,
		"rows": rows,
		"apply_status": _text_chain_apply_status_label.text if _text_chain_apply_status_label != null else "",
	}


## Test-Hook: triggert Widget-Events ohne Scene-Tree-Interaktion.
func simulate_text_chain_toggle_for_test(row_index: int, pressed: bool) -> void:
	_on_text_chain_row_toggled(pressed, row_index)


func simulate_text_chain_move_for_test(row_index: int, direction: int) -> void:
	_on_text_chain_row_move(row_index, direction)


# --- Cloud-HTTP-Editor (PR 10) ------------------------------------------


## Baut den Cloud-HTTP-Editor. Konservativ: Enabled + Endpoint +
## Modell + Secret + Probe + Apply. Der Secret-Wert wird **nie** aus
## `apply_status` rückgespiegelt — das Edit-Feld bleibt leer, ein
## separates Label trägt den `cloud_http_secret_present`-Flag.
func _build_cloud_http_editor_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "cloud_http · Edit · external"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1, 0.85, 0.55, 0.95)
	box.add_child(title)

	_cloud_http_external_warning_label = Label.new()
	_cloud_http_external_warning_label.text = (
		"Achtung: externer / cloud Pfad. Requests verlassen diese Maschine in dem Moment, in dem dieser Provider in der Chain steht und enabled ist."
	)
	_cloud_http_external_warning_label.modulate = Color(1, 0.85, 0.55, 0.9)
	_cloud_http_external_warning_label.add_theme_font_size_override("font_size", 10)
	_cloud_http_external_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_cloud_http_external_warning_label)

	_cloud_http_enabled_check = CheckBox.new()
	_cloud_http_enabled_check.text = "SMOLIT_CLOUD_HTTP_ENABLED"
	_cloud_http_enabled_check.tooltip_text = "Master-Schalter für cloud_http. Ohne diesen Flag bleibt der Provider inert, auch wenn er in der Chain steht."
	box.add_child(_cloud_http_enabled_check)

	var endpoint_row := HBoxContainer.new()
	endpoint_row.add_theme_constant_override("separation", 6)
	box.add_child(endpoint_row)
	var endpoint_label := Label.new()
	endpoint_label.text = "endpoint"
	endpoint_label.custom_minimum_size = Vector2(90, 0)
	endpoint_row.add_child(endpoint_label)
	_cloud_http_endpoint_edit = LineEdit.new()
	_cloud_http_endpoint_edit.placeholder_text = "http://host:port/path  (https:// in dieser Stufe noch nicht unterstützt)"
	_cloud_http_endpoint_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endpoint_row.add_child(_cloud_http_endpoint_edit)

	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 6)
	box.add_child(model_row)
	var model_label := Label.new()
	model_label.text = "model"
	model_label.custom_minimum_size = Vector2(90, 0)
	model_row.add_child(model_label)
	_cloud_http_model_edit = LineEdit.new()
	_cloud_http_model_edit.placeholder_text = "optional, z. B. gpt-4o-mini"
	_cloud_http_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_row.add_child(_cloud_http_model_edit)

	# Secret-Zeile: Maskiertes LineEdit + Status + Save/Clear. Der
	# Wert wird **nie** aus `apply_status` befüllt.
	var secret_row := HBoxContainer.new()
	secret_row.add_theme_constant_override("separation", 6)
	box.add_child(secret_row)
	var secret_label := Label.new()
	secret_label.text = "api_key"
	secret_label.custom_minimum_size = Vector2(90, 0)
	secret_row.add_child(secret_label)
	_cloud_http_secret_edit = LineEdit.new()
	_cloud_http_secret_edit.secret = true
	_cloud_http_secret_edit.placeholder_text = "paste key — not echoed, not stored in UI"
	_cloud_http_secret_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secret_row.add_child(_cloud_http_secret_edit)
	_cloud_http_save_secret_button = Button.new()
	_cloud_http_save_secret_button.text = "Save key"
	_cloud_http_save_secret_button.tooltip_text = "Schreibt den eingegebenen Key über settings_set_cloud_http_secret in den Core-Secret-Store (0600). Leeres Feld = kein Write."
	_cloud_http_save_secret_button.pressed.connect(_on_cloud_http_save_secret_pressed)
	secret_row.add_child(_cloud_http_save_secret_button)
	_cloud_http_clear_secret_button = Button.new()
	_cloud_http_clear_secret_button.text = "Clear key"
	_cloud_http_clear_secret_button.tooltip_text = "Löscht den persistierten Key im Core-Secret-Store."
	_cloud_http_clear_secret_button.pressed.connect(_on_cloud_http_clear_secret_pressed)
	secret_row.add_child(_cloud_http_clear_secret_button)

	_cloud_http_secret_status_label = Label.new()
	_cloud_http_secret_status_label.text = "key: unknown"
	_cloud_http_secret_status_label.modulate = Color(1, 1, 1, 0.6)
	_cloud_http_secret_status_label.add_theme_font_size_override("font_size", 10)
	box.add_child(_cloud_http_secret_status_label)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	box.add_child(actions_row)
	_cloud_http_apply_button = Button.new()
	_cloud_http_apply_button.text = "Apply"
	_cloud_http_apply_button.tooltip_text = "Schreibt enabled/endpoint/model in den Core (Secret ist getrennter Pfad)."
	_cloud_http_apply_button.pressed.connect(_on_cloud_http_apply_pressed)
	actions_row.add_child(_cloud_http_apply_button)
	_cloud_http_probe_button = Button.new()
	_cloud_http_probe_button.text = "Probe"
	_cloud_http_probe_button.tooltip_text = "TCP-Connect gegen den Endpoint; kein Completion-Request, kein Bearer-Header."
	_cloud_http_probe_button.pressed.connect(_on_cloud_http_probe_pressed)
	actions_row.add_child(_cloud_http_probe_button)

	_cloud_http_apply_status_label = Label.new()
	_cloud_http_apply_status_label.text = ""
	_cloud_http_apply_status_label.modulate = Color(1, 1, 1, 0.6)
	_cloud_http_apply_status_label.add_theme_font_size_override("font_size", 10)
	box.add_child(_cloud_http_apply_status_label)
	_cloud_http_probe_status_label = Label.new()
	_cloud_http_probe_status_label.text = ""
	_cloud_http_probe_status_label.modulate = Color(1, 1, 1, 0.6)
	_cloud_http_probe_status_label.add_theme_font_size_override("font_size", 10)
	box.add_child(_cloud_http_probe_status_label)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	box.add_child(sep)

	_sync_cloud_http_widgets_from_status()
	return box


## Liest `cloud_http_*`-Felder aus dem letzten Status und spiegelt sie
## in die Widgets. **Niemals** wird der API-Key zurückgeholt — das
## Secret-Edit-Feld bleibt leer. Ein separates Label trägt den
## `cloud_http_secret_present`-Bool.
func _sync_cloud_http_widgets_from_status() -> void:
	if _cloud_http_enabled_check == null:
		return
	_syncing_cloud_http_widgets = true
	var enabled := bool(_last_status.get("cloud_http_enabled", false))
	_cloud_http_enabled_check.button_pressed = enabled
	# Endpoint/Model werden **nicht** aus dem Status geholt — der
	# StatusPayload trägt diese Felder bewusst nicht, siehe
	# `docs/provider_fallback_and_settings_architecture.md` §11. Die
	# UI leert sie beim ersten Sync, damit keine Stale-Werte aus einem
	# alten Core hängen bleiben.
	if _cloud_http_endpoint_edit != null and _cloud_http_endpoint_edit.text == "":
		_cloud_http_endpoint_edit.text = ""
	if _cloud_http_model_edit != null and _cloud_http_model_edit.text == "":
		_cloud_http_model_edit.text = ""
	var secret_present := bool(_last_status.get("cloud_http_secret_present", false))
	if _cloud_http_secret_status_label != null:
		if secret_present:
			_cloud_http_secret_status_label.text = "key: saved ✓"
			_cloud_http_secret_status_label.modulate = Color(0.6, 0.9, 0.6, 0.9)
		else:
			_cloud_http_secret_status_label.text = "key: not set ✗"
			_cloud_http_secret_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
	_syncing_cloud_http_widgets = false


func _on_cloud_http_apply_pressed() -> void:
	if _cloud_http_enabled_check == null:
		return
	var client: Node = null
	if is_inside_tree():
		client = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _cloud_http_apply_status_label != null:
			_cloud_http_apply_status_label.text = "offline"
			_cloud_http_apply_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	var endpoint: Variant = null
	if _cloud_http_endpoint_edit != null:
		endpoint = _cloud_http_endpoint_edit.text
	var model: Variant = null
	if _cloud_http_model_edit != null and _cloud_http_model_edit.text.strip_edges() != "":
		model = _cloud_http_model_edit.text
	if client.has_method("settings_set_cloud_http_config"):
		client.call(
			"settings_set_cloud_http_config",
			_cloud_http_enabled_check.button_pressed,
			endpoint,
			model,
			null,
		)
	if _cloud_http_apply_status_label != null:
		_cloud_http_apply_status_label.text = "sent"
		_cloud_http_apply_status_label.modulate = Color(1, 1, 1, 0.55)


## Secret-Schreibpfad. Security-first:
##   1. Wert aus dem Edit lesen.
##   2. Edit-Feld **sofort** leeren (auch bei Offline / leerem Input),
##      damit der Klartext in keinem UI-Zustand überlebt.
##   3. Erst danach gegen den Core senden.
func _on_cloud_http_save_secret_pressed() -> void:
	if _cloud_http_secret_edit == null:
		return
	var value := _cloud_http_secret_edit.text
	# Step 1+2: Wert kopieren, Feld sofort leeren.
	_cloud_http_secret_edit.text = ""
	# UI-seitige Vorbedingung: leeres Feld = kein Save (Clear
	# läuft über den eigenen Button).
	if value.strip_edges() == "":
		if _cloud_http_secret_status_label != null:
			_cloud_http_secret_status_label.text = "key: empty input — use 'Clear key' to remove a stored key"
			_cloud_http_secret_status_label.modulate = Color(0.9, 0.7, 0.3, 0.9)
		return
	var client: Node = null
	if is_inside_tree():
		client = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _cloud_http_secret_status_label != null:
			_cloud_http_secret_status_label.text = "offline — key not sent (retype to retry)"
			_cloud_http_secret_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_set_cloud_http_secret"):
		client.call("settings_set_cloud_http_secret", value)
	if _cloud_http_secret_status_label != null:
		_cloud_http_secret_status_label.text = "key: sent (field cleared)"
		_cloud_http_secret_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_cloud_http_clear_secret_pressed() -> void:
	var client: Node = null
	if is_inside_tree():
		client = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _cloud_http_secret_status_label != null:
			_cloud_http_secret_status_label.text = "offline"
			_cloud_http_secret_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_set_cloud_http_secret"):
		client.call("settings_set_cloud_http_secret", null)
	if _cloud_http_secret_edit != null:
		_cloud_http_secret_edit.text = ""
	if _cloud_http_secret_status_label != null:
		_cloud_http_secret_status_label.text = "key: clear requested"
		_cloud_http_secret_status_label.modulate = Color(1, 1, 1, 0.55)


func _on_cloud_http_probe_pressed() -> void:
	var client: Node = null
	if is_inside_tree():
		client = get_node_or_null("/root/IpcClient")
	if client == null or not client.has_method("is_connected_to_core") \
			or not client.is_connected_to_core():
		if _cloud_http_probe_status_label != null:
			_cloud_http_probe_status_label.text = "offline"
			_cloud_http_probe_status_label.modulate = Color(0.9, 0.5, 0.5, 0.9)
		return
	if client.has_method("settings_probe_cloud_http"):
		client.call("settings_probe_cloud_http")
	if _cloud_http_probe_status_label != null:
		_cloud_http_probe_status_label.text = "probe: pending…"
		_cloud_http_probe_status_label.modulate = Color(1, 1, 1, 0.55)


func cloud_http_editor_snapshot() -> Dictionary:
	var built := _cloud_http_enabled_check != null
	if not built:
		return {
			"built": false,
			"enabled": false,
			"endpoint": "",
			"model": "",
			"secret_status": "",
			"secret_edit_text": "",
			"apply_status": "",
			"probe_status": "",
			"external_warning": "",
		}
	return {
		"built": true,
		"enabled": _cloud_http_enabled_check.button_pressed,
		"endpoint": _cloud_http_endpoint_edit.text if _cloud_http_endpoint_edit != null else "",
		"model": _cloud_http_model_edit.text if _cloud_http_model_edit != null else "",
		"secret_status": _cloud_http_secret_status_label.text if _cloud_http_secret_status_label != null else "",
		"secret_edit_text": _cloud_http_secret_edit.text if _cloud_http_secret_edit != null else "",
		"apply_status": _cloud_http_apply_status_label.text if _cloud_http_apply_status_label != null else "",
		"probe_status": _cloud_http_probe_status_label.text if _cloud_http_probe_status_label != null else "",
		"external_warning": _cloud_http_external_warning_label.text if _cloud_http_external_warning_label != null else "",
	}


## Test-Hook: simuliert einen Klick auf „Save key". Wird vom Smoke-
## Test benutzt, um Secret-Masking und sofortiges Leeren des Felds zu
## verifizieren, ohne einen echten IpcClient-Autoload zu brauchen.
func simulate_cloud_http_save_secret_for_test(value: String) -> void:
	if _cloud_http_secret_edit != null:
		_cloud_http_secret_edit.text = value
	_on_cloud_http_save_secret_pressed()
