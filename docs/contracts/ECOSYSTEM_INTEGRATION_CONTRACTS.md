# Ecosystem Integration Contracts Matrix

- **Status:** Index / Docs-only.
- **Date:** 2026-04-25.
- **Scope:** Smolit-Assistant-seitiger Index aller Cross-Repo-
  Integrationsgrenzen zum Smolitux-/EcoSphere-Network-Ökosystem.
- **Companion:** [`docs/contracts/README.md`](./README.md).

> Leitprinzip: **Index existing contracts, do not duplicate them.**
> Die kanonische Form eines Vertrags lebt dort, wo sie entsteht.
> Diese Matrix verlinkt, fasst zusammen und benennt Lücken — sie
> ersetzt keinen ADR und keinen Vertrag in einem anderen Repo.

---

## 1. Purpose

Smolit-Assistant ist heute mit vier benachbarten Repos
durch dokumentierte Verträge verbunden — einige davon liegen in
Smolit-Assistant selbst (als ADR), andere in den Nachbar-Repos
(als Integration-/Contract-Doku).

Ohne zentralen Index droht:

- **Drift** zwischen ADR und Gegenseite.
- **Doppelverträge**, weil eine PR-Reihe denselben Vertrag in
  zwei Repos parallel formuliert.
- **Verloren­gegangene Lücken** (z. B. Smolit-Assistant ↔ AdminBot
  hat heute *kein* Vertragsdokument auf irgendeiner Seite — und
  das ist eine Designaussage, keine Vergesslichkeit).
- **Begriffsdrift**, z. B. wenn AdminBot-Doku ABrain noch als
  „Agent-NN" führt oder wenn OceanData fälschlich als
  UI-Library / Token-Quelle dargestellt wird.

Diese Matrix ist die einzige Stelle, an der diese Verträge
gemeinsam erfasst und gegen die Smolit-Assistant-Designlinie
gespiegelt werden.

## 2. Current repository roles

### Smolit-Assistant

- Godot-native desktop assistant UI + Rust Core + WebSocket IPC.
- **Source of Truth** für: IPC-Envelope, Provider-Routing
  (Text/STT/TTS), Settings-Store, Secret-Store (`0600`), Approval-
  Engine (Policy v0), Audit-Ring-Buffer, lokale Desktop-
  Interaction-Gates.
- **Nicht** Data-Layer, **nicht** Admin-Daemon, **nicht**
  Design-System.

### ABrain

- Brain / Reasoning / Orchestration.
- Darf typisierte Antworten und optional `action_intents` als
  **Vorschläge** zurückmelden.
- Darf über Smolit-Assistant **keine** Desktop-/Admin-/Shell-
  Aktionen direkt ausführen.
- Native Contract Draft existiert in ABrain
  (`docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`,
  Status: Draft / Proposed).

### Smolit_AdminBot

- Admin-/System-/Ops-Aktionslayer.
- High-risk capability surface (privilegierte lokale Aktionen,
  systemd, polkit).
- **Nicht** Brain, **nicht** UI, **nicht** Datenplattform.
- Jede Integration braucht: Capability Scope, Policy,
  Approval/Audit, Correlation ID.
- Aktuelle AdminBot-Doku referenziert ABrain teilweise weiterhin
  als „Agent-NN" — das ist eine bekannte Naming-Drift, kein
  technischer Konflikt.

### OceanData

- Data-Layer / Kontext-/Datenplattform mit Decide-Access-Semantik
  (`AccessDecision`, `ExportConstraint`, `UsageRecord`).
- **Nicht** UI-Library.
- **Nicht** Smolitux-UI.
- **Nicht** Design-System.
- **Nicht** Token-Quelle.
- **Nicht** Tool-Executor.
- Bestehende Verträge in OceanData (`docs/integrations/*.md`)
  sind **kanonisch für die OceanData-Seite** und müssen nicht
  in andere Repos kopiert werden.

### smolitux-ui

- Web-/React-Komponentenbibliothek; UI-Library /
  Design-System / Token-Quelle des Smolitux-Ökosystems.
- **Nicht** OceanData.
- **Nicht** ABrain.
- **Nicht** AdminBot.
- **Kein** Runtime-Import in Godot — kein React in Godot, keine
  WebView, keine Pakete in Smolit-Assistant.
- Smolitux Token Contract (`docs/design/SMOLITUX_TOKEN_CONTRACT.md`)
  lebt dort und ist die einzige cross-runtime Token-Quelle.

## 3. Contract principles

Jede Cross-Repo-Integration auf der Smolit-Assistant-Achse muss
folgende Linien einhalten:

- **No hidden execution.** Keine Aktion läuft an UI/Audit
  vorbei.
- **No bypass of Smolit-Assistant approval/audit gates.** Policy v0
  + Audit-Ring-Buffer sind bindend, auch für Native-Pfade.
- **Local-first defaults.** Erste Implementation: Unix-Socket /
  Loopback. Cloud/Remote ist immer **explicit opt-in**.
- **Least privilege.** Kein generisches Tool-Surface; nur
  whitelistete Capabilities.
- **Typed request/response.** Keine freien Strings auf der
  Wire-Ebene.
- **Bounded payloads.** Größe und Tiefe sind im Vertrag
  spezifiziert, nicht implizit.
- **No raw secrets.** Tokens, API-Keys, Sessions kreuzen die
  Repo-Grenze nicht im Klartext; Secrets liegen im
  `0600`-Secret-Store des Core.
- **Clear failure modes.** Jeder Vertrag listet `deny`,
  `require_approval`, `unsupported`, `timeout`, `error` als
  benannte Klassen.
- **Action intents are proposals.** Smolit-Assistant entscheidet,
  ob eine vorgeschlagene Aktion läuft.
- **Admin/system actions require policy + audit.** AdminBot-
  artige Aktionen bekommen Capability-Scope, Approval-Hop und
  Audit-Korrelation, nie generischen Shell-Pass-Through.
- **Cross-repo links are references, not runtime dependencies.**
  Doku-Links erzeugen weder Cargo-Deps noch npm-Deps.

## 4. Contract matrix

| # | Pair | Direction | Existing contract / canonical source | Status | Implementation today | Risk | First allowed mode | Required before implementation | Notes |
|---|------|-----------|--------------------------------------|--------|----------------------|------|--------------------|-------------------------------|-------|
| 1 | Smolit-Assistant ↔ ABrain | Assistant → ABrain: text / reasoning request. ABrain → Assistant: text response, optional `action_intents` als Vorschläge. | Smolit-Assistant [`ADR-0003`](../adr/ADR-0003-abrain-native-integration.md); ABrain [`docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md) | draft / proposed | CLI-Adapter via `ABRAIN_CMD` (Default-Chain `["abrain"]`). Kein `abrain_native`-Provider. | medium → high, sobald `action_intents` aktiviert werden | text-only; **keine** `action_intents`-Ausführung in v1 | Cross-Repo-Contract-Review (FA-2); typed Rust-Client; **kein** direktes Tool-/Desktop-Execution; Approval-/Audit-Bridge **bevor** `action_intents` zugelassen werden | PR 39 (ADR-0003) und ABrain Native Contract Draft sind PR 43 verlinkt; Implementation ist FA-Reihe, nicht PR 44 |
| 2 | ABrain ↔ AdminBot | ABrain → AdminBot: typisierte Tool-Calls (`adminbot_system_status`, `adminbot_system_health`, `adminbot_service_status`, …). | ABrain [`docs/integrations/adminbot/*`](https://github.com/Modularium/Agent-NN/tree/main/docs/integrations/adminbot) (`ADMINBOT_AGENT_CONTRACT.md`, `SECURITY_INVARIANTS.md`, `TOOL_SURFACE.md`); Smolit_AdminBot [`docs/integrations/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/integrations) + [`docs/adminbot_v2/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/adminbot_v2) | exists, beidseitig dokumentiert; Naming-Drift Agent-NN ↔ ABrain | außerhalb von Smolit-Assistant verdrahtet | high — privilegierte lokale Aktionen | dry-run / describe-only für jede neu hinzukommende Surface | Capability-Whitelist (fixed `tool_name`); kein generischer Shell-/`exec`-Pass-Through; Audit-Correlation-ID; Naming-Sync später | **PR 44 schreibt diese Verträge nicht um.** Pfad ist außerhalb der Smolit-Assistant-Hoheit; hier nur indexiert |
| 3 | Smolit-Assistant ↔ AdminBot | (heute keiner — by design) | **missing** in beiden Repos | **explicit gap** (Designentscheidung, keine Vergesslichkeit) | none | high — privilegierte lokale Aktionen würden Approval-/Audit-Linie kreuzen | falls je eingeführt: status / read-only only | ADR vor Code; Safety-Boundary-Contract; Capability-Whitelist; Approval-/Audit-Hop; **kein** direkter Shell-Pfad; **kein** Bypass des bestehenden Policy-v0-Gates | Empfohlener Folge-PR: AdminBot Safety Boundary ADR (siehe §12) |
| 4 | Smolit-Assistant ↔ OceanData | Assistant → OceanData: `decide_access` für externen Provider-Export, `query_context` / `list_available_contexts` / `fetch_context_summary` als read-only Kontext-Pfad. | Smolit-Assistant [`ADR-0004`](../adr/ADR-0004-oceandata-data-layer-integration.md); OceanData [`docs/integrations/smolit_assistant.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/smolit_assistant.md) | proposed / docs-only (beidseitig) | none in Smolit-Assistant; OceanData-Seite hat ausführbare Test-Vektoren | data / privacy | read-only lokale Kontext-Summary; lokal-first (Unix-Socket / Loopback); kein Cloud-Default | Context-Provider-SPI-ADR; Sensitivity-/Provenance-Schema; bounded results; Redaction **vor** externer Weitergabe; Honoring von `AccessDecision.effect` (`deny` / `require_approval` / `allow_local_only` / …) | Workstream K Folgearbeiten: FA-1…FA-6 (siehe ADR-0004) |
| 5 | ABrain ↔ OceanData | ABrain → OceanData: `decide_access` vor Tool-/Provider-Use; `compute_jobs` für anonymisierten Export. | OceanData [`docs/integrations/abrain.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/abrain.md) ist **kanonisch**; ABrain referenziert OceanData heute nur als negative Boundary in `SMOLIT_ASSISTANT_NATIVE_API.md` §2 + §"What this contract is not" | asymmetric docs-only — kanonisch nur OceanData-seitig | none **durch Smolit-Assistant**; eine direkte ABrain ↔ OceanData-Linie würde Smolit-Assistant nicht kreuzen | data exfiltration / overbroad context, falls ABrain unrestrictierten OceanData-Zugriff bekäme | redacted summaries only (gespiegelt durch Smolit-Assistant ADR-0004 D8 + ADR-0003 §"OceanData-Boundary") | purpose-bound access; **kein** unrestrictierter Data-Lake-Zugriff; Privacy-/Redaction-Gate; Honoring `AccessDecision` exakt | **PR 44 dupliziert den OceanData-Vertrag in ABrain nicht.** Naming-Drift in der ABrain-Seite (Spiegel fehlt) ist bekannt; eine spätere Spiegel-PR liegt im ABrain-Repo, nicht hier |
| 6 | AdminBot ↔ OceanData | (heute keiner) | **missing** beidseitig | **deferred** | none | high, falls je mutierende Pfade entstehen | none — explizit zurückgestellt | Eigener ADR vor jeder Implementation; AdminBot bleibt Executor mit Policy-Boundary, OceanData bleibt Decide-Access-Quelle ohne Aktionsrecht | by design; kein Plan in nahe Reihe |
| 7 | OceanData ↔ smolitux-ui | OceanData-Frontend (Konsument) ← smolitux-ui (Anbieter, `@smolitux/data-governance`, `@smolitux/oceandata`, `@smolitux/core/theme/layout`). | OceanData [`docs/architecture/SMOLITUX_UI_ADOPTION.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_ADOPTION.md), [`UI_SINGLE_SOURCE_OF_TRUTH.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/UI_SINGLE_SOURCE_OF_TRUTH.md), [`SMOLITUX_UI_CONSUMPTION_STRATEGY.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_CONSUMPTION_STRATEGY.md), [`SMOLITUX_UI_COMPATIBILITY_MATRIX.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_COMPATIBILITY_MATRIX.md); smolitux-ui [`ADR-0001`](https://github.com/Modularium/smolitux-ui/blob/main/docs/adr/ADR-0001-smolitux-design-contract.md) + Token Contract als Anbieter-Kontext | exists auf OceanData-Seite (asymmetrisch — by design) | OceanData-Web-Frontend konsumiert smolitux-ui bereits via local-workspace; keine npm-Hard-Pin | low — UI-Supply-Chain | Web-Frontend-Komponenten only | **keine** Verwechslung der OceanData-Datenrolle mit einer UI-Rolle | smolitux-ui ist Anbieter, OceanData ist Konsument für UI-Frontend-Aspekte. **Kein** Smolit-Assistant-seitiger Eingriff in dieses Pair |
| 8 | Smolit-Assistant ↔ smolitux-ui | Smolit-Assistant ← smolitux-ui (zukünftig: Design-Tokens als serialisierter Snapshot). | Smolit-Assistant [`ADR-0001`](../adr/ADR-0001-smolitux-design-contract.md); smolitux-ui [`ADR-0001`](https://github.com/Modularium/smolitux-ui/blob/main/docs/adr/ADR-0001-smolitux-design-contract.md); smolitux-ui [`docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md) | accepted (ADRs) / draft (Token Contract v0) | Docs/Schema only. Lokale `ui/scripts/avatar/avatar_palette.gd` ist lokaler Andockpunkt, **kein** Token-Consumer | low | tokens / schema only | **kein** React in Godot; **keine** WebView; **keine** `@smolitux/*`-Cargo-/Build-Abhängigkeit; keine Runtime-Kopplung | Design-Vertrag, kein Execution-/Data-Boundary |

## 5. Existing canonical documents

Diese Liste benennt die **kanonischen** Quellen pro Repo. PR 44
verlinkt sie nur — sie schreibt sie nicht um.

### Smolit-Assistant (this repo)

- [`docs/adr/ADR-0001-smolitux-design-contract.md`](../adr/ADR-0001-smolitux-design-contract.md) —
  Smolitux Design Contract (Mirror auf smolitux-ui-Seite).
- [`docs/adr/ADR-0002-accessibility-rpc-readonly.md`](../adr/ADR-0002-accessibility-rpc-readonly.md) —
  Accessibility RPC Read-only.
- [`docs/adr/ADR-0003-abrain-native-integration.md`](../adr/ADR-0003-abrain-native-integration.md) —
  ABrain Native Integration Path.
- [`docs/adr/ADR-0004-oceandata-data-layer-integration.md`](../adr/ADR-0004-oceandata-data-layer-integration.md) —
  OceanData Data-Layer Integration Path.
- [`docs/security/APPROVAL_UX.md`](../security/APPROVAL_UX.md) —
  Approval-UX und Policy-v0-Verdrahtung.
- [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md) —
  In-memory Audit-Ring-Buffer, Lifecycle, Sanitization.
- [`docs/api.md`](../api.md) — IPC-Wire-Format.
- [`docs/provider_fallback_and_settings_architecture.md`](../provider_fallback_and_settings_architecture.md) —
  Text/STT/TTS-Provider-Resolver inkl. ABrain-CLI-Pfad.

### ABrain

- [`docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md)
  — Cross-Repo-Vertragsentwurf für `abrain_native`.
- [`docs/integrations/adminbot/`](https://github.com/Modularium/Agent-NN/tree/main/docs/integrations/adminbot) —
  ABrain ↔ AdminBot Tool-Surface, Security-Invariants,
  Review-Checklist.

### Smolit_AdminBot

- [`docs/adminbot_v2/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/adminbot_v2)
  (`ARCHITECTURE.md`, `DECISIONS.md`, `ACTION_REGISTRY.md`,
  `IPC_SPEC.md`, `SECURITY_MODEL.md`, `AGENTNN_INTEGRATION.md`).
- [`docs/integrations/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/integrations)
  (`AGENT_NN_INTEGRATION.md`, `AGENT_SECURITY_BOUNDARY.md`,
  `ADMINBOT_AGENT_MODEL.md`, `TOOL_MAPPING.md`).
- [`docs/security/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/security)
  — Threat Model, Audit Operations, Hardening Checklist,
  Trust Boundaries, Defense-in-Depth.

### OceanData

- [`docs/integrations/abrain.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/abrain.md) —
  ABrain ↔ OceanData (Decide-Access).
- [`docs/integrations/smolit_assistant.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/smolit_assistant.md) —
  Smolit-Assistant ↔ OceanData (Decide-Access für Provider-Export).
- [`docs/integrations/ocean_protocol.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/ocean_protocol.md) —
  Ocean-Protocol-Adapter-Vertrag.
- [`docs/architecture/SMOLITUX_UI_ADOPTION.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_ADOPTION.md),
  [`UI_SINGLE_SOURCE_OF_TRUTH.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/UI_SINGLE_SOURCE_OF_TRUTH.md),
  [`SMOLITUX_UI_CONSUMPTION_STRATEGY.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_CONSUMPTION_STRATEGY.md) —
  OceanData als Konsument von smolitux-ui.

### smolitux-ui

- [`docs/adr/ADR-0001-smolitux-design-contract.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/adr/ADR-0001-smolitux-design-contract.md) —
  Smolitux Design Contract (Mirror zu Smolit-Assistant ADR-0001).
- [`docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md) —
  Datenform der Smolitux Design Tokens (Draft, Docs/Schema only).

## 6. Explicit gaps

- **Smolit-Assistant ↔ AdminBot — missing by design.** Es gibt heute
  keinen direkten Pfad und kein Vertragsdokument. Eine eventuelle
  Einführung braucht einen eigenen ADR (Safety Boundary Contract)
  vor jedem Codepfad.
- **AdminBot ↔ OceanData — missing / deferred.** AdminBot ist
  Executor mit Policy-Boundary, OceanData ist Decide-Access-Quelle
  ohne Aktionsrecht; eine direkte Kopplung wäre Architektur-
  Entscheidung, kein Implementation-Detail.
- **ABrain ↔ OceanData — asymmetrisch.** Der positive Vertrag lebt
  nur in OceanData (`docs/integrations/abrain.md`). ABrain
  spiegelt heute nur die negative Boundary. PR 44 erzeugt **keinen**
  zweiten Vertrag in ABrain — eine Spiegel-PR auf der ABrain-Seite
  ist die richtige Stelle dafür.
- **AdminBot Naming-Drift.** Smolit_AdminBot-Doku führt ABrain
  weiterhin als „Agent-NN". ABrain-Repo wurde umbenannt; die
  AdminBot-Seite zieht noch nicht mit. Ein Naming-Sync-PR liegt
  im AdminBot-Repo, nicht hier.
- **Kein gemeinsamer Audit Correlation ID Spec.** Smolit-Assistant
  Audit (`docs/security/AUDIT_TRAIL.md`), ABrain-Adapter und
  AdminBot-IPC tragen je eigene Correlation-Felder; ein
  cross-repo Vertrag dafür fehlt.
- **Kein gemeinsames Capability Vocabulary.** AdminBot kennt
  `adminbot_system_status` etc.; ABrain kennt `action_intents`;
  Smolit-Assistant kennt Approval-`category`. Eine cross-repo
  Capability-Vokabular-Definition existiert noch nicht.

## 7. Capability boundaries

Capability-Boundary pro Rolle. Diese Tabelle beschreibt, was eine
Komponente darf — nicht, was sie kann.

| Repo | Darf vorschlagen | Darf entscheiden | Darf ausführen | Darf privilegieren |
|------|------------------|------------------|----------------|--------------------|
| Smolit-Assistant Core | nichts (es ist die Entscheidungsstelle) | Approval, Routing, Provider-Wahl, lokale Desktop-Actions | lokale Actions hinter Policy v0 + Audit | nein — nutzt nur User-Privilegien |
| Smolit-Assistant UI | Approval-Antworten anzeigen / sammeln | nichts (UI ist passiv ggü. Core) | nichts (UI hängt am Core via WebSocket) | nein |
| ABrain | `action_intents` als **Vorschläge** | Reasoning, Plan, Provider-Wahl **innerhalb seines Repos** | nichts auf der Smolit-Assistant-Seite | nein |
| AdminBot | nichts | Policy auf eingehende Tool-Calls | nur whitelisted Tools, mit polkit-/systemd-Aktionsbindung | ja, **aber action-bezogen** — Daemon nicht prozessweit |
| OceanData | `AccessDecision` / `ExportConstraint` | Decide-Access, Compute-Routing, Privacy-Transform | nichts auf Smolit-Assistant- oder AdminBot-Seite | nein |
| smolitux-ui | nichts (statische Komponentenquelle) | nichts | nichts | nein |

**Konsequenzen:**

- ABrain darf nie direkt eine AdminBot-Tool-Call-Kette starten,
  ohne dass die Anfrage von einer entscheidenden Stelle (Smolit-
  Assistant Core oder eine separat zugelassene Adapter-Linie)
  durchgereicht wurde.
- OceanData darf nie eine Aktion auslösen — sie liefert nur
  Entscheidungen.
- smolitux-ui ist nie Laufzeit-Konsument auf der Smolit-Assistant-
  Seite.

## 8. Approval / Policy / Audit expectations

Smolit-Assistant ist heute der **einzige Audit- und Approval-Sink**
auf seiner Achse. Cross-Repo-Verträge müssen das berücksichtigen:

- **Approval-Default = true** für reale Interaction-Actions
  (Policy v0, PR 25). Auch ein nativer ABrain-Pfad mit
  `action_intents` darf diese Linie nicht umgehen.
- **Audit-Lifecycle-Events** (PR 19, PR 32): jede ABrain-induzierte
  Action gehört in denselben Lifecycle (`IpcCommandReceived` →
  `ActionPlanned` → `ApprovalRequested` → `ApprovalResolved` →
  `ActionStarted` → `ActionCompleted` / `ActionCancelled` /
  `ActionFailed`).
- **Audit-Sanitization**: keine Command-Templates, keine
  Env-Namen, keine Secrets in Audit-Summaries (heute durchgesetzt
  durch Audit-Schreibpfad).
- **AdminBot-Style Aktionen**: jede Tool-Aufrufkette über AdminBot
  trägt eine Correlation-ID, die im Smolit-Assistant-Audit
  angekommen wäre, **wenn** sie über Smolit-Assistant läuft. Da
  heute kein Smolit-Assistant ↔ AdminBot Pfad existiert (siehe §6),
  ist das eine Anforderung an einen zukünftigen Vertrag, nicht ein
  aktueller Test.
- **OceanData-Decide-Access**: Smolit-Assistant routet **strikt**
  auf `AccessDecision.effect` (`deny` / `require_approval` /
  `allow_local_only` / `allow_with_transformation` / `c2d_only` /
  `allow`) — kein Retry mit anderem `purpose` oder `consent_id`,
  kein Fallback auf einen anderen Provider mit demselben Payload.

## 9. Data / Privacy expectations

- **Local-first als Default.** Erste Implementation jeder OceanData-
  oder ABrain-Native-Integration: Unix-Socket / Loopback. Cloud /
  Remote ist explizit opt-in — sichtbar in der Settings-Shell als
  Safety-Note, nie versteckt.
- **No raw context out without OceanData approval.** Wenn OceanData
  einen Decide-Access mit `export = no_export` /
  `anonymize_before_export` zurückgibt, darf der Core die rohen
  Daten **nicht** an externe Provider weitergeben.
- **Bounded payloads.** Kontext-/Reasoning-Antworten haben
  vertraglich gesetzte Maxima (Tiefe, Größe, Token-Zahlen). Werte
  werden im jeweiligen Vertrag fixiert, nicht hier.
- **Redaction before external forwarding.** Wenn ein externer
  Provider involviert ist und OceanData `anonymize_before_export`
  fordert, geht der Pfad durch den Privacy-/Redaction-Layer
  (FA-5 in ADR-0004) — nicht über einen direkten Provider-Aufruf.
- **No raw secrets across repo boundaries.** API-Keys / Tokens
  bleiben im `0600`-Secret-Store von Smolit-Assistant; ABrain /
  OceanData / AdminBot bekommen sie nicht über Wire-Felder.
- **Audit trail records the "why".** Jede Decide-Access-Antwort
  erzeugt server-seitig in OceanData einen `UsageRecord` und
  einen `access_decision_made`-Event; Smolit-Assistant darf den
  Trail nicht unterdrücken oder mutieren.

## 10. Transport / Auth expectations

- **Smolit-Assistant ↔ ABrain (CLI heute):** Prozess-Spawn via
  `ABRAIN_CMD`; stdin/stdout. Kein Auth-Modell nötig — beide
  Prozesse teilen User-Identität.
- **Smolit-Assistant ↔ ABrain (Native, future):** Unix-Socket
  oder Loopback-HTTP; Auth lokal-Peer (z. B. `SO_PEERCRED` oder
  Loopback-only Bind). Kein Token im Wire-Format heute.
- **Smolit-Assistant ↔ OceanData (future):** Unix-Socket oder
  Loopback. Kein Cloud-Default. Auth-Modell ist
  Smolit-Assistant-seitig in ADR-0004 FA-Reihe noch zu fixieren.
- **ABrain ↔ AdminBot:** Unix-Socket `/run/adminbot/adminbot.sock`,
  Length-prefixed JSON, Peer-Identität via `SO_PEERCRED` (siehe
  AdminBot-Doku). Kein Smolit-Assistant-Eingriff.
- **OceanData server (existing):** HTTP-only, lokal-first
  (Loopback). Auth-Modell ist OceanData-PR-Reihe; PR10 nutzt
  Netzwerk-Level-Controls statt Token-Auth. Smolit-Assistant
  übernimmt diesen Stand, ohne ihn zu duplizieren.
- **smolitux-ui:** kein Transport (statische
  Komponentenbibliothek). Token Contract hat keinen Auth-Aspekt.

## 11. Non-goals

PR 44 fügt **keine** der folgenden Dinge hinzu:

- Kein Code.
- Keine neuen APIs.
- Keine neuen Provider-Kinds.
- Keine IPC-Erweiterung.
- Keine AdminBot-Aufrufe.
- Keine OceanData-Aufrufe.
- Keine ABrain-Native-Aufrufe.
- Keine Token-Implementation und kein Token-Generator.
- Keine UI-Änderung.
- Keine Edits in ABrain, Smolit_AdminBot, OceanData oder
  smolitux-ui.
- Keine Status-Aussagen über andere Repos jenseits dessen, was
  dort kanonisch dokumentiert ist.

## 12. Future work

Folge-PRs in **diesem** Repo (Reihenfolge nicht bindend):

- **Smolit-Assistant ↔ AdminBot Safety Boundary ADR.** Schließt
  die explizite Lücke aus §6 mit einem Designrahmen, bevor je
  ein Codepfad entsteht.
- **Audit Correlation ID Spec.** Cross-Repo-Korrelation zwischen
  Smolit-Assistant Audit, ABrain-Adapter und AdminBot-Aktionen.
  Idealerweise auf der ADR-Ebene, weil sie mehrere Verträge
  gleichzeitig formt.
- **Capability Vocabulary.** Gemeinsames Vokabular für
  Capability-Klassen (`status_read`, `service_status`,
  `action_intent`, `context_summary`, …), das die Verträge in §4
  konsumieren.
- **ABrain ↔ OceanData Handoff Review.** Kein neuer Vertrag —
  Review der bestehenden OceanData-seitigen Verträge und der
  Smolit-Assistant-Linie aus ADR-0003 / ADR-0004 auf
  Konsistenz.

Folge-PRs in **anderen** Repos sind explizit out-of-scope für
PR 44; sie liegen im jeweiligen Repo-Owner.

## 13. Verification notes

PR 44 ist Docs-only. Verifikation deshalb:

- `cargo test --manifest-path core/Cargo.toml --locked` bleibt
  grün (keine Code-Änderung).
- `scripts/run_overlay_verification.sh settings-shell-smoke`
  bleibt grün (keine UI-Änderung).
- `rg ECOSYSTEM_INTEGRATION_CONTRACTS docs README.md ROADMAP.md`
  zeigt nur erwartete Verlinkungen.
- `rg "OceanData" docs README.md ROADMAP.md` darf OceanData
  nirgends als UI-Library, Design-System oder Token-Quelle
  beschreiben — alle Treffer sind Abgrenzung oder Data-Layer-
  Kontext.
- `rg "Smolitux-UI" docs README.md ROADMAP.md` darf
  smolitux-ui nirgends als Data-Layer beschreiben.
- `git diff --name-only` zeigt nur Dateien unter
  `Smolit-Assistant/`. Keine Änderungen an ABrain,
  Smolit_AdminBot, OceanData oder smolitux-ui.
