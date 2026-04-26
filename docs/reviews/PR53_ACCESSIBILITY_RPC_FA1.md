# PR 53 — Accessibility RPC FA-1 Spike (partial)

- **Datum:** 2026-04-26.
- **Typ:** Code-Spike, default-off; **partial spike**. Erster
  Code-Eintritt für [ADR-0002](../adr/ADR-0002-accessibility-rpc-readonly.md)
  FA-1.
- **Scope:** Schmaler, gehärteter Eintrittspunkt für einen
  zukünftigen `atspi`/`zbus`-Registry-Client. Setzt den
  Feature-/Env-/Trait-Gate, fixiert die `verified`-Semantik in
  Code, ändert *kein* Default-Verhalten, **bringt keinen** echten
  AT-SPI-Client mit.

> Leitprinzip: **Verified accessibility data only comes from
> read-only AT-SPI registry evidence.**

## 1. Scope

ADR-0002 (PR 37) hat den Rahmen entschieden: read-only
Registry-Root-`GetChildren`, default-off, kein Tree-Walk, kein
`DoAction`, keine Input-Injection, kein Approval-Bypass. PR 53 ist
der erste Code-Eintritt — bewusst **partial**:

- **Was geliefert ist.** Cargo-Feature `accessibility_rpc`
  (default-off), Runtime-Env `SMOLIT_ACCESSIBILITY_RPC_ENABLED=1`,
  mockable Trait `AccessibilityRegistryClient`, neuer Datentyp
  `RegistryRootChild`, Fehlerklassen `AccessibilityRpcError`,
  Orchestrator `discover_top_level_with_config`, hint-orchestrator
  `inspect_target_with_config`, und der **einzige** Konstruktor für
  `confidence: verified` — `RegistryRootChild::into_verified_item`.
  Alle Pfade sitzen in
  [`core/src/interaction/accessibility.rs`](../../core/src/interaction/accessibility.rs).
- **Was bewusst nicht geliefert ist.** Kein `atspi`/`zbus`-Client.
  Keine echte D-Bus-Verbindung. Keine Production-Verified-Items.
  Kein UI-Readout für `verified` vs. `discovered`. Kein neues
  IPC-Command, kein neues Outgoing-Envelope, keine neue Cargo-
  Dependency.

## 2. Decision

**Partial spike** statt Full Spike, weil:

- Echte `atspi`+`zbus`-Dependencies brauchen eine eigene Permission-
  /Provenance-Runde (Flatpak `--talk-name=org.a11y.Bus`, Cargo-
  audit-Linie für transitive D-Bus-Crates). Diese Runde ist eigener
  Folge-PR.
- Die **Sicherheits-Invariante** (verified ⇒ Registry-Evidenz) ist
  unabhängig vom realen Client durchsetzbar — sie lebt im
  Konstruktor und im Trait-Vertrag.
- Der Default-Build verhält sich **bit-für-bit** wie pre-PR-53.
  Keine Regression, kein neuer Run-Path für 99 % der Nutzer.

Production-Verhalten mit Feature+Env on:

```text
config.accessibility.rpc_enabled = true
+ Cargo --features accessibility_rpc
+ keine AccessibilityRegistryClient-Implementation gewired
→ AccessibilityDiscovery::Unavailable {
    reason: "accessibility_rpc_backend_not_implemented"
  }
```

## 3. Implemented

### 3.1 Cargo feature

[`core/Cargo.toml`](../../core/Cargo.toml):

```toml
[features]
default = []
accessibility_rpc = []
```

Kein neuer `[dependencies]`-Eintrag. Default-Build identisch zu
pre-PR-53.

### 3.2 Runtime config

[`core/src/config.rs`](../../core/src/config.rs):

```rust
pub struct AccessibilityConfig {
    pub rpc_enabled: bool,  // default false
}
pub struct Config {
    // …
    pub accessibility: AccessibilityConfig,
}
```

Env-Lookup: `SMOLIT_ACCESSIBILITY_RPC_ENABLED` (parseBool, default
false). `Config::load` propagiert den Wert in `accessibility:
AccessibilityConfig { rpc_enabled }`. Ohne Env bleibt es `false`.

### 3.3 RPC scaffold

[`core/src/interaction/accessibility.rs`](../../core/src/interaction/accessibility.rs):

- `pub struct RegistryRootChild { name, role, app_name,
  is_password, is_invisible }` — flat by design (Tiefe 1, kein
  `children`-Feld).
- `pub enum AccessibilityRpcError` mit fünf Klassen
  (`DbusSessionMissing`, `A11yBusUnavailable`, `PermissionDenied`,
  `BackendNotImplemented`, `Other(String)`); jede hat eine stable
  `unavailable_reason()`-Konstante.
- `pub trait AccessibilityRegistryClient` mit *einer* Methode
  (`registry_root_children`). Keine `do_action`, kein
  `set_*`, kein `children_of(id)`. Trait-Signatur **macht** die
  Tiefen-1-Regel zur Compile-Time-Garantie.
- `pub fn apply_registry_children(rows) -> AccessibilityDiscovery`
  — pure Konversion. Filtert `is_password`, `is_invisible` und
  Empty-Name. Empty-Result → `Uncertain { reason: "registry_empty",
  items: [] }`. Mit Items → `Ok { … }`.
- `RegistryRootChild::into_verified_item` — der **einzige**
  Konstruktor für `confidence: Verified`. Kann nur über die
  Trait-Result-Pipeline aufgerufen werden.
- `pub fn discover_top_level_with_config(cfg, client)` —
  Orchestrator. Drei-Stufen-Gate:
  1. `!cfg.enabled` → `discover_top_level()` (Legacy-Fallback).
  2. Cargo-Feature off → `Unavailable { reason:
     "accessibility_rpc_feature_disabled" }`.
  3. Feature on, kein Client → `Unavailable { reason:
     "accessibility_rpc_backend_not_implemented" }`.
- `pub fn inspect_target_with_config(hint, cfg, client)` —
  delegiert in FA-1 weiter an Hint-Echo. Name-Match ist FA-2.

### 3.4 App-Wiring

[`core/src/app.rs`](../../core/src/app.rs):

`App::discover_accessibility` baut einen `AccessibilityRpcConfig`
aus `self.config.accessibility.rpc_enabled` und ruft
`discover_top_level_with_config` /
`inspect_target_with_config`. Production passt `client = None`
durch — der Gate fällt auf `accessibility_rpc_backend_not_implemented`
zurück, sobald Feature+Env on sind.

## 4. Verified semantics

`confidence: verified` darf in **genau** einem Pfad entstehen:

```text
AccessibilityRegistryClient::registry_root_children()
  ↓ Ok(rows: Vec<RegistryRootChild>)
RegistryRootChild::into_verified_item(row)
  ↓ Some(AccessibilityItem {
       confidence: Verified,
       source: "accessibility_registry_root",
       … })
```

Jede Zeile mit `is_password=true`, `is_invisible=true` oder leerem
`name` wird **vor** dem Wire silent gedroppt — kein Failure, keine
Auslassung.

Andere Pfade:

- **Hint-Echo** (`inspect_target` / `inspect_target_with_config`)
  → `confidence: discovered`, `source: accessibility_hint_echo`.
  Auch mit Feature+Env on bleibt es `discovered`. Der
  Hint-Match-gegen-Registry-Pfad ist FA-2.
- **Probe-Stage-Failure** (kein DISPLAY, kein DBus,
  Permission denied, Backend not implemented) →
  `unavailable`/`failed` mit stabiler Reason, **niemals**
  `verified` und **niemals** `discovered` aus heuristischer
  Hochstufung.
- **Empty registry** → `Uncertain` (ein Screenreader könnte
  Items nach Aktivierung exportieren).

## 5. Tests

10 neue Invariant-Tests im Default-Build plus ein feature-gated
End-to-End-Test:

| Test | Sichert |
| ---- | ------- |
| `default_without_feature_or_env_never_verified` | Legacy-Fallback nie `verified`. |
| `rpc_env_enabled_without_feature_reports_feature_disabled` | Env on, Feature off → `accessibility_rpc_feature_disabled`. |
| `missing_dbus_session_or_display_never_emits_verified_without_feature` | Ohne Feature kein `verified`, egal welcher Host-Env-State. |
| `hint_echo_remains_discovered` | Hint-Echo wird auch mit RPC-Config nicht hochgestuft. |
| `mock_registry_child_can_be_verified_via_apply_helper` | Pure Konversion eines Registry-Rows produziert `verified` + `source=accessibility_registry_root`. |
| `password_or_invisible_items_are_filtered` | Password / Invisible Rows werden gedroppt. |
| `registry_depth_limit_is_one_by_trait_signature` | Trait erzwingt Tiefe 1 (kein `children_of`). |
| `permission_denied_and_friends_map_to_stable_unavailable_reasons` | Stable Reasons für alle vier Fehlerklassen. |
| `rpc_failure_never_falls_back_to_verified` | Empty Registry → `Uncertain`; Unnamed Row → silent drop. |
| `serialization_keeps_existing_fields_stable` | Wire-Schema unverändert; `matched_hint` nur bei Hint-Echo, nicht bei Registry-Item. |
| *(feature-gated)* `rpc_path_with_feature_and_mock_client_can_emit_verified` | End-to-End mit Mock-Client unter `--features accessibility_rpc`. |

Default-Build: **408 Tests passed** (war 398 vor PR 53). Mit
Feature: **409 passed** (zusätzlicher Feature-Test).

**Keine** Tests laufen gegen eine echte AT-SPI-Session. **Keine**
Test-Daten produzieren `verified` ohne Mock-Registry-Evidenz.

## 6. Verification commands

```bash
# Default-Build, CI-paritätisch (XDG-isoliert)
scripts/ci_verify.sh core
# Erwartung: 408 passed; 0 failed

# Mit Feature
cargo test --manifest-path core/Cargo.toml --locked \
    --features accessibility_rpc
# Erwartung: 409 passed; 0 failed

# UI Smoke
scripts/run_overlay_verification.sh settings-shell-smoke
# Erwartung: PASS

# Repo-Hygiene
rg "accessibility_rpc" core docs README.md ROADMAP.md
rg "verified" core/src/interaction/accessibility.rs
rg "DoAction|click|type_text|send_shortcut" \
    core/src/interaction/accessibility.rs
# Erwartung: keine DoAction/click/type_text/send_shortcut-Referenzen
# im accessibility-Modul.
```

## 7. Security constraints (alle eingehalten)

- Kein Klick, kein Tippen, kein Shortcut, kein Fokuswechsel.
- Kein `DoAction`, kein `set_*`, kein State-Mutating-Method-Call.
- Kein Tree-Walk über Tiefe 1 (Trait-Signatur).
- Keine Wayland-Compositor-Aktion.
- Keine AdminBot-/Shell-Aktion.
- Keine Persistenz, keine Audit-Erweiterung.
- Keine Approval-Änderung.
- Kein neues IPC-Command, keine neuen Outgoing-Envelopes.
- Keine UI-Änderung.
- Keine Default-Verhaltens-Änderung im Default-Build.
- Keine neuen Cargo-Dependencies.

## 8. Repo state after PR 53

- **Geändert:**
  - [`core/Cargo.toml`](../../core/Cargo.toml) — Cargo-Feature.
  - [`core/src/interaction/accessibility.rs`](../../core/src/interaction/accessibility.rs)
    — RPC-Layer + 11 neue Tests.
  - [`core/src/interaction/mod.rs`](../../core/src/interaction/mod.rs)
    — Re-Exports.
  - [`core/src/config.rs`](../../core/src/config.rs) —
    `AccessibilityConfig`, Env-Loader, Config-Feld.
  - [`core/src/app.rs`](../../core/src/app.rs) — Wiring im
    `discover_accessibility`-Pfad (Imports + drei Zeilen
    Orchestrator-Aufruf).
  - [`core/src/ipc/server.rs`](../../core/src/ipc/server.rs) — sechs
    Test-`Config { … }`-Literale ergänzt um
    `accessibility: AccessibilityConfig::default()`.
  - Docs:
    [`docs/adr/ADR-0002-accessibility-rpc-readonly.md`](../adr/ADR-0002-accessibility-rpc-readonly.md),
    [`docs/api.md`](../api.md),
    [`docs/presence_desktop_interaction.md`](../presence_desktop_interaction.md),
    [`docs/SETUP.md`](../SETUP.md),
    [`docs/OPEN_WORK.md`](../OPEN_WORK.md),
    [`ROADMAP.md`](../../ROADMAP.md).
- **Neu:** dieser Review-Eintrag.
- **Unverändert:** UI (`ui/`), Provider-Resolver, Settings-Store,
  Audit-Modul, IPC-Protokoll-Schema, ABrain-Pfad, AdminBot-Pfad,
  OceanData-Pfad, smolitux-ui.

## 9. Follow-ups (Future Work, alle nicht priorisiert)

- **FA-1-Folge — Real registry client.** Eigener PR, der
  `atspi`+`zbus` als Cargo-Dependency einführt (hinter dem
  `accessibility_rpc`-Feature) und einen
  `AccessibilityRegistryClient` implementiert. Vorbedingung:
  Permission-Review (Flatpak `--talk-name=org.a11y.Bus`),
  Real-Host-AT-SPI-Messung, eigene Tests gegen einen lokalen
  `atspi`-Mock.
- **UI-Readout** für `verified` vs. `discovered`-Items. Optional;
  heutige UI rendert beide gleich.
- **FA-2 — Name-Match-ADR.** Hint-Echo gegen Registry-`GetChildren`
  + Name-Filter, ggf. mit `verified` für Treffer.
- **FA-3 — Toolkit-Gap-ADR** (GTK / Qt / Electron / Terminal).
  Erst nach FA-1-Folge, falls reale Lücken sichtbar werden.
- **FA-4 — Wayland-Portal-Fokus-ADR.** Separater Scope, kein
  Accessibility-Pfad.
- **Permission-Docs** (Flatpak / Snap / `.deb`) als Follow-up zu
  [ADR-0007](../adr/ADR-0007-packaging-decision.md) §11.
