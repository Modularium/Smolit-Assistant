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

SMOLIT_INTERACTION_ENABLED=true
SMOLIT_INTERACTION_BACKEND=command
SMOLIT_INTERACTION_ALLOW_OPEN_APP=true
SMOLIT_INTERACTION_ALLOW_TYPE_TEXT=false
SMOLIT_INTERACTION_ALLOW_SHORTCUTS=false
SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=true
SMOLIT_INTERACTION_OPEN_APP_CMD=
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

Zusätzlich emittiert der Core **standardisierte Action Events**
(`action_planned`, `action_started`, `action_step`,
`action_completed`, `action_failed`) additiv zu den klassischen
Events — als Grundlage für spätere Avatar-/Präsenz-Reaktionen, Logs
und die Desktop-Interaction-Schicht. Details in
[docs/api.md](docs/api.md) §2.5.

## Desktop Interaction Layer (MVP)

Der Core enthält unter [core/src/interaction/](core/src/interaction/)
einen dünnen, explizit konservativen Desktop-Interaction-Layer. Er
modelliert Interaction-Aktionen (`InteractionAction`,
`InteractionKind`, `InteractionPayload`), exekutiert über ein
`InteractionBackend`-Trait und integriert sich ausschließlich über das
Action Event Model v1 (`action_planned` → `action_started` →
`action_step` → `action_verification` → `action_completed` /
`action_failed`). Fehler werden über `RecoveryHint`
(`retry` / `abort` / `ask_user` / `fallback_unavailable`) klassifiziert
und im `action_failed.error`-Feld als `recovery_hint=<x>` übertragen.

Im MVP sind `open_application` und — seit dem aktuellen Spike —
`focus_window` wirklich implementiert (`CommandBackend`,
konfigurierbare Kommando-Templates wie `gtk-launch {name}` /
`xdg-open {name}` für Open-App und z. B. `wmctrl -a {name}` für
Focus-Window). `type_text` und `send_shortcut` sind weiterhin nur als
Hooks vorhanden, liefern `BackendUnsupported`. Defaults sind bewusst
restriktiv: `allow_focus_window=false`, `allow_type_text=false`,
`allow_shortcuts=false`, `require_confirmation=true`, leeres
`SMOLIT_INTERACTION_OPEN_APP_CMD` / `…_FOCUS_WINDOW_CMD` meldet
ehrlich „Preconditions not met" bzw. `BackendUnsupported`. Kein OCR,
keine A11y-Traversierung, keine Pixel-Erkennung, keine globalen
Input-Grabs, keine Wayland-Fokus-Sonderpfade — siehe
[docs/api.md](docs/api.md) §2.6 und
[docs/presence_desktop_interaction.md](docs/presence_desktop_interaction.md)
§14b.

Eingehende IPC-Nachrichten:

```json
{"type":"interaction_open_application","application":"firefox"}
{"type":"interaction_focus_window","target":{"type":"window","name":"calendar"}}
{"type":"interaction_probe_accessibility"}
{"type":"interaction_discover_accessibility","hint":"Files"}
```

Zusätzlich ist ein **Linux Accessibility Backend Spike** gelandet
(Phase 8b, read-only). `interaction_probe_accessibility` liefert ein
getaggtes Ergebnis `uncertain` / `unavailable` / `failed` (mit Grund)
aus Session-Umgebung (`DBUS_SESSION_BUS_ADDRESS`, `WAYLAND_DISPLAY` /
`DISPLAY`, `AT_SPI_BUS_ADDRESS`) und einer Unix-Socket-Vorprüfung —
ohne echten AT-SPI-RPC. `interaction_discover_accessibility`
(optional mit `hint`) reicht dieses Verdikt an eine
Discovery-/Inspection-Oberfläche durch und gibt ein strukturiertes
`accessibility_discovery_result`-Envelope zurück. Der Discovery-Status
kennt zusätzlich `ok` (strukturierte Items vorhanden); pro Item trägt
das Payload `confidence` (`verified` bleibt für den späteren echten
RPC-Pfad reserviert, `discovered` liefert der heutige Hint-Echo-Pfad)
sowie `source`, optional `matched_hint`, `detail`, `app_name`. Das
Ergebnis läuft regulär durch das Action Event Model
(`action_planned` → … → `action_completed` / `action_failed` mit
`recovery_hint=fallback_unavailable`). Kein Klicken, kein
`type_text`-Pfad, keine Passwort-/Secret-Interaktion. Details in
[docs/api.md §2.8](docs/api.md) und
[docs/linux_interaction_backends_research.md](docs/linux_interaction_backends_research.md).

Aktionen mit `requires_confirmation=true` (heute: jede
`interaction_open_application` und jede `interaction_focus_window`)
gehen durch den **Approval / Confirmation Flow**: der Core sendet `approval_requested`, die UI
zeigt einen Banner mit Approve/Deny, und ein
`approval_response`-Frame settelt die Aktion. Ohne Antwort innerhalb
von `SMOLIT_APPROVAL_TIMEOUT_SECONDS` (Default 20) emittiert der Core
`approval_resolved` mit `decision="timed_out"` und anschließend
`action_cancelled`. Details: [docs/api.md §2.7](docs/api.md).

## UI (Godot, Phase 3.3 Presence MVP)

Unter [ui/](ui/) liegt ein Godot-4-Projekt, das die Core-Bridge als lokaler
Client konsumiert. Phase 3.3 erweitert den Avatar-MVP um ein **Presence- und
Overlay-MVP**: die UI unterscheidet zwischen einem ruhigen Docked-Modus,
einem Expanded-Modus (Log + Text-Eingabe sichtbar) und einem Action-Modus,
der auf standardisierte Action Events des Cores reagiert und symbolische
Target-Informationen in einem Banner anzeigt.

Presence (wie viel UI) und Avatar-State (wie der Avatar wirkt) laufen bewusst
als zwei unabhängige Achsen — siehe
[docs/presence_desktop_interaction.md](docs/presence_desktop_interaction.md).
Native Always-on-top, Click-through, transparenter Desktop-Overlay und echte
Pixel-/OCR-Interaktion sind **noch nicht** Teil dieses MVPs; die Architektur
ist aber so vorbereitet, dass ein späteres GDExtension-Overlay ohne
Umschreiben der Presence-Logik andocken kann.

### Starten

1. Godot 4.2+ öffnen, Projektordner `ui/` wählen, Projekt importieren.
2. Den Rust-Core mit aktivem IPC laufen lassen
   (`SMOLIT_IPC_ENABLED=true`, Default-Bind `127.0.0.1:8787`).
3. Godot-Szene ausführen. Es erscheint ein Fenster mit:

   - Header: Status (`connected` / `disconnected`), aktueller Presence-Mode,
     Toggle-Button `Expand` / `Dock`
   - Action Banner (nur sichtbar, wenn eine Action läuft) mit Titel, Step,
     einem Target-Chip samt Primärname (`[window] calendar`), optionaler
     Mapping-Zeile (`mapping: logical_space · towards calendar app`),
     kompaktem Target-Text und Status (completed / failed / cancelled)
   - Avatar-Bereich mit State-Label und Debug-State-Anzeige
   - Event-Log (RichTextLabel, farbcodiert) — nur im Expanded-Modus sichtbar
   - Eingabezeile + „Send" / „Ping"-Buttons — nur im Expanded-Modus sichtbar

### Aufbau

```text
ui/
├── project.godot
├── config.cfg                 # UI-Config (websocket_url, reconnect backoff)
├── autoload/
│   ├── event_bus.gd           # Signal-Hub (keine Logik)
│   └── ipc_client.gd          # WebSocketPeer-Wrapper mit Reconnect
├── scenes/
│   ├── main.tscn              # Composition Root: Header, Banner, Avatar, Log, Input
│   └── avatar/
│       └── avatar_root.tscn   # eigenständige Avatar-Szene
├── scripts/
│   ├── main.gd                # Scene-Controller (Presence-Wiring, Log, Input)
│   ├── presence/
│   │   ├── presence_state.gd        # Mode-Enum + Helpers
│   │   └── presence_controller.gd   # Presence-State-Maschine (Action-Events)
│   └── avatar/
│       ├── avatar_state.gd    # State-Enum + Name-Mapping
│       └── avatar_controller.gd  # State-Mapping + Rendering
└── assets/
    └── avatar/                # Platzhalter für spätere Sprites
```

### Avatar-States (MVP)

- `idle` → Grundzustand, auch nach Connect.
- `thinking` → Core sendet `thinking` (blinkender Indikator).
- `talking` → Core sendet `response` (kurzer Mouth-Tween, deterministischer
  Rückfall auf `idle` nach ~1,8 s).
- `disconnected` → Transport ist offen; ohne weitere Aktion zeigt der
  Avatar eine neutrale Farbe.
- `error` → kurzer Fehlerzustand nach `error`-Event, fällt auf `idle`
  bzw. `disconnected` zurück.
- `acting` → während `action_started` / `action_step` (nur wenn der Avatar
  nicht gerade `thinking` / `talking` ist), mit eigenem Farbton und
  Aktivitätsindikator. Fällt nach `action_completed` / `action_failed` /
  `action_cancelled` sauber zurück.

### Discovery Panel (Accessibility)

Neben dem Action-Banner rendert die UI seit der „verified target
discovery"-Stufe ein kleines **DiscoveryPanel**. Es wird sichtbar,
sobald der Core ein `accessibility_discovery_result` schickt, und
zeigt:

- ein Status-Badge (`ok` / `uncertain` / `unavailable` / `failed`),
- den ehrlichen Grund aus dem Core,
- pro Item Name, Rolle/Kind, ein Confidence-Badge
  (`[verified]` / `[discovered]`), optional `hint=…` oder `source`.

Die UI **interpretiert** nichts — sie rendert nur, was der Core
geliefert hat. Fehlende optionale Felder führen zu neutralen
Defaults, nicht zu Crashes.

### Presence-Modes (Phase 3.3 MVP)

Presence-State ist orthogonal zum Avatar-State und wird vom
`PresenceController` verwaltet:

- `docked` → ruhige, kompakte Präsenz; Log und Eingabezeile ausgeblendet.
- `expanded` → volle Interaktion; Log + Eingabezeile sichtbar. Umschalten
  über den Toggle-Button.
- `action` → automatisch aktiv, sobald der Core `action_started` /
  `action_step` sendet. Der Action-Banner zeigt Titel, aktuellen Step und
  symbolischen Target-Text. Nach `action_completed` / `action_failed` /
  `action_cancelled` hält die Presence kurz als „Nachhall" den Status und
  fällt dann zurück in den zuletzt gewählten Base-Modus.
- `disconnected` → Core nicht erreichbar; Toggle deaktiviert.

Die UI interpretiert Inhalte nicht — sie rendert ausschließlich, was der
Core über das Action Event Model v1 als nächsten sichtbaren Zustand
signalisiert.

Der Avatar hört ausschließlich am `EventBus`. Keine zweite
Core-Verbindung, keine UI-seitige Interpretation von Inhalten.

Scenes hängen ausschließlich an `EventBus` — der Transport (`IpcClient`)
kann später ersetzt werden, ohne Scene-Code anzufassen.

### Verbindungsverhalten

- Default-URL: `ws://127.0.0.1:8787` (überschreibbar in `ui/config.cfg`).
- Reconnect-Backoff 500 ms → 5 s, verdoppelnd, gecapped.
- Nach jedem erfolgreichen Connect sendet die UI automatisch
  `get_status` als Handshake.
- Während „disconnected" bleibt die UI benutzbar, `Send`/`Ping` sind
  deaktiviert.
