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

**Workflow-Overlay / Visual Action Flow (MVP-Spike, Ist-Zustand).**
Ein erster kleiner MVP-Spike ist eingebaut. Unter
`ui/scripts/workflow_overlay/` liegen die vier Scripts (State,
Controller, Node-View, Edge-View), unter
`ui/scenes/workflow_overlay/` die Szene
`workflow_overlay_root.tscn`. Der Overlay ist in `main.tscn`
unterhalb des Avatars eingebettet (x=18..346, y=162..210,
z_index=40) und konsumiert ausschließlich die bestehenden Action
Events (`action_planned` / `action_started` / `action_step` /
`action_completed` / `action_failed`) über den `EventBus`. Er ist
read-only, sendet keine neuen IPC-Nachrichten, ist mouse-pass-through
(fängt keine Klicks), versteckt sich standardmäßig und zeigt sich
erst, wenn ein Flow läuft. Drei feste Rollen (Trigger → Action →
Result) — **kein** Workflow-Builder, **kein** Desktop-Executor,
**keine** zweite Wahrheit neben dem Core. Details: siehe
Subeinheit 3.4 unten sowie
[docs/ui_architecture.md §6a/§8a](./docs/ui_architecture.md) und
[docs/api.md „UI-Projektion: Workflow Overlay"](./docs/api.md).

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

- [~] Echte Sprite-/Charakteranimation statt Platzhalter — Phase 3.2
      Render-Polish gelandet: geteilter prozeduraler **Rim-Accent-Ring**
      an der Silhouette (`ui/scripts/avatar/avatar_rim_accent.gd`,
      `$AvatarRoot/RimAccent`), der Smolit und die drei kuratierten
      Alternativen identitätsneutral mit state-farbigem Silhouetten-
      Akzent versorgt (`IDLE` / `THINKING` / `TALKING` / `ACTING` /
      `DISCONNECTED` / `ERROR`); dazu kleiner prozeduraler Polish in
      `avatar_identity_visual.gd` für Robot (Face-Plate + Pupillen +
      Antennen-Stalk), Humanoid (Wangen + Pupillen-Highlights +
      Kinn-Schatten) und Orb (vierstufiger Halo-Verlauf +
      Sekundär-Highlight). Smolit-`TEXTURE`-Pfad unverändert; Rim
      profitiert auch den Default. Rein prozedural, keine Asset-
      Imports, keine neue State-Maschine, kein Capability-Contract-
      Eingriff. Verifiziert durch 19-Assertions-Smoke
      `scripts/avatar_render_polish_smoke.gd` (Harness-Case
      `avatar-render-polish-smoke`). **Restschuld:** echte
      Sprite-/Charakteranimation im Sinn einer animierten Figur
      (z. B. Blink, Idle-Breath auf Asset-Ebene, Acting-Geste) ist
      weiterhin offen und nicht Teil dieses Schritts. Details in
      [docs/ui_architecture.md §7 „Phase B Render Polish"](./docs/ui_architecture.md).
- [x] Speech-Bubble für `response` und `heard` — kleiner Utterance-MVP
      (`ui/scripts/utterance/`, `ui/scenes/utterance/utterance_bubble.tscn`)
      neben dem Avatar. Rein rendernd, EventBus-getrieben
      (`heard_received` / `response_received` / `ipc_disconnected`),
      genau ein aktiver Slot (kein Konversationsverlauf, kein
      Transcript), deterministisches Text-Shaping (strip + Ellipsis bei
      `MAX_CHARS = 240`), Kill-and-replace-Timer/-Tween. Keine IPC-
      /Protokolländerung, kein TTS-Sync, keine Interaktion, keine
      Stage-C-/Appearance-Kopplung. Verifiziert durch 52-Assertions-
      Smoke `scripts/utterance_bubble_smoke.gd` (Harness-Case
      `utterance-bubble-smoke`). Details in
      [docs/ui_architecture.md §8.4](./docs/ui_architecture.md).
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
- [~] Visual Action Modes (minimal feedback / guided / theatrical) als
      Benutzerpräferenz — Phase-3.3-MVP gelandet: UI-Staging-Achse
      mit vier Modi (`none` / `minimal_feedback` / `guided_movement` /
      `full_theatrical`), die rein innerhalb der Presence-Hülle das
      Action-Banner und das Workflow-Overlay gaten und in der Deckkraft
      modulieren. Realisiert in `ui/scripts/presence/visual_action_mode.gd`
      und `ui/scripts/presence/visual_action_preferences.gd`; Integration
      im `main.gd` (Resolver `Env > Preferences > Default`, Staging-Push
      auf Banner + Overlay) und in der env-gated Dev-Steuerung
      (`SMOLIT_UI_DEV_CONTROLS=1`, Vier-Stufen-Picker + „Save as
      default"). Env-Flag `SMOLIT_UI_VISUAL_ACTION_MODE` (kanonische
      Namen plus Aliasse `off` / `min` / `guide` / `demo`). Persistenz
      in `user://smolit_ui.cfg` Sektion `[presence]`. Verifiziert durch
      41-Assertions-Smoke `scripts/visual_action_mode_smoke.gd`
      (Harness-Case `visual-action-mode-smoke`). Default bleibt
      `minimal_feedback` — reproduziert den bisherigen Ist-Stand.
      **Restschuld (bewusst):** Die Endausprägung aus
      [docs/presence_desktop_interaction.md §7.3 / §7.4](./docs/presence_desktop_interaction.md)
      — Avatar zeigt Zielobjekt, Bewegungspfad, Gestik über Fremd-
      fenster — ist **nicht** implementiert und bleibt offen. Der
      heutige Schritt benennt die vier Produktstufen ehrlich, liefert
      aber nur eine In-Place-Intensitätsachse; keine Pixel-Geometrie,
      keine Desktop-Automation, keine Core-/IPC-Änderung. Details in
      [docs/ui_architecture.md §8.5](./docs/ui_architecture.md) und
      [docs/presence_desktop_interaction.md §7.5](./docs/presence_desktop_interaction.md).
- [ ] Kill-Switch / Stop-Aktion im Banner (setzt Core-seitige
      Cancel-API voraus)

### Subeinheit 3.4 – Workflow Overlay / Visual Action Flow (MVP-Spike, PR 2)

MVP-Spike aus PR 1 bleibt die Basis (drei feste Knoten Trigger →
Action → Result, zwei Kanten, read-only, core-driven, keine neue
IPC, kein Builder). PR 2 schärft die bestehende Kurzprojektion
nach, ohne den Scope zu vergrößern:

- **Zweistufige Darstellung.** Automatischer Wechsel zwischen
  `COLLAPSED` (bei `PLANNED`) und `EXPANDED` (bei `ACTIVE` /
  Terminal). Keine Interaktion, kein Nutzerschalter, keine zweite
  Presence-State-Maschine — der Modus ist eine reine Funktion der
  aktuellen Phase.
- **Bessere Node-Semantik.** Klare Fallback-Ketten pro Rolle (
  `trigger_label_from_payload`, `action_label_from_payload`,
  `step_label_from_payload`, `result_label_from_payload`,
  `cancel_label_from_payload`) als pure Helper in
  `workflow_overlay_state.gd`. Leere Labels zeigen den
  Rollennamen + einen neutralen Default („Start", „Working…",
  „Done") statt leerer Kapseln.
- **Robustere Event-Rekonstruktion.** Step-Counter liefert einen
  optionalen Hint („Step 3") im EXPANDED-Modus; leere
  `action_step`-Payloads überschreiben bestehende Labels nicht
  mehr; ein `action_step` vor `action_planned` promotet den Flow
  still auf `ACTIVE`.
- **Ruhigerer visueller Rhythmus.** Kantenpuls von 1.1 s → 1.45 s,
  Linien- und Padding-Werte zwischen den Modi differenziert,
  leisere Aktivitätsfarbe.
- **Harness-Integration.** Neuer Case `workflow-state-smoke` in
  `scripts/run_overlay_verification.sh` läuft
  `scripts/workflow_overlay_state_smoke.gd` (47 Assertions, alle
  PASS) — deckt Label-Ketten, Phase→DisplayMode, Step-Hint ab.

Was bewusst **nicht** Teil von PR 2 ist:

- kein Workflow-Builder, kein Editor, kein freier Canvas;
- keine action_id-Queue, kein History-System, keine Persistenz;
- keine neuen Event-Typen, keine Protokolländerung, keine neue
  IPC-Nachricht;
- kein Nutzer-Toggle zwischen Collapsed und Expanded;
- keine Änderung an Window-Behavior, Avatar, Presence, Banner,
  Discovery-Panel, Compact-Input.

**PR 4 (Dev-Steuerung).** Zusätzlich zur produktiven Workflow-
Overlay-Logik gibt es jetzt einen kleinen, opt-in Dev-Hook
`workflow_overlay_controller.preview_phase(name)` — siehe
`docs/ui_architecture.md` §8c. Der Hook setzt den internen Flow-
Zustand direkt auf eine der bekannten Phasen, ohne EventBus-
Injection, ohne Action-Event-Erzeugung, und wird nur aus dem
env-gategten Dev-Panel (`SMOLIT_UI_DEV_CONTROLS=1`) aufgerufen.
Read-only-Charakter des Overlays bleibt erhalten.

**1. Kurzbeschreibung.** Ein transparentes, leichtgewichtiges
visuelles Flow-Overlay, das links vom Avatar/Icon bzw. als linker
Flügel innerhalb derselben Presence-Hülle erscheint. Es zeigt auf
Basis der Action Events einen verständlichen Handlungsfluss
(Trigger / Schritte / Aktion / Ergebnis). **Read-only**, kein
Editor, kein Executor, kein zweites Logiksystem.

**2. MVP-Scope.**

- kleine node-basierte Darstellung, Standardfall 2–4 Knoten;
- gerichtete Kanten mit dezenten Aktivitätsanimationen;
- semantische Zustände pro Knoten/Kante: `geplant` / `aktiv` /
  `erfolgreich` / `fehlgeschlagen` / `abgebrochen` / `unklar`;
- **kein** Zoom, **kein** Pan, **kein** Drag, **keine** freie
  Verkabelung, **kein** unendlicher Canvas.

**3. Event-Bindung.** Das Overlay konsumiert ausschließlich
Action Events aus dem Core — es erzeugt keine eigenen Zustände.
Im MVP bevorzugt genutzt:

- `action_planned`
- `action_started`
- `action_step`
- `action_completed`
- `action_failed`

Spätere Eventtypen (`action_verification`, `action_cancelled` o. ä.)
können **additiv** hinzukommen, sollen aber nicht als heutiger
Ist-Zustand dargestellt werden. Details zur Projektion in
[docs/api.md „UI-Projektion: Workflow Overlay"](./docs/api.md).

**4. Nicht-Ziele.**

- kein n8n-Ersatz, kein Workflow-Authoring, kein Graph-Editor;
- keine Desktop-Automation in Godot;
- keine zweite Session- oder Execution-Logik in der UI;
- keine Protokollhoheit — die Wahrheit bleibt im Core;
- Smolit wird dadurch **kein** visueller Workflow-Builder.

**5. Offene Punkte.**

- Layout-Strategie (feste Spur vs. adaptiv, vertikal vs. radial);
- Node-Semantik / Symbolik (Trigger / Step / Action / Result);
- Collapse/Expand-Verhalten bei längeren Abläufen;
- spätere Visualisierungsstufen (Inspect, History-Rewind) sind
  explizit **nicht** MVP-Teil, aber architektonisch nicht
  ausgeschlossen.

Dieses Overlay erweitert die Presence-Linie, hält aber die Trennung
zwischen sichtbarer Darstellung und technischer Ausführung strikt
aufrecht — die Desktop-Ausführung bleibt ausschließlich im Core /
Desktop Interaction Layer, die UI projiziert nur.

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

## Phase 4b – Avatar Appearance & Personalization (parallele Linie; Stufen A und B Ist, Stufe C research-/security-gated)

Parallele Linie zu Phase 4 (Behavioral Layer). Diese Phase beschreibt
die Erweiterung der bestehenden Avatar-/Presence-Linie um ein
strukturiertes **Appearance-System**. Sie ist **rein visuell /
darstellerisch**, beeinflusst weder Core-Logik noch ABrain noch
Sicherheits-/Permission-Modelle.

**Status.** Stufe A ist als MVP-Spike implementiert (nur
Smolit-Salamander, vier markentreue Themes, drei UI-Behavior-
Profiles, kleine Appearance-Overrides, Env-gesteuerte Opt-in-
Konfiguration). Stufe B ist gelandet und gehärtet (drei zusätzliche
prozedurale Identities neben Smolit und ein Template-Capability-
Contract; Details siehe §4b.5 unten). Stufe C ist ausdrücklich
**nicht begonnen**; sie ist in diesem Zyklus ein dokumentierter
Forschungs-/Designraum mit eigenen Nicht-Zielen, Sicherheitsmodell
und Exit-Kriterien —
[`docs/avatar_stage_c_research.md`](./docs/avatar_stage_c_research.md).
Der Default-Avatar (Smolit Salamander) bleibt unverändert und
erster-Klasse.

**Bindende Abgrenzungen:**

- Appearance ≠ Behavior ≠ Personality ≠ Policy.
- Avatar-Auswahl beeinflusst **nicht**: Action-Execution, Permissions,
  ABrain-Entscheidungen, Systemverhalten.
- Personalisierung ist **additiv, nicht ersetzend** — der Default
  Smolit Salamander bleibt erster-Klasse und ist kein austauschbares
  Theme unter gleichberechtigten Themes.
- Kein Vermischen von Avatar-Look, Assistant-Personality und
  Automation-Policy.
- UI bleibt reiner Renderer; Rust Core bleibt Source of Truth.

### 4b.1 Avatar Identity

Figurentyp — beschreibt **ausschließlich die visuelle Figur**, nicht
Verhalten oder Logik:

- **Salamander** (Default, Smolit)
- Roboter
- Mensch (Kopf / Figur)
- Tiere
- abstrakte Formen (z. B. Orb, Nebel)

Ein Wechsel der Identity darf die Liste der unterstützten Presence-
/Avatar-States nicht implizit ändern; fehlende States fallen auf
einen neutralen Zustand zurück, ohne die UI zu brechen.

### 4b.2 Avatar Themes / Styles

Mehrere visuelle Varianten **pro Figur**. Themes verändern Stil,
nicht Funktion. Beispiele:

- `default`
- `tech`
- `soft`
- `neon`
- `minimal`

Themes sind reine Rendering-Presets; sie dürfen keine Zustands-
Maschine modifizieren und keine neuen Presence-Modi erzeugen.

### 4b.3 Appearance Overrides

Nutzerspezifische, rein visuelle Anpassungen oberhalb von Identity
und Theme:

- Farben
- Glow
- Outline
- Größe
- visuelle Intensität

Overrides sind additiv zum Theme und persistieren als reine
UI-Präferenz. Im Ist-Zustand landet das in einer sehr kleinen
lokalen ConfigFile (`user://smolit_ui.cfg`, Sektion
`[avatar_appearance]`); siehe
[`docs/ui_architecture.md` §8b.7](./docs/ui_architecture.md). Eine
größere Persistenz-/Nutzerprofil-Architektur ist in dieser Phase
bewusst *nicht* Teil des Scopes.

### 4b.4 Behavior Profiles (UI-Ebene)

„Behavior Profile" in diesem Abschnitt meint ausschließlich den
*visuellen Ausdruck*, nicht Assistant-Verhalten:

- ruhig
- aktiv
- verspielt
- zurückhaltend

Sie modulieren Animationsintensität, Idle-Cues und Übergangsstil —
**kein** Einfluss auf Core-Entscheidungen, kein Einfluss auf die
Avatar-State-Maschine, kein Einfluss auf Action-Events oder deren
Verarbeitung.

### 4b.5 Stufenmodell

Die Personalisierung wird in drei klar getrennten Stufen ausgebaut.
Stufe A ist implementiert; B und C bleiben Ziel-Zustand.

- **Stufe A — Brand-safe Personalisierung (Ist, MVP-Spike).** Nur
  Smolit-Varianten, Themes + Behavior Profiles + Appearance
  Overrides. Realisiert in
  `ui/scripts/avatar/avatar_appearance.gd`; Integration im
  bestehenden `avatar_controller.gd`; Steuerung via drei opt-in
  Env-Variablen (`SMOLIT_AVATAR_THEME` / `SMOLIT_AVATAR_PROFILE` /
  `SMOLIT_AVATAR_INTENSITY`) und zusätzlich über die kleine
  env-gated Dev-Steuerung
  (`SMOLIT_UI_DEV_CONTROLS=1`, Theme/Profile/Intensity live in der
  UI schaltbar; siehe
  [`docs/ui_architecture.md` §8c](./docs/ui_architecture.md)).
  Seit diesem PR zusätzlich eine **kleine lokale UI-Persistenz**
  (`ui/scripts/avatar/avatar_preferences.gd`, Datei
  `user://smolit_ui.cfg`, Sektion `[avatar_appearance]`) — die
  Dev-Steuerung bekommt einen `Save as default`-Button,
  ausdrücklich **kein** Auto-Save, **kein** Settings-System, **kein**
  Nutzerprofil. Prioritätsreihenfolge beim Laden ist feldweise und
  bindend: `Env > gespeicherte Preferences > harte Defaults`. Ohne
  Env und ohne Preferences-Datei bleibt das Startverhalten byte-
  identisch zum vor-PR-Stand (alle 8 Harness-Cases diff-sauber).
  Identitätsgarantie (DEFAULT + CALM + Unity-Overrides == vor-PR-
  Verhalten) durch den Smoketest
  `scripts/avatar_appearance_smoke.gd` belegt (32 Assertions
  PASS; Harness-Case `avatar-appearance-smoke`). Zusätzlich
  deckt `scripts/dev_controls_smoke.gd` die Übersetzungslogik
  zwischen Panel und Controllern ab (15 Assertions PASS;
  Harness-Case `dev-controls-smoke`), und der neue
  `scripts/avatar_preferences_smoke.gd` prüft Load/Save/Fallback-
  Reihenfolge, invalide Einträge, partielle Dateien und Intensity-
  Clamping (22 Assertions PASS; Harness-Case
  `avatar-preferences-smoke`). Details siehe
  [`docs/ui_architecture.md` §8b.7](./docs/ui_architecture.md).
- **Stufe B — Kuratierte Templates (Ist, gehärtet mit Capability-Contract).**
  Drei zusätzliche Identity-IDs neben Smolit: `robot_head`,
  `humanoid_head` und `orb`, rein prozedural gezeichnet (keine
  Binärassets, keine Import-Pipeline). Gleiche Eingabepfade wie
  Phase A (`SMOLIT_AVATAR_IDENTITY` Env, gespeicherte
  UI-Preferences, harter Default = Smolit). Unbekannte Werte fallen
  in allen Schichten still auf Smolit zurück — nie auf eine der
  Alternativen. Realisiert in `ui/scripts/avatar/avatar_identity.gd`
  (Katalog), `ui/scripts/avatar/avatar_identity_visual.gd`
  (prozeduraler `_draw`) und seit dem Hardening-PR zusätzlich
  `ui/scripts/avatar/avatar_template_capabilities.gd` (Capability-
  Contract). Jedes Template deklariert jetzt explizit: welche
  Avatar-States es trägt (inkl. optionalem `state_fallback`, z. B.
  `orb.TALKING → ACTING`, weil Orb keinen Mund hat), und wie stark
  es die fünf Ausdrucks-Achsen (Theme-Tint, Behavior-Profile,
  State-Pulse, Wiggle, Error-Startle) umsetzt
  (`NONE` / `REDUCED` / `FULL`). Der Avatar-Controller fragt dieses
  Modul statt auf Identity-IDs zu verzweigen. Dev-Panel bekommt vier
  Optionen im Identity-Picker. Smoketests
  `scripts/avatar_identity_smoke.gd` (45 Assertions PASS;
  Harness-Case `avatar-identity-smoke`) und
  `scripts/avatar_template_capabilities_smoke.gd` (65 Assertions
  PASS; Harness-Case `avatar-template-capabilities-smoke`) decken
  Default, Parser, Fallback, Capability-Lookups und Multiplier-
  Mapping ab. Details siehe
  [`docs/ui_architecture.md` §8b.8](./docs/ui_architecture.md).
  Bewusst **nicht** Teil dieses Schritts: weitere Figuren über die
  vier hinaus, animierte Prozeduralformen, alternative State-
  Maschinen, Asset-Imports, Plug-in-Contract-Sprache, User-Uploads.
- **Stufe C — Forschungs- und Designraum (research-gated,
  security-gated; nicht begonnen).** Stage C ist in diesem Zyklus
  ausdrücklich **keine** aktive Build-Phase. Es existiert weder
  Asset-Loader noch Manifest-Parser noch File-Picker für Avatar-
  Inhalte; der Capability-Contract aus Stufe B bleibt intern. Was
  „Stage C" in Zukunft überhaupt meinen könnte — mögliche
  Architekturpfade (nur mehr kuratierte Templates, repo-gepflegte
  statische Assets, deklarative lokale Bundles, echte User-Imports),
  harte Nicht-Ziele (kein Plugin-System, kein Marktplatz, keine
  ausführbaren Fremdskripte, keine stillen Netzwerkzugriffe, keine
  Vermischung mit Personality / Policy / Permissions / ABrain),
  Sicherheits- und Vertrauensmodell sowie Exit-Kriterien für einen
  späteren echten Implementierungsstart — steht konsolidiert in
  [`docs/avatar_stage_c_research.md`](./docs/avatar_stage_c_research.md).
  Ein Übergang von Research in Implementation ist erst legitim, wenn
  die dort in §10 aufgeführten Kriterien erfüllt sind.

### 4b.6 Nicht-Ziele

- **Kein 3D-Character-Editor.**
- **Kein generisches Avatar-Rigging-System** im MVP.
- **Kein Einfluss auf ABrain** — weder über das Appearance-System
  noch über Behavior Profiles.
- **Kein Einfluss auf Core-Logik** — gleiche Nutzereingabe erzeugt
  dieselbe Systemreaktion, unabhängig vom gewählten Avatar.
- **Kein Einfluss auf Security / Permissions** — Avatar-Wahl
  verändert keine Approval-Flows, keine Action-Execution-Rechte,
  keine Trust-Entscheidungen.
- **Kein automatisches „Persönlichkeits-Upgrade" durch Avatar** —
  ein „verspieltes" Visual-Profile führt nicht zu anderem
  Assistant-Verhalten.
- **Kein Austausch des Defaults.** Smolit Salamander bleibt
  Default und Referenz; Alternativen sind additiv, nicht
  ersetzend.

Detailarchitektur siehe
[`docs/ui_architecture.md`](./docs/ui_architecture.md), Abschnitt
„Avatar Appearance System (Ziel-Zustand)".
Presence-Einordnung siehe
[`docs/presence_desktop_interaction.md`](./docs/presence_desktop_interaction.md),
Unterabschnitt „Avatar-Personalisierung als Presence-Erweiterung".

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
- [~] Visual Action Modes (none / minimal feedback / guided movement /
      full theatrical) — Phase-3.3-MVP als UI-Staging-Achse gelandet
      (siehe Phase 3 Subeinheit 3.3 oben). Endausprägung (Bewegungspfad
      / Zielobjekt / Gestik über Fremdfenster) bleibt offen.
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
- [~] Forschungsspikes zu Wayland-Constraints unter GNOME 46/47
      (Transparenz, Input-Region, HiDPI, Fractional Scaling,
      Nvidia/XWayland-Edge-Cases). Grundlage ist jetzt der
      **Verifikationsspike**: opt-in Runtime-Report
      (`SMOLIT_WINDOW_REPORT=1`) +
      [docs/linux_overlay_verification_matrix.md](./docs/linux_overlay_verification_matrix.md)
      + [scripts/run_overlay_verification.sh](./scripts/run_overlay_verification.sh).
      Die tatsächlichen Messläufe auf realen Wayland-/X11-Sessions
      stehen weiterhin offen und sind nicht von diesem Harness
      geleistet — er liefert nur die reproduzierbare Grundlage dafür.
- [x] Entscheidungsspike „always-on-top unter GNOME": Extension vs.
      Verzicht vs. compositor-spezifischer Pfad — entschieden für
      **Verzicht im Standardpfad** auf GNOME/Wayland. GNOME-Shell-
      Extension ausdrücklich zurückgestellt (Pflegeaufwand,
      Versionsbindung, Sicherheitsmodell); X11-Sonderpfad bleibt
      dokumentierte Option für spätere, opt-in Aktivierung;
      wlroots/layer-shell bleibt dokumentierte Möglichkeit ohne
      aktuelles Ziel. Details und Produktversprechen siehe
      [docs/linux_always_on_top_decision.md](./docs/linux_always_on_top_decision.md);
      Entscheidungssnapshot in
      [docs/linux_window_overlay_architecture.md §G.2](./docs/linux_window_overlay_architecture.md).
      Ergänzend enthält der opt-in `SMOLIT_WINDOW_PROBE=1`-Pfad
      jetzt einen kurzen, reversiblen AOT-Flag-Versuch als ehrliche
      Diagnostik („flag accepted by API — not a user-visible
      guarantee under Mutter").
- [~] X11-Sonderpfad für optionales Always-on-top — kleiner opt-in
      MVP gelandet. Eigenes Env-Flag `SMOLIT_UI_ALWAYS_ON_TOP=1`,
      eigener Controller
      `ui/scripts/window_behavior/overlay_always_on_top_controller.gd`,
      strikt X11-only: unter Wayland/GNOME, headless und unknown
      Session ein ehrlicher No-op mit klarer Log-Begründung.
      Unter echtem X11 setzt der Controller
      `WINDOW_FLAG_ALWAYS_ON_TOP` (entspricht `_NET_WM_STATE_ABOVE`)
      und loggt, dass sichtbares Stacking-Verhalten WM-abhängig
      bleibt — ausdrücklich kein Standard-MVP und kein universelles
      Linux-AOT-Feature. Reproduzierbarer Harness-Case `aot-x11` in
      [scripts/run_overlay_verification.sh](./scripts/run_overlay_verification.sh)
      (neu: `--scene`-Flag startet die Main-Scene als Standalone-
      Runtime für echte X11-Messungen). Details:
      [docs/linux_window_overlay_architecture.md §F.4](./docs/linux_window_overlay_architecture.md)
      und
      [docs/linux_always_on_top_decision.md](./docs/linux_always_on_top_decision.md).
      Auf dem GNOME/X11-Entwicklungshost inzwischen **beide Ebenen**
      gemessen: Protokoll (`_NET_WM_STATE_ABOVE` gesetzt) und UX mit
      xterm-Peer (Smolit bleibt im Stacking oberhalb bei
      Fokuswechsel, über Minimize/Restore und sogar bei
      fullscreen-xterm; nicht sticky über Workspaces). Details in
      [docs/x11_always_on_top_verification.md §F.1 / §H](./docs/x11_always_on_top_verification.md)
      und [docs/x11_always_on_top_results.md](./docs/x11_always_on_top_results.md).
      Zeile bleibt bewusst bei `[~]` — offen: KDE/KWin (X11), Xfwm4,
      Openbox, Fluxbox, XWayland-Sonderfall, Browser-F11 /
      Videospieler-Fullscreen, Multi-Monitor, Langzeitstabilität.
      Feintuning (z. B. `_NET_WM_WINDOW_TYPE_DOCK`) nur bei klarer
      Nachfrage.
      Zusätzlich: **Refusal-Gegentest** für GNOME/Wayland existiert
      jetzt als dedizierter Harness-Case `aot-wayland-refusal` mit
      Env-Override-Simulation; Rohdaten in
      [docs/wayland_always_on_top_refusal_results.md](./docs/wayland_always_on_top_refusal_results.md).
      Offen bleibt der Lauf gegen einen echten Mutter-Wayland- oder
      wlroots-Compositor — nicht, um AOT dort einzubauen, sondern um
      die Refusal-Message gegen reale Session-Signale zu verifizieren.
- [ ] Entscheidungsspike „Godot-Fenster-Flags vs. GDExtension vs.
      Host-Prozess mit eingebettetem Godot".
- [~] Window-Behavior-Abstraktion als eigene Schicht
      (`window_behavior/`) vollständig ausbauen — Trait/Interface mit
      `set_always_on_top`, `set_transparent`, `set_click_through`,
      `request_position`, `current_capabilities`. Capability-Seite
      steht per Spike v1 bereits; Activation-Seite ist inzwischen in
      drei getrennte opt-in Controller (Overlay, Click-through, X11-
      AOT) zerlegt und verwendet ein gemeinsames Ergebnis-Vokabular
      (`requested / capable / applied / observed / active / reason`,
      siehe `window_behavior_result.gd`). Offen: echte Backend-
      Familie (§F Zielstruktur), `request_position`, ein Setter-
      Interface statt drei separaten Controllern.
- [~] Backends als getrennte Familie einordnen: `backend_x11`,
      `backend_wayland_mutter`, `backend_wayland_wlroots`,
      `backend_xwayland`, `backend_wayland_generic`,
      `backend_noop`. **Familienstruktur steht** — alle sechs
      Klassen existieren unter `ui/scripts/window_behavior/`, plus
      `backend_base.gd` und `backend_resolver.gd`. Die Fassade
      `apply_all(anchor)` löst pro Lauf ein Backend auf (Session-Typ
      + Desktop-Environment + Display-Driver → konservative
      Klassifikation in GNOME/Mutter, wlroots-Familie, XWayland-
      Sonderfall, oder generischer Wayland-Fallback) und delegiert
      die drei Aktivierungen darüber. Plattformlogik bleibt in den
      Controller-Gates. **Routing-Ebene empirisch belegt**: der
      Resolver-Klassifikations-Smoketest
      [`scripts/resolver_classification_smoke.gd`](./scripts/resolver_classification_smoke.gd)
      bestätigt die Auswahl für alle sechs Backends (9 synthetische
      Session/Desktop/Driver-Kombinationen PASS); der opt-in
      Runtime-Report druckt die gewählte `backend.id` +
      `backend.description` in einem eigenen Block. Evidenzmatrix
      pro Backend (real / simuliert / offen) steht in
      [docs/window_behavior_backend_verification.md](./docs/window_behavior_backend_verification.md).
      **Echte backend-spezifische Aktivierung bleibt offen**: die
      Backends delegieren 1:1 an die gemeinsamen Controller; echte
      Differenzierung (`wlr-layer-shell`-Wrapper in
      `backend_wayland_wlroots`, etwaige Mutter-spezifische Policy
      in `backend_wayland_mutter`, XWayland-AOT-Feintuning) bleibt
      spätere, bewusst gewählte Arbeit. Auch die in §F des
      Architekturdokuments genannten Setter-/Positionsoperationen
      sind noch offen, ebenso echte Compositor-Läufe auf realen
      Mutter-Wayland-/KDE-Wayland-/wlroots-Sessions.
- [~] Experimenteller wlroots-Vorbereitungspfad —
      `backend_wayland_wlroots` trägt jetzt als **einziges** Backend
      einen `experimental_stance`-Marker und ergänzt die
      Aktivierungs-Ergebnis-Dicts additiv um einen
      `wlroots_research`-Block (`state = "prepared, not
      implemented"`). Runtime-Report druckt `backend.experimental =
      experimental seat for a future wlr-layer-shell-unstable-v1
      path …`, wenn dieses Backend gewählt wurde. Verhalten
      unverändert: keine layer-shell-Integration, keine neue
      Aktivierung, kein Nutzerversprechen unter wlroots. Forschungs-
      und Decision-Grundlage:
      [docs/wlroots_overlay_path.md](./docs/wlroots_overlay_path.md).
      Offen: echter Spike mit `wlr-layer-shell-unstable-v1`,
      Godot-/GDExtension-/Host-Prozess-Frage aus §F des
      Architekturdokuments, echte Sway-/Hyprland-Messung.
- [x] Overlay-MVP Phase B (opt-in): transparent + borderless
      Presence-Fenster per `SMOLIT_UI_OVERLAY=1`, capability-gesteuert
      mit ehrlichem Fallback; **ohne** Always-on-top-Zusicherung unter
      GNOME/Wayland. Produktives Click-through hat seinen eigenen
      Folgepunkt (siehe nächsten Eintrag), ist nicht stillschweigend in
      Phase B enthalten. Siehe
      [docs/linux_window_overlay_architecture.md §F.2](./docs/linux_window_overlay_architecture.md)
      und
      [docs/ui_architecture.md §9.2](./docs/ui_architecture.md).
- [~] Click-through mit definierten interaktiven Zonen (opt-in
      Folgeschritt auf Phase B) — Zwischenstand, ausdrücklich noch
      **nicht** das finale Interaktionsmodell. Aktiv nur, wenn
      `SMOLIT_UI_CLICK_THROUGH=1` gesetzt ist, Overlay wirklich aktiv
      ist, Click-through-Capability tragfähig ist und mindestens eine
      *gültige* Zone (Allowlist, Visible, Rohsize > 0, Viewport-Clamp,
      Mindestkantenlänge) ableitbar ist. Aktueller MVP nutzt Godots
      `DisplayServer.window_set_mouse_passthrough` mit *einem*
      Polygonpfad und fasst alle gültigen Zonen (Avatar, Header,
      Banner, DockPanel, CompactInputPanel) zu einer **einzigen
      Bounding-Rect-Union** zusammen — leerer Raum *innerhalb* dieser
      Box bleibt klickbar. Refresh läuft über `visibility_changed` /
      `resized`-Signale und einen einmaligen `call_deferred`-Post-
      Layout-Refresh; Refresh-Logs sind dedupliziert. Ausdrücklich
      offen bis zur Ablösung dieses Zwischenstandes:
      Multi-Polygon-Passthrough-Shapes (XShape-Multirect unter X11
      bzw. `wl_surface.set_input_region` mit mehreren Rechtecken
      unter Wayland), präzisere Input-Regionen statt Bounding-Union,
      robustere HiDPI-/Mehrfenster-Koordinaten. Siehe
      [docs/linux_window_overlay_architecture.md §F.3](./docs/linux_window_overlay_architecture.md)
      und
      [docs/ui_architecture.md §9.3](./docs/ui_architecture.md).
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

## Phase 8c – Provider Fallback & Settings (parallele Linie, Architektur-Spike)

Parallele Linie zu den Avatar-/Interaction-Strängen. Ziel: Smolit-
Assistant auch **ohne ABrain** als eigenständiger Assistent nutzbar
machen — über lokale oder (opt-in, sichtbare) Cloud-Provider für Text,
STT und TTS. **Kein** Security-Bypass, **keine** Aufweichung der
Approval-/Interaction-Policy, kein heimlicher Cloud-Zwang.

Grundlage steht als Architektur-Dokument:
[docs/provider_fallback_and_settings_architecture.md](./docs/provider_fallback_and_settings_architecture.md)
— Provider-Achsen (Text / STT / TTS), Fallback-Modell,
Transparenz-/Sicherheitsgrenzen, Status-/Health-Modell, Settings-Scope
und Nicht-Ziele.

- [x] Architektur + Doku (PR 1 aus §9 der Doku). Kein Code, kein
      Scene-/IPC-/Core-Eingriff.
- [x] PR 2: Core Provider Resolver für Text — gelandet. Neuer
      `core/src/providers/text.rs` mit `TextProviderImpl`-Enum,
      `TextProviderResolver` (geordnete Kette, deterministischer
      Fallback, Runtime-Status), `AbrainCliProvider` als einziger
      produktiver Kind. Config: `TextProviderConfig.chain` (Env
      `SMOLIT_TEXT_PROVIDER_CHAIN`, unbekannte Kinds sichtbar
      verworfen, leere Kette → Default `["abrain"]`). `App::handle_text_query`
      geht jetzt ausschließlich durch den Resolver (alter
      `adapters::abrain`-Pfad entfernt). `StatusPayload` additiv um
      fünf `text_provider_*`-Felder erweitert
      (`configured` / `active` / `availability` / `last_error` /
      `cloud`). Keine neuen Eventtypen, keine Policy-Änderung, kein
      Cloud-Pfad. Details in
      [docs/provider_fallback_and_settings_architecture.md §9](./docs/provider_fallback_and_settings_architecture.md)
      und [docs/api.md §2.3 / §3](./docs/api.md).
- [x] PR 2a: Llamafile-Local-Vorbereitung (Variante A, Architektur-
      Stub) — gelandet. Neue Enum-Variante
      `TextProviderImpl::LlamafileLocal`, `LlamafileLocalProvider`
      mit acht-Zustände-Lifecycle-Modell (heute produziert:
      `disabled` / `not_configured` / `configured`; scaffolding:
      `starting` / `ready` / `busy` / `failed` / `stopped`),
      `LlamafileConfig` in `config.rs` mit vier neuen Env-Vars
      (`SMOLIT_LLAMAFILE_ENABLED` / `SMOLIT_LLAMAFILE_PATH` /
      `SMOLIT_LLAMAFILE_MODE` mit Whitelist `on_demand`/`standby` /
      `SMOLIT_LLAMAFILE_IDLE_TIMEOUT_SECONDS`). Stub liefert beim
      Aufruf **ausschließlich** deterministische Refusal-Klassen
      (`disabled` / `not_configured` / `not_implemented`); Resolver
      instanziiert den Stub auch bei inaktivem Lifecycle, damit
      Fallback-Fluss `llamafile_local → abrain` mit
      `availability=fallback_active` überprüfbar ist. **Runtime
      nicht implementiert** — Prozess-Spawn, HTTP-Dispatch,
      Idle-Timeout-Scheduling bleiben PR 2b. Kein Modell-Bundling,
      keine Secrets, keine UI, keine Cloud. Core-Tests: 120 PASS
      (17 neue Resolver-/Lifecycle-Tests, 4 neue Config-Tests); alle
      10 UI-Smokes bleiben grün.
- [x] PR 2b: Llamafile Runtime — gelandet. Realer `on_demand`-
      Runtime-Pfad für `llamafile_local`: Prozess-Spawn (tokio mit
      `kill_on_drop`), Readiness-Poll gegen `GET /health`, Completion
      via `POST /completion` (`stream: false`), interner HTTP/1.1-
      Client auf `tokio::net::TcpStream` (keine SDK-Abhängigkeit).
      Watchdog-Task hält `Weak`-Referenz und beendet den Prozess nach
      `idle_timeout_seconds` Ruhe; Folge-Request spawnt wieder. Alle
      acht Lifecycle-Zustände (`disabled` / `not_configured` /
      `configured` / `starting` / `ready` / `busy` / `failed` /
      `stopped`) werden real durchlaufen. Drei neue Env-Vars
      (`SMOLIT_LLAMAFILE_PORT` / `_STARTUP_TIMEOUT_SECONDS` /
      `_REQUEST_TIMEOUT_SECONDS`), acht zusätzliche Fehlerklassen im
      Klassifikator. Single-Process-/Single-Request-MVP; kein
      Streaming, kein `standby` (reserviert, verhält sich heute wie
      `on_demand`). Core-Tests: 129 PASS (+9 gegenüber PR 2a, darunter
      drei Integrationstests gegen einen Fake-HTTP-Server plus Shell-
      Skript als Spawn-Ziel); alle 10 UI-Smokes grün. Details in
      [docs/provider_fallback_and_settings_architecture.md §4.1a](./docs/provider_fallback_and_settings_architecture.md)
      und [docs/api.md §3](./docs/api.md). **Weiterhin offen:**
      Modell-Bundling/Provisioning, echter `standby`-Mode, Streaming,
      GPU-/Advanced-Tuning, Settings-UI-Exposition des Lifecycles —
      jeweils eigene Folge-PRs.
- [x] PR 3: Settings-Shell im UI — gelandet. Reine UI-Shell für ein
      Settings-Panel im Expanded-Window: sichtbarer `⚙ Settings`-
      Button im Header-Row, neuer UI-Substate innerhalb derselben
      Presence-Hülle (Shell ersetzt das Dock-Panel, Avatar / Banner /
      Workflow-Overlay / Utterance-Bubble bleiben unberührt). Sieben
      read-only Bereiche aus Doku §6 in fester Reihenfolge:
      **General**, **Presence / UI**, **Text Provider**, **STT**,
      **TTS**, **Privacy / Cloud / Data handling**,
      **Connection / Status**. Text-Provider-Readout bindet defensiv
      an die fünf `text_provider_*`-Felder aus `StatusPayload` und
      benennt `llamafile_local` ehrlich als lokalen Runtime-Fallback
      (Configured/Active/Availability/Last-Error/Cloud sichtbar; keine
      Pfad-/Secret-/Start/Stop-Eingabe). Keine neuen IPC-Nachrichten,
      keine Schreibaktionen, kein Secrets-Editor, keine Cloud-Integration.
      Neue Dateien: `ui/scenes/settings/settings_panel.tscn`,
      `ui/scripts/settings/settings_sections.gd`,
      `ui/scripts/settings/settings_panel_controller.gd`; additive
      Einbindung in `ui/scenes/main.tscn` + `ui/scripts/main.gd`. Tests:
      `scripts/settings_shell_smoke.gd` (70 Assertions PASS), Harness-
      Case `settings-shell-smoke`. Alle bestehenden UI-Smokes bleiben
      grün, Core-Tests unberührt. Details in
      [docs/ui_architecture.md §8d](./docs/ui_architecture.md) und
      [docs/provider_fallback_and_settings_architecture.md §9](./docs/provider_fallback_and_settings_architecture.md).
- [x] PR 4: Vertiefter Status-Readout für Text/STT/TTS — gelandet
      (Text-Achse produktiv; STT/TTS konservativ bei Basis-Readout).
      `StatusPayload` um sieben additive Felder erweitert:
      `text_provider_chain` (geordnete Resolver-Kette),
      `llamafile_in_chain`, `llamafile_enabled`,
      `llamafile_configured`, `llamafile_lifecycle`, `llamafile_mode`,
      `llamafile_idle_timeout_seconds`. Lifecycle-/Mode-/Idle-Felder
      sind `null`, wenn `llamafile_local` **nicht** in der Kette
      steht — so bleibt `null` ehrlich als „nicht in der Kette"
      lesbar, nicht als „Runtime kaputt". Resolver exponiert
      `chain_kinds()` (jetzt öffentlich) und
      `llamafile_lifecycle()`. Die Settings-Shell rendert die Kette
      als „→"-getrennte Reihenfolge, öffnet bei
      `llamafile_in_chain=true` einen vertieften llamafile-Block und
      verdichtet Cloud-/Lokal-Status im Privacy-Abschnitt. Kein
      Cloud-Provider, keine STT-/TTS-Provider-Abstraktion, keine
      Secrets-Eingabe, keine Schreibaktionen, keine neue IPC-Familie.
      Ältere UI-Stände ohne Kenntnis der neuen Felder bleiben ohne
      Regression lesbar (defensiver Rückfall-Pfad im Renderer).
      Tests: Core 135 PASS (+6 Resolver-/IPC-Tests); UI
      `settings-shell-smoke` auf 88 Assertions erweitert (+18). Alle
      anderen UI-Smokes grün. Details in
      [docs/provider_fallback_and_settings_architecture.md §8.1](./docs/provider_fallback_and_settings_architecture.md),
      [docs/api.md §2.3](./docs/api.md) und
      [docs/ui_architecture.md §8d](./docs/ui_architecture.md).
- [x] PR 5: Erste Schreib-/Probe-Oberfläche (Text-Achse,
      `llamafile_local`) — gelandet, bewusst konservativ. Die
      Settings-Shell bekommt einen schmalen Editor-Block direkt
      unter dem Text-Provider-Readout: `enabled` (CheckBox),
      `mode` (OptionButton `on_demand`/`standby`),
      `idle_timeout_seconds` (SpinBox) und Binary-`path` (LineEdit),
      plus Apply- und Probe-Button. Apply → neue additive IPC-
      Nachricht `settings_set_llamafile_config`; Core validiert
      (Whitelist für Mode, `idle > 0`), rebuildet den
      `TextProviderResolver` atomar, persistiert atomar in einer
      kleinen JSON-Datei unter `SMOLIT_SETTINGS_DIR` → `$XDG_CONFIG_HOME/smolit-assistant/` →
      `$HOME/.config/smolit-assistant/` (Permissions 0600), und
      antwortet mit einem frischen `status`-Envelope; unbekannte
      Werte lehnen den Write **ausdrücklich** ab. Probe →
      `settings_probe_llamafile` → `settings_probe_result` mit
      kuratierten Tags (`ok` / `not_in_chain` / `disabled` /
      `not_configured` / `path_missing` / `path_not_file` /
      `path_not_executable`), Side-Effect-frei (kein Spawn, kein
      HTTP). Sicherheitsdisziplin: Binary-Pfad taucht weder in Logs
      noch im Probe-Ergebnis noch im Fehler-Envelope auf (`path_set`-
      Boolean reicht); Sensitive-Werte (API-Keys etc.) sind
      ausdrücklich **nicht** Teil von PR 5 und bleiben für einen
      späteren dedizierten Secret-Pfad reserviert. Neues Core-Modul
      `settings_store` mit Kategorien-Doku; App wrappt
      `text_provider` jetzt hinter `RwLock<Arc<...>>` für atomare
      Rebuilds. Keine neue IPC-Familie, keine STT-/TTS-Provider-
      Abstraktion, keine Cloud-Integration, keine Provider-Auswahl,
      keine Start/Stop-Logik in der UI, keine Pfad-Editor-
      Clear-Affordance (bewusst ausgelassen — Apply mit leerem Feld
      sendet `null`, nicht `""`). Details in
      [docs/provider_fallback_and_settings_architecture.md §9 + §11](./docs/provider_fallback_and_settings_architecture.md),
      [docs/api.md §2.10](./docs/api.md),
      [docs/ui_architecture.md §8d.5a](./docs/ui_architecture.md).
      Tests: Core 150 PASS (+15 vs. PR 4 — sechs
      `settings_store`-Unit-Tests, vier IPC-Integrationstests, vier
      Protocol-Tests, ein Mode-Validator-Test); UI
      `settings-shell-smoke` auf 103 Assertions erweitert (+15).
      Alle zehn anderen UI-Smokes grün; Headless-Boot sauber.
- [x] PR 6: STT-/TTS-Provider-Abstraktion + Statusangleichung —
      gelandet, konservativ. Die Audio-Achsen werden an den Text-Pfad
      angeglichen: zwei neue Core-Module
      [core/src/providers/stt.rs](./core/src/providers/stt.rs) und
      [core/src/providers/tts.rs](./core/src/providers/tts.rs) mit
      Enum-Dispatch, Resolver, Laufzeitstatus und
      Fehlerklassifikator — gleiche Leitplanken wie Text-Resolver.
      Heute produktives Kind pro Achse: `command` (bisheriger
      `SMOLIT_STT_CMD` / `SMOLIT_TTS_CMD`-Pfad, byte-kompatibel —
      Timeouts, Fehlertexte, Legacy-`available`-Semantik bleiben
      erhalten). Altes `audio::SttService`/`audio::TtsService`
      entfernt; `audio/types.rs` bleibt für geteilte Helfer.
      `AudioConfig` bekommt zwei zusätzliche Listen
      (`stt_provider_chain`, `tts_provider_chain`) mit
      Env-Overrides `SMOLIT_STT_PROVIDER_CHAIN` /
      `SMOLIT_TTS_PROVIDER_CHAIN`; unbekannte Kinds werden sichtbar
      verworfen, Fallback auf `["command"]`. `App.stt` und `App.tts`
      sind jetzt `Arc<…Resolver>`; `handle_voice_once` und
      `handle_speak` routen ausschließlich durch den Resolver.
      `StatusPayload` additiv um zehn Felder erweitert:
      `stt_provider_configured` / `_active` / `_availability` /
      `_last_error` / `_cloud` und der TTS-Spiegel. UI-Settings-
      Shell rendert die fünf Resolver-Zeilen pro Achse (mit
      ehrlichem Fallback-Hinweis für alte Cores); der Privacy-
      Abschnitt verdichtet STT-/TTS-Cloud separat, sobald die
      neuen Felder da sind. Keine Cloud-Kinds, kein HTTP-Kind,
      keine Streaming-Pipeline, keine neuen Audio-Events, keine
      STT-/TTS-Provider-Editor-Fläche in der UI — das bleibt
      explizit offen für spätere PRs. Details in
      [docs/provider_fallback_and_settings_architecture.md §4.2 + §4.3 + §9](./docs/provider_fallback_and_settings_architecture.md),
      [docs/api.md §2.3 + §4](./docs/api.md),
      [docs/ui_architecture.md §8d](./docs/ui_architecture.md).
      Tests: Core 170 PASS (+20 vs. PR 5 — zwei neue Resolver-
      Test-Module mit je ~7 Tests, drei neue Config-Parser-Tests,
      zwei neue IPC-Integrationstests); UI
      `settings-shell-smoke` auf 118 Assertions erweitert (+15).
      Alle zehn anderen UI-Smokes grün; Headless-Boot sauber.
- [x] PR 7: STT-/TTS-Settings-Editor + Probe-Pfade — analog zu PR 5,
      bewusst kleiner gehalten. Der
      [`settings_store`](./core/src/settings_store.rs) bekommt zwei
      weitere Override-Dateien `stt.json` und `tts.json` (gleiche
      Verzeichnis-Auflösung, 0600-Permissions, atomarer Schreibpfad),
      [`App`](./core/src/app.rs) hält einen neuen `live_audio`-
      Zustand (`Mutex<AudioConfig>`) und rebuildet den STT- bzw.
      TTS-Resolver atomar bei jedem Schreibpfad. STT-/TTS-Resolver
      sitzen dafür seit PR 7 hinter `RwLock<Arc<…>>`, Callsites holen
      den aktuellen Resolver über `App::current_stt()` /
      `current_tts()`. Neue IPC-Messages
      `settings_set_stt_config` / `settings_set_tts_config` /
      `settings_probe_stt` / `settings_probe_tts` (alle additiv).
      `SettingsProbeResultPayload` trägt jetzt ein `axis`-Feld
      (`"llamafile"` / `"stt"` / `"tts"`) für das UI-Routing;
      ältere Cores ohne das Feld werden UI-seitig auf `llamafile`
      zurückgefallen. Die Settings-Shell bekommt zwei weitere
      Editor-Blöcke (`stt · Edit` und `tts · Edit`) direkt unter
      dem jeweiligen Read-only-Abschnitt: Enabled + Command +
      Apply + Probe; TTS ergänzt um Auto-Speak. Der Probe-Pfad ist
      Side-Effect-frei: kein Mikrofon-Zugriff, kein Audio-Output,
      kein Spawn — nur `split_command` + Filesystem-Check des
      ersten Tokens. Secret-Disziplin wie bei PR 5: der Command-
      String taucht weder in Logs, `settings_probe_result` noch
      `error`-Envelopes auf. Keine Timeout-Editoren, keine Chain-
      Umordnung, keine Cloud-Achse, keine Audio-Level-Anzeige, kein
      Secrets-Store — bleibt explizit offen. Details in
      [docs/provider_fallback_and_settings_architecture.md §9 + §11](./docs/provider_fallback_and_settings_architecture.md),
      [docs/api.md §2.10 (inkl. 2.10a)](./docs/api.md),
      [docs/ui_architecture.md §8d.5b](./docs/ui_architecture.md).
      Tests: Core 185 PASS (+15 vs. PR 6 — fünf IPC-Ende-zu-Ende-
      Tests, vier `settings_store`-Unit-Tests, fünf Protocol-
      Parser-Tests, zwei Probe-Axis-Tests); UI
      `settings-shell-smoke` auf 136 Assertions erweitert (+18).
      Alle übrigen UI-Smokes grün; Headless-Boot sauber.
- [x] PR 8: erster zusätzlicher externer Text-Provider `local_http`
      — allgemeiner lokaler HTTP-Text-Provider, gleichrangig zu
      `abrain` und `llamafile_local`. Ziel: Brücke zwischen rein
      lokal-eingebetteten Providern und späterer Cloud-Welt; kein
      Cloud-SDK, keine Secrets-Pflicht, lokal-first, HTTP-MVP.
      Neuer `TextProviderImpl::LocalHttp`-Variant in
      [`core/src/providers/text.rs`](./core/src/providers/text.rs);
      nutzt den bereits bestehenden internen `http_request`-Helfer
      (HTTP/1.1 über `tokio::net::TcpStream`), **keine neue
      Dependency, kein TLS, kein Streaming**. `TextProviderConfig`
      bekommt ein additives `local_http`-Unterobjekt
      (`LocalHttpConfig`) mit `enabled`, `endpoint`,
      `request_timeout_seconds`, `prompt_field`, `response_field`;
      neue Env-Variablen `SMOLIT_LOCAL_HTTP_ENABLED` /
      `_ENDPOINT` / `_REQUEST_TIMEOUT_SECONDS` / `_PROMPT_FIELD` /
      `_RESPONSE_FIELD`. Der Provider postet
      `{"<prompt_field>": "<input>", "stream": false}` und liest
      `<response_field>` aus der JSON-Antwort; `https://` wird
      hart abgelehnt (eigene Fehlerklasse
      `endpoint_scheme_unsupported`). `settings_store` bekommt
      `local_http.json` als viertes Override-File
      (Verzeichnis-Auflösung, 0600-Permissions, atomarer
      Schreibpfad wie bei PR 5/7). `App` hält einen neuen
      `live_local_http`-Zustand; Schreibpfad rebuildet den
      `TextProviderResolver` atomar analog zu PR 5. Neue IPC-
      Messages `settings_set_local_http_config` /
      `settings_probe_local_http`; der Probe ist ehrlich
      loopback-begrenzt: **nur** TCP-Connect auf `host:port`,
      **kein** Completion-Roundtrip, **kein** Prompt-Versand.
      `StatusPayload` bekommt drei additive Felder
      (`local_http_in_chain` / `_enabled` / `_configured`); der
      Endpoint **taucht nicht** im Status auf. Die Settings-Shell
      bekommt einen eigenen „local_http · Edit"-Block direkt
      unter dem Llamafile-Editor (Enabled + Endpoint + Apply +
      Probe), Probe-Ergebnisse werden über den neuen
      `axis="local_http"`-Diskriminator geroutet. **Bewusst nicht
      Teil von PR 8:** kein TLS / `https://`, keine Streaming-
      Pipeline, keine Auth-/API-Key-Eingabe, keine
      OpenAI-/`messages`-Welt, keine Chain-Reihenfolge-Umordnung
      in der UI, keine Cloud-Provider-Implementierung, keine
      Timeout-Editoren in der Shell. Details in
      [docs/provider_fallback_and_settings_architecture.md §4.1c + §9 + §11](./docs/provider_fallback_and_settings_architecture.md),
      [docs/api.md §2.10 (inkl. 2.10b) + §3](./docs/api.md),
      [docs/ui_architecture.md §8d.5c](./docs/ui_architecture.md).
      Tests: Core 210 PASS (+25 vs. PR 7 — neun Text-Provider-
      Unit-Tests für den `local_http`-Request-/Response-Pfad und
      den Endpoint-Parser, drei `settings_store`-Unit-Tests,
      drei Protocol-Parser-Tests, fünf IPC-Ende-zu-Ende-Tests
      inkl. Secret-Disziplin); UI `settings-shell-smoke` auf 154
      Assertions erweitert (+18 — Editor-Bau + Sync, axis-
      Routing, Scheme-unsupported ohne Leak,
      `text_provider_lines`-Visibility-Pfad). Alle übrigen UI-
      Smokes grün; Headless-Boot sauber.

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
