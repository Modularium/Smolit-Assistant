# AdminBot Safety Boundary Contract

- **Status:** Draft / Proposed (Docs/Contract-only — keine Code-
  Implementation in PR 47).
- **Date:** 2026-04-25.
- **Scope:** Smolit-Assistant-seitiger Capability-Contract für eine
  hypothetische zukünftige direkte AdminBot-Integration. Beschreibt
  *welche* Capability-Klassen Smolit-Assistant überhaupt akzeptieren
  würde, *welche* deny-by-default sind, und *welche* Pflichtfelder
  pro Capability-Eintrag gelten.
- **Workstream:** E (Approval / Policy / Tool-Gating) — Folgearbeit
  aus PR 45
  [`ADR-0005 §14 FA-1`](../adr/ADR-0005-adminbot-safety-boundary.md).
- **Companion:**
  [`docs/contracts/CAPABILITY_VOCABULARY.md`](./CAPABILITY_VOCABULARY.md),
  [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](./AUDIT_CORRELATION_ID_SPEC.md),
  [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./ECOSYSTEM_INTEGRATION_CONTRACTS.md).

> Leitprinzip: **Define allowed AdminBot capabilities before any
> AdminBot integration code exists.** Dieses Dokument ist die
> Eintrittsbedingung für einen späteren Spike — kein API-Vertrag
> mit AdminBot, kein Wire-Schema, kein Code.

---

## 1. Purpose

[ADR-0005](../adr/ADR-0005-adminbot-safety-boundary.md) hat
festgelegt, dass ein direkter Smolit-Assistant ↔ AdminBot Pfad
*read-only / status-first, capability-whitelisted, ohne Shell-
Pfad, ohne generischen Tool-Passthrough* sein muss. Dieser
Contract gibt jedem dieser Worte einen **konkreten Eintrag** mit
Pflichtfeldern und einer expliziten Deny-Liste.

Was dieses Dokument **nicht** ist:

- **Kein AdminBot-API-Dokument.** Wire-Format, IPC-Spezifikation,
  systemd-/polkit-Bindung, `SO_PEERCRED`-Verhalten und die
  AdminBot-Action-Registry leben in der AdminBot-Repo-Hoheit
  ([`Modularium/Smolit_AdminBot docs/adminbot_v2/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/adminbot_v2)).
- **Kein Code.** Keine Konstanten in `core/src/`, keine
  Capability-Registry-Struktur, kein AdminBot-Client-Crate.
- **Kein Mirror der AdminBot Action Registry.** AdminBot kennt
  Action-IDs (`system.status`, `service.restart`, …); dieser
  Contract spricht von Smolit-Assistant-seitigen
  `capability_id`-Klassen aus
  [CAPABILITY_VOCABULARY.md](./CAPABILITY_VOCABULARY.md).

Was dieses Dokument **ist**:

- Die kanonische Liste, welche AdminBot-Capability-**Klassen**
  Smolit-Assistant überhaupt akzeptieren *dürfte*, sortiert nach
  Risk und Stufe.
- Die Pflichtfelder, die jeder Eintrag tragen muss.
- Eine deny-by-default Baseline für gefährliche Klassen
  (Shell, Sudo, unscoped Filesystem-Write, Secret-Read, …).

## 2. Scope

In Scope:

- **Klassen** akzeptierter Capabilities (`admin.status.read`,
  `admin.capability.describe`, `admin.action.dry_run`,
  `admin.action.execute`).
- Pflichtfelder pro Eintrag (`contract_version`, `capability_id`,
  `risk_level`, …).
- Approval-/Policy-Anforderungen pro Klasse.
- Audit-Erfassungsregeln pro Klasse.
- Transport-/Auth-Erwartungen für eine erste Verdrahtung.
- Failure-Mode-Vokabular.
- Versionsregel.

Nicht in Scope:

- Eine Implementation des AdminBot-Clients in `core/src/`.
- Eine Wire-Änderung in [`docs/api.md`](../api.md).
- Eine OpenTelemetry-Integration.
- Eine Audit-Persistenz.
- Eine Cloud-/Remote-AdminBot-Variante.
- Eine Änderung an der AdminBot-Action-Registry oder am
  AdminBot-IPC-Format.

## 3. Relationship to ADR-0005

[ADR-0005](../adr/ADR-0005-adminbot-safety-boundary.md) ist die
**Safety-Entscheidung**: read-only-first, capability-whitelisted,
kein Shell, kein Bypass via ABrain `action_intents` / Desktop
Interaction / OceanData. Dieses Dokument ist der **erste
Capability-Contract-Entwurf** aus
[`ADR-0005 §14 FA-1`](../adr/ADR-0005-adminbot-safety-boundary.md).

| Aussage in ADR-0005 | Konkretisierung hier |
|---------------------|----------------------|
| §4 Decision: „read-only / status-first" | §8 Klasse 1 (`admin.status.read`) |
| §4 Decision: „capability-whitelisted" | §7 Capability-Schema + §8 vier Initial-Klassen |
| §4 Decision: „kein generischer Shell-Pfad" | §9 Deny-Liste |
| §5.2 Stufe 0/1/2 | §8.1/8.3/8.4 Klassen 1+3+4 |
| §6 Pflichtfelder | §7 Capability-Schema (Pflichtfelder dieser Tabelle) |
| §7 Approval/Policy/Audit | §10 + §11 |
| §8 Transport/Auth | §12 |
| §9 Failure modes | §13 |

ADR-0005 gewinnt bei jedem Konflikt; dieser Contract ist die
operative Lesart.

## 4. Relationship to Capability Vocabulary

`capability_id` muss aus
[`CAPABILITY_VOCABULARY.md`](./CAPABILITY_VOCABULARY.md) §3 (Naming
Rules) stammen, sonst ist der Eintrag invalide. Die initialen
AdminBot-Capabilities sind in
[CAPABILITY_VOCABULARY §5.3](./CAPABILITY_VOCABULARY.md) bereits
benannt:

| `capability_id` | Status laut Vokabular | Stufe in [ADR-0005 §5.2](../adr/ADR-0005-adminbot-safety-boundary.md) |
|-----------------|------------------------|-----------------------------------------------------------------------|
| `admin.status.read` | not implemented | Stufe 0 |
| `admin.capability.describe` | not implemented | Stufe 0 |
| `admin.action.dry_run` | not implemented | Stufe 1 |
| `admin.action.execute` | not implemented | Stufe 2 |

Wenn dieser Contract eine *neue* Capability einführen will (z. B.
`admin.diagnostic.export`), muss sie *zuerst* in
CAPABILITY_VOCABULARY.md ergänzt werden — dieser Contract erfindet
keine `capability_id` einseitig.

## 5. Relationship to Audit Correlation ID Spec

Format und Lebenszyklus von `correlation_id` sind in
[`AUDIT_CORRELATION_ID_SPEC.md`](./AUDIT_CORRELATION_ID_SPEC.md)
fixiert. Pro Capability gilt:

- **Status / Read-only Capabilities:** `correlation_id` optional;
  empfohlen, wenn die Anfrage Teil eines Aktionsflusses ist.
- **Dry-run Capabilities:** `correlation_id` **Pflicht**.
- **Execute Capabilities:** `correlation_id` **Pflicht**.
  Fail-closed bei `missing_correlation_id` /
  `invalid_correlation_id` (siehe
  [AUDIT_CORRELATION_ID_SPEC §10](./AUDIT_CORRELATION_ID_SPEC.md)).

Der Contract beschreibt Soll-Verhalten; die `correlation_id`-
*Implementation* (Feld in `AuditEvent`, Cross-Repo-Wire) bleibt
hinter eigenen Folge-PRs (siehe AUDIT_CORRELATION_ID_SPEC §12).

## 6. Contract object model

Jeder akzeptierte Capability-Eintrag hat folgende kanonische Form:

```json
{
  "contract_version": "0.1",
  "capability_id": "admin.status.read",
  "capability_name": "Read AdminBot status",
  "risk_level": "low",
  "allowed_arguments_schema": {},
  "denied_arguments": [],
  "dry_run_supported": false,
  "approval_required": false,
  "audit_required": true,
  "correlation_id_required": false,
  "timeout_ms": 3000,
  "rollback_supported": false,
  "side_effects": [],
  "operator_visible_summary": "Read sanitized AdminBot health/version/summary status.",
  "failure_modes": [
    "unavailable",
    "auth_failed",
    "capability_not_allowed",
    "timeout",
    "invalid_response"
  ]
}
```

**Pflichtfelder** (Reihenfolge nicht verbindlich, Vorhandensein ist es):

- `contract_version` — semver-Form (`"0.1"`); Bump bei jeder
  Schema-Änderung dieses Contracts (siehe §14).
- `capability_id` — kanonisch aus
  [CAPABILITY_VOCABULARY §3](./CAPABILITY_VOCABULARY.md).
- `capability_name` — menschenlesbarer Kurztitel, ≤ 80 Zeichen.
- `risk_level` — `"low"` / `"medium"` / `"high"`, bindet an
  [`core/src/approvals/request.rs`](../../core/src/approvals/request.rs)
  `RISK_LOW` / `RISK_MEDIUM` / `RISK_HIGH`.
- `allowed_arguments_schema` — typisiertes Schema; freie Strings
  sind verboten. Leeres Objekt (`{}`) bedeutet „keine Argumente
  außer optionalem `correlation_id`".
- `denied_arguments` — explizite Negativliste (Wildcards, Glob,
  Pipe, Shell-Tokens, Pfad-Traversal, …).
- `dry_run_supported` — Boolean. Jede Mutation muss `true` haben.
- `approval_required` — Boolean. Mutation = `true`. Read kann
  `false` sein.
- `audit_required` — Boolean. Mutation und User-sichtbarer Effekt
  = `true`.
- `correlation_id_required` — Boolean. Mutation = `true`.
- `timeout_ms` — Integer, Pflicht-Cutoff für die Capability.
- `rollback_supported` — Boolean. `false` hebt die Risiko-
  Einstufung (siehe §10).
- `side_effects` — Liste freier, kuratierter Strings für Approval-
  Card-Summary; **keine** rohen Argumente, **keine** Shell-Tokens.
- `operator_visible_summary` — kuratierter Approval-Card-Text,
  ≤ 140 Zeichen, **kein** Raw-Payload.
- `failure_modes` — Liste benannter Fehlerklassen aus §13. Jeder
  Eintrag muss in §13 enthalten sein.

Optionale Felder:

- `target_capability_id` — bei `admin.action.dry_run` /
  `admin.action.execute`: das von dieser Klasse *gemeinte*
  AdminBot-Action-Mapping. Das Mapping passiert hinter dem
  Capability-Contract; AdminBot-Action-IDs leben in der
  AdminBot-Repo-Hoheit.
- `dry_run_reference` — bei `admin.action.execute`: Referenz auf
  einen vorausgegangenen Dry-run (Future Work, siehe §17).

## 7. Capability schema

| Feldgruppe | Pflicht/Optional | Beispielwerte |
|------------|------------------|---------------|
| Identity | `contract_version`, `capability_id`, `capability_name` | `"0.1"`, `"admin.status.read"`, `"Read AdminBot status"` |
| Risk | `risk_level` | `"low"` / `"medium"` / `"high"` |
| Arguments | `allowed_arguments_schema`, `denied_arguments` | `{ "scope": "summary|health|version" }`; `["raw_logs", "secrets", "config_dump"]` |
| Modes | `dry_run_supported`, `approval_required`, `audit_required`, `correlation_id_required` | Booleans |
| Bounds | `timeout_ms`, `rollback_supported` | `3000`; `false` |
| Audit-Sichtbarkeit | `side_effects`, `operator_visible_summary` | `[]`; `"…"` |
| Failure-Vokabular | `failure_modes` | siehe §13 |

Naming-Regeln aus
[CAPABILITY_VOCABULARY §3](./CAPABILITY_VOCABULARY.md) gelten
unverändert (lowercase dot-path, runtime-neutral, keine
Shell-Kommandos als IDs, keine Natural-Language-Labels).

## 8. Initial capability set

Vier Klassen, bewusst klein. Keine davon ist heute
implementiert — `Status` in jeder Tabelle ist `not implemented`.

### 8.1 `admin.status.read` (Stufe 0)

Read-only sanitized status (`health` / `version` / `summary`). Maps
auf AdminBot `R0` Read-Klassen wie `system.status`,
`system.health`, `service.status`, `disk.usage` (Liste lebt in der
AdminBot-Action-Registry, nicht hier).

| Feld | Wert |
|------|------|
| `risk_level` | `"low"` |
| `approval_required` | `false` (transparent-only) |
| `audit_required` | `true`, sobald die Capability in einem Aktionskontext genutzt wird; sonst optional |
| `correlation_id_required` | `false` außer im Aktionskontext |
| `dry_run_supported` | `false` |
| `timeout_ms` | `3000` |
| `rollback_supported` | `false` |
| `side_effects` | keine |
| Erlaubte Argumente | `scope: "summary" | "health" | "version"` |
| Denied Arguments | rohe Logs, Secrets, vollständige Config-Dumps, Pfad-Filter, regex-Filter |
| Status | not implemented |

### 8.2 `admin.capability.describe` (Stufe 0)

Read-only Beschreibung der vom AdminBot heute angebotenen
Capabilities (Action-Registry-Read). Keine Argumentwerte, keine
Filter mit freier Syntax.

| Feld | Wert |
|------|------|
| `risk_level` | `"low"` |
| `approval_required` | `false` |
| `audit_required` | `true` |
| `correlation_id_required` | `false` außer im Aktionskontext |
| `dry_run_supported` | `false` |
| `timeout_ms` | `3000` |
| `rollback_supported` | `false` |
| `side_effects` | keine |
| Erlaubte Argumente | `filter?: string` (kuratierter Filter, keine Regex/Glob); maximal eine Capability-Klasse pro Anfrage |
| Denied Arguments | beliebige Action-Namen, Shell-Snippets, `*`/`**`-Glob, regex, vollständiger Registry-Dump mit Secrets |
| Status | not implemented |

### 8.3 `admin.action.dry_run` (Stufe 1)

Mutationsabsicht-Vorschau ohne Mutation. Jede Mutation **muss**
zuerst durch dry_run laufen, ehe Stufe 2 zulässig ist.

| Feld | Wert |
|------|------|
| `risk_level` | `"medium"` |
| `approval_required` | `true` |
| `audit_required` | `true` |
| `correlation_id_required` | `true` |
| `dry_run_supported` | `true` (per Definition) |
| `timeout_ms` | `5000` |
| `rollback_supported` | `false` (kein Effekt zum Rollback) |
| `side_effects` | keine Mutation; ggf. Read der Ziel-Status |
| Erlaubte Argumente | `target_capability_id`, `arguments` (typisiert nach Ziel-Schema), `reason` (kuratiert, ≤ 140 Zeichen) |
| Denied Arguments | Shell-Tokens, `sudo`, beliebige Executable-Pfade, rohe Skripte, Secrets, externe URLs, Pfad-Traversal |
| Notes | Denied/expired/cancelled Approval bedeutet kein AdminBot-Aufruf. Ein dry_run für eine **deny-by-default** Klasse aus §9 ist immer `refused_by_policy`. |
| Status | not implemented |

### 8.4 `admin.action.execute` (Stufe 2)

Mutation. Hinter eigenem Capability-Contract pro `target_capability_id`
(Future Work — siehe §17). Diese Klasse ist nicht direkt aufrufbar
ohne dass eine **konkrete** Ziel-Capability eigene
`allowed_arguments_schema`-/`denied_arguments`-/`failure_modes`-
Einträge bekommt.

| Feld | Wert |
|------|------|
| `risk_level` | `"high"` |
| `approval_required` | `true` |
| `audit_required` | `true` |
| `correlation_id_required` | `true` (fail-closed bei `correlation_missing`) |
| `dry_run_supported` | empfohlene Voraussetzung; pro Ziel-Capability fixiert |
| `timeout_ms` | abhängig von Ziel; Defaultsperre ohne Override |
| `rollback_supported` | abhängig von Ziel; `false` triggert höhere Approval-Anforderung |
| `side_effects` | Mutation möglich |
| Erlaubte Argumente | `target_capability_id`, `arguments` (typisiert nach Ziel-Schema), `reason`, optional `dry_run_reference` (Future Work) |
| Denied Arguments | generische Shell, freiform Command, unscoped Filesystem-Write, Secret-Read, Privilege-Escalation, unbeschränkte Netzwerk-Operation, destruktive Operation ohne dedizierten Capability-Contract |
| Notes | **Nicht implementierbar**, bis eine konkrete Ziel-Capability ihren eigenen Schema-Eintrag hat. Dieser Eintrag ist die Klasse, nicht eine konkrete Aktion. |
| Status | not implemented |

## 9. Denied capability classes

**Deny-by-default** ohne dedizierten Folge-ADR und eigenen
Capability-Contract. Diese Liste ist eine *Baseline*, nicht
abschließend — alles was diesen Klassen ähnelt, ist ebenfalls
denied.

| Klasse | Begründung |
|--------|-----------|
| `admin.shell.execute` | Generische Shell-Ausführung; widerspricht ADR-0005 §4 und ist im AdminBot-Repo selbst explizit ausgeschlossen. |
| `admin.sudo.execute` | Privilege-Escalation am Approval-Gate vorbei. |
| `admin.filesystem.write_unscoped` | Unbeschränkter Schreibzugriff; kein Schema, keine Rollback-Strategie. |
| `admin.secret.read` | Secret-Exfiltration; widerspricht §11 Audit-Sanitization und Smolit-Assistant Secret-Store-Linie. |
| `admin.network.exfiltrate` | Outbound-Netzwerk ohne Inhalt-Kontrolle. |
| `admin.process.kill_unscoped` | Beliebiger Prozess-Tod; potenziell systemkritisch. |
| `admin.service.restart_unscoped` | Restart ohne Ziel-Whitelist; AdminBot-Repo gibt `service.restart` nur mit fester Service-Bindung frei. |
| `admin.package.install_unscoped` | Package-Manager-Aufruf ohne Quelle/Signatur-Vertrag. |
| `admin.user.modify` | User-/Group-Mutation. |
| `admin.auth.modify` | Auth-Stack-Mutation (PAM, polkit, sudoers). |
| `admin.backup.delete` | Destruktive Backup-Operation. |
| `admin.audit.clear` | Audit-Manipulation widerspricht §11. |
| `admin.policy.disable` | Policy-Bypass widerspricht ADR-0005 §4. |

Eine zukünftige Aufnahme einer dieser Klassen in den Contract
verlangt:

1. einen eigenen ADR (nicht ADR-0005 als Erweiterung; eigener
   ADR mit eigenem Threat Model),
2. einen Eintrag in
   [CAPABILITY_VOCABULARY.md](./CAPABILITY_VOCABULARY.md),
3. einen separaten Capability-Contract-Entry in §8 mit eigenem
   Schema und eigener Failure-Mode-Liste.

## 10. Approval / Policy requirements

- **Read-only Low-Risk Capabilities** (`admin.status.read`,
  `admin.capability.describe`) können `approval_required = false`
  haben. Sichtbarkeit ist Pflicht: Operator muss in der
  Settings-Shell oder im Audit-Panel sehen können, dass diese
  Capability genutzt wurde.
- **Dry-run Capabilities** (`admin.action.dry_run`) verlangen
  Approval per Default — auch wenn keine Mutation passiert,
  enthüllt der Dry-run System-State und ist deshalb
  approval-würdig.
- **Execute Capabilities** (`admin.action.execute`) verlangen
  Approval **immer**. Approval-Default = true, Tripwire-Test in
  [`core/src/config.rs`](../../core/src/config.rs)
  `policy_v0_defaults_are_locked` schützt diese Linie.
- **Approval-Card-Pflichtinhalt für `medium`/`high`-Risk:**
  - `target_capability_id` (nicht der AdminBot-internen
    Action-Name, sondern die canonical `capability_id`),
  - `risk_level`,
  - kuratiertes Summary über `side_effects`,
  - `rollback_supported`-Anzeige,
  - `timeout_ms` als sichtbare Bounds,
  - `correlation_id` (sobald implementiert).
- **Denied / expired / cancelled Approval** bedeutet **kein**
  AdminBot-Aufruf — auch nicht für Dry-run.
- **Approval-Reuse verboten:** ein Approval gilt nur für
  *seine* `correlation_id` und sein `target_capability_id`.
  Eine Wieder­verwendung über Anfragegrenzen oder
  Capability-Grenzen hinweg ist `refused_by_policy`.

## 11. Audit requirements

Sobald die Capability implementiert ist, muss der Audit-Pfad
folgende Events erfassen — Lifecycle wie in
[`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md), mit
AdminBot-spezifischen Markern:

| Event | Pflicht |
|-------|---------|
| `request_received` | ✅ |
| `capability_selected` | ✅ (mit `capability_id`, deterministisches Mapping) |
| `approval_requested` | ✅ für `medium` / `high` |
| `approval_resolved` | ✅ für `medium` / `high` (mit `result` ∈ `approved` / `denied` / `cancelled` / `timed_out`, `source` ∈ `user` / `timeout` / `system`) |
| `dry_run_started` / `dry_run_completed` / `dry_run_failed` | ✅ für Stufe 1 |
| `execution_started` / `execution_completed` / `execution_failed` / `execution_cancelled` | ✅ für Stufe 2 |

**Pflicht-Felder pro Audit-Eintrag** (Implementation hinter
AUDIT_CORRELATION_ID_SPEC FA-1):

- `correlation_id`,
- `capability_id`,
- `target_capability_id` (für Stufe 1+2),
- `risk_level`,
- `result`.

**Audit darf niemals erfassen:**

- Secrets (API-Keys, Tokens, Passwort-Material).
- Rohe Shell-Kommandos.
- Vollständige Config-Dumps.
- Vollständige Logs (nur kuratierte Marker).
- Rohe Skripte.
- Credentials.
- Unredacted Environment.

Diese Linie spiegelt die bestehende Audit-Sanitization aus
[`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md) und
ist nicht weicher.

## 12. Transport / Auth requirements

- **Lokal-first.** Erste Verdrahtung: Unix Domain Socket
  (`/run/adminbot/adminbot.sock`, AdminBot-seitig festgelegt) oder
  Loopback-only.
- **Cloud / Remote AdminBot ist out-of-scope** für diesen Contract
  v0.1. Kein TLS-Setup, kein Auth-Token, kein Secret-Store-Eintrag
  für Remote-AdminBot-URLs.
- **Mutation verlangt authentifizierte lokale Peer-Identität.**
  AdminBot nutzt bereits `SO_PEERCRED`; Smolit-Assistant darf den
  Pfad nur einnehmen, wenn die Peer-Identität auf dem Socket dem
  ausführenden User entspricht.
- **Unauthentifizierter Endpoint muss fail-closed sein.** Kein
  HTTP-Loopback ohne Peer-Auth, kein Socket ohne `SO_PEERCRED`.
- **Kein Bearer-Token in Logs/UI.** Falls je ein Token-Mechanismus
  eingeführt wird (Future Work), darf er nicht in
  Audit-Summaries, Approval-Cards, Settings-Shell oder
  Error-Frames sichtbar sein.
- **Kein Env-Secret-Dumping.** Keine Capability darf Environment-
  Variablen rückspielen, weder bei Status, Describe noch Dry-run.

## 13. Failure modes

Pflicht-Failure-Mode-Vokabular für jeden Eintrag in §8:

| Failure mode | Bedeutung |
|--------------|-----------|
| `unavailable` | AdminBot-Socket nicht erreichbar, Daemon down. |
| `auth_failed` | Peer-Identity stimmt nicht. |
| `capability_not_allowed` | Capability ist im Vokabular, aber dieser Contract erlaubt sie nicht. |
| `capability_schema_mismatch` | Argumente passen nicht zu `allowed_arguments_schema`. |
| `approval_denied` | User hat in der Approval-Card abgelehnt. |
| `approval_expired` | Approval lief in `timed_out`. |
| `dry_run_required` | Stufe 2 wurde aufgerufen, ohne dass ein gültiger Dry-run vorausgegangen ist. |
| `dry_run_failed` | Dry-run lieferte Fehler — Mutation wird nicht eingeleitet. |
| `execution_failed` | Mutation lief, AdminBot meldete Fehler. |
| `timeout` | `timeout_ms` gerissen. |
| `invalid_response` | AdminBot lieferte unerwartetes Schema. |
| `refused_by_policy` | Smolit-Assistant Policy hat das Mapping verweigert (deny-by-default Klasse, unbekannter `capability_id`, unbekannter `target_capability_id`). |
| `correlation_missing` | Pflicht-`correlation_id` fehlt. |
| `correlation_mismatch` | Antwort trägt andere `correlation_id` als Anfrage. |
| `rollback_unavailable` | Mutation wurde verlangt für eine Capability mit `rollback_supported = false`, ohne explizite Approval-Bestätigung dieser Linie. |

Erweiterte Failure-Modes pro Ziel-Capability sind erlaubt, müssen
aber ergänzend, nicht ersetzend wirken.

## 14. Versioning

- `contract_version` ist semver.
- `0.x.y` ist Pre-1.0; **breaking changes erlaubt** mit Bump der
  minor-Version, solange der Contract Draft / Proposed bleibt.
- Bump des `contract_version`:
  - bei jeder Schema-Änderung (Pflichtfeld neu/entfernt/umbenannt),
  - bei Erweiterung der initialen Capability-Klassen über die
    vier in §8,
  - bei Aufnahme einer Klasse aus §9 (Deny-Liste).
- Kein Bump bei rein redaktionellen Änderungen (Wording,
  zusätzliche Beispiele, Verlinkung).
- Bei Übergang auf Status `Accepted` rückt die Versions­linie auf
  `1.0.0`.

## 15. Examples

Alle Beispiele sind *fiktiv* — sie nennen keine echten
Service-Namen, keine echten Shell-Kommandos, keine Secrets. Sie
zeigen die Form, nicht die Inhalte einer späteren Implementation.

### 15.1 `admin.status.read` (`scope: "summary"`)

```json
{
  "contract_version": "0.1",
  "capability_id": "admin.status.read",
  "capability_name": "Read AdminBot summary",
  "risk_level": "low",
  "allowed_arguments_schema": {
    "type": "object",
    "properties": {
      "scope": { "type": "string", "enum": ["summary", "health", "version"] }
    },
    "required": ["scope"],
    "additionalProperties": false
  },
  "denied_arguments": ["raw_logs", "secrets", "config_dump", "regex_filter", "path_filter"],
  "dry_run_supported": false,
  "approval_required": false,
  "audit_required": true,
  "correlation_id_required": false,
  "timeout_ms": 3000,
  "rollback_supported": false,
  "side_effects": [],
  "operator_visible_summary": "Read sanitized AdminBot status (summary | health | version).",
  "failure_modes": [
    "unavailable",
    "auth_failed",
    "capability_not_allowed",
    "capability_schema_mismatch",
    "timeout",
    "invalid_response",
    "refused_by_policy"
  ]
}
```

### 15.2 `admin.capability.describe` (kuratierter Filter)

```json
{
  "contract_version": "0.1",
  "capability_id": "admin.capability.describe",
  "capability_name": "Describe AdminBot capabilities",
  "risk_level": "low",
  "allowed_arguments_schema": {
    "type": "object",
    "properties": {
      "filter": { "type": "string", "maxLength": 64, "pattern": "^[a-z][a-z0-9._]*$" }
    },
    "additionalProperties": false
  },
  "denied_arguments": ["arbitrary_command", "shell_snippet", "glob", "regex", "registry_full_dump"],
  "dry_run_supported": false,
  "approval_required": false,
  "audit_required": true,
  "correlation_id_required": false,
  "timeout_ms": 3000,
  "rollback_supported": false,
  "side_effects": [],
  "operator_visible_summary": "List AdminBot capabilities; optional curated filter, no glob/regex.",
  "failure_modes": [
    "unavailable",
    "auth_failed",
    "capability_not_allowed",
    "capability_schema_mismatch",
    "timeout",
    "invalid_response",
    "refused_by_policy"
  ]
}
```

### 15.3 `admin.action.dry_run` (hypothetisches `service.restart`)

```json
{
  "contract_version": "0.1",
  "capability_id": "admin.action.dry_run",
  "capability_name": "Dry-run an AdminBot mutation",
  "risk_level": "medium",
  "allowed_arguments_schema": {
    "type": "object",
    "properties": {
      "target_capability_id": { "type": "string" },
      "arguments": { "type": "object" },
      "reason": { "type": "string", "maxLength": 140 }
    },
    "required": ["target_capability_id", "arguments", "reason"],
    "additionalProperties": false
  },
  "denied_arguments": [
    "shell", "sudo", "executable_path", "raw_script",
    "secret", "external_url", "path_traversal"
  ],
  "dry_run_supported": true,
  "approval_required": true,
  "audit_required": true,
  "correlation_id_required": true,
  "timeout_ms": 5000,
  "rollback_supported": false,
  "side_effects": ["no mutation; may inspect target status"],
  "operator_visible_summary": "Preview of a privileged AdminBot action; no system change is applied.",
  "failure_modes": [
    "unavailable",
    "auth_failed",
    "capability_not_allowed",
    "capability_schema_mismatch",
    "approval_denied",
    "approval_expired",
    "dry_run_failed",
    "timeout",
    "invalid_response",
    "refused_by_policy",
    "correlation_missing",
    "correlation_mismatch"
  ]
}
```

### 15.4 Rejected `admin.shell.execute`

```json
{
  "contract_version": "0.1",
  "capability_id": "admin.shell.execute",
  "rejection": {
    "reason": "deny_by_default",
    "policy_reference": "ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md §9",
    "required_for_admission": [
      "dedicated ADR with own threat model",
      "entry in CAPABILITY_VOCABULARY.md",
      "separate capability contract entry with its own schema and failure modes"
    ],
    "result": "refused_by_policy"
  }
}
```

Dies ist **kein** akzeptierter Eintrag — es zeigt nur, wie eine
Ablehnung dokumentiert würde, falls jemand `admin.shell.execute`
einreicht.

## 16. Non-goals

- **Kein Code.** Kein AdminBot-Client in `core/src/`, keine
  Capability-Registry-Datenstruktur, keine Konstanten.
- **Keine AdminBot-Repo-Änderung.** AdminBot-Action-Registry,
  IPC-Spec, Security-Model bleiben unangetastet.
- **Kein neuer Provider-Kind**, kein neues IPC-Command, keine
  Wire-Änderung in [`docs/api.md`](../api.md).
- **Keine Runtime-Capability-Registry.** Dieser Contract beschreibt
  Form, keine Datenstruktur im Speicher.
- **Keine Policy-Engine** im „grand design"-Sinn.
- **Keine `AuditEvent`-Änderung.** Das Feld `correlation_id` ist
  weiter Future Work aus AUDIT_CORRELATION_ID_SPEC.
- **Keine `correlation_id` / `capability_id` Implementation** in
  diesem PR.
- **Keine Shell-Pfade** — weder als Capability noch als Argument-
  Sub-Schema.
- **Keine echten Service-Namen oder Shell-Kommandos** in
  Beispielen.
- **Keine Secrets** anywhere im Vertragsdokument.
- **Keine UI-Änderung.**

## 17. Future work

Reihenfolge nicht bindend; alle Schritte hinter eigenen PRs.

- **AC-1.** Pro `target_capability_id` aus AdminBot Stufe 2 ein
  eigener Capability-Contract-Eintrag mit eigenem Schema (z. B.
  `admin.action.execute@service.restart` mit fester Service-
  Whitelist). Kein Code, nur Vertragsergänzung.
- **AC-2.** `dry_run_reference`-Feld implementieren: Stufe 2
  verlangt einen Verweis auf einen erfolgreichen Dry-run derselben
  `correlation_id`.
- **AC-3.** Mapping-Tabelle „canonical `capability_id`" ↔
  „AdminBot-Action-ID" aus
  [CAPABILITY_VOCABULARY §9](./CAPABILITY_VOCABULARY.md) als
  formales Anhang-Dokument verfeinern (sobald die AdminBot-Seite
  ihre Action-Registry-API stabilisiert).
- **AC-4.** Spike-PR Stufe 0 read-only hinter Feature-Flag, erst
  nachdem AUDIT_CORRELATION_ID_SPEC FA-1 (`correlation_id` in
  `AuditEvent`) und CAPABILITY_VOCABULARY FA-1 (Code-Konstanten
  für live Capabilities) gelandet sind.
- **AC-5.** Approval-Card-Erweiterung mit Pflichtfeldern aus §10
  (Operator-Visible-Summary, `target_capability_id`,
  `rollback_supported`, `timeout_ms`).
- **AC-6.** Spike-PR Stufe 1 dry-run hinter Feature-Flag, erst
  nach AC-4 und AC-5.
- **AC-7.** Spike-PR Stufe 2 execute hinter Feature-Flag, erst
  nach AC-1 (eine konkrete Ziel-Capability mit eigenem
  Schema) und AC-6.
