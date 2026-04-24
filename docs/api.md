# Smolit Assistant – IPC- und API-Spezifikation

Diese Datei ist die **autoritative Beschreibung** der Schnittstellen von
Smolit. Sie unterscheidet strikt zwischen:

- **Ist-Zustand** — heute im Code umgesetzt und getestet,
- **Ziel-Zustand** — geplant, aber noch nicht implementiert.

Nichts hier ist Spekulation: jeder Ist-Zustand-Eintrag lässt sich im
Repo nachvollziehen (siehe `core/src/ipc/protocol.rs` für das WebSocket-
Protokoll, `core/src/app.rs` für die geteilten Handler,
`adapters/abrain/` bzw. `core/src/abrain.rs` für den ABrain-Adapter).

---

## 1. Überblick der Schnittstellen

```text
┌───────────────┐   WebSocket JSON   ┌────────────────┐   CLI stdin/stdout   ┌──────────┐
│  Godot UI     │ ◀────────────────▶ │  Rust Core     │ ◀──────────────────▶ │  ABrain  │
│  (Client)     │   Phase 3 (Ist)    │  (Host)        │   Phase 0 (Ist)      │          │
└───────────────┘                    └────────────────┘                      └──────────┘
                                             │                Commands       ┌──────────┐
                                             └────────────────────────────▶  │ STT/TTS  │
                                                             Phase 1 (Ist)   └──────────┘
```

Produktive Grenzen (Ist-Zustand):

- **UI ↔ Core** über lokalen WebSocket (Phase 3).
- **Core ↔ ABrain** über CLI-Prozess (Phase 0).
- **Core ↔ STT/TTS** über konfigurierbare externe Commands (Phase 1).

Geplant (Ziel-Zustand):

- **Core ↔ ABrain** als natives API (noch nicht implementiert).

---

## 2. UI ↔ Core: WebSocket-Protokoll (Ist-Zustand)

- Transport: WebSocket, Text-Frames, UTF-8, eine Nachricht je Frame.
- Default-Bind: `127.0.0.1:8787` (siehe `SMOLIT_IPC_BIND`).
- Payload: JSON-Objekt. Pflichtfeld `"type"`. Unbekannte `type`-Werte
  werden mit einer `error`-Antwort beantwortet; die Verbindung bleibt
  offen.
- Fehlerhaftes JSON führt ebenfalls zu einer `error`-Antwort, nicht zu
  einem Crash.

### 2.1 Eingehend (UI → Core)

| `type`                   | Felder                        | Semantik                                                                                  |
|--------------------------|-------------------------------|-------------------------------------------------------------------------------------------|
| `ping`                   | —                             | Health-Check. Core antwortet mit `pong`.                                                  |
| `get_status`             | —                             | Fragt Feature-Status ab. Core antwortet mit `status`.                                     |
| `submit_text`            | `text: string`                | Freitext-Query an ABrain. Löst `thinking` + `response`/`error`.                           |
| `speak_text`             | `text: string`                | Direkte TTS-Ausgabe ohne ABrain. Emittiert `speaking_started`/`_ended` (2.11). Bei Fehler: `error`. |
| `voice_once`             | —                             | Einmal STT aufnehmen, Ergebnis als `heard`, dann ABrain-Flow.                             |
| `approval_response`      | `approval_id`, `decision`     | Unified Approval-Antwort (siehe 2.7).                                                     |
| `approval_approve`       | `approval_id`                 | PR 17 — schmale Variante, wire-äquivalent zu `approval_response(..., "approved")`.        |
| `approval_deny`          | `approval_id`                 | PR 17 — schmale Variante für `decision="denied"`.                                         |
| `request_approval_demo`  | `title?`, `summary?`, `risk?` | PR 17 — harmloser Demo-Auslöser. Keine Aktion folgt.                                      |
| `plan_demo_action`       | `title?`, `summary?`, `risk?`, `kind?`, `requires_approval?` | PR 18 — Approval-Gated Demo-Action-Planner. Mock-Executor, keine Systemaktion. |
| `audit_recent`           | `limit?`                      | PR 19 — Read-only Abfrage des lokalen Audit-Ring-Buffers.                                 |

Zusätzlich nimmt der Core Interaction-Nachrichten des Desktop
Interaction Layer MVP entgegen (Details in Abschnitt 2.6):

- `interaction_open_application` mit Feld `application: string`.
- `interaction_focus_window` mit Feld `target` (siehe 2.6).
- `interaction_probe_accessibility` — Environment-Probe für den
  Linux Accessibility Backend Spike (Details in Abschnitt 2.8).
- `interaction_discover_accessibility` mit optionalem Feld
  `hint: string` — symbolische Discovery-/Inspection-Anfrage für den
  AT-SPI Spike (Details in Abschnitt 2.8).

Für den Approval / Confirmation Flow (Details in Abschnitt 2.7):

- `approval_response` mit `approval_id: string` und `decision`
  (`"approved" | "denied" | "cancelled"`).

Für die Settings-Shell (Details in Abschnitt 2.10, seit PR 5; um
PR 7 erweitert):

- `settings_set_llamafile_config` — editiert die `llamafile_local`-
  Provider-Config. Pflicht-Feld `enabled: bool`. Optional:
  `mode: "on_demand" | "standby"`, `idle_timeout_seconds: integer`,
  `path: string` (leerer String löscht den Pfad). Core validiert,
  rebuildet den Provider-Resolver und antwortet mit einem
  `status`-Envelope (Erfolg) oder einem `error`-Envelope
  (z. B. unbekannter Mode).
- `settings_probe_llamafile` — Side-Effect-freie Diagnose-Probe.
  Antwort: `settings_probe_result` mit `axis: "llamafile"`.
- `settings_set_stt_config` — editiert die STT-Provider-Config.
  Pflicht-Feld `enabled: bool`. Optional: `command: string` (leer /
  whitespace löscht, sonst ersetzt). Timeouts und Provider-Chain
  bleiben env-/Startup-gesteuert. Core rebuildet den STT-Resolver
  atomar.
- `settings_set_tts_config` — Spiegel zu STT plus optional
  `auto_speak: bool`.
- `settings_probe_stt` / `settings_probe_tts` — Side-Effect-freie
  Diagnose-Proben für die Audio-Achsen. Kein Mikrofon-Zugriff, kein
  Audio-Output, kein Spawn — nur Config- und Filesystem-Check des
  ersten Command-Tokens. Antwort: `settings_probe_result` mit
  `axis: "stt"` bzw. `"tts"`.
- `settings_set_local_http_config` (PR 8) — editiert den neuen
  `local_http`-Text-Provider. Pflichtfeld `enabled: bool`. Optional:
  `endpoint: string` (leer löscht, sonst ersetzt — erwartet
  `http://host[:port][/path]`), `request_timeout_seconds: integer`
  (`0` wird abgelehnt). Prompt-/Response-Feldnamen bleiben
  env-gesteuert und werden nicht über diese Nachricht transportiert.
- `settings_probe_local_http` (PR 8) — Side-Effect-freie
  Diagnose-Probe: TCP-Connect auf den geparsten Endpoint, **kein**
  Completion-Request, **kein** Prompt-Daten-Leak. Antwort:
  `settings_probe_result` mit `axis: "local_http"`.
- `settings_set_text_provider_chain` (PR 9) — editiert die
  geordnete Text-Provider-Fallback-Kette. Pflichtfeld `chain:
  string[]`. Der Core validiert: nur bekannte Kinds
  (`abrain` / `llamafile_local` / `local_http`), keine Duplikate,
  nicht leer. Bei Erfolg antwortet der Core mit einem frischen
  `status`-Envelope; bei Validation-Fehlern mit `error`.
- `settings_reset_text_provider_chain` (PR 9) — setzt die Kette
  auf den Compile-Zeit-Default `["abrain"]` zurück und löscht den
  persistierten Override im Settings-Store. Antwort: `status`.
- `settings_set_cloud_http_config` (PR 10) — editiert die
  **operationale** Config des ersten Cloud-/Remote-Text-Providers
  `cloud_http` (enabled / endpoint / model / request_timeout). Der
  API-Key ist **nicht Teil dieser Message** (separate Secret-Pfad,
  s. u.). Antwort: `status` bei Erfolg.
- `settings_set_cloud_http_secret` (PR 10) — einziger IPC-Pfad, der
  den API-Key transportiert. Leerer String / `null` = Key löschen.
  Antwort trägt nur `cloud_http_secret_present: bool`, nie den
  Key-Wert.
- `settings_probe_cloud_http` (PR 10) — TCP-Connect-only Diagnose
  gegen den geparsten Endpoint; **kein** Completion-Request,
  **kein** Bearer-Header auf der Leitung. Antwort:
  `settings_probe_result` mit `axis: "cloud_http"`.
- `settings_set_stt_provider_chain` (PR 13, seit PR 27 zwei Kinds) —
  editiert die geordnete STT-Provider-Fallback-Kette. Pflichtfeld
  `chain: string[]`. Whitelist: `command`, `whisper_cpp`. Der Core
  validiert (Whitelist, Duplikate, Empty-Reject, Trim+Lowercase).
  Antwort: `status` oder `error`.
- `settings_reset_stt_provider_chain` (PR 13) — setzt die Kette
  auf Default `["command"]` und löscht den persistierten
  Override. PR 27 ändert den Compile-Time-Default *nicht* —
  `whisper_cpp` kommt nur dann in die Kette, wenn der Nutzer sie
  explizit setzt.
- `settings_set_tts_provider_chain` / `settings_reset_tts_provider_chain`
  (PR 13, seit PR 34 zwei Kinds) — spiegel für die TTS-Achse.
  Whitelist: `command`, `piper`. Default bleibt `["command"]`.
  PR 34 fügt `piper` nur zur Whitelist hinzu; das Kind kommt nur
  dann in die Kette, wenn der Nutzer sie explizit setzt.

**PR 26 — Provider-Onboarding UX v1 (keine neuen IPC-Commands).**
Der in der Settings-Shell ergänzte Onboarding-Block (siehe
[`docs/ui_architecture.md §8d.5g`](./ui_architecture.md) und
[`docs/provider_fallback_and_settings_architecture.md §12`](./provider_fallback_and_settings_architecture.md))
**erweitert das IPC-Protokoll nicht**. Er liest nur bestehende
`StatusPayload`-Felder (`text_provider_active`, `text_provider_chain`,
`text_provider_configured`, `cloud_http_enabled`,
`cloud_http_configured`, `cloud_http_secret_present`,
`cloud_http_in_chain`). Die Quick-Action „Use local-first chain"
sendet denselben `settings_set_text_provider_chain`-Command aus PR 9
mit der Payload `{"chain":["llamafile_local","local_http","abrain"]}`
— kein neuer Command-Typ. Die Quick-Action „Add cloud_http to chain"
ist per Design **disabled** und emittiert keinen Command.

Beispiele:

```json
{"type":"ping"}
{"type":"get_status"}
{"type":"submit_text","text":"Hallo Smolit"}
{"type":"speak_text","text":"Dies ist ein Test"}
{"type":"voice_once"}
{"type":"interaction_open_application","application":"calendar"}
{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}
{"type":"interaction_probe_accessibility"}
{"type":"interaction_discover_accessibility"}
{"type":"interaction_discover_accessibility","hint":"firefox"}
{"type":"settings_set_llamafile_config","enabled":true,"mode":"on_demand","idle_timeout_seconds":300,"path":"/opt/llamafile/server"}
{"type":"settings_probe_llamafile"}
{"type":"settings_set_stt_config","enabled":true,"command":"whisper --model base"}
{"type":"settings_set_tts_config","enabled":true,"command":"espeak -v de","auto_speak":true}
{"type":"settings_probe_stt"}
{"type":"settings_probe_tts"}
{"type":"settings_set_local_http_config","enabled":true,"endpoint":"http://127.0.0.1:8080/completion","request_timeout_seconds":60}
{"type":"settings_probe_local_http"}
{"type":"settings_set_text_provider_chain","chain":["llamafile_local","local_http","abrain"]}
{"type":"settings_reset_text_provider_chain"}
{"type":"settings_set_cloud_http_config","enabled":true,"endpoint":"http://cloud-gateway.local:8443/v1/chat","model":"gpt-4o-mini","request_timeout_seconds":60}
{"type":"settings_set_cloud_http_secret","api_key":"sk-XXXXXXXXXXXXXX"}
{"type":"settings_set_cloud_http_secret","api_key":null}
{"type":"settings_probe_cloud_http"}
```

### 2.2 Ausgehend (Core → UI)

| `type`                           | Felder                            | Semantik                                                           |
|----------------------------------|-----------------------------------|--------------------------------------------------------------------|
| `pong`                           | —                                 | Antwort auf `ping`.                                                |
| `status`                         | `payload: StatusPayload`          | Aktueller Feature-Status (siehe 2.3).                              |
| `thinking`                       | —                                 | ABrain-Anfrage läuft. Wird pro Query einmal emittiert.             |
| `response`                       | `payload: { text: string }`       | ABrain-Antworttext.                                                |
| `heard`                          | `payload: { text: string }`       | STT-Ergebnis (nur im `voice_once`-Flow).                           |
| `error`                          | `message: string`                 | Fehler bei Parsing, Ausführung oder Adapter.                       |
| `accessibility_probe_result`     | `payload: AccessibilityProbe`     | Ergebnis einer `interaction_probe_accessibility`-Anfrage (2.8).    |
| `accessibility_discovery_result` | `payload: AccessibilityDiscovery` | Ergebnis einer `interaction_discover_accessibility`-Anfrage (2.8). |
| `settings_probe_result`          | `payload: SettingsProbeResult`    | Antwort auf `settings_probe_{llamafile,stt,tts}` (2.10).           |
| `speaking_started`               | `payload: SpeakingStarted`        | PR 14 — TTS-Lebenszyklus, Start. Siehe 2.11.                       |
| `speaking_ended`                 | `payload: SpeakingEnded`          | PR 14 — TTS-Lebenszyklus, Ende. Siehe 2.11.                        |
| `audit_recent`                   | `payload: AuditRecentPayload`     | PR 19 — Antwort, Liste sanitisierter Audit-Events (2.7).           |

Zusätzlich emittiert der Core **Action Events** (Action Event Model v1).
Sie sind additiv; ältere UIs, die sie nicht kennen, dürfen sie
ignorieren. Details in Abschnitt 2.5.

Diese Action Events bilden auch die **Grundlage für den geplanten
visuellen Workflow-/Action-Readout in der UI** (Ziel-Zustand, siehe
Abschnitt „UI-Projektion: Workflow Overlay" und
[`ui_architecture.md` §6a/§8a](./ui_architecture.md)). Das Overlay
ist eine **Projektion** dieser Events — kein separates Protokoll,
keine zweite Wahrheit, keine neue Event-Kategorie. Der Core bleibt
Source of Truth.

Für freigabepflichtige Aktionen kommen die Approval-Events
`approval_requested` und `approval_resolved` hinzu (Details in
Abschnitt 2.7).

Beispiele:

```json
{"type":"pong"}
{"type":"status","payload":{"tts_enabled":true,"tts_available":false,"stt_enabled":true,"stt_available":false,"auto_speak":true,"ipc_enabled":true}}
{"type":"thinking"}
{"type":"response","payload":{"text":"Hallo!"}}
{"type":"heard","payload":{"text":"was ist heute für ein Tag"}}
{"type":"error","message":"stt not available"}
```

### 2.3 `StatusPayload` (Ist-Zustand)

```json
{
  "tts_enabled":                   true,
  "tts_available":                 false,
  "stt_enabled":                   true,
  "stt_available":                 false,
  "auto_speak":                    true,
  "ipc_enabled":                   true,
  "interaction_enabled":           true,
  "interaction_backend":           "command",
  "approval_timeout_seconds":      20,
  "accessibility_probe":           "unavailable",
  "accessibility_probe_reason":    "DBUS_SESSION_BUS_ADDRESS is unset",
  "text_provider_configured":      "abrain",
  "text_provider_active":          "",
  "text_provider_availability":    "available",
  "text_provider_last_error":      null,
  "text_provider_cloud":           false,
  "text_provider_chain":           ["abrain"],
  "llamafile_in_chain":            false,
  "llamafile_enabled":             false,
  "llamafile_configured":          false,
  "llamafile_lifecycle":           null,
  "llamafile_mode":                null,
  "llamafile_idle_timeout_seconds": null,
  "stt_provider_configured":       "command",
  "stt_provider_active":           "",
  "stt_provider_availability":     "unavailable",
  "stt_provider_last_error":       null,
  "stt_provider_cloud":            false,
  "tts_provider_configured":       "command",
  "tts_provider_active":           "",
  "tts_provider_availability":     "unavailable",
  "tts_provider_last_error":       null,
  "tts_provider_cloud":            false
}
```

Semantik:

- `*_enabled`: durch Config angeschaltet (z. B. `SMOLIT_TTS_ENABLED`).
- `*_available`: Command ist gesetzt und wurde bei Core-Start als
  auflösbar erkannt. `enabled && !available` ist ein legitimer Zustand
  und wird von der UI als „an, aber nicht nutzbar" gerendert.
- `auto_speak`: wird jede `response` zusätzlich über TTS ausgegeben?
- `ipc_enabled`: ist der WebSocket-Server aktiv? (per Definition `true`
  für jeden UI-Client, der dieses Feld sieht.)
- `interaction_enabled`: ist der Desktop Interaction Layer aktiv?
- `interaction_backend`: Name des aktiven Interaction-Backends
  (MVP: `command`). Welche Kinds effektiv erlaubt sind, ergibt sich aus
  `SMOLIT_INTERACTION_ALLOW_*`.
- `approval_timeout_seconds`: Fenster, in dem die UI auf ein
  `approval_requested` mit `approval_response` antworten muss, bevor
  der Core die Aktion als `timed_out` abbricht (siehe 2.7).
- `accessibility_probe`: Einer der Strings `"uncertain"` /
  `"unavailable"` / `"failed"` — Ergebnis der beim Core-Start
  ausgeführten, rein umgebungsbasierten AT-SPI-Erkennung (siehe 2.8).
  Es handelt sich um einen Capability-Hinweis, **nicht** um eine
  Bestätigung, dass AT-SPI tatsächlich funktioniert.
- `accessibility_probe_reason`: Kurze, freie Begründung zum
  `accessibility_probe`-Wert (z. B. `"DBUS_SESSION_BUS_ADDRESS is unset"`).
- `text_provider_configured`: Kanonischer Kind-Name des primär
  konfigurierten Text-/Reasoning-Providers (erstes Element der
  Provider-Kette). `"none"` nur, wenn die Kette leer ist. Default
  `"abrain"`. Siehe
  [`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md) §8.
- `text_provider_active`: Kind-Name des Providers, der den **letzten**
  `submit_text` / `voice_once`-Request erfolgreich beantwortet hat.
  Leer, solange noch kein Request durchgelaufen ist. Weicht
  `active != configured` ab, zeigt das: ein Fallback-Provider hat
  geantwortet (siehe `text_provider_availability`).
- `text_provider_availability`: Einer der Strings `"available"`
  (nominell, Kette nicht leer, kein totaler Fehlschlag) /
  `"unavailable"` (leere Kette oder alle Provider der Kette sind am
  letzten Request gescheitert) / `"fallback_active"` (ein Nicht-Primary
  hat den letzten Request beantwortet). Das Vokabular ist additiv
  ausbaubar (`"degraded"` u. ä.); UIs müssen unbekannte Werte tolerant
  behandeln.
- `text_provider_last_error`: Kurze Fehlerklasse der letzten komplett
  fehlgeschlagenen Runde (`"timeout"` / `"process_missing"` /
  `"empty_response"` / `"exit_nonzero"` / `"invalid_response"` /
  `"unknown"`). `null` im Erfolgsfall. Keine Nutzerinhalte, keine
  Stacktraces, keine Secrets — ausführliche Meldungen laufen weiter
  über das `error`-Envelope.
- `text_provider_cloud`: Ob der aktuell aktive Provider eine Cloud-
  Komponente hat. In dieser Stufe implementiert nur ABrain-CLI; das
  Feld bleibt immer `false`. Additiv vorhanden, damit der UI-
  Transparenzvertrag aus §7 der Architektur-Doku (Cloud-Kennzeichnung)
  ohne Protokoll-Revision einlösbar ist, sobald ein Cloud-Pfad
  existiert.

Seit PR 4 der Provider-Fallback-Linie kommen sieben weitere,
**additive** Felder dazu. Sie vertiefen den Status-Readout der
Settings-Shell (siehe
[`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md)
§8), ohne eine neue Nachrichtenfamilie einzuführen. Ältere UI-Stände,
die diese Felder nicht kennen, behandeln sie ignorant — das bestehende
`text_provider_*`-Vokabular bleibt unverändert.

- `text_provider_chain`: Geordnete Liste der produktiv instanziierten
  Provider-Kinds. Spiegelt den Resolver-Zustand nach dem Bau der Kette,
  d. h. unbekannte Kinds aus der Config sind hier bereits verworfen.
  Fallback auf `["abrain"]`, wenn die Kette nach dem Filtern leer
  wäre. Beispiele: `["abrain"]`, `["llamafile_local", "abrain"]`,
  `["cloud_http", "llamafile_local", "abrain"]`.
  Seit PR 9 editierbar über `settings_set_text_provider_chain`
  (siehe §2.10c); ein Reset-Pfad stellt den Default `["abrain"]`
  wieder her. Seit PR 10 akzeptiert die Whitelist zusätzlich
  `"cloud_http"`.
- `cloud_http_in_chain` (PR 10): Boolesch. `true` genau dann, wenn
  `"cloud_http"` in `text_provider_chain` enthalten ist.
- `cloud_http_enabled` (PR 10): Ausgewerteter Master-Schalter
  (`SMOLIT_CLOUD_HTTP_ENABLED` + Runtime-Overrides). Unabhängig
  von Chain-Mitgliedschaft — zeigt, ob der Betreiber den Pfad
  bewusst eingeschaltet hat.
- `cloud_http_configured` (PR 10): `enabled` **und** Endpoint
  gesetzt **und** API-Key gesetzt. Die ehrliche „bereit für einen
  Request"-Grenze.
- `cloud_http_secret_present` (PR 10): **Nur ein Boolean.** Zeigt,
  ob im Secrets-Store ein Key steht. Der Wert selbst verlässt den
  Secrets-Store niemals — weder im Status, noch in Logs, noch in
  Probe-/Error-Envelopes.
- `llamafile_in_chain`: Boolesch. `true` genau dann, wenn
  `"llamafile_local"` in `text_provider_chain` enthalten ist. Wenn
  `false`, sind die folgenden vier `llamafile_*`-Felder semantisch
  leer — `*_enabled` / `*_configured` bleiben als boolescher Readout
  der Config sichtbar, `*_lifecycle` / `*_mode` /
  `*_idle_timeout_seconds` werden `null`.
- `llamafile_enabled`: Spiegelt `SMOLIT_LLAMAFILE_ENABLED`, unabhängig
  davon, ob `llamafile_local` in der Kette steht. Lässt „konfiguriert,
  aber nicht in der Kette" ehrlich sichtbar werden.
- `llamafile_configured`: `enabled` **und** nicht-leerer
  `SMOLIT_LLAMAFILE_PATH`. Das ist die ehrliche „in der Config bereit
  zum Spawn"-Grenze. Beides muss stimmen, sonst landet der Provider
  zur Laufzeit in `disabled` bzw. `not_configured`.
- `llamafile_lifecycle`: Lifecycle-Tag des `llamafile_local`-Providers,
  nur gesetzt wenn `llamafile_in_chain=true`. Vokabular aus
  [`crate::providers::text::LlamafileLifecycle::as_str`]:
  `"disabled"` / `"not_configured"` / `"configured"` / `"starting"` /
  `"ready"` / `"busy"` / `"failed"` / `"stopped"`. `null` heißt **nicht
  in der Kette** — nicht „Runtime kaputt". Das Vokabular ist stabil;
  spätere Runtime-Erweiterungen bleiben additiv, nicht ersetzend.
- `llamafile_mode`: `"on_demand"` / `"standby"`. Nur gesetzt, wenn
  `llamafile_in_chain=true`. Reflektiert den bereits normalisierten
  Config-Wert (unbekannte Eingaben sind in der Config-Stufe auf den
  Default gefallen).
- `llamafile_idle_timeout_seconds`: Ganzzahl (Sekunden). Nur gesetzt,
  wenn `llamafile_in_chain=true`. Im `on_demand`-Modus: nach dieser
  Zeitspanne ohne neuen Request stoppt der Watchdog den Prozess und
  der Lifecycle wird auf `stopped` gesetzt.

Seit PR 8 kommen drei weitere `local_http_*`-Felder dazu (analog zur
Llamafile-Projektion, aber bewusst kleiner — kein Lifecycle, kein
Endpoint-Echo):

- `local_http_in_chain`: Boolesch. `true` genau dann, wenn
  `"local_http"` in `text_provider_chain` steht.
- `local_http_enabled`: Spiegelt `SMOLIT_LOCAL_HTTP_ENABLED`.
- `local_http_configured`: `enabled` **und** nicht-leerer Endpoint.
  Die ehrliche „in der Config bereit zum Request"-Grenze.
  **Kein Endpoint-Feld** im StatusPayload — Secret-/Endpoint-
  Disziplin, wie beim Llamafile-Pfad.

Für STT/TTS bleibt das bekannte `*_enabled` / `*_available` /
`auto_speak`-Vokabular erhalten — Legacy-Feldpaar, kein Breaking
Change.

Seit PR 6 kommen pro Achse fünf weitere **additive** Felder dazu, die
strukturell dem Text-Readout entsprechen:

- `stt_provider_configured` / `tts_provider_configured`: Kanonischer
  Kind-Name des primär konfigurierten Providers. Default
  `"command"`. `"none"`, wenn die Kette leer ist.
- `stt_provider_active` / `tts_provider_active`: Kind des
  Providers, der den **letzten** erfolgreichen Run beantwortet hat
  (`voice_once` bzw. `speak_text`/`auto_speak`). Leer vor dem ersten
  erfolgreichen Aufruf.
- `stt_provider_availability` / `tts_provider_availability`: Einer
  aus `"available"` (Primärprovider nominell bereit — enabled +
  Command gesetzt) / `"unavailable"` (Primärprovider nicht bereit
  oder letzter Run in allen Providern fehlgeschlagen) /
  `"fallback_active"` (Nicht-Primärprovider hat zuletzt geantwortet,
  heute nicht erreichbar, weil nur ein Kind existiert). Vokabular
  ist additiv ausbaubar.
- `stt_provider_last_error` / `tts_provider_last_error`: Kurze
  Fehlerklasse nach einem komplett fehlgeschlagenen Run. STT-Klassen:
  `"disabled"` / `"not_configured"` / `"timeout"` /
  `"process_missing"` / `"exit_nonzero"` / `"empty_response"` /
  `"invalid_response"` / `"unknown"`. TTS-Klassen identisch plus
  `"stdin_write_failed"` (statt `empty_response`, das es für
  Sprachausgabe nicht gibt). `null` im Erfolgsfall. Keine
  Nutzerinhalte, keine Secrets.
- `stt_provider_cloud` / `tts_provider_cloud`: Boolesch. Heute
  immer `false` (keine Cloud-Kinds implementiert).
- `stt_provider_chain` / `tts_provider_chain` (PR 13): Geordnete
  Liste der produktiv instanziierten Audio-Kinds. Spiegel zum
  `text_provider_chain`-Feld. Seit PR 13 über
  `settings_set_{stt,tts}_provider_chain` editierbar; ein
  Reset-Pfad stellt den Default `["command"]` wieder her.

Die STT-Achse hat seit PR 27 zwei Kinds: `command` (bestehend,
`SMOLIT_STT_CMD`) und `whisper_cpp` (PR 27,
`SMOLIT_STT_WHISPER_CPP_CMD`). Die TTS-Achse hat seit PR 34
ebenfalls zwei Kinds: `command` (bestehend, `SMOLIT_TTS_CMD`) und
`piper` (PR 34, `SMOLIT_TTS_PIPER_CMD`). Alle vier sind
command-basierte Adapter, keine eingebundene Bibliothek und kein
Modell-/Download-Manager. Die Chain ist env-überschreibbar über
`SMOLIT_STT_PROVIDER_CHAIN` / `SMOLIT_TTS_PROVIDER_CHAIN`; unbekannte
Kinds werden im Resolver sichtbar verworfen und die Kette fällt
dann auf den Default `["command"]` zurück.

**PR 27 — whisper_cpp STT.** Das Kind ist ein zweiter command-
basierter Spawn-Adapter. Eigene Env-Variable:

- `SMOLIT_STT_WHISPER_CPP_CMD` — vollständiger Spawn-Befehl
  (Binary + Args), z. B. `/opt/whisper.cpp/main -m model.bin -f {input}`.
  **Leer/nicht gesetzt** → das Kind bleibt `unavailable`; der
  Resolver fällt auf den nächsten Chain-Eintrag zurück.

`SMOLIT_STT_ENABLED` gilt als globale Master-Flag für alle STT-
Kinds; eine dedizierte Per-Kind-Enabled-Variable gibt es bewusst
**nicht**. Die Error-Klassifikation aus dem Command-Kind
(`not_configured` / `timeout` / `process_missing` / `exit_nonzero` /
`empty_response` / `invalid_response` / `disabled` / `unknown`)
gilt 1:1 auch für `whisper_cpp` — beide Kinds teilen den Spawn-
Pfad, damit `stt_provider_last_error` stabil bleibt.

Neue StatusPayload-Booleans (PR 27, additiv):

- `stt_whisper_cpp_in_chain` — ob `whisper_cpp` Teil der
  produktiv instanziierten STT-Chain ist.
- `stt_whisper_cpp_configured` — ob `SMOLIT_STT_WHISPER_CPP_CMD`
  einen nicht-leeren Wert hat. Unabhängig von der Chain-
  Mitgliedschaft, analog zu `llamafile_configured` /
  `local_http_configured` / `cloud_http_configured`.

**Keine neuen IPC-Commands in PR 27.** Der bestehende
`settings_set_stt_provider_chain`-Pfad akzeptiert `whisper_cpp` in
der `chain`-Payload (Whitelist wurde erweitert); der Command-
String selbst ist env-only und wird nicht über IPC gesetzt.

**PR 34 — piper TTS.** Das TTS-Gegenstück zur PR-27-Linie: ein
zweiter command-basierter Spawn-/stdin-Adapter. Eigene Env-
Variable:

- `SMOLIT_TTS_PIPER_CMD` — vollständiger Spawn-Befehl
  (Binary + Args), z. B.
  `piper --model /opt/piper/de-thorsten-low.onnx --output-raw`.
  **Leer/nicht gesetzt** → das Kind bleibt `unavailable`; der
  Resolver fällt auf den nächsten Chain-Eintrag zurück.

`SMOLIT_TTS_ENABLED` gilt als globale Master-Flag für alle TTS-
Kinds; eine dedizierte Per-Kind-Enabled-Variable gibt es bewusst
**nicht**. Die Error-Klassifikation aus dem Command-Kind
(`not_configured` / `timeout` / `process_missing` /
`stdin_write_failed` / `exit_nonzero` / `disabled` / `unknown`)
gilt 1:1 auch für `piper` — beide Kinds teilen denselben
Spawn-/stdin-Pfad, damit `tts_provider_last_error` stabil bleibt.

Die Speaking-Lifecycle-Events aus PR 14 tragen das
`provider`-Feld unverändert: bei erfolgreichem Piper-Lauf trägt
`speaking_ended.payload.provider` den String `"piper"` (bzw.
`"command"`, wenn der Fallback übernimmt); `ok` / `error_class`
werden vom Resolver gefüllt.

Neue StatusPayload-Booleans (PR 34, additiv):

- `tts_piper_in_chain` — ob `piper` Teil der produktiv
  instanziierten TTS-Chain ist.
- `tts_piper_configured` — ob `SMOLIT_TTS_PIPER_CMD` einen
  nicht-leeren Wert hat. Unabhängig von der Chain-Mitgliedschaft,
  analog zu `stt_whisper_cpp_configured` (PR 27).

**Keine neuen IPC-Commands in PR 34.** Der bestehende
`settings_set_tts_provider_chain`-Pfad akzeptiert `piper` in der
`chain`-Payload (Whitelist wurde erweitert); der Command-String
selbst ist env-only und wird nicht über IPC gesetzt.

### 2.4 Flow-Beispiele

Dieser Abschnitt zeigt nur die **klassischen** Events
(`thinking` / `response` / `heard` / `error`). Die parallel dazu
emittierten Action Events sind in Abschnitt 2.5 beschrieben.

`submit_text`:

```text
UI → Core: {"type":"submit_text","text":"Hallo"}
Core → UI: {"type":"thinking"}
Core → UI: {"type":"response","payload":{"text":"Hallo!"}}
```

`voice_once` mit verfügbarem STT und ABrain:

```text
UI → Core: {"type":"voice_once"}
Core → UI: {"type":"heard","payload":{"text":"was ist heute für ein Tag"}}
Core → UI: {"type":"thinking"}
Core → UI: {"type":"response","payload":{"text":"Montag"}}
```

`voice_once` ohne STT:

```text
UI → Core: {"type":"voice_once"}
Core → UI: {"type":"error","message":"stt not available"}
```

Ungültiges JSON:

```text
UI → Core: not-json
Core → UI: {"type":"error","message":"invalid JSON: ..."}
```

### 2.5 Action Event Model v1

Der Core emittiert **standardisierte Action Events** parallel zu den
klassischen `thinking` / `response` / `heard` / `error`-Nachrichten.
Sie sind die Basis für Avatar-/Präsenz-Reaktionen, UI-Feedback, Logs,
spätere Replay-/Trace-Integration und die zukünftige Desktop-
Interaction-Schicht.

Grundprinzipien:

- **Additiv.** Keine bestehende Nachricht wird verändert oder entfernt.
- **Stabile Action-IDs.** Jede Aktion bekommt eine kurze ID
  (z. B. `act_000001`), mit der UI und Logs zusammengehören.
- **Symbolisches Visual Mapping.** Felder wie `target` und `mapping`
  sind in v1 beschreibend / symbolisch, nicht geometrisch.
- **Unknown-friendly.** Neue Eventtypen und neue `target.type`-Werte
  dürfen additiv dazukommen; unbekannte Felder dürfen ignoriert werden.

#### Eventtypen

| `type`                | Zweck                                                        |
|-----------------------|--------------------------------------------------------------|
| `action_planned`      | Eine Aktion ist erkannt und grob beschrieben.                |
| `action_started`      | Die Aktion beginnt.                                          |
| `action_progress`     | **Reserviert**, heute nicht emittiert.                       |
| `action_step`         | Einzelschritt innerhalb der Aktion.                          |
| `action_verification` | Verifikationsphase (nur Interaction-Executor).               |
| `action_completed`    | Aktion erfolgreich abgeschlossen.                            |
| `action_failed`       | Aktion fehlgeschlagen.                                       |
| `action_cancelled`    | Aktion abgebrochen (Approval-Deny, Timeout, System-Cancel).  |

Ist-Zustand der tatsächlich emittierenden Pfade (Stand PR 14–19):

- `submit_text`: `action_planned` → `action_started` →
  `action_step` → (`thinking` → `response` →) `action_completed`
  bzw. `action_failed`.
- `voice_once`: wie `submit_text` plus `heard`-Envelope nach dem
  STT-Schritt.
- `speak_text`: `action_planned` → `action_started` → `action_step`
  → (bei aktiver TTS-Kette) `speaking_started` → `speaking_ended`
  → `action_completed`/`action_failed`.
- `plan_demo_action` (PR 18): `action_planned` → optional
  `approval_requested` → `approval_resolved` → (bei Approve)
  `action_started` → `action_step` → `action_completed`; sonst
  `action_cancelled` mit sprechender `message`.
- Interaction (`open_application`): seit PR 25 gilt Policy v0 —
  `require_confirmation` ist per Default `true`, also läuft die
  Sequenz `action_planned` → `approval_requested` → (nach
  `approval_approve`) `approval_resolved(approved)` →
  `action_started` → `action_step` → `action_verification` →
  `action_completed`. Bei `denied` / `cancelled` / `timed_out`
  emittiert der Core `approval_resolved` und `action_cancelled`,
  **ohne** vorher `action_started` zu senden.

`action_progress` ist im Enum reserviert, wird heute aber von
**keinem** Emitter genutzt. UIs müssen die Variante tolerieren.

#### Action Kinds (`action_kind`)

`query` · `speech` · `ui` · `system` · `automation` · `unknown`.

In v1 genutzt: `query` (Text an ABrain), `speech` (STT-/TTS-Flow).

#### Phasen (`phase`)

`planned` · `started` · `in_progress` · `verifying` · `completed` ·
`failed` · `cancelled`.

Derzeit transportiert nur `action_started` das Feld `phase`
(Wert `started`). Die übrigen Phasen sind intern/für spätere Phasen
vorgesehen.

#### Target (`target`)

Kleines, abstrahiertes Zielmodell. Varianten (v1):

- `{"type":"application","name":"<name>","hint?":"..."}`
- `{"type":"window","title?":"...","app?":"..."}`
- `{"type":"ui_element","role":"...","label?":"...","hint?":"..."}`
- `{"type":"region","name?":"...","hint?":"..."}`
- `{"type":"unknown"}` — Default für die derzeitigen Flows.

Das Target ist bewusst beschreibend: es sagt, **worauf** sich eine
Aktion richtet, nicht **wo** dieses Ziel pixelgenau liegt.

#### Mapping (`mapping`, optional)

Symbolisches Visual Mapping als Datenmodell; in v1 **nicht**
emittiert, aber im Schema vorhanden:

```json
{ "space": "logical_space", "hint": "towards calendar app" }
```

`space` ∈ `logical_space` · `window_space` · `screen_space`.
`window` ist optional. Geometrie/Koordinaten sind explizit kein Teil
von v1.

#### Fehler (`action_failed`)

`action_failed` trägt ein Pflichtfeld `message` und ein optionales
`error` (Fehlerkontext). Zusätzlich wird weiterhin die bestehende
`error`-Nachricht ausgesendet, damit UIs, die Action Events (noch)
nicht kennen, nicht regressiv werden.

#### Beispiele

`submit_text` (Erfolgspfad):

```text
UI   → Core: {"type":"submit_text","text":"Hallo"}
Core → UI:   {"type":"action_planned","payload":{"action_id":"act_000001","action_kind":"query","title":"Process text request","target":{"type":"unknown"}}}
Core → UI:   {"type":"action_started","payload":{"action_id":"act_000001","phase":"started"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000001","title":"Dispatch to ABrain"}}
Core → UI:   {"type":"thinking"}
Core → UI:   {"type":"response","payload":{"text":"Hallo!"}}
Core → UI:   {"type":"action_completed","payload":{"action_id":"act_000001","status":"completed"}}
```

`voice_once` ohne STT:

```text
UI   → Core: {"type":"voice_once"}
Core → UI:   {"type":"action_planned","payload":{"action_id":"act_000002","action_kind":"speech","title":"Voice request","target":{"type":"unknown"}}}
Core → UI:   {"type":"action_started","payload":{"action_id":"act_000002","phase":"started"}}
Core → UI:   {"type":"error","message":"STT is not available."}
Core → UI:   {"type":"action_failed","payload":{"action_id":"act_000002","status":"failed","message":"STT is not available."}}
```

#### Rückwärtskompatibilität

- `thinking`, `response`, `heard`, `error`, `status`, `pong` bleiben
  unverändert.
- UIs, die Action Events nicht kennen, funktionieren weiter.
- Erst spätere Phasen dürfen die UI stärker auf Action Events
  ausrichten; v1 ist additiv.

#### UI-Projektion: Workflow Overlay (Ziel-Zustand)

Dieser Unterabschnitt beschreibt, wie die UI aus den bestehenden
Action Events einen kleinen symbolischen Workflow-/Action-Readout
rekonstruieren soll. Er ist **Ziel-Zustand**, heute nicht
implementiert. Die Produktsicht steht in
[`ui_architecture.md` §6a/§8a](./ui_architecture.md); die
Architektureinordnung in
[`presence_desktop_interaction.md`](./presence_desktop_interaction.md),
Unterabschnitt „Workflow Overlay als Presence-Erweiterung".

Grundsätze:

- **Projektion, kein Protokoll.** Das Overlay liest die bestehenden
  Action Events und baut daraus einen kleinen sichtbaren Flow auf.
  Es **erzeugt keinen eigenen Event-Typ** und erwartet kein
  separates Workflow-Push vom Core.
- **MVP bevorzugt bestehende Eventtypen.** Der Flow wird aus
  `action_planned` / `action_started` / `action_step` /
  `action_completed` / `action_failed` rekonstruiert, die oben in
  §2.5 bereits vollständig spezifiziert sind.
- **Additiv, nie Pflicht.** Falls zusätzliche Felder später
  sinnvoll werden (siehe unten), dann ausschließlich als
  **optionale** Metadaten an bestehenden Events. Kein Pflichtfeld,
  keine Breaking Change.
- **Keine Pflicht für ein vollständiges Workflow-Graph-Schema im
  MVP.** Smolit ist durch das Overlay ausdrücklich **kein**
  visueller Workflow-Builder, und die API spezifiziert daher keine
  Graph-DSL.

Mögliche zusätzliche, **nicht implementierte** optionale Felder an
den Action Events (nur als Diskussionsgrundlage; keine Pflicht,
keine Zusicherung):

- `step_id` — stabile ID eines Schritts innerhalb eines
  `action_id`.
- `parent_step_id` — optionaler Verweis auf einen vorangegangenen
  Schritt.
- `step_kind` — symbolische Kategorie des Knotens (z. B.
  `trigger` / `step` / `action` / `result`).
- `display_label` — kurzer, symbolischer Anzeige-Text.
- `visual_state_hint` — optionaler Zustands-Hint für das Overlay
  (z. B. `planned` / `active` / `completed` / `failed` /
  `cancelled` / `uncertain`).

Alle fünf Felder sind **ausdrücklich nicht implementiert**, sind
**nicht** Teil des heutigen v1-Protokolls, und dürfen nur dann
ergänzt werden, wenn sie:

- als **optional** und ohne Pflicht-Semantik eingeführt werden,
- bestehende Frames nicht ungültig machen,
- UIs ohne Kenntnis dieser Felder weiterhin funktionieren lassen.

Kein separates `workflow_overlay_update`-Protokoll. Das Overlay
rekonstruiert ausschließlich aus den bestehenden Action Events.

### 2.6 Desktop Interaction Layer MVP

Der Core enthält seit dieser Phase eine Interaction-Schicht
(`core/src/interaction/`), die Desktop-nahe Aktionen modelliert,
ausführt, verifiziert und als Action Events sichtbar macht. Die
Schicht ist bewusst klein und konservativ konfiguriert.

Eingehend:

- `{"type":"interaction_open_application","application":"<name>"}` —
  symbolischer App-Name (`"calendar"`, `"terminal"`, …).
- `{"type":"interaction_focus_window","target":{...}}` — Fokus eines
  Fensters anfordern. `target` ist eine kleine, bewusst schmale
  Struktur (nicht der volle `ActionTarget`):
  - `{"type":"window","name":"<title>"}` — Fenster nach (Teil-)Titel.
    `name` ist ein bequemer Alias für `title`; zusätzlich darf ein
    optionaler `app` mitgegeben werden, um den Treffer zu
    disambiguieren.
  - `{"type":"application","name":"<app>"}` — irgendein Fenster der
    Anwendung fokussieren.

Die Handler rufen intern `App::execute_open_application(name)` bzw.
`App::execute_focus_window(target)` auf, erzeugen einen
`InteractionAction` und führen ihn über den `InteractionExecutor` aus.
Das Ergebnis ist eine Action-Event-Sequenz (und ggf. der Approval-Flow
aus 2.7).

#### Eventfolge (Erfolgspfad, Best-effort)

```text
UI   → Core: {"type":"interaction_open_application","application":"calendar"}
Core → UI:   {"type":"action_planned","payload":{"action_id":"act_000001","action_kind":"automation","title":"Open calendar","description":"interaction:open_application","target":{"type":"application","name":"calendar"}}}
Core → UI:   {"type":"action_started","payload":{"action_id":"act_000001","phase":"started"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000001","title":"Resolving target"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000001","title":"Opening application"}}
Core → UI:   {"type":"action_verification","payload":{"action_id":"act_000001","title":"Best-effort: Spawned open command"}}
Core → UI:   {"type":"action_completed","payload":{"action_id":"act_000001","status":"completed","message":"spawned `gtk-launch` for `calendar` (no window probe yet)"}}
```

Wichtig: Verifikation ist in v1 **"uncertain" / best-effort**. Der Core
spawnt den konfigurierten Launcher und protokolliert den Spawn, prüft
aber **nicht**, ob die Anwendung tatsächlich erschienen ist. Das wird
im `action_verification`-Event durch das `Best-effort:`-Präfix und im
`action_completed`-`message` ehrlich ausgedrückt.

#### Eventfolge `focus_window` (Erfolgspfad, Best-effort)

```text
UI   → Core: {"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}
Core → UI:   {"type":"action_planned","payload":{"action_id":"act_000002","action_kind":"automation","title":"Focus calendar","description":"interaction:focus_window","target":{"type":"window","title":"calendar"}}}
Core → UI:   {"type":"approval_requested","payload":{"approval_id":"apr_000001","action_id":"act_000002","action_kind":"focus_window","title":"Focus calendar","message":"Smolit möchte das Fenster \"calendar\" fokussieren.","target":{"type":"window","title":"calendar"},"timeout_seconds":20}}
// … nach approved:
Core → UI:   {"type":"action_started","payload":{"action_id":"act_000002","phase":"started"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000002","title":"Resolving target"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000002","title":"Focusing window"}}
Core → UI:   {"type":"action_verification","payload":{"action_id":"act_000002","title":"Best-effort: Focus command completed"}}
Core → UI:   {"type":"action_completed","payload":{"action_id":"act_000002","status":"completed","message":"ran `wmctrl` for `calendar` (no focus probe yet)"}}
```

`focus_window` ist plattform-/backendabhängig. Die ehrlichen Zustände:

- **Verified** — tritt im MVP nicht auf (keine Fokus-Probe).
- **Uncertain** — der Fokus-Befehl wurde ohne Fehler ausgeführt, aber
  der Core prüft nicht, ob der Fokus tatsächlich gewechselt ist.
  Default-Ausgang bei Erfolg.
- **Failed** / `BackendUnsupported("focus_window")` — wenn kein
  `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD` konfiguriert ist (z. B. unter
  Wayland ohne Helfer), oder der Helper einen Nicht-Null-Exit liefert.
  Recovery-Hint: `fallback_unavailable` bzw. `retry`.

Der Core versucht **nicht**, auf exotische Sonderpfade auszuweichen —
das Backend sagt ehrlich „das geht hier gerade nicht" und überlässt die
Entscheidung der UI / dem Nutzer.

Dieser Zustand ist per PR 23 (2026-04-24) als finaler MVP-Stand
bestätigt: Option 1 („template-basierter X11-Backend via
`wmctrl -a {name}`, sonst honest `BackendUnsupported`") bleibt;
kein Wayland-Fokus-Pfad, keine Fokus-Probe. Details in
[`docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`](./reviews/PR23_FOCUS_WINDOW_DECISION.md).

#### Eventfolge (Fehlerpfade)

Wenn der Layer deaktiviert ist, ein Kind nicht erlaubt ist, das
Open-App-Command-Template fehlt, oder der Backend-Spawn scheitert,
endet die Sequenz nach `action_started` (bzw. nach den Steps) mit:

```json
{"type":"action_failed","payload":{"action_id":"act_00000X","status":"failed","message":"...","error":"recovery_hint=<hint>"}}
```

Das Feld `error` enkodiert einen klassifikatorischen Recovery-Hinweis:

- `recovery_hint=retry` — Spawn schlug fehl, retry ist sinnvoll.
- `recovery_hint=abort` — Preconditions fehlen (z. B. leerer App-Name);
  Retry ohne Änderung bringt nichts.
- `recovery_hint=ask_user` — Bestätigung/Eingabe notwendig (z. B. wenn
  die Aktion `requires_confirmation=true` trägt und der globale
  `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION` aktiv ist). Der
  Confirmation-Kanal ist seit PR 17 / PR 25 verdrahtet; siehe §2.7
  und [`docs/security/APPROVAL_UX.md`](./security/APPROVAL_UX.md).
- `recovery_hint=fallback_unavailable` — Kind ist vom Backend
  strukturell nicht unterstützt (z. B. `type_text` / `send_shortcut`
  in diesem MVP) oder per Config deaktiviert.

#### Action-Kind und Target

Interaction-Aktionen werden als `action_kind: "automation"` geplant.
Das `target` übernimmt die Variante aus `crate::actions::ActionTarget`
(typisch `{"type":"application","name":"..."}`). Das Feld
`description` trägt einen technischen Hinweis der Form
`"interaction:<kind>"` (z. B. `"interaction:open_application"`), damit
Logs/Replays die Interaction-Herkunft klar erkennen, ohne die UI
darauf festzulegen.

#### Config (Überblick)

- `SMOLIT_INTERACTION_ENABLED` (Default `true`) — Layer insgesamt
  an/aus.
- `SMOLIT_INTERACTION_BACKEND` (Default `command`) — aktives Backend;
  für MVP nur `command`.
- `SMOLIT_INTERACTION_ALLOW_OPEN_APP` (Default `true`) —
  `open_application` erlaubt?
- `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW` (Default `false`) —
  `focus_window` erlaubt? Konservativ standardmäßig aus; in Kombination
  mit `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=true` bleibt auch nach
  dem Opt-In jede Aktion freigabepflichtig.
- `SMOLIT_INTERACTION_ALLOW_TYPE_TEXT` (Default `false`) — `type_text`
  erlaubt? (Backend liefert dennoch `BackendUnsupported`.)
- `SMOLIT_INTERACTION_ALLOW_SHORTCUTS` (Default `false`) —
  `send_shortcut` erlaubt? (Analog MVP-Stub.)
- `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION` (Default `true`) — Policy;
  freigabepflichtige Aktionen laufen über den Approval-Flow (2.7).
- `SMOLIT_INTERACTION_OPEN_APP_CMD` (Default *leer*) — Command-Template
  für Open-App, z. B. `xdg-open {name}` oder `gtk-launch {name}`.
- `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD` (Default *leer*) —
  Command-Template für Focus-Window. Platzhalter: `{name}` (bevorzugter
  Ziel-String, Titel oder App), `{title}`, `{app}`. Beispiel auf X11:
  `wmctrl -a {name}`. Unter Wayland existiert kein generisches
  Äquivalent — leer lassen, der Core meldet dann ehrlich
  `BackendUnsupported("focus_window")`.

Ohne ein Command-Template meldet der Backend für die jeweilige
Operation ehrlich „preconditions not met" bzw. `BackendUnsupported` —
das Verhalten ist damit deterministisch und ungefährlich.

#### Policy v0 Defaults (PR 25)

Die obigen Default-Werte sind in
[`core/src/config.rs`](../core/src/config.rs) als
`DEFAULT_INTERACTION_*`-Konstanten fixiert; der Tripwire-Test
`policy_v0_defaults_are_locked` schlägt an, wenn jemand die Baseline
flippt.

Zusammengefasst: ein Start ohne `SMOLIT_INTERACTION_*`-Env-Vars
liefert

- `open_application` **erlaubt**, aber **approval-gated**,
- `focus_window` **gesperrt** (doppeltes Opt-in nötig: Flag **und**
  X11-Template `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`),
- `type_text` / `send_shortcut` **gesperrt** *und* ohne Backend —
  ein Flip der Env-Variablen schaltet sie **nicht** aktiv.

`SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=0` ist ein reiner Test-
Hebel; produktive Läufe belassen den Default `true`. Details und
Reality-Check:
[`docs/security/APPROVAL_UX.md`](./security/APPROVAL_UX.md) (Abschnitt
„Policy v0") und [`docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md).

#### Scope-Grenzen (explizit)

- **Keine** OCR / Pixel-Matching / Button-Erkennung per Vision.
- **Keine** Accessibility-Vollintegration (AT-SPI / UIA).
- **Keine** Window-Probe nach dem Spawn — Verification bleibt
  „uncertain".
- **Keine** globale Tastatur-/Mausinjektion: `type_text` /
  `send_shortcut` sind nur als Hooks modelliert und liefern
  `BackendUnsupported`.
- **Keine** Fensterliste, keine a11y-basierte Fenstersuche — der
  Core reicht die symbolischen Felder an das Command-Template weiter
  und überlässt dem externen Helper (z. B. `wmctrl -a`), was er daraus
  macht. Keine Sonderpfade für Wayland.
- **Keine** Fokus-Probe nach dem Helfer-Aufruf — `focus_window` meldet
  bei Erfolg konsequent `uncertain` statt `verified`.
- **Keine** Eingabe in sensible Dialoge (Anmelde-, Zahlungs-, System-
  dialoge) geplant; erst eine spätere Phase definiert Trust-Stufen
  (siehe [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  §10 Future Work und §11 Explicit Non-goals).

---

### 2.7 Approval / Confirmation Flow MVP

Aktionen, die laut `InteractionAction.requires_confirmation` und
`InteractionConfig.require_confirmation` freigabepflichtig sind, werden
vom Core **nicht** mehr stumm abgelehnt. Stattdessen tritt der Core in
einen expliziten Dialog mit der UI:

1. Core emittiert `action_planned` wie gewohnt.
2. Core emittiert `approval_requested` mit einer Beschreibung der
   geplanten Aktion.
3. Core wartet auf ein passendes `approval_response` (oder auf den
   konfigurierten Timeout).
4. Bei `approved` läuft der Executor durch und emittiert
   `action_started` → `action_step*` → `action_verification` →
   `action_completed` / `action_failed`.
5. Bei `denied`, `cancelled` oder Timeout emittiert der Core
   `approval_resolved` und anschließend `action_cancelled`.

Die Zuordnung erfolgt über die `approval_id`; jede UI-Instanz kann
sie eindeutig einem `action_id` zuordnen.

#### Eingehend (UI → Core)

- `approval_response` — Antwort auf ein zuvor empfangenes
  `approval_requested`. Felder:
  - `approval_id: string`
  - `decision: "approved" | "denied" | "cancelled"`

  Idempotent: eine zweite Antwort mit gleicher `approval_id` erzeugt
  einen `error`-Frame.

- `approval_approve` — schmaler Pfad (PR 17), entspricht wire-seitig
  `approval_response` mit `decision="approved"`. Beide Commands
  teilen sich dieselbe Pending-Approval-Registry; die Idempotenz
  gilt envelope-übergreifend.
  Felder: `approval_id: string`.

- `approval_deny` — Gegenstück zu `approval_approve` mit
  `decision="denied"`. Felder: `approval_id: string`.

- `request_approval_demo` — **harmloser Demo-Auslöser** (PR 17).
  Erzeugt ein pending Approval **ohne** Backend-Aktion; nach dem
  `approval_resolved`-Envelope passiert *nichts* weiter. Dient
  ausschließlich zur UX-Evaluation der Approval-Card. Felder (alle
  optional):
  - `title: string` (Default: "Demo approval")
  - `summary: string` (Default: kurzer Sicherheitshinweis)
  - `risk: "low" | "medium" | "high"` (Default: `medium`; unbekannte
    Werte fallen auf `medium`)

  **Nicht** erlaubt in diesem Command: echte Aktionen, Shell-
  Invokation, Desktop-Automation, Provider-Aufrufe.

- `plan_demo_action` — **Approval-Gated Demo-Action-Planner** (PR 18).
  Erzeugt einen kleinen, harmlosen `DemoPlan` im Core und spielt
  dessen Lebenszyklus durch den bestehenden Action-Event-Strom. Der
  Core führt einen **reinen Mock** aus (`action_planned` → optional
  `approval_requested` → `approval_resolved` → `action_started` →
  `action_step` → `action_completed` bzw. `action_cancelled`). Es
  gibt **keinen** Shell-, Dateisystem-, Desktop- oder Provider-
  Aufruf. Felder (alle optional):
  - `title: string` (Default: "Demo action")
  - `summary: string` (Default: kurzer Sicherheitshinweis)
  - `risk: "low" | "medium" | "high"` (Default: `medium`)
  - `kind: "demo_echo" | "demo_wait" | "noop"` (Default: `noop`;
    unbekannte Werte fallen auf `noop` — die sicherste Default-Aktion)
  - `requires_approval: bool` (Default: `false`)

  Ist `requires_approval=false`, läuft der Mock unmittelbar
  (`planned → started → step → completed`) ohne Approval-Klammer.
  Ist `requires_approval=true`, emittiert der Core ein
  `approval_requested` und **blockiert** den Executor, bis eine
  `approval_approve`/`approval_deny`-Entscheidung (oder ein Timeout)
  vorliegt:
  - `approved` → `approval_resolved(approved, user)` gefolgt von
    `action_started → action_step → action_completed`.
  - `denied` / `cancelled` → `approval_resolved(denied|cancelled)`
    gefolgt von `action_cancelled` mit sprechender `message`. Kein
    Mock-Step läuft.
  - `timed_out` → `approval_resolved(timed_out, timeout)` gefolgt
    von `action_cancelled(message="Approval expired")`. Kein
    Mock-Step läuft.

  **Idempotenz:** ein zweiter `approval_approve`/`approval_deny` auf
  dieselbe `approval_id` landet als `error`-Frame; der Executor läuft
  nicht ein zweites Mal. **Nicht** erlaubt: echte Aktionen, Shell,
  Desktop-Automation, Provider-Mutationen, Dateioperationen.

- `audit_recent` (PR 19, seit PR 32 mit Coverage für reale
  Interaction-Actions) — **read-only** Abfrage des lokalen
  In-Memory-Audit-Ringbuffers. Felder:
  - `limit: integer` (optional, auf `1000` hart geklemmt).
    Standardmäßig liefert der Core den vollen Ringbuffer-Inhalt.

  Antwort: `audit_recent`-Envelope mit
  `payload.events: AuditEvent[]`, neueste zuletzt. Jeder
  `AuditEvent` enthält:
  - `audit_id: string` (`aud_NNNNNN`)
  - `timestamp_ms: integer` (Unix epoch ms)
  - `kind: string` — einer aus
    `ipc_command_received` / `ipc_command_rejected` /
    `action_planned` / `approval_requested` / `approval_resolved` /
    `action_started` / `action_completed` / `action_cancelled` /
    `action_failed`
  - optional `action_id: string`, `approval_id: string`,
    `risk: "low"|"medium"|"high"`, `result: string`,
    `source: "user"|"timeout"|"system"|"ui"|"core"`,
    `summary: string` (hart auf 80 Zeichen gekürzt, Whitespace
    gestrippt). Felder ohne Wert werden nicht serialisiert.

  Seit PR 32 (2026-04-24) erfasst der Ring-Buffer **zusätzlich zum
  `plan_demo_action`-Pfad** den echten
  `interaction_open_application` / `interaction_focus_window`-
  Lifecycle (IPC-Command-Received → Action-Planned → optional
  Approval-Requested / Approval-Resolved → Action-Started →
  Action-Completed / Action-Cancelled / Action-Failed). Der
  Summary-Text der Real-Interaction-Pfade ist von der Form
  `interaction_<kind>: <action_title>` — **kein** Command-Template,
  **kein** Env-Name, **kein** Secret aus dem
  Secrets-Store (siehe
  [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md)
  Abschnitt „Coverage für reale Interaction-Actions (PR 32)").

  **Keine** Persistenz, **kein** Export, **keine** Schreib-Variante,
  **kein** `audit_clear` — PR 32 erweitert die Coverage, aber nicht
  die Oberfläche. Siehe
  [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md)
  für Datenschutz-Grenzen und Zukunftsüberlegungen.

#### Ausgehend (Core → UI)

- `approval_requested` — Core bittet um Freigabe. `payload` ist eine
  `ApprovalRequest` mit den Feldern `approval_id`, `action_id`,
  `action_kind`, `title`, `message`, `target`, optional `reason`,
  `timeout_seconds`. PR 17 fügt additiv `risk: "low" | "medium" |
  "high"` hinzu (Default `medium`; ältere Emitter kommen weiterhin
  an — das Feld wird mit einem serde-Default ergänzt). Für
  `request_approval_demo`-Approvals ist `action_id` ein **leerer
  String** (kein Backend-Action vorhanden); UIs müssen das tolerieren.
- `approval_resolved` — Endergebnis der Freigabe. `payload.decision`
  ist einer der Strings `approved`, `denied`, `cancelled`,
  `timed_out`. Wird vor dem endgültigen `action_completed` bzw.
  `action_cancelled` emittiert. PR 17 fügt additiv
  `source: "user" | "timeout" | "system"` hinzu (Default `user`):
  `user` für UI-Entscheidungen, `timeout` für den Watchdog, `system`
  für core-interne Abbrüche. Für `request_approval_demo`-Approvals
  folgt **kein** `action_cancelled` — die Demo-Kette endet mit dem
  Resolve-Envelope.

`approval_resolved` ist eine Bestätigung für die UI, unabhängig vom
anschließenden Action-Event-Strom. `timed_out` tritt nur core-intern
auf (die UI kann es nicht selbst senden).

#### Fehlerfälle

- **Unbekannte `approval_id`** (nie gesehen oder bereits aufgelöst):
  Core antwortet mit einem `error`-Frame, der Action-Strom bleibt
  unberührt.
- **Timeout** (`SMOLIT_APPROVAL_TIMEOUT_SECONDS`, Default 20):
  Core emittiert `approval_resolved { decision: "timed_out" }` und
  `action_cancelled`.
- **UI nicht verbunden**: Das `approval_requested`-Frame geht verloren,
  der Timeout-Watchdog cancelt die Aktion ordentlich.
- **Core-Restart**: Pending Approvals sind rein in-memory und gehen
  mit einem Neustart verloren — bewusst, keine Persistenz im MVP.

#### Beispiel

```json
// Core → UI
{"type":"action_planned","payload":{"action_id":"act_000001","action_kind":"automation","title":"Open calendar","target":{"type":"application","name":"calendar"}}}
{"type":"approval_requested","payload":{"approval_id":"apr_000001","action_id":"act_000001","action_kind":"open_application","title":"Open calendar","message":"Confirm open_application: Open calendar","target":{"type":"application","name":"calendar"},"timeout_seconds":20}}

// UI → Core
{"type":"approval_response","approval_id":"apr_000001","decision":"approved"}

// Core → UI
{"type":"approval_resolved","payload":{"approval_id":"apr_000001","action_id":"act_000001","decision":"approved"}}
{"type":"action_started","payload":{"action_id":"act_000001","phase":"started"}}
// …step, verification, completed…
```

#### Approval-Scope-Grenzen (explizit)

- Keine Persistenz, kein „remember this choice", kein Global-Policy-UI.
- Kein Multi-User / Multi-Seat — ein einziger UI-Client entscheidet.
- Keine kryptografische Absicherung des Approval-Kanals (lokaler
  Loopback-WebSocket als Vertrauensgrenze).
- `type_text` und `send_shortcut` bekommen keine eigene
  Approval-Semantik — sie bleiben MVP-seitig abgelehnt.

---

### 2.8 Linux Accessibility Backend Spike (Ist-Zustand, Spike)

Der Core enthält seit dieser Phase einen ersten, bewusst kleinen
Spike für ein Linux-spezifisches Accessibility-Backend
(`core/src/interaction/accessibility.rs`). Das Spike sitzt als
getrennter Capability-Pfad neben dem bestehenden `CommandBackend` im
Interaction Layer und ist **read-only**: er probt Umgebung und
symbolische Discovery, ohne Eingaben zu erzeugen, ohne zu klicken,
ohne zu schreiben.

Ausdrücklicher Scope:

- **Probe.** Entscheidet anhand der Session-Umgebung (Linux-Check,
  `WAYLAND_DISPLAY` / `DISPLAY`, `DBUS_SESSION_BUS_ADDRESS`,
  optional vorhandener Unix-Socket) ob ein AT-SPI-Pfad plausibel ist.
- **Discovery / Inspection.** Entweder Top-Level-Discovery
  (ohne `hint`) oder Inspection eines symbolischen Targets (mit
  `hint`). Liefert honest `uncertain`/`unavailable`/`failed`.
- **Kein RPC.** Das Spike spricht **nicht** mit dem AT-SPI-Registry;
  der echte RPC-Pfad (zbus/atspi) ist ausdrücklich Folgearbeit.

> **PR 37 — Decision only:** Der Rahmen für einen späteren RPC-Pfad
> ist seit 2026-04-24 in [`ADR-0002`](./adr/ADR-0002-accessibility-rpc-readonly.md)
> entschieden (Docs/ADR-only, keine Code-Implementation): read-only
> `GetChildren` am Registry-Root, `atspi`+`zbus` hinter einem
> `accessibility_rpc`-Feature-Flag (default-off), keine Input-
> Injection, kein `DoAction`, kein Baum-Walk über eine Tiefe hinaus,
> keine Passwort-/Secret-Felder, kein Approval-Bypass. Das
> Wire-Schema in diesem Abschnitt bleibt unverändert; der RPC-Pfad
> füllt bestehende Felder. `confidence: verified` bleibt exklusiv
> für Items mit Registry-Evidenz.

#### Eingehend

- `{"type":"interaction_probe_accessibility"}` — startet die
  Capability-Probe. Braucht keine Parameter, braucht keine Approval,
  verändert nichts am Desktop.
- `{"type":"interaction_discover_accessibility"}` — Top-Level-
  Discovery.
- `{"type":"interaction_discover_accessibility","hint":"<name>"}` —
  Inspection eines Targets per symbolischem Hinweis.

#### Ausgehend

- `accessibility_probe_result` mit `payload: AccessibilityProbe`.
- `accessibility_discovery_result` mit
  `payload: AccessibilityDiscovery`.

Beide Payloads sind getagte Enums mit einem `"status"`-Feld:

```json
{"type":"accessibility_probe_result",
 "payload":{"status":"uncertain","reason":"session=wayland, dbus-session-bus present, AT_SPI_BUS_ADDRESS unset (typical; resolved via registry); RPC probe not yet implemented"}}
{"type":"accessibility_probe_result",
 "payload":{"status":"unavailable","reason":"DBUS_SESSION_BUS_ADDRESS is unset"}}
{"type":"accessibility_discovery_result",
 "payload":{"status":"uncertain",
            "reason":"… AT-SPI RPC discovery (registry root GetChildren) is not yet wired up",
            "items":[]}}
{"type":"accessibility_discovery_result",
 "payload":{"status":"ok",
            "reason":"session=wayland, dbus-session-bus present, …; hint echoed as structured target (confidence=discovered)",
            "items":[
              {"kind":"application",
               "name":"Firefox",
               "confidence":"discovered",
               "source":"accessibility_hint_echo",
               "role":"application",
               "detail":"hint echoed; no AT-SPI RPC confirmation yet",
               "matched_hint":"Firefox",
               "app_name":"Firefox"}
            ]}}
```

Pro Item werden folgende Felder transportiert:

| Feld           | Typ     | Bedeutung                                                    |
| :------------- | :------ | :----------------------------------------------------------- |
| `kind`         | String  | Grobes Ziel-Kind (`application` / `window` / `frame`).       |
| `name`         | String  | Best-effort-Anzeigename.                                     |
| `confidence`   | String  | `verified` \| `discovered` — Semantik siehe unten.           |
| `source`       | String  | Provenienzlabel, z. B. `accessibility_hint_echo`.            |
| `role`         | String? | Optionaler AT-SPI-Role-Hinweis.                              |
| `hint`         | String? | Optionale freie Beschreibung.                                |
| `detail`       | String? | Optionale Kurzinfo für die UI.                               |
| `matched_hint` | String? | Original-Hinweis, wenn das Item aus `inspect_target` stammt. |
| `app_name`     | String? | Optionaler umgebender App-Name.                              |

Optionale Felder erscheinen nur, wenn sie belegt sind
(`#[serde(skip_serializing_if = "Option::is_none")]`).

#### Eventfolge (Probe, Erfolgspfad)

```text
UI   → Core: {"type":"interaction_probe_accessibility"}
Core → UI:   {"type":"action_planned","payload":{"action_id":"act_000010","action_kind":"system","title":"Probe accessibility backend","target":{"type":"unknown"}}}
Core → UI:   {"type":"action_started","payload":{"action_id":"act_000010","phase":"started"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000010","title":"Checking session environment"}}
Core → UI:   {"type":"action_verification","payload":{"action_id":"act_000010","title":"Probe: uncertain"}}
Core → UI:   {"type":"accessibility_probe_result","payload":{"status":"uncertain","reason":"…"}}
Core → UI:   {"type":"action_completed","payload":{"action_id":"act_000010","status":"completed","message":"uncertain: …"}}
```

#### Eventfolge (Discovery, unavailable-Pfad)

```text
UI   → Core: {"type":"interaction_discover_accessibility"}
Core → UI:   {"type":"action_planned","payload":{"action_id":"act_000011","action_kind":"system","title":"Discover top-level accessibles","target":{"type":"unknown"}}}
Core → UI:   {"type":"action_started","payload":{"action_id":"act_000011","phase":"started"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000011","title":"Probing accessibility backend"}}
Core → UI:   {"type":"action_step","payload":{"action_id":"act_000011","title":"Discovering top-level accessibles via AT-SPI probe"}}
Core → UI:   {"type":"action_verification","payload":{"action_id":"act_000011","title":"Discovery: unavailable"}}
Core → UI:   {"type":"accessibility_discovery_result","payload":{"status":"unavailable","reason":"no WAYLAND_DISPLAY or DISPLAY in environment"}}
Core → UI:   {"type":"action_failed","payload":{"action_id":"act_000011","status":"failed","message":"unavailable: no WAYLAND_DISPLAY or DISPLAY in environment","error":"recovery_hint=fallback_unavailable"}}
```

#### Semantik der Discovery-Status-Werte

- **`ok`** — Discovery wurde ausgeführt und hat mindestens ein
  strukturiertes Item zurückgegeben. Heute produziert das ausschließ­
  lich der Hint-Echo-Pfad von `inspect_target(hint)`: ein einziges
  Item mit `confidence=discovered` und `source=accessibility_hint_echo`.
  Der echte RPC-Pfad (zbus / atspi-connection, Registry-Walk) ist
  Folgearbeit.
- **`uncertain`** — Umgebungsprobe plausibel, Discovery wurde
  versucht, aber ohne strukturierbares Ergebnis. Heute der Default
  für `discover_top_level()` auf einem realen Linux-Desktop, solange
  kein RPC-Client existiert.
- **`unavailable`** — Eine konkrete Voraussetzung fehlt (nicht
  Linux, weder `DISPLAY` noch `WAYLAND_DISPLAY`, keine
  `DBUS_SESSION_BUS_ADDRESS`, fehlender Session-Bus-Socket, leerer
  Hint bei `inspect_target`).
- **`failed`** — Reserviert für unerwartete Fehler beim Probe- oder
  Discovery-Schritt selbst. In der aktuellen environment-only-
  Implementierung tritt das nicht auf; das Feld existiert, damit ein
  zukünftiger RPC-basierter Pfad einen eigenen Fehlerpfad bekommt.

Beim `AccessibilityProbe` entfällt der `ok`-Status: der Probe ist
**immer** ohne echten RPC-Roundtrip, also reicht die Trias
`uncertain` / `unavailable` / `failed`.

#### Semantik der Confidence-Werte (pro Item)

- **`verified`** — **Reserviert.** Für einen echten RPC-Pfad, der ein
  Target direkt aus der AT-SPI-Registry bestätigt hat. Der aktuelle
  Spike emittiert niemals `verified` — sonst würde er Sicherheit
  behaupten, die er technisch nicht hat.
- **`discovered`** — Das Item wird als strukturiertes Target weiter­
  gereicht, ist aber nicht unabhängig verifiziert. Heute das Label
  für Hint-Echo-Items: „die UI hat mir diesen Namen genannt, ich
  führe ihn in der Schemaform weiter, aber ich habe ihn nicht gegen
  die Accessibility-Registry abgeglichen."

UI-seitig gilt: **`discovered` darf nicht still zu `verified`
aufgewertet werden.** Das ist eine Core-Entscheidung, keine
Darstellung.

#### Scope-Grenzen des Accessibility-Spikes

- **Keine** Tastatur-/Maus-Injektion.
- **Keine** Button-/Feld-Automation, kein generisches Klicken.
- **Keine** Form-Befüllung, keine Passwort-/Secret-Felder.
- **Keine** Tree-Walker-UI, keine tiefe Baumstruktur.
- **Keine** App-spezifischen Adapter (Browser, Electron, GTK, Qt,
  Terminal — alle behandeln Accessibility unterschiedlich).
- **Keine** OCR / Pixel-Vision.
- **Keine** Wayland-Fokussteuerung — Window-Overlay-Themen bleiben
  eine separate Linie (siehe
  `docs/linux_window_overlay_architecture.md`, falls vorhanden; das
  Accessibility-Backend ist **nicht** dasselbe wie ein Overlay).
- **Kein** Approval-Flow für Probe/Discovery — beide sind
  read-only und können in dieser Phase ohne Freigabe laufen. Sobald
  ein Pfad fokussieren, schreiben oder klicken soll, muss er
  zurück durch den bestehenden Approval-Flow (2.7).

---

### 2.9 Target Selection (Ist-Zustand, MVP)

Zwischen Discovery und Execution sitzt eine kleine, ehrliche
Zwischenstufe: die UI kann ein entdecktes Target als **aktuellen
Interaction-Kontext** markieren. Der Core hält dafür genau einen Slot
im Speicher — kein persistenter Store, keine Multi-Target-Historie,
kein globales Memory.

**Wichtig:** Auswahl ≠ Berechtigung. Ein ausgewähltes Target bedeutet
nur „das ist wahrscheinlich das richtige Ziel", nicht „Smolit darf
jetzt damit etwas tun". Jede Folgeaktion geht weiterhin durch den
Approval-Flow (2.7).

#### Target-Selection — Eingehend (UI → Core)

- `interaction_select_target` — Wählt ein Target aus einer
  Discovery-Antwort oder einer ähnlichen Quelle aus. Der Core
  validiert (`name`, `role`, `confidence`) und speichert. Bei leerem
  `id` weist der Core eine fortlaufende `sel_NNNNNN`-ID zu.

  ```json
  {
    "type": "interaction_select_target",
    "target": {
      "id": "sel_ui_1",
      "name": "calendar",
      "role": "window",
      "source": "accessibility",
      "confidence": "discovered",
      "matched_hint": "calendar"
    }
  }
  ```

- `interaction_clear_target` — Verwirft die aktuelle Auswahl.
  Idempotent: die Antwort ist immer `target_cleared`, unabhängig davon
  ob etwas zu räumen war.

  ```json
  { "type": "interaction_clear_target" }
  ```

#### Target-Selection — Ausgehend (Core → UI)

- `target_selected` — Bestätigt die Auswahl und liefert das vom Core
  normalisierte Target. Die UI nutzt diese Antwort als Quelle der
  Wahrheit; das eigene Request-Payload wird nicht direkt gerendert.

  ```json
  {
    "type": "target_selected",
    "payload": {
      "target": {
        "id": "sel_000001",
        "name": "calendar",
        "role": "window",
        "source": "accessibility",
        "confidence": "discovered",
        "matched_hint": "calendar"
      }
    }
  }
  ```

- `target_cleared` — Bestätigt die Räumung. `previous` ist das
  vorherige Target, sofern eines gehalten wurde; fehlt es, war der
  Slot ohnehin leer.

  ```json
  {
    "type": "target_cleared",
    "payload": {
      "previous": {
        "id": "sel_000001",
        "name": "calendar",
        "role": "window",
        "source": "accessibility",
        "confidence": "discovered"
      }
    }
  }
  ```

#### Target-Schema

| Feld            | Typ      | Bedeutung                                                                 |
| --------------- | -------- | ------------------------------------------------------------------------- |
| `id`            | string   | Session-lokale ID; leer → Core vergibt `sel_NNNNNN`.                      |
| `name`          | string   | Anzeigename; Pflicht, nicht leer.                                         |
| `role`          | string   | `"application"` / `"window"` / `"ui_element"` / `"region"` / `"unknown"`. |
| `source`        | string   | Provenienz, Default `"accessibility"`.                                    |
| `confidence`    | string   | `"verified"` \| `"discovered"` (aus der Discovery-Quelle übernommen).     |
| `matched_hint`  | string?  | Ursprünglicher Hint, falls aus `inspect_target` stammend.                 |
| `app_name`      | string?  | Einhüllende Anwendung, wenn ableitbar.                                    |

Validierungsfehler (`name`/`role` leer, unbekannte `confidence`)
erzeugen ein `error`-Envelope; die bestehende Auswahl bleibt
unverändert.

#### Approval-Kopplung

Wenn beim Auslösen einer Interaction ein Target ausgewählt ist, nimmt
der Core einen **Snapshot** in die `ApprovalRequest` auf:

- `approval_requested.payload.selected_target` trägt das aktive
  Target (1:1 wie das `target_selected`-Payload).
- `approval_requested.payload.message` hängt einen `Ziel: name (role,
  confidence)`-Zusatz an, damit Nutzer:innen sehen *was* angeklickt
  werden soll und *wo*.

Diese Integration ist rein deskriptiv. Der Core leitet aus dem
gehaltenen Target **keine** zusätzlichen Rechte ab — die üblichen
Policy-Checks und der Approval-Flow laufen unverändert.

#### Reset

Die UI muss Auswahl-Zustand in mindestens diesen Fällen aktiv verwerfen:

- expliziter Klick auf „Clear".
- `ipc_disconnected` (Core-Zustand wird beim Reconnect neu gelesen).
- nicht behebbarer Fehler im eigenen Flow (optional — kein Muss).

#### Scope-Grenzen der Target Selection

- **Keine** automatischen Aktionen nach der Auswahl.
- **Kein** persistenter Target-Store, keine Cross-Session-Memory.
- **Keine** Multi-Target-Chains oder implizite Target-Historie.
- **Keine** fuzzy/smart Matching-Logik; die UI schickt, was sie aus
  der Discovery hat.
- **Keine** direkte A11y-Execution — Discovery und Selection enden
  hier, Execution läuft weiterhin über das bestehende Interaction-
  Backend inkl. Approval.

### 2.10 Settings-Schreib-/Probe-Pfad (Ist-Zustand, PR 5 + PR 7 + PR 8 + PR 9 + PR 10 + PR 11 + PR 12 + PR 13)

Kleine, kuratierte Schreib-/Diagnose-Oberfläche für die Settings-
Shell. Additiv zum bestehenden Protokoll, keine neue
Nachrichtenfamilie. Der heutige Scope umfasst `llamafile_local`-Felder
(PR 5), STT-/TTS-Command-Provider (PR 7), den lokalen HTTP-
Text-Provider `local_http` (PR 8), die Text-Provider-Fallback-
Kette (PR 9), den ersten Cloud-/Remote-Text-Provider `cloud_http`
mit dediziertem Secret-Pfad (PR 10), sicheres HTTPS/TLS für
`cloud_http` (PR 11), einen authentifizierten Application-Layer-
Probe-Roundtrip (PR 12) und seit PR 13 zusätzlich editierbare
STT-/TTS-Provider-Fallback-Ketten.

> **PR 36 (Settings Shell UX Cleanup) ändert am IPC-Vertrag
> nichts.** Weder neue Commands noch neue `StatusPayload`-Felder
> werden eingeführt; der Cleanup lebt ausschließlich im UI-Renderer
> ([`SettingsSections`](../ui/scripts/settings/settings_sections.gd))
> und fügt visuelle Gruppierung (Summary / Details / Safety notes)
> plus eine Opt-in-Note im Text-Chain-Editor hinzu. Der Smoke-Guard
> `_check_no_new_ipc_command_helpers_in_controller` hält diese
> Invariante live. Details:
> [`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md)
> §13.

**Eingang:** `settings_set_llamafile_config`.

```json
{
  "type": "settings_set_llamafile_config",
  "enabled": true,
  "mode": "on_demand",
  "idle_timeout_seconds": 300,
  "path": "/opt/llamafile/server"
}
```

- `enabled` (bool, Pflicht) — spiegelt `SMOLIT_LLAMAFILE_ENABLED`.
- `mode` (string, optional) — `"on_demand"` oder `"standby"`.
  Unbekannte Werte ergeben ein `error`-Envelope; die Shell fällt
  **nicht** still auf den Default zurück, weil der Schreibpfad
  explizit ist.
- `idle_timeout_seconds` (unsigned integer, optional) — Watchdog-
  Fenster. `0` wird als Fehler abgelehnt.
- `path` (string, optional) — Pfad zum llamafile-Binary.
  Leerer/whitespace-String löscht den Pfad. Fehlendes Feld lässt
  ihn unverändert.
- Nicht editierbar über diesen Pfad: `port`, `startup_timeout_seconds`,
  `request_timeout_seconds`. Diese bleiben env-gesteuert.

Erfolg → der Core persistiert den neuen Stand in einer kleinen
JSON-Datei (Dateiname `llamafile_local.json`; Verzeichnis-Lookup
`SMOLIT_SETTINGS_DIR` → `$XDG_CONFIG_HOME/smolit-assistant/` →
`$HOME/.config/smolit-assistant/`, Permissions 0600), rebuildet den
`TextProviderResolver` mit der neuen Llamafile-View und antwortet
mit einem frischen `status`-Envelope. Fehler → `error`-Envelope mit
kurzer Meldung (Secret-frei).

**Eingang:** `settings_probe_llamafile`.

```json
{"type":"settings_probe_llamafile"}
```

Keine Side-Effects (kein Spawn, kein HTTP). Der Core prüft Chain-
Mitgliedschaft, Master-Flag, Path-Existenz, Regular-File-Status und
Execute-Bit (Unix). Antwort: `settings_probe_result`.

**Ausgang:** `settings_probe_result`.

```json
{
  "type": "settings_probe_result",
  "payload": {
    "axis": "llamafile",
    "ok": false,
    "class": "path_missing",
    "message": "configured binary path does not exist",
    "lifecycle": "configured",
    "in_chain": true,
    "enabled": true,
    "configured": true
  }
}
```

- `axis` (string, PR 7) — `"llamafile"` / `"stt"` / `"tts"`. Routet
  das Ergebnis in der Settings-Shell in den passenden Editor-Block.
  Ältere Cores ohne dieses Feld fallen UI-seitig auf
  `"llamafile"` zurück.
- `ok` (bool) — `true` nur wenn `class="ok"`.
- `class` (string) — kuratierter Tag. Für `axis="llamafile"`:
  `"ok"` / `"not_in_chain"` / `"disabled"` / `"not_configured"` /
  `"path_missing"` / `"path_not_file"` / `"path_not_executable"`.
  Für `axis="stt"` bzw. `"tts"` zusätzlich `"command_unparseable"`
  (Command-String nach `split` leer).
- `message` (string) — kurze, Secret-freie Begründung. **Enthält
  weder Pfad/Command noch Roh-Fehlerstring.**
- `lifecycle` (string | null) — aktueller Lifecycle (nur Llamafile,
  nur wenn `in_chain=true`). STT/TTS tragen heute kein Lifecycle
  (spawn-on-demand) und senden `null`.
- `in_chain` / `enabled` / `configured` — booleans, spiegeln den
  Entscheidungsbaum des Probes und lassen die UI ohne Extra-
  `get_status` zwischen „config falsch" und „Chain falsch"
  unterscheiden.

#### 2.10a STT-/TTS-Schreib-/Probe-Pfad (PR 7)

`settings_set_stt_config` / `settings_set_tts_config` spiegeln den
Llamafile-Pfad für die Audio-Achsen. Editierbar sind ausschließlich
die Felder, die auch in der Settings-Shell sichtbar sind; Timeouts
und Provider-Chains bleiben env-/Startup-gesteuert, damit eine
zukünftige Cloud-Kette nicht versehentlich über einen alten Override
abgeschaltet wird.

```json
{"type":"settings_set_stt_config","enabled":true,"command":"whisper --model base"}
{"type":"settings_set_tts_config","enabled":true,"command":"espeak -v de","auto_speak":true}
```

- `enabled` (bool, Pflicht) — spiegelt `SMOLIT_STT_ENABLED` bzw.
  `SMOLIT_TTS_ENABLED`.
- `command` (string, optional) — spiegelt `SMOLIT_STT_CMD` /
  `SMOLIT_TTS_CMD`. Leer/whitespace löscht, sonst ersetzt. Fehlendes
  Feld lässt den Wert unverändert.
- `auto_speak` (bool, optional, nur TTS) — spiegelt
  `SMOLIT_AUTO_SPEAK`. Fehlendes Feld lässt den Wert unverändert.

Erfolg → der Core persistiert den neuen Stand in `stt.json` bzw.
`tts.json` (gleiche Verzeichnis-Auflösung und 0600-Permissions wie
der Llamafile-Override), rebuildet den jeweiligen Provider-Resolver
und antwortet mit einem frischen `status`-Envelope.

**Eingang:** `settings_probe_stt` / `settings_probe_tts`.

```json
{"type":"settings_probe_stt"}
{"type":"settings_probe_tts"}
```

Side-Effect-frei: **kein** Mikrofon-Zugriff, **kein** Audio-Output,
**kein** Spawn. Der Core prüft Chain-Mitgliedschaft, Enabled-Flag,
Command-Parsing (`split_command`) und den Filesystem-/Execute-Status
des ersten Tokens. Antwort: `settings_probe_result` mit `axis` auf
`"stt"` bzw. `"tts"`, `lifecycle=null`.

#### 2.10b Local-HTTP-Schreib-/Probe-Pfad (PR 8)

`settings_set_local_http_config` editiert den neuen, allgemeinen
lokalen HTTP-Text-Provider `local_http` (siehe §4 und
[`docs/provider_fallback_and_settings_architecture.md` §4.1](./provider_fallback_and_settings_architecture.md)).
Loopback-first, HTTP-MVP. Keine Secrets, kein TLS.

```json
{"type":"settings_set_local_http_config","enabled":true,"endpoint":"http://127.0.0.1:8080/completion","request_timeout_seconds":60}
```

- `enabled` (bool, Pflicht) — spiegelt `SMOLIT_LOCAL_HTTP_ENABLED`.
- `endpoint` (string, optional) — spiegelt
  `SMOLIT_LOCAL_HTTP_ENDPOINT`. Muss mit `http://` beginnen;
  `https://` wird vom Core **abgelehnt** (eigene Fehlerklasse
  `endpoint_scheme_unsupported`), weil PR 8 keine TLS-/Trust-
  Infrastruktur mitbringt. Leerer/whitespace-String löscht den
  Endpoint.
- `request_timeout_seconds` (unsigned integer, optional) — Zeitbudget
  pro Completion-Request. `0` wird als Fehler abgelehnt. Fehlendes
  Feld lässt den bisherigen Wert stehen.
- Nicht editierbar über diesen Pfad: `prompt_field` / `response_field`.
  Beide bleiben env-/Startup-gesteuert (`SMOLIT_LOCAL_HTTP_PROMPT_FIELD`
  / `SMOLIT_LOCAL_HTTP_RESPONSE_FIELD`), Default
  `"prompt"` / `"content"` — llama.cpp-kompatibel.

Erfolg → der Core persistiert den neuen Stand in `local_http.json`
(gleiche Verzeichnisauflösung wie Llamafile-/STT-/TTS-Overrides,
Permissions 0600), rebuildet den `TextProviderResolver` atomar und
echoed ein frisches `status`-Envelope.

**Eingang:** `settings_probe_local_http`.

```json
{"type":"settings_probe_local_http"}
```

Side-Effect-frei im Sinne des Nutzer-Prompts: **kein**
Completion-Request, **kein** Prompt-Versand. Der Core parst den
Endpoint, macht einen TCP-Connect auf `host:port` (mit kleinem
Timeout von höchstens 30 s) und liefert eine kuratierte Klasse:

- `"ok"` — TCP-Connect gelang.
- `"not_in_chain"` / `"disabled"` / `"not_configured"` — wie bei den
  anderen Achsen.
- `"endpoint_scheme_unsupported"` — `https://` wurde konfiguriert.
- `"endpoint_unparseable"` — URL konnte nicht geparst werden.
- `"http_connect_failed"` — TCP-Connect schlug fehl.
- `"timeout"` — TCP-Connect lief in den Zeitrahmen.

Antwort: `settings_probe_result` mit `axis="local_http"`,
`lifecycle=null`. Der konfigurierte Endpoint taucht **nicht** im
Response-Body auf; `message` bleibt kuratiert.

#### 2.10c Text-Provider-Chain-Editor (PR 9)

`settings_set_text_provider_chain` editiert die geordnete Text-
Provider-Fallback-Kette. Scope bewusst klein: nur **bekannte** Kinds
(`abrain` / `llamafile_local` / `local_http`); keine freie
Namens-eingabe, keine STT-/TTS-Chain-Editoren, keine Cloud-Kinds.

```json
{"type":"settings_set_text_provider_chain","chain":["llamafile_local","local_http","abrain"]}
```

- `chain` (string[], Pflicht) — geordnete Liste. Elemente werden
  vor der Validierung **lowercased** und **getrimmt**.

Validierungsregeln (siehe
[`crate::providers::text::validate_text_chain`](../core/src/providers/text.rs)):

1. **Leere Kette** → Fehler `text provider chain is empty (use reset
   to restore default)`. Kein stiller Fallback auf den Default, damit
   die UI den Nutzer zu einer bewussten Entscheidung zwingt
   (Reset-Knopf → `settings_reset_text_provider_chain`).
2. **Unbekannter Kind** → Fehler
   `unknown text provider kind \`KIND\` (known: abrain, llamafile_local, local_http)`
   (Platzhalter `KIND` steht für den abgelehnten Rohwert).
3. **Duplikat** → Fehler
   `duplicate text provider kind \`KIND\` in chain`.

Erfolg → der Core persistiert die normalisierte Kette in
`text_chain.json` (gleiche Verzeichnisauflösung und
0600-Permissions wie bei den anderen Override-Files), rebuildet den
`TextProviderResolver` atomar (mit den aktuellen Llamafile-/
Local-HTTP-Views aus `live_llamafile` / `live_local_http`) und
antwortet mit einem frischen `status`-Envelope. `text_provider_chain`
spiegelt sofort die neue Reihenfolge, `llamafile_in_chain` /
`local_http_in_chain` werden entsprechend aktualisiert.

#### 2.10d Cloud-HTTP-Schreib-/Probe-Pfad + Secret-Pfad (PR 10 + PR 11 + PR 12)

PR 10 führt den **ersten Cloud-/Remote-Text-Provider** `cloud_http`
ein — mit einem **dedizierten Secret-Pfad**. Sensitive Werte (API-
Keys) wandern durch eine andere IPC-Message als operationale Werte
(Endpoint/Modell/Timeout) und werden in einer **separaten Datei**
(`secrets.json`, 0600) unter
[`crate::secrets_store`](../core/src/secrets_store.rs) persistiert.

**Operational:** `settings_set_cloud_http_config`.

```json
{"type":"settings_set_cloud_http_config","enabled":true,"endpoint":"http://cloud-gateway.local:8443/v1/chat","model":"gpt-4o-mini","request_timeout_seconds":60}
```

- `enabled` (bool, Pflicht) — Master-Schalter. Cloud ist
  opt-in; ohne `true` bleibt der Provider inert, selbst wenn er
  in der Chain steht und ein Key gespeichert ist.
- `endpoint` (string|null, optional) — `http://host:port/path`
  **oder** `https://host:port/path`. Seit PR 11 akzeptiert der
  Parser beide Schemes; `https://` geht durch `tokio-rustls` mit
  dem in `webpki-roots` eingebetteten Mozilla-Trust-Store. Andere
  Schemes (z. B. `ftp://`) werden hart abgelehnt (Error-Klasse
  `endpoint_scheme_unsupported`). Ein leerer String / nur
  Whitespace löscht den Wert.
- `model` (string|null, optional) — optionaler Modellname, wird
  als `model`-Feld in den Request-Body aufgenommen.
- `request_timeout_seconds` (u64|null, optional) — `0` wird
  abgelehnt.

Erfolg → frischer `status`-Envelope. **Endpoint und Modell tauchen
nicht in `StatusPayload` auf** — nur die Bool-Flags
`cloud_http_in_chain` / `cloud_http_enabled` / `cloud_http_configured`.

**Secret:** `settings_set_cloud_http_secret`.

```json
{"type":"settings_set_cloud_http_secret","api_key":"sk-…"}
```

- `api_key` (string|null, Pflicht — `null` oder leerer String
  löscht den Key).

Der Core persistiert den Wert in `secrets.json` (eigene Datei,
0600, atomarer Write); bestehende Datei-Inhalte bleiben unverändert
außer dem cloud_http-Key. Die Antwort ist ein `status`-Envelope
mit genau einem neuen Feld:
`cloud_http_secret_present: bool`. **Der Key-Wert selbst taucht
in der Antwort niemals auf, auch nicht in einer gekürzten oder
gehashten Form.**

**Probe:** `settings_probe_cloud_http`. **Seit PR 12** ist der
Probe-Pfad ein **authentifizierter Application-Layer-Roundtrip**:
der Core sendet einen `HEAD`-Request mit
`Authorization: Bearer <key>` (Key aus dem Secrets-Store, Header-
Name aus `SMOLIT_CLOUD_HTTP_AUTH_HEADER`). Für `http://`-
Endpoints läuft der Request direkt über TCP; für `https://`
zusätzlich durch den TLS-Handshake gegen den
`default_cloud_http_tls_config` (webpki-roots). **Kein**
Completion-Request, **kein** Prompt, **kein** Nutzer-Inhalt
auf der Leitung. Der Bearer-Wert verlässt den Core ausschließlich
in genau diesem HEAD-Request und wird **niemals** in Logs,
Response-Bodies, Fehlermeldungen oder StatusPayload gespiegelt.

Kuratierte Klassen (PR 10 + PR 11 + PR 12):

- `"not_in_chain"` / `"disabled"` / `"not_configured"` —
  Config-Stufen.
- `"secret_missing"` — enabled, Endpoint gesetzt, aber kein Key
  im Secrets-Store.
- `"endpoint_scheme_unsupported"` — Scheme ist weder `http://`
  noch `https://` (z. B. `ftp://`).
- `"endpoint_unparseable"` — URL-Parser-Fehler.
- `"http_connect_failed"` / `"timeout"` — TCP-Schicht.
- `"tls_handshake_failed"` (PR 11) — TLS-Handshake scheiterte
  aus einem Grund, der nicht als Zertifikatsproblem klassifiziert
  werden kann (z. B. Protokoll-Mismatch; Peer spricht kein TLS).
- `"cert_untrusted"` (PR 11) — Peer-Cert wurde zurückgewiesen,
  weil der Issuer nicht im Trust-Store steht
  (`UnknownIssuer`-Familie).
- `"cert_invalid"` (PR 11) — Peer-Cert liegt außerhalb seiner
  Gültigkeit (expired / not-yet-valid), hat eine ungültige
  Signatur, einen nicht passenden Hostnamen oder wurde aus einem
  anderen `InvalidCertificate(…)`-Grund abgelehnt.
- `"unauthorized"` (seit PR 12 auch von der Probe erreichbar) —
  HEAD-Response war `401 Unauthorized` oder `403 Forbidden`. Der
  Server ist erreichbar (TLS/TCP ok), hat aber den gespeicherten
  Key explizit abgelehnt.
- `"http_error"` (seit PR 12 auch von der Probe erreichbar) —
  HEAD-Response hatte einen Status außerhalb von `200..300`
  **und** außerhalb von `{401, 403}`. Die Meldung enthält den
  numerischen Status-Code (kein Secret), z. B. „cloud_http
  endpoint returned HTTP status 500".
- `"ok"` — HEAD-Response hatte einen Status im Bereich `200..300`:
  Server erreichbar, TLS (für https://) vertraut, Key akzeptiert.
  Es wurde **kein** Completion-Roundtrip gemacht und **kein**
  Prompt gesendet.

Antwort: `settings_probe_result` mit `axis="cloud_http"`.
`message` und `class` sind kuratiert; **weder Endpoint noch Key
tauchen im Response auf — auch nicht im Fehlerpfad.**

**Entfallen seit PR 12:** die PR-11-only-Klasse `"ok_http"`
(nur-TCP-Connect für `http://`). Der Probe läuft jetzt für beide
Transporte über denselben authentifizierten HEAD — ein Erfolg
heißt immer `"ok"`, unabhängig vom Scheme.

**Eingang:** `settings_reset_text_provider_chain`.

```json
{"type":"settings_reset_text_provider_chain"}
```

Setzt die Kette auf den Compile-Zeit-Default `["abrain"]` zurück
und löscht das persistierte `text_chain.json`. Geht durch denselben
Update-Pfad wie `settings_set_text_provider_chain`, damit der
Validator-Run und der Resolver-Rebuild einheitlich behandelt
werden. Antwort: `status`.

#### 2.10e STT-/TTS-Chain-Editor (PR 13)

Spiegel zum Text-Chain-Editor aus §2.10c, angewendet auf die
Audio-Achsen. Scope bewusst klein: heute gibt es pro Achse nur
das Kind `command`; die Persistenz-/Validator-/IPC-Geometrie ist
aber vollständig vorbereitet, damit weitere Kinds ohne UI-
Refactor dazukommen können.

```json
{"type":"settings_set_stt_provider_chain","chain":["command"]}
{"type":"settings_reset_stt_provider_chain"}
{"type":"settings_set_tts_provider_chain","chain":["command"]}
{"type":"settings_reset_tts_provider_chain"}
```

Validierungsregeln (siehe
[`crate::providers::stt::validate_stt_chain`](../core/src/providers/stt.rs)
und
[`crate::providers::tts::validate_tts_chain`](../core/src/providers/tts.rs))
sind identisch zur Text-Achse:

1. Leere Kette → Fehler `stt/tts provider chain is empty (use reset
   to restore default)`.
2. Unbekannter Kind → Fehler mit dem abgelehnten Rohwert + der
   aktuellen Whitelist (heute `command`).
3. Duplikat → Fehler mit dem ablehnten Namen.
4. Trim + Lowercase als erste Normalisierung.

Erfolg → Persistenz in `stt_chain.json` / `tts_chain.json` (gleiche
Verzeichnisauflösung und 0600-Permissions wie die anderen
Override-Files); Resolver atomar rebuildet; frischer
`status`-Envelope mit `stt_provider_chain` / `tts_provider_chain`
als aktualisierter Reihenfolge.

**Keine Audio-Secrets über diese Nachrichten.** Die Audio-
Provider haben heute keinen Secret-Pfad — kommt einer,
entsteht analog zum Cloud-HTTP-Secret-Pfad eine eigene
`settings_set_*_secret`-Message.

**Sicherheitsgrenzen dieser Fläche.**

- **Keine Secrets über diese Nachrichten.** API-Keys, Tokens usw.
  werden ausdrücklich nicht über `settings_set_*` transportiert —
  sie sind für einen späteren, dedizierten Secrets-Pfad reserviert.
- **Kein Pfad-/Command-/Endpoint-Leak.** Binary-Pfad, Command-
  String und Endpoint-URL tauchen weder in Logs noch im
  `settings_probe_result` noch im `error`-Envelope auf.
- **Kein Mikrofon-/Audio-Zugriff in der STT-/TTS-Probe.** Die
  `local_http`-Probe löst ebenfalls **keinen** Completion-Request
  aus.
- **Atomarer Schreibpfad.** Der Settings-Store schreibt temp + rename.
- **Keine neue Eventfamilie.** `settings_probe_result` ist ein
  zusätzlicher `type`-Wert im bestehenden `OutgoingMessage`-Enum,
  nicht ein paralleler Kanal.

### 2.11 TTS-Lebenszyklus (PR 14)

Der Core meldet einen kleinen, ehrlichen TTS-Lebenszyklus: genau dann,
wenn ein TTS-Provider tatsächlich anläuft, kommen zwei additive
Envelopes auf die Leitung. Ist die Kette nicht einsatzbereit, wird
**gar nichts** emittiert — die UI darf also aus „speaking_started"
immer ableiten: „jetzt läuft wirklich TTS".

```json
{"type":"speaking_started","payload":{"source":"speak_text","provider":"command","action_id":"act_000012"}}
{"type":"speaking_ended","payload":{"source":"speak_text","provider":"command","ok":true,"action_id":"act_000012"}}

{"type":"speaking_started","payload":{"source":"auto_speak","provider":"command"}}
{"type":"speaking_ended","payload":{"source":"auto_speak","provider":"command","ok":false,"error_class":"exit_nonzero"}}
```

Payload-Felder (identisch in `started` / `ended`, `ended` ergänzt
`ok` / `error_class`):

- `source` (string, Pflicht) — `"speak_text"` (IPC-Nachricht
  `speak_text`) oder `"auto_speak"` (stille Wiedergabe einer
  `response`, wenn `auto_speak=true` ist). Die UI darf darauf
  unterschiedlich reagieren, muss aber nicht.
- `provider` (string, Pflicht) — Kind-Name des tatsächlich
  angesprochenen TTS-Providers. In `speaking_started` ist das der
  primäre Kind-Name aus der TTS-Kette; in `speaking_ended` der
  tatsächlich aktive Kind-Name (bei Fallback zeigt das den
  sprechenden Provider). Heute nur `"command"`. **Kein** Binary-Pfad,
  **kein** Command-String — nur der kuratierte Kind-Name aus
  [`crate::providers::tts::KNOWN_TTS_KINDS`](../core/src/providers/tts.rs).
- `action_id` (string, optional) — gesetzt, wenn der Lifecycle aus
  einem Action-Event-Flow stammt (`speak_text` → Action-Kind
  `speech`). Beim `auto_speak`-Pfad bleibt das Feld weg, weil der
  Event dort **nach** der `action_completed`-Klammer der
  auslösenden Query kommt und nicht zu ihr gehört.
- `ok` (bool, `speaking_ended` Pflicht) — `true` bei erfolgreichem
  Sprechen (auch über Fallback), `false` bei Fehler.
- `error_class` (string, optional, nur bei `ok=false`) — kuratierte
  Klasse aus demselben Vokabular wie `SettingsProbeResult` (siehe
  §2.10): `empty_chain` / `timeout` / `process_missing` /
  `stdin_write_failed` / `exit_nonzero` / `not_configured` /
  `disabled` / `unknown`.

Ordnungs- und Pairing-Regeln:

- **Pairing.** Zu jedem `speaking_started` kommt genau ein
  `speaking_ended`. Der Core emittiert nie zwei aufeinander folgende
  `speaking_started` ohne dazwischen liegendes `speaking_ended`.
- **`speak_text`-Flow.** Die Events sind Teil der Action-Klammer:
  `action_planned` / `action_started` / `action_step` →
  `speaking_started` → `speaking_ended` → `action_completed`
  (oder `action_failed` bei `ok=false`). Alle Frames fließen auf
  derselben Wire-Reihenfolge zurück, die der Handler aufgebaut hat.
- **`auto_speak`-Flow.** Die Events erscheinen **nach** der
  vollständigen Action-Klammer der auslösenden Query:
  `response` → `action_completed` → `speaking_started` →
  `speaking_ended`. Sie gehören nicht zur Query-Action — deshalb auch
  kein `action_id`.
- **Kein Event, wenn kein TTS läuft.** Ist die Kette leer /
  `enabled=false` / `command` fehlt, bleibt der Pfad still. Der
  bestehende `error`-Envelope („TTS is not available") für
  `speak_text` bleibt unverändert; `auto_speak` schweigt wie bisher.
- **Abbruch-/Fehlerfall.** Scheitert die Kette (z. B.
  `exit_nonzero`), kommt trotzdem genau ein `speaking_ended` mit
  `ok=false` — ein „hängender" TTS-Zustand auf der UI-Seite ist
  strukturell ausgeschlossen.

Bewusste Nicht-Ziele:

- **Kein Audio-Streaming.** Die Events sagen „Smolit spricht jetzt"
  bzw. „Smolit ist fertig" — nicht „wo genau in der Phrase wir sind".
- **Kein Phonem-/Lip-Sync-Kanal.** Diese Ebene ist weiterhin dem
  Avatar-Asset-Pfad vorbehalten (nicht Teil von PR 14).
- **Kein Text im Event.** Der gesprochene Text wird nicht dupliziert
  — er kam bereits als `response` oder als Argument zu `speak_text`
  und bleibt dort die Wahrheit.
- **Keine Audio-Bytes, keine Timeline.** Die UI renderiert „talking"
  als State-Wechsel, nicht als Synchronisation gegen einen Audio-
  Puffer.

Für die UI-Projektion (Avatar, Utterance-Bubble) siehe
[`ui_architecture.md` §8.4a](./ui_architecture.md).

---

## 3. Core ↔ ABrain: CLI-Adapter (Ist-Zustand)

Heute spricht der Core ABrain über einen **externen Prozess** an.

- Kommando konfigurierbar über `ABRAIN_CMD` (Default: `abrain`).
- Aufruf: `${ABRAIN_CMD} task run "<input>"`.
- Eingabe: reiner Text auf der Kommandozeile.
- Ausgabe: Antworttext auf `stdout`, Fehlermeldungen auf `stderr`.
- Fehler: Nicht-Null-Exit-Code oder Timeout → der Core gibt dem CLI-Loop
  bzw. der UI ein `error`-Event zurück.

Diese Schnittstelle ist bewusst schmal. Sie abstrahiert ABrain von der
konkreten Einbettung und erlaubt später einen Austausch (siehe 5.).

Seit PR 2 der Provider-Fallback-Linie
([`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md))
wird der ABrain-CLI-Aufruf **nicht mehr direkt** aus dem IPC-Handler
gesprochen, sondern über die interne Text-Provider-Schicht
(`core/src/providers/text.rs`). ABrain-CLI ist dort der Provider-Kind
`abrain` — die äußere Kommandoform bleibt 1:1 erhalten. Zusätzlich
kann die Reihenfolge über die Konfiguration festgelegt werden:

- Env: `SMOLIT_TEXT_PROVIDER_CHAIN` — komma-separierte Liste von
  Kind-Namen. Unbekannte Namen werden sichtbar verworfen; leere Kette
  → Default `["abrain"]`.
- Heute produktiv implementierte Kinds: **`abrain`** (CLI-Adapter,
  siehe oben).
- Produktiv implementiert (Ist, PR 2b): **`llamafile_local`**.
  Lokaler Fallback-Provider; der Core startet das konfigurierte
  llamafile-Binary on-demand beim ersten Request
  (`--server --host 127.0.0.1 --port <port> --nobrowser`), pollt
  `GET /health` bis 200 OK, dispatchet Completion via `POST /completion`
  (`{"prompt": ..., "n_predict": 256, "stream": false}`) und beendet
  den Prozess nach `idle_timeout_seconds` ohne Aktivität.
  Konfigurierbar über `SMOLIT_LLAMAFILE_ENABLED` /
  `SMOLIT_LLAMAFILE_PATH` / `SMOLIT_LLAMAFILE_MODE` (Whitelist
  `on_demand` / `standby` — `standby` ist reserviert und verhält sich
  heute wie `on_demand`) / `SMOLIT_LLAMAFILE_IDLE_TIMEOUT_SECONDS` /
  `SMOLIT_LLAMAFILE_PORT` (Default 8788, Loopback-only, Well-Known-
  Ports unzulässig) / `SMOLIT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS` /
  `SMOLIT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS`. Fehlerklassen landen
  additiv in `text_provider_last_error` (`process_missing`,
  `process_exit_early`, `startup_timeout`, `timeout`,
  `http_connect_failed`, `http_error`, `empty_response`,
  `invalid_response`). Details:
  [`docs/provider_fallback_and_settings_architecture.md` §4.1a](./provider_fallback_and_settings_architecture.md).
- Produktiv implementiert (Ist, PR 8): **`local_http`**. Allgemeiner
  lokaler HTTP-Text-Provider. Postet an einen konfigurierten
  Endpoint ein JSON-Objekt `{"<prompt_field>": "<input>", "stream": false}`
  und liest das `<response_field>` aus der JSON-Antwort. Kein
  Streaming, keine Tool-/Schema-Modes, kein TLS (`https://` wird
  abgelehnt), kein Auth-Header. Nutzt denselben
  `http_request`-Helfer wie der llamafile-Runtime; keine neue
  Dependency. Konfigurierbar über `SMOLIT_LOCAL_HTTP_ENABLED` /
  `SMOLIT_LOCAL_HTTP_ENDPOINT` (z. B.
  `http://127.0.0.1:8080/completion`) /
  `SMOLIT_LOCAL_HTTP_REQUEST_TIMEOUT_SECONDS` /
  `SMOLIT_LOCAL_HTTP_PROMPT_FIELD` (Default `prompt`) /
  `SMOLIT_LOCAL_HTTP_RESPONSE_FIELD` (Default `content`). Fehlerklassen
  additiv in `text_provider_last_error`: `disabled`, `not_configured`,
  `endpoint_scheme_unsupported`, `endpoint_unparseable`,
  `http_connect_failed`, `http_error`, `timeout`, `empty_response`,
  `invalid_response`.
- Weitere Kinds (Cloud) folgen in späteren PRs und sind **heute
  nicht implementiert**.

---

## 4. Core ↔ STT/TTS: Externe Commands (Ist-Zustand)

Der Core nimmt **kein Audio selbst** auf oder aus. Er ruft konfigurierte
Kommandos auf:

- `SMOLIT_STT_CMD`: Command, das einmal aufnimmt und den erkannten Text
  auf `stdout` ausgibt. Leerer Output → Fehler. Wird vom `command`-Kind
  konsumiert.
- `SMOLIT_STT_WHISPER_CPP_CMD` (PR 27): gleicher Spawn-Kontrakt wie
  `SMOLIT_STT_CMD`, aber vom `whisper_cpp`-Kind konsumiert. Env-only;
  kein Runtime-Editor in der Settings-Shell. Wird ignoriert, solange
  `whisper_cpp` nicht Teil der `stt_provider_chain` ist.
- `SMOLIT_TTS_CMD`: Command, das den zu sprechenden Text auf `stdin`
  bekommt und selbst die Ausgabe macht. Wird vom `command`-Kind
  konsumiert.
- `SMOLIT_TTS_PIPER_CMD` (PR 34): gleicher stdin-Spawn-Kontrakt wie
  `SMOLIT_TTS_CMD`, aber vom `piper`-Kind konsumiert. Env-only;
  kein Runtime-Editor in der Settings-Shell. Wird ignoriert,
  solange `piper` nicht Teil der `tts_provider_chain` ist.
- Timeouts konfigurierbar über `SMOLIT_STT_TIMEOUT_SECONDS` bzw.
  `SMOLIT_TTS_TIMEOUT_SECONDS` (Default 20 s).
- Ist das Feature an (`*_ENABLED=true`), aber kein Command gesetzt,
  bleibt `available=false`. Der Core loggt eine Warnung, läuft aber
  weiter.

Damit sind Kokoro, Piper, Whisper.cpp, Vosk oder beliebige eigene Skripte
einbindbar, ohne den Core zu verändern.

Seit PR 6 läuft dieser Command-Pfad hinter einer kleinen Provider-
Abstraktion
([`crate::providers::stt`](../core/src/providers/stt.rs) /
[`crate::providers::tts`](../core/src/providers/tts.rs)), strukturell
analog zum Text-Resolver. Die Chain ist env-überschreibbar über
`SMOLIT_STT_PROVIDER_CHAIN` / `SMOLIT_TTS_PROVIDER_CHAIN` und beginnt
per Default mit `command`. Seit PR 27 hat die STT-Whitelist ein
zweites Kind (`whisper_cpp`) — der Default bleibt aber
`["command"]`; `whisper_cpp` landet nur dann in der Kette, wenn der
Nutzer es explizit setzt.
`App::handle_voice_once` und `App::handle_speak` gehen ausschließlich
durch den Resolver — kein direkter Service-Call mehr. Bestehendes
Verhalten (Timeouts, Fehlermeldungen, `available`-Semantik) bleibt
byte-kompatibel; die Resolver-Sicht wird zusätzlich über die neuen
`stt_provider_*` / `tts_provider_*`-Felder im StatusPayload (§2.3)
projiziert.

---

> **OceanData ist kein Teil des IPC-Protokolls.** Weder heute (kein
> Provider-Kind, keine IPC-Commands, keine `StatusPayload`-Felder)
> noch in der skizzierten Zukunft. Der Proposed-Rahmen für eine
> spätere Data-/Kontext-Anbindung lebt in
> [`docs/adr/ADR-0004-oceandata-data-layer-integration.md`](./adr/ADR-0004-oceandata-data-layer-integration.md);
> der ADR beschreibt ausdrücklich **keine** Wire-Form am heutigen
> IPC-Kanal.

## 5. Core ↔ ABrain: natives API (Ziel-Zustand)

Geplant, **noch nicht implementiert**. Sobald ABrain als Bibliothek oder
als IPC-Server verfügbar ist, ergänzt die native Schnittstelle den
CLI-Prozess — sie **ersetzt** ihn nicht.

> **PR 39 (2026-04-24, Proposed) — Rahmen entschieden:**
> [`ADR-0003`](./adr/ADR-0003-abrain-native-integration.md) legt den
> Rahmen eines zukünftigen Native-Pfades fest, bevor Code entsteht.
> Kernaussagen: `ABRAIN_CMD` und der heutige CLI-Adapter bleiben
> unverändert; der Native-Pfad kommt als **zusätzlicher** Text-
> Provider-Kind (Arbeitsname `abrain_native`, Default-Chain bleibt
> `["abrain"]`, Opt-in per Env + Chain-Eintrag); typed
> request/response; lokal-first (Unix-Socket / Loopback, kein
> Cloud-Default); jede ABrain-induzierte Action läuft durch den
> bestehenden Approval-/Policy-/Audit-Pfad; kein AdminBot-/Shell-/
> Desktop-Bypass; kein Streaming und keine Tool-Call-Execution in
> der ersten Version. Der ADR ist **Docs-only** — es existiert kein
> Native-Client, kein `abrain_native`-Code, kein neues IPC-Event.
> Heute bleibt der CLI-Adapter aus §3 die einzige produktive Quelle
> von ABrain-Antworten.

Ziele der späteren Native-Schnittstelle (Ziel-Zustand, siehe
ADR-0003 für die verbindliche Messlatte):

- strukturierte Requests (Kontext, Modalitäten, Session-IDs),
- strukturierte Responses (Text + optional Action-Intents / Task-ID;
  Emotion-/Voice-/Tool-Call-Felder bleiben Future Work),
- Streaming,
- geringere Latenz als Prozess-Spawn.

### 5.1 Request (Ziel)

```json
{
  "type": "task",
  "input": "string",
  "context": {
    "user_id":    "string",
    "session_id": "string",
    "history":    []
  },
  "modalities": ["text", "audio"]
}
```

### 5.2 Response (Ziel)

```json
{
  "status": "ok",
  "response": {
    "text":    "string",
    "emotion": "neutral | thinking | happy | alert",
    "actions": [],
    "voice": {
      "tone":  "calm",
      "speed": 1.0
    }
  }
}
```

### 5.3 Streaming (Ziel)

```json
{"type":"stream","chunk":"partial text"}
```

### 5.4 Tool Calls (Ziel)

```json
{"type":"tool_call","tool":"adminbot","payload":{}}
```

Bis dieses API existiert, bleibt der CLI-Adapter aus Abschnitt 3 die
einzige reale Quelle von ABrain-Antworten. Das WebSocket-Protokoll aus
Abschnitt 2 muss für eine native ABrain-Schicht **nicht** geändert werden,
solange der Response-Text weiterhin in `response.payload.text` landet.

---

## 6. Fehlermodell

### 6.1 IPC-Layer

- Verbindungsabbruch: UI sieht Socket-Close, Core schließt sauber.
- Ungültige JSON-Frames: `error`-Antwort, Verbindung bleibt offen.
- Unbekannter `type`: `error`-Antwort, Verbindung bleibt offen.

### 6.2 Adapter-Layer

- Fehlende STT/TTS-Commands: `error`-Antwort mit beschreibender Message.
- ABrain-Timeout oder Non-Zero-Exit: `error`-Antwort mit stderr-Kontext
  im Log (nicht notwendigerweise in der UI-Nachricht).

### 6.3 Core-Invariante

Ein einzelner UI-Client oder Adapter darf den Core nie in einen
dauerhaft fehlerhaften Zustand bringen. Der CLI-Loop bleibt kanonisch
und läuft unabhängig vom IPC-Server weiter.

---

## 7. Kompatibilitätsprinzipien

- **Additiv statt mutierend.** Neue Nachrichtentypen werden hinzugefügt;
  bestehende ändern ihre Felder nicht.
- **Optionale Felder statt Breaking Changes.** Neue Felder in Payloads
  sind optional und dürfen von älteren UIs ignoriert werden.
- **Ein Protokollstand pro Commit.** `docs/api.md` und
  `core/src/ipc/protocol.rs` werden gemeinsam geändert.
- **Lokales Binding.** IPC ist nur für `127.0.0.1` vorgesehen; kein
  Remote-Access, keine Auth-Schicht erforderlich — andernfalls wäre eine
  separate Protokoll-Entscheidung nötig.

---

## 8. Zukunftsfelder (Ziel-Zustand)

Die folgenden Erweiterungen sind vorgesehen, aber **noch nicht
implementiert**; sie kommen additiv über neue `type`-Werte oder
optionale Felder:

- `response.payload.emotion` — optionales Feld, sobald ABrain Emotion
  liefert. *Hinweis:* Der UI-seitige **Behavioral Expression Layer v1**
  (PR 15, siehe [`ui_architecture.md` §8.4b](./ui_architecture.md))
  bringt sechs kuratierte Ausdrucksmodi (`neutral` / `focused` /
  `curious` / `speaking` / `pleased` / `error_soft`) als visuelle
  Patches oberhalb der bestehenden Avatar-States — **ohne** neues
  IPC-Feld. Der Core sendet weiterhin keine Expressions und nimmt
  keine entgegen; das Protokoll bleibt unverändert.
  Ebenso bringt das **Workflow Visibility Overlay v1** (PR 16,
  siehe [`ui_architecture.md` §8.4c](./ui_architecture.md)) eine
  lineare UI-Projektion bestehender Events (`heard` → `thinking` →
  `response` → `action_*` → `speaking_*` → `completed` / `failed`)
  **ohne** neue IPC-Envelopes. Es ist ein reiner Renderer über den
  bereits existierenden Ausgangskanälen — `workflow_snapshot` oder
  ähnliches ist ausdrücklich **nicht** Teil des Protokolls.
- `tool_call` / `tool_result` — wenn Tool-Orchestrierung einzieht.
- `session_reset` — explizites Beenden/Zurücksetzen einer Session.
- Vision-/Sensor-Modalitäten — erst nach Klärung von Datenschutz und
  Transportformat.

---

## 9. Nicht-Ziele

- Kein Remote-Protokoll. Smolit-IPC ist explizit lokal.
- Keine UI-seitige Geschäftslogik über das Protokoll. UIs dürfen keine
  Entscheidungen treffen, die im Core gehören (z. B. „gehe in Voice-Mode,
  wenn X").
- Keine Parallel-Protokolle. Kein zweiter IPC-Stack neben
  `core/src/ipc/`; neue Transporte müssten als Adapter hinter derselben
  Handler-Schicht (`core/src/app.rs`) aufgehängt werden.

---

## 10. Referenz-Quellen im Repo

- `core/src/ipc/protocol.rs` — Enum-Definitionen für Ein-/Ausgang
  inkl. Action Event Varianten.
- `core/src/ipc/server.rs` — WebSocket-Accept-Loop und Dispatch;
  emittiert Action Events für `submit_text`, `voice_once`, `speak_text`.
- `core/src/actions/` — Datenmodell für Action Events, Targets und
  symbolisches Visual Mapping (v1).
- `core/src/interaction/` — Desktop Interaction Layer MVP:
  `InteractionAction`, `InteractionBackend` / `CommandBackend`,
  `InteractionExecutor`, Verification- und Recovery-Hints.
- `core/src/app.rs` — geteilte Handler (CLI und IPC nutzen denselben Code),
  Action-ID-Generator (`next_action_id`), `handle_interaction_action` /
  `execute_open_application`.
- `core/src/audio/` — STT/TTS-Command-Adapter.
- `core/src/config.rs` — Env-Konfiguration (`SMOLIT_*`).
- `ui/autoload/ipc_client.gd` — Godot-seitige Referenzimplementierung
  des Protokolls.
- [`docs/GLOSSARY.md`](./GLOSSARY.md) — einheitliches Vokabular
  (Approval, Audit Trail, Workflow-Overlay, Workflow Visibility
  Overlay, Presence, Expression, Action Event, Interaction Layer,
  Provider Chain, Stage C). Wenn diese Datei einen Begriff anders
  nutzt, gewinnt das Glossar.
