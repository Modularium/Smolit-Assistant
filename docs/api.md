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

| `type`        | Felder         | Semantik                                                        |
|---------------|----------------|-----------------------------------------------------------------|
| `ping`        | —              | Health-Check. Core antwortet mit `pong`.                        |
| `get_status`  | —              | Fragt Feature-Status ab. Core antwortet mit `status`.           |
| `submit_text` | `text: string` | Freitext-Query an ABrain. Löst `thinking` + `response`/`error`. |
| `speak_text`  | `text: string` | Direkte TTS-Ausgabe ohne ABrain. Bei Fehler: `error`.           |
| `voice_once`  | —              | Einmal STT aufnehmen, Ergebnis als `heard`, dann ABrain-Flow.   |

Zusätzlich nimmt der Core Interaction-Nachrichten des Desktop
Interaction Layer MVP entgegen (Details in Abschnitt 2.6):

- `interaction_open_application` mit Feld `application: string`.
- `interaction_focus_window` mit Feld `target` (siehe 2.6).

Für den Approval / Confirmation Flow (Details in Abschnitt 2.7):

- `approval_response` mit `approval_id: string` und `decision`
  (`"approved" | "denied" | "cancelled"`).

Beispiele:

```json
{"type":"ping"}
{"type":"get_status"}
{"type":"submit_text","text":"Hallo Smolit"}
{"type":"speak_text","text":"Dies ist ein Test"}
{"type":"voice_once"}
{"type":"interaction_open_application","application":"calendar"}
{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}
```

### 2.2 Ausgehend (Core → UI)

| `type`      | Felder                       | Semantik                                                    |
|-------------|------------------------------|-------------------------------------------------------------|
| `pong`      | —                            | Antwort auf `ping`.                                         |
| `status`    | `payload: StatusPayload`     | Aktueller Feature-Status (siehe 2.3).                       |
| `thinking`  | —                            | ABrain-Anfrage läuft. Wird pro Query einmal emittiert.      |
| `response`  | `payload: { text: string }`  | ABrain-Antworttext.                                         |
| `heard`     | `payload: { text: string }`  | STT-Ergebnis (nur im `voice_once`-Flow).                    |
| `error`     | `message: string`            | Fehler bei Parsing, Ausführung oder Adapter.                |

Zusätzlich emittiert der Core **Action Events** (Action Event Model v1).
Sie sind additiv; ältere UIs, die sie nicht kennen, dürfen sie
ignorieren. Details in Abschnitt 2.5.

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
  "tts_enabled":              true,
  "tts_available":            false,
  "stt_enabled":              true,
  "stt_available":            false,
  "auto_speak":               true,
  "ipc_enabled":              true,
  "interaction_enabled":      true,
  "interaction_backend":      "command",
  "approval_timeout_seconds": 20
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
| `action_progress`     | Fortschrittsindikator (optional, derzeit nicht emittiert).   |
| `action_step`         | Einzelschritt innerhalb der Aktion.                          |
| `action_verification` | Verifikationsphase (Modell für spätere Automation).          |
| `action_completed`    | Aktion erfolgreich abgeschlossen.                            |
| `action_failed`       | Aktion fehlgeschlagen.                                       |
| `action_cancelled`    | Aktion abgebrochen (Modell für spätere Automation).          |

In v1 emittieren die bestehenden Flows aktiv: `action_planned`,
`action_started`, `action_step`, `action_completed`, `action_failed`.
`action_progress`, `action_verification` und `action_cancelled` sind
als Schema und Outgoing-Typ bereits vorgesehen, werden von v1-Handlern
aber (noch) nicht emittiert.

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
  `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION` aktiv ist — der
  Confirmation-Kanal selbst ist noch nicht implementiert, siehe
  Phase 8b).
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
  (siehe `docs/presence_desktop_interaction.md`, §7).

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

#### Ausgehend (Core → UI)

- `approval_requested` — Core bittet um Freigabe. `payload` ist eine
  `ApprovalRequest` mit den Feldern `approval_id`, `action_id`,
  `action_kind`, `title`, `message`, `target`, optional `reason`,
  `timeout_seconds`.
- `approval_resolved` — Endergebnis der Freigabe. `payload.decision`
  ist einer der Strings `approved`, `denied`, `cancelled`,
  `timed_out`. Wird vor dem endgültigen `action_completed` bzw.
  `action_cancelled` emittiert.

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

---

## 4. Core ↔ STT/TTS: Externe Commands (Ist-Zustand)

Der Core nimmt **kein Audio selbst** auf oder aus. Er ruft konfigurierte
Kommandos auf:

- `SMOLIT_STT_CMD`: Command, das einmal aufnimmt und den erkannten Text
  auf `stdout` ausgibt. Leerer Output → Fehler.
- `SMOLIT_TTS_CMD`: Command, das den zu sprechenden Text auf `stdin`
  bekommt und selbst die Ausgabe macht.
- Timeouts konfigurierbar über `SMOLIT_STT_TIMEOUT_SECONDS` bzw.
  `SMOLIT_TTS_TIMEOUT_SECONDS` (Default 20 s).
- Ist das Feature an (`*_ENABLED=true`), aber kein Command gesetzt,
  bleibt `available=false`. Der Core loggt eine Warnung, läuft aber
  weiter.

Damit sind Kokoro, Piper, Whisper.cpp, Vosk oder beliebige eigene Skripte
einbindbar, ohne den Core zu verändern.

---

## 5. Core ↔ ABrain: natives API (Ziel-Zustand)

Geplant, **noch nicht implementiert**. Sobald ABrain als Bibliothek oder
als IPC-Server verfügbar ist, ersetzt die native Schnittstelle den
CLI-Prozess. Ziele:

- strukturierte Requests (Kontext, Modalitäten, Session-IDs),
- strukturierte Responses (Text + optional Emotion/Actions/Tool Calls),
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

- `speaking_started` / `speaking_ended` — TTS-Lebenszyklus für
  Animations-Sync in der UI.
- `response.payload.emotion` — optionales Feld, sobald ABrain Emotion
  liefert.
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
