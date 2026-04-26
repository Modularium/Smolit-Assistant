# PR 54 — Audit Correlation ID Runtime Spike

- **Date:** 2026-04-26
- **Workstream:** E (Approval / Policy / Tool-Gating)
- **Branch:** `feat/audit-correlation-id-runtime`
- **Status:** landed (code-spike, additive, default-on within
  Smolit-Assistant; no cross-repo wire).
- **Spec:** [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md)
  — implements FA-1 locally.

---

## 1. Scope

Erste Code-Implementation der Audit Correlation ID Spec FA-1.
PR 54 hängt eine optionale, additive `correlation_id` in den
Smolit-Assistant Action-/Approval-/Audit-Lifecycle ein. Eine
Aktion, die der Core lokal plant, sieht ab jetzt eine durchgehende
`corr_…`-Identität von der ersten IPC-Antwort bis zum letzten
Audit-Eintrag.

PR 54 ist bewusst klein:

- **Lokal.** Kein Cross-Repo-Wire, kein Echo, kein
  Distributed Tracing.
- **Additiv.** Kein neues IPC-Command, kein neues
  Outgoing-Envelope, keine UI-Änderung.
- **Stabil.** Same `correlation_id` über alle Lifecycle-Schritte
  desselben Pfads; Double-Approve / Re-Resolve erzeugt **keine**
  zweite ID.

## 2. Implemented

### 2.1 Generator + Validator

- Neues Modul [`core/src/audit/correlation.rs`](../../core/src/audit/correlation.rs).
- `generate_correlation_id() -> String` produziert
  `corr_<timestamp_ms_hex(12)><counter_hex(16)>` (33 Zeichen
  insgesamt, ≪ 80-char-Limit der Spec §5).
- `sanitize_correlation_id(Option<String>) -> Option<String>`
  validiert Prefix, Charset (`[a-z0-9_]`), Mindest- und
  Maximal-Länge.
- Re-Exports in [`core/src/audit/mod.rs`](../../core/src/audit/mod.rs).
- Sieben Unit-Tests im Modul:
  `generated_correlation_id_has_corr_prefix`,
  `generated_correlation_id_is_lowercase_safe_charset`,
  `generated_correlation_id_fits_max_length`,
  `generated_correlation_ids_are_not_constant`,
  `invalid_correlation_id_is_rejected`,
  `valid_correlation_id_passes_sanitization`,
  `generated_correlation_id_shape_is_stable`.

### 2.2 Audit-Modell

- `AuditEvent.correlation_id: Option<String>` —
  [`core/src/audit/event.rs`](../../core/src/audit/event.rs).
- `AuditFields.correlation_id` plus Builder-Methoden
  `with_correlation_id(...)` und
  `with_correlation_id_opt(Option<...>)`.
- `AuditFields::sanitized()` läuft über
  `sanitize_correlation_id` — kaputte Tokens werden zu `None`
  geklemmt, **nie** roh durchgereicht.
- Store ([`core/src/audit/store.rs`](../../core/src/audit/store.rs))
  spiegelt das neue Feld in den vom `record(...)`-Pfad gebauten
  `AuditEvent`.

### 2.3 Action-/Approval-Payloads

Folgende Payloads tragen ein neues, optionales `correlation_id:
Option<String>`-Feld
([`core/src/actions/event.rs`](../../core/src/actions/event.rs)):

- `ActionPlannedPayload`
- `ActionStartedPayload`
- `ActionStepPayload`
- `ActionVerificationPayload`
- `ActionCompletedPayload`
- `ActionFailedPayload`
- `ActionCancelledPayload`
- `ActionProgressPayload`

Approval-Payloads in
[`core/src/approvals/request.rs`](../../core/src/approvals/request.rs):

- `ApprovalRequest.correlation_id`
- `ApprovalResolvedPayload.correlation_id`

Alle Felder sind `#[serde(default, skip_serializing_if =
"Option::is_none")]` — Wire-Form bleibt rückwärts kompatibel,
keine `null`-Werte landen im JSON.

### 2.4 InteractionAction

- `InteractionAction.correlation_id: Option<String>`
  ([`core/src/interaction/action.rs`](../../core/src/interaction/action.rs)) —
  damit der Executor nicht jede Helper-Signatur erweitern muss.
- `InteractionExecutor::run_approved` /
  `InteractionExecutor::execute` /
  `InteractionExecutor::refusal_events` lesen das Feld und
  spiegeln es in jedem ausgehenden Action-Event
  ([`core/src/interaction/executor.rs`](../../core/src/interaction/executor.rs)).
- `refusal_events` nimmt zusätzlich ein
  `correlation_id: Option<&str>` für den Policy-Refusal-Pfad
  entgegen (so trägt das `ActionFailed` aus einer Disabled-Layer-
  oder `ActionKindDisallowed`-Ablehnung dieselbe Korrelation wie
  das vorausgegangene `ActionPlanned`).

### 2.5 App-Wiring

[`core/src/app.rs`](../../core/src/app.rs) setzt die
`correlation_id` an drei Eintrittspunkten und trägt sie durch:

- **`plan_demo_action`** — generiert die ID am Anfang, schreibt
  sie in `IpcCommandReceived`, `ActionPlanned` und (falls
  Approval verlangt) in `ApprovalRequested`. Der gespawnte
  Executor-Task (`await_and_execute_demo_plan` /
  `execute_demo_plan`) bekommt sie als zusätzliches
  `correlation_id`-Argument und schreibt sie in
  `ApprovalResolved`, `ActionStarted`, `ActionStep`,
  `ActionCompleted` bzw. `ActionCancelled` (für Denied /
  Cancelled / TimedOut, jeweils via
  `record_plan_cancel_audit`).
- **`dispatch_interaction`** — Eintrittspunkt für
  `interaction_open_application` und
  `interaction_focus_window`. Erzeugt die ID, falls die `action`
  noch keine trägt, und schreibt sie in `action.correlation_id`,
  in `IpcCommandReceived`, `ActionPlanned`, `ApprovalRequested`,
  und über `await_and_continue` in `ApprovalResolved` und alle
  vom Executor zurückgegebenen Lifecycle-Frames.
  `record_interaction_lifecycle_audit` benutzt
  `with_correlation_id_opt`, weil ältere Tests die Action ohne
  Korrelation aufbauen können.
- **`request_approval_demo`** — der UX-Demo-Pfad bekommt
  ebenfalls eine `correlation_id` am Eingangstor; sie reist von
  `ApprovalRequested` über `await_and_resolve_demo` bis ins
  `ApprovalResolved`.

Read-only-Pfade (`probe_accessibility`,
`discover_accessibility`, `submit_text` /
`speak_text`-Helper-Frames, `ping`, `get_status`, `audit_recent`
selbst) **lassen** das Feld leer — entsprechend Spec §6
(„Nicht-Punkte" und „Optionale Punkte").

### 2.6 Tests

- 9 neue Lifecycle-Invariant-Tests in
  [`core/src/ipc/server.rs`](../../core/src/ipc/server.rs)
  (Test-Modul am Ende):
  - `plan_demo_action_audit_events_share_correlation_id`
  - `open_application_approved_chain_shares_correlation_id`
  - `open_application_denied_chain_shares_correlation_id`
  - `open_application_timeout_chain_shares_correlation_id`
  - `double_approve_does_not_create_second_correlation_id`
  - `audit_recent_includes_optional_correlation_id_for_action_events`
  - `non_action_commands_do_not_require_correlation_id`
  - `approval_request_carries_same_correlation_as_action`
  - `action_completed_carries_same_correlation_as_action_started`
- 7 Generator-Unit-Tests in
  [`core/src/audit/correlation.rs`](../../core/src/audit/correlation.rs)
  (siehe §2.1).
- Bestehende Tests bleiben unverändert (`cargo test` 424 passed,
  vorher 415).

### 2.7 Docs

- [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md):
  Status (Runtime FA-1 implemented), §3 Identifier-Tabelle, §11
  Non-Goals und §12 Future Work aktualisiert. Der Cross-Repo-
  Vertrag bleibt **Spec**, nur die lokale Smolit-Assistant-
  Implementation ist code-fest.
- [`docs/api.md`](../api.md): neuer Unterabschnitt „Optional:
  `correlation_id` (PR 54)" unter den Action-Events plus
  Erweiterung des `audit_recent`-Eintrags.
- [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md):
  neuer Unterabschnitt „Optional: `correlation_id` (PR 54)" mit
  den Garantien und Sanitisierungs-Regeln.
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md): Workstream E aktualisiert
  (FA-2 Implementation = erledigt in PR 54; Cross-Repo bleibt
  Folgearbeit).
- [`ROADMAP.md`](../../ROADMAP.md) §6.4: PR 54 als gelandet
  markiert.
- Reviews-Index aktualisiert (siehe
  [`docs/reviews/README.md`](./README.md)).

## 3. Not implemented

- **Kein Cross-Repo-Wire.** Kein ABrain-Echo, kein
  AdminBot-Pflicht-Pfad, kein OceanData-Akzeptanz-Pfad. Spec
  §8 bleibt ein zukunftsbindender Vertrag, kein Code.
- **Kein OpenTelemetry / W3C traceparent.**
- **Keine Audit-Persistenz / Export.** Ring-Buffer bleibt
  in-memory.
- **Kein neues IPC-Command** (kein `audit_correlation`-Endpoint,
  keine Settings-Shell-Anzeige).
- **Keine UI-Änderung.** Approval-Card und Audit-Panel rendern
  das neue Feld nicht; sie ignorieren es.
- **Kein fail-closed-Verhalten.** Spec §10 bleibt Future Work
  (`missing_correlation_id` ist im Spike kein Hard-Fail).
- **ULID/UUID-v7 nicht implementiert.** Generator nutzt einen
  prozesslokalen `timestamp_ms+counter`-Hex-Body. Spec §5
  erlaubt das ausdrücklich; ULID/UUID-v7 wandert auf FA-7.

## 4. Runtime behavior

Beispielablauf für ein
`{"type":"interaction_open_application","application":"calendar"}`:

1. Core empfängt den Command, generiert `corr_…`, schreibt
   `IpcCommandReceived` (Audit) mit der ID.
2. Sendet `action_planned` (mit `correlation_id`).
3. Schreibt `ActionPlanned` (Audit) mit der ID.
4. Sendet `approval_requested` (mit `correlation_id`,
   `risk: "medium"`, `selected_target` falls gesetzt).
5. Schreibt `ApprovalRequested` (Audit) mit der ID.
6. UI antwortet mit `approval_response`/`approval_approve`.
7. Core sendet `approval_resolved` (mit `correlation_id`),
   schreibt `ApprovalResolved` (Audit).
8. Executor läuft: `action_started`, `action_step`,
   `action_step`, `action_verification`, `action_completed`
   (alle mit `correlation_id`), parallele Audit-Einträge mit
   derselben ID.

Cancel-Pfade (Denied / Cancelled / TimedOut) verzweigen nach §7,
schreiben `action_cancelled` mit derselben ID, schreiben
`ActionCancelled` (Audit) mit derselben ID — keine neue ID,
keine zweite Korrelation.

Double-Approve auf demselben `approval_id`: der zweite
`approval_response` löst ein `ipc_command_rejected` (Audit-
Eintrag, ohne Korrelations-ID) aus, **nicht** einen zweiten
Lifecycle. Test
`double_approve_does_not_create_second_correlation_id` lockt das.

## 5. Wire compatibility

- **Backwards-compatible.** Das neue Feld ist überall optional
  und wird dank `skip_serializing_if = "Option::is_none"` nur
  emittiert, wenn der Core es gesetzt hat.
- **Frontwards-tolerant.** Ältere UIs (vor PR 54) ignorieren das
  Feld und sehen sonst dieselbe Wire-Form wie vorher.
- **Kein neuer Variant.** `IncomingMessage` /
  `OutgoingMessage` haben **keine** neue Variante; PR 54 fügt
  Felder zu bestehenden Payloads hinzu, sonst nichts.
- **`audit_recent` kompatibel.** Der `AuditRecentPayload`
  enthält ggf. `correlation_id` pro Event; ältere Reader
  ignorieren es. Tests
  `audit_recent_includes_optional_correlation_id_for_action_events`
  und `non_action_commands_do_not_require_correlation_id`
  locken beide Seiten.

## 6. Security constraints

- `correlation_id` ist **kein** User-Identifier. Body-Inhalt
  ist ein lokal generiertes
  `timestamp_ms+counter`-Hex-Token — kein Pfad, kein Hostname,
  kein Username, kein Secret, kein Kommando-String, kein
  lesbarer ISO-Zeitstempel.
- Sanitisierung läuft am Eingangstor (`with_correlation_id*`
  setzt das Feld; `AuditFields::sanitized()` validiert via
  `sanitize_correlation_id`). Tests
  `invalid_correlation_id_is_rejected` lockt das.
- Kein Netzwerk, kein DNS, keine Persistenz, kein Export, kein
  OpenTelemetry. Der Generator hat keine externe Dependency.
- Audit-Sanitization-Regeln aus
  [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)
  bleiben unverändert: keine Command-Templates, keine
  Env-Namen, keine Secrets in Audit-Summaries — die
  `correlation_id` darf weder solche Inhalte transportieren
  noch zu deren Aufdeckung führen.

## 7. Verification

Lokal ausgeführt:

```bash
bash scripts/ci_verify.sh core
# → 424 passed; 0 failed; ci_verify: PASS

bash scripts/run_overlay_verification.sh settings-shell-smoke
# → settings_shell smoke: PASS

cargo test --manifest-path core/Cargo.toml --locked
# (gleiche 424 Tests; CI-Skript setzt zusätzlich XDG-Isolation,
#  damit zwei pre-existing Tests nicht über lokale Settings-
#  Drift fallen — siehe PR 51.)
```

Greps (alle erwartet sauber):

```bash
rg "<<<<<<<|=======|>>>>>>>" core docs README.md ROADMAP.md
# → keine Konflikt-Marker

rg "AdminBot|OceanData|ABrain" core
# → keine Treffer im Code (nur Docs)

rg "correlation_id" core/src
# → ausschließlich in audit/, actions/event.rs, approvals/request.rs,
#   interaction/{action,executor}.rs, app.rs, ipc/{server,protocol}.rs
```
