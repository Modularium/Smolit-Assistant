# Approval UX v1 — Prinzipien und Grenzen (PR 17)

## Leitprinzip

**Control > Autonomy.** Smolit darf eine Aktion *erklären* und um
*Zustimmung bitten*. Er darf sie in PR 17 weder eigenmächtig
ausführen, noch über die Approval-Card eine neue gefährliche
Operation einführen. Die Approval-UX ist eine Oberfläche, kein
Fähigkeits-Upgrade.

## Harte Grenzen von PR 17

1. **Explicit user consent.** Jede geplante Aktion, die durch die
   Approval-Card gezeigt wird, wartet auf eine bewusste User-
   Entscheidung. Keine impliziten Timeouts, die zu „approve" werden
   können; ein Timeout resolvet immer als `timed_out` mit
   `source: timeout`.
2. **Short summaries.** Die UI kürzt Titel hart auf 80 Zeichen,
   Summaries auf 140. Kein Full-Payload-Dump. Wer mehr Inhalt
   zeigen will, bricht das Prinzip.
3. **No hidden payloads.** Der Core darf im `approval_requested`-
   Envelope keine sensiblen Daten mitschicken, die der User nicht
   lesen kann. Die UI-Schicht filtert nicht nach — der Core ist
   verantwortlich, nur menschenlesbare, kuratierte Strings zu
   emittieren.
4. **No dangerous execution in this PR.** Der einzige durch die
   Approval-Card auslösbare Core-Pfad, der in PR 17 **neu** ist, ist
   der Demo-Auslöser `request_approval_demo`. Dieser führt *keine*
   Aktion aus — er öffnet eine Approval-Kette, wartet auf eine
   Entscheidung und emittiert genau ein `approval_resolved`. Kein
   Shell, kein Desktop-Automation, kein Provider-Aufruf, kein
   AdminBot.
5. **Idempotent resolution.** Der bestehende
   `PendingApprovalRegistry`-Pfad enforced: ein zweiter
   `approve`/`deny`/`response` auf dieselbe `approval_id` kommt als
   `error`-Frame zurück, niemals als zweites `approval_resolved`.
   Doppelte UI-Klicks sind dadurch harmlos.
6. **No persistence.** Keine Approval-Historie, kein Remember-
   this-choice, kein Audit-Log-Artefakt. Ein Core-Restart leert alle
   pending Approvals.
7. **No policy engine.** Die Approval-Entscheidung gilt genau für
   den aktuellen, vom Core geöffneten Approval — nicht für eine
   Klasse von Aktionen, nicht für eine zukünftige Sitzung.

## Wire-Form (additive Erweiterung)

Der bestehende Approval-Pfad aus [`docs/api.md` §2.7](../api.md)
bleibt unverändert. PR 17 fügt rein additiv hinzu:

- `ApprovalRequest.risk` (`low` / `medium` / `high`, Default
  `medium`). Ältere Emitter bleiben kompatibel — der serde-Default
  hält das Feld präsent.
- `ApprovalResolvedPayload.source` (`user` / `timeout` / `system`,
  Default `user`). Ältere Empfänger ignorieren das Feld.
- Commands `approval_approve` / `approval_deny` als schmale
  Varianten von `approval_response`. Wire-semantisch äquivalent;
  nur Code-Stil-Präferenz.
- Command `request_approval_demo { title?, summary?, risk? }` —
  harmloser Demo-Pfad. Der Core fillt Defaults, wenn Felder
  fehlen; unbekannte Risikostufen werden auf `medium` geklemmt.

## Verifikation (PR 17)

Core-Unit- und IPC-Tests (`cargo test`) decken ab:

- Risk-Sanitizer akzeptiert/normalisiert `low` / `medium` / `high`
  und fängt unbekannte Werte auf `medium` ab.
- `request_approval_demo` emittiert `approval_requested` mit
  korrektem Risk-Feld und leerem `action_id`.
- Approve/Deny resolvet ohne Folgeereignisse (insbesondere **kein**
  `action_cancelled`, da keine Aktion existiert).
- Doppelter Approve auf dieselbe `approval_id` → `error`-Frame.
- Unbekannte `approval_id` → `error`-Frame ohne Panic.
- Interaction-Approvals (Desktop-Interaction-Flow aus §2.7)
  tragen weiterhin `decision` plus neu `source` und `risk=medium`.

UI-Smoke (`scripts/approval_card_smoke.gd`, Harness-Case
`approval-card-smoke`):

- `SmolitApprovalModel.sanitize_risk` / `trim_title` / `trim_summary`
  / `decision_outcome` / `is_terminal_decision` auf Pure-Ebene.
- Panel-Scene: Default-hidden, Rendern bei `approval_requested`,
  Summary-Kürzung, Resolving-Flow mit Idempotenz, Mismatched-ID-
  Ignore, Disconnect-Pfad, Missing-Fields-Toleranz,
  `reset_for_tests`.
- Quelltext-Assertion, dass `ipc_client.gd` die drei neuen Commands
  (`approval_approve`, `approval_deny`, `request_approval_demo`)
  trägt.

## Nicht-Ziele (PR 17)

- **Echtes Tool-Gating.** Ein Policy-Layer, der ausgewählte
  Core-Aktionen automatisch durch den Approval-Pfad zwingt, bleibt
  Folgearbeit. PR 17 liefert nur die UX-Oberfläche.
- **Feinere Risk-Achse.** Dreistufig genügt für MVP; eine feinere
  Skala (Score, Begründung) ist explizit zukünftig.
- **Audit-Log / Persistenz.** Nicht in diesem PR. Falls gewünscht,
  braucht es eine eigene Design-Entscheidung (welche Daten, wie
  lange, mit welcher Vertraulichkeit).
- **Multi-Seat.** Genau ein UI-Client entscheidet.
- **Kryptografische Absicherung.** Der lokale Loopback-WebSocket
  bleibt Vertrauensgrenze wie in §2.7.

## Verhältnis zu PRs 14–16

- **PR 14 Speech-Sync** — kein direkter Zusammenhang; die
  Approval-Card blockiert weder TTS noch wird sie vom TTS-Lifecycle
  getriggert.
- **PR 15 Behavioral Expression Layer** — weicher Hook: der Avatar
  zieht bei `approval_requested` auf `curious`, bei
  `denied`/`cancelled`/`timed_out`/`expired` auf `error_soft`.
  Bestehende Guards (kein Überschreiben von ACTING/ERROR) gelten
  unverändert.
- **PR 16 Workflow Visibility Overlay** — neuer Step-Kind
  `APPROVAL` rendert Approval-Requests als zusätzliche Karte in
  der linearen Workflow-Kette. Kein eigenes Historien-System.

## Betrieb

Der Demo-Pfad ist für Entwicklung/UX-Evaluation gedacht. In einer
produktiven Umgebung empfiehlt sich:

- `SMOLIT_UI_DEV_CONTROLS=1` nur auf Dev-Maschinen setzen; die drei
  Demo-Buttons erscheinen sonst nicht.
- `request_approval_demo` sendet **keine sensiblen Daten** — der
  Core akzeptiert beliebige Strings im Payload. Wenn die UI den
  Demo-Auslöser aufruft, schickt sie feste, harmlose Default-Texte.
- Der bestehende Interaction-Approval-Flow
  (`interaction_open_application` → `approval_requested` →
  `approval_response`) bleibt die produktive Route; die Card zeigt
  beides identisch an (Card + bestehender ApprovalBanner laufen
  parallel, bis ein künftiger Refactor die beiden UI-Surface
  vereinheitlicht).
