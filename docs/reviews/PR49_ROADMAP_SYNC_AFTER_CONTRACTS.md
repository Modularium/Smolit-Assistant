# PR 49 — Roadmap Sync after Contracts (PR 43–48)

- **Datum:** 2026-04-25.
- **Typ:** Docs-only Reality-Check / Roadmap-Sync.
- **Scope:** ROADMAP.md, docs/OPEN_WORK.md, docs/reviews/README.md.
  Kein Code, keine ADR-Neuanlage, keine Contract-Neuanlage.

## 1. Scope

PR 43–48 haben in schneller Folge eine Contract-Serie eingeführt
(ABrain Native Contract Draft Link, Ecosystem Integration
Contracts Matrix, AdminBot Safety Boundary ADR + Capability
Contract, Audit Correlation ID Spec + Capability Vocabulary,
OceanData Context Provider SPI ADR). Während dieser Serie wurden
Roadmap-Vorschläge teilweise verschoben (PR 47 wechselte von
„OceanData Context Provider SPI ADR" auf „AdminBot Capability
Contract"; ADR-0006 landete als PR 48 statt PR 47). Dieses Review
synchronisiert ROADMAP, OPEN_WORK und Reviews-Index, **bevor** der
nächste Code-Spike folgt.

## 2. Why this sync exists

- **Roadmap-Sequenz spiegelt nicht mehr die tatsächliche Reihenfolge.**
  PR 47 wird in einigen ROADMAP-Vorschlagsblöcken noch als
  Vorgänger des aktuellen ADR-0006 referenziert.
- **OPEN_WORK Workstream I** trägt noch einen veralteten Eintrag
  „PR 48 — Release Packaging Decision ADR", obwohl PR 48 jetzt
  ADR-0006 ist; der Packaging-ADR rückt nach hinten.
- **§6.3 Header** sagt noch „drei docs/ADR-Folge-PRs aus PR 44";
  realistisch sind es **vier** (PR 45 + 46 + 47 + 48).
- **Reviews-Index** trägt PR 49 nicht.
- **Runtime-Baseline** (kein abrain_native, kein
  oceandata_context, kein AdminBot-Adapter, kein
  `correlation_id`-Wire-Feld, kein `capability_id`-Konstante) ist
  durch PR 43–48 nicht verändert worden — das soll sichtbar
  bleiben, sonst entsteht Lese-Drift („wenn so viele ADRs gelandet
  sind, dann muss ja Code dahinter sein").

## 3. PR 43–48 actual sequence

| PR | Workstream | Gegenstand | Status |
|----|-----------|-----------|--------|
| 43 | H | ABrain Native Contract Draft Link — ADR-0003 verlinkt zusätzlich [ABrain `docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md). | Docs-only, gelandet |
| 44 | A | Ecosystem Integration Contracts Matrix — [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](../contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) für alle acht Cross-Repo-Pairs. | Docs-only, gelandet |
| 45 | E | AdminBot Safety Boundary ADR — [`ADR-0005`](../adr/ADR-0005-adminbot-safety-boundary.md). | Docs/ADR-only, Proposed |
| 46 | E | Audit Correlation ID Spec + Capability Vocabulary — [`AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md) + [`CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md). | Docs/Contract-only, Draft / Proposed |
| 47 | E | AdminBot Safety Boundary Contract — [`ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`](../contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md). | Docs/Contract-only, Draft / Proposed |
| 48 | K | OceanData Context Provider SPI ADR — [`ADR-0006`](../adr/ADR-0006-oceandata-context-provider-spi.md). | Docs/ADR-only, Proposed |

## 4. Current contract baseline

| Dokument | Pfad | Status |
|----------|------|--------|
| Smolitux Design Contract | [ADR-0001](../adr/ADR-0001-smolitux-design-contract.md) | Accepted |
| Accessibility RPC Read-only | [ADR-0002](../adr/ADR-0002-accessibility-rpc-readonly.md) | Accepted |
| ABrain Native Integration Path | [ADR-0003](../adr/ADR-0003-abrain-native-integration.md) | Proposed |
| OceanData Data-Layer Integration Path | [ADR-0004](../adr/ADR-0004-oceandata-data-layer-integration.md) | Proposed |
| AdminBot Safety Boundary | [ADR-0005](../adr/ADR-0005-adminbot-safety-boundary.md) | Proposed |
| OceanData Context Provider SPI | [ADR-0006](../adr/ADR-0006-oceandata-context-provider-spi.md) | Proposed |
| Ecosystem Integration Contracts Matrix | [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](../contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md) | Docs-only |
| Audit Correlation ID Spec | [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md) | Draft / Proposed |
| Capability Vocabulary | [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md) | Draft / Proposed |
| AdminBot Safety Boundary Contract | [`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`](../contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md) | Draft / Proposed |

## 5. Runtime baseline unchanged

PR 43–48 sind **alle** Docs/ADR/Contract-only. Der Runtime-Stand
ist seit dem letzten Code-PR (PR 42, CI Hardening, 2026-04-25)
unverändert:

- **Kein** `abrain_native`-Provider-Kind.
- **Kein** AdminBot-Adapter, kein AdminBot-Client, kein
  `adminbot_*`-IPC-Command.
- **Kein** `oceandata_context`-Provider; `KNOWN_TEXT_KINDS` bleibt
  `[abrain, llamafile_local, local_http, cloud_http]`.
- **Kein** `correlation_id`-Feld in `AuditEvent`, in
  Action-Events oder im IPC-Wire-Format. (`grep correlation_id
  core/` ist leer.)
- **Kein** `capability_id`-Code-Konstante. (`grep capability_id
  core/` ist leer.)
- **Keine** IPC-Schema-Änderung durch PR 43–48.
- **Keine** Provider-Whitelist-Erweiterung.
- **Keine** Audit-Persistenz, kein Export.
- **`cargo test --locked`** weiterhin 398 passed; 0 failed.
- **`scripts/run_overlay_verification.sh settings-shell-smoke`**
  weiterhin PASS.

## 6. Corrected next PR sequence

Gewählte Reihenfolge (konservativ — Docs/ADR vor Code):

| PR | Gegenstand | Typ |
|----|-----------|-----|
| 50 | **v0.2 Release Gate Review** — Docs-only Reality-Check pro Workstream A–K, „was ist heute auf main, was bleibt nicht implementiert", Review-Form analog [PR31 Roadmap Checkpoint](./PR31_ROADMAP_CHECKPOINT.md). | Docs-only |
| 51 | **Packaging Decision ADR** — `.deb` vs. AppImage vs. Flatpak, Signing-Chain, Auto-Update-Linie. ADR vor Code. | Docs/ADR-only |
| 52 | **Accessibility RPC FA-1 Spike** — erster Code-Spike hinter `accessibility_rpc`-Feature-Flag (read-only `GetChildren` auf Registry-Root, default-off). Implementation-Eintritt für ADR-0002 FA-1. | Code-Spike, default-off |
| 53 | **Correlation ID Runtime Spike** — `correlation_id`-Feld in `AuditEvent` hinter Feature-Flag, default-off. Implementation-Eintritt für AUDIT_CORRELATION_ID_SPEC FA-1. | Code-Spike, default-off |
| 54 | **Capability Constants Runtime Spike** — String-Konstanten für die heute live Capabilities (`interaction.*` / `assistant.*` / `provider.*` / `audit.*`); reine `pub const`-Werte plus Validation-Tests, **keine** Registry-Datenstruktur. Implementation-Eintritt für CAPABILITY_VOCABULARY FA-1. | Code-Spike, additiv |
| 55 | **OceanData Privacy / Redaction ADR** — Eintrittsbedingung für `redaction = external_safe` aus ADR-0006 §10 + ADR-0004 FA-5. ADR vor Code. | Docs/ADR-only |

### Begründung der Reihenfolge

- **PR 50 Release Gate Review zuerst** schafft eine
  geschlossene Sicht auf den heutigen Code- und Doku-Stand,
  bevor wieder Code-Spikes kommen — analog wie PR 31 nach der
  PR-21–30-Stabilisierungsserie.
- **PR 51 Packaging ADR vor jedem Code-Spike**, weil ein Spike
  hinter Feature-Flag implizit eine erste Release-Frage stellt
  („wo geht das Binary hin?"). Der ADR ist klein, Docs-only und
  blockt nicht.
- **PR 52 Accessibility RPC FA-1** als erster Code-Spike, weil
  ADR-0002 die älteste fertige Spike-Vorbereitung trägt und der
  Pfad strikt isoliert ist (`accessibility_rpc`-Feature-Flag,
  read-only AT-SPI, kein `DoAction`).
- **PR 53/PR 54** verlängern PR 46 von der Doku in den Code,
  beide additiv und default-off. PR 53 (`correlation_id` als
  optionales Feld in `AuditEvent`) ist die Voraussetzung dafür,
  dass spätere Spikes (AdminBot-Stufe-0, OceanData-Spike) im
  Audit korreliert sind.
- **PR 55 OceanData Privacy / Redaction ADR** als Eintritts­
  bedingung für jeden OceanData-Spike — bewusst nach den
  Audit-/Capability-Spikes, weil das Privacy-Layer auf
  `correlation_id` und `capability_id` aufsetzen wird.

Diese Reihenfolge ist **nicht bindend** — wenn die Praxis zeigt,
dass eine andere Sequenz besser passt, kommt ein Folge-Sync.

## 7. Drift watchlist

Punkte, die in der nächsten PR-Reihe eingehalten werden müssen,
weil PR 43–48 sie sehr explizit fixiert haben:

- **OceanData darf nirgends als UI-Library, Design-System-Quelle,
  Token-Quelle oder Text-LLM-Provider beschrieben werden.**
  ADR-0004, ADR-0006, GLOSSARY und ECOSYSTEM_INTEGRATION_CONTRACTS
  halten diese Linie.
- **smolitux-ui darf nirgends als Data-Layer beschrieben werden.**
  ADR-0001 hält die Linie.
- **ABrain ≠ AdminBot.** Beide haben getrennte ADRs, getrennte
  Capability-Klassen (`assistant.*` / `admin.*`) und getrennte
  Beziehungen (ABrain ↔ AdminBot ist außerhalb von Smolit-
  Assistant; Smolit-Assistant ↔ AdminBot ist *missing by design*).
- **AdminBot ist nicht Brain.** AdminBot ist Executor mit
  Policy-Boundary; Reasoning bleibt in ABrain.
- **`abrain_native` / `oceandata_context` / `adminbot_*` sind
  keine Wire-Felder oder Code-Konstanten.** Sie tauchen nur in
  Docs auf, mit klarem „not implemented"-Marker.
- **`correlation_id` und `capability_id` sind keine
  Wire-/Runtime-Felder.** Sie sind Soll-Form, kein Ist.
- **Naming-Drift Agent-NN ↔ ABrain** liegt im AdminBot-Repo —
  niemand zieht sie nach Smolit-Assistant.
- **`KNOWN_TEXT_KINDS` darf nicht erweitert werden,** weder durch
  `oceandata_context`, noch durch `adminbot_*`. Beides sind
  separate Achsen.
- **Approval-Default = true** für jede mutierende Capability
  bleibt. Keine Auto-Approval-Heuristik.

## 8. Verification

PR 49 ist Docs-only.

- `cargo test --manifest-path core/Cargo.toml --locked` → 398
  passed, 0 failed (unverändert).
- `scripts/run_overlay_verification.sh settings-shell-smoke` →
  PASS (unverändert).
- `rg "PR 4[3-8]" ROADMAP.md docs/OPEN_WORK.md
  docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md` zeigt eine
  konsistente Sequenz.
- `rg "abrain_native|oceandata_context|adminbot_" core/` ist
  leer.
- `rg "correlation_id|capability_id" core/` ist leer.
- `git diff --name-only` zeigt nur Smolit-Assistant-Dateien.
