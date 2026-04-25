# PR 50 — v0.2 Release Gate Review

- **Datum:** 2026-04-25.
- **Typ:** Docs-only Reality-Check / Release-Gate.
- **Scope:** Honest assessment, ob Smolit-Assistant heute reif für
  einen v0.2-Tag ist. Kein Release, kein Tag, kein Version-Bump,
  kein Packaging — nur eine Entscheidung darüber, **was** vor v0.2
  noch passieren muss.

> Leitprinzip: **Review before release. No release tag before the
> gate is explicit.**

## 1. Scope

PR 43–48 haben eine reine Docs/ADR/Contract-Serie auf den Stack
gelegt; PR 49 hat die Roadmap nach dieser Serie synchronisiert.
Dieses Review fragt, ob **die Code-Realität** auf main für einen
v0.2-Kandidaten reicht — und welche kleinen, ehrlichen Schritte
zwischen heute und einem späteren Tag liegen.

In Scope:

- Aktueller Code- und Feature-Stand auf main.
- Aktueller Doku-Stand (ADR / Contracts / Reviews).
- CI- und Verifikations-Stand.
- Was als „runtime-stabil" gilt, was als „docs-only" bleibt.
- Liste ehrlicher Blocker und ehrlicher Non-Blocker.

Nicht in Scope:

- Ein Tag, ein Release, ein Version-Bump, ein Packaging-Format.
- Code-Änderungen, ADR-Neuanlagen, Contract-Neuanlagen.
- Änderungen an ABrain / Smolit_AdminBot / OceanData / smolitux-ui.

## 2. Current stable baseline

### Core (Rust)

- **WebSocket-IPC-Server** mit JSON-Wire-Format
  (`core/src/ipc/`); Action-Event-Modell v1.
- **Provider-Resolver** für drei Achsen
  (`core/src/providers/`):
  - **Text:** `KNOWN_TEXT_KINDS = [abrain, llamafile_local,
    local_http, cloud_http]`; Default-Chain `["abrain"]`.
  - **STT:** `KNOWN_STT_KINDS = [command, whisper_cpp]`;
    Default-Chain `["command"]`. `whisper_cpp` env-only via
    `SMOLIT_STT_WHISPER_CPP_CMD`.
  - **TTS:** `KNOWN_TTS_KINDS = [command, piper]`;
    Default-Chain `["command"]`. `piper` env-only via
    `SMOLIT_TTS_PIPER_CMD`.
- **Approval-Engine** (`core/src/approvals/`) — Idempotenz über
  `PendingApprovalRegistry`, `risk` ∈ `low` / `medium` / `high`,
  `source` ∈ `user` / `timeout` / `system`,
  `result` ∈ `approved` / `denied` / `cancelled` / `timed_out`.
- **Audit-Ring-Buffer** (`core/src/audit/`) — in-memory,
  Default 100 / Hard 1000 / Env `SMOLIT_AUDIT_MAX_EVENTS`,
  Sanitization für Templates / Env / Secrets.
- **Interaction-Layer** (`core/src/interaction/`) —
  `InteractionExecutor` + `CommandBackend`. Real verdrahtet:
  `open_application` (approval-gated, Policy v0); `focus_window`
  (X11-Template, doppeltes Opt-in
  `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW=1` +
  `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`); `type_text` /
  `send_shortcut` bleiben `BackendUnsupported`.
- **Settings-Store** (`core/src/settings_store.rs`) + **Secret-
  Store** (`core/src/secrets_store.rs`, `0600`).
- **Tripwire-Test** `policy_v0_defaults_are_locked` in
  `core/src/config.rs` schützt Approval-Default-Linie.

### UI (Godot)

- 3 Autoloads (EventBus, IpcClient, MCPRuntime).
- 8 Scenes (Avatar, Utterance, Workflow-Visibility-Panel,
  Approval-Card, Audit-Panel, Settings-Shell, Dev-Controls,
  Main).
- Behavioral Expression Layer v1 (PR 15) als Multiplier-/Tint-
  Patch.
- Workflow Visibility Overlay v1 (PR 16) — der alte
  Drei-Knoten-Spike ist seit PR 33 entfernt.
- Approval-Card (PR 17) + Dev-only Audit-Panel (PR 19, sichtbar
  bei `SMOLIT_UI_DEV_CONTROLS=1`).
- Settings-Shell mit Summary · Details · Safety-notes-Struktur
  (PR 36).

### Docs / ADR / Contracts

- ADR-0001 Smolitux Design Contract (Accepted)
- ADR-0002 Accessibility RPC Read-only (Accepted)
- ADR-0003 ABrain Native Integration Path (Proposed)
- ADR-0004 OceanData Data-Layer Integration Path (Proposed)
- ADR-0005 AdminBot Safety Boundary (Proposed)
- ADR-0006 OceanData Context Provider SPI (Proposed)
- [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](../contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md)
- [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md) (Draft)
- [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md) (Draft)
- [`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`](../contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md) (Draft)

### CI / Verification

- GitHub Actions [`ci.yml`](../../.github/workflows/ci.yml) —
  zwei Jobs (`core-test` + `ui-smoke`); Godot 4.6 headless,
  pinned `GODOT_VERSION` + `GODOT_SHA512`, `actions/cache@v4`.
- Lokaler Parity-Helper [`scripts/ci_verify.sh`](../../scripts/ci_verify.sh).
- Branch-Protection-Doku [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md).

## 3. Implemented runtime capabilities

| Capability / Area | Implemented? | Notes | v0.2 status |
|-------------------|--------------|-------|-------------|
| `abrain` CLI text provider | ✅ | Default-Chain `["abrain"]`; CLI über `ABRAIN_CMD` (Default `abrain`) | runtime-stable |
| `llamafile_local` text provider | ✅ | Lifecycle (idle-timeout, readiness) implementiert | runtime-stable |
| `local_http` text provider | ✅ | Loopback-only, kein Cloud-Default | runtime-stable |
| `cloud_http` text provider | ✅ | Bearer aus `0600`-Secret-Store; opt-in, nie Default | runtime-stable, gated |
| STT `command` | ✅ | Default-Chain | runtime-stable |
| STT `whisper_cpp` | ✅ | env-only via `SMOLIT_STT_WHISPER_CPP_CMD`; PR 27 | runtime-stable, opt-in |
| TTS `command` | ✅ | Default-Chain | runtime-stable |
| TTS `piper` | ✅ | env-only via `SMOLIT_TTS_PIPER_CMD`; PR 34 | runtime-stable, opt-in |
| `speaking_started` / `speaking_ended` | ✅ | PR 14, vom Avatar + Utterance konsumiert | runtime-stable |
| Workflow Visibility Overlay v1 | ✅ | PR 16, einzige Workflow-UI seit PR 33 | runtime-stable |
| Legacy Workflow-Overlay (Phase-3.1-Spike) | ❌ entfernt | PR 33 Option C | n/a |
| Approval-Card (UX v1) | ✅ | PR 17 | runtime-stable |
| Approval-gated Demo-Action-Planner | ✅ Mock-only | PR 18 | runtime-stable, mock |
| `open_application` | ✅ approval-gated | Policy v0 (PR 25) | runtime-stable |
| `focus_window` | ✅ X11-Template, doppeltes Opt-in | PR 23 | runtime-stable, opt-in |
| `type_text` | ❌ `BackendUnsupported` | bewusst | not implemented |
| `send_shortcut` | ❌ `BackendUnsupported` | bewusst | not implemented |
| Wayland Always-on-top | ❌ honest refusal | bestätigt PR 22 | not implemented |
| OCR / Vision / Pixel-Matching | ❌ | nie geplant | not implemented |
| Audit Ring-Buffer (in-memory) | ✅ | PR 19 + PR 32 (Interaction-Lifecycle) | runtime-stable |
| Audit-Persistenz | ❌ | bewusst out-of-scope | not implemented |
| Settings-Shell | ✅ | PR 36 (Summary · Details · Safety-notes) | runtime-stable |
| Provider-Onboarding | ✅ | PR 26 | runtime-stable |
| Accessibility-Probe (env-basiert) | ✅ | siehe ADR-0002 | runtime-stable |
| Accessibility RPC FA-1 (`atspi+zbus`) | ❌ | ADR-0002 Future Work | not implemented |
| ABrain Native Integration (`abrain_native` Provider) | ❌ | ADR-0003 Proposed | not implemented |
| AdminBot Integration (jeglicher Pfad) | ❌ | ADR-0005 + ADMINBOT_SAFETY_BOUNDARY_CONTRACT Draft | not implemented |
| OceanData Integration (jeglicher Pfad) | ❌ | ADR-0004 + ADR-0006 Proposed | not implemented |
| `correlation_id` Wire/Runtime | ❌ | AUDIT_CORRELATION_ID_SPEC Draft, nicht im Code | not implemented |
| `capability_id` Code-Konstante | ❌ | CAPABILITY_VOCABULARY Draft, nicht im Code | not implemented |
| Token-Implementation (Smolitux Token Contract) | ❌ | cross-repo Schema-only | not implemented |
| Packaging (`.deb` / AppImage / Flatpak) | ❌ | Future, eigener ADR (PR 51 Vorschlag) | not implemented |
| Release-Tagging / signierte Releases / Auto-Update | ❌ | bewusst out-of-scope für v0.2 | not implemented |

`grep` Bestätigungen aus `core/`:

- `correlation_id` → leer.
- `capability_id` → leer.
- `abrain_native` → leer.
- `oceandata_context` → leer.
- `adminbot_*` → leer (außer als Doku-Begriff).

## 4. Docs / ADR / Contract baseline

Alles aus §2 ist auf main vorhanden und konsistent. PR 49 hat die
Roadmap-Drift („drei" → „vier" Folge-PRs aus PR 44; OPEN_WORK
PR-48-Eintrag verschoben) bereits geheilt. ADR-0001…ADR-0006 und
die vier Contract-Dokumente sind durchgängig miteinander
verlinkt; OceanData ist nirgends als UI-Library/Token-Quelle/LLM
beschrieben, smolitux-ui nirgends als Data-Layer.

## 5. CI / verification baseline

| Check | Ergebnis |
|-------|----------|
| `cargo test --manifest-path core/Cargo.toml --locked` | **398 passed; 0 failed** |
| `scripts/run_overlay_verification.sh settings-shell-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh avatar-render-polish-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh workflow-visibility-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh approval-card-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh audit-panel-smoke` | **PASS** |
| `ci.yml` Required jobs | `core-test` + `ui-smoke` (fünf Smokes oben) |
| Godot binary verification | `GODOT_SHA512` pinned, `sha512sum -c` fail-fast |
| Branch-Protection-Empfehlungen | dokumentiert in [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md) |

Lokal-Run mit isoliertem `HOME` / `XDG_CONFIG_HOME` /
`XDG_CACHE_HOME` / `XDG_DATA_HOME` analog CI; ohne Isolation
würden lokale Dev-Konfigs (`~/.config/smolit-assistant/text_chain.json`)
zwei IPC-Tests stören.

## 6. Explicit non-runtime future work

Diese Punkte sind als ADR/Contract gerahmt, aber **nicht im
Code**. v0.2 muss sie sichtbar als Future markieren — sie sind
**keine** Bestandteile, die ein Tag impliziert:

- **ABrain Native Integration** — ADR-0003. Heute weiterhin
  CLI-only via `ABRAIN_CMD`.
- **AdminBot Safety Boundary + Capability Contract** — ADR-0005
  + ADMINBOT_SAFETY_BOUNDARY_CONTRACT. Kein AdminBot-Adapter,
  keine `admin.*`-Capability-Konstanten.
- **OceanData Data-Layer + Context Provider SPI** — ADR-0004 +
  ADR-0006. Kein `oceandata_context`-Provider, kein
  ContextProvider-Trait, keine OceanData-IPC.
- **Audit Correlation ID** — Spec Draft. Kein Feld in
  `AuditEvent` / Action-Events / IPC-Wire.
- **Capability Vocabulary** — Spec Draft. Keine Code-Konstanten,
  keine Runtime-Registry.
- **Accessibility RPC FA-1** — ADR-0002 Future Work.
- **Packaging Decision ADR** — Future, PR 51 Vorschlag.
- **Privacy / Redaction Layer** — Future, PR 55 Vorschlag.

## 7. v0.2 blocker assessment

### A. Blocker before v0.2

1. **GitHub CI muss auf main grün laufen,** nicht nur lokal. Der
   Tag darf nicht vor einer grünen Action gesetzt werden. (Lokal
   bestätigt grün; remote-Stand ist außerhalb dieses Reviews
   beobachtbar.)
2. **README + SETUP müssen mit den aktuellen Befehlen matchen.**
   Beide nennen heute `cargo test --manifest-path core/Cargo.toml`
   und `scripts/run_overlay_verification.sh …` — diese Pfade
   stimmen mit dem Repo überein. Keine Korrektur in PR 50 nötig.
3. **Keine kritische Doku-Drift zwischen ADR-only und Runtime.**
   PR 44 + PR 49 haben die Drift abgefangen; aktuelle Greps in
   §11 bestätigen, dass `abrain_native` / `oceandata_context` /
   `correlation_id` / `capability_id` nirgends als implementiert
   beschrieben werden.
4. **`cargo test`-Suite und die fünf CI-Smokes müssen grün sein.**
   Lokal grün (§5).
5. **Branch-Protection** muss entweder konfiguriert oder klar als
   manueller Pre-Tag-Schritt dokumentiert sein. Empfehlungen
   liegen in [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md).

### B. Should-fix-if-cheap before v0.2

- **Reviews-Index Drift:** [`docs/reviews/README.md`](./README.md)
  trägt heute keinen `PR36`-Eintrag, obwohl
  `PR36_SETTINGS_SHELL_UX_CLEANUP.md` existiert. Pre-existing,
  klein, kein Blocker.
- **Markdown-Lint-Warnungen** (MD004 / MD060) in
  `docs/contracts/*.md` und `docs/api.md`. Stylistische Drift
  aus PR 44/45/46, keine Inhaltsfehler. Kein Blocker.

### C. Not blocking v0.2

- ABrain Native Integration (FA-1+).
- AdminBot Integration jeglicher Stufe.
- OceanData Integration jeglicher Stufe.
- Correlation ID Runtime-Implementation.
- Capability Constants Runtime-Implementation.
- Accessibility RPC FA-1 Spike.
- Packaging Decision ADR.
- Persistent Audit / Audit Export.
- Token-Import-Implementation.
- Wayland Always-on-top reale Unterstützung.
- `type_text` / `send_shortcut`-Backends.
- OCR / Vision / Pixel-Matching.
- Streaming-Audio / Phonem-Lip-Sync.

### D. Explicitly deferred beyond v0.2

Alle Punkte aus
[ROADMAP §7 Explicitly Deferred](../../ROADMAP.md). Diese Liste
verlängert sich durch v0.2 nicht — sie bleibt unverändert.

## 8. Must-fix before v0.2

| # | Punkt | Status heute | Aktion |
|---|-------|--------------|--------|
| 1 | GitHub CI grün auf main | lokal grün; remote nicht in diesem Review beobachtet | Vor Tag prüfen |
| 2 | README/SETUP Befehle korrekt | grün | keine Aktion |
| 3 | Keine Runtime-vs-Docs-Drift | grün (PR 49 hat geheilt) | keine Aktion |
| 4 | `cargo test` + 5 CI-Smokes grün | grün | keine Aktion |
| 5 | Branch-Protection konfiguriert oder dokumentiert | dokumentiert; manuelle Konfiguration nicht reviewbar in diesem PR | Manuell prüfen vor Tag |

## 9. Not blocking v0.2

Siehe §7.C. Der gesamte ADR-/Contract-Stack aus PR 43–48 ist
bewusst dokumentarisch; jeder Punkt darin verlängert die v0.2-
Bedingungen **nicht**. Im Gegenteil: er hält die zukünftige
Erweiterung sicher außerhalb des Tags.

## 10. Release risks / watchlist

- **Risiko: „so viele ADRs, also Code dahinter".** Reviewer
  müssen wissen, dass PR 43–48 keinen Runtime-State verändert
  haben. Diese Datei hier ist Teil der Antwort darauf.
- **Risiko: lokale Dev-Konfigs in `~/.config/smolit-assistant/`**
  verfälschen `cargo test`. Lösung dokumentiert in
  [`scripts/ci_verify.sh`](../../scripts/ci_verify.sh) +
  [`docs/SETUP.md`](../SETUP.md); CI nutzt isoliertes XDG.
- **Risiko: cloud_http aus Versehen aktivieren.** Bleibt opt-in
  (PR 26); Settings-Shell hat seit PR 36 explizite
  Safety-notes-Zeile.
- **Risiko: Wayland-Userin sieht Always-on-top als „funktioniert".**
  Honest refusal seit PR 22; UI zeigt Refusal-Banner.
- **Risiko: OceanData wird als UI/Token verstanden.** ADR-0001 +
  ADR-0004 + ADR-0006 + GLOSSARY halten die Linie aktiv.
- **Risiko: AdminBot-Doku-Naming-Drift (Agent-NN).** Liegt im
  AdminBot-Repo, nicht hier. Smolit-Assistant nutzt durchgängig
  „ABrain".

## 11. Recommended v0.2 decision

> **Conditionally ready for v0.2 candidate.**

Bedingungen für den Tag (alle aus §8):

1. Letzte CI-Aktion auf main ist grün.
2. README + SETUP Smoke-Befehle stimmen mit dem Repo überein
   (heute der Fall).
3. ROADMAP / OPEN_WORK haben keine Runtime-Drift (heute der Fall
   nach PR 49).
4. Branch-Protection ist konfiguriert oder als manueller Schritt
   dokumentiert.

Wenn alle vier zur Tag-Zeit erfüllt sind, ist Smolit-Assistant
ein v0.2-Kandidat. Ein Tag wird **nicht** in PR 50 gesetzt — PR 50
ist ein Gate-Review, kein Release.

**Begründung.** Der Code-Stand auf main ist seit PR 36 (Settings-
Shell-UX-Cleanup) und PR 32 (Audit-Lifecycle für Interaction-
Actions) qualitativ stabil. PR 38/42 haben CI von Hand-Run auf
verified GitHub Actions gehoben. PR 43–48 haben den
*dokumentarischen* Stack verbreitert, ohne einen einzigen
Code-Pfad zu ändern. Damit gilt: alles was als Feature in v0.2
gehört, ist heute schon implementiert; alles was nicht
implementiert ist, ist als ADR/Contract klar als Future gerahmt.
Die einzigen offenen Schritte sind Verifikations-/Konfigurations-
Punkte, nicht Code-Punkte.

## 12. Verification

- `cargo test --manifest-path core/Cargo.toml --locked` → **398
  passed**, 0 failed.
- 5 CI-Smokes (`settings-shell-smoke`, `avatar-render-polish-smoke`,
  `workflow-visibility-smoke`, `approval-card-smoke`,
  `audit-panel-smoke`) → alle **PASS**.
- `rg "abrain_native" core/` → leer.
- `rg "oceandata_context" core/` → leer.
- `rg "correlation_id" core/` → leer.
- `rg "capability_id" core/` → leer.
- `rg "BackendUnsupported" core/` → bestätigt
  `type_text` / `send_shortcut` als unsupported, nicht als
  Feature.
- Konfliktmarker → keine.
- `git diff --name-only` (vor Commits) → nur Smolit-Assistant-
  Dateien.
