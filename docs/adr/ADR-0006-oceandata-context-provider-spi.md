# ADR-0006: OceanData Context Provider SPI

- **Status:** Proposed (Docs/ADR-only — keine Code-Implementation
  in PR 48).
- **Date:** 2026-04-25.
- **Deciders:** Smolit-Assistant Maintainer.
- **Scope:** Smolit-Assistant Rust-Core und eine **hypothetische**
  zukünftige Context-Provider-Achse, die OceanData oder einen
  lokalen Static-Context-Provider als Quelle hat. **Nicht** Teil
  dieses ADR: OceanData-Repo selbst, ABrain ↔ OceanData (lebt
  außerhalb), AdminBot, smolitux-ui, Text-Provider-Resolver.
- **Workstream:** K (OceanData Data-Layer Boundary) — Folgearbeit
  aus [`ADR-0004 §11 FA-2`](./ADR-0004-oceandata-data-layer-integration.md).
- **Related:**
  [`ADR-0001`](./ADR-0001-smolitux-design-contract.md),
  [`ADR-0003`](./ADR-0003-abrain-native-integration.md),
  [`ADR-0004`](./ADR-0004-oceandata-data-layer-integration.md),
  [`ADR-0005`](./ADR-0005-adminbot-safety-boundary.md);
  [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](../contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md);
  [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md);
  [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md).

> Leitprinzip: **Define context-provider boundaries before
> querying OceanData from Smolit-Assistant.** Dieser ADR ist die
> Eintrittsbedingung für jeden späteren Code, der Kontext-Daten
> aus OceanData (oder einem anderen Context-Provider) zieht — er
> ist kein API-Vertrag mit OceanData, kein Wire-Schema, kein Code.

---

## 1. Status

**Proposed.** Es existiert heute kein Codepfad, der OceanData
adressiert; dieser ADR fixiert die SPI-Grenzen, *bevor* irgendein
solcher Pfad entsteht. Status wird auf **Accepted** angehoben,
sobald

- ein OceanData-seitiges Mirror-Vertragsdokument (siehe
  [`ADR-0004 §11 FA-1`](./ADR-0004-oceandata-data-layer-integration.md))
  publiziert ist,
- Audit-Correlation-ID-Spec (siehe AUDIT_CORRELATION_ID_SPEC) und
  Capability-Vocabulary (siehe CAPABILITY_VOCABULARY) auf der
  *Implementation*-Ebene mindestens FA-1 abgeschlossen haben, und
- ein Spike-PR (FA-1) gegen §4 (Decision) und §10 (Privacy /
  Redaction) geprüft formelle Zustimmung hat.

## 2. Date

2026-04-25.

## 3. Context

### 3.1 Stand der OceanData-Linie heute

[`ADR-0004`](./ADR-0004-oceandata-data-layer-integration.md) hat
OceanData als **Data-/Kontext-Provider** definiert — nicht UI-
Library, nicht Design-System, nicht Token-Quelle, nicht Text-
LLM-Provider. PR 44 Matrix Pair 4 markiert den Pfad als
*proposed / docs-only* mit kanonischer OceanData-Seite in
[`Modularium/EcoSphereNetwork OceanData docs/integrations/smolit_assistant.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/smolit_assistant.md).

Smolit-Assistant integriert OceanData heute **nicht**:

- `KNOWN_TEXT_KINDS` in
  [`core/src/providers/text.rs`](../../core/src/providers/text.rs)
  enthält `abrain`, `llamafile_local`, `local_http`, `cloud_http`
  — **nicht** OceanData. Der Frozen-List-Test
  (`docs/api.md` / `docs/provider_fallback_and_settings_architecture.md`)
  schützt diese Linie aktiv.
- Es gibt keine Context-Provider-Achse im Code.
- Es gibt keine OceanData-IPC-Commands.

### 3.2 Was diese ADR entscheidet

ADR-0004 hat *die Boundary* gezogen (OceanData ist Daten-/Kontext-
Layer, kein LLM, kein Tool-Executor); ADR-0004 §11 FA-2 hat aber
absichtlich die *Achsen-Form* (Trait-Hierarchie, Config-Namespace,
IPC-Command-Familie) offen gelassen. Dieser ADR füllt genau
diese Lücke — auf SPI-Ebene, nicht auf Implementations-Ebene.

### 3.3 Warum nicht in `text_provider_chain` einreihen

OceanData *liefert keinen Text-Antwort-Stream*, sondern Kontext-
Items mit Provenance und Sensitivity. Eine Einreihung als Text-
Provider würde:

- die Default-Chain-Semantik brechen (OceanData hätte keine
  produktive `generate`-Antwort),
- den Frozen-List-Test bewusst aufweichen,
- die ADR-0004-Linie „kein Text-LLM-Provider" semantisch
  invertieren,
- Capability-Vocabulary §5.5 (`provider.text.generate`) und §5.4
  (`data.context.query`) verschmelzen, was sie *nicht* sein sollen.

Der Context-Provider lebt daher auf einer **separaten Achse**
neben Text/STT/TTS und neben dem hypothetischen AdminBot-Adapter
aus ADR-0005.

### 3.4 Cross-Repo-Kontext

- ABrain hat seinen Native Contract Draft, der OceanData
  ausdrücklich nur als negative Boundary erwähnt
  ([ABrain `docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md)).
  ABrain bekommt Kontext nur **bounded und redacted** und nur über
  Smolit-Assistant.
- AdminBot hat keine OceanData-Linie (PR 44 Matrix Pair 6
  *deferred*; ADR-0005 §11 stellt klar: AdminBot darf nicht über
  Smolit-Assistant in OceanData schreiben/mutieren).
- smolitux-ui hat keine Runtime-Rolle. Eine OceanData-eigene
  Web-Frontend-App kann smolitux-ui konsumieren — das berührt
  diesen ADR nicht.

## 4. Decision

1. **OceanData wird in Smolit-Assistant ausschließlich über eine
   eigene Context-Provider-SPI integriert,** wenn überhaupt.
2. **OceanData wird nicht in `text_provider_chain` aufgenommen.**
   `KNOWN_TEXT_KINDS` bleibt unverändert; der Chain-Validator
   lehnt `oceandata_context` als Text-Kind explizit ab.
3. **Erste Integration ist read-only, bounded, lokal-first.**
   - Read-only: keine Mutation, kein Sync, keine Writes.
   - Bounded: harter `max_items`-Cutoff, harter
     `max_summary_chars`-Cutoff.
   - Lokal-first: Unix-Socket / Loopback. Kein Cloud-Default.
4. **Keine Raw-Dumps, keine Secrets, keine vollständigen
   privaten Datenbestände** im Antwort-Pfad. Responses bevorzugen
   Summaries mit `provenance` und `sensitivity`.
5. **Keine direkte Action-Ausführung aus OceanData.** OceanData
   liefert Kontext und Decide-Access-Antworten; die Aktionswahl
   bleibt im Smolit-Assistant Core.
6. **OceanData-Kontext darf ABrain nur bounded/redacted
   erreichen.** Kein Transit-Pfad, der OceanData-Antworten
   ungefiltert an einen externen Text-Provider weitergibt.
7. **Externe Weitergabe** (Cloud-Provider, smolitux-Web-App,
   Remote-Logging) **erfordert einen zukünftigen Privacy-/
   Redaction-Gate** (ADR-0004 D7 / FA-5). Solange dieser nicht
   existiert, ist `allow_external_forwarding = false` der harte
   Default.
8. **`correlation_id` wird übernommen, sobald die
   AUDIT_CORRELATION_ID_SPEC implementiert ist.** Heute ist sie
   weder im Wire-Format noch im `AuditEvent`; dieser ADR
   behauptet kein bestehendes Wire-Feld.

## 5. Candidate SPI model

> Arbeitsmodell, **nicht** Code. Die Detail-Form (Rust-Trait-
> Hierarchie, Async-Vertrag, Iterator vs. Vec, Tokio-Channel-
> Form) bleibt eigene Implementation-Entscheidung.

### 5.1 Achsen-Form

Eine **Context-Provider-Achse** parallel zu Text/STT/TTS und
parallel zum hypothetischen AdminBot-Adapter. Konzeptionell:

```
                       Smolit-Assistant Core
        ┌─────────────────┬─────────────────┬─────────────────────┐
        │ TextProvider    │ STT/TTS         │ ContextProvider     │
        │ (existing)      │ (existing)      │ (this ADR)          │
        ├─────────────────┼─────────────────┼─────────────────────┤
 kinds: │ abrain          │ command         │ local_static_context│
        │ llamafile_local │ whisper_cpp     │ oceandata_context   │
        │ local_http      │ piper           │                     │
        │ cloud_http      │                 │                     │
        └─────────────────┴─────────────────┴─────────────────────┘
                                           │  (separat von der
                                            └─ AdminBot-Achse aus
                                               ADR-0005 §5.1)
```

### 5.2 Kandidaten-Kinds

- `local_static_context` — Provider, der lokale, vorab kuratierte
  Kontext-Items liefert (z. B. ein Test-Set für Spike-PRs);
  nützlich, um den SPI-Vertrag ohne OceanData-Abhängigkeit zu
  verifizieren.
- `oceandata_context` — Provider gegen OceanData
  (`/decide/access`, `query_context`, `list_available_contexts`,
  `fetch_context_summary` aus OceanData-seitigem Vertrag).

### 5.3 Kandidaten-Operationen (v1)

- `list_available_contexts` — read-only.
- `query_context` — read-only mit `max_items`.
- `fetch_context_summary` — read-only Detail-Read pro Item-ID.
- `inspect_context_item_metadata` — read-only Metadaten-Read
  (Sensitivity, Provenance).

### 5.4 Ausgeschlossen (v1)

- **Keine Write-Operationen.** Kein Insert, kein Update, kein
  Delete, kein Tag.
- **Keine Sync-Operationen.** Kein Two-Way-Sync, kein Push aus
  Smolit-Assistant nach OceanData.
- **Keine direkte Vector-DB-Exposition.** Keine `embed`-/
  `nearest_neighbors`-Calls; OceanData-seitige Ranking-Wahl
  ist undurchsichtig vom Smolit-Assistant aus.
- **Keine Streaming-Antworten** in v1 (auch wenn ABrain Native
  Streaming kennen wird — siehe ADR-0003).

### 5.5 Defaults

- **Default-off.** Kein Context-Provider-Aufruf ohne explizites
  Opt-in (Settings-Flag oder Feature-Flag).
- **Keine Default-Chain.** Anders als Text/STT/TTS gibt es keinen
  Standardweg, einen Context-Provider in eine Antwort­kette
  einzuhängen — Aufrufe sind explizit, nicht passiv.
- **Keine Auto-Add-Logik.** OceanData-Endpoints werden niemals
  beim First-Run automatisch eingetragen.

## 6. Context provider object model

### 6.1 ProviderConfig

Konzeptionelle Form (kein TOML-/Cargo-Schema):

```json
{
  "provider_kind": "oceandata_context",
  "enabled": false,
  "endpoint": "unix:///run/user/<uid>/oceandata.sock",
  "transport": "unix|loopback_http",
  "auth_mode": "local_peer|bearer",
  "max_items_default": 5,
  "max_summary_chars": 800,
  "allow_sensitive": false,
  "allow_external_forwarding": false
}
```

- `enabled` ist `false` per Default.
- `endpoint` darf nicht auf eine Remote-URL zeigen, solange
  `transport` ∈ {`unix`, `loopback_http`} ist.
- `auth_mode = bearer` ist erlaubt, aber nur, wenn das Token aus
  dem `0600`-Secret-Store kommt (siehe §11). Keine Klartext-
  Tokens in Settings-Files.
- `max_items_default`, `max_summary_chars` sind harte Cutoffs;
  `max_items` per Request darf den Default nicht überschreiten.
- `allow_sensitive = true` ist nur erlaubt, wenn die zukünftige
  Privacy-Policy es zulässt (FA-Reihe).
- `allow_external_forwarding = true` ist nur erlaubt, wenn der
  Privacy-/Redaction-Gate aus ADR-0004 D7 existiert und der
  Aufrufer explizit als „external safe" markiert ist.

### 6.2 Verhältnis zu ADR-0004 §6

ADR-0004 hat eine **minimale Datenform** als Skizze gegeben
(`query`, `context_scope`, `max_items`, `purpose` →
`status`, `items[id, title, summary, source, sensitivity?,
provenance?]`). Dieser ADR **erweitert** sie für die SPI:

- explizite `contract_version` (semver),
- explizite `request_id` (per-call, lokal),
- optionale `correlation_id` (Pflicht im Aktionskontext, sobald
  AUDIT_CORRELATION_ID_SPEC FA-1 implementiert ist),
- explizites `redaction`-Feld (`local_only` / `external_safe`),
- explizites `include_provenance`-Feld (default `true`),
- strukturierte `provenance` (Object statt String),
- expliziter `error`-Block mit `code` / `message`.

ADR-0004 §6 bleibt **autoritativ** für die OceanData-seitige
Wire-Form; ADR-0006 ist die Smolit-Assistant-seitige SPI-Form
darüber.

## 7. Request / response shape

### 7.1 ContextQueryRequest

```json
{
  "contract_version": "0.1",
  "request_id": "req_…",
  "correlation_id": "optional-future",
  "query": "string",
  "context_scope": "user|project|session|system",
  "purpose": "assistant_context|action_planning|debug",
  "max_items": 5,
  "redaction": "local_only|external_safe",
  "include_provenance": true
}
```

Pflichtfelder: `contract_version`, `request_id`, `query`,
`context_scope`, `purpose`, `max_items`, `redaction`.

`correlation_id` ist *optional in v0.1* — Pflicht, sobald die
Aufrufkette einen User-induzierten Aktionspfad kreuzt und
AUDIT_CORRELATION_ID_SPEC FA-1 implementiert ist.

`max_items` darf `max_items_default` aus der ProviderConfig nicht
überschreiten; höhere Werte werden als `too_many_results` (siehe
§12) abgelehnt.

`redaction = external_safe` ist nur erlaubt, wenn
`allow_external_forwarding = true` und ein Privacy-/Redaction-Gate
existiert (FA-Reihe). Andernfalls: `external_forwarding_denied`.

### 7.2 ContextQueryResponse

```json
{
  "contract_version": "0.1",
  "request_id": "req_…",
  "status": "ok|refused|error",
  "items": [
    {
      "id": "ctx_…",
      "title": "string",
      "summary": "string",
      "source": "string",
      "sensitivity": "public|internal|private|sensitive",
      "provenance": {
        "kind": "document|event|record|derived",
        "uri": "optional-redacted",
        "timestamp": "optional"
      }
    }
  ],
  "error": {
    "code": "optional",
    "message": "optional"
  }
}
```

- `status = ok` → `items` ist befüllt (ggf. leer); `error` ist
  abwesend.
- `status = refused` → `items` ist leer; `error.code` benennt einen
  Failure-Mode aus §12 (z. B. `refused_by_policy`).
- `status = error` → `items` ist leer; `error` enthält einen
  Failure-Mode-Code plus kuratiertes `message` (≤ 140 Zeichen,
  siehe §10 für Privacy-Regeln).
- `items[].id` ist stabil (Re-Query mit `inspect_context_item_metadata`
  liefert konsistente Ergebnisse).
- `items[].sensitivity` darf nie höher sein als
  `allow_sensitive`-Schwelle der ProviderConfig zulässt.
- `items[].provenance.uri` ist *redacted-by-default* — kein
  vollständiger Filesystem-Pfad, kein Token, kein Hostname.

## 8. Capability mapping

Bindet an
[`docs/contracts/CAPABILITY_VOCABULARY.md` §5.4](../contracts/CAPABILITY_VOCABULARY.md):

| `capability_id` | SPI-Operation | Risk-Level | Status |
|-----------------|---------------|------------|--------|
| `data.context.query` | `query_context` | `low` (lokal-read), `medium` (extern-forward) | not implemented |
| `data.context.summary` | `fetch_context_summary` | `low`, `medium` (sensible Items) | not implemented |
| `data.decide.access` | OceanData `/decide/access` (read-side, server-eigen) | `low` (Decision-Read) | not implemented |

`list_available_contexts` und `inspect_context_item_metadata`
fallen unter `data.context.query` (Sub-Operation, gleiche
Risk-Bedingungen).

**Approval-/Audit-Regeln** (kanonisch aus CAPABILITY_VOCABULARY
§5.4 und ADR-0005 §10-Logik):

- Lokal-read mit `purpose = "debug"`: `approval_required = false`,
  `audit_required` nur wenn das Ergebnis in eine Action fließt.
- Lokal-read mit `purpose = "assistant_context"` oder
  `"action_planning"`: `audit_required = true`,
  `approval_required = false` solange `redaction = local_only`
  und `allow_sensitive = false`.
- `redaction = external_safe` oder `allow_sensitive = true`:
  `approval_required = true` (Mutationsabsicht-Äquivalent —
  externer Datenfluss).
- `correlation_id` ist **Pflicht**, sobald das Ergebnis in einen
  Aktionspfad fließt.

## 9. Audit / correlation requirements

Pro `query_context` / `fetch_context_summary`-Aufruf wird, sobald
implementiert, ein Audit-Eintrag mit folgenden Feldern erzeugt:

| Audit-Feld | Bedeutung |
|------------|-----------|
| `provider_kind` | `oceandata_context` / `local_static_context`. |
| `context_scope` | aus Request. |
| `purpose` | aus Request. |
| `max_items` | aus Request. |
| `result_count` | aus Response. |
| `sensitivity_max` | höchstes `sensitivity` über alle Items. |
| `used_for_action` | `true` / `false`; ergibt sich aus dem Caller. |
| `external_forwarding` | `true` / `false`; spiegelt `redaction`. |
| `correlation_id` | aus Request, sofern vorhanden. |

**Niemals erfasst:**

- Rohe `query`-Strings, wenn `sensitivity_max ≥ private` —
  stattdessen kuratiertes Summary oder Hash.
- Vollständige `summary`-Bodies — stattdessen Längen + Kategorien.
- `provenance.uri` in Klartext, wenn redacted-Empfehlung gilt.
- API-Keys, Tokens, Bearer-Strings.
- Vollständige Item-Bodies.

Lifecycle-Verzahnung mit dem bestehenden Audit-Pfad
([`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md))
folgt der ADR-0005-§11-Linie: Context-Reads, die einen
Aktionspfad einleiten, werden in den Action-Lifecycle-Audit
verkettet (`ipc_command_received` → `action_planned` → …).
Reine Debug-/Test-Reads (`purpose = "debug"`,
`used_for_action = false`) erzeugen einen separaten,
sanitisierten Eintrag ohne Approval-Pflicht.

## 10. Privacy / redaction requirements

- **`local_only` ist Default.** `external_safe` muss explizit
  angefragt werden und ist nur erlaubt, wenn der Privacy-/
  Redaction-Gate (ADR-0004 D7 / FA-5) existiert.
- **`allow_sensitive = false` ist Default.** Sensitive Items
  werden serverseitig (OceanData) gefiltert, bevor sie ins
  Smolit-Assistant kommen — und werden in jedem Fall *nicht* in
  externe Provider weitergeleitet.
- **`allow_external_forwarding = false` ist Default.** Eine
  Setzung auf `true` ist eine bewusste UI-Aktion mit Approval-
  Default = true.
- **No hidden exfiltration.** Jeder Pfad, der OceanData-Items an
  einen externen Provider (z. B. `cloud_http`) weiterleitet, geht
  über den Privacy-/Redaction-Gate; ein direkter „bekomme
  OceanData-Item, sende sofort an Cloud-LLM"-Pfad ist verboten.
- **No unrestricted data lake access.** Smolit-Assistant fragt
  immer mit `query` + `max_items` + `purpose`; ein „dump
  alles"-Aufruf ist syntaktisch nicht möglich.
- **No full private dumps.** OceanData-Antwort liefert Summaries,
  nicht Raw-Bodies (ADR-0004 §6.3 spiegelt das).
- **Summaries preferred.** `fetch_context_summary` ist die normale
  Detail-Operation; ein hypothetischer „Raw-Body-Read" wäre eigene
  Capability mit eigenem ADR.
- **Provenance required where possible.** Items ohne `provenance`
  sind erlaubt, aber `provenance_missing` ist ein Audit-Hinweis
  (siehe §12).

## 11. Transport / auth expectations

- **Lokal-first.** Erste Verdrahtung: Unix Domain Socket
  (`unix:///run/user/<uid>/oceandata.sock`-Form, OceanData-seitig
  kanonisch festgelegt) oder Loopback-HTTP (z. B.
  `http://127.0.0.1:<port>/`).
- **Cloud / Remote OceanData ist out-of-scope** für v0.1. Kein
  TLS-Bundle, kein DNS-Resolve, kein Setup-Wizard-Eintrag für
  Remote-URLs.
- **Bearer-Auth ist optional.** Falls je nötig (z. B. wenn
  OceanData FA-Reihe einen lokalen Token einführt), kommt der
  Wert ausschließlich aus dem `0600`-Secret-Store des Core. Keine
  Klartext-Tokens in Settings-Files, keine Tokens in Logs, keine
  Tokens in der UI sichtbar.
- **Endpoint-Defaults zeigen niemals auf Remote.** Default ist
  immer lokal; ein zukünftiger Schalter „erlaube Remote" ist
  eigene UX-Runde mit Approval.
- **Unauthentifizierter Endpoint muss fail-closed sein** für
  `sensitivity ≥ private` und für jede Anfrage mit
  `redaction = external_safe`.
- **Keine Mutual-TLS-Annahme.** Lokal-Peer-Identität (Unix-Socket
  Filesystem-Permissions, OceanData-seitige `actor`-Hint) reicht
  für `local_only` / Lokal-Read.

## 12. Failure modes

| Failure mode | Bedeutung |
|--------------|-----------|
| `unavailable` | OceanData-Endpoint nicht erreichbar. |
| `auth_failed` | Peer-Identity passt nicht; Bearer-Token ungültig; Socket-Permissions falsch. |
| `timeout` | Pflicht-Cutoff aus ProviderConfig gerissen. |
| `invalid_request` | Pflichtfelder fehlen, `contract_version` unbekannt, `max_items > max_items_default`. |
| `invalid_response` | OceanData lieferte unerwartetes Schema oder verletzt `contract_version`. |
| `refused_by_policy` | Smolit-Assistant Policy verweigert (z. B. unbekannter `provider_kind`, deaktiviert). |
| `context_scope_not_allowed` | `context_scope` ist im Capability-Contract nicht erlaubt. |
| `sensitivity_not_allowed` | Item-`sensitivity` überschreitet `allow_sensitive`-Schwelle. |
| `provenance_missing` | Pflicht-`provenance` fehlt für `purpose = "action_planning"`. |
| `too_many_results` | OceanData lieferte mehr als `max_items` Items. |
| `redaction_required` | `redaction = external_safe` angefordert, aber Privacy-/Redaction-Gate fehlt. |
| `correlation_missing` | Pflicht-`correlation_id` fehlt im Aktionskontext. |
| `external_forwarding_denied` | Caller wollte das Ergebnis extern weiterleiten, aber `allow_external_forwarding = false`. |

Ergänzende Failure-Modes pro Provider-Kind sind erlaubt, aber
ergänzend, nicht ersetzend.

## 13. Relationship to ABrain

- **ABrain darf bounded und redacted Kontext über Smolit-
  Assistant erhalten.** Smolit-Assistant ist der Vermittler;
  ABrain bekommt nie einen direkten OceanData-Endpoint-Handle.
- **ABrain bekommt keinen unrestrictierten OceanData-Zugriff.**
  Das ist eine harte Linie aus ADR-0003 (ABrain-Native-Pfad
  schließt direkten OceanData-Hook aus) und ADR-0004 D8.
- **ABrain Native Contract impliziert keinen OceanData-Zugriff.**
  `action_intents` aus ABrain dürfen *Kontext anfordern* (über
  ein `capabilities.context_provider`-Feld in ABrains
  Native-API-Draft), aber Smolit-Assistant entscheidet, ob es
  diese Anforderung über ContextProvider-SPI bedient — und mit
  welcher `redaction`-Stufe.

## 14. Relationship to AdminBot

- **AdminBot darf OceanData nicht über Smolit-Assistant
  ansprechen** — weder lesend noch mutierend (ADR-0005 §11).
- **AdminBot ist keine Datenquelle für OceanData.** Ein
  hypothetischer „AdminBot-Status fließt in OceanData-Kontext"-
  Pfad braucht eigenen ADR und eigenen Capability-Contract; PR 44
  Matrix Pair 6 markiert *deferred*.
- **AdminBot ↔ OceanData direkter Pfad** ist ausdrücklich
  außerhalb dieses ADR. Eintrittsbedingung wäre ein eigener ADR
  mit eigenem Threat Model.

## 15. Relationship to Smolitux-UI

- **Keine Runtime-Beziehung.** smolitux-ui ist UI-Library /
  Design-System / Token-Quelle für Web/React-Anwendungen — kein
  Beteiligter an Context-Provider-SPI.
- **Keine Token-/Design-System-Beziehung.** Eine Approval-Card
  für `data.context.query` mit hoher Sensitivity folgt dem
  Smolitux Design Contract aus ADR-0001 wie jede andere
  Approval-Card; OceanData fügt dem Token-Vertrag nichts hinzu.
- **OceanData-eigene Web-Frontend-App** kann smolitux-ui
  konsumieren — das passiert ausschließlich im OceanData-Repo
  ([OceanData docs/architecture/SMOLITUX_UI_ADOPTION.md](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_ADOPTION.md))
  und ist von dieser SPI getrennt.

## 16. Non-goals

PR 48 (dieser ADR) ist Docs/ADR-only. Ausdrücklich **nicht** Teil:

- Kein Code; kein Trait, kein Crate, kein neues Modul in
  `core/src/`.
- Keine OceanData-Repo-Änderung.
- Kein neues IPC-Command, keine `oceandata_*`-Wire-Erweiterung.
- Kein neuer Provider-Kind-Eintrag in `KNOWN_TEXT_KINDS` (und
  niemals in `text_provider_chain`).
- Keine Context-Provider-Runtime-Registry.
- Keine Auth-Implementation.
- Keine Privacy-/Redaction-Layer-Implementation.
- Keine Vector-DB-Exposition.
- Keine Sync-Operationen.
- Keine Write-Operationen.
- Keine ABrain-Änderungen.
- Keine AdminBot-Änderungen.
- Keine smolitux-ui-Änderungen.
- Keine UI-Änderung (keine Context-Card, kein Settings-Block).
- Keine Cloud-/Remote-OceanData-Variante.

## 17. Future work

Reihenfolge nicht bindend; alle Schritte hinter eigenen PRs.

- **OC-1 — OceanData-side mirror review.** Sicherstellen, dass
  [OceanData `docs/integrations/smolit_assistant.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/smolit_assistant.md)
  zu §6/§7 dieser ADR konsistent ist; ein Update auf der
  OceanData-Seite ist FA-1 aus ADR-0004, lebt **nicht** hier.
- **OC-2 — Privacy / Redaction Layer ADR.** Eintrittsbedingung
  für `redaction = external_safe` und für jede ABrain-Weitergabe
  von OceanData-Kontext. Docs-only.
- **OC-3 — Capability-Vocabulary-Erweiterung** für eine
  Sub-Capability-Stufe (`data.context.query@external_safe`),
  falls die Praxis zeigt, dass eine eigene Approval-Linie nötig
  ist.
- **OC-4 — Spike-PR `local_static_context`** hinter Feature-Flag.
  Erste Code-Berührung; default-off; kein OceanData-Touch — nur
  ein lokales Test-Set, das den SPI-Vertrag verifiziert. Nur
  nach AUDIT_CORRELATION_ID_SPEC FA-1 (`correlation_id` in
  `AuditEvent`) und CAPABILITY_VOCABULARY FA-1.
- **OC-5 — Settings-Shell-Block** für ContextProvider mit
  Summary · Details · Safety-notes-Struktur (analog zu PR 36 D-
  Settings-Shell-UX-Cleanup), default-off, kein Auto-Add.
- **OC-6 — Spike-PR `oceandata_context`** hinter Feature-Flag.
  Erst nach OC-1, OC-2, OC-4, OC-5.
- **OC-7 — ABrain Native Contract `capabilities.context_provider`**
  Mirror-Spec auf der ABrain-Seite. Liegt im ABrain-Repo, **nicht
  hier**.
