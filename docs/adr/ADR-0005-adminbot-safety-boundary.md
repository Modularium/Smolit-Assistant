# ADR-0005: AdminBot Safety Boundary for Smolit-Assistant

- **Status:** Proposed (Docs/ADR-only — keine Code-Implementation).
- **Date:** 2026-04-25.
- **Deciders:** Smolit-Assistant Maintainer.
- **Scope:** Smolit-Assistant Rust-Core und ein **hypothetischer**
  zukünftiger direkter Smolit-Assistant ↔ AdminBot Pfad. **Nicht**
  Teil dieses ADR: AdminBot-Repo selbst, ABrain ↔ AdminBot (lebt
  außerhalb), OceanData, smolitux-ui.
- **Workstream:** E (Approval / Policy / Tool-Gating) — Folgearbeit
  aus PR 44 Matrix §6 *Smolit-Assistant ↔ AdminBot — missing by
  design*.
- **Related:** [ADR-0001](./ADR-0001-smolitux-design-contract.md),
  [ADR-0003](./ADR-0003-abrain-native-integration.md),
  [ADR-0004](./ADR-0004-oceandata-data-layer-integration.md);
  [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](../contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md);
  [`docs/security/APPROVAL_UX.md`](../security/APPROVAL_UX.md);
  [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md).

> Leitprinzip: **Admin/system actions require explicit capability
> scope, user approval, audit correlation, and no hidden execution.**

---

## 1. Status

**Proposed.** Es existiert heute kein direkter Smolit-Assistant ↔
AdminBot Pfad, und dieser ADR soll genau die Bedingungen festlegen,
die *vor* einem solchen Pfad geklärt sein müssen. Der Status wird
auf **Accepted** angehoben, sobald

- ein Capability-Contract-Dokument
  (`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`,
  Future Work, siehe §14) auf Basis dieses Rahmens publiziert ist,
- ein Audit-Correlation-ID-Spec (FA-aus PR 44 §12) existiert, und
- ein Spike-PR (FA-1) gegen §4 (Decision) und §7 (Approval/Policy/
  Audit) geprüft formelle Zustimmung hat.

## 2. Date

2026-04-25.

## 3. Context

### 3.1 Was AdminBot ist

[Smolit_AdminBot](https://github.com/Modularium/Smolit_AdminBot)
ist ein nativer Linux-Systemdienst in Rust — der Admin-/System-/
Ops-Aktionslayer im Smolitux-/EcoSphere-Network-Ökosystem. Er
führt **deterministische, registrierte, policy-geprüfte
Admin-Aktionen** aus (z. B. `system.status`, `system.health`,
`service.status`, `service.restart`); kanonische AdminBot-Doku liegt
unter
[`docs/adminbot_v2/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/adminbot_v2)
und [`docs/security/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/security).

AdminBot ist explizit:

- **kein** AI-System,
- **kein** Agenten-Framework,
- **kein** generischer Automationsbaukasten,
- **keine** generische Shell — keine `exec`, kein `sudo`-Wrapper,
  kein Plugin-System im Core,
- **kein** Provider-Router, keine Datenplattform, keine UI-Library.

AdminBots Vertrauensgrenze liegt **lokal beim AdminBot selbst**
(`SO_PEERCRED`, polkit, systemd-D-Bus, eigene Policy auf
`unix_user`/`unix_group`), nicht bei einem aufrufenden Brain oder
Assistant. Diese Linie ist im AdminBot-Repo dokumentiert und
**bindend** für jeden Caller.

### 3.2 Wo AdminBot heute in Smolit-Assistant erscheint

AdminBot wird in Smolit-Assistant heute **rein negativ** erwähnt:

- [README.md §12](../../README.md) Non-goals: „**AdminBot-Integration /
  Shell-Zugriff** — nicht im Plan."
- [ROADMAP.md §7](../../ROADMAP.md): „**AdminBot-Integration /
  Shell-Zugriff.** Kein Plan."
- [`docs/security/APPROVAL_UX.md`](../security/APPROVAL_UX.md):
  „Es gibt **keine echte Tool-/Desktop-/Shell-/AdminBot-
  Ausführung**" / „**Kein AdminBot, keine Shell.** Nicht im Scope."
- [`docs/adr/ADR-0002-accessibility-rpc-readonly.md`](./ADR-0002-accessibility-rpc-readonly.md):
  „**Keine AdminBot-/Shell-Aktionen.** Accessibility ≠ Shell."
- [ADR-0003](./ADR-0003-abrain-native-integration.md): „kein
  AdminBot-/Shell-/Desktop-Bypass" für den ABrain-Native-Pfad.
- [ADR-0004](./ADR-0004-oceandata-data-layer-integration.md): „kein
  Tool-/Desktop-/AdminBot-Bypass" für den OceanData-Pfad.
- [`docs/api.md` §5.4](../api.md): listet `tool_call.tool="adminbot"`
  als Ziel-Beispiel im Native-ABrain-Tool-Call-Schema — explizit
  Ziel-Zustand, nicht implementiert; und seit ADR-0003 ohnehin auf
  „keine Tool-Call-Execution in der ersten Version" festgenagelt.
- [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md` §4 Pair 3](../contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md):
  *Smolit-Assistant ↔ AdminBot* — *(heute keiner — by design)*,
  Status **explicit gap (Designentscheidung, keine Vergesslichkeit)**.

### 3.3 ABrain ↔ AdminBot existiert — außerhalb dieses Repos

ABrain hat ein dokumentiertes Tool-Surface gegen AdminBot
([`Modularium/Agent-NN docs/integrations/adminbot/*`](https://github.com/Modularium/Agent-NN/tree/main/docs/integrations/adminbot),
gespiegelt in
[`Modularium/Smolit_AdminBot docs/integrations/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/integrations)).
Diese Linie kreuzt Smolit-Assistant **nicht**: ABrain spricht
AdminBot direkt über
`/run/adminbot/adminbot.sock`. Smolit-Assistant ist an diesem Pfad
**kein Vermittler** und darf es nicht werden, ohne dass dieser ADR
und sein Folge-Capability-Contract gelten.

### 3.4 Naming-Drift (Hintergrund)

AdminBot-Doku führt ABrain teils weiterhin als „Agent-NN"
(historischer Name); die Naming-Sync gehört in den AdminBot-Repo
und ist **nicht** Teil dieses ADR. Smolit-Assistant nutzt
durchgängig „ABrain".

### 3.5 Warum dieser ADR jetzt sinnvoll ist

Die Lücke ist seit PR 44 Matrix sichtbar markiert. Solange kein
geschriebener Rahmen existiert, könnte ein zukünftiger Vorschlag
(„wir verdrahten AdminBot doch direkt ans Core — ist nur ein Status-
Read") an den bestehenden Approval-/Policy-/Audit-Gates vorbeilaufen
oder eine generische Tool-Passthrough-Schicht einführen. Dieser ADR
formuliert die Messlatte, gegen die jeder spätere Vorschlag laufen
muss.

## 4. Decision

1. **Smolit-Assistant ↔ AdminBot bleibt nicht implementiert,** bis
   die Voraussetzungen aus §1 Status erfüllt sind.
2. **Falls jemals eingeführt,** muss der Pfad alle folgenden
   Eigenschaften haben:
   - **read-only / status-first.** Erste Stufe ist ausschließlich
     status / describe-only / dry-run.
   - **capability-whitelisted.** Nur explizit aufgezählte
     `capability_id`s erlaubt; keine generischen Argument-Strings.
   - **kein generischer Shell-Pfad.** Kein `exec`, kein `sudo`-
     Wrapper, kein Pipe-zu-Shell, kein Wrapper, der freie Strings
     in eine systemctl-/D-Bus-/polkit-Kette weitergibt.
   - **keine generische Tool-Passthrough-Schicht.** Ein Caller
     darf nicht „beliebigen AdminBot-Action-Namen + beliebige
     Params" einreichen.
   - **kein AdminBot-Kommando aus Natural Language direkt
     ausgeführt.** Eine LLM-Antwort darf nie als
     AdminBot-Action-Body wandern, ohne über Capability-Mapping +
     Approval zu laufen.
   - **jedes mutierende Kommando wird approval-gegated.**
     Approval-Default = true für alle Mutationen, inklusive
     restartender und dienst-modifizierender Aktionen.
   - **jedes akzeptierte Kommando wird auditiert.** Lifecycle
     wie [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)
     beschreibt — Sanitization-Regeln gelten.
   - **Audit Correlation ID** wird genutzt, sobald der cross-repo
     Spec (Folgearbeit aus PR 44 §12) existiert.
   - **explicit opt-in.** Default-off, Env-/Settings-Flag, keine
     stille Aktivierung durch Update.
   - **dry-run / describe-only Vorstufe** ist Pflicht für jede
     mutierende Capability.
3. **AdminBot darf nicht als Shortcut dienen** für:
   - **ABrain `action_intents`.** Ein vorgeschlagener Action-Intent
     wird nicht in einen AdminBot-Call übersetzt, ohne über
     Capability-Mapping + Approval zu laufen.
   - **Desktop Interaction.** AdminBot ist nicht der Backdoor-Pfad
     für `type_text` / `send_shortcut` / Wayland-`focus_window`.
     Die `BackendUnsupported`-Linie aus PR 23 / Workstream F
     bleibt bindend.
   - **OceanData.** AdminBot wird nicht zur Datenquelle, zum
     Decide-Access-Bypass oder zum Mutationskanal in OceanData.
     Ein eventueller AdminBot ↔ OceanData Pfad braucht einen
     **eigenen** ADR (siehe §11).

## 5. Candidate integration model

> Arbeitsmodell, **nicht** Implementierung.

### 5.1 Optionale zukünftige Provider-/Adapter-Achse

Falls jemals eingeführt, ist der Pfad eine **separate Adapter-
Achse** neben Text/STT/TTS — **nicht** ein neuer Text-Provider-Kind
und **nicht** ein neuer Interaction-Action-Kind:

- `adminbot_status` — read-only / describe-only / dry-run.
- `adminbot_action_request` — mutierend, hinter eigenem Capability
  Contract + Approval-/Audit-Gate.

Das vermeidet semantische Kollision mit
[`docs/provider_fallback_and_settings_architecture.md`](../provider_fallback_and_settings_architecture.md)
(Provider-Resolver = Antwortquelle für Text/STT/TTS) und mit dem
Interaction-Layer (lokale Desktop-Aktionen).

### 5.2 Stufen

1. **Stufe 0 — Status / Read-only.**
   - `adminbot_status` darf `system.status` / `system.health` /
     `resource.snapshot` / `disk.usage` / `service.status` /
     `describe_capabilities` aufrufen.
   - Keine Mutation, kein `service.restart`.
   - Keine Approval nötig (siehe §7), aber **transparent**: jede
     Antwort wird im Audit gelogged.
2. **Stufe 1 — Dry-run für mutierende Capabilities.**
   - `adminbot_action_request` mit `dry_run = true`.
   - AdminBot beschreibt, was er **täte**, ohne es zu tun.
   - Approval-Default = true, weil bereits eine Mutationsabsicht
     existiert.
3. **Stufe 2 — Mutierende Ausführung.**
   - `adminbot_action_request` mit `dry_run = false`.
   - Approval-Default = true.
   - Pro Capability ein eigener Eintrag im
     `ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`.

### 5.3 Defaults

- **Default-off.** Kein `adminbot_*`-Aufruf ohne explizites Opt-in.
- **Keine Default-Chain.** Anders als ABrain (Default-Chain
  `["abrain"]`) gibt es keinen Standardweg, AdminBot in eine
  Antwort­kette einzuhängen.
- **Lokal-first.** Erst Unix-Socket / Loopback; Cloud/Remote ist
  out-of-scope (siehe §8).

## 6. Required capability contract

Ein zukünftiger Capability Contract (Working title:
`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`, **Future
Work — nicht in PR 45 angelegt**, siehe §14) muss pro
zugelassener Capability folgende Felder fixieren:

| Feld | Bedeutung |
| ---- | --------- |
| `contract_version` | semver, Bump bei jeder Schema-Änderung. |
| `capability_id` | maschinenlesbarer Kurzname, z. B. `adminbot.system.status`. |
| `capability_name` | menschenlesbarer Name für Approval-Card. |
| `risk_level` | `low` / `medium` / `high` — Mutation ≥ medium. |
| `allowed_arguments_schema` | typisierte, **whitelistete** Argumente; freie Strings sind verboten. |
| `denied_arguments` | explizit verbotene Eingaben (z. B. Wildcards, Glob, Pipe). |
| `dry_run_supported` | bool — jede Mutation muss `true` haben. |
| `approval_required` | bool — Mutation = `true`. |
| `audit_required` | bool — immer `true`. |
| `correlation_id_required` | bool — `true`, sobald Audit-Correlation-Spec existiert. |
| `timeout` | Pflicht-Cutoff in Millisekunden. |
| `rollback_supported` | bool, optional — wenn `false`, hebt das die Risiko-Einstufung. |
| `side_effects` | freie Beschreibung für Approval-Card-Summary. |
| `operator_visible_summary` | menschenlesbarer Text für die Approval-Card (kuratiert, **kein** Raw-Payload-Dump). |
| `failure_modes` | benannte Fehlerklassen (siehe §9). |

Begründung: Diese Felder verhindern, dass „AdminBot kann doch
schon alles" als Argument für eine generische Passthrough-Schicht
dient. Jede einzelne Capability ist dokumentiert, klein,
beschreibbar und einzeln widerrufbar.

## 7. Approval / Policy / Audit requirements

### 7.1 Approval

- **Read-only Status (Stufe 0)** *kann* approval-frei sein, **muss**
  aber im Audit-Ring-Buffer sichtbar sein. Operator-Sichtbarkeit ist
  Pflicht — der User muss in der Settings-Shell sehen können, dass
  ein AdminBot-Status-Read passiert ist.
- **Jede Mutation (Stufe 1+2)** läuft durch Policy v0
  (PR 25, Approval-Default = true). Es gibt keine
  Stille-Erfolg-Heuristik, kein Auto-Approval auf Basis
  vergangener Approvals.
- **Denied approvals** dürfen AdminBot **nicht** aufrufen, auch
  nicht im dry-run.
- **Timed-out approvals** dürfen AdminBot **nicht** aufrufen. Das
  bestehende `timed_out`-Verhalten aus
  [`docs/security/APPROVAL_UX.md`](../security/APPROVAL_UX.md)
  gilt unverändert.
- **Cancelled approvals** brechen die Aktion ab; jeder bereits
  laufende dry-run wird abgebrochen, sofern technisch möglich.

### 7.2 Policy

- **Approval-Default = true** für alle Mutationen.
- **Capability-Mapping** ist deterministisch: gleicher Input →
  gleiche Capability. Kein LLM-getriggertes Mapping ohne
  deterministischen Lookup.
- **Refused-by-policy** ist ein **eigener Failure-Mode** (§9), kein
  versteckter „nichts-passiert"-Pfad.

### 7.3 Audit

Der Audit-Lifecycle für AdminBot-Aktionen folgt dem bestehenden
Schema aus [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)
und ergänzt es um AdminBot-spezifische Marker. Mindest-Erfassung:

- `ipc_command_received` — Request kam an, mit Capability-ID.
- `capability_selected` — welche Capability hat der Lookup
  ausgewählt? (kein freier String, sondern `capability_id`).
- `approval_requested` / `approval_resolved` (mit `risk` und
  `result`).
- `dry_run_started` / `dry_run_completed` / `dry_run_failed` (für
  Stufe 1).
- `action_started` / `action_completed` / `action_failed` (für
  Stufe 2).
- `correlation_id` — verkettet UI-Klick → Smolit-Assistant Audit
  → AdminBot-IPC, sobald der cross-repo Spec existiert.

**Audit-Sanitization** ist bindend:

- **Keine Secrets** (API-Keys, Tokens, Passworte, Session-Cookies).
- **Keine rohen Shell-Kommandos** — nur Capability-ID +
  kuratiertes Summary.
- **Keine vollen sensiblen Payloads** — Größenlimit pro Audit-Eintrag
  bleibt erhalten.

## 8. Transport / Auth expectations

- **Lokal-first.** Erste Verdrahtung: Unix Domain Socket
  (`/run/adminbot/adminbot.sock`, AdminBot-seitig) oder Loopback.
- **Cloud / Remote AdminBot ist out-of-scope.** Kein TLS-Setup,
  kein Auth-Token, kein Secret-Store-Eintrag für eine
  Remote-AdminBot-URL.
- **Lokale Peer-Identität** vor jeder Mutation: AdminBot nutzt
  bereits `SO_PEERCRED`; Smolit-Assistant darf den Pfad nur
  einnehmen, wenn die Peer-Identität auf dem Socket dem
  ausführenden User entspricht.
- **Mutual auth oder Peer-Identity required before mutation.**
  Read-only kann mit Peer-Identity allein laufen; Mutationen
  brauchen die volle Linie aus §7 (Approval + Audit + Correlation).
- **Secrets nur über den `0600`-Secret-Store** des Core, falls
  überhaupt nötig — Stand heute ist kein Secret-Bedarf
  vorgesehen, weil lokale Peer-Identität reicht.
- **Kein Env-Secret-Dumping.** Keine `printenv`-artigen Capabilities.
- **Kein unauthentifizierter Admin-Endpoint.** Kein
  HTTP-Loopback-Endpoint ohne Peer-Auth.

## 9. Failure modes

Jeder AdminBot-Pfad muss diese benannten Fehlerklassen
unterscheiden — keine stille Konvergenz auf „error":

| Failure mode | Bedeutung |
| ------------ | --------- |
| `unavailable` | AdminBot-Socket nicht erreichbar, Daemon down. |
| `auth_failed` | Peer-Identity stimmt nicht. |
| `capability_not_allowed` | Capability ist im Vertrag nicht enthalten oder deaktiviert. |
| `approval_denied` | User hat in der Approval-Card abgelehnt. |
| `approval_expired` | Approval lief in `timed_out`. |
| `dry_run_failed` | Dry-run liefert Fehler — Mutation wird nicht eingeleitet. |
| `execution_failed` | Mutation lief, AdminBot meldete Fehler. |
| `timeout` | Capability-Timeout (`timeout` aus §6) gerissen. |
| `invalid_response` | AdminBot lieferte unerwartetes Schema. |
| `refused_by_policy` | Smolit-Assistant Policy hat das Mapping verweigert (z. B. unbekannter Capability-ID). |
| `correlation_missing` | Correlation-ID fehlt, obwohl der Capability Contract sie verlangt. |

## 10. Relationship to ABrain

- **ABrain darf `action_intents` als Vorschläge zurückmelden**
  ([ADR-0003](./ADR-0003-abrain-native-integration.md)).
- **ABrain darf AdminBot nicht über Smolit-Assistant
  triggern,** ohne dass Capability-Mapping + Approval + Audit
  greifen. Kein „weil ABrain das vorgeschlagen hat, war es schon
  freigegeben"-Argument.
- **ABrain ↔ AdminBot existiert kanonisch außerhalb dieses Repos**
  ([`Modularium/Agent-NN docs/integrations/adminbot/*`](https://github.com/Modularium/Agent-NN/tree/main/docs/integrations/adminbot),
  AdminBot-Repo
  [`docs/integrations/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/integrations)).
  Dieser ADR adressiert diese Linie nicht; PR 44 Matrix Pair 2
  bleibt der Referenzpunkt.

## 11. Relationship to OceanData

- **OceanData ist Data-/Kontext-Layer**
  ([ADR-0004](./ADR-0004-oceandata-data-layer-integration.md)) — sie
  liefert Decide-Access, niemals eine ausführbare Aktion.
- **AdminBot darf nicht über Smolit-Assistant in OceanData
  schreiben oder mutieren.** Kein Shortcut, kein „AdminBot kennt
  ja systemd, also kann er die Datenbank…"-Argument.
- **AdminBot ist keine Datenquelle für OceanData.** OceanData
  liest nicht über Smolit-Assistant aus AdminBot.
- **Ein direkter AdminBot ↔ OceanData Pfad braucht einen eigenen
  ADR** und ist heute *deferred* (PR 44 Matrix Pair 6).

## 12. Relationship to Smolitux-UI

- **smolitux-ui hat keine Runtime-Rolle** auf der AdminBot-Achse —
  keine `@smolitux/*`-Pakete in der AdminBot-Adapter-Schicht, kein
  React in Godot, keine WebView.
- **Kein Design-/Token-Bezug.** Eine Approval-Card für eine
  AdminBot-Capability folgt dem bestehenden Smolitux Design Contract
  ([ADR-0001](./ADR-0001-smolitux-design-contract.md)) wie jede
  andere Approval-Card; AdminBot fügt dem Token-Vertrag nichts
  hinzu.

## 13. Non-goals

PR 45 (dieser ADR) ist Docs/ADR-only. Ausdrücklich **nicht** Teil:

- Kein Code.
- Keine Änderungen am AdminBot-Repo.
- Kein neues IPC-Command.
- Kein neuer Provider-Kind.
- Keine Action-Execution.
- Kein Shell-Pfad.
- Keine generische Tool-Passthrough-Schicht.
- Kein AdminBot-Client (kein Rust-Crate, kein Wrapper, keine
  Adapter-Schicht).
- Keine ABrain-Änderungen.
- Keine OceanData-Änderungen.
- Keine smolitux-ui-Änderungen.
- Keine Änderungen am Secret-Store.
- Keine Audit-Persistenz (Ring-Buffer bleibt in-memory).
- Keine Wayland-/Desktop-Backend-Erweiterung.
- Keine Cloud-/Remote-AdminBot-Variante.

## 14. Future work

Reihenfolge nicht bindend; alle Schritte Docs/ADR-only oder hinter
explizitem Opt-in:

- **FA-1 — `docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`.**
  Das Capability-Contract-Dokument auf Basis von §6. Pro Capability
  ein Eintrag, beginnend mit Stufe 0 (read-only). Docs-only, kein
  Code.
- **FA-2 — Audit Correlation ID Spec.** Draft / Proposed seit
  PR 46:
  [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md).
  Voraussetzung für `correlation_id_required = true` aus §6 ist
  damit *dokumentarisch* erfüllt; die *Implementation* (Feld in
  `AuditEvent`, Cross-Repo-Wire, fail-closed-Verhalten) bleibt
  aufgeschoben hinter eigenen Folge-PRs (siehe FA-Liste in
  AUDIT_CORRELATION_ID_SPEC §12).
- **FA-3 — Capability Vocabulary.** Draft / Proposed seit
  PR 46:
  [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md).
  Definiert `capability_id`-Naming-Regeln, Kategorien, Risk-Levels
  und Mappings; keine Runtime-Registry. Die Code-Konstanten
  entstehen erst in eigenen Folge-PRs (siehe FA-Liste in
  CAPABILITY_VOCABULARY §12).
- **FA-4 — Spike-PR (Stufe 0 read-only) hinter Feature-Flag.**
  Erste Code-Berührung; default-off, capability-whitelisted, audit-
  verdrahtet, ohne Mutation. Nur nach FA-1 + FA-2.
- **FA-5 — Approval-Card-Erweiterung für AdminBot-Capabilities.**
  UX-Detailschritt nach FA-4; folgt
  [`docs/security/APPROVAL_UX.md`](../security/APPROVAL_UX.md).
- **FA-6 — Mutating spike (Stufe 1 dry-run) hinter Feature-Flag.**
  Erst nach FA-4 und FA-5.
- **FA-7 — Naming-Sync auf der AdminBot-Seite.** Liegt im
  AdminBot-Repo, nicht hier; aufgenommen für die Vollständigkeit
  des Bilds.
