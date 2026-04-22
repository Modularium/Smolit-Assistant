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
`interaction_open_application` als eingehende Nachricht. `type_text`,
`send_shortcut` und `focus_window` sind als Hooks modelliert, liefern
aber `BackendUnsupported`.

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
- [x] Angereichertes Target-/Mapping-Rendering im Action-Banner:
      Kind-Chip (`[application]` / `[window]` / `[ui_element]` /
      `[region]` / `[unknown]`), Primärname + Sekundärdetail,
      Mapping-Zeile mit `space`, `hint` und optionalem Fensterbezug;
      stille Fallbacks, wenn Target- oder Mapping-Felder fehlen
- [x] Symbolische Avatar-Tint-Variante je Target-Kind im ACTING-State
      (rein farblich, keine Bewegung, keine Koordinaten)
- [x] Compact Input UX am Icon (Docked-Presence): Klick auf den Avatar
      öffnet ein leichtes Eingabepanel mit Text/Send, Voice, Add-Files-
      Hook (Placeholder), Mini-Commands-Hilfe und Close/Escape. Nutzt
      denselben `submit_text`- / `voice_once`-Pfad wie die Expanded-
      Eingabe und schließt kontrolliert beim Wechsel nach Expanded/
      Disconnected. Siehe
      [docs/ui_architecture.md §8.3](./docs/ui_architecture.md).

### Offen (Phase 3.3)

- [ ] Randloses, always-on-top Fenster (native) — randlos ist mit dem
      opt-in Overlay-MVP (Phase B) bereits Teil der transparenten
      Presence-Schicht; Always-on-top bleibt unter Wayland
      (GNOME/Mutter) **nicht** über Standard-Toplevel-Hints machbar,
      siehe
      [docs/linux_window_overlay_architecture.md](./docs/linux_window_overlay_architecture.md)
      §C.1 / §D
- [~] Transparenter Hintergrund / echter Desktop-Overlay — opt-in über
      `SMOLIT_UI_OVERLAY=1` mit ehrlichem Fallback; siehe
      [docs/linux_window_overlay_architecture.md §F.2](./docs/linux_window_overlay_architecture.md)
- [ ] Click-through-Modus (togglebar) — X11 via XShape, Wayland via
      `wl_surface.set_input_region`, braucht zusätzlich definierte
      interaktive Zonen (Passthrough-Polygone), damit Avatar und Banner
      klickbar bleiben; siehe
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

- [x] **Micro-Animation / Personality Layer v1 (UI-only)** — subtile
      Idle-Breath, Thinking-Breath, Acting-Pulse, Talking-Pulse,
      Error-Startle; seltener Curious-Wiggle im Idle; ruhiger
      Disconnected-Zustand; sauber geschichtet auf drei orthogonalen
      Transform-Properties (Root-Scale / Body-Scale / Body-Rotation).
      Rein UI-seitig, keine neuen States, keine IPC-/Protokolländerung.
      Siehe
      [docs/ui_architecture.md §7](./docs/ui_architecture.md) „Phase B++".
- [ ] Feinere Animationszustände (`curious`, `focused`, `alert`, …)
- [ ] Emotion-Mapping Core → UI (setzt Protokollerweiterung um
      `emotion` voraus)
- [ ] Speech-Sync (TTS-Lebenszyklus-Events → Animation)
- [ ] Antwortabhängige Reaktionen
- [ ] erste echte Persönlichkeits-Cues über rein visuelle Mikro-Cues
      hinaus

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
- [x] **Window Behavior Capability Spike v1** — kleine
      `ui/scripts/window_behavior/`-Linie (Fassade + Capability-
      Detection + opt-in Runtime-Probe via `SMOLIT_WINDOW_PROBE=1`)
      für Transparenz und Click-through. Kein Always-on-top, keine
      Scene-Kopplung, keine IPC-Änderung. Siehe
      [docs/linux_window_overlay_architecture.md §F.1](./docs/linux_window_overlay_architecture.md)
      und
      [docs/ui_architecture.md §9.1](./docs/ui_architecture.md).
- [ ] Forschungsspikes zu Wayland-Constraints unter GNOME 46/47
      (Transparenz, Input-Region, HiDPI, Fractional Scaling,
      Nvidia/XWayland-Edge-Cases).
- [ ] Entscheidungsspike „always-on-top unter GNOME": Extension vs.
      Verzicht vs. compositor-spezifischer Pfad.
- [ ] Entscheidungsspike „Godot-Fenster-Flags vs. GDExtension vs.
      Host-Prozess mit eingebettetem Godot".
- [ ] Window-Behavior-Abstraktion als eigene Schicht
      (`window_behavior/`) vollständig ausbauen — Trait/Interface mit
      `set_always_on_top`, `set_transparent`, `set_click_through`,
      `request_position`, `current_capabilities` (Capability-Seite
      steht per Spike v1 bereits; Setter-/Backend-Seite offen).
- [ ] Backends als getrennte Familie einordnen: `backend_x11`,
      `backend_wayland_mutter`, `backend_wayland_wlroots`,
      `backend_noop` (first-class Fallback).
- [~] Overlay-MVP Phase B (opt-in): transparent + borderless
      Presence-Fenster per `SMOLIT_UI_OVERLAY=1`, capability-gesteuert
      mit ehrlichem Fallback; **ohne** Always-on-top-Zusicherung unter
      GNOME/Wayland und **ohne** produktives Click-through
      (interaktive Zonen / Passthrough-Polygone sind Folgearbeit).
      Siehe
      [docs/linux_window_overlay_architecture.md §F.2](./docs/linux_window_overlay_architecture.md)
      und
      [docs/ui_architecture.md §9.2](./docs/ui_architecture.md).
- [ ] Click-through mit definierten interaktiven Zonen
      (Avatar + Banner bleiben klickbar) als Folgeschritt auf Phase B —
      X11 via XShape/`WINDOW_FLAG_MOUSE_PASSTHROUGH` + Passthrough-
      Polygon, Wayland via `wl_surface.set_input_region` plus
      Input-Region pro interaktiver Zone.
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
- [x] Approval / Confirmation Flow MVP zwischen Core und UI (Banner,
      `approval_requested` / `approval_response` / `approval_resolved`,
      Timeout über `SMOLIT_APPROVAL_TIMEOUT_SECONDS`; siehe
      [docs/api.md §2.7](./docs/api.md))
- [x] `focus_window` Interaction-Spike: Policy-Gate
      (`SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW`), command-basiertes
      MVP-Backend mit Template (`SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`),
      Approval-Integration, ehrliches `uncertain` statt Pseudo-
      Verifikation, `BackendUnsupported` wenn kein Template (z. B.
      Wayland). IPC-Nachricht `interaction_focus_window` additiv.
- [ ] Confirmation- und Approval-UX für weitere Action Kinds
      (`type_text`, `send_shortcut`, Multi-Step-Flows, persistente
      Trust-Entscheidungen)
- [ ] Reicheres `focus_window`-Backend jenseits command-basiertem
      Spike (Portal / compositor-spezifische Pfade, Fokus-Probe zur
      `verified`-Hochstufung)
- [ ] Kill switch / Stop-Mechanik
- [ ] Action-/Verification-/Failure-Events additiv in
      [docs/api.md](./docs/api.md) (Basis steht seit Action Event
      Model v1; offen sind aktive Emission und strukturierte Targets
      aus der Automation-Schicht)
- [ ] Avatar-Zustände für Interaktionsphasen (`targeting`,
      `executing`, `verifying`, `recovered`, `aborted`)
- [x] Linux Accessibility Backend Spike (AT-SPI Capability Probe +
      read-only Discovery/Inspection-Schema): `AccessibilityProbe`
      (`uncertain` / `unavailable` / `failed` + Grund) aus Umgebungs-
      und Unix-Socket-Vorprüfung, Schema für `AccessibilityItem`,
      IPC-Nachrichten `interaction_probe_accessibility` /
      `interaction_discover_accessibility`, Action-Event-Integration
      mit zusätzlichen Envelopes `accessibility_probe_result` /
      `accessibility_discovery_result`, optionale
      `StatusPayload`-Felder `accessibility_probe` /
      `accessibility_probe_reason`. Bewusst dependency-frei; echter
      zbus-/`atspi-connection`-RPC-Probe, Registry-`GetChildren` und
      Namens-/Rollen-Lookup bleiben nächste Stufe. Siehe
      [docs/linux_interaction_backends_research.md](./docs/linux_interaction_backends_research.md)
      §2 und [docs/api.md §2.8](./docs/api.md).
- [x] Verified Target Discovery (Confidence-Modell + UI-Darstellung):
      `AccessibilityDiscovery::Ok { items }` neben `Uncertain` /
      `Unavailable` / `Failed`; pro Item `confidence` (`verified`
      reserviert für echten RPC-Pfad, `discovered` für ehrliche
      Hint-Echos), `source`, optional `matched_hint`, `detail`,
      `app_name`. `inspect_target(hint)` liefert Hint-Echo-Items in
      strukturierter Form; `discover_top_level()` bleibt ehrlich
      `Uncertain`. Godot-UI rendert das in einem neuen DiscoveryPanel
      (Status-Badge, Item-Liste mit Confidence-Badge) rein anzeigend.
      Siehe [docs/api.md §2.8](./docs/api.md) und
      [docs/ui_architecture.md §8.1](./docs/ui_architecture.md).
- [x] Target Selection + Approval-assisted Target Handoff:
      `SelectedTarget`-Referenzmodell (`id`, `name`, `role`, `source`,
      `confidence`, optional `matched_hint` / `app_name`) in
      `core/src/interaction/selection.rs`, IPC-Nachrichten
      `interaction_select_target` / `interaction_clear_target` →
      `target_selected` / `target_cleared`. Core hält genau einen Slot
      im Speicher (kein Store, keine Persistenz); `ApprovalRequest`
      trägt den Snapshot als `selected_target` und der Approval-Text
      bekommt den Zusatz „Ziel: name (role, confidence)". Godot-UI
      macht Discovery-Items klickbar („Select"/„Selected"), zeigt eine
      SelectedTargetRow mit Clear-Button und rendert das Ziel im
      Approval-Banner. Auswahl ≠ Berechtigung — der Approval-Flow
      bleibt unverändert. Siehe [docs/api.md §2.9](./docs/api.md) und
      [docs/ui_architecture.md §8.2](./docs/ui_architecture.md).
- [ ] Linux-Backends (Folgestufen): echter AT-SPI-RPC-Pfad (zbus /
      atspi-connection), Registry-Root-Discovery, Namens-/Rollen-
      basierte Inspection, Toolkit-Vergleich (GTK / Qt / Electron /
      Terminal), Umgang mit Wayland vs. X11 beim Fokus-/Write-Pfad
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

Für den Desktop Interaction Layer läuft jetzt ein konkreter
**Approval / Confirmation Flow MVP**: freigabepflichtige Aktionen
(aktuell `open_application`) werden vom Core nicht mehr stumm
abgelehnt, sondern über `approval_requested` / `approval_response` /
`approval_resolved` an die UI gespiegelt und bei Timeout sauber
`action_cancelled`. Details in [docs/api.md §2.7](./docs/api.md).

Zusätzlich ist der erste **Interaction-Backend-Spike für
`focus_window`** im Core gelandet: neuer IPC-Call
`interaction_focus_window`, Policy-Gate
`SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW` (konservativ off),
command-basiertes Backend mit Template
`SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`, vollständige Einbindung in
den Approval-Flow. Verifikation bleibt ehrlich `uncertain`; ohne
Template (typisch Wayland) meldet der Core
`BackendUnsupported("focus_window")` statt Pseudo-Erfolg.

Zusätzlich begonnen: **Phase 3b Linux Window & Overlay Architecture**
als parallele Architekturlinie. Das Dokument legt Wayland/X11-Trennung,
Capability-Matrix und eine noch nicht vollständig implementierte
Window-Behavior-Abstraktion fest. Als erster Codepunkt ist ein
**Window Behavior Capability Spike v1** gelandet:
`ui/scripts/window_behavior/` (Capability-Detection + opt-in
Transparenz-/Click-through-Probe via `SMOLIT_WINDOW_PROBE=1`, ohne
Always-on-top-Versprechen und ohne Scene-Kopplung). Details in
[docs/linux_window_overlay_architecture.md §F.1](./docs/linux_window_overlay_architecture.md).

Aufbauend darauf ist jetzt ein **Overlay-MVP Phase B** gelandet:
`ui/scripts/window_behavior/overlay_controller.gd` aktiviert opt-in
(via `SMOLIT_UI_OVERLAY=1`) einen transparenten, borderlosen
Presence-Modus — capability-gesteuert, mit ehrlichem Fallback auf das
normale Fenster, wenn die Transparenz im aktuellen Setup nicht
tragfähig ist. Click-through und Always-on-top werden bewusst **nicht**
versprochen (Folgearbeit bzw. compositor-abhängig). Presence- und
Avatar-Schicht bleiben unberührt. Details in
[docs/linux_window_overlay_architecture.md §F.2](./docs/linux_window_overlay_architecture.md)
und
[docs/ui_architecture.md §9.2](./docs/ui_architecture.md).

Ebenfalls gelandet: **Verified Target Discovery** (Phase 8b). Der
Accessibility-Spike unterscheidet jetzt explizit zwischen `ok`,
`uncertain`, `unavailable` und `failed` auf Payload-Ebene sowie
`verified` vs. `discovered` pro Item. `verified` bleibt reserviert
für den zukünftigen echten RPC-Pfad; `inspect_target(hint)` liefert
Hint-Echo-Items als `discovered`. Die Godot-UI rendert die Ergebnisse
in einem kleinen DiscoveryPanel — rein anzeigend, ohne Confidence
nachträglich hochzustufen. Details in
[docs/ui_architecture.md §8.1](./docs/ui_architecture.md) und
[docs/linux_interaction_backends_research.md §2.3](./docs/linux_interaction_backends_research.md).

Ebenfalls gelandet: **Target Selection + Approval-assisted Target
Handoff** (Phase 8b). UI kann Discovery-Items per „Select"-Button als
aktuellen Interaction-Kontext markieren; der Core hält genau einen
`SelectedTarget` im Speicher und antwortet mit `target_selected` /
`target_cleared`. Beim nächsten `approval_requested` trägt der Core das
Target im zusätzlichen `selected_target`-Feld und ergänzt den
Approval-Text um „Ziel: name (role, confidence)". Auswahl ist
ausdrücklich **keine** Berechtigung — jede Folgeaktion geht weiterhin
durch den bestehenden Approval-Flow, und die UI räumt die Auswahl bei
Clear-Klick oder `ipc_disconnected`. Details in
[docs/api.md §2.9](./docs/api.md) und
[docs/ui_architecture.md §8.2](./docs/ui_architecture.md).

Ebenfalls gelandet: **Linux Accessibility Backend Spike** (Phase 8b).
`AccessibilityProbe::detect()` liefert aus Session-Umgebung und
Unix-Socket-Vorprüfung ein getaggtes
`uncertain` / `unavailable` / `failed` mit Grund; die neuen
IPC-Nachrichten `interaction_probe_accessibility` und
`interaction_discover_accessibility` laufen über das Action Event
Model und emittieren zusätzliche `accessibility_probe_result`- bzw.
`accessibility_discovery_result`-Envelopes. `AccessibilityItem` ist
als Schema vorbereitet, aber die Discovery-Füllung fehlt bewusst —
die echte RPC-Stufe (zbus / `atspi-connection`, Registry-
`GetChildren`, Namens-Lookup) ist die nächste Ausbaustufe. Details in
[docs/linux_interaction_backends_research.md](./docs/linux_interaction_backends_research.md)
und [docs/api.md §2.8](./docs/api.md).
