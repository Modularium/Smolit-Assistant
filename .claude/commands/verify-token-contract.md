---
description: Compare locally consumed Smolitux design tokens against the upstream contract and report drift.
---

You are verifying that **Smolit-Assistant's** locally consumed
Smolitux design-token state matches the upstream contract:
[`smolitux-ui/docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md).

Cross-runtime contract: [ADR-0001 mirror](../../docs/adr/ADR-0001-smolitux-design-contract.md).
Token-only consumption: confirmed by [`README.md`](../../README.md) §11
and ADR-0001 §Decision §3.

## Phase context

- **Today (Phase 1)**: there is **no local token state** in this
  repo. No `assets/tokens/`, no `ui/themes/<smolitux>.tres`, no
  Rust-constant module that mirrors token values. The pipeline that
  ADR-0001 §Decision §4 describes has not been implemented. The
  audit therefore returns **"no local tokens consumed yet — drift
  check trivially passes"**.
- **Phase 2 (planned)**: once a token-import pipeline lands (chosen
  format per ADR-0001 §Future-work — CSS custom properties, Tailwind
  preset, JSON, Godot-theme-JSON, or Rust constants), the audit
  becomes a real drift gate.

## Method

Walk the audit in this order:

### 1. Confirm Phase

Detect whether any local token state exists. Search for typical
landing locations:

```bash
find . -maxdepth 5 \( \
    -name 'tokens*.json' -o \
    -name 'smolitux*.json' -o \
    -name 'design_tokens*' -o \
    -path '*assets/tokens*' -o \
    -path '*ui/themes*' \
  \) -not -path '*/.git/*' -not -path '*/target/*'
git grep -nE 'smolitux.token|design_token|TOKEN_CONTRACT' \
  -- ':!docs/' ':!CLAUDE.md' ':!.claude/' 2>&1 | head -20
```

If both queries return empty: the repo is in **Phase 1**. Output the
"trivially passes" message and stop.

If anything matches: **Phase 2** — proceed.

### 2. Read upstream token contract

The upstream contract lives at
`/home/dev/EcoSphereNetwork/smolitux-ui/docs/design/SMOLITUX_TOKEN_CONTRACT.md`.
The filesystem MCP (`.mcp.json`) makes this path accessible read-only
from this repo.

Extract:

- **Token categories** (canvas, ink, accent, state, border,
  selection, plus spacing / radius / typography / shadow / motion).
- **Per-category names** required (e.g. `canvas-base`,
  `ink-primary`, `accent-default`, `state-success`).
- **Value type expectations** (color hex / rgb / hsl, named scale
  step, named-text-style id, named-elevation tier, named-duration).

The contract document is the source of truth — do not infer token
names from anywhere else.

### 3. Read local token state

Pull the token names + values from each local landing location
(format depends on the Phase-2 implementation choice). Bucket them
into the same categories as the upstream contract.

### 4. Compare

Build a per-token-name comparison table:

```
Category | Token name        | Upstream value         | Local value         | Status
---------|-------------------|------------------------|---------------------|--------
canvas   | canvas-base       | <hex / scale step>     | <hex / step>        | matches | drift | missing-locally | missing-upstream
ink      | ink-primary       | …                      | …                   | …
accent   | accent-default    | …                      | …                   | …
…        | …                 | …                      | …                   | …
```

Status meanings:

- **matches** — local value equals upstream value (allowing for
  format-translation, e.g. CSS hex vs. Godot hex).
- **drift** — same name, different value. Flag for review.
- **missing-locally** — upstream defines it, local does not consume
  it yet. Informational unless the assistant UI uses that
  category — then it is a gap to close.
- **missing-upstream** — local consumes a token name that does not
  exist upstream. **Violation** — the local state has invented a
  token outside the contract.

### 5. Output

Compact report:

```
Phase:                 Phase 1 / Phase 2
Local landing paths:   <list, or "(none)">
Upstream contract:     /home/dev/EcoSphereNetwork/smolitux-ui/docs/design/SMOLITUX_TOKEN_CONTRACT.md

Categories audited:    <count>
Tokens audited:        <count>

matches:               N
drift:                 M  (Category × Name × upstream × local)
missing-locally:       K  (informational unless used)
missing-upstream:      L  (VIOLATION — token outside contract)
```

If Phase 1: a single short paragraph stating that the audit is
trivially clean because the local pipeline is not yet implemented,
plus a pointer to ADR-0001 §Future-work for the planned next step.

## Scope and limits

- **Read-only.** Do not edit any file. Token-state changes land in
  their own PR with cross-runtime review per ADR-0001.
- **No upstream change** is suggested by this audit — drift detection
  is the trigger for human review, not for automated fix-up. The
  reverse direction (upstream change → local update) is also
  human-coordinated.
- **No format conversion** in this command. If the chosen Phase-2
  format adds translation (e.g. CSS hex → Godot Color or Rust
  `[u8; 4]`), the comparison normalizes both sides before deciding
  status, but the conversion logic itself lives in the pipeline,
  not here.
