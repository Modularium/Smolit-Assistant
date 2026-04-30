# CLAUDE.md — Smolit-Assistant Operating Memory

This file is the Claude Code memory anchor for `Smolit-Assistant`. It
is deliberately short. The authoritative documents are linked inline.
When they disagree with this file, the linked document wins.

## Repository role

Smolit-Assistant is a **local-first, Godot-native Linux desktop
assistant** with a Rust core and a WebSocket IPC seam ([`README.md`](README.md) §1). Three-layer architecture:

- **Rust core** ([`core/`](core/)) — orchestration, provider
  fallback, approval engine, audit ring buffer, interaction layer,
  IPC server.
- **Godot UI** ([`ui/`](ui/)) — presentation layer (avatar,
  presence, approval card, workflow overlay). No direct system
  access; talks to the core via local WebSocket only.
- **ABrain CLI adapter** — external reasoning process invoked via
  command interface.

Mantra: **"Sichtbar, kontrolliert, ehrlich"**.

## Smolitux relationship — native, **token-only**

Smolit-Assistant is **a native Smolitux consumer through the Design
Token Contract** ([ADR-0001 mirror](docs/adr/ADR-0001-smolitux-design-contract.md);
upstream: [`smolitux-ui ADR-0001`](https://github.com/Modularium/smolitux-ui/blob/main/docs/adr/ADR-0001-smolitux-design-contract.md), [`SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)).

**Status (2026-04):** the contract is **Accepted**, the
**implementation is later** ([`README.md`](README.md) §11). No local
token JSON, no token-import pipeline, no bound Godot theme keys are
shipped today. The `/verify-token-contract` slash command is a
Phase-1 smoke test for that reason; it will become a real drift gate
once the pipeline lands.

## Out of scope for this repo (explicit non-goals)

Per [ADR-0001 §Decision §3](docs/adr/ADR-0001-smolitux-design-contract.md)
and [`README.md`](README.md) §11:

- **No `@smolitux/*` packages at runtime.** The Rust core does not
  pull JS packages; the Godot UI does not embed React.
- **No React components.** Godot is the UI; HTML / CSS / DOM are not
  the rendering target.
- **No WebView** as a Smolitux-component bridge. A WebView shell
  would break the presence / overlay / approval path (`README.md` §11).
- **No npm Smolitux dependencies** in `core/Cargo.toml` or any Godot
  resource. Tokens cross the boundary as data (JSON / Style Dictionary
  / Godot-theme-JSON / Rust constants — format chosen later per
  ADR-0001 §Decision §4), never as code.

If a native UI need is not covered by the existing primitives, the
path is **not** "fall back to a WebView" but either:

1. Implement it natively in Godot / Rust, **or**
2. If the need is cross-runtime relevant (would benefit Smolitux-UI
   web consumers too), propose a **token category** addition
   upstream — analogous to LabOS' driver role for component
   proposals, but for the token contract instead.

## Token consumption mechanics

| Aspect | Today | Planned |
|---|---|---|
| Source | upstream [`smolitux-ui/docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md) | unchanged |
| Local persistence | none | `assets/tokens/`, `ui/themes/`, or equivalent — chosen when the pipeline lands |
| Sync | manual / not running | scripted; CI-checked drift |
| Verification | `/verify-token-contract` (smoke test today) | `/verify-token-contract` (real drift gate) |

The format choice (CSS custom properties, Tailwind preset, JSON,
Godot-theme-JSON, Rust constants) is **deliberately open** until a
follow-up ADR fixes it (per [ADR-0001 §Decision §4](docs/adr/ADR-0001-smolitux-design-contract.md)).

## Token categories (from [`SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md))

The minimum surface every consumer (web or native) shares:

```text
Color:       canvas/*, ink/*, accent/*, state/*  (success / warning
             / danger / info), border/*, selection/*
Spacing:     named scale (e.g. space-0 … space-24); no ad-hoc px in
             components / themes
Radius:      named scale (radius-none / sm / md / lg / full)
Typography:  named font roles + named text styles for headings, body,
             labels, code
Shadow:      named elevation tiers (shadow-none / sm / md / lg)
Motion:      named durations (motion-instant / fast / base / slow)
             plus named easings
```

Smolit-Assistant binds Godot themes / Rust constants to these
**names**, not to literal values. Token rename / removal / semantic
flips require coordinated cross-runtime review per ADR-0001.

## Companion documents

Smolit-Assistant side:

- [`README.md`](README.md) — repo overview; §1 architecture, §11 Smolitux relationship, §12 deliberate non-goals.
- [`docs/adr/ADR-0001-smolitux-design-contract.md`](docs/adr/ADR-0001-smolitux-design-contract.md) — local mirror of the cross-runtime design contract.
- [`docs/adr/ADR-0007-packaging-decision.md`](docs/adr/ADR-0007-packaging-decision.md) — packaging path (relevant for the Godot/Rust artifact pipeline).
- [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) — cross-product integration contracts (OceanData adapter, ABrain).
- [`docs/contracts/CAPABILITY_VOCABULARY.md`](docs/contracts/CAPABILITY_VOCABULARY.md) — capability terms used across the ecosystem.
- [`docs/presence_desktop_interaction.md`](docs/presence_desktop_interaction.md) — honest current state per product axis.

Smolitux-UI side (Single Source of Truth for the contract):

- [`smolitux-ui ADR-0001`](https://github.com/Modularium/smolitux-ui/blob/main/docs/adr/ADR-0001-smolitux-design-contract.md) — original cross-runtime design contract (mirrored locally above).
- [`SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md) — token data shape (categories, naming, value types).
- [`SMOLITUX_DESIGN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_DESIGN_CONTRACT.md) — system roles + branding-via-theme rule.

## Build / verify commands

Native stack — no npm. Rust core:

```bash
cd core
cargo --version            # rustup must point at edition-2024 toolchain
cargo check                # fast compile validation, no linker
cargo build                # full debug build
cargo test                 # core test suite
cargo run --bin <bin>      # run a specific binary (see core/Cargo.toml)
```

Godot UI — `ui/project.godot` opens in the Godot editor (no
meaningful CLI gate; Godot is a GUI tool). The smoke-test scripts in
[`scripts/`](scripts/) (e.g. `approval_card_smoke.gd`,
`avatar_appearance_smoke.gd`) are Godot scripts run from the editor.

Repo-level wrappers in [`scripts/`](scripts/) — read before running:

- `build_local_release.sh` — local release artifact
- `ci_verify.sh` — CI verification entry point
- `run_overlay_verification.sh` — overlay verification

These wrappers can be destructive (artifact creation, file moves).
Read them before invoking from a Claude Code session; do not auto-run.

## Slash commands ([`.claude/commands/`](.claude/commands/))

- `/verify-token-contract` — compare the locally consumed token state
  against [`SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)
  upstream. **Today** the local state is empty (no token pipeline yet);
  the command runs as a smoke test and reports "no local tokens
  consumed yet — drift check trivially passes". Once the pipeline
  lands (per ADR-0001 §Future-work), it becomes a real drift gate.

There is no `/audit-smolitux-imports` slash command in this repo —
there are no Smolitux imports to audit (npm is not used). Likewise no
`/check-token-usage` for hex-color hunting in `web/`-style code —
Godot themes and Rust constants are not the same shape.

## PR hygiene

- Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, …).
- One concern per PR.
- For Rust-core changes: paste `cargo check` and `cargo test` output
  (or its tail) into the PR description.
- For Godot-UI changes: paste relevant smoke-test output from
  `scripts/<...>_smoke.gd` runs.
- Documentation changes that touch ADRs or `docs/contracts/` link the
  affected ADR in the PR description.
- Token-related changes (once the pipeline lands) **always** route
  through ADR-0001's cross-runtime review — rename / removal /
  semantic flips never land alone.
