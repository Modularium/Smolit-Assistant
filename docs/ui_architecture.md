# Smolit Assistant – UI- und Avatar-Architektur

Dieses Dokument beschreibt den **heutigen Stand** der UI nach Phase 3.1 sowie
den geplanten Ausbau. Alles, was noch nicht implementiert ist, ist explizit
als Ziel-Zustand markiert.

Für das übergeordnete Zielbild von Smolit als sichtbare Desktop-Präsenz
und für das Zusammenspiel mit echter Desktop-Automation siehe
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).
Dieses Dokument hier bleibt auf die **UI-/Godot-Ebene** fokussiert.

---

## 1. Rolle der UI

Die Godot-UI ist ein **reiner Client** des Rust-Cores. Sie hat:

- **keine eigene Intelligenz** (kein ABrain-Aufruf, kein Prompting),
- **keine eigene Audio-Pipeline** (kein STT/TTS, kein Mikrofon, keine
  Lautsprecher-Ausgabe),
- **keine eigene Session-Wahrheit** (keine Chat-Historie, kein Profil,
  keine Preferences),
- **keine Protokollerweiterung** am IPC, die über das in
  [`docs/api.md`](./api.md) festgelegte Format hinausgeht.

Die UI konsumiert Events vom Core und rendert sie. Alle Interaktionen
werden als wohldefinierte IPC-Nachrichten an den Core zurückgespielt.

Im Sinne des Presence-Modells ist die UI der **Presence Layer**:
sichtbare Figur, Zustände, Overlay-Verhalten, Rückmeldung. Sie ist
ausdrücklich **nicht** die Stelle, an der Desktop-Automation
implementiert wird — siehe
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md),
Abschnitt 3 („Visual truth, not implementation coupling“) und
Abschnitt 15.

---

## 2. Systemübersicht

```text
┌────────────────────────────┐        ws://127.0.0.1:8787        ┌────────────────────┐
│  Godot UI (ui/)            │  ◀─────────────────────────────▶  │  Rust Core (core/) │
│  - Autoload EventBus       │     JSON Frames (siehe api.md)    │  - CLI Event-Loop  │
│  - Autoload IpcClient      │                                   │  - IPC-Server      │
│  - Scenes (Renderer)       │                                   │  - App (Handlers)  │
└────────────────────────────┘                                   │  - Audio-Adapter   │
                                                                 │  - ABrain-Adapter  │
                                                                 └────────────────────┘
                                                                          │
                                                                          ▼
                                                                 ┌────────────────────┐
                                                                 │  ABrain (CLI)      │
                                                                 │  externe Commands  │
                                                                 │  (STT / TTS)       │
                                                                 └────────────────────┘
```

Der Core ist die einzige Quelle der Wahrheit. UI und ABrain/Audio sind
jeweils Adaptergrenzen.

---

## 3. Verantwortlichkeiten

| Schicht        | Verantwortlich für                                           |
|----------------|--------------------------------------------------------------|
| Rust Core      | Orchestrierung, Konfiguration, Logging, Audio, IPC, ABrain   |
| IPC-Bridge     | lokaler WebSocket-Server, JSON-Protokoll, Event-Fan-out      |
| Godot UI       | Rendering, Animation, lokale Eingabe, Statusanzeige          |
| ABrain-Adapter | Textanfrage → Antworttext (heute CLI-Prozess)                |
| STT/TTS-Adapter| externe Commands, austauschbar per Env-Config                |

---

## 4. Nicht-Ziele der UI

Ausdrücklich **nicht** in der UI:

- keine Entscheidungslogik („was soll der Assistent antworten?"),
- keine Tool-Orchestrierung,
- keine zweite Runtime / kein zweiter Prozess-Manager,
- keine zweite Audiopipeline,
- keine persistente Wahrheit über den Verlauf (Event-Log ist volatil),
- keine direkten Zugriffe auf ABrain, Dateisysteme oder Subsysteme außerhalb
  der IPC-Nachrichten,
- **keine Desktop-Automation** (kein Klicken, Tippen, Fenster-Steuern,
  kein OCR/Screenshot). Desktop-Interaktion gehört in eine eigene
  Adapterfamilie unterhalb des Cores, nicht in Godot — siehe
  [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).

---

## 5. Godot-Projektstruktur (Ist-Zustand Phase 3.1)

```text
ui/
├── project.godot        # Godot-4-Projektdefinition, registriert Autoloads
├── config.cfg           # UI-eigene Config: websocket_url, reconnect, debug
├── autoload/
│   ├── event_bus.gd     # reiner Signal-Hub, keine Logik
│   └── ipc_client.gd    # WebSocketPeer-Wrapper, Reconnect, Frame-Parsing
├── scenes/
│   └── main.tscn        # Control → VBox(StatusLabel, Log, InputRow)
├── scripts/
│   └── main.gd          # Scene-Controller, verdrahtet EventBus + UI
├── assets/              # Platzhalter für 3.2
└── .gitignore
```

Scenes hängen ausschließlich am `EventBus`. Der Transport (`IpcClient`) ist
damit austauschbar, ohne Scene-Code anzufassen.

---

## 6. IPC-Bindung der UI

- Default-URL: `ws://127.0.0.1:8787`, überschreibbar in `ui/config.cfg`
  unter `[ipc] websocket_url`.
- Reconnect-Strategie: exponentielles Backoff von `min_backoff_ms = 500`
  bis `max_backoff_ms = 5000`, Verdopplung, gecapped.
- Nach jedem erfolgreichen Connect wird automatisch ein `get_status`
  als Handshake gesendet.
- Während *disconnected* bleibt die UI sichtbar und benutzbar; Send/Ping
  deaktivieren sich jedoch, da kein Transport offen ist.
- Ungültige JSON-Frames führen zu einer lokalen `error_received`-Emission,
  nicht zu einem Crash.
- Für freigabepflichtige Aktionen versteht die UI die zusätzlichen
  Approval-Frames (`approval_requested` / `approval_resolved`) aus
  [`docs/api.md`](./api.md) §2.7. `IpcClient.send_approval_response`
  ist der einzige Weg, Approve/Deny zurück an den Core zu schicken;
  `EventBus` vermittelt sie an die Scene, die einen modalen Banner
  mit Approve-/Deny-Buttons einblendet, solange eine Approval-ID
  offen ist.

Das genaue Protokoll (Eingangs- und Ausgangs-Nachrichten, Felder,
Semantik) ist in [`docs/api.md`](./api.md) beschrieben und ist die
autoritative Quelle; diese Datei dupliziert das Schema nicht.

---

## 7. Avatar-System (Phasen)

Avatar-Rendering ist **noch nicht implementiert**. Die Phasen unten sind
die geplante Ausbaustrecke, nicht der heutige Stand.

### Phase A – MVP-Log (Ist-Zustand 3.1)

- `StatusLabel` zeigt `connected` / `disconnected`.
- `RichTextLabel` rendert eingehende Events farbcodiert als Event-Log.
- `LineEdit` + Buttons „Send" / „Ping" bedienen `submit_text` und `ping`.
- Kein Avatar, keine Animation, keine Sprechblase.

### Phase B – 2D-Avatar + Zustände (Ziel 3.2)

- 2D-Sprite als Kind-Scene, zentrale State-Machine auf EventBus-Signalen
  (`thinking_received`, `response_received`, `error_received`,
  `heard_received`).
- Animationen für: `idle`, `thinking`, `talking`, `error`.
- Speech-Bubble ersetzt das RichText-Log als Primär-Anzeige; das Log
  kann als Debug-Panel bleiben.
- Keine Protokolländerung nötig; es werden nur bestehende Events gemappt.

### Phase B+ – Reaktion auf Action Events (Ziel)

Zusätzlich zu `thinking` / `response` / `heard` / `error` emittiert der
Core seit Action Event Model v1 (siehe [`docs/api.md`](./api.md), §2.5)
standardisierte **Action Events** (`action_planned`, `action_started`,
`action_step`, `action_completed`, `action_failed`, …). Sie sind die
vorgesehene Grundlage für:

- Avatar-/Präsenz-Reaktion auf Handlungsphasen statt nur auf
  `thinking`/`response`,
- spätere sichtbare Fehlerdarstellung (`action_failed` → Warn-/Failure-
  State am Avatar),
- spätere symbolische Bewegung Richtung Ziel (über `target` und
  `mapping`).

Wichtig für die UI-Ebene:

- **Mapping ist symbolisch.** `mapping.space` ∈
  `logical_space` / `window_space` / `screen_space`, ohne Geometrie.
  Die UI soll daraus eine Richtung / Intention ableiten, keine
  Pixelpositionen berechnen.
- **Additiv.** Die bestehenden Signale bleiben. Action Events werden
  schrittweise eingebunden, keine Umschreibung des Scene-Codes auf
  einmal.
- **Keine UI-Geschäftslogik.** Die UI reagiert auf die Events, sie
  interpretiert keine Targets eigenständig und löst keine
  Desktop-Aktionen aus.

### Phase C – Erweiterter Ausdruck (Ziel > 3.x)

- Feinere Zustände (z. B. `curious`, `focused`, `alert`).
- Speech-Sync mit TTS-Lebenszyklus (setzt TTS-Events im Protokoll voraus —
  aktuell nicht vorhanden).
- Optional höher aufgelöste 2.5D/3D-Darstellung.

Jede Phase nach A ist additiv zum vorherigen Stand und erfordert entweder
reine UI-Arbeit oder eine klar dokumentierte Protokollerweiterung im
Core.

---

## 8. Zustands- und Eventmodell (Ist-Zustand)

Die UI kennt drei Zustandsquellen:

1. **Transportzustand** (`connected` / `disconnected`) — von `IpcClient`.
2. **Statuspayload** (`status_received`) — zuletzt gemeldetes Core-Status-Dict.
3. **Event-Strom** (`thinking`, `response`, `heard`, `error`, `pong`) — rein
   reaktiv, wird vom `EventBus` verteilt.

Es gibt **keinen** von der UI gehaltenen Dialogzustand. Jede neue
Conversation-Turn startet mit einem `submit_text` oder `voice_once`.

---

## 9. Always-on-top- und Overlay-Verhalten (Ziel-Zustand)

Phase 3.3 liefert das **Presence-MVP** in-window: die Modi
**Docked / Expanded / Action / Disconnected** laufen bereits als
eigenständige State-Maschine (`ui/scripts/presence/`). Presence-State
(UI-Umfang) und Avatar-State (visueller Ausdruck) sind bewusst
orthogonal geführt.

Was das MVP umsetzt:

- eigener `PresenceController` als Autoload-artiger Node in `main.tscn`,
- Hold-Timer für Completed / Failed / Cancelled als Nachhall nach einer
  Action, bevor die Presence in den gewählten Base-Mode zurückfällt,
- Action-Banner mit Titel, Step und **symbolischem** Target-Text
  (`→ Anwendung`, `→ Fenstertitel`, `→ Label (Rolle)`, `→ Region`) —
  ohne Pixelgeometrie,
- manuelle Umschaltung zwischen Docked und Expanded über den
  Header-Toggle; Docked blendet Log und Eingabezeile aus.

Noch **nicht** umgesetzt und explizit ausserhalb des MVP:

- randloses Fenster,
- transparenter Hintergrund,
- optionales Click-through (togglebar),
- Snap-to-Edge / Idle-Movement / Multi-Monitor-Heuristik.

Die Architektur ist so vorbereitet, dass ein späteres natives Overlay
(GDExtension oder Window-Mode-Wechsel) nur Rendering und Fenstermodus
berühren muss — die Presence-Logik bleibt unverändert und zieht ihren
Modus weiterhin aus den Core-Events. Das Zielbild bleibt
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md),
§6.

Wichtig: **natives Overlay ist nicht automatisch Teil von Godot selbst.**
Fähigkeiten wie Always-on-top, Click-through, transparenter Desktop-
Überzug und Pixel-Positionierung hängen an Protokoll (Wayland vs. X11)
und Compositor (Mutter, KWin, wlroots, …) und sind unter Ubuntu 24.04
Wayland nicht pauschal verfügbar. Die UI-Architektur bleibt deshalb
bewusst **host-window-neutral**: Scenes und Presence-Controller kennen
kein Always-on-top, keine Input-Region, keine Portal-Aufrufe. Die
Linux-spezifische Fenster- und Overlay-Strategie — inklusive der
geplanten separaten Window-Behavior-Abstraktion — ist in
[`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
dokumentiert.

---

## 10. Designprinzipien

- **Core-driven**: UI reagiert, sie entscheidet nicht.
- **Transport-entkoppelt**: Scenes kennen nur den EventBus, nicht den
  WebSocket.
- **Additiv**: neue Fähigkeiten kommen über zusätzliche Events, nicht über
  Umschreiben bestehender.
- **Graceful failure**: fehlende Core-Verbindung, ungültige Frames oder
  fehlende Audiocommands dürfen die UI nicht abstürzen lassen.
- **Minimalismus**: keine klassische Fensterflut, Fokus auf Präsenz statt
  auf Bedien-UI.
- **Action-driven Avatar**: Avatar-Zustände und -Reaktionen sind
  Core-/Action-getrieben. Die UI animiert, sie entscheidet nicht über
  Handlung, Ziel oder Erfolg einer Desktop-Aktion — das kommt als
  Event-Strom aus Core und Desktop Interaction Layer.
- **Interaction Layer bleibt im Core**: Desktop-nahe Ausführung
  (`core/src/interaction/`) läuft strikt serverseitig. Die UI sendet
  höchstens einen symbolischen Auslöser
  (`interaction_open_application`, siehe
  [`docs/api.md`](./api.md), §2.6) und konsumiert die zurückkommenden
  Action Events — sie führt nichts selbst aus. Die UI stellt nur das
  Approval-Banner dar, der Core entscheidet per Policy und Backend
  über Ausführbarkeit, Verifikation und Recovery.

---

## 11. Offene Punkte

- **Avatar-Rendering** — Platzhalter-Grafik; echte Sprite-/
  Charakteranimation steht aus.
- **Natives Overlay** (Folge zu 3.3) — Always-on-top, Transparenz,
  Click-through, Snap-to-Edge. Presence-Logik ist bereits in-window
  fertig; das Desktop-Overlay hängt nur noch am Fenstermodus.
- **TTS-Lebenszyklus-Events** — aktuell gibt es kein `speaking_started` /
  `speaking_ended` im Protokoll; Animation-Sync hängt davon ab.
- **Emotion-Feld** — heute transportiert das Protokoll keine Emotion in
  `response`-Payloads. Sobald ABrain Emotionen liefert, wird das Feld in
  [`docs/api.md`](./api.md) additiv ergänzt.
- **Headless/Export** — Export-Pipeline und CI-Smoke für Godot stehen aus.
