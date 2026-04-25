# Audit Correlation ID Spec

- **Status:** Draft / Proposed (Docs/Contract-only — keine Code-
  Implementation in PR 46).
- **Date:** 2026-04-25.
- **Scope:** Cross-Repo. Beschreibt das zukünftige Verhalten einer
  gemeinsamen `correlation_id` zwischen Smolit-Assistant,
  ABrain, AdminBot und OceanData.
- **Workstream:** E (Approval / Policy / Tool-Gating) — Folgearbeit
  aus PR 44 §12 und PR 45 [`ADR-0005 §14 FA-2`](../adr/ADR-0005-adminbot-safety-boundary.md).
- **Companion:** [`docs/contracts/CAPABILITY_VOCABULARY.md`](./CAPABILITY_VOCABULARY.md).

> Leitprinzip: **Cross-repo actions need shared correlation before
> code.** Eine Aktion, die UI → Smolit-Assistant → ABrain → AdminBot
> kreuzt, soll **eine** durchgehende Spur haben — ohne dass
> ein einzelner Repo-Eigner einseitig ein neues ID-Schema setzt.

---

## 1. Purpose

Heute hat jeder Repo lokale IDs. Smolit-Assistant kennt
`audit_id`, `action_id`, `approval_id`. ABrain hat in seinem
[Native Contract Draft](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md)
ein `request_id`. AdminBot kennt `request_id` plus optional
`correlation_id` auf der IPC-Ebene. OceanData kennt `actor` als
Audit-Hinweis. **Es existiert kein gemeinsamer Trace-Identifier**,
der eine User-Aktion über mehrere Repos hinweg verkettet.

Ohne globale Korrelation:

- Eine Audit-Suche beginnt lokal und endet lokal.
- Eine Reproduktion eines fehlgeschlagenen Aktionspfads kreuzt
  keinen Repo-Sprung.
- Ein Reviewer kann die Frage „welche AdminBot-Aktion gehörte zu
  welcher Approval-Card?" nicht aus den Audits beantworten.

Diese Spec fixiert das **Verhalten** einer zukünftigen
`correlation_id`, bevor Code entsteht. Sie ist Voraussetzung für
`correlation_id_required = true` in
[ADR-0005](../adr/ADR-0005-adminbot-safety-boundary.md) §6.

## 2. Scope

In Scope:

- Format und Lebenszyklus einer cross-repo `correlation_id`.
- Propagationspunkte innerhalb von Smolit-Assistant.
- Erwartungen an ABrain / AdminBot / OceanData.
- Audit-Sanitization.
- Failure-Modes, falls die Korrelation bricht.

Nicht in Scope:

- Eine Implementation in `core/src/audit/`.
- Eine Wire-Änderung in [`docs/api.md`](../api.md).
- Distributed Tracing (OpenTelemetry / W3C Trace Context).
- Audit-Persistenz / Export.
- Ein cross-repo Schema-Generator.

## 3. Current identifiers

Stand 2026-04-25:

| Identifier | Wo definiert | Form | Geltungsbereich |
|------------|--------------|------|-----------------|
| `audit_id` | [`core/src/audit/event.rs`](../../core/src/audit/event.rs) `AuditEvent` | String | lokal pro Audit-Eintrag im Ring-Buffer |
| `action_id` | [`core/src/actions/`](../../core/src/actions/), [`core/src/interaction/action.rs`](../../core/src/interaction/action.rs), [`core/src/approvals/request.rs`](../../core/src/approvals/request.rs), [`core/src/audit/event.rs`](../../core/src/audit/event.rs), [`core/src/ipc/protocol.rs`](../../core/src/ipc/protocol.rs) | String, z. B. `act_…` / `interaction_…` | lokal pro geplanter Action |
| `approval_id` | [`core/src/approvals/request.rs`](../../core/src/approvals/request.rs) | String | lokal pro Approval |
| `request_id` | ABrain Native Contract Draft (extern) | String | transport-/request-spezifisch in ABrain |
| `task_id` | reserviert (siehe [`docs/api.md` §5](../api.md)) | optional | nicht implementiert |
| `correlation_id` | — | — | **existiert heute nicht** |

`correlation_id` ist heute **nicht** Teil des `AuditEvent`-Structs,
**nicht** Teil eines Action-Events, **nicht** Teil des IPC-Wire-
Formats. Diese Spec beschreibt das *zukünftige* Verhalten, nicht
das aktuelle.

## 4. Correlation model

```
                       ┌───────────────────────────────────┐
                       │          correlation_id           │
                       │  (cross-repo Intent-/Trace-ID)    │
                       └───────────────────────────────────┘
                                       ▲
                                       │ verkettet
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
   ┌────┴────┐      ┌──────────────┐   │   ┌──────────────────┐  ┌────┴────┐
   │ audit_id│      │  action_id   │       │  approval_id     │  │request_id│
   │ (local  │      │  (local SA   │       │  (local SA       │  │(per-call │
   │  audit  │      │   action     │       │   approval       │  │ in ABrain│
   │  event) │      │   identity)  │       │   identity)      │  │/AdminBot)│
   └─────────┘      └──────────────┘       └──────────────────┘  └─────────┘
```

- **`correlation_id`** ist der einzige Identifier, der **mehrere
  Repos überspannen** darf.
- **`audit_id` / `action_id` / `approval_id`** bleiben lokale
  Smolit-Assistant-Identifier. Sie verschwinden nicht, sie werden
  **zusätzlich** mit `correlation_id` verknüpft.
- **`request_id`** bleibt transport-/request-spezifisch (eine
  einzelne ABrain-Anfrage, ein einzelner AdminBot-IPC-Roundtrip)
  und kann pro Hop wechseln.
- **`task_id`** bleibt reserviert; eine spätere Native-API mit
  Task-Lifecycle kann es nutzen, ohne das Korrelations-Modell
  zu brechen.

**Wer erzeugt `correlation_id`?** Smolit-Assistant. Ein User-Anstoß
(IPC-Command, Voice-Utterance, UI-Klick), der einen Aktionspfad
auslösen *könnte*, bekommt am frühesten Punkt im Core eine
`correlation_id` zugewiesen. Kein anderer Repo erzeugt sie; alle
anderen Repos **echoen** sie zurück.

**Wann wird sie erzeugt?** Sobald ein Pfad anfängt, der mindestens
einen Repo-Sprung kreuzen *könnte*. Rein lokale, intent-frei
read-only Pfade (z. B. `audit_recent` selbst, oder ein interner
Settings-Read) brauchen keine `correlation_id` — siehe §6.

## 5. Identifier format

| Eigenschaft | Wert |
|-------------|------|
| Prefix | `corr_` (verpflichtend; verhindert Verwechslung mit `audit_*`, `act_*`, `appr_*`) |
| Body | URL-safe Base32 oder Hex eines monotonen, kollisionsarmen Tokens (ULID/UUID-v7 als Empfehlung; konkrete Wahl ist Implementation-Detail in FA-Code-PR) |
| Charset | `[a-z0-9_]` |
| Mindestlänge | 16 Zeichen Body (24 inkl. Prefix) |
| Maximallänge | 64 Zeichen Body (≤ 80 Zeichen inkl. Prefix; passt zu [`MAX_SUMMARY_CHARS = 80`](../../core/src/audit/event.rs)) |
| Casing | lowercase |
| Stabilität | unverändert über den gesamten Aktionspfad; nicht regenerierbar nach Erstellung |
| Zeitbezug | falls ULID/UUID-v7 verwendet wird, ist Zeit *implizit* enthalten — das ist akzeptiert |

**Beispiele:**

- `corr_01jcb5x7whk4q9rt2yz3v8ab5d` (ULID, empfohlen)
- `corr_018f3c2e7c9148adb1f5e29c3e6f4a0a` (UUID-v7 hex)

**Verboten** im Body:

- Roher Prompt-Text.
- Dateinamen, Pfade, Hostnamen.
- IP-Adressen, MAC-Adressen, User-Namen.
- Secrets (Tokens, API-Keys, Passwort-Material).
- Kommando-Strings, Shell-Argumente.
- Zeitstempel als lesbares ISO-Datum (ULID-Embedding ist okay,
  weil nicht direkt menschenlesbar).

## 6. Required propagation points

`correlation_id` muss an folgenden Punkten **gesetzt, gelesen oder
weitergegeben** werden, sobald die Implementation existiert:

### Pflicht-Punkte (high-risk Pfade)

- IPC-Command empfangen, der einen Aktionspfad auslösen kann
  (`plan_demo_action`, `interaction_open_application`,
  `interaction_focus_window`, zukünftige `adminbot_*`-Calls,
  zukünftige `abrain_native`-Requests mit `action_intents`).
- `action_planned` emittiert.
- `approval_requested` emittiert.
- `approval_resolved` empfangen.
- `action_started` / `action_completed` / `action_cancelled` /
  `action_failed`.
- Jeder Audit-Event, der zu einem dieser Lifecycle-Schritte
  gehört.
- Jeder zukünftige ABrain-Native-Request, der `action_intents`
  zurückgeben *könnte*.
- Jeder zukünftige AdminBot-Call (Status, Dry-run, Execute) — siehe
  [ADR-0005](../adr/ADR-0005-adminbot-safety-boundary.md).
- Jeder zukünftige OceanData-`decide_access` / `query_context`,
  dessen Ergebnis in eine Action einfließt.
- Jede Error-Response, die einen der obigen Schritte abbricht.

### Optionale Punkte (low-risk Pfade)

- Reine `audit_recent`-Reads (Audit über Audit-Read würde
  Rekursion erzeugen — siehe §9).
- Settings-Reads ohne Aktionsbezug.
- Provider-Probes (`settings_probe_*`) — solange sie keinen
  externen Provider-Call auslösen.

### Nicht-Punkte

- TTS-Lifecycle-Events (`speaking_started` / `speaking_ended`)
  haben heute `action_id`, brauchen `correlation_id` nur, wenn die
  TTS-Ausgabe Teil eines Aktionspfads ist; `auto_speak` nach einer
  Provider-Antwort gehört zur ABrain-Korrelations-Kette und erbt
  die `correlation_id` der ursprünglichen Anfrage.
- STT-Lifecycle ist analog: nur korreliert, wenn die Transkription
  einen Aktionspfad auslöst.

## 7. Event mapping

| Flow step | Local id | `correlation_id` required? | Notes |
|-----------|----------|----------------------------|-------|
| User utterance / IPC-Command empfangen | `request_id` (lokal generiert) | **Pflicht**, wenn der Command einen Aktionspfad auslösen *kann* | Smolit-Assistant erzeugt `correlation_id` hier, falls noch keine vorhanden |
| ABrain native request (zukünftig) | `request_id` (per-call) | **Pflicht** | Smolit-Assistant sendet `correlation_id`; ABrain echoed sie in der Response |
| `action_intent` empfangen (zukünftig) | — | **Pflicht** | erbt `correlation_id` des umgebenden Native-Request |
| `action_planned` | `action_id` | **Pflicht** | Audit-Event trägt `correlation_id` |
| `approval_requested` | `approval_id` | **Pflicht** | Approval-Card-Pfad korreliert |
| `approval_resolved` | `approval_id` | **Pflicht** | `result` ∈ `approved` / `denied` / `cancelled` / `timed_out`; `source` ∈ `user` / `timeout` / `system` |
| AdminBot describe-only / status-read (zukünftig) | `request_id` (AdminBot IPC) | empfohlen | Stufe 0 in ADR-0005, kein Approval, aber Audit-Sichtbarkeit |
| AdminBot dry-run (zukünftig) | `request_id` | **Pflicht** | Stufe 1 in ADR-0005 |
| AdminBot execute (zukünftig) | `request_id` | **Pflicht** | Stufe 2 in ADR-0005, fail-closed bei `correlation_missing` |
| OceanData `decide_access` (zukünftig) | `actor` (Audit-Hint) | **Pflicht**, wenn Decision in Action fließt | `UsageRecord` server-seitig korreliert über Audit-Trail |
| OceanData `query_context` (zukünftig) | — | empfohlen | Pflicht, wenn Ergebnis in Action fließt |
| `action_started` | `action_id` | **Pflicht** | |
| `action_completed` / `action_failed` / `action_cancelled` | `action_id` | **Pflicht** | |
| `audit_recent` Eintrag-Read | `audit_id` | nicht erforderlich | siehe §9 zur Anti-Rekursion |

## 8. Cross-repo expectations

### Smolit-Assistant (this repo)

- **Erzeuger** der `correlation_id`.
- Trägt sie durch den lokalen Lifecycle, in jeden ausgehenden
  Cross-Repo-Call und in jeden Audit-Event, der zum Aktionspfad
  gehört.
- Fail-closed bei `correlation_missing` für Mutationen (`high`-Risk
  Capabilities aus [`CAPABILITY_VOCABULARY.md`](./CAPABILITY_VOCABULARY.md)).

### ABrain

- **Echo-only.** ABrain darf `correlation_id` nicht verändern,
  nicht regenerieren, nicht aufsplitten.
- Wenn der Smolit-Assistant-Native-Request eine `correlation_id`
  trägt, muss die Response sie unverändert zurückgeben.
- ABrain darf eine eigene `request_id` und ein eigenes
  internes Plan-/Trace-ID-System haben — diese korrelieren
  *zusätzlich*, ersetzen aber `correlation_id` nicht.
- Mirror-Eintrag liegt im ABrain Native Contract; eine
  spätere Mirror-PR liegt im ABrain-Repo, **nicht** hier.

### AdminBot

- **Erforderlich für Mutationen** ([ADR-0005 §6](../adr/ADR-0005-adminbot-safety-boundary.md):
  `correlation_id_required` = `true` für mutierende Capabilities).
- AdminBot prüft das Format (§5), nicht den Inhalt.
- AdminBot darf eigene `request_id` setzen; sie ersetzt
  `correlation_id` nicht.
- Fail-closed bei `correlation_missing` für jede Mutation.
- Naming-Drift Agent-NN ↔ ABrain auf der AdminBot-Seite ist
  irrelevant für diese Spec — die Felder sind generisch.

### OceanData

- **Should accept**, nicht **must require**, `correlation_id` für
  `decide_access` / `query_context` / `compute_jobs`.
- Wenn akzeptiert, gehört sie in den server-seitigen `UsageRecord`
  und in den `access_decision_made`-Audit-Event.
- OceanData ist Decide-Access-Quelle, kein Aktions-Executor;
  fail-closed-Verhalten gehört in den Caller (Smolit-Assistant
  oder ABrain), nicht in OceanData selbst.

### smolitux-ui

- **Keine Runtime-Rolle.** smolitux-ui ist UI-Library und
  Token-Quelle, kein Beteiligter an Aktions-Korrelation.
- Eine Approval-Card, die `correlation_id` anzeigt (z. B. für
  Dev-Zwecke), bleibt eine Smolit-Assistant-UI-Entscheidung.

### Allgemein

- **Missing `correlation_id` muss fail-closed sein** für jede
  high-risk Mutation. Ein silently-success-Pfad ohne Korrelation
  ist verboten.
- **Duplicate `correlation_id`** ist ein Audit-Hinweis, kein
  Hard-Fail — der Aktionspfad läuft weiter, aber der Audit-Event
  trägt eine `correlation_duplicate`-Markierung.

## 9. Privacy and redaction

- **`correlation_id` ist kein User-Identifier.** Sie referenziert
  einen Aktionspfad, nicht eine Person.
- **Kein Embedding** von Prompt-Text, Dateinamen, Hostnamen,
  Usernamen, IP-Adressen, Secrets oder Shell-Kommandos im
  Identifier-Body.
- **Keine Audit-Persistenz** ändert sich durch diese Spec — der
  Ring-Buffer bleibt in-memory wie heute.
- **Anti-Rekursion:** Ein `audit_recent`-Read löst keinen
  Audit-Eintrag aus; `correlation_id`-Tracking auf der Read-Seite
  würde diese Linie aufweichen und ist verboten.
- **Sanitization-Regeln** aus
  [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)
  bleiben unverändert: keine Command-Templates, keine Env-Namen,
  keine Secrets in Audit-Summaries — `correlation_id` darf weder
  diese Inhalte transportieren noch zu deren Aufdeckung führen.

## 10. Failure modes

| Failure mode | Bedeutung | Erwartetes Verhalten |
|--------------|-----------|----------------------|
| `missing_correlation_id` | Aktionspfad ohne ID | High-risk: fail-closed; medium-risk: Audit-Warnung; low-risk: Audit-Hinweis |
| `invalid_correlation_id` | Format passt nicht zu §5 | Refuse-by-policy am Eingangstor |
| `correlation_mismatch` | Antwort trägt andere ID als Anfrage | Refuse-by-policy + Audit-Hinweis |
| `correlation_not_supported` | Gegenseite kann ID nicht verarbeiten | Audit-Hinweis; Aktionspfad nur fortsetzen, wenn Risk ≤ medium |
| `upstream_dropped_correlation` | ABrain/AdminBot/OceanData hat ID nicht zurückgegeben | Audit-Hinweis; bei Mutation fail-closed |
| `duplicate_correlation_id` | dieselbe ID in zwei parallelen Aktionspfaden | Audit-Hinweis (`correlation_duplicate`); Aktionspfad läuft weiter |
| `refused_by_policy` | Smolit-Assistant Policy verweigert wegen Korrelations-Verletzung | Standard-Failure-Mode aus ADR-0005 §9 |

## 11. Non-goals

PR 46 ist **Docs/Contract-only**:

- **Kein Code** — kein neues Feld in `AuditEvent`, kein neues Feld
  in Action-Events, kein neues Feld im IPC-Wire-Format.
- **Keine IPC-Schema-Änderung.**
- **Keine Wire-Protokoll-Erweiterung** in
  [`docs/api.md`](../api.md).
- **Keine Distributed-Tracing-Implementation** (kein
  OpenTelemetry, kein W3C Trace Context).
- **Keine Audit-Persistenz** (Ring-Buffer bleibt in-memory).
- **Keine kryptografische Signatur** der Audit-Events.
- **Keine externe Log-Shipping-Integration.**
- **Kein Replay-Harness.**
- **Keine Edits** in ABrain / Smolit_AdminBot / OceanData /
  smolitux-ui.

## 12. Future work

Reihenfolge nicht bindend; alle Schritte hinter eigenen PRs:

- **FA-1.** `correlation_id`-Feld zu `AuditEvent` ergänzen (Code,
  hinter Feature-Flag, default-off bis Tests grün).
- **FA-2.** `correlation_id`-Feld zu Action-Events
  (`action_planned`, `action_started`, …).
- **FA-3.** `correlation_id`-Mirror in ABrain Native Contract
  (lebt im ABrain-Repo).
- **FA-4.** `correlation_id`-Pflicht für AdminBot-Mutationen
  (lebt in einem zukünftigen `ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`,
  siehe ADR-0005 FA-1).
- **FA-5.** Smoke-Tests, die die End-to-End-Korrelation für
  `interaction_open_application` (lokal) und `abrain_native →
  action_planned → approval → action_completed` (zukünftig)
  prüfen.
- **FA-6.** Settings-Shell-Anzeige der `correlation_id` als
  Dev-/Debug-Hinweis (optional, hinter `accessibility_rpc`-artigem
  Feature-Flag).
