# Smolit AI Assistant — Developer Roadmap

> Stand: 2026-04-24 (nach PR 20 Docs Reality Check). Diese Datei ist
> eine **Roadmap**, kein PR-Changelog. Detailhistorie pro PR lebt in
> [`docs/reviews/`](./docs/reviews/).

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
  Nur `open_application` ist real verdrahtet; `focus_window` /
  `type_text` / `send_shortcut` sind `BackendUnsupported`.
- `core/src/providers/` text (abrain / llamafile_local /
  local_http / cloud_http), stt (command), tts (command).
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

Detaillierte PR-Historie: [`docs/reviews/`](./docs/reviews/).

---

## 5. Open Workstreams

Single-Source für offene Punkte:
[`docs/OPEN_WORK.md`](./docs/OPEN_WORK.md).

- **A. Docs & Architecture Hygiene** — PR 20 (läuft), Nachläufer
  PR 21.
- **B. Window / Overlay / Click-through / AOT Reality** — echte
  Wayland-Compositor-Messungen noch ausstehend.
- **C. Audio Pipeline v2** — zweites STT-/TTS-Kind, *kein*
  Streaming-Audio in Sichtweite.
- **D. Provider / Settings Consolidation** — Default-Ketten-UX,
  cloud_http-Onboarding.
- **E. Approval / Policy / Tool-Gating** — erste echte Gating-
  Verdrahtung (z. B. für `open_application`).
- **F. Desktop Interaction Layer** — `focus_window`-Backend-
  Entscheidung.
- **G. Avatar Animation / Stage C Research** — research-gated.
- **H. ABrain Native Integration** — heute CLI; native API ist
  Ziel-Zustand.
- **I. Packaging / Release / CI** — noch nicht aufgesetzt.
- **J. Smolitux Design Contract / Cross-Runtime UI Consistency** —
  neuer Docs-/ADR-only-Workstream. Smolit-Assistant bleibt Godot-
  native; [smolitux-ui](https://github.com/Modularium/smolitux-ui)
  bleibt Web-/React-Komponentenbibliothek; gemeinsamer Nenner sind
  Design Tokens + Status-Semantik + Accessibility-/Motion-
  Konventionen. Kein React in Godot, kein WebView, keine
  Core-Abhängigkeit. **OceanData** ist Data-Layer und **nicht**
  Teil dieses Workstreams.

---

## 6. Next Mandatory PRs (Vorschlag)

Reihenfolge ist **nicht bindend**, aber navigierbar. Jeder Schritt
bleibt klein; keiner führt eine neue gefährliche Fähigkeit ein,
ohne vorgeschaltete Policy-Verdrahtung.

> **Hinweis:** Die ursprüngliche Tabelle hatte PR 24 als Policy-v0.
> Mit Einfügen des Cross-Repo-ADR als PR 24 verschieben sich die
> Folge-Nummern um eins. *PR numbers may shift after ADR insertion* —
> Reihenfolge und Inhalt der Folge-PRs bleiben identisch.

| PR | Workstream | Gegenstand |
| -- | ---------- | ---------- |
| 21 | A | Docs-Follow-ups aus PR 20: tote Links, `docs/reviews/`-Index, Glossar-Embryo |
| 22 | B | Wayland-Compositor-Live-Messung auf separatem Host |
| 23 | F | `focus_window` Reality Decision — Option 1 bestätigt (template-basierter X11-Backend via `wmctrl -a {name}` bleibt), Details in [`docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`](./docs/reviews/PR23_FOCUS_WINDOW_DECISION.md) |
| 24 | J | Cross-Repo ADR: Smolitux Design Contract (Docs-only, dieser PR; Spiegel-ADR in smolitux-ui). Siehe [`docs/adr/ADR-0001-smolitux-design-contract.md`](./docs/adr/ADR-0001-smolitux-design-contract.md) |
| 25 | E | Policy v0 (2026-04-24, gelandet): `require_confirmation=true` als Default, `open_application` läuft per Default durch die Approval-Kette, `focus_window` bleibt doppeltes Opt-in; Defaults in `core/src/config.rs` als `DEFAULT_INTERACTION_*`-Konstanten mit Tripwire-Test fixiert. Details in [`docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md). |
| 26 | D | Provider-Onboarding-UX: Default-Ketten und cloud_http-First-Run |
| 27 | C | STT-Alternative (z. B. `whisper.cpp`), bleibt command-basiert |
| 28 | A | `presence_desktop_interaction.md` auf Ist-Zustand trimmen |
| 29 | G | Avatar-Render-Polish-Follow-up (rein visuell) |
| 30 | I | README-Build-Setup + erste Install-Doku |
| 31 | A | Glossar fixieren (`Approval`, `Audit`, `Workflow-Overlay`, `Presence`, …) |

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
- **Multi-Seat / Multi-User / kryptografische Signatur.**
- **Emotion-Feld in `response`-Payloads.** Kein Core-Signal heute.
- **Native ABrain-API / Tool-Calls / Streaming-Response.**
  `docs/api.md §5` beschreibt das Ziel; kein Code.

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
