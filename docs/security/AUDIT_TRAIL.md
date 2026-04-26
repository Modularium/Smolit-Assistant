# Local Audit Trail v1 — Prinzipien und Grenzen (PR 19 + PR 32)

## Zweck

Der Audit-Store protokolliert, **was passiert ist**, damit jemand es
später nachvollziehen kann — lokal, in-memory, klein. Er ist ein
Dev-/Debug-Hilfsmittel, kein Produkt-Feature.

Seit PR 19 wird der Lifecycle der Approval-Gated Demo-Actions aus
PR 18 erfasst (plus ein paar IPC-Grenzfälle). **Seit PR 32**
(2026-04-24) deckt der Audit-Store zusätzlich die **echte
Interaction-Action-Kette** (`interaction_open_application` und
`interaction_focus_window`) ab — dieselbe Kind-Sequenz, derselbe
kuratierte Vokabular-Satz, dieselben Redaction-Regeln. Kein
Persistenz-Pfad, keine neuen IPC-Commands.

Erfasste Kinds in beiden Pfaden:

- IPC-Command kam an → `ipc_command_received`
  (Demo: `plan_demo_action`; real: `interaction_open_application` /
  `interaction_focus_window`, Summary formatiert als
  `interaction_<kind>: <title>` — nur der Action-Titel, **nie** das
  Command-Template aus `SMOLIT_INTERACTION_OPEN_APP_CMD` /
  `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`).
- `action_planned` emittiert → `action_planned`
- `approval_requested` emittiert → `approval_requested`
  (`risk=medium` für reale Interaction-Approvals, seit PR 17).
- `approval_resolved` emittiert → `approval_resolved`
  (`result` ∈ `approved` / `denied` / `cancelled` / `expired`,
  `source` ∈ `user` / `system` / `timeout`).
- `action_started` / `action_completed` / `action_cancelled` /
  `action_failed` → passender `action_*`-Eintrag mit
  kuratiertem `result`.
- Policy-Refusal (`layer_disabled` / `kind_not_allowed`) →
  `action_failed` mit `result=failed`, ohne Freitext aus der
  Policy-Error-Kette.
- Idempotenter Fehlschlag (unbekannte / bereits aufgelöste
  `approval_id`, Double-Approve) → `ipc_command_rejected` mit
  `result=rejected`.

## Leitprinzip: *accountability without surveillance*

Der Store darf helfen, Verhalten zu prüfen, aber keine unnötigen
Nutzerdaten sammeln. Das schlägt sich konkret nieder in:

- **Keine Full-Payloads.** `summary` ist hart auf **80 Zeichen**
  gekürzt (`MAX_SUMMARY_CHARS`), danach Ellipsis. Leere oder
  whitespace-only Strings werden nicht gespeichert.
- **Keine langen User-Texte.** Der Core übergibt keinen ABrain-
  Response, keinen STT-Transkript, keinen TTS-Text an den Store.
  Was gespeichert wird, ist der bereits in Approval-Cards /
  Workflow-Overlays sichtbare Titel — sonst nichts.
- **Kuratiertes Vokabular.** `source` wird gegen die Whitelist
  `user` / `timeout` / `system` / `ui` / `core` geprüft; `result`
  gegen `approved` / `denied` / `expired` / `completed` / `failed`
  / `cancelled` / `rejected`. Unbekannte Werte fallen auf `None` —
  wir speichern lieber kein Feld als ein freies Label.
- **`risk` bleibt `low` / `medium` / `high`.** Dieselbe Whitelist
  wie in PR 17; unbekannte Werte werden auf `medium` geklemmt.

## Speicherung

- **Ring Buffer.** `VecDeque<AuditEvent>` mit fester Kapazität. Ein
  Insert über die Kapazität hinaus evictet den ältesten Eintrag.
- **Default-Kapazität:** `DEFAULT_MAX_EVENTS = 100`.
- **Hartes Maximum:** `HARD_MAX_EVENTS = 1000` — ein konfigurierter
  Wert über dieser Grenze wird geklemmt.
- **Env-Override:** `SMOLIT_AUDIT_MAX_EVENTS` (ungültige oder
  negative / `0`-Werte fallen auf den Default).
- **Keine Persistenz.** Ein Core-Restart leert den Store vollständig.
  Es gibt **keinen** Schreib-Pfad ins Dateisystem, **keinen** DB-
  Anschluss, **keinen** Cloud-Upload.
- **Keine Export-Funktion.** Der IPC-Command `audit_recent` ist
  read-only und liefert eine gekürzte Liste in-memory — kein `save`,
  kein `copy-to-clipboard` auf der UI-Seite.

## Wire-Form

Eingehend:

```json
{"type":"audit_recent","limit":20}
```

`limit` ist optional und wird auf `HARD_MAX_EVENTS` geklemmt. Fehlt
`limit`, liefert der Core den vollen Ring-Buffer-Inhalt.

Ausgehend:

```json
{
  "type":"audit_recent",
  "payload":{
    "events":[
      {
        "audit_id":"aud_000001",
        "timestamp_ms":1700000000000,
        "kind":"action_planned",
        "action_id":"act_000001",
        "risk":"medium",
        "source":"core",
        "summary":"Demo action"
      }
    ]
  }
}
```

`approval_id` / `result` / `action_id` / `summary` sind optional und
werden nur serialisiert, wenn der Store sie nach Sanitisierung
behalten hat.

### Optional: `correlation_id` (PR 54)

Seit PR 54 (Runtime FA-1 spike) trägt jeder AuditEvent, der zu einem
Action-/Approval-Lifecycle gehört, ein optionales
`correlation_id: "corr_<token>"`-Feld. Die ID wird vom Core früh am
Aktionspfad vergeben (in `plan_demo_action`, `dispatch_interaction`,
`request_approval_demo`) und durch alle Lifecycle-Schritte des
gleichen Pfads gespiegelt — `IpcCommandReceived`, `ActionPlanned`,
`ApprovalRequested`, `ApprovalResolved`, `ActionStarted`,
`ActionCompleted`, `ActionCancelled`, `ActionFailed`.

Garantien:

- **Additiv und optional.** Kein neuer IPC-Command, kein neues
  Outgoing-Envelope, keine Persistenz. Der Ring-Buffer bleibt
  in-memory.
- **Lokal.** Die ID verlässt den Prozess nicht; keine Cross-Repo-
  Propagation, kein Distributed Tracing.
- **Sanitisiert.** Format-Validator ist
  `crate::audit::sanitize_correlation_id`; ungültige Eingaben
  fallen zu `None`.
- **Keine Userdaten.** Body-Inhalt ist ein lokal generiertes
  `timestamp_ms+counter`-Hex-Token — keine Pfade, Hostnamen,
  Secrets, Kommando-Strings (siehe Spec §5/§9).

Audit-Einträge ohne Action-Kontext (z. B. ein `audit_recent`-Read
selbst, reine Settings-Probes oder ein
`ipc_command_rejected`-Refusal außerhalb eines Lifecycles) lassen
das Feld weg.

### Optional: `capability_id` (PR 55)

Seit PR 55 (Runtime FA-1 für
[`CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md))
trägt jeder AuditEvent eines lokalen Action-Lifecycles zusätzlich
ein optionales `capability_id`-Feld. Es benennt die kanonische
Capability laut Vocabulary §5; Werte stammen ausschließlich aus
[`crate::capabilities::KNOWN_CAPABILITY_IDS`].

Garantien:

- **Whitelist-only.** `AuditFields::sanitized()` ruft
  `crate::capabilities::sanitize_capability_id` — User-Strings
  ohne Vocab-Eintrag werden zu `None` geklemmt und nie
  geschrieben. Keine User-Eingabe landet als Capability im
  Audit-Store.
- **Descriptive metadata.** Das Feld ist *kein* Eingabewert für
  eine Permission-Entscheidung. Approval / Risk / Audit-Required
  bleiben in Policy v0 + bestehender Approval-Linie.
- **Stabil über den Lifecycle.** Eine Action behält ihre
  Capability-ID über IpcCommandReceived → ActionPlanned →
  (ApprovalRequested → ApprovalResolved) → ActionStarted/Step/
  Completed bzw. ActionCancelled. Re-Approve / Cancel / Timeout
  erzeugen keinen neuen Wert.
- **Anti-Rekursion.** `audit_recent` selbst löst keinen
  Audit-Eintrag aus; folglich erscheint `audit.read_recent` nicht
  als Audit-Capability.

Heute geschriebene Werte:

- `interaction.open_application` für `interaction_open_application`
- `interaction.focus_window` für `interaction_focus_window`
- `assistant.demo.echo` / `assistant.demo.wait` /
  `assistant.plan_demo_action` für die `plan_demo_action`-Pfade
  (kind-abhängig)
- `assistant.plan_demo_action` für `request_approval_demo`

Admin- und Data-Capabilities sind im Vokabular geführt, aber
[`crate::capabilities::is_executable_today`] liefert für sie
`false` — sie können nicht ausgeführt und folglich auch nicht in
einen lebenden Audit-Lifecycle geschrieben werden.

### Optional: Capability Guard Deny (PR 56)

Seit PR 56 läuft im Smolit-Assistant Core ein lokaler
Capability-Guard
([`core/src/capability_guard.rs`](../../core/src/capability_guard.rs)),
der die in PR 55 eingeführten Konstanten und Metadaten als
deny-only / fail-closed Filter nutzt. Wenn der Guard verweigert,
schreibt der Audit-Pfad einen Eintrag mit:

- `result = "capability_guard_denied"` — neue, kuratierte
  Whitelist-Konstante
  ([`crate::audit::RESULT_CAPABILITY_GUARD_DENIED`]); bewusst
  **getrennt** von `failed`, weil ein Guard-Deny eine
  deterministische Vor-Filterung ist, kein Backend-Fehler.
- `summary` mit kuratiertem Suffix `[guard:<reason>]`. Erlaubte
  Reason-Tokens in
  [`crate::capability_guard::KNOWN_GUARD_REASONS`]:
  `unknown_capability_id`, `capability_not_executable_today`,
  `future_capability_not_implemented`,
  `interaction_type_text_not_supported`,
  `interaction_send_shortcut_not_supported`.
- `correlation_id` und `capability_id` wie üblich (PR 54 / PR 55).

Garantien:

- **Fail-closed.** Unbekannte / future / unsupported Capabilities
  werden lokal abgelehnt; es entsteht kein Approval-Request, kein
  Backend-Run.
- **Whitelist-only.** Der Reason-Suffix in `summary` ist
  ausschließlich aus den kuratierten Tokens; keine User-Inhalte.
- **Kein neuer Wire-Typ.** Die Wire-Form bleibt
  `action_planned` → `action_started` → `action_failed` (oder ein
  `error`-Envelope auf dem Demo-Approval-Pfad). Keine neue UI,
  kein neues IPC-Command.
- **Anti-Bypass.** Der Guard hebt **keine** bestehende Sperre auf;
  er kann nur zusätzlich verweigern.

## UI (PR 19)

Ein kleines `AuditPanel` (`ui/scripts/audit/audit_panel.gd` +
`ui/scenes/audit/audit_panel.tscn`) rendert die letzten Einträge
vertikal:

- Zeit (`HH:MM:SS`) · Kind-Label · Risk · gekürzte ID · Summary
- Color-Tint pro Result (grün = approved/completed, rot = denied/
  cancelled/rejected/failed, gelb = expired)
- Refresh-Button sendet genau einen `audit_recent`-Request

Sichtbarkeit:

- **Standardmäßig hidden.** Sichtbar wird das Panel nur bei
  `SMOLIT_UI_DEV_CONTROLS=1` (gleiches Gate wie die anderen Dev-
  Hilfen).
- **Kein Auto-Refresh** — der Nutzer muss aktiv abfragen.
- **Kein Kopieren / Speichern** in PR 19. Eine spätere Variante
  müsste das als eigene Design-Entscheidung rechtfertigen (welche
  Daten, welche Vertraulichkeit, welche Speicherform).

## Coverage für reale Interaction-Actions (PR 32)

PR 32 weitet die Audit-Kette auf den **produktiv verdrahteten**
Interaction-Pfad aus (`interaction_open_application`,
`interaction_focus_window`). Beide Aktionen teilen sich seit PR 25
(Policy v0) den Approval-Pfad; PR 32 schließt die ehrliche Lücke aus
dem PR-25-Review, wo Audit nur den `plan_demo_action`-Lifecycle
abdeckte.

### Wo der Audit-Pfad ansetzt

- **`App::dispatch_interaction`** (`core/src/app.rs`) — die
  gemeinsame Einstiegsfunktion beider Interaction-Kinds — schreibt:
  - `IpcCommandReceived` (Summary `interaction_<kind>: <title>`)
  - `ActionPlanned`
  - Optional `ActionFailed` (bei Policy-Refusal)
  - `ApprovalRequested` (falls `require_confirmation=true`)
  - Beim Direkt-Run (No-Confirmation-Pfad, heute **nicht** Default
    unter Policy v0) zusätzlich die Lifecycle-Events per
    `record_interaction_lifecycle_audit`.
- **`App::await_and_continue`** — der Approval-Warte-Task —
  schreibt:
  - `ApprovalResolved` mit `result ∈ approved / denied / cancelled
    / expired`.
  - Auf Approved: ruft `record_interaction_lifecycle_audit` auf
    dem vom Executor zurückgegebenen Event-Vektor auf; schreibt
    `ActionStarted` + `ActionCompleted` (oder `ActionFailed` /
    `ActionCancelled` je nach `ActionStatus`).
  - Auf Denied / Cancelled / TimedOut: direkter
    `ActionCancelled`-Audit-Eintrag mit passendem `result`.

### Was garantiert **nicht** in den Store geht

- Command-Templates (`wmctrl -a {name}`, `xdg-open {name}`, …) —
  der Audit-Summary nutzt ausschließlich den menschenlesbaren
  Action-Titel.
- Env-Variablen-Namen (`SMOLIT_INTERACTION_OPEN_APP_CMD` etc.).
- User-Prompts oder ABrain-Antworten.
- Secrets aus dem Secrets-Store (`cloud_http`-API-Key).
- Audio-Bytes / STT-Transkripte / TTS-Texte.

Tests locken dieses Verhalten: u. a.
`audit_recent_records_open_application_approved_full_chain`,
`audit_recent_records_open_application_denied_chain`,
`audit_recent_records_open_application_timeout_chain`,
`audit_recent_records_focus_window_approved_chain_generic`,
`audit_recent_open_application_double_approve_does_not_double_complete`
in [`core/src/ipc/server.rs`](../../core/src/ipc/server.rs). Die
Tests prüfen aktiv, dass weder `/bin/true`, `wmctrl` noch Env-
Variablen-Namen in der Audit-Antwort auftauchen.

### Was bewusst **nicht** Teil von PR 32 ist

- **Keine Persistenz** — der Store bleibt in-memory, Ring-Buffer
  (siehe §Speicherung).
- **Kein Export** — keine neue `audit_*`-IPC-Route.
- **Kein `audit_clear`** — Read-only bleibt die einzige externe
  Oberfläche.
- **Keine kryptografische Signatur** — der Store ist weiterhin
  nicht manipulationssicher.
- **Keine Step-/Verification-Audit-Einträge** — der Audit-Pfad
  fokussiert sich auf Lifecycle-Grenzen (Start / Abschluss), nicht
  auf Zwischen-Frames. Das Workflow Visibility Overlay (PR 16) ist
  der Ort, an dem Steps für die UI sichtbar werden.
- **Keine Erweiterung der `sanitize_*`-Whitelists** —
  `source` / `result` / `risk` bleiben wie in PR 19 definiert.
- **Keine neuen Interaction-Kinds** — `type_text` und
  `send_shortcut` bleiben `BackendUnsupported`, werden also nie
  in einen Audit-Lifecycle eintreten.

## Nicht-Ziele (PR 19)

- **Keine Persistenz.** Weder Datei, DB noch Cloud.
- **Kein Datei-Export.** Kein `audit_save`, keine `.json`-Dump-
  Funktion.
- **Kein Cloud-Upload.** Der Loopback-WebSocket bleibt
  Vertrauensgrenze.
- **Keine vollständigen User-Prompts.** Summaries sind ≤ 80
  Zeichen.
- **Keine vollständigen TTS-/STT-Texte.** Der TTS-Lifecycle aus
  PR 14 hat bereits bewusst keinen Text im Event; PR 19 erweitert
  das nicht.
- **Keine Audio-Bytes.** Kein Puffer, kein Stream.
- **Keine Approval-Historie als Produktfeature.** Die UI zeigt nur
  die letzten Einträge im Ring-Buffer — keine Suche, keine
  Filterung, keine Exportformate.
- **Keine kryptografische Signatur.** Der Store ist weder
  manipulationssicher noch beweist er Authentizität. Wer den Core-
  Prozess kompromittiert, kann Einträge frei manipulieren.
- **Keine Policy-Engine.** Der Store beobachtet; er entscheidet
  nichts.
- **Keine AdminBot-/Desktop-/Shell-Aktionen.** PR 19 ist reine
  Observability über bestehende harmlose Pfade.

## Spätere Persistenz (out of scope PR 19)

Falls ein späteres PR Persistenz braucht (z. B. für einen echten
Compliance-Case), sind mindestens zu klären:

- **Was wird gespeichert?** Das aktuelle Feld-Set ist bereits
  sanitisiert; eine Persistenz-Variante darf das Set **nicht**
  erweitern, ohne den Nutzer explizit darüber aufzuklären.
- **Wo?** Ein lokaler Pfad (`~/.local/state/smolit/`) ist
  wahrscheinlich der sinnvollste Ort — kein Cloud-Default.
- **Verschlüsselung / Redaktion.** Eine Persistenz-Variante sollte
  jedes Feld ein zweites Mal redacten und optional symmetrisch
  verschlüsseln. Unverschlüsselte Langzeit-Logs sind explizit
  abgelehnt.
- **Rotation.** Ein Datei-Ring analog zum in-memory Ring, mit
  hartem Byte-/Datei-Limit und automatischer Rotation.
- **Opt-in.** Persistenz ist Opt-in (Env oder Settings), nicht
  Default. Der Nutzer muss sie bewusst einschalten.

Diese Punkte sind **noch nicht** implementiert. PR 19 bleibt
explizit beim Ring-Buffer-Modell.
