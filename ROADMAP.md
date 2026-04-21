# Smolit AI Assistant – Developer ROADMAP

## Vision

Ein leichtgewichtiger, persistenter KI-Assistent mit eigener Präsenz auf dem
Desktop:

- **Rust Core** — Runtime, Orchestrierung, Adapter.
- **Godot UI** — Avatar, Interaktion, Rendering.
- **ABrain** — Reasoning, Lernen.

Siehe [docs/VISION.md](./docs/VISION.md) für die Produktperspektive,
[docs/ui_architecture.md](./docs/ui_architecture.md) /
[docs/api.md](./docs/api.md) für die technische Detailebene,
[docs/presence_desktop_interaction.md](./docs/presence_desktop_interaction.md)
für das Presence- und Desktop-Interaction-Modell (Avatar-Präsenz,
Automation-Schicht, Modusachsen, Sicherheits- und Performancegrenzen)
und
[docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md)
für die Linux-spezifische Fenster-/Overlay-Architektur (Wayland/X11,
Compositor-Abhängigkeiten, Capability-Matrix, Window-Behavior-
Abstraktion).

---

## Stack

- Core: Rust (tokio, tokio-tungstenite, tracing).
- UI: Godot 4.x (GDScript, WebSocketPeer).
- IPC: WebSocket (lokal, `127.0.0.1:8787`).
- ABrain: heute CLI-Adapter, Ziel natives API.
- Audio: externe STT/TTS-Commands (pluggable).

---

## Ist-Zustand (Stand Phase 3.3 MVP)

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
  State-Mapping `idle` / `thinking` / `talking` / `acting`
  (+ `disconnected` / `error`), deterministischem Rückfall auf `idle`
  und Platzhalter-Rendering (ColorRect-Body, Gesicht, Mouth-Tween,
  Thinking-Indicator).
- Presence-MVP (`ui/scripts/presence/`) mit Modi
  `docked` / `expanded` / `action` / `disconnected`, manuellem Toggle,
  automatischem Wechsel bei Action Events und Action-Banner mit
  symbolischem Target-Text. Orthogonal zum Avatar-State geführt.

Was noch **nicht** existiert: echte Charakteranimation, Always-on-top /
transparenter Hintergrund, Emotion-Mapping, Personality, natives
ABrain-API, Multimodalität, Tool-Orchestrierung.

Zusätzlich im Core: **Action Event Model v1** (siehe
[docs/api.md](./docs/api.md), §2.5; `core/src/actions/`). Der Core
emittiert standardisierte Action Events (`action_planned`,
`action_started`, `action_step`, `action_completed`, `action_failed`)
parallel zu den bestehenden `thinking`/`response`/`heard`/`error`-
Nachrichten. Dieses Modell ist die gemeinsame Grundlage für spätere
Avatar-Synchronisierung, Logs/Replay und die Desktop-Interaction-
Linie.

Ebenfalls im Core: **Desktop Interaction Layer MVP**
(`core/src/interaction/`, siehe [docs/api.md](./docs/api.md) §2.6 und
[docs/presence_desktop_interaction.md](./docs/presence_desktop_interaction.md)
§14b). Der Layer modelliert Interaction-Aktionen
(`InteractionAction` / `InteractionKind` / `InteractionPayload`),
exekutiert über ein `InteractionBackend`-Trait (MVP: `CommandBackend`
mit `open_application`), kennt Verifikation (`VerificationResult`,
Confidence `verified`/`uncertain`/`failed`) und klassifiziert
Fehler über `RecoveryHint` (`retry` / `abort` / `ask_user` /
`fallback_unavailable`). Integration verläuft ausschließlich über
Action Events; das Protokoll kennt zusätzlich
`interaction_open_application` als eingehende Nachricht. `type_text`
und `send_shortcut` sind als Hooks modelliert, liefern aber
`BackendUnsupported`.

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
- [x] **Action Event Model v1** (`core/src/actions/`,
      `action_planned` / `action_started` / `action_step` /
      `action_completed` / `action_failed` additiv in
      `submit_text` / `voice_once` / `speak_text`)

### Offen (Phase 2)

- [ ] Server-seitige Reconnect-/Keepalive-Politik ausbauen
- [ ] Event-Erweiterungen (TTS-Start/-Ende)
- [ ] Streaming-Support
- [ ] aktive Emission von `action_progress` / `action_verification` /
      `action_cancelled` (Typen sind bereits vorgesehen)
- [ ] strukturierte Targets (derzeit emittieren alle Flows
      `target: unknown`)

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
- [x] Avatar-State-Mapping auf Action Events (neuer `acting`-State,
      `action_started` / `action_step` / `action_completed` /
      `action_failed` / `action_cancelled` respektieren bestehende
      `thinking` / `talking`-Zustände)

### Subeinheit 3.3 – Presence & Overlay MVP ✅

- [x] Presence-State-Modell (`ui/scripts/presence/presence_state.gd`)
      mit den Modi `docked` / `expanded` / `action` / `disconnected`
- [x] Presence-Controller (`ui/scripts/presence/presence_controller.gd`)
      als EventBus-Konsument; Hold-Timer für Completed/Failed/Cancelled,
      automatischer Übergang in den Action-Modus bei `action_started` /
      `action_step`
- [x] Main-Layout mit Header (Status + Presence-Label + Toggle),
      Action-Banner (Titel / Step / symbolisches Target / Status) und
      docked/expanded-Umschaltung von Log und Eingabezeile
- [x] Separation Presence-State (UI-Umfang) vs. Avatar-State
      (visueller Ausdruck) — zwei unabhängige Achsen
- [x] Symbolisches Target-Mapping (`→ Anwendung` / `→ Fenstertitel` /
      `→ Label (Rolle)` / `→ Region`) — keine Pixelgeometrie

### Offen (Phase 3.3)

- [ ] Randloses, always-on-top Fenster (native) — unter Wayland
      (GNOME/Mutter) **nicht** über Standard-Toplevel-Hints machbar,
      siehe
      [docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md)
      §C.1 / §D
- [ ] Transparenter Hintergrund / echter Desktop-Overlay — unter beiden
      Protokollen realistisch, Compositor-Edge-Cases beachten
- [ ] Click-through-Modus (togglebar) — X11 via XShape, Wayland via
      `wl_surface.set_input_region`, siehe
      [docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md)
      §C.3
- [ ] Snap-to-Edge, Screen-Positionierung, Multi-Monitor-Heuristik —
      unter Wayland nicht client-seitig; frühestens in Phase C der
      Overlay-Strategie
- [ ] Visual Action Modes (minimal feedback / guided / theatrical) als
      Benutzerpräferenz
- [ ] Kill-Switch / Stop-Aktion im Banner (setzt Core-seitige
      Cancel-API voraus)

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

Ziel: Umsetzung des Presence-Modells aus
[docs/presence_desktop_interaction.md](./docs/presence_desktop_interaction.md),
§5–§7 (Presence Modes, Docked/Expanded/Action Mode, Visual Action
Modes). Noch **nicht** implementiert.

- [ ] Presence Modes konfigurierbar (Off / Icon only / Light avatar /
      Full avatar)
- [ ] Zustände Docked / Expanded / Action Mode im Overlay
- [ ] Visual Action Modes (none / minimal feedback / guided movement /
      full theatrical)
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

## Phase 3b – Linux Window & Overlay Architecture (parallele Linie)

Plattformgrundlage für spätere Overlay-Arbeit. Bewusst **keine
Implementierung in diesem Schritt**, sondern Architektur- und
Forschungslinie. Vollständige Grundlage in
[docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md).

Ziel-Session: Ubuntu 24.04 / Wayland (GNOME/Mutter), X11 als
dokumentierter Fallback.

- [x] Architekturdokument Linux Window & Overlay
      ([docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md))
      mit Wayland/X11-Trennung, Capability-Matrix und Phasen A/B/C.
- [ ] Forschungsspikes zu Wayland-Constraints unter GNOME 46/47
      (Transparenz, Input-Region, HiDPI, Fractional Scaling,
      Nvidia/XWayland-Edge-Cases).
- [ ] Entscheidungsspike „always-on-top unter GNOME": Extension vs.
      Verzicht vs. compositor-spezifischer Pfad.
- [ ] Entscheidungsspike „Godot-Fenster-Flags vs. GDExtension vs.
      Host-Prozess mit eingebettetem Godot".
- [ ] Window-Behavior-Abstraktion als eigene Schicht
      (`window_behavior/`) entwerfen — Trait/Interface mit
      `set_always_on_top`, `set_transparent`, `set_click_through`,
      `request_position`, `current_capabilities`.
- [ ] Backends als getrennte Familie einordnen: `backend_x11`,
      `backend_wayland_mutter`, `backend_wayland_wlroots`,
      `backend_noop` (first-class Fallback).
- [ ] Overlay-MVP Phase B (opt-in): transparent + click-through +
      interaktive Zone — **ohne** Always-on-top-Zusicherung unter
      GNOME/Wayland.
- [ ] Compositor-spezifische Pfade (wlroots layer-shell,
      optional GNOME-Extension) erst in Phase C, falls
      Nutzungsnachfrage da ist.
- [ ] XDG-Portal-Strategie festlegen (Screenshot, Screen-Cast,
      GlobalShortcuts, OpenURI) für spätere Desktop-Interaktion.

---

## Phase 8b – Desktop Interaction Layer (parallele Linie)

Architektonisch eigene, von der UI entkoppelte Schicht gemäß
[docs/presence_desktop_interaction.md](./docs/presence_desktop_interaction.md),
§3, §4 und §10. Diese Phase ist bewusst **parallel** zu den
UI-Phasen geführt und noch **nicht** begonnen.

- [ ] Desktop Interaction Layer als eigene Adapterfamilie (nicht in
      Godot)
- [ ] Interaction Fidelity Modes (native-first / hybrid /
      pixel-guided / experimental)
- [ ] Interaction Stack v1: App Discovery → UI Targeting → Action
      Execution → Verification → Recovery
- [ ] Standardaktionen `open` / `focus` / `click` / `type` /
      `shortcut` / `scroll`
- [ ] Verifikations- und Recovery-Schicht
- [ ] Desktop Automation Modes (none / assist only / confirm before
      action / allowed trusted actions only)
- [ ] Trust-Modell für Anwendungen und Fenster
- [ ] Approval / Confirmation Flow zwischen Core und UI (Banner,
      `approval_requested` / `approval_response` / `approval_resolved`)
- [ ] `focus_window` Interaction-Spike mit Policy-Gate und Template-
      gesteuertem MVP-Backend
- [ ] Kill switch / Stop-Mechanik
- [ ] Action-/Verification-/Failure-Events additiv in
      [docs/api.md](./docs/api.md) (Basis steht seit Action Event
      Model v1; offen sind aktive Emission und strukturierte Targets
      aus der Automation-Schicht)
- [ ] Avatar-Zustände für Interaktionsphasen (`targeting`,
      `executing`, `verifying`, `recovered`, `aborted`)
- [ ] Linux-Backends: Accessibility (AT-SPI / D-Bus), Umgang mit
      Wayland vs. X11
- [ ] OCR-/Template-Erkennung und Pixel-Fallback mit Safe Sandboxing
- [ ] Performance Profiles (low / balanced / high fidelity)
      konfigurierbar und mit Presence/Visual Action gekoppelt

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

→ **Phase 3.3 Presence MVP** steht: Presence-State, Action-Banner und
docked/expanded-Umschaltung laufen auf Basis der Action Events. Nächste
Schritte sind das echte Desktop-Overlay (randloses, transparentes,
optional click-through-fähiges Fenster) auf Basis der neuen Linux-
Window-/Overlay-Architektur (Phase 3b, siehe
[docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md))
und die strukturierten Targets aus einer Desktop-Interaction-Schicht
(Phase 8b). Avatar-seitig bleiben echte Charakteranimation und
Speech-Sync offene Folgearbeiten.

Zusätzlich begonnen: **Phase 3b Linux Window & Overlay Architecture**
als parallele Architekturlinie. Das Dokument legt Wayland/X11-Trennung,
Capability-Matrix und eine noch nicht implementierte Window-Behavior-
Abstraktion fest — bewusst ohne Codeänderungen.
