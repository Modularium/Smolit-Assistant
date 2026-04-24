# Local Audit Trail v1 — Prinzipien und Grenzen (PR 19)

## Zweck

Der Audit-Store protokolliert, **was passiert ist**, damit jemand es
später nachvollziehen kann — lokal, in-memory, klein. Er ist ein
Dev-/Debug-Hilfsmittel, kein Produkt-Feature.

Konkret erfasst er den Lifecycle der Approval-Gated Demo-Actions aus
PR 18 (plus ein paar IPC-Grenzfälle):

- `plan_demo_action` kam an → `ipc_command_received`
- `action_planned` emittiert → `action_planned`
- `approval_requested` emittiert → `approval_requested`
- `approval_resolved` emittiert → `approval_resolved` (+ `result` / `source`)
- `action_started` / `action_completed` / `action_cancelled` →
  passender `action_*`-Eintrag
- Idempotenter Fehlschlag (unbekannte / bereits aufgelöste
  `approval_id`) → `ipc_command_rejected`

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
