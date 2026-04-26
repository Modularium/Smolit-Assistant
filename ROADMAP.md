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
- 8 Scenes (Avatar, Utterance, Workflow-Visibility-Panel,
  Approval-Card, Audit-Panel, Settings-Shell, Dev-Controls, Main)
  — seit PR 33 ohne den alten Workflow-Overlay-Spike.
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

### CI

- GitHub-Actions-Workflow ([`ci.yml`](./.github/workflows/ci.yml))
  mit `core-test` + `ui-smoke` (PR 38). CI uses pinned + verified
  Godot binary (PR 42): `GODOT_VERSION` + `GODOT_SHA512` hart im
  Workflow, `sha512sum -c` verifiziert den Download, Binary wird
  via `actions/cache@v4` unter `godot-${GODOT_VERSION}` gecached.
  Branch-Protection-Empfehlungen: [`docs/ci/BRANCH_PROTECTION.md`](./docs/ci/BRANCH_PROTECTION.md).

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
  verdrahtet; `Add cloud_http` per Design disabled. Settings-Shell-
  UX-Cleanup gelandet (PR 36): Summary · Details · Safety notes
  strukturieren die drei Provider-Achsen; kein neues IPC, kein
  neues Status-Feld. Kein zwingender D-Kandidat mehr in der nahen
  Reihe.
- **E. Approval / Policy / Tool-Gating** — Policy v0 (PR 25)
  gelandet, Tripwire-Test fix. **Offene Lücke:** Audit-Ring-Buffer
  deckt nur `plan_demo_action`; der reale
  `open_application`-Lifecycle ist nicht auditiert. → PR 32.
- **F. Desktop Interaction Layer** — `focus_window` mit PR 23
  entschieden; Accessibility-RPC-Spike-Decision mit PR 37
  entschieden ([`ADR-0002`](./docs/adr/ADR-0002-accessibility-rpc-readonly.md),
  read-only AT-SPI, Docs/ADR-only). Nächster Kandidat (Future Work,
  nicht priorisiert): FA-1-Spike-Implementation hinter dem
  `accessibility_rpc`-Feature-Flag.
- **G. Avatar Animation / Stage C Research** — PR 30 gelandet;
  Stage C bleibt Research-Gate. Nächster Kandidat wartet auf
  Token-Export auf der smolitux-ui-Seite (siehe J / PR 35).
- **H. ABrain Native Integration** — heute CLI
  (`AbrainCliProvider` via `ABRAIN_CMD`). Native-Pfad-Rahmen
  entschieden (PR 39,
  [`ADR-0003`](./docs/adr/ADR-0003-abrain-native-integration.md),
  Status **Proposed** / Docs-ADR-only): zukünftiger Kind
  `abrain_native` als Zusatz, nicht Ersatz; Default bleibt
  `["abrain"]`; jede Action läuft durch Approval/Policy/Audit.
  Nächster Kandidat (Future Work, nicht priorisiert): FA-1
  Provider-Spike hinter Feature-Flag, FA-2 Cross-Repo-Contract-ADR
  mit ABrain.
- **I. Packaging / Release / CI** — README/SETUP/.env.example
  gelandet (PR 29). Minimale GitHub-Actions-CI gelandet (PR 38,
  [`ci.yml`](./.github/workflows/ci.yml)): Job `core-test`
  (`cargo test`) plus Job `ui-smoke` (Godot 4.6 headless, fünf
  Smokes), beide mit XDG-Isolation gegen stray Dev-Artefakte.
  PR 42 gelandet: SHA512-Verifikation + Binary-Cache für das
  Godot-Binary, plus Branch-Protection-Empfehlungen in
  [`docs/ci/BRANCH_PROTECTION.md`](./docs/ci/BRANCH_PROTECTION.md).
  Nächster Kandidat (Future Work, nicht priorisiert):
  Packaging-Entscheidungs-ADR (`.deb` vs. AppImage vs. Flatpak,
  Signing-Chain) — rein ADR, keine Implementation in der nahen
  Reihe. **Keine** Packaging-Formate, **keine** signierten Releases,
  **kein** Auto-Update in dieser Stufe.
- **J. Smolitux Design Contract / Cross-Runtime UI Consistency** —
  ADR-0001 gelandet (PR 24), Avatar-Palette (PR 30) als lokaler
  Token-Andockpunkt, Smolitux Token Contract v0 gelandet (PR 35,
  cross-repo in smolitux-ui, Docs/Schema only). Smolit-Assistant
  bleibt Godot-native;
  [smolitux-ui](https://github.com/Modularium/smolitux-ui) bleibt
  Web-/React-Komponentenbibliothek; gemeinsamer Nenner sind Design
  Tokens + Status-Semantik + Accessibility-/Motion-Konventionen.
  Kein React in Godot, kein WebView, keine Core-Abhängigkeit.
  **OceanData** ist Data-Layer und **nicht** Teil dieses
  Workstreams. Nächster Kandidat (Future Work, nicht priorisiert):
  Token-Example-Validation- oder Token-Generator-ADR auf
  smolitux-ui-Seite.

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
| 32 | E | Audit Coverage für reale Interaction-Actions (2026-04-24, gelandet): `interaction_open_application` **und** `interaction_focus_window` laufen jetzt durch denselben Audit-Lifecycle wie der Demo-Pfad (IpcCommandReceived → ActionPlanned → ApprovalRequested → ApprovalResolved → ActionStarted → ActionCompleted / ActionCancelled / ActionFailed). Summaries tragen nur den Action-Titel — keine Command-Templates, keine Env-Namen, keine Secrets. Ring-Buffer bleibt in-memory, keine neuen IPC-Commands. Schließt die in PR 25 dokumentierte Audit-Lücke. Details: [`docs/reviews/PR32_AUDIT_INTERACTION_LIFECYCLE.md`](./docs/reviews/PR32_AUDIT_INTERACTION_LIFECYCLE.md). |
| 33 | A | Workflow-Overlay-Konsolidierung (2026-04-24, gelandet, **Option C — Entfernen**): der alte Drei-Knoten-Phase-3.1-Spike (`ui/scripts/workflow_overlay/`, `ui/scenes/workflow_overlay/`, `scripts/workflow_overlay_state_smoke.gd`, zugehörige Dev-Control-Previews, Visual-Action-Staging-Keys) ist komplett aus dem Repo entfernt. Das Workflow Visibility Overlay v1 (PR 16) bleibt die einzige Workflow-UI. Kein neues Feature, keine neuen IPC-Events, keine neue Persistenz. Details: [`docs/reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md`](./docs/reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md). |
| 34 | C | TTS Alternative v1 (2026-04-24, gelandet): `piper` als zweites command-basiertes TTS-Kind unter `SMOLIT_TTS_PIPER_CMD`. Whitelist `[command, piper]`; Default bleibt `["command"]`. Keine Build-Abhängigkeit auf Piper, kein Modell-Manager, kein Runtime-Editor. Speaking-Lifecycle-`provider`-Feld trägt jetzt den realen Kind-Namen statt hardcodiert `command`. Keine neuen IPC-Commands. |
| 35 | J | **Smolitux Token Contract Prep in smolitux-ui** (2026-04-24, gelandet, **Docs/Schema only**): Token Contract v0 liegt cross-repo in [`smolitux-ui docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md) — Kategorien, Naming-Regeln (lowercase dot-path, runtime-neutral), Value-Types, Pflicht-Semantic-/State-Tokens, Export-Target-Katalog, Versionierung und Validator-Erwartungen. Non-authoritatives Beispiel unter `docs/design/examples/smolitux.tokens.example.json`. **Keine** Token-Implementation, **kein** Generator, **kein** Style Dictionary, **kein** Export-Build, **kein** Import in Smolit-Assistant, **keine** `@smolitux/*`-Paketänderung, **keine** OceanData-Berührung. In Smolit-Assistant selbst: ADR-0001 verlinkt den Token Contract, `ui_architecture.md` markiert `avatar_palette.gd` explizit als lokalen Andockpunkt (kein Token-Consumer). |
| 36 | D | **Settings-Shell-UX-Cleanup** (2026-04-24, gelandet): Text / STT / TTS folgen derselben dreiteiligen Lesereihenfolge **Summary · Details · Editoren**. Summary benennt `Primary (intended)` (chain[0]), `Active (running)`, `Availability`, `Local / Cloud` in eigenen Zeilen — Fallback-Fälle werden so beim ersten Blick sichtbar. Privacy-Section bekommt einen expliziten `— Safety notes —`-Block (Opt-in cloud, Secrets nie angezeigt, env-only `SMOLIT_STT_WHISPER_CPP_CMD` / `SMOLIT_TTS_PIPER_CMD`, Probes side-effect-frei). Text-Chain-Editor bekommt eine Note, die cloud_http als Opt-in ausweist. **Keine** neuen IPC-Commands, **keine** neuen `StatusPayload`-Felder, **keine** Core-Änderung, **keine** Default-Änderung — Smoke-Guard gegen neue IPC-Helfer im Controller hält das live. Details: [`docs/provider_fallback_and_settings_architecture.md`](./docs/provider_fallback_and_settings_architecture.md) §13. |
| 37 | F | **Accessibility RPC Spike Decision (AT-SPI read-only)** (2026-04-24, gelandet, **Docs/ADR-only**): [`ADR-0002`](./docs/adr/ADR-0002-accessibility-rpc-readonly.md) entscheidet den Rahmen vor Code. Read-only `GetChildren` auf Registry-Root; `atspi`+`zbus` hinter einem `accessibility_rpc`-Feature-Flag (default-off); **keine** Input-Injection, **kein** `DoAction`, **kein** Baum-Walk über eine Tiefe hinaus, **keine** Passwort-/Secret-Felder, **keine** Wayland-Compositor-Aktion, **kein** Approval-Bypass. `confidence: verified` bleibt exklusiv für Items mit Registry-Evidenz — Hint-Echos bleiben `discovered`. Wire-Schema (`docs/api.md` §2.8) unverändert, keine neuen IPC-Commands. |
| 38 | I | **Release/CI Foundation** (2026-04-24, gelandet): GitHub-Actions-Workflow [`ci.yml`](./.github/workflows/ci.yml) mit zwei Jobs — `core-test` (`cargo test --manifest-path core/Cargo.toml --locked` auf `ubuntu-latest`, Rust stable) und `ui-smoke` (Godot 4.6 headless, pinned via `GODOT_VERSION`, fünf Smokes: `settings-shell-smoke`, `avatar-render-polish-smoke`, `workflow-visibility-smoke`, `approval-card-smoke`, `audit-panel-smoke`). Beide Jobs laufen mit `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` unterhalb `runner.temp` — damit sind stray `~/.config/smolit-assistant/`-Dev-Artefakte strukturell ausgeschlossen. Lokaler Parity-Helper: [`scripts/ci_verify.sh`](./scripts/ci_verify.sh). **Kein** Packaging-Format, **keine** Signing-Stufe, **kein** Artifact-Upload, **kein** Release-Tagging, **kein** Docker-Image, **keine** Secrets, **keine** Provider-Endpunkte, **keine** echten TTS/STT-Binaries. |
| 39 | H | **ABrain Native Integration ADR** (2026-04-24, gelandet, **Docs/ADR-only**, Status **Proposed**): [`ADR-0003`](./docs/adr/ADR-0003-abrain-native-integration.md) fixiert den Rahmen vor Code. Native-Pfad kommt als **zusätzlicher** Text-Provider-Kind (Arbeitsname `abrain_native`, Default-Chain bleibt `["abrain"]`), nicht als Ersatz; typed request/response; lokal-first (Unix-Socket / Loopback); jede ABrain-induzierte Action läuft durch Approval/Policy/Audit (PR 25 / PR 19 / PR 32); **kein** AdminBot-/Shell-/Desktop-Bypass, **kein** Streaming, **keine** Tool-Call-Execution in der ersten Version, **kein** Cloud-Default, **keine** Änderung an `ABRAIN_CMD`. Status bleibt Proposed, bis ABrain-Seite einen Gegenvorschlag publiziert hat. |
| 40 | K | **OceanData Data-Layer Integration ADR** (2026-04-24, gelandet, **Docs/ADR-only**, Status **Proposed**): [`ADR-0004`](./docs/adr/ADR-0004-oceandata-data-layer-integration.md) formt aus der bisherigen rein-negativen Abgrenzung einen aktiven Designrahmen. OceanData ist **Data-/Kontext-Provider** (nicht Text-LLM); erste Integration ist **read-only** (`query_context` / `list_available_contexts` / `fetch_context_summary`), lokal-first (Unix-Socket / Loopback), **kein** Cloud-Default, **kein** UI-Komponentenimport, **kein** Token-/Design-System-Bezug, **kein** Tool-/Desktop-/AdminBot-Bypass. Jede daraus abgeleitete Action läuft durch Approval/Policy/Audit (PR 25 / PR 19 / PR 32). ABrain bekommt **keinen** unrestrictierten OceanData-Zugriff — nur indirekt, als redacted Summary über den Core. Privacy-/Redaction-Layer ist bindende Voraussetzung vor externer Weitergabe. **Keine** Code-Änderung, **keine** IPC-Commands, **keine** Persistenz, **keine** Auth-Implementation. Nachbar-ADRs: ADR-0001 (Smolitux Design Contract), ADR-0003 (ABrain Native). |
| 42 | I | **CI Hardening — checksum + branch protection docs** (2026-04-25, gelandet): `.github/workflows/ci.yml` pinnt `GODOT_SHA512` aus der upstream-publizierten `SHA512-SUMS.txt` und verifiziert den Godot-Download per `sha512sum -c` fail-fast; parallel cached `actions/cache@v4` das Binary unter `godot-${GODOT_VERSION}` (Single-Key, kein Multi-Version-Scheme). Neue Branch-Protection-Doku [`docs/ci/BRANCH_PROTECTION.md`](./docs/ci/BRANCH_PROTECTION.md) listet Required checks `core-test` + `ui-smoke`, Required review 1, dismiss stale approvals, linear history empfohlen, **keine** Auto-merge, **keine** Required deployments, **keine** Merge-Queue. **Kein** Release-System, **kein** Packaging, **kein** Docker, **kein** Signing, **kein** Dependabot, **keine** Matrix, **kein** Rust-Toolchain-Pinning. |
| 43 | H | **ABrain Native Contract Draft Link** (2026-04-25, gelandet, **Docs-only**): ADR-0003 (PR 39) verlinkt zusätzlich den ABrain-seitigen Vertrags-Entwurf [`docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md) (Status: Draft / Proposed) und macht den Spiegel zwischen Smolit-Assistant ADR und ABrain-seitigem Cross-Repo-Contract sichtbar. Keine Code-Änderung, kein Provider-Kind, keine Wire-Implementation; ABrain-Repo wird in diesem PR nicht angefasst. |
| 44 | A | **Ecosystem Integration Contracts Matrix** (2026-04-25, gelandet, **Docs-only**): zentraler Index [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) für alle Cross-Repo-Integrationsgrenzen (Smolit-Assistant ↔ ABrain / AdminBot / OceanData / smolitux-ui sowie ABrain ↔ AdminBot, ABrain ↔ OceanData, AdminBot ↔ OceanData, OceanData ↔ smolitux-ui). Jede Zeile verweist auf die **kanonische** Vertragsquelle (egal in welchem Repo) und benennt explizite Lücken: Smolit-Assistant ↔ AdminBot ist *missing by design*, AdminBot ↔ OceanData ist *deferred*, ABrain ↔ OceanData ist asymmetrisch (kanonisch in OceanData), AdminBot-Doku trägt Naming-Drift Agent-NN ↔ ABrain. **Index existing contracts, do not duplicate them** — ABrain, Smolit_AdminBot, OceanData und smolitux-ui werden nicht angefasst. **Keine** Code-Änderung, **keine** API-Spec, **keine** Provider-Kinds, **keine** IPC-Erweiterung, **keine** Token-Implementation. Companion: [`docs/contracts/README.md`](./docs/contracts/README.md). |

### 6.3 Contract-Serie PR 45–48 + Roadmap-Sync PR 49

Aus den expliziten Lücken in PR 44 sind **vier** docs/ADR-Folge-PRs
entstanden (PR 45 + 46 + 47 + 48); PR 49 ist der Roadmap-Sync nach
der Serie. Reihenfolge der tatsächlichen Sequenz, nicht der
ursprünglich vorgeschlagenen — siehe
[`docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md`](./docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md)
für die vollständige Reality-Check-Form.

| PR | Workstream | Gegenstand |
| -- | ---------- | ---------- |
| 45 | E | **AdminBot Safety Boundary ADR** (2026-04-25, gelandet, **Docs/ADR-only**, Status **Proposed**): [`ADR-0005`](./docs/adr/ADR-0005-adminbot-safety-boundary.md) fixiert den Smolit-Assistant ↔ AdminBot Safety-Boundary-Rahmen vor Code. Kernlinien: read-only / status-first (`adminbot_status` first; `system.status` / `system.health` / `describe_capabilities` / dry-run); capability-whitelisted (kein freier Argument-String, kein generischer Tool-Passthrough); **kein** Shell-Pfad; **kein** AdminBot-Kommando aus Natural Language ohne deterministisches Capability-Mapping; Approval-Default = true für jede Mutation; Audit-Lifecycle wie bestehender Ring-Buffer plus Capability-Marker; Audit Correlation ID sobald cross-repo Spec existiert; lokal-first (Unix-Socket / Loopback), Cloud/Remote out-of-scope; default-off; **kein** Bypass via ABrain-`action_intents`; **kein** Backdoor für `type_text` / `send_shortcut` / Wayland-`focus_window`; **kein** AdminBot ↔ OceanData Shortcut. Begleitend: ADR-Index aktualisiert, [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) Pair 3 trägt jetzt ADR-0005 als kanonischen Smolit-Assistant-seitigen Verweis (Status weiterhin **not implemented**). **Keine** Code-Änderung, **kein** AdminBot-Client, **kein** neuer Provider-Kind, **kein** IPC, **keine** Änderung am AdminBot-Repo. |
| 46 | E | **Audit Correlation ID + Capability Vocabulary** (2026-04-25, gelandet, **Docs/Contract-only**, Status **Draft / Proposed**): zwei cross-repo Vertragsentwürfe für die in PR 44/PR 45 markierten Lücken liegen jetzt im Repo vor. [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](./docs/contracts/AUDIT_CORRELATION_ID_SPEC.md) fixiert Format (`corr_<ulid-or-uuid-v7>`, lowercase, ≤ 80 Zeichen), Lebenszyklus, Propagationspunkte (IPC-Command → `action_planned` → `approval_*` → `action_started/completed/failed/cancelled` → Audit), cross-repo Erwartungen (Smolit-Assistant erzeugt; ABrain echoed; AdminBot fail-closed bei Mutation; OceanData should-accept; smolitux-ui keine Runtime-Rolle), Privacy/Sanitization-Regeln und sieben benannte Failure-Modes. [`docs/contracts/CAPABILITY_VOCABULARY.md`](./docs/contracts/CAPABILITY_VOCABULARY.md) fixiert Naming-Regeln (`category.subcategory.action`, lowercase dot-path, runtime-neutral), sechs Kategorien (`interaction.*` / `admin.*` / `data.*` / `assistant.*` / `provider.*` / `audit.*`), initiales Vokabular mit Mappings auf bestehende Smolit-Assistant-Code-Identitäten ([`InteractionKind`](./core/src/interaction/action.rs), Demo-Plan-Kinds, Provider-Pipeline, `audit_recent`) sowie zukünftige AdminBot-/OceanData-Surfaces, Risk-Levels (`low`/`medium`/`high`) als kanonische Lesart und 14 Pflicht-Metadaten-Felder pro Capability. Begleitend: [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) §6 *Explicit gaps* + §12 *Future work* aktualisiert; ADR-0005 FA-2/FA-3 mit Links versehen. **Keine** Code-Änderung, **kein** neues Feld in `AuditEvent`/Action-Events/IPC-Wire, **keine** Runtime-Registry, **keine** OpenTelemetry-Integration, **keine** Audit-Persistenz, **keine** Änderung an ABrain/Smolit_AdminBot/OceanData/smolitux-ui. Implementation bleibt aufgeschoben hinter eigenen Folge-PRs (siehe AUDIT_CORRELATION_ID_SPEC §12 + CAPABILITY_VOCABULARY §12). |
| 47 | E | **AdminBot Capability Contract** (2026-04-25, gelandet, **Docs/Contract-only**, Status **Draft / Proposed**): [`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`](./docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md) schließt ADR-0005 §14 FA-1 auf Doku-Ebene. Vier Initial-Klassen (`admin.status.read`, `admin.capability.describe`, `admin.action.dry_run`, `admin.action.execute`); 13-Eintrags-Deny-Baseline (`admin.shell.execute`, `admin.sudo.execute`, `admin.filesystem.write_unscoped`, `admin.secret.read`, `admin.network.exfiltrate`, `admin.process.kill_unscoped`, `admin.service.restart_unscoped`, `admin.package.install_unscoped`, `admin.user.modify`, `admin.auth.modify`, `admin.backup.delete`, `admin.audit.clear`, `admin.policy.disable`); 15 Pflichtfelder pro Capability-Eintrag (`contract_version`, `capability_id`, `capability_name`, `risk_level`, `allowed_arguments_schema`, `denied_arguments`, `dry_run_supported`, `approval_required`, `audit_required`, `correlation_id_required`, `timeout_ms`, `rollback_supported`, `side_effects`, `operator_visible_summary`, `failure_modes`); 15 benannte Failure-Modes inkl. `correlation_missing` / `dry_run_required` / `rollback_unavailable`; vier JSON-Beispiele (drei akzeptierte Klassen + ein abgelehntes `admin.shell.execute`). Begleitend: ADR-0005 FA-1 mit Link versehen, Matrix Pair 3 + §6 *Explicit gaps* + §5 *Existing canonical documents* aktualisiert, contracts/README ergänzt. **Keine** Code-Änderung, **kein** AdminBot-Client, **keine** Capability-Konstanten in `core/`, **keine** IPC-Erweiterung, **keine** Runtime-Registry, **keine** Änderung am AdminBot-Repo, **keine** echten Service-Namen oder Shell-Kommandos in Beispielen. Implementation bleibt aufgeschoben hinter eigenen Folge-PRs (siehe ADMINBOT_SAFETY_BOUNDARY_CONTRACT §17 AC-1…AC-7). |
| 48 | K | **OceanData Context Provider SPI ADR** (2026-04-25, gelandet, **Docs/ADR-only**, Status **Proposed**): [`ADR-0006`](./docs/adr/ADR-0006-oceandata-context-provider-spi.md) schließt ADR-0004 §11 FA-2 auf Doku-Ebene. Context-Provider-Achse parallel zu Text/STT/TTS (kein Eintrag in `KNOWN_TEXT_KINDS`); Kandidaten-Kinds `local_static_context` / `oceandata_context`; Kandidaten-Operationen `list_available_contexts` / `query_context` / `fetch_context_summary` / `inspect_context_item_metadata`; ProviderConfig-Form (`enabled` default `false`, `transport` ∈ `unix` / `loopback_http`, `auth_mode` ∈ `local_peer` / `bearer`, `max_items_default`, `max_summary_chars`, `allow_sensitive` / `allow_external_forwarding` default `false`); ContextQueryRequest/Response-Form mit `contract_version`, `request_id`, optionaler `correlation_id`, `redaction = local_only` / `external_safe`, strukturierte `provenance`; Capability-Mapping auf `data.context.query` / `data.context.summary` / `data.decide.access`; 13 benannte Failure-Modes inkl. `context_scope_not_allowed` / `sensitivity_not_allowed` / `provenance_missing` / `too_many_results` / `redaction_required` / `external_forwarding_denied`; Audit-Felder (`provider_kind`, `context_scope`, `purpose`, `result_count`, `sensitivity_max`, `used_for_action`, `external_forwarding`); ABrain bekommt OceanData-Kontext **nur** bounded/redacted **über** Smolit-Assistant; AdminBot ↔ OceanData direkter Pfad explizit deferred. Begleitend: ADR-0004 FA-2 mit Link versehen, Matrix Pair 4 + Pair 5 aktualisiert, CAPABILITY_VOCABULARY §5.4 + AUDIT_CORRELATION_ID_SPEC §7 verlinken ADR-0006. **Keine** Code-Änderung, **keine** Eintrag in `KNOWN_TEXT_KINDS`, **kein** ContextProvider-Trait, **kein** neuer Provider-Kind, **kein** neuer IPC-Command, **keine** OceanData-Repo-Änderung, **keine** Privacy-/Redaction-Implementation, **keine** Vector-DB-Exposition, **keine** Sync-/Write-Operationen, **kein** Cloud-/Remote-Default. Implementation bleibt aufgeschoben hinter eigenen Folge-PRs (siehe ADR-0006 §17 OC-1…OC-7). |
| 49 | A | **Roadmap Sync after Contracts PR 43–48** (2026-04-25, gelandet, **Docs-only**): Reality-Check-Review unter [`docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md`](./docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md). Synchronisiert ROADMAP, OPEN_WORK und Reviews-Index nach der PR-43–48-Contract-Serie. Korrigiert Drift: §6.3-Header zählte „drei Folge-PRs", real waren es vier (PR 45 + 46 + 47 + 48); OPEN_WORK Workstream I trug noch „PR 48 — Release Packaging Decision ADR" (jetzt verschoben hinter die Code-Spike-Reihe); §6.4 setzt die neue PR-50–55-Sequenz (konservativ — Docs/ADR vor Code: PR 50 Release Gate Review, PR 51 Packaging ADR, PR 52 Accessibility RPC FA-1, PR 53 Correlation ID Runtime, PR 54 Capability Constants Runtime, PR 55 OceanData Privacy/Redaction ADR). Runtime-Baseline durch PR 43–48 unverändert: kein `abrain_native` / `oceandata_context` / AdminBot-Adapter; `correlation_id` und `capability_id` weiter nicht im Code; `KNOWN_TEXT_KINDS` unverändert; `cargo test` 398 passed; `settings-shell-smoke` PASS. **Keine** Code-Änderung, **keine** ADR-Neuanlage, **keine** Contract-Neuanlage, **keine** IPC-/Provider-/UI-Änderung, **keine** Änderung an ABrain / Smolit_AdminBot / OceanData / smolitux-ui. |

### 6.4 PR 50 + Folge-PRs nach v0.2-Gate (nicht bindend, ohne Termin)

Konservative Reihenfolge — Docs/ADR vor Code; Begründung in
[`docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md` §6](./docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md).

| PR | Workstream | Gegenstand |
| -- | ---------- | ---------- |
| 50 | A | **v0.2 Release Gate Review** (2026-04-25, gelandet, **Docs-only**): Reality-Check unter [`docs/reviews/PR50_V0_2_RELEASE_GATE_REVIEW.md`](./docs/reviews/PR50_V0_2_RELEASE_GATE_REVIEW.md). Bewertung: **conditionally ready for v0.2 candidate** nach vier Verifikations-/Konfigurations-Punkten (GitHub-CI grün auf main, README/SETUP-Befehle korrekt, ROADMAP/OPEN_WORK keine Runtime-Drift, Branch-Protection konfiguriert oder dokumentiert). Lokal: `cargo test` 398 passed; alle fünf CI-Smokes (`settings-shell-smoke`, `avatar-render-polish-smoke`, `workflow-visibility-smoke`, `approval-card-smoke`, `audit-panel-smoke`) PASS. PR 43–48 haben Runtime-State **nicht** verändert; alle ADR/Contract-Drafts sind als Future gerahmt. **Kein** Tag, **kein** Version-Bump, **kein** Packaging in diesem PR — PR 50 ist ein Gate, kein Release. |
| 51 | I | **v0.2 Gate Fix: CI Workflow + SETUP Smoke Drift + XDG-Isolation** (2026-04-26, gelandet, **Docs/CI-Fix-only**): [`docs/reviews/PR51_V0_2_GATE_FIX.md`](./docs/reviews/PR51_V0_2_GATE_FIX.md). Behebt drei reale Gate-Blocker, die der PR-50-Check zutage gefördert hat. (1) `.github/workflows/ci.yml` Zeile 98: `${{ env.GODOT_VERSION }}` im job-level `name:` ist laut GitHub-Actions-Context-Availability-Regeln ungültig — Job-Name ist auf `Godot 4.6-stable headless` hardcoded; alle anderen `env.GODOT_VERSION`-Verwendungen (step-level `name:`, `with.key`, Shell-Steps) bleiben dynamisch. (2) `docs/SETUP.md §2.4` zitierte den seit PR 33 entfernten Smoke-Case `workflow-state-smoke`; ersetzt durch `workflow-visibility-smoke` mit explizitem Verweis auf PR 33. (3) Plain `cargo test --manifest-path core/Cargo.toml` kann lokale Persistenz unter `~/.config/smolit-assistant/text_chain.json` lesen und reproduziert ohne Isolation 396 / 2 fail; mit `scripts/ci_verify.sh core` (XDG-isoliert) sind 398 Tests grün. README + SETUP empfehlen jetzt `scripts/ci_verify.sh core` als kanonischen Gate-Befehl, plain `cargo test` bleibt als schnellere Dev-Iteration mit Drift-Hinweis dokumentiert. `scripts/ci_verify.sh` und der `Configure XDG isolation`-Step im CI-`core-test`-Job exportieren zusätzlich `XDG_DATA_HOME` für künftige Persistenz-Locations; `HOME` bleibt unverändert (rustup/cargo-Toolchain). **Keine** Runtime-Code-Änderung, **kein** neues Feature, **kein** Provider-Kind, **kein** IPC, **kein** Release-Tag, **kein** Version-Bump, **keine** ABrain/AdminBot/OceanData/smolitux-ui-Änderung. Verbleibend bis v0.2-Tag: GitHub-CI grün auf main nach Merge, Branch-Protection konfiguriert, Operator-Approval. |
| 52 | I | **Packaging Decision ADR** (Vorschlag, Docs/ADR-only): `.deb` vs. AppImage vs. Flatpak, Signing-Chain, Auto-Update-Linie. ADR vor Code. **Keine** Implementation. *(Zweifach verschoben — ehemals PR 48 vor PR 49 Sync, dann PR 51 nach PR 49 Sync, nun PR 52 weil PR 51 die Gate-Fix-Position eingenommen hat; siehe PR 51 Review §6.)* |
| 53 | F | **Accessibility RPC FA-1 Spike** (Vorschlag, Code-Spike, default-off): Erster Code-Eintritt für [`ADR-0002`](./docs/adr/ADR-0002-accessibility-rpc-readonly.md) FA-1 — read-only `GetChildren` auf Registry-Root hinter `accessibility_rpc`-Feature-Flag. **Kein** `DoAction`, **keine** Input-Injection, **kein** Tree-Walk über eine Tiefe hinaus, **kein** Approval-Bypass. |
| 54 | E | **Correlation ID Runtime Spike** (Vorschlag, Code-Spike, default-off): `correlation_id`-Feld in `AuditEvent` hinter Feature-Flag, additiv. Implementation-Eintritt für [AUDIT_CORRELATION_ID_SPEC §12 FA-1](./docs/contracts/AUDIT_CORRELATION_ID_SPEC.md). **Keine** Wire-Pflicht, **kein** Cross-Repo-Echo, **kein** fail-closed-Verhalten in v1. |
| 55 | E | **Capability Constants Runtime Spike** (Vorschlag, Code-Spike, additiv): `pub const`-String-Konstanten für die heute live Capabilities (`interaction.*` / `assistant.*` / `provider.*` / `audit.*`) plus Validation-Tests. **Keine** Runtime-Registry-Datenstruktur, **keine** Policy-Engine. Implementation-Eintritt für [CAPABILITY_VOCABULARY §12 FA-1](./docs/contracts/CAPABILITY_VOCABULARY.md). |
| 56 | K | **OceanData Privacy / Redaction ADR** (Vorschlag, Docs/ADR-only): Eintrittsbedingung für `redaction = external_safe` aus [ADR-0006 §10](./docs/adr/ADR-0006-oceandata-context-provider-spi.md) + [ADR-0004 FA-5](./docs/adr/ADR-0004-oceandata-data-layer-integration.md). **Keine** Implementation, **kein** Provider-Kind, **kein** IPC. |

### 6.5 v0.2 Release Gate

> **Status (2026-04-26):** *Gate fix in progress; not yet ready
> for v0.2 candidate.* PR 50 hatte „conditionally ready"
> empfohlen; der reale Gate-Check zog drei Blocker, die in PR 51
> gefixt sind (CI-Workflow YAML-Validität, SETUP-Smoke-Drift,
> plain `cargo test` Host-Config-Drift). Vor einem `v0.2`-Tag
> müssen folgende Punkte zusätzlich grün sein:
>
> 1. **GitHub Actions auf `main` grün** nach Merge von PR 51
>    (PR 51 fixt die zuvor invalide YAML; ein erfolgreicher
>    `core-test` + `ui-smoke` Run kann erst nach Push beobachtet
>    werden).
> 2. **Branch-Protection für `main`** gemäß
>    [`docs/ci/BRANCH_PROTECTION.md`](./docs/ci/BRANCH_PROTECTION.md)
>    konfiguriert (Required checks `core-test` + `ui-smoke`,
>    Required review 1, dismiss stale approvals, linear history).
> 3. **Operator-Approval für den Tag selbst** — kein Auto-Tag.
>
> **Kanonischer Gate-Befehl lokal:** `scripts/ci_verify.sh core`
> (XDG-isoliert, 398 Tests). **Kanonischer Smoke-Befehl:**
> `scripts/ci_verify.sh smokes`. Plain `cargo test` ist für
> schnelle Dev-Iteration okay, aber **nicht** für Gate-Checks —
> persistierte Settings unter `~/.config/smolit-assistant/`
> können IPC-Tests verfälschen (siehe PR 51 §2.3).
>
> **Nicht-Blocker für v0.2:** ABrain Native Integration, AdminBot
> Integration, OceanData Integration, `correlation_id` /
> `capability_id`-Runtime, Accessibility RPC FA-1, Packaging,
> Persistent Audit, Token-Implementation, Wayland-AOT,
> `type_text` / `send_shortcut`-Backends. Code-Spikes (PR 53 /
> 54 / 55) entstehen **nach** dem v0.2-Tag, nicht davor.
>
> **Kein Tag wird in PR 51 gesetzt.** Ein zukünftiger Release-PR
> setzt den Tag, sobald die drei Bedingungen oben erfüllt sind
> und ein expliziter Operator-Approval erfolgt. Bis dahin gilt:
> kein Version-Bump im Code, kein `Cargo.toml`-Versionssprung,
> kein GitHub-Release, kein Packaging-Format.

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
  Smolit-Assistant. Rahmen mit PR 40 entschieden
  ([`ADR-0004`](./docs/adr/ADR-0004-oceandata-data-layer-integration.md),
  Proposed, Docs/ADR-only): read-only erster Pfad, lokal-first,
  kein Cloud-Default, kein Tool-Execution-Bypass, kein
  Transit-Pfad ABrain → OceanData. Code weiterhin hinter
  FA-1 (OceanData-side contract doc) und FA-2 (Context-provider
  SPI ADR) aufgeschoben.

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
