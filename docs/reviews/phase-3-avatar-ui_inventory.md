# Phase 3 – Avatar UI · Inventar & Scope-Analyse

Status: Pre-Implementation Inventory
Scope-Name (für Branch/Review): `phase-3-avatar-ui`

Dieses Dokument erfasst den Ist-Zustand **vor** jeglicher Godot-Arbeit,
damit die Phase-3-Umsetzung idempotent, architekturkonform und ohne
Doppelarbeit starten kann (vgl. `MASTER-PROMPT.md` Abschnitte C, E, F).

---

## 1. Ist-Zustand der kanonischen Pfade

### 1.1 `ui/`

```text
ui/
└── .gitkeep
```

Leer. Es existieren **keine** Godot-Projektdateien, Scenes, Scripts oder
Exportkonfigurationen. Nichts zu integrieren, nichts zu migrieren.

### 1.2 `core/` (IPC/Audio-Surface, die die UI konsumieren wird)

- `core/src/ipc/server.rs` – lokaler WebSocket-Server auf `SMOLIT_IPC_BIND`
  (Default `127.0.0.1:8787`)
- `core/src/ipc/protocol.rs` – kanonisches JSON-Protokoll

  - Incoming: `ping`, `get_status`, `submit_text`, `speak_text`, `voice_once`
  - Outgoing: `pong`, `status`, `thinking`, `response`, `heard`, `error`
- `core/src/app.rs` – geteilte Handler (`handle_text_query`,
  `handle_voice_once`, `handle_speak`, `build_status_payload`,
  `maybe_auto_speak`) – genau diese Surface wird die UI indirekt nutzen.

Kein Umbau nötig, damit Godot anschlussfähig ist.

### 1.3 `docs/` (Vorarbeiten, die Scope mitdefinieren)

- `docs/ui_architecture.md` – definiert Zielbild (Avatar, Animationsstates
  `idle/thinking/talking/reacting/error`, Overlay, Always-on-top,
  Click-through). Als Source-of-Truth für UI-Zielzustand zu nutzen.
- `docs/api.md` – Core ↔ ABrain Protokoll (nicht UI, aber relevant für
  spätere Emotion-Felder).
- `docs/VISION.md` – Leitprinzipien.
- `docs/reviews/` – existierte noch nicht, wurde mit diesem Dokument angelegt.

### 1.4 `adapters/`, `config/`, `scripts/`

Alle drei enthalten nur `.gitkeep` (bzw. leere Unterordner). Nicht
Phase-3-relevant.

---

## 2. Roadmap-Bezug

Aus `ROADMAP.md`, Phase 3 – Avatar UI (V0.4):

- [ ] Godot project setup
- [ ] WebSocket client
- [ ] connect to core IPC
- [ ] 2D avatar rendering
- [ ] always-on-top window
- [ ] transparent background
- [ ] basic input (click/text)
- [ ] text display (speech bubble)
- [ ] reconnect + lifecycle handling

Phase 0–2 sind per ROADMAP als abgeschlossen markiert. Phase 3 ist die
erste echte UI-Phase und gleichzeitig die erste Phase, die den
Prozess-Split (Core ↔ UI) materialisiert.

---

## 3. Scope dieser Umsetzung (Phase 3 – Subeinheit 1)

Phase 3 ist zu groß für einen einzigen mergebaren Schritt. Entlang echter
Architekturgrenzen (vgl. MASTER-PROMPT D) schlage ich **drei Subeinheiten**
vor. Dieses Inventar deckt primär die erste Subeinheit ab.

### Subeinheit 3.1 · Godot-Projekt-Bootstrap + IPC-Client (MVP)

Ziel: Godot-Projekt legt die minimale Verbindung zur bestehenden
Core-Bridge her und kann Text round-trippen — ohne Avatar, ohne
Always-on-top, ohne Transparenz.

Enthält:

- Godot-Projektstruktur unter `ui/` (Projekt-Datei, Autoload-Bus, ein
  einziger Scene-Einstieg)
- WebSocket-Client, der auf `ws://127.0.0.1:8787` verbindet
- Eingabefeld + Ausgabefeld (Textbubble-Platzhalter)
- Reconnect + Lifecycle (sauber schließen, sauber neu verbinden)
- Minimaler Smoke: Core starten, Godot-Projekt öffnen, Nachricht senden,
  `response` empfangen und anzeigen.

Enthält **NICHT**:

- Avatar-Sprite oder Animation
- Always-on-top, Transparenz, Click-through
- Emotion-Mapping
- Voice-Trigger-UI
- Godot Headless Export

### Subeinheit 3.2 · Avatar + Zustandsrendering

- 2D-Platzhalter-Avatar
- Animationsstates (idle/thinking/talking/error) auf Basis der existierenden
  Outgoing-Events (`thinking`, `response`, `error`, `heard`)
- Speech-Bubble mit Responsetext

### Subeinheit 3.3 · Fenster-Präsenz

- Borderless / Always-on-top
- Transparenter Hintergrund
- Click-through als Toggle

Begründung der Aufteilung: jede Subeinheit hat eine eigene, saubere
Architekturgrenze und kann isoliert reviewt/gemergt werden. Bricht man
sie nicht auf, bündeln sich Godot-Setup, Rendering und Window-Manager-
Spezifika in einem Mega-Diff — unreviewbar und nicht idempotent.

---

## 4. Festzulegende Architektur-Entscheidungen (vor Subeinheit 3.1)

Diese Einmalentscheidungen sollten **vor** dem ersten Godot-Commit
festgezurrt werden, um Rework zu vermeiden.

### 4.1 Godot-Version

**Empfehlung:** Godot 4.x (LTS-Linie). Begründung: WebSocket-Support
ist in 4.x deutlich besser (`WebSocketPeer`), und 3.x ist EOL-nah.

### 4.2 Scripting-Sprache

**Empfehlung:** GDScript.
Begründung: kein .NET-Tooling, kein Build-Overhead, keine Cross-Platform-
Stolperfallen. Core-Logik bleibt sowieso in Rust — die UI soll „Renderer,
nicht Brain" sein (VISION.md + Smolit-Regel J.2). C# würde ohne Gegenwert
Komplexität addieren.

### 4.3 WebSocket-Client-Form

**Empfehlung:** `WebSocketPeer` (in Godot 4 eingebaut, low-level, reicht
für Text-Frames). Kein Fremd-Plugin, keine GDExtension.

### 4.4 Projektlayout unter `ui/`

Vorschlag:

```text
ui/
├── project.godot
├── .gitignore          # .godot/, *.import, export_presets.cfg ausschließen
├── scenes/
│   └── main.tscn
├── scripts/
│   ├── ipc_client.gd   # WebSocketPeer-Wrapper
│   ├── event_bus.gd    # Autoload-Signalhub
│   └── main.gd         # Scene-Controller
└── assets/             # leer in 3.1
```

Autoload `event_bus.gd` als zentrale Signal-Drehscheibe — damit später
der Avatar-Scene nur auf Signale reagiert und die IPC-Schicht unverändert
bleibt.

### 4.5 Config-Kopplung

UI soll die Bind-Adresse **nicht** hart kodieren. Vorschlag: lesen aus
einer kleinen `ui/config.cfg` mit Default `127.0.0.1:8787`, später optional
aus ENV. Keine Duplizierung von `.env` — die Config gehört in den Core,
die UI bekommt nur die Verbindungsparameter.

### 4.6 Reconnect-Strategie

- Exponentielles Backoff 500 ms → 5 s, gecapped
- Bei erfolgreicher Verbindung: automatisches `get_status` als Handshake
- Bei Core-Abwesenheit: UI bleibt nutzbar (Disabled-Zustand), aber
  sendet nichts

### 4.7 Protokoll-Erweiterungen?

**Nein, in 3.1 nicht.** Das bestehende Protokoll reicht für Text-Round-Trip.
Emotion-Feld und Audio-Sync-Events gehören zu Phase 4.

---

## 5. Architektur-Invarianten, die bewahrt werden müssen

Aus `MASTER-PROMPT.md` Abschnitte B + J, für Phase 3 relevant:

1. Keine Business-Logik in `ui/` (kein ABrain-Call, keine TTS/STT-
   Entscheidung, kein Tool-Routing).
2. Kein zweiter IPC-Stack (Godot-Client konsumiert nur das bestehende
   `core/src/ipc/` Protokoll).
3. Keine zweite Session-/State-Wahrheit (UI hält keine dauerhafte
   Historie — das ist Phase 5).
4. Keine harte Kopplung an spezifische STT/TTS-Engines in UI-Ebene.
5. IPC bleibt lokal (`127.0.0.1`).
6. Nur additive Änderungen — `core/` bleibt unverändert in 3.1.

---

## 6. Out of Scope für gesamte Phase 3

(als Leitplanke, damit Scope nicht wandert)

- Godot-Export/Packaging (Phase 10)
- Emotion-Mapping Core → UI (Phase 4)
- Speech-Sync TTS ↔ Talking-Animation (Phase 4)
- Voice-Trigger-UI / Push-to-Talk-Button (Phase 4/7)
- Tool-Feedback-Rendering (Phase 8)
- Memory-/Profil-Anzeige (Phase 5)
- Presence / Screen-Movement (Phase 6)

---

## 7. Risiken & offene Punkte

- **Transparenz + Always-on-top sind plattformabhängig.** Linux
  (X11 vs. Wayland), Windows und macOS verhalten sich unterschiedlich.
  → Nicht in 3.1 lösen. In 3.3 zuerst auf einer Plattform validieren
  (primär Linux/X11, da Entwickler-Setup), Abweichungen dokumentieren.
- **Godot-Projektdateien sind teilweise generiert** (`.godot/`,
  `*.import`). `.gitignore` muss präzise sein, sonst wandern Binaries
  in den Tree.
- **Kein Godot-Headless-Smoke in CI** aktuell vorgesehen — Verifikation
  läuft in 3.1 manuell. Das ist ok, solange dokumentiert.

---

## 8. Nächster Schritt

Subeinheit 3.1 (Godot-Projekt-Bootstrap + IPC-Client MVP) implementieren,
sobald die Architektur-Entscheidungen in Abschnitt 4 bestätigt sind.

Begleitend entsteht dann `docs/reviews/phase-3-avatar-ui_review.md` mit
dem Abgleich gegen dieses Inventar.
