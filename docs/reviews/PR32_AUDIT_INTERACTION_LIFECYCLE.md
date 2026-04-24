# PR 32 — Audit Coverage für reale Interaction-Actions

- **Datum:** 2026-04-24
- **Scope:** Workstream E (Approval / Policy / Tool-Gating).
  Schließt die ehrliche Audit-Lücke aus PR 25: der reale
  `interaction_open_application`-Lifecycle war nicht auditiert.
  Da `dispatch_interaction` + `await_and_continue` auch
  `interaction_focus_window` bedienen, erstreckt sich die
  Coverage **generisch** auf beide Kinds.
- **Guardrails:** kein Persistenz-Pfad, kein neuer IPC-Command,
  keine neuen Capabilities, keine Smolitux-/OceanData-Arbeit.

---

## 1. Entscheidung: Option A (generisch) statt Option B (nur open_application)

Die Task-Beschreibung erlaubte zwei Scopes:

- **Option A:** Audit-Coverage generisch für `InteractionAction`.
- **Option B:** Nur `open_application` in PR 32; `focus_window`
  als Folgearbeit dokumentieren.

Der Ist-Zustand des Cores zeigte, dass beide Real-Interaction-Kinds
dieselbe Einstiegsfunktion
`App::dispatch_interaction` und denselben Approval-Warte-Task
`App::await_and_continue` nutzen
(`core/src/app.rs:1326` und `1376`). `execute_open_application`
und `execute_focus_window` konstruieren jeweils eine
`InteractionAction`, flippen `requires_confirmation = true` und
rufen `dispatch_interaction` auf — ab da ist der Pfad identisch.

Damit ist Option A **ohne Refactor** möglich: die Audit-Aufrufe
landen im gemeinsamen Pfad und bedienen beide Kinds byte-
identisch. Option B hätte bedeutet, die Audit-Logik künstlich auf
`open_application` einzuschränken und dann in einer Folgearbeit zu
verdoppeln — mehr Code, mehr Drift-Risiko, kein Vorteil.

**Entscheidung:** Option A.

## 2. Konkret gelandet

### 2.1 Audit-Aufrufe auf dem geteilten Interaction-Pfad

**`App::dispatch_interaction`** (`core/src/app.rs`) schreibt jetzt
(alle in dieser Reihenfolge):

1. `IpcCommandReceived` — Summary
   `interaction_<kind>: <action_title>` (z. B.
   `interaction_open_application: Open calendar`). `source = ui`.
2. `ActionPlanned` nach dem `plan_event` — Summary `action.title`,
   `source = core`.
3. **Bei Policy-Refusal** (`layer_disabled` / `kind_not_allowed`):
   zusätzlich ein `ActionFailed`-Eintrag mit `result=failed`;
   der Policy-Error-Text selbst landet **nicht** im Summary.
4. **Direkt-Run-Branch** (`needs_approval == false`, d. h. Tests
   mit `require_confirmation=false`): via neuen Helper
   `record_interaction_lifecycle_audit` aus dem zurückgegebenen
   `Vec<OutgoingMessage>` die Lifecycle-Grenzen
   (`ActionStarted` / `ActionCompleted` / `ActionFailed` /
   `ActionCancelled`) in den Store schreiben.
5. **Approval-Branch** (heute Produktiv-Default unter Policy v0):
   `ApprovalRequested` mit `approval_id`, `action_id`,
   `risk=medium`, `source=core`.

**`App::await_and_continue`** (`core/src/app.rs`) schreibt auf dem
Wege der Decision-Resolution:

6. `ApprovalResolved` mit `result ∈ approved / denied / cancelled /
   expired` und `source ∈ user / system / timeout`.
7. Bei **Approved**: ruft denselben `record_interaction_lifecycle_audit`
   auf dem vom Executor zurückgegebenen `Vec<OutgoingMessage>` auf
   — schreibt `ActionStarted` + `ActionCompleted` (oder
   `ActionFailed` / `ActionCancelled` je nach `ActionStatus`).
8. Bei **Denied / Cancelled / TimedOut**: direkter
   `ActionCancelled`-Audit-Eintrag mit `result=denied` /
   `cancelled` / `expired` und der `source`-Variable aus dem
   Wartepfad.

### 2.2 Neuer Helper

`App::record_interaction_lifecycle_audit(action, messages)` ist
eine reine App-Methode, die den Executor **nicht** auf
`AuditStore` koppelt. Sie liest ausschließlich die typisierten
`OutgoingMessage`-Varianten und schreibt passende Audit-Einträge:

- `ActionStarted { .. }` → `AuditKind::ActionStarted`.
- `ActionCompleted { payload }` → `AuditKind::ActionCompleted`,
  `result` aus `payload.status` (`completed` / `failed` /
  `cancelled`).
- `ActionFailed { .. }` → `AuditKind::ActionFailed` mit
  `result=failed`.
- `ActionCancelled { .. }` → `AuditKind::ActionCancelled` mit
  `result=cancelled`.
- Alle anderen Varianten (`ActionStep`, `ActionVerification`, …)
  werden bewusst ignoriert — der Audit-Fokus liegt auf
  Lifecycle-Grenzen, nicht auf Zwischen-Frames.

### 2.3 IpcCommandReceived-Anker

Die Audit-Summary für den Entry-Eintrag nutzt das Format
`interaction_<kind>: <action_title>`. Das ist bewusst — so stehen
`interaction_open_application` und `interaction_focus_window` als
Suchbegriff zur Verfügung, ohne dass ein Audit-Leser das
Command-Template, den Env-Namen oder den Window-Match-String
sieht.

### 2.4 Keine Protokoll-Erweiterung

Weder `protocol.rs` noch `server.rs` bekommen neue Command- oder
Envelope-Typen. Alle Audit-Aufrufe leben auf der App-Schicht; der
IPC-Server dispatcht nach wie vor auf `execute_open_application` /
`execute_focus_window`, die jetzt — via `dispatch_interaction` —
auditieren.

## 3. Chain-Tabelle

### 3.1 Approved-Pfad (Default Policy v0)

```
ipc_command_received   source=ui    summary="interaction_open_application: Open calendar"
action_planned         source=core  summary="Open calendar"
approval_requested     source=core  approval_id=apr_… action_id=act_… risk=medium
approval_resolved      source=user  result=approved
action_started         source=core
action_completed       source=core  result=completed
```

### 3.2 Denied-Pfad

```
ipc_command_received   source=ui
action_planned         source=core
approval_requested     source=core
approval_resolved      source=user  result=denied
action_cancelled       source=user  result=denied
```

Es gibt **kein** `action_started` oder `action_completed` — ohne
User-Zustimmung läuft der Backend-Aufruf nicht. Test:
`audit_recent_records_open_application_denied_chain`.

### 3.3 Timeout-Pfad

```
ipc_command_received   source=ui
action_planned         source=core
approval_requested     source=core
approval_resolved      source=timeout  result=expired
action_cancelled       source=timeout  result=expired
```

Der Watchdog (`SMOLIT_APPROVAL_TIMEOUT_SECONDS`, Default 20)
konvertiert das Nicht-Antworten in eine `TimedOut`-Decision; Audit
schreibt `result=expired` und `source=timeout`. Test:
`audit_recent_records_open_application_timeout_chain`.

### 3.4 Double-Approve-Idempotenz

Ein zweiter `approval_response` auf dieselbe `approval_id` wird
vom `PendingApprovalRegistry` abgelehnt und erzeugt
`ipc_command_rejected` mit `result=rejected` — **kein** zweites
`action_completed`. Test:
`audit_recent_open_application_double_approve_does_not_double_complete`.

### 3.5 focus_window

Gleiche Kette wie `open_application`, ebenfalls durch Approval
gegated, wenn das doppelte Opt-in gesetzt ist
(`SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW=1` +
`SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`). Test:
`audit_recent_records_focus_window_approved_chain_generic`.

## 4. Security-Invarianten (aktiv getestet)

- **Kein Command-Template leaked.** Tests prüfen aktiv, dass
  weder `/bin/true` (Test-Template) noch `wmctrl` (Real-Template)
  in der Audit-Antwort auftauchen.
- **Kein Env-Variablen-Name leaked.** `SMOLIT_INTERACTION_OPEN_APP_CMD`
  erscheint nie im Summary.
- **Kein Secret.** Der Secrets-Store-Zugriff (`cloud_http`-Key) ist
  nicht Teil des Interaction-Pfads; Audit-Summaries beziehen sich
  ausschließlich auf den menschenlesbaren `action.title`.
- **`source` / `result` / `risk` gehen durch die bestehenden
  `sanitize_*`-Whitelists** aus PR 19 (keine neuen Labels, keine
  Freitext-Werte).
- **`summary` bleibt ≤ 80 Zeichen** (`MAX_SUMMARY_CHARS`).

## 5. Was **nicht** Teil von PR 32 ist

- **Keine Persistenz.** Ring-Buffer bleibt in-memory; Core-Restart
  leert ihn. Kein Dateisystem, keine DB, kein Cloud-Upload.
- **Kein Export.** Kein `audit_save`, kein
  `audit_copy_to_clipboard`.
- **Kein `audit_clear`.** Read-only bleibt die einzige externe
  Oberfläche.
- **Keine kryptografische Signatur.**
- **Keine neuen Interaction-Kinds.** `type_text` und
  `send_shortcut` bleiben `BackendUnsupported`; sie treten nie in
  einen Audit-Lifecycle ein.
- **Keine Step-/Verification-Audit-Einträge.** Der Audit-Pfad
  fokussiert sich auf Lifecycle-Grenzen (Start / Abschluss), nicht
  auf jedes Zwischen-Frame. Das Workflow Visibility Overlay
  (PR 16) ist der Ort, an dem Steps für die UI sichtbar werden.
- **Keine UI-Änderung.** Das bestehende Audit-Panel rendert die
  neuen Einträge mit denselben Labels wie den Demo-Pfad
  (`audit-panel-smoke` bleibt grün ohne Anpassung).
- **Keine Smolitux-Token-Arbeit**, keine `smolitux-ui`-Änderung,
  keine OceanData-Abhängigkeit.

## 6. Honesty Check

- ✅ `open_application` real verdrahtet und vollständig auditiert.
- ✅ `focus_window` ebenfalls auditiert (Generic-Coverage über den
  geteilten `dispatch_interaction`-Pfad).
- ✅ `type_text` / `send_shortcut` weiterhin `BackendUnsupported`
  — kein Audit-Lifecycle, weil keine Execution.
- ✅ Command-Templates, Env-Variablen-Namen und Secrets tauchen
  nicht in Audit-Einträgen auf (test-gelockt).
- ✅ Keine Persistenz, keine Protokoll-Erweiterung.
- ⚠️ Der Audit-Store bleibt nicht manipulationssicher — wer den
  Core-Prozess kompromittiert, kann Einträge frei manipulieren.
  Das war seit PR 19 so und ist ausdrücklich kein Produktziel
  dieser Linie.

Tests: 387 cargo-Tests grün (382 vor PR 32 + 5 neue PR-32-Chains).
Smokes: `audit-panel-smoke` und `approval-card-smoke` unverändert
grün.
