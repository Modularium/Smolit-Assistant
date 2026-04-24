extends RefCounted
## Settings-Shell (Phase 8c PR 3) — pure Helfer für die read-only
## Abschnitte.
##
## Dieses Modul trägt nur die Struktur und die defensive Formatierung.
## Es kennt kein UI-Node, kein IPC und keine Business-Logik:
##
##   * SectionId + `all_sections()` definieren die sichtbaren Bereiche
##     und ihre feste Reihenfolge.
##   * `label_for()` / `placeholder_for()` liefern deutschsprachige
##     Shell-Texte pro Bereich.
##   * Die `*_lines()`-Helfer nehmen den zuletzt gesehenen
##     `StatusPayload` (ein Dictionary) und geben eine flache Liste
##     von `{label, value, muted}`-Rows zurück. Ein leeres oder
##     unvollständiges Payload crasht **nicht** — fehlende Felder
##     werden als `—` gerendert.
##
## Ausdrücklich *nicht* Teil dieses Moduls:
##   * Keine Schreibaktionen, keine Provider-Entscheidungslogik.
##   * Kein Secrets-Pfad — das Settings-Panel ist bewusst Shell.
##   * Keine neuen StatusPayload-Felder — nur vorhandenes Vokabular
##     (siehe `docs/api.md` §2.3) wird defensiv angezeigt.

class_name SettingsSections

enum SectionId {
	GENERAL,
	PRESENCE_UI,
	TEXT_PROVIDER,
	STT,
	TTS,
	PRIVACY,
	CONNECTION,
}

const _DASH: String = "—"

const _SECTION_ORDER: Array = [
	SectionId.GENERAL,
	SectionId.PRESENCE_UI,
	SectionId.TEXT_PROVIDER,
	SectionId.STT,
	SectionId.TTS,
	SectionId.PRIVACY,
	SectionId.CONNECTION,
]


## Deutscher Anzeigename pro Abschnitt. Bewusst knapp.
static func label_for(section: int) -> String:
	match section:
		SectionId.GENERAL: return "General"
		SectionId.PRESENCE_UI: return "Presence / UI"
		SectionId.TEXT_PROVIDER: return "Text Provider"
		SectionId.STT: return "STT"
		SectionId.TTS: return "TTS"
		SectionId.PRIVACY: return "Privacy / Cloud / Data handling"
		SectionId.CONNECTION: return "Connection / Status"
		_: return "unknown"


## Kurzer, ehrlicher Shell-Hinweis unter dem Section-Titel. Der
## Hinweis benennt, was diese Shell **schon** sichtbar macht und was
## noch fehlt — keine versprochenen Editoren.
static func placeholder_for(section: int) -> String:
	match section:
		SectionId.GENERAL:
			return "Allgemeine Shell — vollständige Optionen folgen in späteren PRs."
		SectionId.PRESENCE_UI:
			return "Anzeige der aktuellen Presence-/UI-Stellgrößen (read-only)."
		SectionId.TEXT_PROVIDER:
			return "Read-only Blick auf die aktuelle Text-Provider-Kette. Keine Pfad-/Secret-/Start-Eingabe in dieser Shell."
		SectionId.STT:
			return "Status des STT-Kommandos. Provider-Auswahl kommt in einem Folge-PR."
		SectionId.TTS:
			return "Status des TTS-Kommandos und Auto-Speak. Provider-Auswahl kommt in einem Folge-PR."
		SectionId.PRIVACY:
			return "Cloud-Kennzeichnung ist sichtbar. Einwilligungs-Flow und Offline-Only-Schalter folgen (kein Cloud-Pfad heute)."
		SectionId.CONNECTION:
			return "Read-only Diagnose: IPC, Interaction-Backend, Accessibility-Probe."
		_:
			return ""


## Reihenfolge der Abschnitte, in der das Panel sie rendern soll.
static func all_sections() -> Array:
	return _SECTION_ORDER.duplicate()


## Canonical, maschinenlesbarer Slug pro Abschnitt — praktisch für
## den Smoke-Test und spätere Anchor-Navigation.
static func slug_for(section: int) -> String:
	match section:
		SectionId.GENERAL: return "general"
		SectionId.PRESENCE_UI: return "presence_ui"
		SectionId.TEXT_PROVIDER: return "text_provider"
		SectionId.STT: return "stt"
		SectionId.TTS: return "tts"
		SectionId.PRIVACY: return "privacy"
		SectionId.CONNECTION: return "connection"
		_: return "unknown"


# --- Zeilen-Renderer ------------------------------------------------------

## Gemeinsames Row-Format. `muted == true` → Renderer darf
## zurückgenommene Optik wählen (z. B. niedrigere Alpha), ändert
## aber nichts am Textinhalt.
static func _row(label: String, value: String, muted: bool = false) -> Dictionary:
	return {
		"label": label,
		"value": value,
		"muted": muted,
	}


## General: heute nur App-Name und ein ehrliches Shell-Marker-Feld.
## Kein echter Versions-String — der Core veröffentlicht aktuell keine
## Version in StatusPayload, und wir erfinden hier nichts.
static func general_lines(_status: Dictionary) -> Array:
	return [
		_row("App", "Smolit Assistant UI"),
		_row("Settings", "Shell MVP — Read-only"),
	]


## Presence / UI: was die UI heute lokal über sich selbst verrät.
## Werte kommen als optionales `extras`-Dictionary rein (z. B.
## aktueller Visual-Action-Mode als String aus `main.gd`).
static func presence_ui_lines(extras: Dictionary) -> Array:
	var lines: Array = []
	var visual_mode := str(extras.get("visual_action_mode", ""))
	lines.append(_row("Visual Action Mode",
		visual_mode if visual_mode != "" else _DASH,
		visual_mode == "",
	))
	var presence_mode := str(extras.get("presence_mode", ""))
	lines.append(_row("Presence Mode",
		presence_mode if presence_mode != "" else _DASH,
		presence_mode == "",
	))
	lines.append(_row("Avatar Appearance",
		"wird in Dev-Controls und lokalen Preferences gepflegt (res: user://smolit_ui.cfg)",
		true,
	))
	return lines


## Text Provider: die fünf klassischen `text_provider_*`-Felder aus
## `StatusPayload` (api.md §2.3) plus die PR-4-Vertiefung
## (`text_provider_chain` als sichtbare Fallback-Reihenfolge und ein
## dedizierter `llamafile_local`-Block mit Lifecycle / Mode / Idle-
## Timeout, wenn der Provider in der Kette steht).
##
## Jedes Feld wird defensiv gelesen; fehlende Felder werden als `—`
## gerendert, ohne den Abschnitt zu bricken. Ältere Cores, die die
## PR-4-Felder noch nicht kennen, bleiben also lesbar — die neuen
## Zeilen kommen dann schlicht mit Dash-Werten.
static func text_provider_lines(status: Dictionary) -> Array:
	var lines: Array = []
	lines.append(_row("Configured",
		_stringify_or_dash(status, "text_provider_configured")))
	lines.append(_row("Active",
		_stringify_or_dash(status, "text_provider_active")))
	# Chain (PR 4): wenn vorhanden, als „→"-getrennte Reihenfolge
	# rendern. Fehlt das Feld (älterer Core), zeigen wir einen Dash
	# und markieren die Zeile als muted.
	var chain_raw: Variant = status.get("text_provider_chain", null)
	if typeof(chain_raw) == TYPE_ARRAY and (chain_raw as Array).size() > 0:
		var chain_names: PackedStringArray = PackedStringArray()
		for entry in chain_raw:
			chain_names.append(str(entry))
		lines.append(_row("Chain", " → ".join(chain_names)))
	else:
		lines.append(_row("Chain", _DASH, true))
	lines.append(_row("Availability",
		_stringify_or_dash(status, "text_provider_availability")))
	var last_error_raw: Variant = status.get("text_provider_last_error", null)
	if last_error_raw == null:
		lines.append(_row("Last error", _DASH, true))
	else:
		lines.append(_row("Last error", str(last_error_raw)))
	# `text_provider_cloud` ist ein optionaler Bool. Fehlt das Feld,
	# zeigen wir defensiv `no` — kein versehentliches `yes`.
	var cloud := _bool_or_default(status, "text_provider_cloud", false)
	lines.append(_row("Cloud", "yes" if cloud else "no",
		not status.has("text_provider_cloud")))
	# llamafile-Sichtbarkeit (PR 4). Wir unterscheiden dreistufig:
	#   * Feld `llamafile_in_chain` fehlt → alter Core, nur ein
	#     zurückhaltender Sammelhinweis wie bisher.
	#   * `llamafile_in_chain=false` → ehrlich „nicht in der Kette".
	#   * `llamafile_in_chain=true` → Lifecycle / Mode / Idle-Timeout /
	#     Configured-Flag defensiv rendern.
	if status.has("llamafile_in_chain"):
		var in_chain := _bool_or_default(status, "llamafile_in_chain", false)
		if in_chain:
			lines.append(_row("llamafile_local", "in Chain"))
			lines.append(_row("  lifecycle",
				_stringify_or_dash(status, "llamafile_lifecycle")))
			lines.append(_row("  mode",
				_stringify_or_dash(status, "llamafile_mode")))
			lines.append(_row("  idle timeout",
				_stringify_or_dash(status, "llamafile_idle_timeout_seconds")))
			lines.append(_row("  enabled",
				_bool_label(status, "llamafile_enabled"),
				not status.has("llamafile_enabled")))
			lines.append(_row("  configured (path set)",
				_bool_label(status, "llamafile_configured"),
				not status.has("llamafile_configured")))
		else:
			var note := "nicht in der Chain."
			if _bool_or_default(status, "llamafile_enabled", false):
				note = "enabled (via SMOLIT_LLAMAFILE_ENABLED), aber nicht in der Chain — Kette via SMOLIT_TEXT_PROVIDER_CHAIN ergänzen."
			lines.append(_row("llamafile_local", note, true))
	else:
		# Rückfallmodus für alte Cores: der zurückhaltende Sammelhinweis
		# aus PR 3 bleibt stehen, damit ältere Setups ohne Regression
		# weiterlesen können.
		var configured := str(status.get("text_provider_configured", ""))
		var active := str(status.get("text_provider_active", ""))
		var llamafile_note := "llamafile_local als lokaler Runtime-Fallback verfügbar (via Core-Config)."
		if configured == "llamafile_local" or active == "llamafile_local":
			llamafile_note = "llamafile_local läuft als aktiver/konfigurierter Text-Provider."
		lines.append(_row("Local fallback", llamafile_note, true))
	# local_http-Sichtbarkeit (PR 8). Gleiche dreistufige Logik wie
	# für llamafile: fehlt das Feld, bleibt der Abschnitt still; ist
	# der Provider in der Kette, rendern wir ein paar defensive
	# Detail-Zeilen; ist er nicht in der Kette, zeigen wir einen
	# ehrlichen Hinweis (keine Fantasiedaten).
	if status.has("local_http_in_chain"):
		var lh_in_chain := _bool_or_default(status, "local_http_in_chain", false)
		if lh_in_chain:
			lines.append(_row("local_http", "in Chain"))
			lines.append(_row("  enabled",
				_bool_label(status, "local_http_enabled"),
				not status.has("local_http_enabled")))
			lines.append(_row("  configured (endpoint set)",
				_bool_label(status, "local_http_configured"),
				not status.has("local_http_configured")))
		else:
			var lh_note := "nicht in der Chain."
			if _bool_or_default(status, "local_http_enabled", false):
				lh_note = "enabled (via SMOLIT_LOCAL_HTTP_ENABLED), aber nicht in der Chain — Kette via SMOLIT_TEXT_PROVIDER_CHAIN ergänzen."
			lines.append(_row("local_http", lh_note, true))
	return lines


## STT: Legacy-Feature-Flags (enabled/available) **plus** die neuen
## `stt_provider_*`-Felder aus PR 6. Die Resolver-Sicht rendert sich
## nur, wenn das Core-Vokabular bekannt ist — alte Cores landen
## stillschweigend auf dem Legacy-Minimalpfad. Seit PR 27
## zusätzlich eine dreistufige whisper_cpp-Sichtbarkeit (analog zu
## llamafile_local / local_http in der Text-Achse).
static func stt_lines(status: Dictionary) -> Array:
	var lines: Array = []
	lines.append(_row("Enabled", _bool_label(status, "stt_enabled"),
		not status.has("stt_enabled")))
	lines.append(_row("Available", _bool_label(status, "stt_available"),
		not status.has("stt_available")))
	if status.has("stt_provider_configured"):
		lines.append_array(_audio_provider_lines(status, "stt_provider"))
	else:
		lines.append(_row("Provider",
			"Core liefert keine stt_provider_*-Felder (alter Build).",
			true))
	# PR 27 — whisper_cpp-Sichtbarkeit. Dreistufig, wie bei
	# llamafile_local in der Text-Achse:
	#   * `stt_whisper_cpp_in_chain` fehlt → alter Core, kein Hinweis.
	#   * `stt_whisper_cpp_in_chain = false` → ehrlich „nicht in Chain".
	#   * `stt_whisper_cpp_in_chain = true` → configured-Flag + env-Hinweis
	#     bei Bedarf.
	if status.has("stt_whisper_cpp_in_chain"):
		var wc_in_chain := _bool_or_default(status, "stt_whisper_cpp_in_chain", false)
		if wc_in_chain:
			lines.append(_row("whisper_cpp", "in Chain"))
			var wc_configured := _bool_or_default(
				status, "stt_whisper_cpp_configured", false,
			)
			lines.append(_row("  configured (command set)",
				"yes" if wc_configured else "no",
				not wc_configured))
			if not wc_configured:
				lines.append(_row("  hint",
					"command not set — configure via SMOLIT_STT_WHISPER_CPP_CMD",
					true))
		else:
			var wc_configured := _bool_or_default(
				status, "stt_whisper_cpp_configured", false,
			)
			if wc_configured:
				lines.append(_row("whisper_cpp",
					"configured (via SMOLIT_STT_WHISPER_CPP_CMD), aber nicht in der Chain.",
					true))
			else:
				lines.append(_row("whisper_cpp",
					"nicht in der Chain (set SMOLIT_STT_WHISPER_CPP_CMD and add to chain to enable).",
					true))
	return lines


## TTS: Legacy-Feature-Flags (enabled/available/auto_speak) **plus**
## die neuen `tts_provider_*`-Felder aus PR 6.
static func tts_lines(status: Dictionary) -> Array:
	var lines: Array = []
	lines.append(_row("Enabled", _bool_label(status, "tts_enabled"),
		not status.has("tts_enabled")))
	lines.append(_row("Available", _bool_label(status, "tts_available"),
		not status.has("tts_available")))
	lines.append(_row("Auto speak", _bool_label(status, "auto_speak"),
		not status.has("auto_speak")))
	if status.has("tts_provider_configured"):
		lines.append_array(_audio_provider_lines(status, "tts_provider"))
	else:
		lines.append(_row("Provider",
			"Core liefert keine tts_provider_*-Felder (alter Build).",
			true))
	# PR 34 — piper-Sichtbarkeit. Dreistufig, wie bei whisper_cpp in
	# der STT-Achse (PR 27) und llamafile_local in der Text-Achse:
	#   * `tts_piper_in_chain` fehlt → alter Core, kein Hinweis.
	#   * `tts_piper_in_chain = false` → ehrlich „nicht in Chain".
	#   * `tts_piper_in_chain = true` → configured-Flag + env-Hinweis
	#     bei Bedarf.
	if status.has("tts_piper_in_chain"):
		var piper_in_chain := _bool_or_default(status, "tts_piper_in_chain", false)
		if piper_in_chain:
			lines.append(_row("piper", "in Chain"))
			var piper_configured := _bool_or_default(
				status, "tts_piper_configured", false,
			)
			lines.append(_row("  configured (command set)",
				"yes" if piper_configured else "no",
				not piper_configured))
			if not piper_configured:
				lines.append(_row("  hint",
					"command not set — configure via SMOLIT_TTS_PIPER_CMD",
					true))
		else:
			var piper_configured := _bool_or_default(
				status, "tts_piper_configured", false,
			)
			if piper_configured:
				lines.append(_row("piper",
					"configured (via SMOLIT_TTS_PIPER_CMD), aber nicht in der Chain.",
					true))
			else:
				lines.append(_row("piper",
					"nicht in der Chain (set SMOLIT_TTS_PIPER_CMD and add to chain to enable).",
					true))
	return lines


## Gemeinsamer Renderer für die fünf `*_provider_*`-Felder einer
## Audio-Achse. `prefix` ist `"stt_provider"` oder `"tts_provider"`.
## Defensiv: fehlende Felder → Dash.
static func _audio_provider_lines(status: Dictionary, prefix: String) -> Array:
	var lines: Array = []
	# PR 13 — Chain-Zeile zuerst rendern, damit der Nutzer sofort
	# sieht, welche Reihenfolge der Core aktuell fährt. Fehlt das
	# Feld (alter Core), zeigt die Zeile einen ehrlichen „—".
	var chain_field := prefix + "_chain"
	var chain_raw: Variant = status.get(chain_field, null)
	if typeof(chain_raw) == TYPE_ARRAY:
		if (chain_raw as Array).is_empty():
			lines.append(_row("Chain", "—", true))
		else:
			var items: Array[String] = []
			for entry in chain_raw:
				items.append(String(entry))
			lines.append(_row("Chain", " → ".join(items)))
	else:
		lines.append(_row("Chain",
			"Core liefert kein %s-Feld (alter Build).".replace("%s", chain_field),
			true))
	lines.append(_row("Configured",
		_stringify_or_dash(status, prefix + "_configured")))
	lines.append(_row("Active",
		_stringify_or_dash(status, prefix + "_active")))
	lines.append(_row("Availability",
		_stringify_or_dash(status, prefix + "_availability")))
	var last_error_key := prefix + "_last_error"
	var last_error_raw: Variant = status.get(last_error_key, null)
	if last_error_raw == null:
		lines.append(_row("Last error", _DASH, true))
	else:
		lines.append(_row("Last error", str(last_error_raw)))
	var cloud_key := prefix + "_cloud"
	var cloud := _bool_or_default(status, cloud_key, false)
	lines.append(_row("Cloud", "yes" if cloud else "no",
		not status.has(cloud_key)))
	return lines


## Privacy: heute nur der Cloud-Hinweis auf Text-Achse; STT/TTS haben
## kein Cloud-Feld. Wir formulieren den Hinweis ehrlich und nutzen die
## PR-4-Felder (`llamafile_in_chain`, `text_provider_chain`), um lokal
## vs. extern sichtbarer zu machen.
static func privacy_lines(status: Dictionary) -> Array:
	var lines: Array = []
	var cloud := _bool_or_default(status, "text_provider_cloud", false)
	lines.append(_row("Text: Cloud aktiv",
		"yes" if cloud else "no",
		not status.has("text_provider_cloud")))
	# Text-Chain: wenn llamafile_local in der Chain und enabled ist,
	# rendern wir das als „lokal verfügbar" — hart anders als Cloud.
	if status.has("llamafile_in_chain"):
		var in_chain := _bool_or_default(status, "llamafile_in_chain", false)
		var enabled := _bool_or_default(status, "llamafile_enabled", false)
		if in_chain and enabled:
			lines.append(_row("Text: lokaler Pfad",
				"llamafile_local in Chain — Nutzerinhalte verlassen den Host nicht."))
		elif in_chain and not enabled:
			lines.append(_row("Text: lokaler Pfad",
				"llamafile_local in Chain, aber disabled — Fallback bleibt abrain (lokaler CLI).",
				true))
		else:
			lines.append(_row("Text: lokaler Pfad",
				"nur abrain in Chain — lokaler CLI-Pfad.", true))
	# STT/TTS-Cloud-Statuszeile. Seit PR 6 liefert der Core
	# `stt_provider_cloud`/`tts_provider_cloud`; ältere Cores landen
	# stillschweigend auf dem honest-„noch nicht modelliert"-Text.
	if status.has("stt_provider_cloud") or status.has("tts_provider_cloud"):
		var stt_cloud := _bool_or_default(status, "stt_provider_cloud", false)
		var tts_cloud := _bool_or_default(status, "tts_provider_cloud", false)
		var stt_label := "yes" if stt_cloud else "no"
		var tts_label := "yes" if tts_cloud else "no"
		lines.append(_row("STT Cloud aktiv", stt_label,
			not status.has("stt_provider_cloud")))
		lines.append(_row("TTS Cloud aktiv", tts_label,
			not status.has("tts_provider_cloud")))
	else:
		lines.append(_row("STT/TTS Cloud",
			_DASH + " (heute nicht modelliert)", true))
	lines.append(_row("Offline-Only",
		"nicht konfiguriert (kommt in Folge-PR)", true))
	lines.append(_row("Secrets",
		"kein Editor in dieser Shell (PR 5)", true))
	return lines


## Connection: IPC-Zustand + kleine Einblicke in Interaction/Accessibility.
## `extras.connected` kommt vom Main-Controller (`IpcClient.is_connected_to_core`).
static func connection_lines(status: Dictionary, extras: Dictionary) -> Array:
	var lines: Array = []
	var connected := bool(extras.get("connected", false))
	lines.append(_row("IPC", "connected" if connected else "disconnected"))
	lines.append(_row("ipc_enabled", _bool_label(status, "ipc_enabled"),
		not status.has("ipc_enabled")))
	lines.append(_row("interaction_enabled",
		_bool_label(status, "interaction_enabled"),
		not status.has("interaction_enabled")))
	lines.append(_row("interaction_backend",
		_stringify_or_dash(status, "interaction_backend")))
	lines.append(_row("approval_timeout_seconds",
		_stringify_or_dash(status, "approval_timeout_seconds")))
	lines.append(_row("accessibility_probe",
		_stringify_or_dash(status, "accessibility_probe")))
	var reason_raw: Variant = status.get("accessibility_probe_reason", null)
	if reason_raw != null and str(reason_raw) != "":
		lines.append(_row("probe_reason", str(reason_raw), true))
	return lines


# --- Kleine defensive Helfer ---------------------------------------------


static func _stringify_or_dash(source: Dictionary, key: String) -> String:
	if not source.has(key):
		return _DASH
	var value: Variant = source.get(key)
	if value == null:
		return _DASH
	var as_str := str(value)
	if as_str == "":
		return _DASH
	return as_str


static func _bool_label(source: Dictionary, key: String) -> String:
	if not source.has(key):
		return _DASH
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_BOOL:
		return "yes" if value else "no"
	# Tolerant: wenn ein numerischer Wert reinkommt, als Truthy/Falsy
	# lesen; wenn Freitext, nach-casten.
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return "yes" if value != 0 else "no"
	if typeof(value) == TYPE_STRING:
		var lowered := String(value).to_lower()
		if lowered in ["true", "yes", "1", "on"]:
			return "yes"
		if lowered in ["false", "no", "0", "off"]:
			return "no"
	return _DASH


static func _bool_or_default(source: Dictionary, key: String, default_value: bool) -> bool:
	if not source.has(key):
		return default_value
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	return default_value
