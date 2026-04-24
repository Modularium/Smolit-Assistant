# ADR-0004: OceanData Data-Layer Integration Path

- **Status:** Proposed (Docs/ADR-only — keine Code-Implementation).
- **Date:** 2026-04-24
- **Deciders:** Smolit-Assistant Maintainer
- **Scope:** Core (`core/src/`) und ein zukünftiger OceanData-
  Data-/Kontext-Pfad. **Nicht** Teil dieses ADR: UI, Smolitux-UI,
  OceanData-Repo selbst, Tool-Execution, Desktop-Automation.
- **Workstream:** K — OceanData Data-Layer Boundary.

---

## 1. Status

**Proposed.** Die OceanData-seitige API und der Interface-Scope sind
außerhalb dieses Repos noch nicht finalisiert. Der ADR fixiert den
**Rahmen** für eine spätere Integration — welche Rolle OceanData
einnimmt, welche nicht, und welche Sicherheits-Invarianten des
Smolit-Assistant-Core eine Integration respektieren muss.

Der Status wird auf **Accepted** angehoben, sobald

- OceanData-Seite einen konkreten Data-/Kontext-Interface-Vorschlag
  publiziert hat,
- dieser Vorschlag gegen §4 (Decision) und §7 (Safety constraints)
  geprüft wurde, und
- ein Spike-PR (FA-1) formelle Zustimmung hat.

## 2. Context

### 2.1 Wer OceanData ist (Rollenklarheit)

OceanData ist ein **Data-Layer / eine Datenplattform** im Smolitux-
Ökosystem. OceanData liegt **außerhalb** dieses Repos und ist heute
**kein** Teil des Smolit-Assistant-Stacks — weder im Core, noch in
der UI, noch als ABrain-Nachbar.

Die bisherigen Erwähnungen in Smolit-Assistant-Docs waren bewusst
**rein negativ** („OceanData ist *nicht* Smolitux-UI", „OceanData
ist *nicht* Design-System-Quelle", „keine OceanData-Integration").
Diese Abgrenzungen liegen in mehreren Dokumenten fest:

- [`docs/adr/ADR-0001-smolitux-design-contract.md`](./ADR-0001-smolitux-design-contract.md)
  (Smolitux-UI vs. OceanData vs. Smolit-Assistant).
- [`docs/adr/ADR-0003-abrain-native-integration.md`](./ADR-0003-abrain-native-integration.md)
  §9 (keine OceanData-Integration durch den ABrain-Native-Pfad).
- [`docs/GLOSSARY.md` § OceanData](../GLOSSARY.md) und
  [`docs/OPEN_WORK.md` § Workstream K](../OPEN_WORK.md).
- [`README.md` §12](../../README.md).

### 2.2 Wer OceanData **nicht** ist

- **Nicht Smolitux-UI.** Smolitux-UI ist die Web-/React-
  Komponentenbibliothek des Ökosystems. OceanData liefert keine
  Komponenten, keine Widgets, keine Scenes. Gelegentliche Vermischungen
  in Drittquellen sind unpräzise; dieser ADR bestätigt die Trennung.
- **Nicht Design-System-Quelle.** OceanData liefert keine Design-
  Tokens. Der Smolitux Token Contract
  ([smolitux-ui `docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md),
  PR 35) ist die einzige cross-runtime Token-Quelle im Ökosystem.
- **Nicht ABrain.** ABrain ist Brain / Reasoning / Orchestration
  (siehe [ADR-0003](./ADR-0003-abrain-native-integration.md)).
  OceanData ist Daten-/Kontext-/Memory-Schicht. Die beiden haben
  getrennte Rollen und dürfen im Core nicht durch einen gemeinsamen
  Provider-Kind verschränkt werden.
- **Kein UI-Komponentenquell-Repo.** OceanData mag eine eigene
  Frontend-App besitzen, die Smolitux-UI konsumiert — das liegt
  außerhalb dieses ADR.

### 2.3 Warum der ADR jetzt sinnvoll ist

Ohne schriftlich fixierten Rahmen besteht das Risiko, dass eine
spätere OceanData-seitige Designwahl (z. B. „wir bieten einen
HTTP-Endpoint, der bei jedem Request den vollständigen User-Kontext
liefert") Smolit-Assistant zu einer Anpassung zwingt, die
Control → Autonomy verschiebt, die Lokal-first-Linie bricht, oder
an den Gate-Pfaden (Approval, Audit, Secret-Store, Policy)
vorbei läuft.

Der ADR ist die Messlatte, die jeder OceanData-Integrations-Vorschlag
bestehen muss.

## 3. Problem statement

Smolit-Assistant braucht eine schriftliche, konservative Grenze für
eine mögliche OceanData-Anbindung — bevor Code entsteht, bevor ein
Provider-Kind verdrahtet wird, bevor ABrain oder ein anderer
Konsument strukturierten OceanData-Zugriff erwartet.

Die heutige Aussage „OceanData ist nicht Teil dieses Repos" ist
korrekt, aber zu passiv für eine künftige Design-Diskussion. Der ADR
formt aus der negativen Abgrenzung einen aktiven Designrahmen.

## 4. Decision

### D1 — OceanData ist ein **optionaler Data-/Kontext-Provider**, kein Text-LLM-Provider

Eine zukünftige Integration wird **nicht** als Text-Provider-Kind
realisiert. OceanData liefert keinen Freitext-Generator; es liefert
**strukturierte Kontext- oder Retrieval-Einträge** (Notizen,
Dokument-Summaries, Entity-Referenzen, projekt-/benutzerbezogene
Daten). Eine Einreihung in die `text_provider`-Whitelist wäre
semantisch falsch und würde das Provider-Modell verwässern.

Der zukünftige Arbeitsname ist **`oceandata_context`** (siehe §5).
Er lebt auf einer **separaten Context-Provider-Achse**, nicht auf
der `text` / `stt` / `tts`-Achse.

### D2 — **Read-only first**

Die erste Integration ist strikt lesend:

- `query_context(query, scope, max_items, purpose)` → strukturierte
  Liste.
- `list_available_contexts()` → verfügbare Kontext-Buckets.
- `fetch_context_summary(id)` → aggregierte Beschreibung eines
  Kontexts.

**Kein** Schreiben, **kein** Sync, **kein** Mutations-Pfad in der
ersten Version. Ein späterer Schreib-Pfad braucht einen eigenen ADR
und einen eigenen Policy-Gate.

### D3 — Kein Tool-/Desktop-/AdminBot-Bypass über OceanData

Aus einem Kontext-Eintrag entsteht **nie** ein direkter
Interaction-Call. Konkret:

- OceanData liefert niemals „click this button" oder „run this
  command" mit Erwartung der Ausführung.
- Selbst wenn ein Kontext-Eintrag eine Action-Beschreibung enthält,
  läuft sie durch denselben Gate-Pfad wie jede andere Action:
  `action_planned` → `approval_requested` → `approval_resolved` →
  `action_started` → `action_completed/failed/cancelled`, mit
  Audit-Ring-Buffer (PR 19 / PR 32).
- Kein AdminBot-/Shell-/`type_text`-/`send_shortcut`-Pfad wird
  durch OceanData geöffnet.

Diese Linie ist kongruent zu ADR-0003 D5 (ABrain-Native darf AdminBot
nicht umgehen). OceanData hat hier keine Sonderrechte.

### D4 — Kein UI-Komponentenimport

Die Smolit-Assistant-UI importiert **keine** OceanData-Frontend-
Komponenten. Es gibt keinen React↔Godot-Brückenpfad, kein WebView,
keine OceanData-Widgets in den Godot-Scenes. Falls OceanData eine
eigene Web-Oberfläche betreibt (die z. B. Smolitux-UI konsumiert),
ist das außerhalb dieses ADR.

### D5 — Kein Token- oder Design-System-Bezug

OceanData liefert **keine** Design-Tokens und wird auch in Zukunft
nicht zu einer Token-Quelle umdefiniert. Cross-runtime Design-Token-
Diskussionen leben in [ADR-0001](./ADR-0001-smolitux-design-contract.md)
und dem [Smolitux Token Contract](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)
(smolitux-ui-Repo), nicht hier.

### D6 — Lokal-first; kein Cloud-Default

Der Default-Endpoint ist lokal (Unix-Socket oder Loopback). Cloud-
fähige OceanData-Instanzen sind **Opt-in** auf derselben Linie wie
`cloud_http` (Text-Achse) und die cloud-fähige Variante des
abrain_native-Pfads aus ADR-0003:

- explizites Env-Flag plus expliziter Chain-/Provider-Eintrag,
- TLS-Pflicht,
- Secret nur aus Secrets-Store (0600),
- kein Auto-Aktivieren, keine stille Eskalation.

### D7 — Privacy-/Redaction-Gate vor externer Weitergabe

Sobald OceanData-Kontext an **externe** Provider (z. B. eine cloud-
fähige ABrain-Instanz oder `cloud_http`-Text-Provider) weitergeleitet
werden könnte, muss ein Privacy-/Redaction-Layer dazwischen stehen.
Dieser Layer ist **nicht** Teil dieses ADR — er ist bindende
Voraussetzung für jede solche Weitergabe.

Bis dieser Layer existiert, bleibt OceanData-Kontext **im Core**
oder fließt höchstens an **lokale** Provider (`abrain`-CLI,
`llamafile_local`, `local_http`, `oceandata_context` selbst).

### D8 — ABrain bekommt **keinen** unrestrictierten OceanData-Zugriff

Smolit-Assistant stellt OceanData-Daten **nicht** transparent an
ABrain durch. Möglich sind:

- **Direkter Core-Pfad:** Smolit-Assistant fragt OceanData selbst,
  zeigt Ergebnisse in der UI, gated Actions durch Approval.
- **Indirekter Pfad:** Der Core aggregiert OceanData-Ergebnisse zu
  einem *redacted* Context-Summary und reicht diesen Summary an
  ABrain weiter — mit denselben Redaction-Regeln wie für jeden
  externen Provider.

**Kein** Transit-Pfad: ABrain bekommt kein OceanData-Handle, keinen
Registry-Lookup, keine Tool-Funktion, die Kontext on-demand abfragt.
Ein solcher Pfad wäre ein eigener ADR (FA-5).

## 5. Candidate integration model

| Merkmal                           | Wert                                                                                        |
| --------------------------------- | ------------------------------------------------------------------------------------------- |
| Arbeitsname                       | `oceandata_context`                                                                         |
| Provider-Achse                    | Neue **Context-Provider-Achse** — **nicht** text/stt/tts.                                   |
| Default                           | **Nicht aktiv.** Kein Default-Chain-Member; Opt-in per Env + expliziter Konfiguration.      |
| Cloud-Default                     | **Nein** (D6). Cloud-Varianten brauchen eigenen Follow-up-ADR.                              |
| Beziehung zu `text_provider_chain` | Keine Einreihung. Der Kontext-Provider lebt parallel, nicht als Text-Antwort-Erzeuger.       |
| Beziehung zu ABrain               | Indirekt; Weiterleitung nur als redacted Summary (D7, D8).                                  |

Die konkrete Achsen-Form (Trait-Hierarchie, Config-Namespace,
IPC-Command-Familie) ist **Future Work** — FA-2-ADR, nicht dieser.

## 6. Minimal data contract idea

Folgende Skizze ist **nicht verbindlich**, sondern die Messlatte, an
der ein OceanData-seitiger Gegenvorschlag sich messen muss.

### 6.1 Request

```json
{
  "query": "string",
  "context_scope": "string?",
  "max_items": 0,
  "purpose": "string"
}
```

- `query` — natürliche oder strukturierte Suchfrage.
- `context_scope` — optional; erlaubt eine enge Eingrenzung
  (z. B. `"project:alpha"`, `"user:me/notes"`). Default: kein Scope
  → OceanData entscheidet selbst konservativ.
- `max_items` — hartes Limit (`>0` Pflicht bei v1). Unbounded
  Result-Sets sind **nicht** akzeptabel (§7).
- `purpose` — freier, aber stabiler String, der begründet, **warum**
  der Kontext gebraucht wird (z. B. `"ui/summary-panel"`,
  `"abrain/redacted-context"`). Dient dem Audit und der späteren
  Privacy-Policy.

### 6.2 Response

```json
{
  "status": "ok",
  "items": [
    {
      "id": "string",
      "title": "string",
      "summary": "string",
      "source": "string",
      "sensitivity": "public | internal | private | secret?",
      "provenance": "string?"
    }
  ]
}
```

- `status` — `ok`, `unavailable`, `refused_by_policy`, `timeout`,
  `invalid_response`, `auth_failed`.
- `items` — bounded durch `max_items`. Jedes Item trägt `id`,
  `title`, `summary`. **Kein** Raw-Content, **kein** Dump, **keine**
  Secrets (§7).
- `sensitivity` (optional, default `internal`) — orientiert, wie
  aggressiv redaktiert werden muss, bevor der Kontext an externe
  Provider geht (D7).
- `provenance` (optional, empfohlen) — Herkunftsstempel („Notiz vom
  2026-03-02", „Kalendereintrag `ID=x`", „Dokument `path`").

### 6.3 Keine Raw-Dumps, keine Secrets

- Responses enthalten **niemals** Raw-API-Keys, Passwörter, Tokens,
  Private-Key-Material oder andere Secret-Klassen — unabhängig davon,
  ob OceanData sie intern speichert.
- Ein voller Benutzer-Dump ohne `query` + `max_items` ist per Design
  **nicht** zulässig. Wenn die Roadmap später einen „Export-Pfad"
  braucht, entsteht er über einen separaten, approval-gated Command —
  nicht über diesen Vertrag.

## 7. Safety constraints

- **Read-only first.** Keine Mutation, kein Sync, kein Schreibpfad in
  v1. Ein späterer Schreibpfad braucht eigenen ADR und Policy-Gate.
- **Purpose-bound access.** Jeder Request trägt einen `purpose`-
  String. Der Audit-Ring-Buffer (PR 19 / PR 32) erhält eine
  sanitizierte Zeile pro Aufruf.
- **No hidden data exfiltration.** OceanData-Ergebnisse fließen
  **nie** still an externe Provider. Jede Weiterleitung läuft durch
  den Privacy-/Redaction-Layer (D7) — fehlt er, bleibt der Kontext
  lokal.
- **No cloud default.** Default-Endpoint ist lokal. Cloud-Varianten
  Opt-in; dieselbe Linie wie `cloud_http` (PR 10 / PR 11 / PR 36).
- **No secrets in response.** Der Secret-Store (`user://secrets.json`,
  0600, PR 10) bleibt die einzige Quelle für Keys. OceanData darf
  Secrets **nicht** in Responses tragen.
- **No direct action execution.** Out of scope in jeder Variante
  (D3).
- **Bounded results.** `max_items` ist Pflicht; unbounded Result-
  Sets werden mit `refused_by_policy` zurückgewiesen.
- **Provenance required where possible.** Die `provenance`-Angabe
  ist nicht strukturell verpflichtend, aber UX- und Audit-
  technisch erwünscht; eine spätere Policy kann sie zur Pflicht
  erheben.
- **Future redaction/privacy layer required before external
  forwarding** (D7).

## 8. Relationship to ABrain

- **Smolit-Assistant darf OceanData direkt abfragen** — für lokale
  Kontext-Panels, Approval-Begründungen oder UI-Summaries. Dieser
  Weg bleibt im Core, läuft durch Audit, braucht kein ABrain.
- **ABrain darf Context-Summaries bekommen** — *redacted*,
  *bounded*, *purpose-bound*. Smolit-Assistant bleibt der
  Vermittler, nicht OceanData.
- **ABrain bekommt keinen unrestrictierten OceanData-Zugriff**
  (D8). Insbesondere keinen Registry-Lookup, keine Tool-Funktion,
  die Kontext on-demand abfragt, keinen Transit-Pfad, kein
  Credential-Handover.
- **Action-Intents aus ABrain** bleiben weiterhin durch den
  Approval-/Policy-/Audit-Gate aus ADR-0003 D4 geführt —
  unabhängig davon, ob OceanData-Kontext im ABrain-Request
  mitgegeben wurde.

Die Rollen bleiben getrennt: **ABrain ≠ OceanData**, **ABrain
native path ≠ unrestricted OceanData access**.

## 9. Relationship to Smolitux-UI

Zur Laufzeit **keine** Beziehung. OceanData ist kein Smolitux-UI-
Modul und wird es auch nicht werden. OceanData ist **keine**
Design-Token-Quelle. Falls OceanData eine eigene Frontend-Oberfläche
betreibt, die Smolitux-UI als React-Komponentenbibliothek konsumiert,
liegt das außerhalb des Smolit-Assistant-Scopes und außerhalb dieses
ADR.

Verweise:

- [ADR-0001 — Smolitux Design Contract](./ADR-0001-smolitux-design-contract.md)
  (Smolitux-UI als Web-/React-Bibliothek, Smolit-Assistant
  Godot-nativ, OceanData als Non-goal).
- [Smolitux Token Contract](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)
  (cross-runtime Token-Quelle, OceanData explizit ausgeschlossen).

## 10. Non-goals

Dieser ADR implementiert **nichts**. Explizit nicht Teil von PR 40:

- **Kein Code** in diesem Repo.
- **Kein Provider-Kind**, kein neuer Provider-Trait.
- **Keine neuen IPC-Commands**, keine `StatusPayload`-Erweiterung.
- **Kein Daten-Sync.**
- **Keine Persistenz**-Schicht, kein Cache, kein Index.
- **Keine Auth-Implementation** (Auth-Modell ist §6.1 skizziert,
  nicht gebaut).
- **Keine OceanData-Repo-Änderung.** Dieser ADR ist Smolit-Assistant-
  seitig; ein Gegenstück auf OceanData-Seite ist FA-1.
- **Keine smolitux-ui-Änderung.**
- **Keine ABrain-Repo-Änderung.**
- **Kein Cloud-Default**, kein Auto-Chain-Add.
- **Keine UI-Screens** für OceanData in diesem PR.
- **Keine Tool-Execution-Engine** (D3, kongruent zu ADR-0003 D5).
- **Keine AdminBot-Integration.**
- **Keine Design-Token-Änderung** (D5, kongruent zu ADR-0001).

## 11. Future work

Folge-PRs, die diesem ADR folgen *können*. Reihenfolge ist nicht
bindend; jeder Schritt bekommt bei Bedarf einen eigenen ADR.

- **FA-1 — OceanData-side contract doc** *(cross-repo,
  OceanData-Repo)*. OceanData-Seite spiegelt §6 dieses ADR als
  verbindliches Gegenstück: Wire-Schema, Versionierung, Auth-Modell,
  Rate-Limits, Sensitivity-Semantik.
- **FA-2 — Context-provider SPI ADR** *(Smolit-Assistant)*. Legt
  die neue Context-Provider-Achse im Core an (Trait, Config-
  Namespace, Audit-Integration). Keine Implementation, nur
  Interface-Entscheidung.
- **FA-3 — Read-only local endpoint spike** *(Smolit-Assistant)*.
  Erster Client hinter Feature-Flag, Unix-Socket / Loopback,
  Wire-Schema aus §6 geprüft. Kein Action-Pfad, kein Write-Pfad.
- **FA-4 — Sensitivity-/Provenance-Schema** *(Smolit-Assistant
  oder cross-repo)*. Fixiert die Klassifikations-Achse
  (`public|internal|private|secret`) als verbindlich.
- **FA-5 — Privacy/Redaction-Layer vor externer Weitergabe**
  *(Smolit-Assistant)*. Bindet OceanData-Summaries durch einen
  Redaction-Gate, bevor sie an externe Provider gehen
  (cloud-fähige ABrain, `cloud_http`). Ohne diesen Gate bleibt die
  Weiterleitung strukturell verboten (D7).
- **FA-6 — ABrain-context handoff ADR** *(cross-repo)*. Entscheidet
  das genaue Format, in dem Smolit-Assistant ABrain
  Context-Summaries weiterreicht — nach D8 niemals als
  OceanData-Handle, immer als redacted Summary.

## Tracking

- Workstream K in [`docs/OPEN_WORK.md`](../OPEN_WORK.md).
- PR 40 in [`ROADMAP.md`](../../ROADMAP.md) (Docs/ADR-only).
- Rollenkläre im Glossar:
  [`docs/GLOSSARY.md` § OceanData / Smolitux-UI](../GLOSSARY.md).
- Nachbar-ADR: [ADR-0003 — ABrain Native Integration](./ADR-0003-abrain-native-integration.md).
- Nachbar-ADR: [ADR-0001 — Smolitux Design Contract](./ADR-0001-smolitux-design-contract.md).
