# Smolit-Assistant Glossar

> Einheitliches Vokabular für den Smolit-Assistant-Code und die
> begleitende Dokumentation. Wenn zwei Dokumente denselben Begriff
> anders verwenden, gewinnt die Definition hier. Begriffe, die im
> Repo heute gelebt werden, stehen oben; Forschungs-/Zukunftsbegriffe
> (z. B. „Stage C") am Ende.

## Approval

Ein vom Core ausgesprochenes „Bitte bestätigen" vor einer potenziell
relevanten Aktion. Technisch getragen vom
[`ApprovalRequest`](../core/src/approvals/request.rs)-Envelope
(outgoing) und einer UI-Antwort (`approval_approve`,
`approval_deny` oder `approval_response`). Der Core hält pending
Approvals in einer
[`PendingApprovalRegistry`](../core/src/approvals/state.rs), die
Idempotenz garantiert: ein zweiter Approve/Deny auf dieselbe
`approval_id` erzeugt niemals ein zweites `approval_resolved`,
sondern einen `error`-Frame.

**Scope heute:**

- Interaction-Flow: `open_application` läuft seit PR 25 (Policy v0)
  **per Default** durch Approval; `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=0`
  ist ein reiner Test-Hebel.
- Demo-Flow: `request_approval_demo` (PR 17) und
  `plan_demo_action` (PR 18) sind Mock-Pfade — **keine echten
  Systemaktionen**.

Siehe [`docs/security/APPROVAL_UX.md`](./security/APPROVAL_UX.md)
und [`docs/api.md §2.7`](./api.md).

## Audit Trail

Bounded, in-memory Ring-Buffer für sanitisierte Lifecycle-Events
der Approval-Gated Demo-Actions plus ein paar IPC-Grenzfälle. Kein
Produkt-Feature, kein Export, keine Persistenz (ein Core-Restart
leert den Store). Zugriff über das read-only IPC-Kommando
`audit_recent`.

**Nicht dasselbe wie:** `audit_snapshot` (existiert nicht),
User-facing Activity-Log, Audit-Log als Compliance-Artefakt.

Default-Kapazität 100, hartes Maximum 1 000, Env-Override
`SMOLIT_AUDIT_MAX_EVENTS`. Einträge redacted: `summary` ≤ 80
Zeichen, `source`/`result`/`risk` gegen Whitelists geprüft.

Siehe [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md).

## Workflow Overlay

**Seit PR 33 (2026-04-24) entfernt.** Der frühere drei-Knoten-
Kurzprojektions-Spike aus Phase 3.1
(`ui/scripts/workflow_overlay/`,
`ui/scenes/workflow_overlay/workflow_overlay_root.tscn`) ist
nicht mehr Teil der UI. Er rendete Trigger → Action → Result als
knappe Zusammenfassung laufender Action Events, brachte aber
gegenüber dem neuen *Workflow Visibility Overlay v1* (PR 16)
keine zusätzliche Fähigkeit — nur einen konkurrierenden
mentalen Modell-Rahmen. Die Koexistenz war seit PR 20
(Docs Reality Check) als offene Konsolidierungsfrage markiert;
PR 33 hat sie durch Entfernung beantwortet.

**Heute gültig:** siehe nächster Eintrag
„Workflow Visibility Overlay". Wenn in einem älteren Dokument
„Workflow Overlay" steht, ist damit im Zweifel das
Visibility-Overlay gemeint — der alte Spike existiert im
Codebase nicht mehr.

Detail-Review:
[`docs/reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md`](./reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md).

## Workflow Visibility Overlay

Das **einzige** Workflow-UI im Smolit-Assistant (seit PR 33). Ein
read-only Panel aus PR 16 neben dem Avatar. Rendert eine lineare
Kartenliste über neun Schritt-Kategorien (HEARD, THINKING,
RESPONSE, ACTION, STEP, SPEAKING, APPROVAL, COMPLETED, FAILED),
je Eintrag Status + gekürzte ID + Snippet. Standardmäßig
**hidden**, opt-in über `SMOLIT_WORKFLOW_OVERLAY=1` oder
session-lokalen Dev-Toggle. Keine neuen IPC-Events; konsumiert
bestehende Signale.

Siehe [`docs/ui_architecture.md`](./ui_architecture.md) §8.4c.

## Presence

Das **Ist-Verhalten der UI-Hülle** im Sinne der Produkt-Vision
„sichtbare Desktop-Präsenz". Trägt die Modi `docked`,
`expanded`, `action`, `disconnected` und moduliert Avatar,
Utterance-Bubble, Workflow-Overlay und Action-Banner. Implementiert
in `ui/scripts/presence/presence_controller.gd`.

**Nicht dasselbe wie:** eine Always-on-top- oder
Click-through-Funktion — das sind orthogonale Window-Behavior-
Themen (siehe
[`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)).

Siehe [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).

## Expression

Eine **Behavioral-Expression-Layer-v1**-Ausdrucksstufe aus PR 15,
die oberhalb der bestehenden Avatar-State-Maschine als Multiplier-/
Tint-Patch wirkt. Sechs kuratierte Modi: `neutral`, `focused`,
`curious`, `speaking`, `pleased`, `error_soft`. Rein UI-seitig,
kein Protokoll, kein Core-Hook.

Eine Expression ersetzt weder den Avatar-State noch einen
Action-Event. Sie moduliert Puls-Amplitude, Wiggle-Stärke und
Tint — und respektiert dabei den Template-Capability-Contract
(`orb.wiggle = NONE` bleibt auch in `curious` still).

Siehe [`docs/ui_architecture.md`](./ui_architecture.md) §8.4b.

## Action Event

Ein Outgoing-Envelope aus dem **Action Event Model v1**
(`core/src/actions/event.rs`), der einen Schritt einer Aktion
sichtbar macht. Neun Varianten: `action_planned`, `action_started`,
`action_step`, `action_progress` (reserviert, heute nicht
emittiert), `action_verification`, `action_completed`,
`action_failed`, `action_cancelled`.

**Unterscheidung:** ein Action Event ist **kein** Approval (der
Entscheidungspfad), **kein** Audit-Eintrag (die Beobachtung) und
**kein** TTS-Lifecycle-Event (die Audio-Klammer). Die vier Kanäle
leben parallel auf derselben WebSocket-Leitung.

Siehe [`docs/api.md §2.5`](./api.md).

## Interaction Layer

Der Core-Baustein, der Desktop-Aktionen modelliert und ausführt:
`core/src/interaction/`. Kennt die `InteractionKind`-Familie
(`OpenApplication`, `FocusWindow`, `TypeText`, `SendShortcut`,
`Noop`, `Unknown`). Heute real verdrahtet ist nur
**`OpenApplication`** via `CommandBackend`; die anderen drei
Kinds sind `BackendUnsupported` (MVP).

Eingebunden in den Approval-Flow: `requires_confirmation=true`
löst den Approval-Dialog aus, bevor der Executor läuft.
Allow-Lists über `SMOLIT_INTERACTION_ALLOW_*`-Env-Vars.

Siehe [`docs/api.md §2.6`](./api.md) und
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).

## Provider Chain

Eine geordnete Liste von **Provider-Kind-Namen** pro Achse (text /
stt / tts), mit Fallback-Semantik: der Resolver probiert das erste
Kind; scheitert es, rutscht er zum nächsten. Whitelists:

- **Text:** `abrain`, `llamafile_local`, `local_http`, `cloud_http`
- **STT:** `command`
- **TTS:** `command`

Der Compile-Zeit-Default ist konservativ (`["abrain"]` bzw.
`["command"]`). User-Ketten werden im Settings-Store persistiert;
unbekannte Kinds und Duplikate werden validator-seitig abgelehnt.

Siehe
[`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md).

## Stage C

Ein **Forschungs-Gate**, kein Feature. Beschreibt die hypothetische
spätere Avatar-Stufe, in der kuratierte Identitäten durch weitere
Pfade ergänzt werden könnten (statische Asset-Bundles,
deklarative lokale Manifeste, echte User-Imports). Alle vier
Optionen (C1–C4) sind **nicht begonnen**.

**Hard-blocked**, solange Sicherheits-/Vertrauensmodell,
Manifest-Format und Render-Capability-Contract für User-supplied
Inhalte nicht entschieden sind.

Siehe [`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md).

## Smolitux-UI

Die **Web-/React-Komponentenbibliothek** des Smolitux-Ökosystems
([github.com/Modularium/smolitux-ui](https://github.com/Modularium/smolitux-ui)).
Enthält `@smolitux/*`-Pakete (z. B. `@smolitux/core`,
`@smolitux/theme`), ein Docusaurus-Wiki und Storybook. Zielgruppe
sind Webanwendungen im EcoSphere Network.

**Nicht dasselbe wie:**

- **Smolit-Assistant** — ein Godot-nativer Desktop-Client, der
  Smolitux-UI **nicht** als Laufzeit-Komponentenquelle benutzt
  (siehe [ADR-0001](./adr/ADR-0001-smolitux-design-contract.md)).
- **OceanData** — Data-Layer / Datenplattform, **keine** UI-Library
  und **kein** Design-System. OceanData liefert weder Komponenten
  noch Design-Tokens.

Siehe [`docs/adr/ADR-0001-smolitux-design-contract.md`](./adr/ADR-0001-smolitux-design-contract.md).

## OceanData

**Data-Layer / Datenplattform** im Smolitux-Ökosystem. OceanData
liegt **außerhalb** dieses Repos und ist **kein** Teil des
Smolit-Assistant-Stacks — weder heute noch in absehbarer PR-Linie.

**Was OceanData ausdrücklich nicht ist** (konsistent zu ADR-0001,
ADR-0003 und ADR-0004):

- **Keine UI-Library.** OceanData liefert keine Komponenten,
  keine Widgets, keine Scenes.
- **Nicht Smolitux-UI.** Smolitux-UI ist die Web-/React-
  Komponentenbibliothek des Ökosystems; OceanData nicht.
- **Kein Design-System.** OceanData liefert keine Design-Tokens,
  keine Theme-Definitionen, keine Styling-Quelle. Die cross-
  runtime Token-Quelle lebt in smolitux-ui
  ([Smolitux Token Contract](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md),
  PR 35), nicht in OceanData.
- **Kein Text-LLM-Provider.** OceanData wird nie als
  `text_provider`-Kind eingereiht — es lebt auf einer separaten
  (zukünftigen) Context-Provider-Achse.
- **Keine Smolit-Assistant-Runtime-Abhängigkeit heute.** Weder
  Core, UI noch ABrain-Adapter nehmen OceanData in Anspruch;
  keine IPC-Commands, kein Provider-Kind, keine Persistenz.

**Zukünftige Rolle (Proposed in
[ADR-0004](./adr/ADR-0004-oceandata-data-layer-integration.md)):**
OceanData ist als optionaler **Data-/Kontext-Provider** skizziert,
der strukturierte Kontext-/Retrieval-Einträge liefert
(`query_context` / `list_available_contexts` /
`fetch_context_summary`). Erste Integration ist strikt read-only,
lokal-first (Unix-Socket / Loopback), kein Cloud-Default, kein
UI-Komponentenimport, kein Tool-/Desktop-/AdminBot-Bypass. Jede
Action, die aus Kontext abgeleitet würde, läuft durch den
bestehenden Approval-/Policy-/Audit-Gate. ABrain bekommt **keinen**
unrestrictierten OceanData-Zugriff — nur indirekt, als redacted
Summary über den Core.

Der ADR ist Docs-only; es existiert kein Code, keine IPC-
Commands, kein Context-Provider-Trait. Alle Folgearbeiten stehen
unter FA-1 bis FA-6 (OceanData-side contract doc,
Context-provider-SPI-ADR, Spike, Sensitivity-Schema,
Privacy-/Redaction-Layer, ABrain-Context-Handoff-ADR).

Siehe [`docs/adr/ADR-0001-smolitux-design-contract.md`](./adr/ADR-0001-smolitux-design-contract.md)
(Smolitux-UI-Abgrenzung),
[`docs/adr/ADR-0003-abrain-native-integration.md`](./adr/ADR-0003-abrain-native-integration.md)
(ABrain ≠ OceanData, kein Transit-Pfad) und
[`docs/OPEN_WORK.md`](./OPEN_WORK.md) Workstream K.

## Smolitux Design Contract

Die cross-repo Vereinbarung, wie Smolit-Assistant visuelle und
semantische Konsistenz zum Smolitux-Ökosystem herstellt, ohne den
Godot-Client mit React zu koppeln. Der Vertrag besagt:

- Smolit-Assistant importiert **keine** React-Komponenten aus
  smolitux-ui.
- Smolit-Assistant nutzt **kein** WebView, um Smolitux-UI
  einzubetten.
- Smolit-Assistant **kann** Smolitux Design Tokens übernehmen, sobald
  diese in einem serialisierbaren Format exportiert werden.
- Der Rust-Core bleibt frei von UI-/React-Abhängigkeiten.
- smolitux-ui bleibt Single Source of Truth für Web-Komponenten;
  Design Tokens werden langfristig Single Source of Truth für
  cross-runtime visuelle Konsistenz.

Siehe [`docs/adr/ADR-0001-smolitux-design-contract.md`](./adr/ADR-0001-smolitux-design-contract.md)
und den Spiegel-ADR in smolitux-ui.

## Design Tokens

**Serialisierbare Design-Konstanten** (Farben, Typografie,
Spacings, Motion, Elevations, Semantik-Status) als potenzielle
cross-runtime Single Source of Truth. Format ist bewusst offen
(JSON / YAML / TOML wären Kandidaten). In Smolit-Assistant heute
**nicht** implementiert — ein späterer Token-Import-Spike würde
Tokens in Godot-native Theme-Ressourcen mappen (Buttons, Panels,
Badges, Statusanzeigen).

**Abgrenzung:** Design Tokens sind kein React-Artefakt; sie sind
der Vertragspunkt, an dem Godot und React gleichwertig andocken
können.

Die **Datenform** (Kategorien, Naming-Regeln, Value-Types,
Pflicht-Semantic-/State-Tokens, Export-Target-Katalog, Versionierung,
Validator-Erwartungen) ist seit PR 35 im
[Smolitux Token Contract v0](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)
(cross-repo in smolitux-ui, Docs/Schema-only) dokumentiert. Der
Vertrag ist bewusst **vor** jeder Implementation fixiert; Smolit-
Assistant ist heute kein Konsument.

## Smolitux Token Contract

Die cross-repo **Beschreibung der Datenform** zukünftiger Smolitux
Design Tokens. Lebt in smolitux-ui unter
[`docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)
(v0, Draft, Docs/Schema-only). Definiert Token-Kategorien,
Naming-Regeln (lowercase dot-path, runtime-neutral), Value-Types,
Pflicht-Semantic-Tokens (`surface.default`, `text.primary`, …),
State-Tokens (`status.success`, `action.completed`,
`approval.high`, …), einen Katalog möglicher Export-Targets und
Versionierungs-/Validator-Erwartungen.

**Abgrenzung:**

- Der Token Contract ist **keine** Token-Implementation und **kein**
  Export. Er wählt kein Zielformat als verbindlich; er führt weder
  Style Dictionary noch einen Generator ein.
- Smolit-Assistant ist **heute kein Konsument**. Die lokale
  Palette-Datei
  [`ui/scripts/avatar/avatar_palette.gd`](./../ui/scripts/avatar/avatar_palette.gd)
  ist ein lokaler **Andockpunkt**, kein Token-Consumer.
- Der Vertrag adressiert **keine OceanData**-Artefakte; OceanData
  bleibt Data-Layer und ist nicht Quelle des Smolitux-Design-
  Systems.

## Godot-native UI

Das Implementierungs-Modell der Smolit-Assistant-UI: Scenes,
Themes, Autoloads, Godot-eigene Nodes. Kein HTML, kein DOM, keine
JavaScript-Laufzeit in der UI-Schicht. Godot-native UI ist die
Voraussetzung für das Presence-Modell (siehe
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md))
und für den Overlay-Pfad (siehe
[`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)).

**Nicht dasselbe wie:** „Smolitux-UI in Godot" — es gibt keinen
React-Godot-Brücken-Layer.

## Capability Contract

Ein **Capability Contract** ist eine Cross-Repo-Vereinbarung, die
beschreibt, welche benannten Capabilities (z. B. `status_read`,
`service_status`, `action_intent`, `context_summary`) eine
Komponente vorschlagen, entscheiden oder ausführen darf — und welche
nicht. Capability Contracts ersetzen *generisches Tool-Surface* durch
*whitelistete, typisierte Aktionen*; sie sind die Grundlage dafür,
dass z. B. ABrain `action_intents` als Vorschläge senden, aber nicht
direkt ausführen darf.

In Smolit-Assistant wird Capability-Vokabular heute lokal pro
Workstream geführt (Approval-`category`, Provider-Kind,
Interaction-Action). Eine cross-repo Capability-Vokabular-Definition
ist Folgearbeit aus PR 44 (siehe
[`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md` §6](./contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md)).

**Abgrenzung:** Ein Capability Contract bestimmt *was darf*, nicht
*wie ausgeführt wird*. Die Ausführung läuft weiter durch Approval/
Policy/Audit; Capability ist die Eintrittskarte, nicht die Aktion
selbst.

## Audit Correlation ID

Eine **Audit Correlation ID** verkettet einen Aktions-Lifecycle über
Repo-Grenzen hinweg, damit ein Reviewer einen Request von der UI bis
zur ausgeführten Aktion rückverfolgen kann (z. B. UI-Klick → Smolit-
Assistant Audit → ABrain-Adapter → AdminBot-Tool-Call). Smolit-
Assistant Audit (PR 19, PR 32), ABrain-Adapter und AdminBot-IPC
tragen heute je eigene Correlation-Felder; ein **gemeinsamer Spec
existiert noch nicht**.

Die Einführung ist Folgearbeit aus PR 44 (siehe
[`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md` §6](./contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md)).
Solange der gemeinsame Spec fehlt, dürfen Cross-Repo-Aktionen
keinen Audit-Bypass erzeugen — d. h. jede Action, die durch
Smolit-Assistant läuft, gehört in den lokalen Audit-Ring-Buffer
(Lifecycle siehe [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md)).

## Safety Boundary Contract

Ein **Safety Boundary Contract** beschreibt eine vertrauens­
relevante Grenze zwischen zwei Komponenten: wer entscheidet, wer
ausführt, welche Capabilities passieren dürfen, welche nicht, und
wie Approval/Audit/Policy auf der Grenze einrasten. AdminBot
(`docs/integrations/AGENT_SECURITY_BOUNDARY.md` im AdminBot-Repo)
ist ein Beispiel: AdminBot bleibt der Executor mit lokaler
Vertrauensgrenze, Agent / Brain darf nur typisiert anfragen.

In Smolit-Assistant existiert heute **kein** Safety Boundary
Contract zu AdminBot — by design, weil es keinen direkten
Smolit-Assistant ↔ AdminBot-Pfad gibt (siehe
[`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md` §6](./contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md)).
Falls ein solcher Pfad je entstehen sollte, ist ein dedizierter
ADR die Eintrittsbedingung — kein Codepfad davor.

## Cross-runtime UI Consistency

Das Ziel, dass eine Smolitux-Web-App und ein Godot-nativer Client
wie Smolit-Assistant *erkennbar* zum selben Produkt-Ökosystem
gehören — über gemeinsame Design Tokens, gemeinsame Status-
Semantik (z. B. `focused`, `speaking`, `error_soft`) und
gemeinsame Accessibility-/Motion-Konventionen. Der Vertrag lebt in
[ADR-0001](./adr/ADR-0001-smolitux-design-contract.md); die
Implementation ist **nicht** Teil dieses ADR.

---

## Nicht im Glossar enthalten (bewusst)

- **Phase A / B / B+ / B++ / C** (Avatar-Rendering-Stufen) —
  interne Staging-Taxonomie der Avatar-Pipeline; **nicht**
  dasselbe wie die Produkt-Roadmap-Phasen. Siehe
  [`docs/ui_architecture.md §7`](./ui_architecture.md).
- **Phase 0 – 10** (Produkt-Roadmap-Phasen) — siehe
  [`ROADMAP.md`](../ROADMAP.md).
- **workflow_snapshot / audit_snapshot** — existieren **nicht**
  im Protokoll. Das Wire-Format heißt `audit_recent`; eine
  `workflow_snapshot`-Variante ist ausdrücklich nicht Teil des
  Protokolls (siehe [`docs/api.md`](./api.md)).
