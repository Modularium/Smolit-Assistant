# Smolit AI Assistant — Developer Roadmap

> Stand: 2026-04-24 (nach PR 31 Roadmap Checkpoint). Diese Datei ist
> eine **Roadmap**, kein PR-Changelog. Detailhistorie pro PR lebt in
> [`docs/reviews/`](./docs/reviews/) — insbesondere der Sammelblick
> auf die PR-21–30-Serie liegt in
> [`docs/reviews/PR31_ROADMAP_CHECKPOINT.md`](./docs/reviews/PR31_ROADMAP_CHECKPOINT.md).

---

## 1. Vision

Smolit ist ein lokal-first AI-Assistent für den Linux-Desktop:
Sprache, Text, Desktop-Präsenz, sichtbarer Action-Flow, Approval-
Gating. Ziel ist ein Assistent, der **sichtbar, kontrolliert und
ehrlich** handelt, nicht ein Autonomie-Maximierer.

Leitlinien:

- **Control > Autonomy.** Gefährliche Aktionen laufen durch einen
  expliziten Approval-Pfad.
- **Lokal vor Cloud.** Cloud-Provider sind opt-in und additiv.
- **Sichtbarkeit statt Surveillance.** Audit-Trail in-memory,
  klein, sanitisiert — keine Persistenz als Default.
- **Additive Protokolle.** IPC-Envelopes wachsen rückwärts-
  kompatibel; kein bestehender Kanal wird ersetzt.
- **Core = Source of Truth.** UI spiegelt, entscheidet nichts
  sicherheitsrelevantes.

Detaillierte Begriffswelt: siehe
[`docs/VISION.md`](./docs/VISION.md) (historischer Snapshot),
[`docs/presence_desktop_interaction.md`](./docs/presence_desktop_interaction.md).

---

## 2. Architekturprinzipien

- **Rust-Core** (`core/src/`) hält Protokoll, Provider-Abstraktion,
  Approval-Engine, Audit-Store, Interaction-Executor. Keine UI-
  Logik im Core.
- **Godot-UI** (`ui/`) ist Renderer plus Thin-Client. Kein Core-
  Ersatz, keine parallelen State-Maschinen.
- **IPC:** lokaler WebSocket auf `127.0.0.1:8787` (Default),
  JSON-Text-Frames, additive Envelopes, keine Persistenz des
  Transports. Siehe [`docs/api.md`](./docs/api.md).
- **Provider-Achsen:** text / stt / tts. Jede Achse hat eine
  kuratierte Whitelist und eine geordnete Kette mit Fallback.
- **Approval:** `PendingApprovalRegistry` enforced Idempotenz
  (Double-Approve → `error`-Frame). Kein Persistenz-Layer, keine
  Policy-Engine, keine Multi-Seat-Semantik.
- **Audit:** bounded Ring-Buffer, sanitisiert, in-memory. Read-
  only Wire-Endpoint `audit_recent`. Siehe
  [`docs/security/AUDIT_TRAIL.md`](./docs/security/AUDIT_TRAIL.md).

---

## 3. Current Stable Baseline

### Core

- `core/src/app.rs` Orchestrator, broadcast-basierter
  Outgoing-Kanal.
- `core/src/actions/` Action-Event-Modell v1 + Demo-Plan-Modell
  (PR 18).
- `core/src/approvals/` ApprovalRequest/Resolved mit `risk` +
  `source`, PendingApprovalRegistry (idempotent).
- `core/src/audit/` AuditStore (Ring-Buffer; Default 100 / Hard
  1000 / Env `SMOLIT_AUDIT_MAX_EVENTS`).
- `core/src/interaction/` InteractionExecutor + CommandBackend.
  `open_application` real verdrahtet und seit PR 25 (Policy v0)
  **approval-gated by default**; `focus_window` template-basiert auf
  X11 mit **doppeltem Opt-in**
  (`SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW=1` plus
  `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`), unter Wayland honest
  `BackendUnsupported`; `type_text` / `send_shortcut` bleiben
  `BackendUnsupported`. `DEFAULT_INTERACTION_*`-Konstanten in
  `core/src/config.rs` mit Tripwire-Test.
- `core/src/providers/` text (abrain / llamafile_local /
  local_http / cloud_http), stt (**command + whisper_cpp** seit
  PR 27, beide command-basiert; Default bleibt `[command]`),
  tts (command).
- `core/src/settings_store.rs` + `secrets_store.rs` JSON-
  Persistenz pro Achse; Secrets separat 0600.

### IPC

- 34 Incoming-Commands (inkl. PR 17 `approval_approve` /
  `approval_deny` / `request_approval_demo`, PR 18
  `plan_demo_action`, PR 19 `audit_recent`).
- 24 Outgoing-Envelopes (inkl. PR 14 `speaking_started` /
  `speaking_ended`, PR 17 `risk` / `source`-Felder additiv, PR 19
  `audit_recent`). `action_progress` ist reserviert, wird heute
  nicht emittiert.

### UI

- 3 Autoloads (EventBus / IpcClient / MCPRuntime).
- 9 Scenes (Avatar, Utterance, Workflow-Overlay-alt, Workflow-
  Visibility-Panel, Approval-Card, Audit-Panel, Settings-Shell,
  Dev-Controls, Main).
- Behavioral Expression Layer v1 (PR 15) als Multiplier-/Tint-
  Patch oberhalb der bestehenden Avatar-State-Maschine.
- Workflow Visibility Overlay v1 (PR 16) linear über acht
  Schritt-Kategorien + `APPROVAL` (PR 17).
- Approval-Card (PR 17) + Dev-only Audit-Panel (PR 19, nur bei
  `SMOLIT_UI_DEV_CONTROLS=1` sichtbar).

### Audio

- TTS/STT nur command-basiert; Provider-Chain existiert mit
  einem Kind (`command`).
- TTS-Lebenszyklus `speaking_started` / `speaking_ended` (PR 14)
  wird vom Avatar und der Utterance-Bubble konsumiert.
- **Kein** Streaming-Audio. **Kein** Phonem-/Lip-Sync.

### Provider / Settings

- 4 Text-Kinds wählbar; `cloud_http` mit Bearer-API-Key aus
  `secrets_store` (0600).
- Settings-Shell (Phase 8c) rendert status-read-only; Schreib-
  pfade gehen über dedizierte IPC-Commands.

### Approval / Gating / Audit

- Approval-Kette für `open_application` (Interaction), für
  `request_approval_demo` und für `plan_demo_action` (alle PR 17 /
  PR 18).
- **Keine** reale Policy-Engine; die Gating-Kette ist verdrahtet,
  aber kein Core-Feature ist dadurch *gesperrt*.
- Audit erfasst IPC-Command-Received, Action-Planned,
  Approval-Requested/Resolved, Action-Started/Completed/Cancelled,
  IPC-Command-Rejected. Ein Core-Restart leert den Store.

### Window / Overlay

- Overlay-MVP (transparent + optional click-through) als opt-in,
  detaillierte Matrix in
  [`docs/linux_window_overlay_architecture.md`](./docs/linux_window_overlay_architecture.md).
- X11-only Always-on-top als eigenständiger opt-in Pfad
  (`SMOLIT_UI_ALWAYS_ON_TOP=1`). Auf GNOME/Wayland ist AOT
  bewusst verweigert.

### Desktop Interaction

- Interaction-Layer-MVP: nur `open_application`. Accessibility-
  Probe + Discovery laufen ehrlich als „unavailable / uncertain"
  bis der AT-SPI-RPC-Spike umgesetzt ist.

---

## 4. Completed Milestones

- **Phase 0 — Core Foundation.** Tokio-Server, Config-Loader,
  Tracing, Cargo-Build.
- **Phase 1 — Voice Interface.** TTS-/STT-Command-Adapter,
  `speak` / `voice` / `audio-status`.
- **Phase 2 — IPC Bridge.** WebSocket-Server, JSON-Protokoll,
  Action-Event-Modell v1, Status-Payload.
- **Phase 3 — Avatar / Presence / UI.** Godot-Projekt, 2D-Avatar-
  MVP, Expanded/Docked-Presence, Compact-Input, Workflow-
  Overlay-Spike, Accessibility-Probe-Spike, Target-Selection,
  Window-Overlay-MVP inkl. AOT-X11-Spezialpfad.
- **Phase 4 — Behavior / Visibility / Approval / Audit.**
  PR 14 (TTS-Lifecycle), PR 15 (Behavioral Expression Layer),
  PR 16 (Workflow Visibility Overlay v1), PR 17 (Approval UX v1),
  PR 18 (Approval-Gated Demo Action Planner), PR 19 (Local Audit
  Trail v1), PR 20 (Docs Reality Check), PR 25 (Policy v0 —
  Approval-Default für echte Interaction Actions).
- **PR 21–30 Stabilization Series.** Zehn PRs in Folge, die
  Sicherheit, Provider-Onboarding, Docs-Hygiene und den
  Einstiegspfad konsolidiert haben: PR 21 (Docs-Follow-ups),
  PR 22 (Wayland-Hostinventur), PR 23 (`focus_window` Reality
  Decision), PR 24 (Smolitux Design Contract ADR — cross-repo),
  PR 25 (Policy v0 — siehe oben), PR 26 (Provider-Onboarding
  UX v1), PR 27 (`whisper_cpp` STT Provider Kind), PR 28
  (`presence_desktop_interaction.md` Reality Trim),
  PR 29 (README / SETUP / `.env.example`), PR 30 (Avatar Render
  Polish Follow-up + `avatar_palette.gd`). Sammelblick:
  [`docs/reviews/PR31_ROADMAP_CHECKPOINT.md`](./docs/reviews/PR31_ROADMAP_CHECKPOINT.md).

Detaillierte PR-Historie: [`docs/reviews/`](./docs/reviews/).

---

## 5. Open Workstreams

Single-Source für offene Punkte:
[`docs/OPEN_WORK.md`](./docs/OPEN_WORK.md).

- **A. Docs & Architecture Hygiene** — PR 20 / 21 / 24 / 28 / 29
  gelandet. PR 31 selbst ist der Checkpoint für die Serie; nächster
  A-Kandidat ist die Workflow-Overlay-Konsolidierungs-Entscheidung
  (siehe §6, PR 33).
- **B. Window / Overlay / Click-through / AOT Reality** — MVP lebt
  (Overlay + Click-through + X11-AOT). PR 22 hat den Dev-Host als
  GNOME/X11 bestätigt; echte Wayland-Compositor-Messung bleibt
  externer Messauftrag ohne Timing.
- **C. Audio Pipeline v2** — STT hat seit PR 27 zwei command-
  basierte Kinds (`command` + `whisper_cpp`); TTS bleibt bei einem
  Kind. Nächster Kandidat: zweites TTS-Kind (PR 34). *Kein*
  Streaming-Audio in Sichtweite.
- **D. Provider / Settings Consolidation** — Provider-Onboarding
  UX v1 gelandet (PR 26); Quick-Action „Use local-first chain"
  verdrahtet; `Add cloud_http` per Design disabled. Nächster
  Kandidat: Settings-Shell-UX-Cleanup nach Onboarding (PR 36).
- **E. Approval / Policy / Tool-Gating** — Policy v0 (PR 25)
  gelandet, Tripwire-Test fix. **Offene Lücke:** Audit-Ring-Buffer
  deckt nur `plan_demo_action`; der reale
  `open_application`-Lifecycle ist nicht auditiert. → PR 32.
- **F. Desktop Interaction Layer** — `focus_window` mit PR 23
  entschieden. Nächster Kandidat ohne Priorität: AT-SPI-RPC-Spike-
  Entscheidung (PR 37).
- **G. Avatar Animation / Stage C Research** — PR 30 gelandet;
  Stage C bleibt Research-Gate. Nächster Kandidat wartet auf
  Token-Export auf der smolitux-ui-Seite (siehe J / PR 35).
- **H. ABrain Native Integration** — heute CLI; native API ist
  Ziel-Zustand. Nächster Kandidat: ADR (PR 39) vor Code.
- **I. Packaging / Release / CI** — README/SETUP/.env.example
  gelandet (PR 29). Nächster Kandidat: minimale CI-Smoke-Linie
  (PR 38); **keine** Packaging-Formate in dieser Stufe.
- **J. Smolitux Design Contract / Cross-Runtime UI Consistency** —
  ADR-0001 gelandet (PR 24), Avatar-Palette (PR 30) als
  Token-Andockpunkt. Smolit-Assistant bleibt Godot-native;
  [smolitux-ui](https://github.com/Modularium/smolitux-ui) bleibt
  Web-/React-Komponentenbibliothek; gemeinsamer Nenner sind Design
  Tokens + Status-Semantik + Accessibility-/Motion-Konventionen.
  Kein React in Godot, kein WebView, keine Core-Abhängigkeit.
  **OceanData** ist Data-Layer und **nicht** Teil dieses
  Workstreams. Nächster Kandidat: Token-Contract-Prep in
  smolitux-ui (PR 35, cross-repo, Docs/Schema only).

---

## 6. Next Mandatory PRs (Vorschlag)

Reihenfolge ist **nicht bindend**, aber navigierbar. Jeder Schritt
bleibt klein; keiner führt eine neue gefährliche Fähigkeit ein,
ohne vorgeschaltete Policy-Verdrahtung.

### 6.1 Gelandet — PR 21–30 Stabilization Series

Zehn PRs in Folge sind gelandet (2026-04-24). Der Sammelblick mit
Closed-Items, Drift-Watchlist und Tabelle steht in
[`docs/reviews/PR31_ROADMAP_CHECKPOINT.md`](./docs/reviews/PR31_ROADMAP_CHECKPOINT.md).
Kurz: PR 21 Docs-Follow-ups, PR 22 Wayland-Hostinventur, PR 23
`focus_window` Reality Decision, PR 24 Smolitux Design Contract
ADR, PR 25 Policy v0, PR 26 Provider-Onboarding UX v1, PR 27
`whisper_cpp` STT Kind, PR 28 Presence Reality Trim, PR 29
README/SETUP/.env.example, PR 30 Avatar Render Polish Follow-up
inkl. `avatar_palette.gd`.

PR 31 selbst ist dieser Roadmap-Checkpoint (Docs-only).

### 6.2 Next Mandatory — PR 32–40 (Vorschlag)

| PR | Workstream | Gegenstand |
| -- | ---------- | ---------- |
| 32 | E | **Audit Coverage für realen `open_application`-Lifecycle.** Ring-Buffer (PR 19) auf die Real-Interaction-Kette ausweiten (planned / approval_requested / approval_resolved / started / step / verification / completed / cancelled); Felder defensiv redacted; Tripwire-Test. Kein Persistenz-Pfad. Schließt die in PR 25 dokumentierte Audit-Lücke. |
| 33 | A | **Workflow-Overlay-Konsolidierungs-Entscheidung.** Entweder Merge der zwei koexistierenden Overlays (Phase 3.1 Spike + PR-16 Visibility Overlay) oder formales Deprecaten des älteren Spike-Pfads. Docs + evtl. Smoke-Update, **keine** neue Feature-Fläche. |
| 34 | C | **Zweites TTS-Kind** (z. B. `piper_http`) analog zu `whisper_cpp`: command-basiert, env-only, Whitelist-Erweiterung, Default bleibt `[command]`. Keine Build-Abhängigkeit, kein Streaming. |
| 35 | J | **Smolitux Token Contract Prep in smolitux-ui.** Cross-Repo-Docs-PR auf [smolitux-ui](https://github.com/Modularium/smolitux-ui): Token-Schema-Vorschlag, Export-Format, Namensraum. **Kein** Export-Build, **kein** Import in Smolit-Assistant. Voraussetzung für einen späteren Token-Spike auf der Assistant-Seite. |
| 36 | D | **Settings-Shell-UX-Cleanup** nach Provider-Onboarding: visuelle Hierarchie, Kollapsierung alter Per-Kind-Editoren, klare Section-Header. Keine neuen IPC-Commands, keine Default-Änderung, kein Auto-Cloud. |
| 37 | F | **Accessibility RPC Spike Decision (AT-SPI read-only).** ADR für einen echten `GetChildren`-Pfad auf Registry-Root; Toolkit-/Wayland-Fragmentierung und Portal-Pfad benennen, entscheiden **vor** Code. |
| 38 | I | **Release/CI Foundation.** Minimale GitHub-Action: `cargo test` + `settings-shell-smoke`. **Kein** Packaging-Format, **keine** Signing-Stufe, **kein** Artifact-Upload in diesem Schritt. |
| 39 | H | **ABrain Native Integration ADR.** API-Scope, Ownership der API-Definition, Migration aus dem CLI-Pfad. Noch kein Code; Entscheidung über Schnittstellen-Besitz kommt vor Implementation. |
| 40 | — | **OceanData Data-Layer Integration ADR** (cross-repo falls nötig). Beschreibt einen *hypothetischen* Anbindungsweg eines Data-Layers an Smolit-Assistant. OceanData bleibt explizit **kein** UI-/Design-System. Nur ADR, keine Implementation. |

---

## 7. Explicitly Deferred

Diese Punkte sind **bewusst nicht** Teil der nahen PR-Reihe; jeder
davon würde eine eigene Design-Entscheidung brauchen:

- **Streaming-Audio / Audio-Timeline.** Kein Code-Pfad heute;
  Phonem- und Lip-Sync sind ausdrücklich Phase-C.
- **Echte Desktop-Automation jenseits `open_application` +
  `focus_window`.** `focus_window` ist per PR 23 als
  template-basierter X11-Backend-Pfad bestätigt (opt-in über
  `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`, Default leer → honest
  `BackendUnsupported`). `type_text` / `send_shortcut` bleiben
  bewusst `BackendUnsupported` im `CommandBackend`; die
  Policy-Baseline (Workstream E / PR 25) schützt die Default-
  Semantik der `allow_*`-Flags, eröffnet aber ausdrücklich kein
  Backend für diese beiden Kinds.
- **AdminBot-Integration / Shell-Zugriff.** Kein Plan.
- **Stage-C-Avatar-Assets / User-Uploads.**
  [`docs/avatar_stage_c_research.md`](./docs/avatar_stage_c_research.md)
  bleibt Research-Gate.
- **Cloud-Provider als Default.** cloud_http existiert als
  opt-in; wird nicht standard-aktiviert.
- **Policy-Engine im „grand design"-Sinn.** Stattdessen Policy v0
  (PR 25, 2026-04-24): Default-Approval-Pfad für
  `open_application`, Tripwire-Test in
  [`core/src/config.rs`](./core/src/config.rs). Keine Regel-Matrix,
  keine rollenbasierte Freigabe.
- **Audit-Persistenz / Audit-Export.** Ring-Buffer bleibt
  in-memory. Ein Persistenz-Pfad braucht eine eigene Security-
  Review (siehe
  [`docs/security/AUDIT_TRAIL.md`](./docs/security/AUDIT_TRAIL.md)).
  Die **Audit-Abdeckung des realen `open_application`-Lifecycles**
  ist eine eigene, kleinere Arbeit (PR 32) — kein Persistenz-Pfad,
  nur Ring-Buffer-Erweiterung.
- **Multi-Seat / Multi-User / kryptografische Signatur.**
- **Emotion-Feld in `response`-Payloads.** Kein Core-Signal heute.
- **Native ABrain-API / Tool-Calls / Streaming-Response.**
  `docs/api.md §5` beschreibt das Ziel; kein Code. Vor Code kommt
  ein ADR (PR 39).
- **Smolitux Token Implementation.** ADR-0001 (PR 24) beschreibt
  den cross-runtime Design-Vertrag. Token-Schema + Export-Pipeline
  entstehen auf [smolitux-ui](https://github.com/Modularium/smolitux-ui)
  (PR 35 als cross-repo Docs-Vorarbeit); ein späterer Token-
  Import-Spike in Smolit-Assistant wäre eigener PR.
- **OceanData-Integration.** OceanData ist Data-Layer /
  Datenplattform im Smolitux-Ökosystem, **keine** UI-Library und
  **kein** Design-System. Heute ohne Berührungspunkt zu
  Smolit-Assistant. Vor Code / Abhängigkeit kommt ein ADR (PR 40).

---

## 8. Quellen / Detailreferenzen

- **IPC-Spezifikation:** [`docs/api.md`](./docs/api.md)
- **UI-Architektur:** [`docs/ui_architecture.md`](./docs/ui_architecture.md)
- **Provider-/Settings-Architektur:**
  [`docs/provider_fallback_and_settings_architecture.md`](./docs/provider_fallback_and_settings_architecture.md)
- **Presence + Desktop-Interaction-Vision:**
  [`docs/presence_desktop_interaction.md`](./docs/presence_desktop_interaction.md)
- **Approval-UX-Prinzipien (PR 17/18):**
  [`docs/security/APPROVAL_UX.md`](./docs/security/APPROVAL_UX.md)
- **Audit-Trail-Prinzipien (PR 19):**
  [`docs/security/AUDIT_TRAIL.md`](./docs/security/AUDIT_TRAIL.md)
- **Linux-Window-/Overlay-Architektur:**
  [`docs/linux_window_overlay_architecture.md`](./docs/linux_window_overlay_architecture.md)
  (plus Teilmessungen in `docs/x11_always_on_top_*.md`,
  `docs/wayland_always_on_top_refusal_results.md`)
- **Avatar-Stage-C-Forschung:**
  [`docs/avatar_stage_c_research.md`](./docs/avatar_stage_c_research.md)
- **Reviews & PR-Historie:**
  [`docs/reviews/`](./docs/reviews/) — Index:
  [`docs/reviews/README.md`](./docs/reviews/README.md), inkl.
  [`PR20_DOCS_REALITY_CHECK.md`](./docs/reviews/PR20_DOCS_REALITY_CHECK.md).
- **Offene Arbeiten (Live-Single-Source):**
  [`docs/OPEN_WORK.md`](./docs/OPEN_WORK.md)
- **Einheitliches Vokabular:**
  [`docs/GLOSSARY.md`](./docs/GLOSSARY.md) — Approval, Audit Trail,
  Workflow-Overlay, Presence, Expression, Action Event,
  Interaction Layer, Provider Chain, Stage C.
