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
	_check_stt_tts_provider_rows()
	_check_privacy_lines()
	_check_privacy_lines_audio_cloud_rollup()
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
	_check_stt_editor_builds_and_syncs()
	_check_tts_editor_builds_and_syncs()
	_check_stt_probe_routes_to_stt_label()
	_check_tts_probe_routes_to_tts_label()
	_check_probe_without_axis_falls_back_to_llamafile()
	_check_stt_tts_probe_does_not_leak_command()
	_check_local_http_editor_builds_and_syncs()
	_check_local_http_probe_routes_to_local_http_label()
	_check_local_http_probe_scheme_unsupported_does_not_leak()
	_check_text_provider_lines_local_http_visibility()
	_check_text_chain_editor_builds_and_syncs_from_status()
	_check_text_chain_editor_toggle_and_move()
	_check_text_chain_editor_prevents_empty_chain_on_apply()
	_check_cloud_http_editor_builds_and_shows_external_warning()
	_check_cloud_http_editor_never_populates_secret_edit_from_status()
	_check_cloud_http_editor_secret_present_flag_mirrored_in_status_label()
	_check_cloud_http_editor_save_secret_clears_edit_field()
	_check_cloud_http_editor_shows_insecure_hint_for_http_endpoint()
	_check_cloud_http_editor_hides_insecure_hint_for_https_endpoint()
	_check_audio_chain_editor_builds_and_syncs_from_status("stt")
	_check_audio_chain_editor_builds_and_syncs_from_status("tts")
	_check_audio_chain_editor_empty_guard("stt")
	_check_audio_chain_editor_empty_guard("tts")
	_check_audio_chain_editor_shows_single_kind_info_hint()
	_check_audio_provider_lines_render_chain_field()
	# --- PR 27: whisper_cpp STT ---
	_check_stt_chain_editor_exposes_whisper_cpp_kind()
	_check_stt_chain_editor_renders_whisper_cpp_then_command_order()
	_check_stt_lines_whisper_cpp_in_chain_shows_env_hint_when_unconfigured()
	_check_stt_lines_whisper_cpp_in_chain_configured_hides_env_hint()
	_check_stt_lines_whisper_cpp_not_in_chain_is_muted_note()
	_check_stt_lines_legacy_core_without_whisper_cpp_fields_is_silent()
	# --- PR 34: piper TTS ---
	_check_tts_chain_editor_exposes_piper_kind()
	_check_tts_chain_editor_renders_piper_then_command_order()
	_check_tts_lines_piper_in_chain_shows_env_hint_when_unconfigured()
	_check_tts_lines_piper_in_chain_configured_hides_env_hint()
	_check_tts_lines_piper_not_in_chain_is_muted_note()
	_check_tts_lines_legacy_core_without_piper_fields_is_silent()
	# --- PR 26: Provider-Onboarding ---
	_check_onboarding_pure_logic()
	_check_onboarding_block_renders_primary_and_chain()
	_check_onboarding_cloud_readiness_rows_render()
	_check_onboarding_cloud_secret_never_leaks_value()
	_check_onboarding_local_first_hint_and_no_auto_cloud_present()
	_check_onboarding_local_first_quick_action_sends_expected_chain()
	_check_onboarding_add_cloud_button_stays_disabled_by_design()
	_check_onboarding_empty_status_renders_dashes()

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


func _check_stt_tts_provider_rows() -> void:
	# PR 6: wenn stt_provider_*-Felder vorhanden sind, rendert die
	# Shell die fünf Resolver-Zeilen (Configured, Active, Availability,
	# Last error, Cloud). Fehlt das Vokabular (alter Core), bleibt die
	# Fallback-Zeile „Core liefert keine stt_provider_*-Felder" stehen.
	var stt_resolver_rows: Dictionary = _row_map(_SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": true,
		"stt_provider_configured": "command",
		"stt_provider_active": "command",
		"stt_provider_availability": "available",
		"stt_provider_last_error": null,
		"stt_provider_cloud": false,
	}))
	_assert(str(stt_resolver_rows.get("Configured", "")) == "command",
		"stt_lines: Configured rendert command")
	_assert(str(stt_resolver_rows.get("Active", "")) == "command",
		"stt_lines: Active rendert command")
	_assert(str(stt_resolver_rows.get("Availability", "")) == "available",
		"stt_lines: Availability rendert available")
	_assert(str(stt_resolver_rows.get("Last error", "")) == "—",
		"stt_lines: Last error null → em-dash")
	_assert(str(stt_resolver_rows.get("Cloud", "")) == "no",
		"stt_lines: Cloud=false → 'no'")

	var tts_resolver_rows: Dictionary = _row_map(_SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": true,
		"auto_speak": true,
		"tts_provider_configured": "command",
		"tts_provider_active": "",
		"tts_provider_availability": "unavailable",
		"tts_provider_last_error": "process_missing",
		"tts_provider_cloud": false,
	}))
	_assert(str(tts_resolver_rows.get("Configured", "")) == "command",
		"tts_lines: Configured rendert command")
	_assert(str(tts_resolver_rows.get("Availability", "")) == "unavailable",
		"tts_lines: Availability rendert unavailable")
	_assert(str(tts_resolver_rows.get("Last error", "")) == "process_missing",
		"tts_lines: Fehlerklasse process_missing wird 1:1 gerendert")

	# Legacy-Core ohne neue Felder → Fallback-Hinweiszeile.
	var stt_legacy: Dictionary = _row_map(_SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": false,
	}))
	var stt_fallback := String(stt_legacy.get("Provider", ""))
	_assert(stt_fallback.find("stt_provider_*") >= 0,
		"stt_lines: alter Core → ehrlicher Fallback-Hinweis")

	var tts_legacy: Dictionary = _row_map(_SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": false,
		"auto_speak": true,
	}))
	var tts_fallback := String(tts_legacy.get("Provider", ""))
	_assert(tts_fallback.find("tts_provider_*") >= 0,
		"tts_lines: alter Core → ehrlicher Fallback-Hinweis")


func _check_privacy_lines_audio_cloud_rollup() -> void:
	# PR 6: sobald stt_provider_cloud oder tts_provider_cloud im Status
	# landen, rendert die Shell zwei separate Cloud-Zeilen je Achse.
	var rows: Dictionary = _row_map(_SectionsRef.privacy_lines({
		"text_provider_cloud": false,
		"stt_provider_cloud": false,
		"tts_provider_cloud": false,
	}))
	_assert(str(rows.get("STT Cloud aktiv", "")) == "no",
		"privacy_lines: STT Cloud=false → 'no'")
	_assert(str(rows.get("TTS Cloud aktiv", "")) == "no",
		"privacy_lines: TTS Cloud=false → 'no'")
	# Die Legacy-Sammelzeile verschwindet, wenn die neuen Felder da sind.
	_assert(not rows.has("STT/TTS Cloud"),
		"privacy_lines: neuer Core ⇒ keine Legacy-Sammelzeile mehr")

	# Alter Core (keine stt_provider_cloud-Felder) → Legacy-Zeile bleibt.
	var legacy: Dictionary = _row_map(_SectionsRef.privacy_lines({}))
	_assert(legacy.has("STT/TTS Cloud"),
		"privacy_lines: alter Core → Legacy-Cloud-Sammelzeile erhalten")


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


# --- PR 7: STT/TTS-Editor + Probe-Routing -------------------------------


func _check_stt_editor_builds_and_syncs() -> void:
	# Der STT-Editor baut sich beim Öffnen idempotent auf und
	# übernimmt den `stt_enabled`-Wert aus dem Status.
	var panel := _spawn_panel()
	panel.apply_status({"stt_enabled": true})
	panel.open_panel()
	var snap: Dictionary = panel.stt_editor_snapshot()
	_assert(bool(snap.get("built", false)),
		"stt-editor: Widgets sind gebaut nach open_panel")
	_assert(bool(snap.get("enabled", false)) == true,
		"stt-editor: enabled-Checkbox spiegelt status.stt_enabled=true")
	_assert(String(snap.get("command", "")) == "",
		"stt-editor: Command-Feld bleibt leer (Secret-Disziplin, nicht aus Status)")
	_despawn_panel(panel)


func _check_tts_editor_builds_and_syncs() -> void:
	var panel := _spawn_panel()
	panel.apply_status({"tts_enabled": true, "auto_speak": true})
	panel.open_panel()
	var snap: Dictionary = panel.tts_editor_snapshot()
	_assert(bool(snap.get("built", false)),
		"tts-editor: Widgets sind gebaut nach open_panel")
	_assert(bool(snap.get("enabled", false)) == true,
		"tts-editor: enabled-Checkbox spiegelt status.tts_enabled=true")
	_assert(bool(snap.get("auto_speak", false)) == true,
		"tts-editor: auto_speak-Checkbox spiegelt status.auto_speak=true")
	_despawn_panel(panel)


func _check_stt_probe_routes_to_stt_label() -> void:
	# Ein `settings_probe_result` mit axis="stt" landet ausschließlich
	# im STT-Label, nicht im Llamafile-Label. So bleibt der Nutzer-
	# Kontext (welche Achse ich gerade diagnostiziere) eindeutig.
	var panel := _spawn_panel()
	panel.open_panel()
	panel.inject_probe_result_for_test({
		"axis": "stt",
		"ok": false,
		"class": "not_configured",
		"message": "axis is enabled but has no command configured",
		"lifecycle": null,
		"in_chain": true,
		"enabled": true,
		"configured": false,
	})
	var stt_snap: Dictionary = panel.stt_editor_snapshot()
	var llf_snap: Dictionary = panel.llamafile_editor_snapshot()
	var stt_text := String(stt_snap.get("probe_status", ""))
	var llf_text := String(llf_snap.get("probe_status", ""))
	_assert(stt_text.find("[not_configured]") >= 0,
		"stt-editor: Probe-Label zeigt Core-class-Tag für STT")
	_assert(llf_text.find("[not_configured]") < 0,
		"llamafile-editor: bleibt unberührt, wenn axis=stt ankommt")
	_despawn_panel(panel)


func _check_tts_probe_routes_to_tts_label() -> void:
	var panel := _spawn_panel()
	panel.open_panel()
	panel.inject_probe_result_for_test({
		"axis": "tts",
		"ok": true,
		"class": "ok",
		"message": "command looks ready (binary present, executable)",
		"lifecycle": null,
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	var tts_snap: Dictionary = panel.tts_editor_snapshot()
	var stt_snap: Dictionary = panel.stt_editor_snapshot()
	var tts_text := String(tts_snap.get("probe_status", ""))
	var stt_text := String(stt_snap.get("probe_status", ""))
	_assert(tts_text.find("[ok]") >= 0,
		"tts-editor: Probe-Label zeigt Core-class-Tag für TTS")
	_assert(stt_text.find("[ok]") < 0,
		"stt-editor: bleibt unberührt, wenn axis=tts ankommt")
	_despawn_panel(panel)


func _check_probe_without_axis_falls_back_to_llamafile() -> void:
	# Backwards-Kompatibilität: ältere Cores schicken kein axis-Feld.
	# Das Ergebnis landet im Llamafile-Label (wie vor PR 7).
	var panel := _spawn_panel()
	panel.open_panel()
	panel.inject_probe_result_for_test({
		"ok": false,
		"class": "path_missing",
		"message": "configured binary path does not exist",
		"lifecycle": "configured",
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	var llf_snap: Dictionary = panel.llamafile_editor_snapshot()
	var probe_text := String(llf_snap.get("probe_status", ""))
	_assert(probe_text.find("[path_missing]") >= 0,
		"llamafile-editor: fällt zurück, wenn axis-Feld fehlt")
	_despawn_panel(panel)


func _check_stt_tts_probe_does_not_leak_command() -> void:
	# PR 7 Secret-Disziplin: die UI darf den konfigurierten Command
	# nicht „nachrendern", auch wenn er hypothetisch im Payload käme.
	var panel := _spawn_panel()
	panel.open_panel()
	var secret_like := "whisper --model sekritmodel --flag=doNotLeak"
	panel.inject_probe_result_for_test({
		"axis": "stt",
		"ok": false,
		"class": "path_missing",
		"message": "configured command binary does not exist",
		"lifecycle": null,
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	var snap: Dictionary = panel.stt_editor_snapshot()
	var probe_text := String(snap.get("probe_status", ""))
	_assert(probe_text.find(secret_like) < 0,
		"stt-editor: Probe-Label enthält keinen synthetischen Command-String")
	_assert(probe_text.find("sekritmodel") < 0,
		"stt-editor: Probe-Label enthält keine Argumente des Command-Strings")
	_despawn_panel(panel)


# --- PR 8: local_http-Editor + Probe-Routing ---------------------------


func _check_local_http_editor_builds_and_syncs() -> void:
	var panel := _spawn_panel()
	panel.apply_status({"local_http_in_chain": true, "local_http_enabled": true})
	panel.open_panel()
	var snap: Dictionary = panel.local_http_editor_snapshot()
	_assert(bool(snap.get("built", false)),
		"local_http-editor: Widgets sind gebaut nach open_panel")
	_assert(bool(snap.get("enabled", false)) == true,
		"local_http-editor: enabled-Checkbox spiegelt status.local_http_enabled=true")
	_assert(String(snap.get("endpoint", "")) == "",
		"local_http-editor: Endpoint-Feld bleibt leer (Secret-Disziplin, nicht aus Status)")
	_despawn_panel(panel)


func _check_local_http_probe_routes_to_local_http_label() -> void:
	# Ein `settings_probe_result` mit axis="local_http" landet im
	# local_http-Label, nicht im Llamafile-/STT-/TTS-Block.
	var panel := _spawn_panel()
	panel.open_panel()
	panel.inject_probe_result_for_test({
		"axis": "local_http",
		"ok": false,
		"class": "http_connect_failed",
		"message": "tcp connect to configured endpoint failed",
		"lifecycle": null,
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	var lh_snap: Dictionary = panel.local_http_editor_snapshot()
	var llf_snap: Dictionary = panel.llamafile_editor_snapshot()
	var lh_text := String(lh_snap.get("probe_status", ""))
	var llf_text := String(llf_snap.get("probe_status", ""))
	_assert(lh_text.find("[http_connect_failed]") >= 0,
		"local_http-editor: Probe-Label zeigt Core-class-Tag")
	_assert(llf_text.find("[http_connect_failed]") < 0,
		"llamafile-editor: bleibt unberührt, wenn axis=local_http ankommt")
	_despawn_panel(panel)


func _check_local_http_probe_scheme_unsupported_does_not_leak() -> void:
	# Die UI darf den konfigurierten Endpoint nicht „nachrendern",
	# auch wenn er hypothetisch im Payload käme. Wir prüfen gegen
	# einen synthetischen, gut erkennbaren String.
	var panel := _spawn_panel()
	panel.open_panel()
	var secret_like := "https://sekrit-host.test/v1/sekritroute"
	panel.inject_probe_result_for_test({
		"axis": "local_http",
		"ok": false,
		"class": "endpoint_scheme_unsupported",
		"message": "endpoint must start with http:// (https:// is not supported in this build)",
		"lifecycle": null,
		"in_chain": true,
		"enabled": true,
		"configured": true,
	})
	var snap: Dictionary = panel.local_http_editor_snapshot()
	var probe_text := String(snap.get("probe_status", ""))
	_assert(probe_text.find(secret_like) < 0,
		"local_http-editor: Probe-Label enthält keinen synthetischen Endpoint-String")
	_assert(probe_text.find("sekritroute") < 0,
		"local_http-editor: Probe-Label enthält keinen Endpoint-Pfad")
	_despawn_panel(panel)


func _check_text_provider_lines_local_http_visibility() -> void:
	# Neuer Core: `local_http_in_chain=true` + `local_http_enabled=true`
	# erzeugt den detaillierten Readout. Fehlendes Feld triggert den
	# Rückfallpfad (alte Cores) — dann keine local_http-Zeile.
	var SectionsRef := load("res://scripts/settings/settings_sections.gd")
	var status_in_chain := {
		"text_provider_configured": "local_http",
		"text_provider_active": "local_http",
		"local_http_in_chain": true,
		"local_http_enabled": true,
		"local_http_configured": true,
	}
	var lines_in_chain: Array = SectionsRef.text_provider_lines(status_in_chain)
	var found_header := false
	var found_enabled := false
	for row in lines_in_chain:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var label := str(row.get("label", ""))
		if label == "local_http":
			found_header = true
		if label == "  enabled":
			found_enabled = true
	_assert(found_header,
		"text_provider_lines: local_http-Header erscheint, wenn in Chain")
	_assert(found_enabled,
		"text_provider_lines: local_http Detailzeilen werden gerendert")

	var status_not_in_chain := {
		"text_provider_configured": "abrain",
		"local_http_in_chain": false,
		"local_http_enabled": false,
	}
	var lines_not_in_chain: Array = SectionsRef.text_provider_lines(status_not_in_chain)
	var mentions_not_in_chain := false
	for row in lines_not_in_chain:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("label", "")) == "local_http":
			mentions_not_in_chain = true
	_assert(mentions_not_in_chain,
		"text_provider_lines: ehrlicher 'nicht in der Chain'-Hinweis für local_http")


# --- PR 9: Text-Provider-Chain-Editor -----------------------------------


func _check_text_chain_editor_builds_and_syncs_from_status() -> void:
	# Core liefert eine Kette aus zwei Kinds: die Shell sollte diese
	# Reihenfolge in den Editor-Rows spiegeln, mit dem dritten
	# bekannten Kind als disabled am Ende.
	var panel := _spawn_panel()
	panel.apply_status({
		"text_provider_chain": ["llamafile_local", "abrain"],
	})
	panel.open_panel()
	var snap: Dictionary = panel.text_chain_editor_snapshot()
	_assert(bool(snap.get("built", false)),
		"text-chain-editor: Widgets sind gebaut nach open_panel")
	var rows: Array = snap.get("rows", [])
	_assert(rows.size() == 3,
		"text-chain-editor: drei bekannte Kinds werden gerendert")
	_assert(
		String(rows[0].get("kind", "")) == "llamafile_local" and bool(rows[0].get("in_chain", false)),
		"text-chain-editor: Status-Kette landet in der Widget-Reihenfolge oben (llamafile_local zuerst)")
	_assert(
		String(rows[1].get("kind", "")) == "abrain" and bool(rows[1].get("in_chain", false)),
		"text-chain-editor: zweiter Status-Eintrag (abrain) folgt")
	_assert(
		String(rows[2].get("kind", "")) == "local_http" and not bool(rows[2].get("in_chain", false)),
		"text-chain-editor: nicht-in-chain-Kind (local_http) steht als disabled am Ende")
	_despawn_panel(panel)


func _check_text_chain_editor_toggle_and_move() -> void:
	# Der Editor muss lokal auf Toggle + Move reagieren, bevor Apply
	# eine IPC-Runde auslöst.
	var panel := _spawn_panel()
	panel.apply_status({"text_provider_chain": ["abrain"]})
	panel.open_panel()
	# Status: [abrain (in), llamafile_local (out), local_http (out)].
	# Aktivieren local_http (Row 2 in den aktuellen Rows).
	panel.simulate_text_chain_toggle_for_test(2, true)
	var snap: Dictionary = panel.text_chain_editor_snapshot()
	var rows: Array = snap.get("rows", [])
	# Nach dem Toggle sollten die in-chain-Einträge oben stehen:
	# abrain bleibt an Position 0, local_http rückt auf Position 1,
	# llamafile_local wird an Position 2 gedrängt (disabled).
	_assert(String(rows[0].get("kind", "")) == "abrain",
		"text-chain-editor: abrain bleibt Primär-Provider nach Toggle")
	_assert(
		String(rows[1].get("kind", "")) == "local_http" and bool(rows[1].get("in_chain", false)),
		"text-chain-editor: neu aktivierter local_http rutscht in den enabled-Block")
	# Jetzt local_http nach oben schieben (soll vor abrain stehen).
	panel.simulate_text_chain_move_for_test(1, -1)
	snap = panel.text_chain_editor_snapshot()
	rows = snap.get("rows", [])
	_assert(String(rows[0].get("kind", "")) == "local_http",
		"text-chain-editor: Up-Move verschiebt local_http an Position 0")
	_assert(String(rows[1].get("kind", "")) == "abrain",
		"text-chain-editor: Abrain rutscht auf Position 1")
	_despawn_panel(panel)


func _check_text_chain_editor_prevents_empty_chain_on_apply() -> void:
	# Wenn der Nutzer alle drei Kinds deaktiviert, darf Apply **keinen**
	# Empty-Request an den Core schicken. Die UI-seitige Absicherung
	# zeigt stattdessen eine kuratierte Meldung; der Core-Validator
	# bleibt Second-Line-of-Defense.
	var panel := _spawn_panel()
	panel.apply_status({"text_provider_chain": ["abrain"]})
	panel.open_panel()
	# Alle Einträge deaktivieren.
	panel.simulate_text_chain_toggle_for_test(0, false)
	var snap: Dictionary = panel.text_chain_editor_snapshot()
	for r in snap.get("rows", []):
		_assert(not bool(r.get("in_chain", false)),
			"text-chain-editor: alle Rows sind nach Toggle deaktiviert (Vorbedingung)")
	# Apply aufrufen; offline reicht, weil wir die „offline"-Meldung
	# hier nicht sehen wollen, sondern die „chain empty"-Absicherung.
	# Wir simulieren das, indem wir den Handler direkt aufrufen —
	# dazu brauchen wir einen echten Button-Press. Der Panel-Controller
	# exponiert keinen direkten Test-Hook für Apply, aber das
	# Apply-Status-Label sollte nach dem Klick die Empty-Meldung tragen.
	# Da wir in dieser SceneTree-only-Umgebung keinen lebenden
	# IpcClient-Autoload haben, greift in `_on_text_chain_apply_pressed`
	# zuerst der `offline`-Zweig. Der Empty-Check kommt davor —
	# wir stellen also sicher, dass der Apply-Snapshot weder „sent"
	# noch „offline" ist, sondern den kuratierten Empty-Hinweis trägt.
	if _panel_text_chain_button_apply(panel) != null:
		_panel_text_chain_button_apply(panel).emit_signal("pressed")
		var post_snap: Dictionary = panel.text_chain_editor_snapshot()
		var apply_status := String(post_snap.get("apply_status", ""))
		_assert(apply_status.find("chain empty") >= 0,
			"text-chain-editor: Apply-Label weist Empty-Chain ehrlich ab")
	_despawn_panel(panel)


func _panel_text_chain_button_apply(panel) -> Button:
	# Suche den „Apply"-Button im text_chain-Editor-Block. Da der
	# Controller die Widget-Referenz nicht exponiert, greifen wir über
	# die Scene-Tree-Struktur zu.
	var candidates: Array[Node] = []
	_collect_buttons_with_text(panel, "Apply", candidates)
	# Der erste „Apply"-Button ist der des Llamafile-Editors — unser
	# Chain-Editor liegt davor (siehe `_render_sections`), also wir
	# suchen den ersten Button innerhalb des obersten Text-Provider-
	# Abschnitts. Bequemer: wir triggern `_on_text_chain_apply_pressed`
	# direkt via interne Methode, aber die ist `_`-prefixed. Nehmen
	# wir den ersten Apply-Button als Approximation — reicht für
	# dieses Smoke-Ziel.
	if candidates.is_empty():
		return null
	return candidates[0] as Button


func _collect_buttons_with_text(node: Node, wanted: String, out: Array[Node]) -> void:
	if node is Button and (node as Button).text == wanted:
		out.append(node)
	for child in node.get_children():
		_collect_buttons_with_text(child, wanted, out)


# --- PR 10: Cloud-HTTP-Editor + Secret-Masking ------------------------


func _check_cloud_http_editor_builds_and_shows_external_warning() -> void:
	var panel := _spawn_panel()
	panel.apply_status({
		"text_provider_chain": ["cloud_http", "abrain"],
		"cloud_http_in_chain": true,
		"cloud_http_enabled": true,
		"cloud_http_configured": false,
		"cloud_http_secret_present": false,
	})
	panel.open_panel()
	var snap: Dictionary = panel.cloud_http_editor_snapshot()
	_assert(bool(snap.get("built", false)),
		"cloud_http-editor: Widgets sind gebaut nach open_panel")
	_assert(bool(snap.get("enabled", false)),
		"cloud_http-editor: enabled-Checkbox spiegelt status.cloud_http_enabled=true")
	var warning := String(snap.get("external_warning", ""))
	_assert(warning.find("extern") >= 0 or warning.find("cloud") >= 0,
		"cloud_http-editor: externer/Cloud-Hinweis ist sichtbar")
	_despawn_panel(panel)


func _check_cloud_http_editor_never_populates_secret_edit_from_status() -> void:
	# Wichtigste Secret-Grenze der UI: selbst wenn der Status
	# `cloud_http_secret_present=true` trägt, darf das LineEdit niemals
	# einen Wert anzeigen. Der Wert kommt ausschließlich vom Nutzer.
	var panel := _spawn_panel()
	panel.apply_status({
		"cloud_http_enabled": true,
		"cloud_http_secret_present": true,
	})
	panel.open_panel()
	var snap: Dictionary = panel.cloud_http_editor_snapshot()
	var secret_edit := String(snap.get("secret_edit_text", ""))
	_assert(secret_edit == "",
		"cloud_http-editor: Secret-Edit bleibt nach Status-Tick leer (kein Rückspiegeln)")
	_despawn_panel(panel)


func _check_cloud_http_editor_secret_present_flag_mirrored_in_status_label() -> void:
	# `cloud_http_secret_present` muss sichtbar sein (als Bool-Flag),
	# aber niemals als Wert.
	var panel := _spawn_panel()
	panel.apply_status({
		"cloud_http_enabled": true,
		"cloud_http_secret_present": true,
	})
	panel.open_panel()
	var with_key: Dictionary = panel.cloud_http_editor_snapshot()
	_assert(String(with_key.get("secret_status", "")).find("saved") >= 0,
		"cloud_http-editor: Statuslabel zeigt 'saved', wenn cloud_http_secret_present=true")
	_despawn_panel(panel)

	var panel2 := _spawn_panel()
	panel2.apply_status({
		"cloud_http_enabled": true,
		"cloud_http_secret_present": false,
	})
	panel2.open_panel()
	var without_key: Dictionary = panel2.cloud_http_editor_snapshot()
	_assert(String(without_key.get("secret_status", "")).find("not set") >= 0,
		"cloud_http-editor: Statuslabel zeigt 'not set', wenn cloud_http_secret_present=false")
	_despawn_panel(panel2)


func _check_cloud_http_editor_save_secret_clears_edit_field() -> void:
	# Nach einem Save-Klick muss das Edit-Feld SOFORT leer sein,
	# damit der Klartext nicht weiter in der UI lebt. Wir simulieren
	# den Save-Pfad direkt (kein IpcClient in der Smoke-Umgebung).
	var panel := _spawn_panel()
	panel.apply_status({"cloud_http_enabled": true})
	panel.open_panel()
	var marker := "sk-smoke-top-secret-marker"
	panel.simulate_cloud_http_save_secret_for_test(marker)
	var snap: Dictionary = panel.cloud_http_editor_snapshot()
	_assert(
		String(snap.get("secret_edit_text", "")) == "",
		"cloud_http-editor: Secret-Edit-Feld ist nach Save sofort geleert")
	_assert(
		String(snap.get("secret_edit_text", "")).find(marker) < 0,
		"cloud_http-editor: Marker taucht nicht mehr im Edit-Feld auf")
	_despawn_panel(panel)


func _check_cloud_http_editor_shows_insecure_hint_for_http_endpoint() -> void:
	# PR 11: sobald der Nutzer einen `http://`-Endpoint eintippt, muss
	# der kleine Insecure-Hint-Label einen klaren Hinweistext zeigen.
	var panel := _spawn_panel()
	panel.apply_status({"cloud_http_enabled": true})
	panel.open_panel()
	panel.simulate_cloud_http_endpoint_input_for_test("http://api.example.invalid:8443/v1")
	var snap: Dictionary = panel.cloud_http_editor_snapshot()
	var hint := String(snap.get("insecure_hint", ""))
	_assert(hint.find("insecure") >= 0 or hint.find("plaintext") >= 0,
		"cloud_http-editor: Insecure-Hint erscheint bei http://-Endpoint")
	_assert(hint.find("https://") >= 0,
		"cloud_http-editor: Hint verweist auf https:// als bevorzugte Alternative")
	_despawn_panel(panel)


func _check_cloud_http_editor_hides_insecure_hint_for_https_endpoint() -> void:
	# PR 11: für `https://` darf der Hint leer sein — dort gibt's
	# nichts zu warnen.
	var panel := _spawn_panel()
	panel.apply_status({"cloud_http_enabled": true})
	panel.open_panel()
	panel.simulate_cloud_http_endpoint_input_for_test("https://api.example.invalid/v1")
	var snap: Dictionary = panel.cloud_http_editor_snapshot()
	_assert(String(snap.get("insecure_hint", "")) == "",
		"cloud_http-editor: Insecure-Hint bleibt bei https://-Endpoint leer")
	_despawn_panel(panel)


# --- PR 13: STT/TTS Chain-Editoren --------------------------------------


func _check_audio_chain_editor_builds_and_syncs_from_status(axis: String) -> void:
	# Core liefert die Chain über `stt_provider_chain` / `tts_provider_chain`.
	# Der Editor muss die genaue Reihenfolge aus dem Status ziehen und
	# bekannte Kinds, die nicht in der Chain stehen, als disabled
	# anhängen. Seit PR 27 hat die STT-Whitelist zwei Kinds
	# (command + whisper_cpp); TTS hat weiterhin ein einziges.
	var panel := _spawn_panel()
	var status := {}
	status["%s_provider_chain" % axis] = ["command"]
	panel.apply_status(status)
	panel.open_panel()
	var snap: Dictionary = panel.audio_chain_editor_snapshot(axis)
	_assert(bool(snap.get("built", false)),
		"%s-chain-editor: Widgets sind gebaut nach open_panel" % axis)
	var rows: Array = snap.get("rows", [])
	# PR 27 gab STT zwei Kinds (command + whisper_cpp). PR 34 gibt
	# TTS ebenfalls zwei Kinds (command + piper). Beide Achsen
	# rendern jetzt zwei Rows.
	_assert(rows.size() == 2,
		"%s-chain-editor: bekannte Kinds werden gerendert (erwartet 2)" % axis)
	_assert(
		String(rows[0].get("kind", "")) == "command"
			and bool(rows[0].get("in_chain", false)),
		"%s-chain-editor: Status-Kette wird gespiegelt (command aktiv als Row 0)" % axis)
	if axis == "stt":
		# whisper_cpp ist nicht in der Chain → Row folgt als disabled.
		_assert(
			String(rows[1].get("kind", "")) == "whisper_cpp"
				and not bool(rows[1].get("in_chain", false)),
			"stt-chain-editor (PR 27): whisper_cpp erscheint als Row 1 mit in_chain=false")
	else:
		# piper ist nicht in der Default-Chain → Row folgt als disabled.
		_assert(
			String(rows[1].get("kind", "")) == "piper"
				and not bool(rows[1].get("in_chain", false)),
			"tts-chain-editor (PR 34): piper erscheint als Row 1 mit in_chain=false")
	_despawn_panel(panel)


func _check_audio_chain_editor_empty_guard(axis: String) -> void:
	# Toggle die einzige Row aus. Apply muss die leere Kette ehrlich
	# blocken, ohne IPC zu involvieren.
	var panel := _spawn_panel()
	var status := {}
	status["%s_provider_chain" % axis] = ["command"]
	panel.apply_status(status)
	panel.open_panel()
	panel.simulate_audio_chain_toggle_for_test(axis, 0, false)
	panel.simulate_audio_chain_apply_for_test(axis)
	var snap: Dictionary = panel.audio_chain_editor_snapshot(axis)
	_assert(
		String(snap.get("apply_status", "")).find("chain empty") >= 0,
		"%s-chain-editor: Apply-Label weist Empty-Chain ehrlich ab" % axis)
	_despawn_panel(panel)


func _check_audio_chain_editor_shows_single_kind_info_hint() -> void:
	# Seit PR 34 haben **beide** Audio-Achsen zwei Kinds (STT:
	# command + whisper_cpp; TTS: command + piper). Der Single-
	# Kind-Info-Hint muss in beiden Editoren leer bleiben, damit
	# keine stale „nur command"-Aussage sichtbar ist.
	var panel := _spawn_panel()
	panel.apply_status({
		"stt_provider_chain": ["command"],
		"tts_provider_chain": ["command"],
	})
	panel.open_panel()
	var tts_info := String(panel.audio_chain_editor_snapshot("tts").get("info_hint", ""))
	_assert(tts_info == "",
		"tts-chain-editor (PR 34): Info-Hint ist leer, weil zwei Kinds verfügbar sind")
	var stt_info := String(panel.audio_chain_editor_snapshot("stt").get("info_hint", ""))
	_assert(stt_info == "",
		"stt-chain-editor (PR 27): Info-Hint ist leer, weil zwei Kinds verfügbar sind")
	_despawn_panel(panel)


func _check_audio_provider_lines_render_chain_field() -> void:
	# Der Readout der STT-/TTS-Section muss die Chain-Zeile zeigen,
	# sobald der Status das Feld trägt.
	var Sections := load("res://scripts/settings/settings_sections.gd")
	var lines: Array = Sections.stt_lines({
		"stt_enabled": true,
		"stt_available": true,
		"stt_provider_configured": "command",
		"stt_provider_active": "command",
		"stt_provider_availability": "available",
		"stt_provider_cloud": false,
		"stt_provider_chain": ["command"],
	})
	var found_chain := false
	for row in lines:
		if String(row.get("label", "")) == "Chain":
			found_chain = true
			_assert(
				String(row.get("value", "")).find("command") >= 0,
				"stt_lines: Chain-Wert zeigt 'command'")
	_assert(found_chain, "stt_lines: `Chain`-Zeile wird gerendert")


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


# --- PR 26: Provider-Onboarding -----------------------------------------


const _OnboardingRef := preload("res://scripts/settings/provider_onboarding.gd")


func _check_onboarding_pure_logic() -> void:
	# primary_provider: active > first(chain) > configured > "".
	var status_active := {
		"text_provider_active": "abrain",
		"text_provider_chain": ["llamafile_local", "abrain"],
		"text_provider_configured": "local_http",
	}
	_assert(_OnboardingRef.primary_provider(status_active) == "abrain",
		"onboarding: primary_provider bevorzugt text_provider_active")
	var status_chain := {
		"text_provider_chain": ["llamafile_local", "abrain"],
		"text_provider_configured": "local_http",
	}
	_assert(_OnboardingRef.primary_provider(status_chain) == "llamafile_local",
		"onboarding: primary_provider fällt auf erstes Chain-Kind zurück")
	var status_configured := {"text_provider_configured": "abrain"}
	_assert(_OnboardingRef.primary_provider(status_configured) == "abrain",
		"onboarding: primary_provider fällt auf text_provider_configured zurück")
	_assert(_OnboardingRef.primary_provider({}) == "",
		"onboarding: primary_provider liefert leeren String bei leerem Status")

	# locality_for: classification stays stable.
	_assert(_OnboardingRef.locality_for("abrain") == _OnboardingRef.LOCALITY_LOCAL,
		"onboarding: abrain ist local")
	_assert(_OnboardingRef.locality_for("llamafile_local") == _OnboardingRef.LOCALITY_LOCAL,
		"onboarding: llamafile_local ist local")
	_assert(_OnboardingRef.locality_for("local_http") == _OnboardingRef.LOCALITY_LOCAL,
		"onboarding: local_http ist local")
	_assert(_OnboardingRef.locality_for("cloud_http") == _OnboardingRef.LOCALITY_CLOUD,
		"onboarding: cloud_http ist cloud")
	_assert(_OnboardingRef.locality_for("mystery_kind") == _OnboardingRef.LOCALITY_UNKNOWN,
		"onboarding: unbekanntes Kind wird als unknown markiert, nie als local/cloud erfunden")

	# chain_with_locality bewahrt Reihenfolge + klassifiziert pro Eintrag.
	var chain := _OnboardingRef.chain_with_locality({
		"text_provider_chain": ["abrain", "cloud_http"],
	})
	_assert(chain.size() == 2,
		"onboarding: chain_with_locality liefert Reihenfolge")
	_assert(String(chain[0]["locality"]) == "local"
			and String(chain[1]["locality"]) == "cloud",
		"onboarding: chain_with_locality markiert local vs cloud korrekt")

	# cloud_http_readiness: Boolean-basiert; leerer Status → alle false.
	var ready_empty := _OnboardingRef.cloud_http_readiness({})
	_assert(not ready_empty["ready"],
		"onboarding: cloud_http_readiness.ready ist false bei leerem Status")
	_assert(not ready_empty["enabled"] and not ready_empty["endpoint_set"]
			and not ready_empty["secret_present"] and not ready_empty["in_chain"],
		"onboarding: cloud_http_readiness defaults sind alle false")

	# add_cloud_disabled_reason folgt der Sanitising-Reihenfolge.
	_assert(_OnboardingRef.add_cloud_disabled_reason({})
			== _OnboardingRef.ADD_CLOUD_DISABLED_REASON_NOT_ENABLED,
		"onboarding: disabled-Grund bei leerem Status nennt not_enabled")
	_assert(_OnboardingRef.add_cloud_disabled_reason({
			"cloud_http_enabled": true,
		}) == _OnboardingRef.ADD_CLOUD_DISABLED_REASON_NO_ENDPOINT,
		"onboarding: disabled-Grund wechselt auf no_endpoint, wenn enabled=true")
	_assert(_OnboardingRef.add_cloud_disabled_reason({
			"cloud_http_enabled": true,
			"cloud_http_configured": true,
		}) == _OnboardingRef.ADD_CLOUD_DISABLED_REASON_NO_SECRET,
		"onboarding: disabled-Grund wechselt auf no_secret, wenn endpoint gesetzt ist")
	_assert(_OnboardingRef.add_cloud_disabled_reason({
			"cloud_http_enabled": true,
			"cloud_http_configured": true,
			"cloud_http_secret_present": true,
			"cloud_http_in_chain": true,
		}) == _OnboardingRef.ADD_CLOUD_DISABLED_REASON_ALREADY_IN_CHAIN,
		"onboarding: disabled-Grund nennt already_in_chain, wenn der Provider bereits drin ist")
	_assert(_OnboardingRef.add_cloud_disabled_reason({
			"cloud_http_enabled": true,
			"cloud_http_configured": true,
			"cloud_http_secret_present": true,
			"cloud_http_in_chain": false,
		}) == "",
		"onboarding: disabled-Grund ist leer, wenn alle Preconditions erfüllt und noch nicht in Chain")

	# Button bleibt per Design disabled, selbst wenn alle Flags grün sind.
	_assert(_OnboardingRef.add_cloud_button_should_stay_disabled({
			"cloud_http_enabled": true,
			"cloud_http_configured": true,
			"cloud_http_secret_present": true,
			"cloud_http_in_chain": false,
		}),
		"onboarding: add-cloud-Button bleibt per Design disabled, auch wenn bereit")

	# LOCAL_FIRST_CHAIN enthält bewusst kein cloud_http.
	_assert(not (_OnboardingRef.LOCAL_FIRST_CHAIN as Array).has("cloud_http"),
		"onboarding: LOCAL_FIRST_CHAIN hat kein cloud_http")
	_assert((_OnboardingRef.LOCAL_FIRST_CHAIN as Array).size() == 3,
		"onboarding: LOCAL_FIRST_CHAIN besteht aus drei Kinds")


func _check_onboarding_block_renders_primary_and_chain() -> void:
	var panel := _spawn_panel()
	panel.apply_status({
		"text_provider_active": "abrain",
		"text_provider_chain": ["abrain", "cloud_http"],
	})
	panel.open_panel()
	var snap: Dictionary = panel.provider_onboarding_snapshot()
	_assert(bool(snap.get("built", false)),
		"onboarding-block: Widgets gebaut nach open_panel")
	var primary := String(snap.get("primary", ""))
	_assert(primary.find("abrain") >= 0 and primary.find("local") >= 0,
		"onboarding-block: primary zeigt 'abrain [local]'")
	var chain := String(snap.get("chain", ""))
	_assert(chain.find("abrain") >= 0 and chain.find("cloud_http") >= 0,
		"onboarding-block: chain zeigt beide Kinds")
	_assert(chain.find("cloud") >= 0,
		"onboarding-block: cloud_http wird explizit als cloud markiert")
	_despawn_panel(panel)


func _check_onboarding_cloud_readiness_rows_render() -> void:
	var panel := _spawn_panel()
	panel.apply_status({
		"cloud_http_enabled": true,
		"cloud_http_configured": false,
		"cloud_http_secret_present": false,
		"cloud_http_in_chain": false,
		"text_provider_chain": ["abrain"],
	})
	panel.open_panel()
	var snap: Dictionary = panel.provider_onboarding_snapshot()
	var rows: Array = snap.get("cloud_rows", [])
	var by_label: Dictionary = {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			by_label[String(row.get("label", ""))] = String(row.get("value", ""))
	_assert(String(by_label.get("cloud_http enabled", "")) == "yes",
		"onboarding-cloud-rows: enabled=yes rendert")
	_assert(String(by_label.get("cloud_http endpoint", "")) == "missing",
		"onboarding-cloud-rows: endpoint=missing rendert als klarer First-Run-Hinweis")
	_assert(String(by_label.get("cloud_http api key", "")) == "not set",
		"onboarding-cloud-rows: api key=not set rendert ohne Wert")
	_assert(String(by_label.get("cloud_http in chain", "")) == "no",
		"onboarding-cloud-rows: in chain=no rendert")
	var ready := String(by_label.get("cloud_http ready", ""))
	_assert(ready.find("first-run") >= 0 or ready.find("pending") >= 0,
		"onboarding-cloud-rows: ready-Zeile weist ehrlich auf First-Run-Schritte hin")
	_despawn_panel(panel)


func _check_onboarding_cloud_secret_never_leaks_value() -> void:
	# Auch bei secret_present=true darf die Onboarding-Sektion keinen
	# Key-Wert rendern — sie zeigt nur das Boolean-Präsent-Label.
	var panel := _spawn_panel()
	panel.apply_status({
		"cloud_http_enabled": true,
		"cloud_http_configured": true,
		"cloud_http_secret_present": true,
		"cloud_http_in_chain": false,
	})
	panel.open_panel()
	var snap: Dictionary = panel.provider_onboarding_snapshot()
	var rows: Array = snap.get("cloud_rows", [])
	var api_key_value := ""
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and String(row.get("label", "")) == "cloud_http api key":
			api_key_value = String(row.get("value", ""))
	_assert(api_key_value == "present",
		"onboarding-cloud-rows: api key-Zeile zeigt nur 'present', nie einen Wert")
	_assert(api_key_value.find("sk-") < 0 and api_key_value.find("Bearer") < 0,
		"onboarding-cloud-rows: keine Key-Artefakte im Wert")
	_despawn_panel(panel)


func _check_onboarding_local_first_hint_and_no_auto_cloud_present() -> void:
	# Die beiden Explain-Texte müssen als Konstanten im UI liegen und
	# stabil referenzierbar sein.
	_assert(_OnboardingRef.LOCAL_FIRST_HINT_TEXT.find("lokal") >= 0
			or _OnboardingRef.LOCAL_FIRST_HINT_TEXT.find("local") >= 0,
		"onboarding: local-first Hinweis adressiert Lokalität")
	_assert(_OnboardingRef.NO_AUTO_CLOUD_TEXT.find("automatisch") >= 0,
		"onboarding: no-auto-cloud Hinweis sagt 'automatisch'")
	_assert(_OnboardingRef.NO_AUTO_CLOUD_TEXT.find("cloud_http") >= 0,
		"onboarding: no-auto-cloud Hinweis nennt cloud_http explizit")


func _check_onboarding_local_first_quick_action_sends_expected_chain() -> void:
	# Smoke simuliert den Button-Klick ohne IpcClient. Wir prüfen:
	#   (a) die vom Helfer bereitgestellte Chain ist die kuratierte
	#       lokale Liste (kein cloud_http).
	#   (b) der Status-Label-Flow setzt "sent".
	var panel := _spawn_panel()
	panel.apply_status({"text_provider_chain": ["abrain"]})
	panel.open_panel()
	var sent: Array = panel.simulate_local_first_chain_for_test(null)
	_assert(sent.size() == 3,
		"onboarding-quick-action: local-first sendet drei Kinds")
	_assert(String(sent[0]) == "llamafile_local"
			and String(sent[1]) == "local_http"
			and String(sent[2]) == "abrain",
		"onboarding-quick-action: local-first Reihenfolge ist llamafile_local → local_http → abrain")
	_assert(not sent.has("cloud_http"),
		"onboarding-quick-action: local-first enthält kein cloud_http")
	var snap: Dictionary = panel.provider_onboarding_snapshot()
	_assert(String(snap.get("local_first_status", "")) == "sent",
		"onboarding-quick-action: Status-Label zeigt 'sent' nach Klick")
	_despawn_panel(panel)


func _check_onboarding_add_cloud_button_stays_disabled_by_design() -> void:
	# Auch wenn alle Flags grün sind, bleibt der „Add cloud_http"-Button
	# disabled. PR 26 legt keine Auto-Aktivierung nahe.
	var panel := _spawn_panel()
	panel.apply_status({
		"cloud_http_enabled": true,
		"cloud_http_configured": true,
		"cloud_http_secret_present": true,
		"cloud_http_in_chain": false,
		"text_provider_chain": ["abrain"],
	})
	panel.open_panel()
	var snap: Dictionary = panel.provider_onboarding_snapshot()
	_assert(bool(snap.get("add_cloud_disabled", false)),
		"onboarding: Add-cloud-Button bleibt disabled trotz aller grünen Flags")
	var reason := String(snap.get("add_cloud_reason", ""))
	_assert(reason != "",
		"onboarding: Disabled-Grund ist immer sichtbar (auch wenn ready)")
	_despawn_panel(panel)


func _check_onboarding_empty_status_renders_dashes() -> void:
	var panel := _spawn_panel()
	panel.apply_status({})
	panel.open_panel()
	var snap: Dictionary = panel.provider_onboarding_snapshot()
	_assert(String(snap.get("primary", "")) == "—",
		"onboarding: leerer Status rendert primary als dash, ohne Crash")
	_assert(String(snap.get("chain", "")) == "—",
		"onboarding: leerer Status rendert chain als dash, ohne Crash")
	_despawn_panel(panel)


# --- PR 27: whisper_cpp STT --------------------------------------------


func _check_stt_chain_editor_exposes_whisper_cpp_kind() -> void:
	# Der Chain-Editor muss beide STT-Kinds (command + whisper_cpp) als
	# Rows zeigen, auch wenn die aktive Chain nur `command` ist.
	# whisper_cpp wird dann als disabled-Row angehängt.
	var panel := _spawn_panel()
	panel.apply_status({"stt_provider_chain": ["command"]})
	panel.open_panel()
	var snap: Dictionary = panel.audio_chain_editor_snapshot("stt")
	_assert(bool(snap.get("built", false)),
		"stt-chain-editor (PR 27): Widgets gebaut")
	var rows: Array = snap.get("rows", [])
	var kinds_found: Array = []
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			kinds_found.append(String(row.get("kind", "")))
	_assert("command" in kinds_found,
		"stt-chain-editor (PR 27): command ist als Row sichtbar")
	_assert("whisper_cpp" in kinds_found,
		"stt-chain-editor (PR 27): whisper_cpp ist als Row sichtbar")
	_despawn_panel(panel)


func _check_stt_chain_editor_renders_whisper_cpp_then_command_order() -> void:
	# Wenn die aktive Chain `["whisper_cpp", "command"]` ist, muss der
	# Editor diese Reihenfolge (whisper_cpp oben, command darunter)
	# spiegeln — in-Chain-Kinds vor nicht-in-Chain-Kinds.
	var panel := _spawn_panel()
	panel.apply_status({
		"stt_provider_chain": ["whisper_cpp", "command"],
		"stt_whisper_cpp_in_chain": true,
		"stt_whisper_cpp_configured": true,
	})
	panel.open_panel()
	var snap: Dictionary = panel.audio_chain_editor_snapshot("stt")
	var rows: Array = snap.get("rows", [])
	_assert(rows.size() >= 2,
		"stt-chain-editor (PR 27): beide Kinds werden als Rows gerendert")
	var first_kind := String((rows[0] as Dictionary).get("kind", ""))
	var second_kind := String((rows[1] as Dictionary).get("kind", ""))
	_assert(first_kind == "whisper_cpp",
		"stt-chain-editor (PR 27): whisper_cpp ist Row 0, wenn primary in Chain")
	_assert(second_kind == "command",
		"stt-chain-editor (PR 27): command ist Row 1 im Fallback-Setup")
	_assert(bool((rows[0] as Dictionary).get("in_chain", false)),
		"stt-chain-editor (PR 27): whisper_cpp-Row trägt in_chain=true")
	_assert(bool((rows[1] as Dictionary).get("in_chain", false)),
		"stt-chain-editor (PR 27): command-Row trägt in_chain=true (beide aktiv)")
	_despawn_panel(panel)


func _check_stt_lines_whisper_cpp_in_chain_shows_env_hint_when_unconfigured() -> void:
	# stt_lines rendert beim in-chain + unconfigured-Fall einen
	# expliziten SMOLIT_STT_WHISPER_CPP_CMD-Hinweis.
	var lines: Array = _SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": false,
		"stt_provider_configured": "whisper_cpp",
		"stt_provider_active": "",
		"stt_provider_availability": "unavailable",
		"stt_provider_last_error": "not_configured",
		"stt_provider_cloud": false,
		"stt_provider_chain": ["whisper_cpp"],
		"stt_whisper_cpp_in_chain": true,
		"stt_whisper_cpp_configured": false,
	})
	var values := _row_map(lines)
	_assert(values.has("whisper_cpp"),
		"stt_lines (PR 27): whisper_cpp-Block wird gerendert, wenn in Chain")
	_assert(String(values.get("whisper_cpp", "")) == "in Chain",
		"stt_lines (PR 27): whisper_cpp-Row markiert 'in Chain'")
	_assert(String(values.get("  configured (command set)", "")) == "no",
		"stt_lines (PR 27): configured=no, wenn SMOLIT_STT_WHISPER_CPP_CMD nicht gesetzt ist")
	_assert(String(values.get("  hint", "")).find("SMOLIT_STT_WHISPER_CPP_CMD") >= 0,
		"stt_lines (PR 27): env-Hinweis nennt SMOLIT_STT_WHISPER_CPP_CMD explizit")


func _check_stt_lines_whisper_cpp_in_chain_configured_hides_env_hint() -> void:
	# Wenn whisper_cpp in Chain UND configured ist, darf der Hint nicht
	# mehr erscheinen — nur die Configured-Yes-Zeile.
	var lines: Array = _SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": true,
		"stt_provider_configured": "whisper_cpp",
		"stt_provider_active": "",
		"stt_provider_availability": "available",
		"stt_provider_cloud": false,
		"stt_provider_chain": ["whisper_cpp"],
		"stt_whisper_cpp_in_chain": true,
		"stt_whisper_cpp_configured": true,
	})
	var values := _row_map(lines)
	_assert(String(values.get("  configured (command set)", "")) == "yes",
		"stt_lines (PR 27): configured=yes, wenn SMOLIT_STT_WHISPER_CPP_CMD gesetzt ist")
	_assert(not values.has("  hint"),
		"stt_lines (PR 27): env-Hinweis entfällt, wenn configured=yes")


func _check_stt_lines_whisper_cpp_not_in_chain_is_muted_note() -> void:
	# Kind in der Whitelist, aber nicht in der aktiven Chain.
	var lines: Array = _SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": true,
		"stt_provider_configured": "command",
		"stt_provider_active": "command",
		"stt_provider_availability": "available",
		"stt_provider_cloud": false,
		"stt_provider_chain": ["command"],
		"stt_whisper_cpp_in_chain": false,
		"stt_whisper_cpp_configured": false,
	})
	var values := _row_map(lines)
	var whisper_row := String(values.get("whisper_cpp", ""))
	_assert(whisper_row.find("nicht in der Chain") >= 0,
		"stt_lines (PR 27): whisper_cpp-Row markiert 'nicht in der Chain' als muted")


func _check_stt_lines_legacy_core_without_whisper_cpp_fields_is_silent() -> void:
	# Ältere Cores, die die beiden PR-27-Booleans nicht kennen, dürfen
	# **keine** whisper_cpp-Zeile rendern — sonst würde die UI einen
	# Zustand implizieren, den der Core nicht bestätigt.
	var lines: Array = _SectionsRef.stt_lines({
		"stt_enabled": true,
		"stt_available": true,
		"stt_provider_configured": "command",
		"stt_provider_active": "command",
		"stt_provider_availability": "available",
		"stt_provider_cloud": false,
		"stt_provider_chain": ["command"],
	})
	var values := _row_map(lines)
	_assert(not values.has("whisper_cpp"),
		"stt_lines (PR 27): ältere Cores ohne stt_whisper_cpp_* bleiben still")


# --- PR 34: piper TTS ---------------------------------------------------


func _check_tts_chain_editor_exposes_piper_kind() -> void:
	# Der Chain-Editor muss beide TTS-Kinds (command + piper) als
	# Rows zeigen, auch wenn die aktive Chain nur `command` ist.
	# piper wird dann als disabled-Row angehängt.
	var panel := _spawn_panel()
	panel.apply_status({"tts_provider_chain": ["command"]})
	panel.open_panel()
	var snap: Dictionary = panel.audio_chain_editor_snapshot("tts")
	_assert(bool(snap.get("built", false)),
		"tts-chain-editor (PR 34): Widgets gebaut")
	var rows: Array = snap.get("rows", [])
	var kinds_found: Array = []
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			kinds_found.append(String(row.get("kind", "")))
	_assert("command" in kinds_found,
		"tts-chain-editor (PR 34): command ist als Row sichtbar")
	_assert("piper" in kinds_found,
		"tts-chain-editor (PR 34): piper ist als Row sichtbar")
	_despawn_panel(panel)


func _check_tts_chain_editor_renders_piper_then_command_order() -> void:
	# Wenn die aktive Chain `["piper", "command"]` ist, muss der
	# Editor diese Reihenfolge (piper oben, command darunter)
	# spiegeln — in-Chain-Kinds vor nicht-in-Chain-Kinds.
	var panel := _spawn_panel()
	panel.apply_status({
		"tts_provider_chain": ["piper", "command"],
		"tts_piper_in_chain": true,
		"tts_piper_configured": true,
	})
	panel.open_panel()
	var snap: Dictionary = panel.audio_chain_editor_snapshot("tts")
	var rows: Array = snap.get("rows", [])
	_assert(rows.size() >= 2,
		"tts-chain-editor (PR 34): beide Kinds werden als Rows gerendert")
	var first_kind := String((rows[0] as Dictionary).get("kind", ""))
	var second_kind := String((rows[1] as Dictionary).get("kind", ""))
	_assert(first_kind == "piper",
		"tts-chain-editor (PR 34): piper ist Row 0, wenn primary in Chain")
	_assert(second_kind == "command",
		"tts-chain-editor (PR 34): command ist Row 1 im Fallback-Setup")
	_assert(bool((rows[0] as Dictionary).get("in_chain", false)),
		"tts-chain-editor (PR 34): piper-Row trägt in_chain=true")
	_assert(bool((rows[1] as Dictionary).get("in_chain", false)),
		"tts-chain-editor (PR 34): command-Row trägt in_chain=true (beide aktiv)")
	_despawn_panel(panel)


func _check_tts_lines_piper_in_chain_shows_env_hint_when_unconfigured() -> void:
	# tts_lines rendert beim in-chain + unconfigured-Fall einen
	# expliziten SMOLIT_TTS_PIPER_CMD-Hinweis.
	var lines: Array = _SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": false,
		"auto_speak": true,
		"tts_provider_configured": "piper",
		"tts_provider_active": "",
		"tts_provider_availability": "unavailable",
		"tts_provider_last_error": "not_configured",
		"tts_provider_cloud": false,
		"tts_provider_chain": ["piper"],
		"tts_piper_in_chain": true,
		"tts_piper_configured": false,
	})
	var values := _row_map(lines)
	_assert(values.has("piper"),
		"tts_lines (PR 34): piper-Block wird gerendert, wenn in Chain")
	_assert(String(values.get("piper", "")) == "in Chain",
		"tts_lines (PR 34): piper-Row markiert 'in Chain'")
	_assert(String(values.get("  configured (command set)", "")) == "no",
		"tts_lines (PR 34): configured=no, wenn SMOLIT_TTS_PIPER_CMD nicht gesetzt ist")
	_assert(String(values.get("  hint", "")).find("SMOLIT_TTS_PIPER_CMD") >= 0,
		"tts_lines (PR 34): env-Hinweis nennt SMOLIT_TTS_PIPER_CMD explizit")


func _check_tts_lines_piper_in_chain_configured_hides_env_hint() -> void:
	# Wenn piper in Chain UND configured ist, darf der Hint nicht
	# mehr erscheinen — nur die Configured-Yes-Zeile.
	var lines: Array = _SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": true,
		"auto_speak": true,
		"tts_provider_configured": "piper",
		"tts_provider_active": "",
		"tts_provider_availability": "available",
		"tts_provider_cloud": false,
		"tts_provider_chain": ["piper"],
		"tts_piper_in_chain": true,
		"tts_piper_configured": true,
	})
	var values := _row_map(lines)
	_assert(String(values.get("  configured (command set)", "")) == "yes",
		"tts_lines (PR 34): configured=yes, wenn SMOLIT_TTS_PIPER_CMD gesetzt ist")
	_assert(not values.has("  hint"),
		"tts_lines (PR 34): env-Hinweis entfällt, wenn configured=yes")


func _check_tts_lines_piper_not_in_chain_is_muted_note() -> void:
	# Kind in der Whitelist, aber nicht in der aktiven Chain.
	var lines: Array = _SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": true,
		"auto_speak": true,
		"tts_provider_configured": "command",
		"tts_provider_active": "command",
		"tts_provider_availability": "available",
		"tts_provider_cloud": false,
		"tts_provider_chain": ["command"],
		"tts_piper_in_chain": false,
		"tts_piper_configured": false,
	})
	var values := _row_map(lines)
	var piper_row := String(values.get("piper", ""))
	_assert(piper_row.find("nicht in der Chain") >= 0,
		"tts_lines (PR 34): piper-Row markiert 'nicht in der Chain' als muted")


func _check_tts_lines_legacy_core_without_piper_fields_is_silent() -> void:
	# Ältere Cores, die die beiden PR-34-Booleans nicht kennen, dürfen
	# **keine** piper-Zeile rendern — sonst würde die UI einen
	# Zustand implizieren, den der Core nicht bestätigt.
	var lines: Array = _SectionsRef.tts_lines({
		"tts_enabled": true,
		"tts_available": true,
		"auto_speak": true,
		"tts_provider_configured": "command",
		"tts_provider_active": "command",
		"tts_provider_availability": "available",
		"tts_provider_cloud": false,
		"tts_provider_chain": ["command"],
	})
	var values := _row_map(lines)
	_assert(not values.has("piper"),
		"tts_lines (PR 34): ältere Cores ohne tts_piper_* bleiben still")
