extends RefCounted
## Settings-Shell · Provider-Onboarding (PR 26) — pure Helfer.
##
## Ein schmaler Readout-Layer oberhalb der bestehenden Text-Provider-
## Editoren, der einem neuen Nutzer erklärt, **was gerade läuft** und
## **was für cloud_http noch fehlt**. Keine Schreibpfade, kein IPC, kein
## Secrets-Zugriff — der Core bleibt Single Source of Truth.
##
## Das Modul ist bewusst frei von UI-Nodes, damit Smoke-Tests es ohne
## SceneTree prüfen können. Der Panel-Controller nutzt diese Helfer
## einmal im Re-Render-Tick, um seine Zeilen zu bauen.
##
## Ausdrücklich *nicht* Teil dieses Moduls:
##   * Keine neuen IPC-Commands (Quick-Action „Use local-first chain"
##     sendet `settings_set_text_provider_chain`, das seit PR 9
##     existiert).
##   * Keine Änderungen an `StatusPayload` — nur vorhandenes Vokabular
##     (siehe `docs/api.md` §2.3).
##   * Keine Anzeige von API-Key-Werten. `cloud_http_secret_present` ist
##     ein Boolean, der Helfer reicht ihn als Boolean weiter, nie als
##     Wert.

class_name ProviderOnboarding

## Kuratierte lokale Default-Kette für die Quick-Action
## „Use local-first chain". Bewusst drei Kinds in der Reihenfolge:
## llamafile (lokaler Runtime), local_http (lokaler Netzwerk-Endpoint),
## abrain (lokaler CLI-Fallback). `cloud_http` ist ausdrücklich **nicht**
## enthalten — cloud bleibt Opt-in und wird nicht automatisch
## aktiviert.
const LOCAL_FIRST_CHAIN: Array[String] = ["llamafile_local", "local_http", "abrain"]

## Label-/Erklärtexte als Konstanten, damit der Smoke-Test sie stabil
## referenzieren kann, ohne UI-Strings per Teilstring zu matchen.
const TITLE_TEXT: String = "Provider Onboarding"
const LOCAL_FIRST_HINT_TEXT: String = "Empfohlen: lokaler Default. llamafile_local → local_http → abrain hält alle Text-Requests auf diesem Host. Cloud bleibt Opt-in."
const NO_AUTO_CLOUD_TEXT: String = "Cloud wird nicht automatisch aktiviert. cloud_http landet nur dann in der Chain, wenn du es explizit setzt — diese Shell schaltet das nicht für dich."
const LOCAL_FIRST_BUTTON_TEXT: String = "Use local-first chain"
const ADD_CLOUD_BUTTON_TEXT: String = "Add cloud_http to chain"
const ADD_CLOUD_DISABLED_REASON_NOT_ENABLED: String = "cloud_http disabled — setze SMOLIT_CLOUD_HTTP_ENABLED oder aktiviere den Provider im cloud_http-Editor."
const ADD_CLOUD_DISABLED_REASON_NO_ENDPOINT: String = "cloud_http kein Endpoint gesetzt — erst Endpoint im cloud_http-Editor eintragen."
const ADD_CLOUD_DISABLED_REASON_NO_SECRET: String = "cloud_http kein API-Key gespeichert — erst Key im cloud_http-Editor speichern."
const ADD_CLOUD_DISABLED_REASON_ALREADY_IN_CHAIN: String = "cloud_http ist bereits Teil der aktiven Chain."

## Tag-Strings für die Lokalitätskennzeichnung. Der UI-Renderer klebt
## sie als `[tag]`-Präfix vor den Kind-Namen, damit der Nutzer im
## Onboarding-Block sofort lokal vs. extern erkennt.
const LOCALITY_LOCAL: String = "local"
const LOCALITY_CLOUD: String = "cloud"
const LOCALITY_UNKNOWN: String = "unknown"


## Ermittelt den **Primary**-Text-Provider. Prinzip:
##   1. `text_provider_active` aus dem Status (Core-Antwort, was heute
##      tatsächlich läuft).
##   2. Fallback: erstes Kind aus `text_provider_chain`.
##   3. Fallback: `text_provider_configured`.
##   4. Zuletzt: leerer String (Renderer zeigt dann `—`).
static func primary_provider(status: Dictionary) -> String:
	var active := String(status.get("text_provider_active", ""))
	if active != "":
		return active
	var chain_raw: Variant = status.get("text_provider_chain", null)
	if typeof(chain_raw) == TYPE_ARRAY and (chain_raw as Array).size() > 0:
		return String((chain_raw as Array)[0])
	var configured := String(status.get("text_provider_configured", ""))
	return configured


## Returns the chain as an ordered `Array` of `{kind, locality}`-Dicts.
## `locality` ist `local`, `cloud` oder `unknown` und wird pro Kind
## statisch entschieden (kein Netzwerk-Lookup, keine Laufzeit-Probe).
static func chain_with_locality(status: Dictionary) -> Array:
	var out: Array = []
	var chain_raw: Variant = status.get("text_provider_chain", null)
	if typeof(chain_raw) != TYPE_ARRAY:
		return out
	for entry in chain_raw:
		var kind := String(entry)
		out.append({
			"kind": kind,
			"locality": locality_for(kind),
		})
	return out


## Statische Lokalitäts-Klassifikation. Die bekannten Text-Provider:
##   * `abrain` — lokaler CLI-Prozess → local
##   * `llamafile_local` — lokaler Runtime-Prozess → local
##   * `local_http` — lokaler HTTP-Server auf 127.0.0.1 → local
##   * `cloud_http` — externer Endpoint → cloud
## Unbekannte Kinds fallen bewusst auf `unknown`; der Renderer kann
## das dann als neutral muten, statt eine Sicherheitsaussage zu
## erfinden.
static func locality_for(kind: String) -> String:
	match kind:
		"abrain":
			return LOCALITY_LOCAL
		"llamafile_local":
			return LOCALITY_LOCAL
		"local_http":
			return LOCALITY_LOCAL
		"cloud_http":
			return LOCALITY_CLOUD
		_:
			return LOCALITY_UNKNOWN


## `cloud_http`-Bereitschafts-Checklist. Ergebnis ist ein Dictionary mit
## vier Booleans plus einem zusammenfassenden `ready`-Flag — `ready`
## impliziert alle vier. Wird vom UI-Renderer zu einer `row`-Liste
## verdrahtet, damit die Shell ehrlich zeigt, was für den First-Run
## fehlt.
##
## Wichtig: `secret_present` wird 1:1 aus `cloud_http_secret_present`
## gelesen (Core liefert Boolean). Der Helfer liest **niemals** einen
## Key-Wert.
static func cloud_http_readiness(status: Dictionary) -> Dictionary:
	var enabled := _bool_or_default(status, "cloud_http_enabled", false)
	var configured := _bool_or_default(status, "cloud_http_configured", false)
	var secret_present := _bool_or_default(status, "cloud_http_secret_present", false)
	var in_chain := _bool_or_default(status, "cloud_http_in_chain", false)
	var ready := enabled and configured and secret_present and in_chain
	return {
		"enabled": enabled,
		"endpoint_set": configured,
		"secret_present": secret_present,
		"in_chain": in_chain,
		"ready": ready,
	}


## Menschliche Kurzbeschreibung der Bereitschaft. Wird vom Smoke-Test
## genutzt, um zu prüfen, dass der First-Run-Hint ohne falsche
## Sicherheitsaussage auskommt. Gibt ein Dictionary zurück mit einer
## `lines`-Liste (Array von `{label, value, muted}`) — identisches
## Row-Format wie `SettingsSections`, damit der Panel-Controller die
## Zeilen ohne Mapping durchreicht.
static func cloud_http_readiness_rows(status: Dictionary) -> Array:
	var readiness := cloud_http_readiness(status)
	var rows: Array = []
	rows.append(_row("cloud_http enabled",
		_yes_no(readiness["enabled"]),
		not readiness["enabled"]))
	rows.append(_row("cloud_http endpoint",
		"set" if readiness["endpoint_set"] else "missing",
		not readiness["endpoint_set"]))
	rows.append(_row("cloud_http api key",
		"present" if readiness["secret_present"] else "not set",
		not readiness["secret_present"]))
	rows.append(_row("cloud_http in chain",
		_yes_no(readiness["in_chain"]),
		not readiness["in_chain"]))
	rows.append(_row("cloud_http ready",
		"ready" if readiness["ready"] else "first-run steps pending",
		not readiness["ready"]))
	return rows


## Begründung, warum die Quick-Action „Add cloud_http to chain" aktuell
## disabled ist — oder leer, wenn sie klickbar wäre. Die Reihenfolge
## spiegelt die sinnvolle Behebungsreihenfolge: erst Master-Schalter,
## dann Endpoint, dann Key, dann Chain.
static func add_cloud_disabled_reason(status: Dictionary) -> String:
	var readiness := cloud_http_readiness(status)
	if not readiness["enabled"]:
		return ADD_CLOUD_DISABLED_REASON_NOT_ENABLED
	if not readiness["endpoint_set"]:
		return ADD_CLOUD_DISABLED_REASON_NO_ENDPOINT
	if not readiness["secret_present"]:
		return ADD_CLOUD_DISABLED_REASON_NO_SECRET
	if readiness["in_chain"]:
		return ADD_CLOUD_DISABLED_REASON_ALREADY_IN_CHAIN
	return ""


## `Add cloud_http to chain` bleibt in PR 26 bewusst ein *disabled*-
## Button mit einer Erklärung. Wir schalten ihn nicht automatisch
## klickbar, auch wenn alle vier Flags grün sind — der Nutzer soll den
## Provider bewusst über den bestehenden `cloud_http`-Editor
## aktivieren. Dieser Helfer ist also der Single-Point, an dem wir
## „disabled" sagen.
##
## `true` → Button bleibt disabled, UI zeigt zusätzlich den Text aus
## `add_cloud_disabled_reason()` bzw. einen neutralen
## „use the cloud_http editor below"-Hinweis, wenn alles ready ist.
static func add_cloud_button_should_stay_disabled(_status: Dictionary) -> bool:
	return true


# --- Kleine defensive Helfer --------------------------------------------


static func _row(label: String, value: String, muted: bool = false) -> Dictionary:
	return {
		"label": label,
		"value": value,
		"muted": muted,
	}


static func _yes_no(value: bool) -> String:
	return "yes" if value else "no"


static func _bool_or_default(source: Dictionary, key: String, default_value: bool) -> bool:
	if not source.has(key):
		return default_value
	var value: Variant = source.get(key)
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	return default_value
