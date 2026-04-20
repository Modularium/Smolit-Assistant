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

Beispiele:

```json
{"type":"ping"}
{"type":"get_status"}
{"type":"submit_text","text":"Hallo Smolit"}
{"type":"speak_text","text":"Dies ist ein Test"}
{"type":"voice_once"}
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
  "tts_enabled":   true,
  "tts_available": false,
  "stt_enabled":   true,
  "stt_available": false,
  "auto_speak":    true,
  "ipc_enabled":   true
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

### 2.4 Flow-Beispiele

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

- `core/src/ipc/protocol.rs` — Enum-Definitionen für Ein-/Ausgang.
- `core/src/ipc/server.rs` — WebSocket-Accept-Loop und Dispatch.
- `core/src/app.rs` — geteilte Handler (CLI und IPC nutzen denselben Code).
- `core/src/audio/` — STT/TTS-Command-Adapter.
- `core/src/config.rs` — Env-Konfiguration (`SMOLIT_*`).
- `ui/autoload/ipc_client.gd` — Godot-seitige Referenzimplementierung
  des Protokolls.
