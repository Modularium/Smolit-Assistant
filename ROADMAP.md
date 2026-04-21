# Smolit AI Assistant – Developer ROADMAP

## Vision

Ein leichtgewichtiger, persistenter KI-Assistent mit eigener Präsenz auf dem
Desktop:

- **Rust Core** — Runtime, Orchestrierung, Adapter.
- **Godot UI** — Avatar, Interaktion, Rendering.
- **ABrain** — Reasoning, Lernen.

Siehe [docs/VISION.md](./docs/VISION.md) für die Produktperspektive und
[docs/ui_architecture.md](./docs/ui_architecture.md) /
[docs/api.md](./docs/api.md) für die technische Detailebene.

---

## Stack

- Core: Rust (tokio, tokio-tungstenite, tracing).
- UI: Godot 4.x (GDScript, WebSocketPeer).
- IPC: WebSocket (lokal, `127.0.0.1:8787`).
- ABrain: heute CLI-Adapter, Ziel natives API.
- Audio: externe STT/TTS-Commands (pluggable).

---

## Ist-Zustand (Stand Phase 3.2)

Produktiv im Repo vorhanden und durch Tests gedeckt:

- Rust-Daemon mit CLI-Loop (`core/src/event_loop.rs`).
- ABrain-CLI-Adapter (`core/src/abrain.rs`, `adapters/abrain/`).
- STT/TTS-Command-Adapter (`core/src/audio/`), CLI-Befehle `voice`,
  `speak`, `audio-status`.
- Lokale WebSocket-Bridge mit geteilten Handlern (`core/src/ipc/`,
  `core/src/app.rs`).
- Godot-UI-Bootstrap (`ui/`) mit Autoloads `EventBus` + `IpcClient`,
  Status-/Event-Log, Reconnect 500 ms → 5 s.
- Avatar-MVP (`ui/scenes/avatar/`, `ui/scripts/avatar/`) mit
  State-Mapping `idle` / `thinking` / `talking` (+ `disconnected` /
  `error`), deterministischem Rückfall auf `idle` und Platzhalter-
  Rendering (ColorRect-Body, Gesicht, Mouth-Tween, Thinking-Indicator).

Was noch **nicht** existiert: echte Charakteranimation, Always-on-top /
transparenter Hintergrund, Emotion-Mapping, Personality, natives
ABrain-API, Multimodalität, Tool-Orchestrierung.

---

## Phase 0 – Core Foundation (V0.1) ✅

- [x] Rust-Daemon
- [x] ABrain CLI-Adapter
- [x] Async CLI-Loop
- [x] Config (.env)
- [x] Logging (tracing)
- [x] Timeout- und Fehlerbehandlung

---

## Phase 1 – Voice Interface (V0.2) ✅

- [x] STT-Command-Adapter
- [x] TTS-Command-Adapter
- [x] `voice`-Befehl (einmaliges STT → ABrain)
- [x] `speak <text>`-Befehl
- [x] `audio-status`-Befehl
- [x] `auto-speak`-Config
- [x] sicheres Fallback-Verhalten bei fehlenden Commands

### Offen (Phase 1)

- [ ] Push-to-Talk
- [ ] Wake-Word
- [ ] Streaming-Audio
- [ ] Engine-Presets (Piper, Whisper.cpp, Vosk, …)

---

## Phase 2 – IPC Bridge (V0.3) ✅

- [x] WebSocket-Server (lokal, additiv zum CLI-Loop)
- [x] JSON-Protokoll (`core/src/ipc/protocol.rs`)
- [x] Geteilte Handler (CLI und IPC nutzen denselben Code)
- [x] Events: `thinking`, `response`, `heard`, `error`
- [x] `get_status`-Endpoint
- [x] Robuste Fehlerbehandlung (kein Crash bei ungültigem JSON)

### Offen (Phase 2)

- [ ] Server-seitige Reconnect-/Keepalive-Politik ausbauen
- [ ] Event-Erweiterungen (TTS-Start/-Ende)
- [ ] Streaming-Support

---

## Phase 3 – Avatar UI (V0.4)

### Subeinheit 3.1 – Bootstrap + IPC-Client MVP ✅

- [x] Godot-4-Projekt (`ui/project.godot`)
- [x] WebSocket-Client (`ui/autoload/ipc_client.gd`, `WebSocketPeer`)
- [x] Verbindung zu Core-IPC (`ws://127.0.0.1:8787`)
- [x] Basis-Eingabe (Text + Buttons, noch kein Voice-Trigger)
- [x] Textanzeige (log-artig, farbcodiert via RichTextLabel)
- [x] Reconnect- und Lifecycle-Handling (500 ms → 5 s Backoff,
      automatisches `get_status` nach Connect)

### Subeinheit 3.2 – Avatar + Zustandsrendering (MVP ✅)

- [x] Avatar-Szene (`ui/scenes/avatar/avatar_root.tscn`) mit eigener
      Node-Struktur und State-Controller
      (`ui/scripts/avatar/avatar_controller.gd`)
- [x] State-Mapping auf bestehenden EventBus-Signalen
      (`idle` / `thinking` / `talking` / `disconnected` / `error`)
- [x] Deterministischer Rückfall `talking → idle` via Timer
- [x] Platzhalter-Rendering (ColorRect-Body, Gesicht, Mouth-Tween,
      Thinking-Indicator)

### Offen (Phase 3.2)

- [ ] Echte Sprite-/Charakteranimation statt Platzhalter
- [ ] Speech-Bubble für `response` und `heard`
- [ ] Speech-Sync via TTS-Lebenszyklus-Events (setzt Protokollerweiterung
      `speaking_started` / `speaking_ended` voraus)

### Subeinheit 3.3 – Fenster-Präsenz

- [ ] Always-on-top-Fenster
- [ ] transparenter Hintergrund
- [ ] Click-through (togglebar)

---

## Phase 4 – Behavioral Layer (V0.5)

- [ ] Feinere Animationszustände (`curious`, `focused`, `alert`, …)
- [ ] Emotion-Mapping Core → UI (setzt Protokollerweiterung um
      `emotion` voraus)
- [ ] Speech-Sync (TTS-Lebenszyklus-Events → Animation)
- [ ] Antwortabhängige Reaktionen
- [ ] erste Persönlichkeits-Cues

---

## Phase 5 – Personality & Memory (V0.6)

- [ ] User-Profil
- [ ] Session-State
- [ ] Conversation-Memory
- [ ] Preference-Storage
- [ ] Context-aware Responses
- [ ] Verhaltensmodulation via ABrain

---

## Phase 6 – Presence System (V0.7)

- [ ] Screen-Movement
- [ ] Idle-Behavior-Cycles
- [ ] Attention-System
- [ ] Interaction-Zones
- [ ] Snap-to-Edge-Verhalten
- [ ] Click-through-Modus (ausgebaut)

---

## Phase 7 – Interaction Layer (V0.8)

- [ ] Unified Input-Routing (Text / Voice / UI-Events)
- [ ] Multimodales Routing
- [ ] Event-getriebenes Interaktionsmodell
- [ ] File- / Image-Input-Hooks

---

## Phase 8 – Tool Integration (V0.9)

- [ ] AdminBot-Integration
- [ ] LabOS-Integration
- [ ] Tool-Call-Routing
- [ ] Plugin-System (basic)
- [ ] Tool → UI-Feedback

---

## Phase 9 – Intelligence Expansion (V0.95)

- [ ] Multi-Agent-Orchestrierung
- [ ] Long-Term-Memory
- [ ] Context-Persistence
- [ ] adaptives Verhalten
- [ ] Feedback-Loops
- [ ] Trace- / Replay-Integration

---

## Phase 10 – Production (V1.0)

- [ ] Performance-Optimierung
- [ ] Packaging
- [ ] Installer
- [ ] Autostart-Integration
- [ ] Crash-Handling
- [ ] Logging / Diagnostics
- [ ] Config-UX
- [ ] Cross-Platform-Support

---

## Architekturprinzipien

Diese Prinzipien gelten über alle Phasen hinweg. Sie sind nicht Wunsch,
sondern Merge-Kriterium.

- **Core-driven.** Der Rust-Core ist die einzige Quelle der Wahrheit für
  Zustand, Entscheidungen und Orchestrierung. UI und Adapter reagieren.
- **UI ohne Geschäftslogik.** Die Godot-UI rendert Events und sendet
  Eingaben. Sie trifft keine Entscheidungen, hält keine Session-Wahrheit,
  kennt ABrain nicht direkt.
- **ABrain als Cognition-Schicht.** ABrain ist das Entscheidungssystem,
  nicht das UI-System und nicht der Orchestrator. Austauschbar hinter
  einer schmalen Adaptergrenze.
- **Adapter statt Parallel-Stacks.** Kein zweiter IPC-Stack, keine zweite
  Runtime, keine zweite Audiopipeline. Neue Transporte oder Engines
  kommen als Adapter hinter bestehenden Handlern.
- **Leichtgewichtig.** Keine schweren Abhängigkeiten ohne klaren Nutzen.
  Der Idle-Footprint muss vertretbar bleiben.
- **Additiv erweitern.** Protokolle und APIs wachsen über neue Felder
  und neue `type`-Werte, nicht über Breaking Changes.
- **Asynchron und nicht-blockierend.** Langsame Adapter (STT, TTS,
  ABrain) dürfen den Event-Loop nicht blockieren.
- **Graceful failure vor harten Dependencies.** Fehlt ein Adapter,
  meldet der Core das als Zustand; er stürzt nicht ab.
- **Inkrementelle Multimodalität.** Text zuerst, dann Audio, dann Vision
  / Sensorik — jeweils erst, wenn die Schicht darunter stabil ist.

---

## Aktueller Fokus

→ **Phase 3.3** – Fenster-Präsenz (randloses Fenster, transparenter
Hintergrund, Click-through togglebar). Avatar-MVP aus 3.2 steht; echte
Charakteranimation und Speech-Sync bleiben offene Folgearbeiten.
