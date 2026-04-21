# Smolit Assistant

Smolit Assistant ist als leichtgewichtiger, always-on Hintergrunddienst aufgebaut. Der Fokus dieses Bootstraps liegt auf einem sauberen Rust-Core, einer klar getrennten Adapter-Schicht und einer minimalen CLI, die Eingaben an ABrain weiterreicht.

## Struktur

```text
smolit-assistant/
├── core/                  # Rust daemon
├── ui/                    # Platzhalter für spätere Godot-UI
├── adapters/
│   ├── abrain/
│   └── adminbot/
├── config/
├── docs/
├── scripts/
├── .env.example
├── README.md
└── ROADMAP.md
```

## Setup

ABrain muss lokal verfügbar sein. Standardmäßig wird der Befehl `abrain` verwendet.

Optionale Konfiguration über `.env` im Repo-Root:

```env
ABRAIN_CMD=abrain
LOG_LEVEL=info

SMOLIT_TTS_ENABLED=true
SMOLIT_TTS_CMD=
SMOLIT_STT_ENABLED=true
SMOLIT_STT_CMD=
SMOLIT_AUDIO_AUTO_SPEAK=true
SMOLIT_STT_TIMEOUT_SECONDS=20
SMOLIT_TTS_TIMEOUT_SECONDS=20

SMOLIT_IPC_ENABLED=true
SMOLIT_IPC_BIND=127.0.0.1:8787
```

## Run

```bash
cd core
cargo run
```

Nach dem Start:

```text
Smolit ready.
> hello
[ABrain Antwort]
> exit
```

## Voice System

Das Voice-System ist additiv: Der bestehende Text-Loop bleibt kanonisch,
Spracheingabe und -ausgabe werden über externe Commands eingebunden. Der Rust-Core
nimmt keine Audiodaten selbst auf — die konfigurierten Commands kümmern sich
um Aufnahme, Erkennung und Sprachausgabe.

### Konfigurationsvariablen

- `SMOLIT_TTS_ENABLED` / `SMOLIT_STT_ENABLED` — Feature an/aus.
- `SMOLIT_TTS_CMD` — externes TTS-Kommando; bekommt den zu sprechenden Text auf stdin.
- `SMOLIT_STT_CMD` — externes STT-Kommando; liefert erkannten Text auf stdout.
- `SMOLIT_AUDIO_AUTO_SPEAK` — wenn `true`, wird jede ABrain-Antwort zusätzlich gesprochen.
- `SMOLIT_TTS_TIMEOUT_SECONDS` / `SMOLIT_STT_TIMEOUT_SECONDS` — Timeouts in Sekunden.

Ist ein Feature aktiviert, aber kein Command gesetzt, läuft der Core ohne Crash
weiter und meldet das Feature als nicht verfügbar.

### CLI-Befehle

```text
help              Hilfe anzeigen
exit | quit       Beenden
voice             einmal STT aufnehmen und Ergebnis an ABrain schicken
speak <text>      Text direkt über TTS sprechen
audio-status      TTS-/STT-Status anzeigen
```

### Beispiel-Workflow

```text
Smolit ready.
> audio-status
TTS: enabled=true, available=false
STT: enabled=true, available=false
auto-speak: true
> voice
STT is not available. Check SMOLIT_STT_ENABLED and SMOLIT_STT_CMD.
```

Die STT/TTS-Kommandos werden bewusst nicht vorgegeben — Kokoro, Piper,
Whisper.cpp, Vosk oder ein eigenes Python-Skript können gleichermaßen
angebunden werden.

## IPC / WebSocket Bridge

Der Core öffnet optional einen lokalen WebSocket-Server, über den eine
spätere Godot-UI den Assistenten ansprechen kann. Der Server ist additiv:
Der CLI-Loop bleibt kanonisch, IPC nutzt dieselben Kern-Handler wie das CLI.

- `SMOLIT_IPC_ENABLED` — an/aus (Default `true`).
- `SMOLIT_IPC_BIND` — lokale Bind-Adresse (Default `127.0.0.1:8787`).

Nur Localhost-Binds sind als Ziel vorgesehen — keine externe Erreichbarkeit.

### Nachrichtenformat

Text-Frames mit JSON. Eingehend (UI → Core):

```json
{"type":"ping"}
{"type":"get_status"}
{"type":"submit_text","text":"Hallo Smolit"}
{"type":"speak_text","text":"Dies ist ein Test"}
{"type":"voice_once"}
```

Ausgehend (Core → UI):

```json
{"type":"pong"}
{"type":"status","payload":{"tts_enabled":true,"tts_available":false,"stt_enabled":true,"stt_available":false,"auto_speak":true,"ipc_enabled":true}}
{"type":"thinking"}
{"type":"response","payload":{"text":"..."}}
{"type":"heard","payload":{"text":"..."}}
{"type":"error","message":"..."}
```

Ungültige JSON-Payloads führen zu einer `error`-Antwort, nicht zu einem Crash.

## UI (Godot, Phase 3.1 Bootstrap)

Unter [ui/](ui/) liegt ein Godot-4-Projekt, das die Core-Bridge als lokaler
Client konsumiert. Zweck in dieser Phase: nachweisen, dass ein separater
UI-Prozess den Round-Trip sauber abwickelt — ohne Avatar, ohne
Always-on-top, ohne Business-Logik.

### Starten

1. Godot 4.2+ öffnen, Projektordner `ui/` wählen, Projekt importieren.
2. Den Rust-Core mit aktivem IPC laufen lassen
   (`SMOLIT_IPC_ENABLED=true`, Default-Bind `127.0.0.1:8787`).
3. Godot-Szene ausführen. Es erscheint ein einfaches Fenster mit:

   - Statuszeile (`connected` / `disconnected`)
   - Event-Log (RichTextLabel, farbcodiert)
   - Eingabezeile + „Send" / „Ping"-Buttons

### Aufbau

```text
ui/
├── project.godot
├── config.cfg         # UI-Config (websocket_url, reconnect backoff)
├── autoload/
│   ├── event_bus.gd   # Signal-Hub (keine Logik)
│   └── ipc_client.gd  # WebSocketPeer-Wrapper mit Reconnect
├── scenes/
│   └── main.tscn
├── scripts/
│   └── main.gd        # Scene-Controller
└── assets/
```

Scenes hängen ausschließlich an `EventBus` — der Transport (`IpcClient`)
kann später ersetzt werden, ohne Scene-Code anzufassen.

### Verbindungsverhalten

- Default-URL: `ws://127.0.0.1:8787` (überschreibbar in `ui/config.cfg`).
- Reconnect-Backoff 500 ms → 5 s, verdoppelnd, gecapped.
- Nach jedem erfolgreichen Connect sendet die UI automatisch
  `get_status` als Handshake.
- Während „disconnected" bleibt die UI benutzbar, `Send`/`Ping` sind
  deaktiviert.

Scenes hängen ausschließlich an `EventBus` — der Transport (`IpcClient`)
kann später ersetzt werden, ohne Scene-Code anzufassen.

### Verbindungsverhalten

- Default-URL: `ws://127.0.0.1:8787` (überschreibbar in `ui/config.cfg`).
- Reconnect-Backoff 500 ms → 5 s, verdoppelnd, gecapped.
- Nach jedem erfolgreichen Connect sendet die UI automatisch
  `get_status` als Handshake.
- Während „disconnected" bleibt die UI benutzbar, `Send`/`Ping` sind
  deaktiviert.
