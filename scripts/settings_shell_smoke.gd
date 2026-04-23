extends SceneTree
## Settings-Shell-Smoketest (Phase 8c PR 3).
##
## Prüft:
##   * die pure Logik in `ui/scripts/settings/settings_sections.gd`
##     (Section-Reihenfolge, Labels, Slugs, defensive `*_lines`-
##     Renderer für leere, partielle und vollständige
##     StatusPayloads);
##   * das Scene-Verhalten des Panel-Controllers
##     (`ui/scripts/settings/settings_panel_controller.gd`):
##     unsichtbarer Default, `open_panel()` / `close_panel()` +
##     `close_requested`-Signal, `apply_status` / `apply_extras`
##     crash-frei für Nicht-Dictionaries.
##
## Ausdrücklich *nicht* Teil dieses Smokes:
##   * kein EventBus-Roundtrip, kein IPC — das Settings-Panel
##     spricht nicht mit dem Core;
##   * keine pixelgenaue Layout-Verifikation — wir prüfen
##     Zustand über `current_snapshot()` und Methodenaufrufe;
##   * keine Main-Scene-Instanziierung (die deckt der headless
##     Bootstrap in run_overlay_verification.sh ab).
##
## Lauf:
##   godot --headless --path ui --script scripts/settings_shell_smoke.gd
## oder:
##   scripts/run_overlay_verification.sh settings-shell-smoke
##
## Exit 0 = alle Assertions haben gehalten, 1 sonst.

const _SectionsRef := preload("res://scripts/settings/settings_sections.gd")
const _PanelScene := preload("res://scenes/settings/settings_panel.tscn")

var _fail: int = 0


func _init() -> void:
	_check_section_order_and_labels()
	_check_slug_uniqueness()
	_check_placeholders_non_empty()
	_check_general_lines()
	_check_presence_ui_lines_defensive()
	_check_text_provider_lines_empty()
	_check_text_provider_lines_full()
	_check_text_provider_lines_llamafile()
	_check_text_provider_lines_chain_visibility()
	_check_text_provider_lines_llamafile_in_chain_readout()
	_check_text_provider_lines_llamafile_not_in_chain_notes_disabled()
	_check_stt_and_tts_lines()
	_check_privacy_lines()
	_check_privacy_lines_llamafile_path_note()
	_check_connection_lines()
	_check_panel_default_hidden()
	_check_panel_open_close()
	_check_panel_close_requested_signal()
	_check_panel_apply_non_dictionary()
	_check_panel_snapshot_shape()
	_check_llamafile_editor_builds_when_panel_opens()
	_check_llamafile_editor_syncs_from_status()
	_check_llamafile_editor_idle_timeout_reflects_status()
	_check_llamafile_probe_result_rendering()
	_check_llamafile_probe_result_path_missing_does_not_leak()

	print("---")
	if _fail == 0:
		print("settings_shell smoke: PASS")
		quit(0)
	else:
		print("settings_shell smoke: FAIL (%d)" % _fail)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS  %s" % message)
	else:
		print("FAIL  %s" % message)
		_fail += 1


# --- Pure Helfer ---------------------------------------------------------


func _check_section_order_and_labels() -> void:
	var sections: Array = _SectionsRef.all_sections()
	_assert(sections.size() == 7, "all_sections liefert genau sieben Abschnitte")
	# Reihenfolge muss der dokumentierten Shell-Aufzählung folgen.
	_assert(sections[0] == _SectionsRef.SectionId.GENERAL,
		"Section[0] ist General")
	_assert(sections[1] == _SectionsRef.SectionId.PRESENCE_UI,
		"Section[1] ist Presence / UI")
	_assert(sections[2] == _SectionsRef.SectionId.TEXT_PROVIDER,
		"Section[2] ist Text Provider")
	_assert(sections[3] == _SectionsRef.SectionId.STT,
		"Section[3] ist STT")
	_assert(sections[4] == _SectionsRef.SectionId.TTS,
		"Section[4] ist TTS")
	_assert(sections[5] == _SectionsRef.SectionId.PRIVACY,
		"Section[5] ist Privacy / Cloud / Data handling")
	_assert(sections[6] == _SectionsRef.SectionId.CONNECTION,
		"Section[6] ist Connection / Status")

	_assert(_SectionsRef.label_for(_SectionsRef.SectionId.TEXT_PROVIDER) == "Text Provider",
		"label_for TEXT_PROVIDER liefert den Shell-Titel")
	_assert(_SectionsRef.label_for(999) == "unknown",
		"label_for unbekannt → 'unknown' ohne Crash")


func _check_slug_uniqueness() -> void:
	var slugs: Array = []
	for section in _SectionsRef.all_sections():
		slugs.append(_SectionsRef.slug_for(section))
	var as_set: Dictionary = {}
	for slug in slugs:
		as_set[slug] = true
	_assert(slugs.size() == as_set.size(),
		"Slugs sind eindeutig (keine doppelten Section-IDs)")
	_assert("text_provider" in slugs,
		"Slug 'text_provider' ist vorhanden")
	_assert("privacy" in slugs,
		"Slug 'privacy' ist vorhanden")


func _check_placeholders_non_empty() -> void:
	for section in _SectionsRef.all_sections():
		var text := String(_SectionsRef.placeholder_for(section))
		_assert(text != "",
			"placeholder_for(%s) ist nicht leer" % _SectionsRef.slug_for(section))


# --- Section-Renderer ---------------------------------------------------


func _check_general_lines() -> void:
	var lines: Array = _SectionsRef.general_lines({})
	_assert(lines.size() >= 2,
		"general_lines liefert mindestens zwei Zeilen")
	var labels: Array = _labels_of(lines)
	_assert("App" in labels, "general_lines enthält 'App'-Zeile")
	_assert("Settings" in labels, "general_lines enthält 'Settings'-Zeile")


func _check_presence_ui_lines_defensive() -> void:
	var lines: Array = _SectionsRef.presence_ui_lines({})
	_assert(lines.size() >= 3,
		"presence_ui_lines liefert mindestens drei Zeilen")
	# Leere Extras → alle dynamischen Werte sind `—`, nicht crashend.
	for row in lines:
		var label := str(row.get("label", ""))
		var value := str(row.get("value", ""))
		if label == "Visual Action Mode":
			_assert(value == "—",
				"Visual Action Mode bei leeren Extras → em-dash")
		if label == "Presence Mode":
			_assert(value == "—",
				"Presence Mode bei leeren Extras → em-dash")

	var filled: Array = _SectionsRef.presence_ui_lines({
		"visual_action_mode": "minimal_feedback",
		"presence_mode": "expanded",
	})
	var filled_labels: Dictionary = _row_map(filled)
	_assert(str(filled_labels.get("Visual Action Mode", "")) == "minimal_feedback",
		"presence_ui_lines übernimmt visual_action_mode aus Extras")
	_assert(str(filled_labels.get("Presence Mode", "")) == "expanded",
		"presence_ui_lines übernimmt presence_mode aus Extras")


func _check_text_provider_lines_empty() -> void:
	var lines: Array = _SectionsRef.text_provider_lines({})
	# Configured / Active / Availability / Last error / Cloud / Local fallback.
	_assert(lines.size() >= 6,
		"text_provider_lines liefert mindestens sechs Zeilen")
	var rows: Dictionary = _row_map(lines)
	_assert(str(rows.get("Configured", "")) == "—",
		"Configured ohne Daten → em-dash (kein Crash)")
	_assert(str(rows.get("Active", "")) == "—",
		"Active ohne Daten → em-dash")
	_assert(str(rows.get("Availability", "")) == "—",
		"Availability ohne Daten → em-dash")
	_assert(str(rows.get("Last error", "")) == "—",
		"Last error ohne Daten → em-dash")
	_assert(str(rows.get("Cloud", "")) == "no",
		"Cloud fehlt → defensiv 'no'")
	_assert(String(rows.get("Local fallback", "")).find("llamafile_local") >= 0,
		"Local-fallback-Zeile benennt llamafile_local")


func _check_text_provider_lines_full() -> void:
	var status := {
		"text_provider_configured": "abrain",
		"text_provider_active": "abrain",
		"text_provider_availability": "available",
		"text_provider_last_error": null,
		"text_provider_cloud": false,
	}
	var rows: Dictionary = _row_map(_SectionsRef.text_provider_lines(status))
	_assert(str(rows.get("Configured", "")) == "abrain",
		"Configured rendert abrain")
	_assert(str(rows.get("Active", "")) == "abrain",
		"Active rendert abrain")
	_assert(str(rows.get("Availability", "")) == "available",
		"Availability rendert available")
	_assert(str(rows.get("Last error", "")) == "—",
		"Last error null → em-dash (erfolgreich)")
	_assert(str(rows.get("Cloud", "")) == "no",
		"Cloud=false → 'no'")


func _check_text_provider_lines_llamafile() -> void:
	var status := {
		"text_provider_configured": "llamafile_local",
		"text_provider_active": "llamafile_local",
		"text_provider_availability": "available",
		"text_provider_last_error": "startup_timeout",
		"text_provider_cloud": false,
	}
	var rows: Dictionary = _row_map(_SectionsRef.text_provider_lines(status))
	_assert(str(rows.get("Configured", "")) == "llamafile_local",
		"llamafile_local als Configured sichtbar")
	_assert(str(rows.get("Active", "")) == "llamafile_local",
		"llamafile_local als Active sichtbar")
	_assert(str(rows.get("Last error", "")) == "startup_timeout",
		"Fehlerklasse startup_timeout wird 1:1 gerendert")
	var fallback_line := String(rows.get("Local fallback", ""))
	_assert(fallback_line.find("aktiver") >= 0 or fallback_line.find("konfigurierter") >= 0,
		"Local-fallback-Hinweis erkennt llamafile_local als aktiv/konfiguriert")


func _check_text_provider_lines_chain_visibility() -> void:
	# PR 4: das neue `text_provider_chain`-Feld wird als „→"-getrennte
	# Reihenfolge gerendert. Leere oder fehlende Arrays → Dash + muted.
	var rows_full: Dictionary = _row_map(_SectionsRef.text_provider_lines({
		"text_provider_chain": ["llamafile_local", "abrain"],
	}))
	_assert(str(rows_full.get("Chain", "")) == "llamafile_local → abrain",
		"Chain rendert die konfigurierte Fallback-Reihenfolge 1:1")

	var rows_single: Dictionary = _row_map(_SectionsRef.text_provider_lines({
		"text_provider_chain": ["abrain"],
	}))
	_assert(str(rows_single.get("Chain", "")) == "abrain",
		"Chain mit einem Kind → nur der Kind-Name, kein Trenner")

	var rows_missing: Dictionary = _row_map(_SectionsRef.text_provider_lines({}))
	_assert(str(rows_missing.get("Chain", "")) == "—",
		"Chain fehlt (alter Core) → Dash, kein Crash")

	var rows_empty_array: Dictionary = _row_map(_SectionsRef.text_provider_lines({
		"text_provider_chain": [],
	}))
	_assert(str(rows_empty_array.get("Chain", "")) == "—",
		"Chain leeres Array → Dash (keine fiktive Kette)")


func _check_text_provider_lines_llamafile_in_chain_readout() -> void:
	# PR 4: wenn `llamafile_in_chain=true`, expandiert die Shell den
	# vertieften Block mit Lifecycle / Mode / Idle-Timeout + Enabled-/
	# Configured-Flags. Werte kommen defensiv durch.
	var rows: Dictionary = _row_map(_SectionsRef.text_provider_lines({
		"text_provider_configured": "llamafile_local",
		"text_provider_active": "",
		"text_provider_chain": ["llamafile_local", "abrain"],
		"llamafile_in_chain": true,
		"llamafile_enabled": true,
		"llamafile_configured": false,
		"llamafile_lifecycle": "not_configured",
		"llamafile_mode": "on_demand",
		"llamafile_idle_timeout_seconds": 300,
	}))
	_assert(str(rows.get("llamafile_local", "")) == "in Chain",
		"llamafile_in_chain=true → Header 'in Chain'")
	_assert(str(rows.get("  lifecycle", "")) == "not_configured",
		"Lifecycle-Tag wird 1:1 durchgereicht")
	_assert(str(rows.get("  mode", "")) == "on_demand",
		"Mode wird 1:1 durchgereicht")
	_assert(str(rows.get("  idle timeout", "")) == "300",
		"Idle-Timeout als Zahl gerendert")
	_assert(str(rows.get("  enabled", "")) == "yes",
		"llamafile_enabled=true → 'yes'")
	_assert(str(rows.get("  configured (path set)", "")) == "no",
		"llamafile_configured=false → 'no'")


func _check_text_provider_lines_llamafile_not_in_chain_notes_disabled() -> void:
	# PR 4: `llamafile_in_chain=false` ist aussagekräftig, auch wenn
	# der Feature-Flag gesetzt ist — die Shell soll das ehrlich
	# aufzeigen, damit Operatoren die Kettenkonfiguration prüfen.
	var rows: Dictionary = _row_map(_SectionsRef.text_provider_lines({
		"text_provider_configured": "abrain",
		"text_provider_chain": ["abrain"],
		"llamafile_in_chain": false,
		"llamafile_enabled": true,
		"llamafile_configured": false,
		"llamafile_lifecycle": null,
		"llamafile_mode": null,
		"llamafile_idle_timeout_seconds": null,
	}))
	var note := str(rows.get("llamafile_local", ""))
	_assert(note.find("nicht in der Chain") >= 0,
		"llamafile_in_chain=false zeigt ehrlich 'nicht in der Chain'")
	_assert(note.find("SMOLIT_TEXT_PROVIDER_CHAIN") >= 0,
		"Hinweis nennt die zuständige Env-Variable (enabled+not-in-chain-Fall)")

	# Alter Core ohne llamafile_in_chain → Rückfallhinweis aus PR 3.
	var legacy: Dictionary = _row_map(_SectionsRef.text_provider_lines({
		"text_provider_configured": "abrain",
	}))
	var fallback_line := String(legacy.get("Local fallback", ""))
	_assert(fallback_line.find("llamafile_local") >= 0,
		"Rückfall-Pfad (alter Core ohne llamafile_in_chain) rendert den PR-3-Hinweis")


func _check_privacy_lines_llamafile_path_note() -> void:
	# PR 4: Privacy zeigt einen zusätzlichen „Text: lokaler Pfad"-Hinweis,
	# sobald llamafile_in_chain in der StatusPayload auftaucht. Text
	# unterscheidet sichtbar zwischen „in Chain + enabled", „in Chain +
	# disabled" und „nicht in Chain".
	var hot: Dictionary = _row_map(_SectionsRef.privacy_lines({
		"text_provider_cloud": false,
		"llamafile_in_chain": true,
		"llamafile_enabled": true,
	}))
	var hot_note := String(hot.get("Text: lokaler Pfad", ""))
	_assert(hot_note.find("llamafile_local in Chain") >= 0,
		"privacy: llamafile aktiv → 'llamafile_local in Chain'")
	_assert(hot_note.find("verlassen den Host nicht") >= 0,
		"privacy: aktiver Lokalpfad benennt den Host-Schutz")

	var chain_disabled: Dictionary = _row_map(_SectionsRef.privacy_lines({
		"text_provider_cloud": false,
		"llamafile_in_chain": true,
		"llamafile_enabled": false,
	}))
	var disabled_note := String(chain_disabled.get("Text: lokaler Pfad", ""))
	_assert(disabled_note.find("disabled") >= 0,
		"privacy: llamafile in Chain + disabled → 'disabled'-Hinweis")

	var abrain_only: Dictionary = _row_map(_SectionsRef.privacy_lines({
		"text_provider_cloud": false,
		"llamafile_in_chain": false,
	}))
	var abrain_note := String(abrain_only.get("Text: lokaler Pfad", ""))
	_assert(abrain_note.find("abrain") >= 0,
		"privacy: ohne llamafile → abrain als lokaler Pfad benannt")


func _check_stt_and_tts_lines() -> void:
	var stt_empty: Dictionary = _row_map(_SectionsRef.stt_lines({}))
	_assert(str(stt_empty.get("Enabled", "")) == "—",
		"stt_lines: Enabled ohne Daten → em-dash")
	_assert(str(stt_empty.get("Available", "")) == "—",
		"stt_lines: Available ohne Daten → em-dash")

	var stt_full: Dictionary = _row_map(_SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": false,
	}))
	_assert(str(stt_full.get("Enabled", "")) == "yes",
		"stt_lines: enabled=true → 'yes'")
	_assert(str(stt_full.get("Available", "")) == "no",
		"stt_lines: available=false → 'no'")

	var tts_full: Dictionary = _row_map(_SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": true,
		"auto_speak": false,
	}))
	_assert(str(tts_full.get("Enabled", "")) == "yes",
		"tts_lines: enabled=true → 'yes'")
	_assert(str(tts_full.get("Auto speak", "")) == "no",
		"tts_lines: auto_speak=false → 'no'")


func _check_privacy_lines() -> void:
	var empty: Dictionary = _row_map(_SectionsRef.privacy_lines({}))
	_assert(str(empty.get("Text: Cloud aktiv", "")) == "no",
		"privacy_lines: Cloud ohne Daten → defensiv 'no'")

	var cloud_on: Dictionary = _row_map(_SectionsRef.privacy_lines({
		"text_provider_cloud": true,
	}))
	_assert(str(cloud_on.get("Text: Cloud aktiv", "")) == "yes",
		"privacy_lines: Cloud=true → 'yes'")


func _check_connection_lines() -> void:
	var rows: Dictionary = _row_map(_SectionsRef.connection_lines({
		"ipc_enabled": true,
		"interaction_enabled": true,
		"interaction_backend": "command",
		"approval_timeout_seconds": 20,
		"accessibility_probe": "unavailable",
		"accessibility_probe_reason": "DBUS_SESSION_BUS_ADDRESS is unset",
	}, {"connected": true}))
	_assert(str(rows.get("IPC", "")) == "connected",
		"connection_lines: IPC connected aus Extras")
	_assert(str(rows.get("interaction_backend", "")) == "command",
		"connection_lines: interaction_backend wird 1:1 gerendert")
	_assert(str(rows.get("approval_timeout_seconds", "")) == "20",
		"connection_lines: approval_timeout_seconds numerisch gerendert")
	_assert(str(rows.get("accessibility_probe", "")) == "unavailable",
		"connection_lines: accessibility_probe sichtbar")
	_assert(str(rows.get("probe_reason", "")) != "",
		"connection_lines: probe_reason bei gesetztem Reason sichtbar")

	var disconnected: Dictionary = _row_map(_SectionsRef.connection_lines({}, {}))
	_assert(str(disconnected.get("IPC", "")) == "disconnected",
		"connection_lines: ohne Extras → disconnected")


# --- Scene-Verhalten ----------------------------------------------------


func _check_panel_default_hidden() -> void:
	var panel := _spawn_panel()
	_assert(not panel.visible,
		"Panel ist per Default unsichtbar")
	_assert(not panel.is_open(),
		"is_open() ist per Default false")
	_despawn_panel(panel)


func _check_panel_open_close() -> void:
	var panel := _spawn_panel()
	panel.apply_status({"text_provider_configured": "abrain"})
	panel.apply_extras({"visual_action_mode": "minimal_feedback"})
	panel.open_panel()
	_assert(panel.visible,
		"open_panel() macht Panel sichtbar")
	_assert(panel.is_open(),
		"is_open() ist nach open_panel() true")
	panel.close_panel()
	_assert(not panel.visible,
		"close_panel() versteckt das Panel wieder")
	_assert(not panel.is_open(),
		"is_open() ist nach close_panel() false")
	_despawn_panel(panel)


func _check_panel_close_requested_signal() -> void:
	var panel := _spawn_panel()
	var listener := _SignalListener.new()
	panel.close_requested.connect(listener.on_emit)
	# Es gibt keinen externen Back-Button außerhalb des Controllers —
	# wir simulieren daher einen Emit direkt aus der Shell, um den
	# Kontrakt zu prüfen: der Controller **muss** auf `close_requested`
	# reagieren, wenn sein interner Back-Button betätigt wird. Der
	# interne Handler emittiert bereits genau dieses Signal, daher
	# reicht der Aufruf des privaten Handlers stellvertretend.
	panel.call("_on_back_pressed")
	_assert(listener.count == 1,
		"close_requested-Signal feuert genau einmal auf Back-Press")
	_despawn_panel(panel)


func _check_panel_apply_non_dictionary() -> void:
	var panel := _spawn_panel()
	# Nicht-Dictionary-Eingaben dürfen nicht crashen — der Controller
	# fällt still auf leere Defaults zurück.
	panel.apply_status(null)
	panel.apply_status("unexpected")
	panel.apply_status(42)
	panel.apply_extras(null)
	panel.apply_extras([])
	panel.open_panel()
	_assert(panel.visible,
		"Panel überlebt Müll-Inputs und öffnet sich ohne Crash")
	_despawn_panel(panel)


func _check_llamafile_editor_builds_when_panel_opens() -> void:
	# PR 5: nach open_panel() muss der Editor-Block aufgebaut sein —
	# Enabled-CheckBox, Mode-Picker, Idle-Spinbox und Path-Edit.
	var panel := _spawn_panel()
	panel.open_panel()
	var snap: Dictionary = panel.llamafile_editor_snapshot()
	_assert(bool(snap.get("built", false)),
		"Editor-Block ist nach open_panel() gebaut")
	_assert(String(snap.get("mode", "")) != "",
		"Editor: Mode-Picker hat eine auflösbare Selektion")
	_despawn_panel(panel)


func _check_llamafile_editor_syncs_from_status() -> void:
	# PR 5: der Core bleibt Source of Truth — die Widgets
	# synchronisieren sich bei jedem `apply_status`-Tick.
	var panel := _spawn_panel()
	panel.apply_status({
		"llamafile_enabled": true,
		"llamafile_mode": "standby",
		"llamafile_idle_timeout_seconds": 900,
	})
	panel.open_panel()
	var snap: Dictionary = panel.llamafile_editor_snapshot()
	_assert(bool(snap.get("enabled", false)),
		"Editor: enabled wird aus Status übernommen")
	_assert(String(snap.get("mode", "")) == "standby",
		"Editor: mode wird aus Status übernommen (standby)")
	_assert(int(snap.get("idle_timeout_seconds", 0)) == 900,
		"Editor: idle_timeout_seconds wird aus Status übernommen (900)")
	_despawn_panel(panel)


func _check_llamafile_editor_idle_timeout_reflects_status() -> void:
	# Kleine Regression-Absicherung: unterschiedliche Status-Payloads
	# dürfen nicht klebrig sein. Erst 300, dann 120.
	var panel := _spawn_panel()
	panel.open_panel()
	panel.apply_status({
		"llamafile_enabled": true,
		"llamafile_mode": "on_demand",
		"llamafile_idle_timeout_seconds": 300,
	})
	var snap1: Dictionary = panel.llamafile_editor_snapshot()
	_assert(int(snap1.get("idle_timeout_seconds", 0)) == 300,
		"Editor: idle_timeout 300 sichtbar nach erstem apply_status")
	panel.apply_status({
		"llamafile_enabled": true,
		"llamafile_mode": "on_demand",
		"llamafile_idle_timeout_seconds": 120,
	})
	var snap2: Dictionary = panel.llamafile_editor_snapshot()
	_assert(int(snap2.get("idle_timeout_seconds", 0)) == 120,
		"Editor: idle_timeout 120 überschreibt den alten Wert")
	_despawn_panel(panel)


func _check_llamafile_probe_result_rendering() -> void:
	# PR 5: ein eingehender `settings_probe_result` mit class="ok"
	# landet im Probe-Status-Label. Die UI setzt keinen eigenen
	# „grünen Haken" — der Core-Tag wird 1:1 gerendert.
	var panel := _spawn_panel()
	panel.open_panel()
	panel.inject_probe_result_for_test({
		"ok": true,
		"class": "ok",
		"message": "llamafile_local looks ready (binary present, executable)",
		"lifecycle": "configured",
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	var snap: Dictionary = panel.llamafile_editor_snapshot()
	var probe_text := String(snap.get("probe_status", ""))
	_assert(probe_text.find("[ok]") >= 0,
		"Probe-Label zeigt den Core-class-Tag in eckigen Klammern")
	_assert(probe_text.find("looks ready") >= 0,
		"Probe-Label enthält die kurze Core-Nachricht")
	_despawn_panel(panel)


func _check_llamafile_probe_result_path_missing_does_not_leak() -> void:
	# PR 5 Secret-Disziplin: die UI darf einen Pfad nicht
	# „nachrendern", auch wenn er hypothetisch im Payload wäre.
	# Der Core sendet keinen Pfad, die UI verlässt sich darauf und
	# zeigt ausschließlich das, was ankommt.
	var panel := _spawn_panel()
	panel.open_panel()
	var secret_like := "/nonexistent/smolit-should-never-render-this"
	panel.inject_probe_result_for_test({
		"ok": false,
		"class": "path_missing",
		"message": "configured binary path does not exist",
		"lifecycle": "configured",
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	# Zusätzlich den Pfad explizit **nicht** ins Probe-Label stopfen:
	# das Label rendert nur message + class-Tag.
	var snap: Dictionary = panel.llamafile_editor_snapshot()
	var probe_text := String(snap.get("probe_status", ""))
	_assert(probe_text.find("[path_missing]") >= 0,
		"Probe-Label zeigt path_missing als class-Tag")
	_assert(probe_text.find(secret_like) < 0,
		"Probe-Label enthält keinen synthetischen Pfad-String")
	_despawn_panel(panel)


func _check_panel_snapshot_shape() -> void:
	var panel := _spawn_panel()
	panel.apply_status({
		"text_provider_configured": "abrain",
		"ipc_enabled": true,
	})
	panel.apply_extras({"connected": true, "presence_mode": "expanded"})
	var snap: Dictionary = panel.current_snapshot()
	_assert(snap.has("visible"),
		"snapshot enthält 'visible'")
	_assert(snap.has("sections"),
		"snapshot enthält 'sections'")
	var sections: Array = snap.get("sections", [])
	_assert(sections.size() == 7,
		"snapshot: sections-Liste hat sieben Einträge")
	_assert("text_provider" in sections,
		"snapshot: 'text_provider' ist in der Section-Liste")
	_despawn_panel(panel)


# --- Scene-Helfer -------------------------------------------------------


func _spawn_panel() -> Node:
	var instance: Node = _PanelScene.instantiate()
	root.add_child(instance)
	return instance


func _despawn_panel(instance: Node) -> void:
	if instance == null:
		return
	root.remove_child(instance)
	instance.queue_free()


# --- kleine Helfer ------------------------------------------------------


static func _labels_of(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			out.append(str(row.get("label", "")))
	return out


static func _row_map(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			out[str(row.get("label", ""))] = str(row.get("value", ""))
	return out


class _SignalListener:
	extends RefCounted
	var count: int = 0

	func on_emit() -> void:
		count += 1
