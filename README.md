# Smolit Assistant

[![CI](https://github.com/Modularium/Smolit-Assistant/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Modularium/Smolit-Assistant/actions/workflows/ci.yml)

Lokal-first, Godot-nativer Desktop-Assistant mit Rust-Core und WebSocket-IPC. 
**Sichtbar, kontrolliert, ehrlich**

## 1. Kurzbeschreibung

Smolit ist ein Linux-Desktop-Assistant aus drei getrennten Schichten:

- **Rust Core** (`core/`) — Orchestrierung, Provider-Fallback,
  Approval-Engine, Audit-Ring-Buffer, Interaction-Layer, IPC-Server.
- **Godot-UI** (`ui/`) — Presentation Layer (Avatar, Presence,
  Approval-Card, Workflow-Overlay). Kein direkter System-Access;
  hängt ausschließlich am Core via lokalem WebSocket.
- **ABrain CLI Adapter** — externer Reasoning-Prozess, vom Core über
  Command-Interface eingebunden.

## 2. Current Status

Honest MVP. Was **heute** in der Hauptlinie lebt:

- **Text-Chat** via ABrain-CLI-Adapter; optional `llamafile_local`,
  `local_http`, `cloud_http` als Fallback-Provider in der Text-Chain.
- **STT/TTS** command-basiert (externe Binaries). STT-Whitelist seit
  PR 27: `command` + `whisper_cpp`. TTS-Whitelist seit PR 34:
  `command` + `piper`.
- **Approval UX v1** — jede `open_application`-Aktion läuft per
  Default durch die Approval-Kette (Policy v0, PR 25).
- **Desktop Interaction**: real verdrahtet sind `open_application` und
  — bei doppeltem Opt-in — `focus_window` (X11-Template-basiert).
- **Workflow Visibility Overlay v1** + **Approval Card** + **Audit
  Panel** (dev-only) in der UI.
- **Accessibility-Probe** (read-only, environment-basiert; kein
  AT-SPI-RPC).
- **Local Audit Trail v1** (in-memory Ring-Buffer, Demo-Pfad
  auditiert).

Was **nicht** funktioniert (absichtlich — siehe §12):

- `type_text`, `send_shortcut` → `BackendUnsupported`.
- Wayland-`focus_window` → kein Backend.
- OCR / Vision / Pixel-Matching / Klick auf fremde UI-Elemente → kein
  Pfad im Code.
- Cloud-STT/TTS, Streaming-Audio, Lip-Sync → nicht vorhanden.

Ehrlicher Ist-Zustand pro Produktachse:
[`docs/presence_desktop_interaction.md`](docs/presence_desktop_interaction.md).

## 3. Architecture at a Glance

```text
┌────────────────────────┐    ws://127.0.0.1:8787   ┌──────────────────────┐
│ Godot UI (ui/)         │  ◀───── JSON frames ────▶│ Rust Core (core/)    │
│ - Avatar, Presence     │                           │ - IPC Server         │
│ - Approval Card        │                           │ - Approval Engine    │
│ - Workflow Overlay     │                           │ - Audit Ring-Buffer  │
│ - Settings Shell       │                           │ - Interaction Layer  │
└────────────────────────┘                           │ - Provider Resolvers │
                                                     └───────────┬──────────┘
                                                                 │
                                ┌────────────────────────────────┼──────────┐
                                │                                │          │
                   ┌────────────▼─────────┐         ┌─────────────▼──────┐  ┌▼───────────┐
                   │ ABrain CLI adapter   │         │ STT/TTS commands   │  │ Interaction│
                   │ (text provider chain)│         │ (whisper_cpp, etc.)│  │ Command    │
                   └──────────────────────┘         └────────────────────┘  │ Backend    │
                                                                             └────────────┘
```

- **Keine eigene Audio-Pipeline** im Core. Externe Commands nehmen
  auf / sprechen.
- **Keine eigene Intelligenz** in der UI. Intent + Plan leben in
  Core + ABrain.
- **Godot importiert kein React.** Smolit-Assistant bleibt
  Godot-nativ; der Smolitux Design Contract (ADR-0001) koppelt das
  Assistant-UI über Design-Tokens (später) statt über Komponenten-
  Import. Details:
  [`docs/adr/ADR-0001-smolitux-design-contract.md`](docs/adr/ADR-0001-smolitux-design-contract.md).

## 4. Requirements

- **Rust 1.85+** (Cargo-Edition 2024 in
  [`core/Cargo.toml`](core/Cargo.toml)).
- **Godot 4.6** (siehe
  [`ui/project.godot`](ui/project.godot) `config/features`). 4.2+
  kann reichen, 4.6 ist getestet.
- **Linux-Desktop**. Ziel-Session GNOME/Wayland (Ubuntu 24.04); X11
  wird zusätzlich für `focus_window` und Always-on-top-Sonderpfad
  unterstützt.
- **Optional** (nur wenn du den jeweiligen Pfad aktivierst):
  - **ABrain-CLI** (externer Reasoning-Prozess).
  - **TTS-Command** (z. B. `espeak`, `piper`, `kokoro`).
  - **STT-Command** (z. B. `whisper`, eigener Wrapper).
  - **whisper.cpp-Binary** (für STT-Chain-Opt-in über
    `SMOLIT_STT_WHISPER_CPP_CMD`).
  - **`wmctrl`** (für X11-`focus_window` über `wmctrl -a {name}`).

## 5. Quick Start

Für einen neuen Entwickler: in 5–10 Minuten build + run.

```bash
# Clone
git clone https://github.com/Modularium/Smolit-Assistant.git
cd Smolit-Assistant

# Env vorbereiten (kleines Minimal-Set)
cp .env.example .env
# optional: Werte anpassen (siehe §6)

# Core testen (CI-paritätisch isoliert, empfohlen für Gate / Release)
scripts/ci_verify.sh core
# Schnellere Dev-Iteration ohne Isolation:
#   cargo test --manifest-path core/Cargo.toml
# Hinweis: plain `cargo test` kann lokale Persistenz unter
# ~/.config/smolit-assistant/ lesen und zwei IPC-Tests verfälschen
# (siehe docs/SETUP.md §2.1). Vor einem Release immer ci_verify.sh.
cargo build --manifest-path core/Cargo.toml

# Core starten (IPC auf 127.0.0.1:8787)
cargo run --manifest-path core/Cargo.toml

# In einem zweiten Terminal: UI starten
godot --path ui        # Godot 4.6 öffnet scenes/main.tscn
```

Für ausführlichere Setup-Anleitung inkl. Troubleshooting:
[`docs/SETUP.md`](docs/SETUP.md).

## 6. Minimal Environment

Kuratiertes Minimum (Vollversion in
[`.env.example`](./.env.example) und
[`docs/SETUP.md`](docs/SETUP.md)):

| Variable | Default | Zweck |
| --- | --- | --- |
| `SMOLIT_IPC_BIND` | `127.0.0.1:8787` | Loopback-WebSocket für die UI. Nie extern binden. |
| `ABRAIN_CMD` | `abrain` | Externer CLI-Reasoning-Prozess. |
| `SMOLIT_TTS_ENABLED` / `SMOLIT_TTS_CMD` | `true` / *leer* | TTS-Achse; leer = `unavailable`. |
| `SMOLIT_STT_ENABLED` / `SMOLIT_STT_CMD` | `true` / *leer* | STT-`command`-Kind; leer = `unavailable`. |
| `SMOLIT_STT_WHISPER_CPP_CMD` | *leer* | whisper.cpp-Kind (PR 27); nur wirksam, wenn `whisper_cpp` in `SMOLIT_STT_PROVIDER_CHAIN` steht. |
| `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION` | `true` | Policy v0 (PR 25); Approval-Default für echte Interaction-Aktionen. In Produktion **nicht auf `false` setzen**. |
| `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW` | `false` | `focus_window` ist doppeltes Opt-in (+ Template). |
| `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD` | *leer* | X11-Template z. B. `wmctrl -a {name}`. Wayland: lassen. |
| `SMOLIT_UI_DEV_CONTROLS` | *leer* | Nur auf Dev-Maschinen `1` setzen; aktiviert Dev-Buttons + Audit-Panel. |
| `SMOLIT_WORKFLOW_OVERLAY` | *leer* | `1` blendet das Workflow Visibility Overlay ein. |

Vollständige Liste mit Gruppen (Provider, Audio, Interaction,
Overlay, Probe): [`docs/SETUP.md`](docs/SETUP.md) §3.

## 7. Provider Setup

**Text-Provider-Chain** (IPC-editierbar, Default `["abrain"]`):
Whitelist `abrain`, `llamafile_local`, `local_http`, `cloud_http`.
Die Settings-Shell trägt seit PR 26 einen **Provider-Onboarding-Block**
mit einer Quick-Action „Use local-first chain"
(`["llamafile_local", "local_http", "abrain"]`). Details:
[`docs/provider_fallback_and_settings_architecture.md`](docs/provider_fallback_and_settings_architecture.md).

**STT-Provider-Chain** (Default `["command"]`): Whitelist `command`,
`whisper_cpp`. whisper.cpp-Kind ist env-only
(`SMOLIT_STT_WHISPER_CPP_CMD`); kein Runtime-Editor.

**TTS-Provider-Chain** (Default `["command"]`): Whitelist `command`,
`piper`. piper-Kind ist env-only (`SMOLIT_TTS_PIPER_CMD`); kein
Runtime-Editor. Speaking-Lifecycle-Events (PR 14) tragen den real
aktiven Kind-Namen im `provider`-Feld.

**cloud_http — Opt-in-Warnung.** cloud_http ist strikt opt-in: **nicht
Teil des Default-Chain**, nicht automatisch aktiviert. Vor dem
ersten Einsatz braucht es:

1. `SMOLIT_CLOUD_HTTP_ENABLED=true`,
2. Endpoint-Setting (`SMOLIT_CLOUD_HTTP_ENDPOINT`),
3. API-Key via IPC (`settings_set_cloud_http_secret`) — **nie** als
   Env-Var, nie im `.env.example`.
4. Manuelles Einfügen von `cloud_http` in die Chain über die
   Settings-Shell.

Es gibt **keine Auto-Cloud-Aktivierung**; der
„Add cloud_http to chain"-Button in der Settings-Shell bleibt per
Design disabled.

## 8. Interaction & Safety

Policy v0 (PR 25, 2026-04-24) fixiert die Approval-Baseline:

- `open_application` ist **real verdrahtet** und läuft per Default
  durch die Approval-Kette. Ohne User-`approve` kein Backend-Aufruf.
- `focus_window` ist **doppeltes Opt-in**: erst
  `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW=true` **und** ein X11-
  Template in `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`, dann
  Approval-gated.
- `type_text` / `send_shortcut` → **`BackendUnsupported`**. Kein
  Backend, keine Simulation.
- **Audit-Ring-Buffer** ist in-memory (max. 100 / hard 1000); deckt
  heute nur den `plan_demo_action`-Pfad. Ein Core-Restart leert den
  Store. Kein Persistenz-Layer.

Details:
[`docs/security/APPROVAL_UX.md`](docs/security/APPROVAL_UX.md),
[`docs/security/AUDIT_TRAIL.md`](docs/security/AUDIT_TRAIL.md),
[`docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md`](docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md).

## 9. Verification

```bash
# Core-Tests (398 Tests, Policy-v0-Tripwire inklusive)
cargo test --manifest-path core/Cargo.toml

# UI-Smokes (Godot headless)
scripts/run_overlay_verification.sh settings-shell-smoke
scripts/run_overlay_verification.sh speech-sync-smoke
scripts/run_overlay_verification.sh workflow-visibility-smoke
scripts/run_overlay_verification.sh resolver-smoke

# Overlay-Verifikationsmatrix (Godot-Scene-Lauf, manuell)
scripts/run_overlay_verification.sh --help
```

Weitere Cases (Overlay, Click-through, Probe, AOT-X11) sind im
Help-Output des Verifikations-Wrappers gelistet.

**GitHub Actions CI** (seit PR 38, [`ci.yml`](.github/workflows/ci.yml))
spiegelt den Kern dieser Verifikation: `cargo test` plus die fünf
kuratierten UI-Smokes (`settings-shell-smoke`,
`avatar-render-polish-smoke`, `workflow-visibility-smoke`,
`approval-card-smoke`, `audit-panel-smoke`) auf `ubuntu-latest` mit
Godot 4.6 headless. Beide Jobs laufen in isolierten
`XDG_CONFIG_HOME` / `XDG_CACHE_HOME`-Ordnern, damit lokale
`~/.config/smolit-assistant/`-Dev-Artefakte die Tests nicht
verfälschen.

Seit PR 42 läuft das Godot-Binary unter einem zwei-stufigen
Härtungs-Setup:

- **Gepinnte Version** (`GODOT_VERSION=4.6-stable`) plus
  **SHA512-Verifikation** gegen die upstream-publizierte
  `SHA512-SUMS.txt` — unverändertes Binary aus dem Godot-Release
  landet 1:1 im Cache; ein manipulierter Download bricht CI sofort.
- **`actions/cache@v4`** cached das entpackte Binary unter dem Key
  `godot-${GODOT_VERSION}`, damit der Download pro Runner nur
  einmal nötig ist.

Für einen lokalen Parity-Lauf:
[`scripts/ci_verify.sh`](scripts/ci_verify.sh). Empfohlene
Branch-Protection-Einstellungen für `main` liegen unter
[`docs/ci/BRANCH_PROTECTION.md`](docs/ci/BRANCH_PROTECTION.md).

## 10. Project Roadmap

- **Roadmap & Phasen:** [`ROADMAP.md`](ROADMAP.md).
- **Offene Arbeit pro Workstream:**
  [`docs/OPEN_WORK.md`](docs/OPEN_WORK.md).
- **PR-Historie / Reality-Checks:**
  [`docs/reviews/`](docs/reviews/) — u. a. PR 20 Docs Reality Check,
  PR 23 `focus_window` Decision, PR 25 Policy v0, PR 28 Presence Trim.

## 11. Design System

Smolit-Assistant folgt dem **Smolitux Design Contract** (ADR-0001,
PR 24) gegenüber der Web-Komponenten-Bibliothek
[`smolitux-ui`](https://github.com/Modularium/smolitux-ui):

- **Godot-nativ.** Keine `@smolitux/*`-Pakete zur Laufzeit, kein
  WebView, keine React↔Godot-Brücke.
- **Design Tokens** sind der zukünftige cross-runtime Vertrag
  (noch nicht implementiert).
- **OceanData ist nicht Teil dieses Projekts.** OceanData ist ein
  Data-Layer im Smolitux-Ökosystem, **kein** UI-/Design-System und
  **kein** Smolit-Assistant-Backend. Keine OceanData-Integration in
  diesem Repo. Ein zukünftiger Anbindungs-Pfad ist als Proposed-ADR
  in [`docs/adr/ADR-0004-oceandata-data-layer-integration.md`](docs/adr/ADR-0004-oceandata-data-layer-integration.md)
  skizziert — Docs/ADR-only, kein Code, kein Provider-Kind, keine
  IPC-Commands.

Vollständiger ADR:
[`docs/adr/ADR-0001-smolitux-design-contract.md`](docs/adr/ADR-0001-smolitux-design-contract.md).

## 12. Non-goals / Not Yet Implemented

Bewusst **nicht** heute:

- **Streaming-Audio**, **Phonem-/Lip-Sync**, **Audio-Timeline**.
- **Wayland-Fokus-Backend** für `focus_window`.
- **`type_text` / `send_shortcut` Backends** (bleiben
  `BackendUnsupported` bis zu einer eigenen Policy-Runde).
- **AT-SPI-RPC, Tree-Walking, App-spezifische Adapter** — der
  Accessibility-Spike bleibt Environment-basiert + Hint-Echo.
- **OCR, Vision, Pixel-Matching** — keine Bibliothek gebunden.
- **AdminBot-Integration / Shell-Zugriff** — nicht implementiert.
  Designrahmen für eine eventuelle spätere Integration in
  [`docs/adr/ADR-0005-adminbot-safety-boundary.md`](docs/adr/ADR-0005-adminbot-safety-boundary.md)
  (Proposed, Docs/ADR-only): read-only / status-first, capability-
  whitelisted, kein Shell-Pfad, kein generischer Tool-Passthrough,
  Approval-/Audit-Hop für jede Mutation, lokal-first, default-off.
- **Stage-C-Avatar-User-Uploads** —
  [`docs/avatar_stage_c_research.md`](docs/avatar_stage_c_research.md)
  bleibt Research-Gate.
- **Packaging-Binaries** (AppImage / `.deb` / Flatpak / Snap /
  Docker als Desktop-Distribution) — aufgeschoben. v0.2.0 trägt
  **keine binären Release-Artefakte**; der Source-/Dev-Run aus §5
  bleibt der offizielle Install-Pfad. Strategie ist als
  Proposed-ADR in
  [`docs/adr/ADR-0007-packaging-decision.md`](docs/adr/ADR-0007-packaging-decision.md)
  fixiert (Linux-Desktop-zuerst, AppImage vor `.deb` vor Flatpak,
  kein Snap, kein Docker als Desktop-Distribution, Signing erst
  nach P5).
- **OceanData-Integration**, **smolitux-ui-Import**, **Smolitux-
  Token-Implementation**.

Siehe [`ROADMAP.md §7 „Explicitly Deferred"`](ROADMAP.md).

## 13. Documentation Map

| Thema | Quelle |
| --- | --- |
| **IPC-Protokoll** (Incoming/Outgoing, Action Events, Approval, Accessibility) | [`docs/api.md`](docs/api.md) |
| **UI-Architektur** (Presence, Avatar, Overlay, Settings-Shell, Provider-Onboarding) | [`docs/ui_architecture.md`](docs/ui_architecture.md) |
| **Provider-/Settings-Architektur** (Text/STT/TTS, Chain-Validator, Onboarding UX) | [`docs/provider_fallback_and_settings_architecture.md`](docs/provider_fallback_and_settings_architecture.md) |
| **Presence & Desktop Interaction** (Ist-Zustand nach PR 28) | [`docs/presence_desktop_interaction.md`](docs/presence_desktop_interaction.md) |
| **Approval UX / Policy v0** | [`docs/security/APPROVAL_UX.md`](docs/security/APPROVAL_UX.md) |
| **Audit Trail** (in-memory, Scope) | [`docs/security/AUDIT_TRAIL.md`](docs/security/AUDIT_TRAIL.md) |
| **Window / Overlay / Always-on-top** (Linux-Plattform-Realität) | [`docs/linux_window_overlay_architecture.md`](docs/linux_window_overlay_architecture.md), [`docs/linux_always_on_top_decision.md`](docs/linux_always_on_top_decision.md) |
| **Architectural Decision Records** | [`docs/adr/`](docs/adr/) — ADR-0001 Smolitux Design Contract |
| **Cross-Repo Contracts Index** | [`docs/contracts/`](docs/contracts/) — [Ecosystem Integration Contracts Matrix](docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) |
| **Reviews / Reality-Checks** | [`docs/reviews/`](docs/reviews/) |
| **Offene Arbeiten / Workstreams** | [`docs/OPEN_WORK.md`](docs/OPEN_WORK.md) |
| **Einheitliches Vokabular** | [`docs/GLOSSARY.md`](docs/GLOSSARY.md) |
| **Setup & Troubleshooting** | [`docs/SETUP.md`](docs/SETUP.md) |

---

**Feedback / Issues:**
[github.com/Modularium/Smolit-Assistant/issues](https://github.com/Modularium/Smolit-Assistant/issues).
