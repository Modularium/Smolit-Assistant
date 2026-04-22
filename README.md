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

### Micro-Animation / Personality Layer v1

Zusätzlich zum State-Mapping trägt der Avatar eine kleine, rein visuelle
Ausdrucksschicht — keine neuen States, keine neuen Core-Events, nur
leichte Körpersprache:

- **Idle** atmet sehr ruhig (Scale-Puls ~3 s, ±1,5 %) und zeigt alle
  14–28 s einen kurzen „curious wiggle" als Rotationsnudge.
- **Thinking** atmet enger und langsamer (fokussiert), zusätzlich zum
  bestehenden Alpha-Puls.
- **Talking** puls rhythmisch leicht aktiver als Idle.
- **Acting** hat einen minimal zielgerichteteren Puls, die bestehende
  Target-Tönung bleibt erhalten.
- **Error** spielt einen kurzen, einmaligen Startle (Flinch + Rebound +
  Settle) und bleibt danach ruhig.
- **Disconnected** bleibt bewusst still.

Hover, Idle-Atem, State-Pulse und Wiggle sitzen auf getrennten
Transform-Properties und kollidieren daher nicht. Siehe
[docs/ui_architecture.md §7](docs/ui_architecture.md) „Phase B++".

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

### Compact Input UX (Docked)

Im Docked-Modus öffnet ein Klick auf den Avatar ein kleines
**Compact Input Panel** direkt am Icon — eine leichte Schnellinteraktion,
kein zweites Expanded. Inhalte:

- **Text + Send** — geht über denselben `submit_text`-Pfad wie die
  Expanded-Eingabe; Enter sendet ebenfalls.
- **Voice** — löst den bestehenden `voice_once`-Pfad aus.
- **+ Files** — in dieser Phase nur ein ehrlicher Platzhalter
  (`Datei-Anhänge noch nicht implementiert`). Kein echtes
  Attachment-Backend.
- **Commands** — togglet eine kompakte Mini-Hilfe mit den heute
  tatsächlich unterstützten Flows (`help`, `voice`, `audio-status`,
  `interaction_probe_accessibility`, `interaction_discover_accessibility`).
- **✕ / Escape** — schließt das Panel.

Das Panel ist bewusst ein UI-Substate im Docked-Modus, kein neuer
globaler Presence-Mode: ein Wechsel nach Expanded oder Disconnected
schließt es kontrolliert, Approval- und Action-Banner bleiben darüber
sichtbar. Siehe
[docs/ui_architecture.md §8.3](docs/ui_architecture.md).

### Linux Window Behavior (Spike v1, opt-in)

Für die spätere Overlay-Linie (Phase 3b) sitzt unter
[`ui/scripts/window_behavior/`](ui/scripts/window_behavior/) eine kleine,
bewusst zurückhaltende Capability-/Probe-Schicht:

- Capability-Detection liest Session-Typ, DisplayServer-Namen,
  `XDG_CURRENT_DESKTOP` und das Projekt-Setting
  `display/window/per_pixel_transparency/allowed`. Pro Fähigkeit
  (`transparency`, `click_through`, `always_on_top`) kommt ein
  getaggter Status (`available` / `experimental` / `unsupported` /
  `unknown`) mit Begründung heraus.
- Optionaler Runtime-Probe setzt testweise
  `WINDOW_FLAG_TRANSPARENT` und `WINDOW_FLAG_MOUSE_PASSTHROUGH` und
  liest sie zurück. Aktivierung per Umgebungsvariable:
  `SMOLIT_WINDOW_PROBE=1 <godot-run>`. Standardmäßig wird das
  Fenster danach wieder auf den vorherigen Zustand gesetzt; wer das
  Ergebnis stehen lassen will, ergänzt `SMOLIT_WINDOW_PROBE_REVERT=0`.
- Always-on-top wird hier ausdrücklich **nicht** gesetzt — unter
  Ubuntu 24.04 / GNOME/Mutter ist es über reguläre Toplevel-Hints
  nicht zuverlässig, und der Spike verspricht das deshalb nicht.

Der Spike ist rein hostseitig: keine IPC-Änderung, keine
Scene-Kopplung, keine neue UI. Ergebnisse landen per `print()` im
Log. Einordnung und Grenzen siehe
[docs/linux_window_overlay_architecture.md §F.1](docs/linux_window_overlay_architecture.md)
und
[docs/ui_architecture.md §9.1](docs/ui_architecture.md).

### Overlay MVP Phase B (opt-in transparentes Presence-Fenster)

Aufbauend auf dem Capability-Spike ist jetzt ein **opt-in Overlay-MVP**
gelandet. Ohne Opt-in bleibt das Verhalten unverändert. Mit
`SMOLIT_UI_OVERLAY=1 <godot-run>` — und nur dann, wenn die
Transparenz-Capability im aktuellen Setup tragfähig ist — läuft Smolit
mit:

- transparentem Hintergrund (`Viewport.transparent_bg = true` +
  `WINDOW_FLAG_TRANSPARENT = true`; das Projekt-Setting
  `display/window/per_pixel_transparency/allowed` ist gesetzt),
- borderlosem Fenster (`WINDOW_FLAG_BORDERLESS = true`),
- unveränderten Presence-/Avatar-Modi — nur die äußere Fensterhülle
  ändert sich.

Bewusst **nicht** aktiviert:

- **Kein Always-on-top.** Unter Ubuntu 24.04 / GNOME/Mutter ist es
  über reguläre Toplevel-Hints nicht zuverlässig; X11 wäre machbar,
  aber in Phase B nicht versprochen.
- **Kein produktives Click-through.** Ein naives
  `WINDOW_FLAG_MOUSE_PASSTHROUGH=true` würde das ganze Fenster
  (inklusive Avatar, Banner, Eingabefelder) für Eingaben durchlässig
  machen. Ein ehrlicher Schritt braucht interaktive Zonen /
  Passthrough-Polygone und bleibt Folgearbeit.

Fallback-Semantik: meldet die Capability-Detection Transparenz als
`unsupported` / `unknown`, bleibt das Fenster im normalen Modus und der
Grund landet im Log. Keine stillen Umschaltungen. Details siehe
[docs/linux_window_overlay_architecture.md §F.2](docs/linux_window_overlay_architecture.md)
und
[docs/ui_architecture.md §9.2](docs/ui_architecture.md).

### Overlay Click-through (opt-in, setzt auf Phase B auf)

Für produktives Click-through — Avatar und sichtbare Panels bleiben
klickbar, der leere Rest des Fensters wird passthrough — gibt es einen
zweiten, eigenen Opt-in:

```bash
SMOLIT_UI_OVERLAY=1 SMOLIT_UI_CLICK_THROUGH=1 <godot-run>
```

Der Folgeschritt aktiviert sich **ausschließlich**, wenn *alle* vier
Bedingungen erfüllt sind:

- `SMOLIT_UI_OVERLAY=1` ist gesetzt,
- `SMOLIT_UI_CLICK_THROUGH=1` ist gesetzt,
- der Overlay-MVP meldet sich als wirklich aktiv (Transparenz
  tragfähig),
- mindestens eine *gültige* interaktive Zone lässt sich aus dem
  aktuellen Layout ableiten. Zonen stammen aus einer expliziten
  Allowlist (Avatar, Header, Action-/Approval-/Discovery-Banner,
  DockPanel, CompactInputPanel), müssen im Tree sichtbar sein, eine
  Rohsize `> 0` haben, werden am Viewport geclamt und müssen nach dem
  Clamp eine Mindestkantenlänge überschreiten (degenerierte Rects
  fallen raus).

Sonst bleibt das Fenster vollständig interaktiv; der Controller
protokolliert einen **einheitlichen Phasen-Report** mit den Achsen
`requested / overlay_requested / overlay_active / capable /
zones_derived / zones_valid / active`, gefolgt von Bounds, Zonenliste
und einer `reason`-Zeile (z. B. `overlay not requested`,
`click-through not requested`, `overlay inactive`, `capability
unsupported/unknown` oder `no valid interactive zones yet`). Refresh-
Zeilen loggen nur bei echter Bounds-Änderung (Dedup). Keine stillen
Aktivierungen.

**MVP-Grenze.** Godots `DisplayServer.window_set_mouse_passthrough`
kennt pro Fenster genau einen Polygonpfad. Der Controller fasst daher
alle gültigen Zonen zu einer einzelnen Bounding-Rect-Union zusammen;
leerer Raum innerhalb dieser Union bleibt klickbar. Das ist bewusst
noch nicht das finale Interaktionsmodell — echte Multi-Polygon-Shapes
(XShape-Multirect / `wl_surface.set_input_region` mit mehreren
Rechtecken) bleiben Folgearbeit. Details siehe
[docs/linux_window_overlay_architecture.md §F.3](docs/linux_window_overlay_architecture.md)
und
[docs/ui_architecture.md §9.3](docs/ui_architecture.md).

### Always-on-Top — was Smolit verspricht / nicht verspricht

Unter Ubuntu 24.04 / GNOME/Wayland (Zielsession) verspricht Smolit
**bewusst kein Always-on-top**. Die sichtbare Desktop-Präsenz läuft
über den Overlay-MVP (transparent + borderless, opt-in) und den
optionalen Click-through-Folgeschritt — das ist der vollständige
produktive Pfad, mehr behaupten wir nicht. Nutzer, die unter GNOME
ein sichtbares AOT-Verhalten wünschen, verwenden die GNOME-eigene
„Always on Top"-Option im Titelleistenmenü des Compositors.

- **X11-Sonderpfad (opt-in) — jetzt als kleiner MVP vorhanden.**
  `SMOLIT_UI_ALWAYS_ON_TOP=1` setzt unter echter X11-Session
  `WINDOW_FLAG_ALWAYS_ON_TOP` (entspricht `_NET_WM_STATE_ABOVE`).
  Der Pfad ist strikt X11-only: unter Wayland/GNOME, unter headless
  oder bei unbekannter Session bleibt er ein ehrlicher No-op mit
  klarem Log-Grund. Das ist ausdrücklich **kein** universelles
  Linux-AOT-Feature und **kein** Wayland/GNOME-Versprechen.
- **GNOME-Shell-Extension** ist als Pfad ausdrücklich zurückgestellt
  (Pflegeaufwand, Versionsbindung, Sicherheitsmodell).
- **wlroots / layer-shell** ist dokumentierte Möglichkeit, kein
  aktuelles Ziel.
- **Diagnose-Probe.** Der bestehende opt-in `SMOLIT_WINDOW_PROBE=1`
  enthält einen kurzen, reversiblen AOT-Flag-Versuch mit
  ehrlichem Log — „flag accepted by API — not a user-visible
  guarantee under Mutter". Kein produktives Feature.

Für reproduzierbare Verifikationsläufe bringt
[scripts/run_overlay_verification.sh](scripts/run_overlay_verification.sh)
jetzt zusätzlich einen `aot-x11`-Case (setzt
`SMOLIT_UI_ALWAYS_ON_TOP=1` + `SMOLIT_WINDOW_REPORT=1`), der das
Ergebnis im konsolidierten Runtime-Report ausgibt.

Vollständige Begründung und Kriterien:
[docs/linux_always_on_top_decision.md](docs/linux_always_on_top_decision.md).

### Overlay-Verifikation (nächster Schritt: reale Messung)

Der nächste konkrete Arbeitsschritt auf der Overlay-Linie ist **kein
neues Feature**, sondern **reale Verifikation** auf echten Sessions.
Dafür gibt es jetzt zwei kleine Hilfen:

- **Opt-in Runtime-Report** via `SMOLIT_WINDOW_REPORT=1`. Druckt am
  Ende von `_ready()` genau einen konsolidierten Konsolenblock mit
  Session, Display-Driver, XDG-Desktop, Capabilities sowie dem
  tatsächlich erreichten Zustand von Overlay und Click-through
  (inkl. Bounds und Zonenliste). Kein Dauer-Log, keine Scene-Logik,
  keine IPC.
- **Verifikations-Wrapper** unter
  [`scripts/run_overlay_verification.sh`](scripts/run_overlay_verification.sh),
  der die typischen Env-Kombinationen (`baseline`, `overlay`,
  `click-through`, `probe`, `full`, `report`) mit oder ohne `--headless`
  startet. Hilft, reproduzierbare Läufe für die Matrix in
  [docs/linux_overlay_verification_matrix.md](docs/linux_overlay_verification_matrix.md)
  zu erzeugen.

Die Matrix deckt Baseline, Overlay-only, Overlay + Click-through,
Probe-Pfad, Docked↔Expanded-Wechsel, Banner-Sichtbarkeit, CompactInput,
sowie offene Hypothesen zu Fractional Scaling und XWayland ab —
ausdrücklich als Messlinie, nicht als Produktzusage.

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
