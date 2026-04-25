# Capability Vocabulary

- **Status:** Draft / Proposed (Docs/Contract-only — keine Code-
  Implementation in PR 46).
- **Date:** 2026-04-25.
- **Scope:** Cross-Repo. Beschreibt das gemeinsame Vokabular für
  Capability-Klassen zwischen Smolit-Assistant, ABrain, AdminBot
  und OceanData.
- **Workstream:** E (Approval / Policy / Tool-Gating) — Folgearbeit
  aus PR 44 §12 und PR 45
  [`ADR-0005 §14 FA-3`](../adr/ADR-0005-adminbot-safety-boundary.md).
- **Companion:** [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](./AUDIT_CORRELATION_ID_SPEC.md).

> Leitprinzip: **Cross-repo actions need shared capability names
> before code.** Smolit-Assistant Approval-Risk, ABrain
> `action_intents`, AdminBot Tool-Calls und OceanData Decide-Access
> sollen sich auf eine gemeinsame Sprache von Capability-IDs
> einigen, bevor jemand sie als Code-Konstanten festschreibt.

---

## 1. Purpose

Heute sprechen die Repos verschiedene Sprachen für „was ist
diese Aktion":

- Smolit-Assistant Approval kennt
  [`risk` ∈ `low` / `medium` / `high`](../../core/src/approvals/request.rs)
  und Action-Kinds wie
  [`open_application` / `focus_window` / `type_text` / `send_shortcut`](../../core/src/interaction/action.rs).
- ABrain
  [Native Contract Draft](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md)
  spricht von `action_intents` mit eigenen Type-Strings.
- AdminBot kennt typisierte Tool-Namen (`adminbot_system_status`,
  `adminbot_service_status`, …) und Action-IDs (`system.status`,
  `service.restart`).
- OceanData spricht von `purpose` (`analytics`, `research`,
  `compute_to_data`, `export`) und `AccessDecision.effect`.

Ein cross-repo Capability-Vokabular zwingt diese Repos nicht in
ein einziges Schema, aber es definiert die **kanonische
Smolit-Assistant-Lesart** — und damit die Sprache, in der
[`ADR-0005`](../adr/ADR-0005-adminbot-safety-boundary.md),
[`AUDIT_CORRELATION_ID_SPEC.md`](./AUDIT_CORRELATION_ID_SPEC.md)
und ein zukünftiger `ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`
sprechen.

## 2. Scope

In Scope:

- Naming-Regeln für `capability_id`.
- Initiales Vokabular (heute genutzte + erwartbare zukünftige
  Capabilities), gespiegelt auf bestehende Smolit-Assistant-Code-
  Identitäten.
- Risk-Levels und ihre Bedeutung.
- Pflicht-Metadaten pro Capability.
- Mappings auf bestehende Smolit-Assistant-Actions, zukünftige
  AdminBot-Capabilities, zukünftige OceanData-Context-Capabilities.

Nicht in Scope:

- **Eine Runtime-Registry.** Dieses Dokument ist kein Code, kein
  Crate, kein TypeScript-Modul.
- **Eine `@smolitux/*`-Token-Datei.** Token-Vertrag bleibt im
  smolitux-ui-Repo.
- **Eine AdminBot-Action-Registry-Änderung.** AdminBot-seitige
  Action-Identitäten bleiben in der AdminBot-Repo-Hoheit.
- **Eine Provider-Whitelist-Erweiterung.**
- **Eine Policy Engine im „grand design"-Sinn.**
- **UI-Labels.** Eine Approval-Card zeigt
  `operator_visible_summary`, nicht den `capability_id` direkt.

## 3. Naming rules

| Regel | Beschreibung |
|-------|--------------|
| Form | `category.subcategory.action`, lowercase, dot-Separator |
| Charset | `[a-z0-9_]` für Segmente; `.` als Separator |
| Mindestsegmente | 2 (`category.action`); empfohlen 3 (`category.subcategory.action`) |
| Maximalsegmente | 4 |
| Maximallänge gesamt | 64 Zeichen |
| Stabilität | einmal vergeben, nicht umbenennen — nur deprecate + neu |
| Namensraum | runtime-neutral; **kein** Provider-Name als Präfix außer in `provider.*` |
| Verboten | Natural-Language-Labels (`open_browser_for_user`), Shell-Kommandos (`systemctl_restart_nginx`), Mehrsprachigkeit (`oeffne_app`) |

Beispiele:

- ✅ `interaction.open_application`
- ✅ `admin.action.dry_run`
- ✅ `data.context.query`
- ❌ `OpenApp` (CamelCase, kein dot-Path)
- ❌ `interaction-open-application` (Bindestrich statt Dot)
- ❌ `adminbot_system_status` (Underscore-Style aus AdminBot-IPC; gehört in die AdminBot-Action-Registry, nicht in den canonical capability namespace)

**Verhältnis zu existierenden Bezeichnern:**

- Smolit-Assistant
  [`InteractionKind::open_application`](../../core/src/interaction/action.rs)
  und Capability `interaction.open_application` referenzieren
  **dieselbe** Aktion. Der Capability-Name ist der **kanonische
  cross-repo Name**; der Code-Identifier bleibt der lokale Name.
- AdminBot Action-ID `system.status` ist **nicht** der Capability-
  Name. Die Capability ist `admin.status.read`; sie *bindet sich
  bei Bedarf* an die AdminBot-Action-ID `system.status`.

## 4. Capability categories

| Kategorie | Bedeutung | Beispielhafte Subcategories |
|-----------|-----------|------------------------------|
| `interaction.*` | Lokale Desktop-Interaktionen, die der Smolit-Assistant Core via Interaction-Layer ausführt. | `open_application`, `focus_window`, `type_text`, `send_shortcut` |
| `admin.*` | Admin-/System-/Ops-Aktionen, die nur AdminBot ausführt. Capability-Aufrufe gehen nie direkt durch Smolit-Assistant; siehe ADR-0005. | `status.read`, `capability.describe`, `action.dry_run`, `action.execute` |
| `data.*` | Daten-/Kontext-Capabilities (OceanData oder ein zukünftiger lokaler Kontext-Provider). | `context.query`, `context.summary`, `decide.access` |
| `assistant.*` | Smolit-Assistant-eigene Demo- und Planner-Pfade, die keine echten externen Effekte haben. | `plan_demo_action`, `demo.echo`, `demo.wait` |
| `provider.*` | Provider-Aufrufe in der Text/STT/TTS-Kette. | `text.generate`, `stt.transcribe`, `tts.speak` |
| `ui.*` | Reine UI-Operationen ohne Aktionspfad-Effekt (z. B. Toggle eines Dev-Panels). Optional, heute nicht benötigt. | `dev_panel.toggle` |
| `audit.*` | Audit-Lesepfade. | `audit.read_recent` |

Subcategories sind **nicht** abgeschlossen — neue Capabilities
können neue Subcategories einführen, sofern sie zur Kategorie
passen.

## 5. Initial vocabulary

Pro Eintrag ist `capability_id` der kanonische Name; `Maps to`
referenziert den heute existierenden Code-Identifier oder den
zukünftigen Vertragspunkt. **Spalten "approval", "audit",
"correlation"** beschreiben das *Soll-Verhalten* — sie sind kein
Spiegel des heute laufenden Code.

### 5.1 Interaction (heute teils real verdrahtet)

| `capability_id` | Maps to | `risk_level` | `approval_required` | `audit_required` | `correlation_id_required` | Status |
|-----------------|---------|--------------|---------------------|------------------|---------------------------|--------|
| `interaction.open_application` | [`InteractionKind::OpenApplication`](../../core/src/interaction/action.rs) (live, PR 25 Approval-Default = true) | `medium` | `true` | `true` | empfohlen — Pflicht nach Audit-Correlation-FA | live |
| `interaction.focus_window` | [`InteractionKind::FocusWindow`](../../core/src/interaction/action.rs) (live, PR 23 X11-Template-only, doppeltes Opt-in) | `medium` | `true` | `true` | empfohlen — Pflicht nach Audit-Correlation-FA | live (X11 only) |
| `interaction.type_text` | [`InteractionKind::TypeText`](../../core/src/interaction/action.rs) — heute `BackendUnsupported` | `high` | `true` | `true` | Pflicht | not implemented |
| `interaction.send_shortcut` | [`InteractionKind::SendShortcut`](../../core/src/interaction/action.rs) — heute `BackendUnsupported` | `high` | `true` | `true` | Pflicht | not implemented |

### 5.2 Assistant (Demo / Planner)

| `capability_id` | Maps to | `risk_level` | `approval_required` | `audit_required` | `correlation_id_required` | Status |
|-----------------|---------|--------------|---------------------|------------------|---------------------------|--------|
| `assistant.plan_demo_action` | [`request_approval_demo` / `plan_demo_action`](../../core/src/actions/plan.rs) (PR 17/18, Mock-only) | konfigurierbar (`low` / `medium`) | konfigurierbar (Test-Hebel) | `true` | empfohlen | live (Mock) |
| `assistant.demo.echo` | Demo-Plan-Kind `demo_echo` | `low` | `false` | `true` | empfohlen | live (Mock) |
| `assistant.demo.wait` | Demo-Plan-Kind `demo_wait` | `low` | `false` | `true` | empfohlen | live (Mock) |

### 5.3 Admin (alle zukünftig — siehe ADR-0005)

| `capability_id` | Maps to | `risk_level` | `approval_required` | `audit_required` | `correlation_id_required` | Status |
|-----------------|---------|--------------|---------------------|------------------|---------------------------|--------|
| `admin.status.read` | AdminBot `system.status` / `system.health` / `resource.snapshot` / `disk.usage` / `service.status` | `low` | `false` (transparent-only) | `true` (wenn im Aktionskontext) | empfohlen | not implemented |
| `admin.capability.describe` | AdminBot `describe_capabilities` | `low` | `false` | `true` (wenn im Aktionskontext) | empfohlen | not implemented |
| `admin.action.dry_run` | AdminBot dry-run für jede Capability mit `dry_run_supported` | `medium` | `true` | `true` | **Pflicht** | not implemented (ADR-0005 Stufe 1) |
| `admin.action.execute` | AdminBot Mutation, z. B. `service.restart` | `high` | `true` | `true` | **Pflicht** (fail-closed bei `correlation_missing`) | not implemented (ADR-0005 Stufe 2) |

### 5.4 Data (alle zukünftig — siehe ADR-0004)

| `capability_id` | Maps to | `risk_level` | `approval_required` | `audit_required` | `correlation_id_required` | Status |
|-----------------|---------|--------------|---------------------|------------------|---------------------------|--------|
| `data.context.query` | OceanData `query_context` / `list_available_contexts` | `low` lokal-read; `medium` wenn Ergebnis extern weitergeleitet | `false` für lokalen Read; policy-gegated für sensibel/extern | `true`, wenn extern weitergeleitet oder in Action eingespeist | empfohlen | not implemented |
| `data.context.summary` | OceanData `fetch_context_summary` | gleiche Regeln | gleiche Regeln | gleiche Regeln | empfohlen | not implemented |
| `data.decide.access` | OceanData `decide_access` | `low` (Decision-Read), Mutationsfolgen sind Caller-Risk | `false` | `true`, wenn Decision in Action fließt | empfohlen | not implemented |

### 5.5 Provider (heute live)

| `capability_id` | Maps to | `risk_level` | `approval_required` | `audit_required` | `correlation_id_required` | Status |
|-----------------|---------|--------------|---------------------|------------------|---------------------------|--------|
| `provider.text.generate` | Text-Provider-Resolver (`abrain` / `llamafile_local` / `local_http` / `cloud_http`) | `low` lokal; `medium` für `cloud_http` (opt-in) | `false` für normale Antworten; policy-gegated für externen Pfad mit privaten Daten | optional (heute nicht erfasst); FA, wenn Audit das Provider-Lifecycle abdeckt | empfohlen | live |
| `provider.stt.transcribe` | STT-Resolver (`command` / `whisper_cpp`) | `low` (lokal) | `false` | optional | empfohlen | live |
| `provider.tts.speak` | TTS-Resolver (`command` / `piper`) | `low` (lokal) | `false` | optional | empfohlen | live |

### 5.6 Audit (heute live, read-only)

| `capability_id` | Maps to | `risk_level` | `approval_required` | `audit_required` | `correlation_id_required` | Status |
|-----------------|---------|--------------|---------------------|------------------|---------------------------|--------|
| `audit.read_recent` | IPC `audit_recent` | `low` | `false` (Dev-/Debug-Read; siehe AUDIT_TRAIL) | **`false`** (Anti-Rekursion — siehe AUDIT_CORRELATION_ID_SPEC §9) | nicht erforderlich | live |

## 6. Risk levels

`risk_level` ist die kanonische Smolit-Assistant-Approval-Risk-
Klassifikation aus
[`core/src/approvals/request.rs`](../../core/src/approvals/request.rs)
(`RISK_LOW = "low"`, `RISK_MEDIUM = "medium"`, `RISK_HIGH = "high"`).
Die Bedeutung pro Stufe für eine Capability:

| Level | Bedeutung | Approval | Audit | Correlation (sobald Spec implementiert) |
|-------|-----------|----------|-------|------------------------------------------|
| `low` | Lokaler Read, Demo-Pfad, oder rein passiver Provider-Read. Effekte sind transparent oder reversibel. | nicht erforderlich (außer Kontextpolicy verlangt es) | empfohlen | nicht erforderlich |
| `medium` | Aktion mit echtem Effekt im User-Kontext oder Aktion mit `BackendUnsupported`-Default + Opt-in. Default heute z. B. für `interaction.open_application` und `interaction.focus_window`. | **Pflicht** (Default = true) | **Pflicht** | empfohlen |
| `high` | Privilegierte oder potenziell destruktive Mutation; AdminBot-Execute, `interaction.type_text` / `interaction.send_shortcut`. | **Pflicht** | **Pflicht** | **Pflicht**, fail-closed bei `correlation_missing` |

**Verschiebung der Klassifikation** ist möglich pro Capability,
aber **nur in Richtung höher**: eine Capability darf
„auto-upgraded" werden (z. B. wenn `cloud_http` aktiviert ist),
nicht stillschweigend abgesenkt.

## 7. Required metadata

Jede zukünftige Capability-Registry-Eintrag (Code, ADR-0005-FA-1
Capability-Contract-Doku, AdminBot-Action-Registry) muss die
folgenden Felder beschreiben — Feldnamen sind die *kanonischen
Smolit-Assistant-seitigen* Namen:

| Feld | Pflicht | Bedeutung |
|------|--------|-----------|
| `capability_id` | ✅ | Eindeutiger Name nach §3. |
| `title` | ✅ | Kurzer menschenlesbarer Titel (≤ 80 Zeichen). |
| `description` | ✅ | Eine Zeile, was die Capability tut. |
| `category` | ✅ | Eine der Kategorien aus §4. |
| `risk_level` | ✅ | `low` / `medium` / `high`. |
| `approval_required` | ✅ | `true` / `false`; Mutation ist immer `true`. |
| `audit_required` | ✅ | `true` / `false`; Mutation und User-Effekt sind immer `true`. |
| `correlation_id_required` | ✅ | `true` / `false`; Mutation ist immer `true` (sobald die Audit-Correlation-Spec implementiert ist). |
| `dry_run_supported` | ✅ | `true` / `false`; jede Mutation muss `true` haben. |
| `allowed_arguments_schema` | ✅ | Typisiertes Schema; freie Strings sind verboten. |
| `denied_arguments` | ✅ | Explizit verbotene Eingaben (Wildcards, Glob, Pipe). |
| `side_effects` | ✅ | Freie Beschreibung für Approval-Card-Summary. |
| `failure_modes` | ✅ | Liste benannter Fehlerklassen ([ADR-0005 §9](../adr/ADR-0005-adminbot-safety-boundary.md) als Vorlage). |
| `operator_visible_summary` | ✅ | Kuratierter Approval-Card-Text; **kein** Raw-Payload. |
| `timeout` | empfohlen | Pflicht-Cutoff in Millisekunden. |
| `rollback_supported` | optional | `true` / `false`; wenn `false`, hebt das die Risiko-Einstufung. |

## 8. Mapping to existing Smolit-Assistant actions

| Heute im Code | Capability |
|---------------|-----------|
| [`InteractionKind::OpenApplication`](../../core/src/interaction/action.rs) | `interaction.open_application` |
| [`InteractionKind::FocusWindow`](../../core/src/interaction/action.rs) | `interaction.focus_window` |
| [`InteractionKind::TypeText`](../../core/src/interaction/action.rs) (`BackendUnsupported`) | `interaction.type_text` |
| [`InteractionKind::SendShortcut`](../../core/src/interaction/action.rs) (`BackendUnsupported`) | `interaction.send_shortcut` |
| [`request_approval_demo` / `plan_demo_action`](../../core/src/actions/plan.rs) | `assistant.plan_demo_action` |
| Demo-Plan-Kind `demo_echo` | `assistant.demo.echo` |
| Demo-Plan-Kind `demo_wait` | `assistant.demo.wait` |
| Text-Provider-Pipeline (`abrain` / `llamafile_local` / `local_http` / `cloud_http`) | `provider.text.generate` |
| STT-Pipeline (`command` / `whisper_cpp`) | `provider.stt.transcribe` |
| TTS-Pipeline (`command` / `piper`) | `provider.tts.speak` |
| IPC `audit_recent` | `audit.read_recent` |

Diese Mappings sind **rein dokumentarisch**. Es entsteht kein
Code, der `capability_id`-Strings auf Code-Identifier wirft.

## 9. Mapping to future AdminBot capabilities

| AdminBot-Action-ID (extern) | Capability (canonical) | Stufe in [ADR-0005 §5.2](../adr/ADR-0005-adminbot-safety-boundary.md) |
|------------------------------|------------------------|-----------------------------------------------------------------------|
| `system.status` | `admin.status.read` | Stufe 0 |
| `system.health` | `admin.status.read` | Stufe 0 |
| `resource.snapshot` | `admin.status.read` | Stufe 0 |
| `disk.usage` | `admin.status.read` | Stufe 0 |
| `service.status` | `admin.status.read` | Stufe 0 |
| `describe_capabilities` | `admin.capability.describe` | Stufe 0 |
| (alle Mutationen mit `dry_run = true`) | `admin.action.dry_run` | Stufe 1 |
| `service.restart` (mit `dry_run = false`) | `admin.action.execute` | Stufe 2 |
| (alle weiteren AdminBot-Mutationen) | `admin.action.execute` | Stufe 2 |

**Wichtig:** Die AdminBot-Action-IDs bleiben in der AdminBot-Repo-
Hoheit. Smolit-Assistant ruft sie nie direkt unter dem
canonical-capability-Namen auf — der canonical name ist die
Außenseite der Smolit-Assistant-Approval-/Audit-Sicht; das
AdminBot-Action-Mapping passiert hinter dem Capability-Contract
(siehe ADR-0005 §6, Future Work `ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`).

## 10. Mapping to OceanData context capabilities

| OceanData-Surface (extern) | Capability (canonical) |
|----------------------------|------------------------|
| `POST /decide/access` | `data.decide.access` |
| `query_context` / `list_available_contexts` (zukünftig) | `data.context.query` |
| `fetch_context_summary` (zukünftig) | `data.context.summary` |

OceanData bleibt Decide-Access-Quelle ohne Aktionsrecht. Die
Capability-Klassifikation hier ist die Smolit-Assistant-seitige
Lesart der OceanData-Antworten — die OceanData-Seite hat
kanonisch ihre eigenen `purpose`-/`AccessDecision`-Vokabularien
(siehe
[`Modularium/EcoSphereNetwork OceanData docs/integrations/`](https://github.com/EcoSphereNetwork/OceanData/tree/main/docs/integrations)).

## 11. Non-goals

- **Kein Code.** Keine Konstanten in `core/src/`.
- **Keine Runtime-Registry.** Diese Datei beschreibt Sprache, nicht
  Datenstruktur.
- **Keine AdminBot-Capability-Registry-Änderung.**
- **Keine Provider-Whitelist-Erweiterung** (siehe
  [`docs/provider_fallback_and_settings_architecture.md`](../provider_fallback_and_settings_architecture.md)).
- **Keine Policy-Engine** im „grand design"-Sinn.
- **Kein UI-Label-Replacement** — eine Approval-Card zeigt
  weiterhin `operator_visible_summary`, nicht den `capability_id`.
- **Keine Edits** an ABrain / Smolit_AdminBot / OceanData /
  smolitux-ui.
- **Keine Token-Implementation** auf der smolitux-ui-Seite.

## 12. Future work

Reihenfolge nicht bindend; alle Schritte hinter eigenen PRs:

- **FA-1.** Code-Konstanten in `core/src/` für Capability-IDs der
  heute live Capabilities (`interaction.*`, `assistant.*`,
  `provider.*`, `audit.*`). Reine String-Konstanten, keine
  Registry.
- **FA-2.** Validation-Tests gegen die Naming-Regeln aus §3.
- **FA-3.** AdminBot-Capability-Mapping in einem zukünftigen
  `docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`
  ([ADR-0005 §14 FA-1](../adr/ADR-0005-adminbot-safety-boundary.md)).
- **FA-4.** Policy-Regeln, die `capability_id` als
  Eingabe nehmen (z. B. „blocke `provider.text.generate` mit
  `cloud_http`-Provider, wenn Privacy-Mode aktiv").
- **FA-5.** UI-Display-Names — Approval-Card-Texte pro
  Capability-ID, lokalisiert.
- **FA-6.** Audit-Sanitization-Erweiterung: `capability_id` darf
  in Audit-Summaries durchgereicht werden (im Gegensatz zu rohen
  Argumenten — siehe
  [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)).
