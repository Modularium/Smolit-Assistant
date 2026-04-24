# ADR-0003: ABrain Native Integration Path

- **Status:** Proposed (Docs/ADR-only — keine Code-Implementation).
- **Date:** 2026-04-24
- **Deciders:** Smolit-Assistant Maintainer
- **Scope:** Core (`core/src/providers/text.rs`, `core/src/config.rs`,
  `core/src/app.rs`) und ein zukünftiges natives ABrain-API. **Nicht**
  Teil dieses ADR: UI, Interaction-Layer, AdminBot, OceanData.
- **Workstream:** H — ABrain Native Integration.

---

## 1. Status

**Proposed.** ABrain-seitig ist der native API-Vertrag noch nicht
stabil; eine Zusicherung hier wäre verfrüht. Der ADR fixiert stattdessen
den **Rahmen**, den Smolit-Assistant jedem ABrain-API-Vorschlag
entgegenhalten wird — welche Grenzen gelten, welche Fähigkeiten *nicht*
eingebettet werden, welche Sicherheits-Invarianten bindend bleiben.

Der Status wird auf **Accepted** angehoben, sobald

- ABrain-Seite einen konkreten API-Vorschlag publiziert hat,
- dieser Vorschlag gegen §4 (Decision) und §7 (Safety constraints)
  geprüft wurde und
- der Spike-PR (FA-1) formelle Zustimmung hat.

## 2. Context

Smolit-Assistant ruft ABrain heute als **externen CLI-Prozess** auf:

- `core/src/config.rs`: `DEFAULT_ABRAIN_CMD = "abrain"`,
  konfigurierbar via CLI-Flag `--abrain-cmd` oder Env `ABRAIN_CMD`.
- `core/src/providers/text.rs`: `AbrainCliProvider` als Text-Provider-
  Kind `abrain`, Teil der `TextProviderImpl`-Enum-Familie.
- [`docs/api.md` §3](../api.md): Kommandoform `${ABRAIN_CMD} task run "<input>"`,
  Input auf der Kommandozeile, Ausgabe auf `stdout`, Fehler auf
  `stderr`, Exit-Code bildet Fehlerklassen.
- [`docs/provider_fallback_and_settings_architecture.md` §4.1](../provider_fallback_and_settings_architecture.md):
  ABrain ist **einer von vier** Text-Provider-Kinds (`abrain`,
  `llamafile_local`, `local_http`, `cloud_http`). Default-Chain seit
  PR 26: `["abrain"]`. Die lokale-first-Quick-Action setzt
  `["llamafile_local", "local_http", "abrain"]` — ABrain bleibt als
  CLI-Fallback in jeder Empfehlung enthalten.

Der heutige CLI-Pfad ist robust, aber schmal:

- **Spawn-Kosten.** Jeder Prompt startet einen neuen Prozess.
- **Keine strukturierte Eingabe.** Session, Kontext, Modalitäten
  werden nicht typisiert übertragen.
- **Keine strukturierte Ausgabe.** Emotion-, Action-Intent- und
  Tool-Call-Felder fehlen vollständig — [`docs/api.md` §5](../api.md)
  beschreibt diese seit Jahren als **Ziel-Zustand**, nicht als Ist.
- **Kein Streaming.** Der aktuelle Provider-Kontrakt ist ein
  einmaliger Request → einmaliger Response.

Mit dem ABrain-Native-Weg würden auf einen Schlag die folgenden
sicherheitsrelevanten Flächen bewegt:

- **Auth.** Wenn ABrain künftig über IPC / HTTP erreichbar ist,
  braucht es ein explizites Auth-Modell (lokaler Socket vs. remote
  Endpoint vs. Token-based).
- **Tool execution.** Sobald ABrain *Action-Intents* oder
  *Tool-Calls* zurückmeldet, steht die Frage im Raum, **wer diese
  ausführt** und **wer sie autorisiert**.
- **Streaming responses.** Teil-Antworten ändern das
  Lifecycle-Protokoll (heute: ein `response`-Envelope; streaming
  würde Deltas oder Chunks einführen).
- **Task IDs.** Sessions / Task-Referenzen kreuzen mehrere Turns —
  das braucht einen Lebenszyklus im Core, nicht nur im Provider.
- **Approval / Policy / Audit.** Smolit-Assistant hat seit Policy v0
  (PR 25) eine **Approval-Default=true**-Linie für reale Interaction-
  Actions. Ein Native-ABrain-Pfad darf diese Linie nicht umgehen.
- **Audit.** Der Ring-Buffer (PR 19, PR 32) deckt heute Demo- und
  Interaction-Pfade. Action-Intents aus ABrain müssten **ebenfalls**
  in diesen Pfad fließen — sonst entsteht ein blinder Fleck.
- **Local vs. remote.** Smolit ist lokal-first. Wenn ABrain hinter
  einem cloud-fähigen Endpoint sitzt, gilt dieselbe Opt-in-Linie wie
  für `cloud_http` — nie Default, nie automatisch aktiviert.
- **Failure modes.** Der CLI-Pfad kennt `exit_nonzero`, `timeout`,
  `empty_response`. Ein Native-Pfad bekommt zusätzliche Klassen
  (`auth_failed`, `refused_by_policy`, `action_intent_rejected`,
  `fallback_to_cli`). Sie müssen auf die bestehende Fehler-Enum-
  Familie abbildbar sein.

## 3. Problem statement

Smolit-Assistant braucht einen schriftlich fixierten Rahmen, damit
eine spätere Native-Integration **nicht** still Fähigkeiten einbettet,
die an den etablierten Sicherheits-Gates (Approval, Policy, Audit,
Secret-Store, Provider-Whitelist) vorbeilaufen. Ohne diesen Rahmen
besteht das Risiko, dass eine ABrain-seitig getroffene Designwahl
(z. B. „Tool-Calls kommen mit einem strukturierten JSON und sollen
direkt ausgeführt werden") Smolit-Assistant zu einer Anpassung
zwingt, die Control → Autonomy verschiebt.

## 4. Decision

### D1 — Native ABrain kommt als **zusätzlicher Provider-Kind**, nicht als Ersatz

Ein zukünftiger Native-Pfad wird als neuer Text-Provider-Kind
eingeführt (Arbeitsname: `abrain_native`, siehe §5). Er koexistiert
mit dem bestehenden `abrain`-CLI-Kind. Der CLI-Pfad bleibt:

- weiterhin wählbar in `SMOLIT_TEXT_PROVIDER_CHAIN`,
- weiterhin Default-Chain-Member (`["abrain"]`),
- weiterhin der **Fallback**, falls Native ausfällt oder die
  Runtime-Bibliothek nicht verfügbar ist.

Kein Ersatz, kein Upgrade-Zwang, keine „Superseded"-Markierung für
den CLI-Pfad. `ABRAIN_CMD` und das heutige Verhalten bleiben
unverändert.

### D2 — Native API nutzt **typed request/response**

Das Native-API akzeptiert und produziert ausschließlich strukturierte
Requests und Responses (JSON oder RPC-Äquivalent). Freitext-Parsing
aus stdout wird **nicht** wiederholt. Konkret:

- Request trägt mindestens `input`, optional `session_id`,
  `context` (limitiert / redacted), deklarierte `capabilities`
  (siehe §6).
- Response trägt mindestens `text`, optional `action_intents` und
  `task_id` (siehe §6).
- Kein implizites Emotion-/Voice-Feld, bis ein explizites Smolit-
  Core-Signal dafür existiert (aktuell nicht der Fall).

### D3 — Native API ist **lokal-first**

Der Default-Endpoint ist ein lokaler Unix-Socket oder Loopback-
Endpoint. Cloud-fähige Endpoints (TLS, externe Hosts) sind
**nicht** Teil der ersten Version und bleiben Opt-in auf derselben
Linie wie `cloud_http` (explizite Env + Secrets-Store; nie Default,
nie automatisches Chain-Add).

### D4 — **Jede ABrain-induzierte Action läuft durch Approval/Policy/Audit**

Wenn ABrain strukturierte `action_intents` zurückmeldet, passieren
diese denselben Gate-Pfad wie heute jede Interaction:

1. Core plant die Action (`action_planned`).
2. Core holt Approval, wenn `requires_confirmation=true` (Policy v0
   default seit PR 25).
3. Core prüft Interaction-Backend-Unterstützung.
4. Core führt aus, meldet `action_started` / `action_completed` /
   `action_failed` / `action_cancelled`.
5. Audit-Ring-Buffer (PR 19, PR 32) sieht *jede* Phase.

**Kein direktes Tool-Execution-Pfad** aus dem Native-Provider heraus.
Kein Hidden-Action, kein Out-of-Band-Channel. Action-Intents sind
**Vorschläge**, nicht Befehle.

### D5 — Kein AdminBot-/Shell-Bypass

ABrain darf **nicht** einen Out-of-Band-Pfad zur Shell, zu AdminBot
oder zu Desktop-Automation eröffnen. Jede dieser Fähigkeiten braucht

- einen eigenen ADR,
- einen eigenen Interaction-Kind im Core,
- einen eigenen Policy-Pfad,
- einen eigenen Audit-Eintrag.

AdminBot erscheint in diesem ADR bewusst nur als **Non-goal**. Die
Option „ABrain ruft AdminBot" existiert in diesem ADR strukturell
nicht.

### D6 — Streaming, Tool-Calls, Task-Lifecycle bleiben **Future Work**

Die erste Native-Integration ist **Request → Response**, ein Turn pro
Aufruf, kein partieller Text, keine offenen Streams, keine
langlebigen Task-IDs im Core. Damit bleibt:

- **Streaming:** Future Work — braucht eigenes Lifecycle-Protokoll
  (`response_started` / `response_chunk` / `response_ended` o. ä.)
  und eigenen ADR.
- **Tool-Calls:** Future Work — braucht die vollständige
  Action-Intent-Schema-Diskussion plus Per-Tool-ADRs.
- **Task-IDs / Session-Lifecycle:** Future Work — der Core hält heute
  keinen Session-State und bekommt ihn nicht durch den Native-Provider.

## 5. Candidate provider kind

| Merkmal                     | Wert                                                         |
| --------------------------- | ------------------------------------------------------------ |
| Arbeitsname                 | `abrain_native`                                              |
| Namespace in Whitelist      | Text-Achse (koexistiert mit `abrain`, `llamafile_local`, `local_http`, `cloud_http`). |
| Default-Chain-Member        | **Nein.** `DEFAULT_TEXT_PROVIDER_CHAIN` bleibt `["abrain"]`. |
| Aktivierung                 | Opt-in via Env (`SMOLIT_ABRAIN_NATIVE_ENABLED=1`) + expliziter Eintrag in `SMOLIT_TEXT_PROVIDER_CHAIN`. |
| Cloud-Default               | **Nein.** Lokal-first per D3. Cloud-Endpoint-Spezifikation braucht eigenen Follow-up-ADR analog zu `cloud_http`. |
| Fallback-Position           | Chain-Position ist User-Wahl; empfohlener Start: `["abrain_native", "abrain"]` — Native primär, CLI als Fallback. |

Kein Auto-Aufstieg zum Default und kein „Upgrade-Auto-Migrate" vom
bestehenden `abrain`-Eintrag zu `abrain_native`. Die Shell zeigt
beide Kinds nebeneinander an (Settings-Shell-UX-Cleanup PR 36
unterstützt das additive Kind-Modell bereits).

## 6. Proposed minimal API contract

Folgende Skizze ist **nicht verbindlich**, sondern die Messlatte, an
der ein ABrain-seitiger Gegenvorschlag sich messen lassen muss.

### 6.1 Endpoint + Auth

- Default-Endpoint: lokaler Unix-Socket (`/run/user/<uid>/abrain.sock`)
  oder Loopback (`127.0.0.1:<port>`).
- Auth-Mode:
  - **Lokaler Socket** — Permission-basiert (0600 / Peer-UID-Match),
    kein zusätzliches Token.
  - **Loopback-HTTP** — optionaler Bearer-Token im Secrets-Store
    (parallel zu `cloud_http_secret`, *nicht* über
    `SMOLIT_ABRAIN_NATIVE_TOKEN`-Env). Default: kein Token nötig,
    solange nur Loopback.
- **Cloud-Endpoint:** außerhalb dieses ADR. Wenn er kommt, gelten
  `cloud_http`-Regeln (TLS-Pflicht, Secret nur aus Secret-Store,
  opt-in, kein Chain-Auto-Add).

### 6.2 Request

```json
{
  "input": "string",
  "session_id": "string?",
  "context": {
    "max_history_turns": 0,
    "redacted": true
  },
  "capabilities": {
    "streaming": false,
    "action_intents": false,
    "tool_calls": false
  }
}
```

- `input` (Pflicht) — User-Prompt als Klartext. Keine impliziten
  Markup-Erweiterungen.
- `session_id` (optional) — opaque String vom Core; ABrain darf ihn
  für Caching nutzen, aber der Core haftet nicht für Persistenz.
- `context` (optional) — vom Core kontrolliert; heute `max_history_turns=0`
  und `redacted=true` (keine Passwörter, keine API-Keys, keine
  Dateisystempfade aus User-Input).
- `capabilities` — der **Core** deklariert, was er akzeptiert. Für
  die erste Native-Integration: alle `false`. ABrain darf Felder
  zurückmelden, die hier auf `false` stehen, **nicht** senden.

### 6.3 Response

```json
{
  "status": "ok",
  "text": "string",
  "task_id": "string?",
  "action_intents": []
}
```

- `status` — `ok`, `refused_by_policy`, `auth_failed`,
  `invalid_response`, `unavailable`, `timeout`.
- `text` (Pflicht bei `ok`) — Antworttext, 1:1 in den bestehenden
  `response.payload.text`-Envelope des IPC-Layers.
- `task_id` (optional, reserviert) — wird vom Core heute
  **nicht** ausgewertet; Platzhalter für Future Work. Smolit hält
  keinen Task-Lifecycle durch diesen ADR.
- `action_intents` (optional, default leer) — **Vorschläge**, keine
  Befehle. Jeder Intent trägt `kind` (z. B. `open_application`),
  `target` (symbolisch, nicht ausgeführt) und `rationale`. Der Core
  konvertiert akzeptierte Intents in reguläre `action_planned`-
  Events und läuft durch Approval/Audit (siehe D4).

### 6.4 Keine direkte Ausführung

Der Native-Provider führt **nie** selbst eine Action aus. Er
emittiert nur `response`-Envelopes und (optional) ein
`abrain_action_intents`-Array, das der Core nach Prüfung in den
normalen Action-Lifecycle einschleust.

## 7. Safety constraints

- **Kein hidden tool execution.** Der Native-Provider ruft keine
  externen Kommandos auf; alle Side-Effects laufen über den
  Interaction-Layer mit Approval/Audit.
- **Kein direct shell.** Weder `sh -c` noch `exec`, noch irgendein
  sekundärer Prozess-Spawn aus dem Native-Provider.
- **Kein direct AdminBot.** AdminBot ist keine Provider-Schicht;
  ABrain darf ihn nicht über den Native-Pfad adressieren.
- **Kein Desktop-Action-Bypass.** `open_application`, `focus_window`,
  `type_text`, `send_shortcut` bleiben ausschließlich Aufgaben des
  Interaction-Layers und brauchen ihren eigenen Approval-/Backend-
  Pfad (Policy v0 / PR 23 / ADR-0002 gelten unverändert).
- **Approval required for real interaction actions.** `action_intents`
  aus ABrain werden als `requires_confirmation=true` geplant und
  laufen **immer** durch `approval_requested` → `approval_resolved`,
  unabhängig davon, was ABrain suggeriert.
- **Audit every accepted action intent.** Jeder angenommene Intent
  erzeugt mindestens `ActionPlanned` + `ActionStarted` +
  `ActionCompleted/Failed/Cancelled` im Ring-Buffer (PR 19, PR 32).
  Verworfene Intents erzeugen einen sanitizierten `ActionCancelled`-
  oder `IpcCommandRejected`-Eintrag — keine stille Verwerfung.
- **Redact context.** Der Core schickt **keinen** unredaktierten
  History-/File-/Secret-Kontext an ABrain ohne explizite User-
  Einwilligung. Default heute: `max_history_turns=0`.
- **Cloud endpoint must be explicit opt-in.** Kein Auto-Fallback auf
  cloud-fähige ABrain-Instanzen; TLS-Pflicht; Secret nur aus
  Secrets-Store.
- **No secret display.** Ein Native-Auth-Token wird niemals im UI
  angezeigt (`cloud_http_secret_present`-Modell, PR 10 / PR 36).

## 8. Failure modes

| Klasse                        | Bedeutung                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `unavailable`                 | Kein Native-Endpoint erreichbar. Chain fällt auf das nächste Kind (typisch `abrain`-CLI).         |
| `auth_failed`                 | Bearer-Token abgelehnt / Peer-UID mismatch. Kein Retry, keine stille Downgrade auf unsicheren Pfad. |
| `timeout`                     | Request-Timeout überschritten. Chain-Fallback wie `unavailable`.                                 |
| `invalid_response`            | Antwort nicht gegen das Schema parsebar. Kein Freitext-Fallback.                                 |
| `refused_by_policy`           | Der Core hat eine `action_intent`-Familie verweigert (z. B. Tool-Call, solange `capabilities.tool_calls=false` ist). Sichtbar im Audit. |
| `action_intent_rejected`      | Approval-UI hat den Vorschlag abgelehnt. Audit markiert `ActionCancelled(policy/user_denied)`.   |
| `fallback_to_cli`             | Dokumentarische Klasse — beschreibt, dass die Chain auf den CLI-Pfad ausgewichen ist. Kein Fehler-Envelope auf der UI. |

Die Mapping-Regeln in `sanitize_text_provider_last_error` müssen um
diese Klassen erweitert werden, bevor FA-1 landet — additiv, ohne
Whitelist-Bruch.

## 9. Non-goals

Dieser ADR implementiert **nichts**. Explizit nicht Teil von PR 39:

- **Kein Code** in diesem Repo.
- **Kein neuer Provider-Kind** — `abrain_native` existiert bis auf
  weiteres nur als Arbeitsname.
- **Keine neuen IPC-Events**, keine `StatusPayload`-Erweiterung.
- **Keine Settings-Shell-Änderung.**
- **Keine ABrain-API-Calls** — der ADR ist die Messlatte, kein Client.
- **Keine Streaming-Implementation.**
- **Keine Tool-Execution-Engine.**
- **Keine AdminBot-Integration.**
- **Keine OceanData-Integration.** OceanData bleibt Data-Layer und
  ist kein Teil dieses ADR.
- **Keine smolitux-ui-Änderung.**
- **Keine Cloud-Defaults**; kein Auto-Cloud-Chain-Add.
- **Keine Secret-Änderung** am bestehenden Secrets-Store.
- **Keine Änderung an `ABRAIN_CMD`** oder dem heutigen CLI-Pfad.

## 10. Future work

Folge-PRs, die diesem ADR folgen *können*. Reihenfolge ist nicht
bindend; jeder Schritt bekommt bei Bedarf einen eigenen ADR.

- **FA-1 — `abrain_native`-Provider-Kind (Spike).** Minimaler Client
  hinter einem Feature-Flag (default-off), Chain-Whitelist um das
  Kind erweitert, Wire-Schema aus §6 geprüft. Kein Action-Intent-
  Pfad, kein Streaming. Erste Tests.
- **FA-2 — Typed API client + ABrain-seitiger Contract.** Ein
  Cross-Repo-ADR (Smolit-Assistant ↔ ABrain) fixiert das JSON-Schema
  als verbindlich. Versionierung, Breaking-Change-Regeln, Validator-
  Erwartungen.
- **FA-3 — Action-Intent-Schema + Approval-/Audit-Integration.**
  Strukturiertes `action_intents`-Array wird im Core in planed
  `Action`s verdrahtet. Policy-Entscheidung: welche `kind`s sind
  zulässig (Start: `open_application`, `focus_window`; andere per
  separatem ADR).
- **FA-4 — Streaming.** Eigenes Lifecycle-Protokoll
  (`response_started` / `response_chunk` / `response_ended`), eigene
  Smoke-Abdeckung, eigene UI-Verdrahtung. Nur nach expliziter
  Entscheidung.
- **FA-5 — ABrain-seitiger Contract-Doc.** ABrain-Repo spiegelt den
  Vertrag im eigenen `docs/` als Gegenstück zu §6 dieses ADR.

## Tracking

- Workstream H in [`docs/OPEN_WORK.md`](../OPEN_WORK.md).
- PR 39 in [`ROADMAP.md`](../../ROADMAP.md) (Docs/ADR-only).
- Heutiger CLI-Vertrag: [`docs/api.md §3`](../api.md).
- Ziel-Zustand-Skizze: [`docs/api.md §5`](../api.md).
- Provider-Chain-Mechanik:
  [`docs/provider_fallback_and_settings_architecture.md`](../provider_fallback_and_settings_architecture.md).

## Crosslinks

- **ABrain ≠ OceanData.** ABrain ist Brain / Reasoning /
  Orchestration (dieser ADR). OceanData ist Data-/Kontext-/Memory-
  Schicht und lebt auf einer separaten (zukünftigen) Context-
  Provider-Achse — siehe [ADR-0004 — OceanData Data-Layer
  Integration Path](./ADR-0004-oceandata-data-layer-integration.md).
- **ABrain native path ≠ unrestricted OceanData access.** Auch wenn
  der Native-Pfad später kommt, darf ABrain **keinen** direkten
  OceanData-Zugriff bekommen (kein Registry-Lookup, keine Tool-
  Funktion, die on-demand Kontext holt). OceanData-Ergebnisse
  fließen — wenn überhaupt — nur als *redacted Summary* über den
  Core an ABrain (ADR-0004 D7 / D8).
