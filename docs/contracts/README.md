# Contracts

Smolit-Assistant-seitiger Index für Cross-Repo-Verträge mit
benachbarten Repositories des Smolitux-/EcoSphere-Network-Ökosystems.

## 1. Purpose

Dieses Verzeichnis ist der **Index- und Kontrollpunkt** für
Integrations­grenzen zwischen Smolit-Assistant und seinen
Nachbar-Repos:

- [ABrain](https://github.com/Modularium/Agent-NN) — Brain /
  Reasoning / Orchestration.
- [Smolit_AdminBot](https://github.com/Modularium/Smolit_AdminBot) —
  Admin-/System-/Ops-Aktionslayer.
- [OceanData](https://github.com/EcoSphereNetwork/OceanData) —
  Data-Layer / Datenplattform.
- [smolitux-ui](https://github.com/Modularium/smolitux-ui) —
  Web-/React-Komponentenbibliothek + Smolitux Token Contract.

Die zentrale Matrix
[`ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./ECOSYSTEM_INTEGRATION_CONTRACTS.md)
listet jedes relevante Repo-Paar, verweist auf den **kanonischen
Vertrag** (egal in welchem Repo er lebt) und benennt explizite
Lücken.

Leitprinzip: **Index existing contracts, do not duplicate them.**

## 2. Scope

In diesem Verzeichnis lebt:

- Der Smolit-Assistant-seitige **Index** der Cross-Repo-
  Vertragsdokumente.
- **Spiegel-Dokumente** nur dann, wenn Smolit-Assistant direkt
  betroffen ist und der Spiegel die ADR-Linie ergänzt, ohne den
  kanonischen Vertrag im anderen Repo zu duplizieren.

In diesem Verzeichnis lebt **nicht**:

- Implementations­details (gehören in die jeweilige
  `docs/`-Architekturdatei oder in den Code).
- Re-Implementationen von Verträgen, die in
  ABrain / Smolit_AdminBot / OceanData / smolitux-ui kanonisch
  vorliegen.
- Roadmap-/Status-Information (lebt in
  [`docs/OPEN_WORK.md`](../OPEN_WORK.md) und
  [`ROADMAP.md`](../../ROADMAP.md)).

## 3. Relationship to ADRs

Dokumente in [`docs/adr/`](../adr/) **entscheiden**; Dokumente in
diesem Verzeichnis **indexieren und spiegeln**. Konkret:

- ADRs treffen die Entscheidung pro Workstream
  (z. B. ADR-0003 ABrain Native Integration Path,
  [`ADR-0005`](../adr/ADR-0005-adminbot-safety-boundary.md)
  AdminBot Safety Boundary).
- `docs/contracts/` referenziert diese ADRs zusammen mit dem
  Spiegel-Dokument der Gegenseite (z. B. ABrain
  `docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`) und benennt
  Future-Work-Verträge (z. B.
  `ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md` als FA-1 aus ADR-0005).
- Wenn ein Konflikt entsteht zwischen einem Eintrag hier und einem
  ADR, **gewinnt der ADR**. Dieses Verzeichnis fasst zusammen,
  ersetzt aber keine ADR-Entscheidung.

## 4. Relationship to external repositories

Verträge können kanonisch in einem **anderen Repo** liegen. Beispiele:

| Vertrag | Kanonische Quelle |
| ------- | ----------------- |
| ABrain Native API | [ABrain `docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md`](https://github.com/Modularium/Agent-NN/blob/main/docs/contracts/SMOLIT_ASSISTANT_NATIVE_API.md) |
| ABrain ↔ AdminBot Tool Surface | [ABrain `docs/integrations/adminbot/`](https://github.com/Modularium/Agent-NN/tree/main/docs/integrations/adminbot) + [Smolit_AdminBot `docs/integrations/`](https://github.com/Modularium/Smolit_AdminBot/tree/main/docs/integrations) |
| OceanData ↔ Smolit-Assistant Decide-Access | [OceanData `docs/integrations/smolit_assistant.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/smolit_assistant.md) |
| OceanData ↔ ABrain Decide-Access | [OceanData `docs/integrations/abrain.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/integrations/abrain.md) |
| OceanData UI-Adoption | [OceanData `docs/architecture/SMOLITUX_UI_ADOPTION.md`](https://github.com/EcoSphereNetwork/OceanData/blob/main/docs/architecture/SMOLITUX_UI_ADOPTION.md) |
| Smolitux Design Contract | [smolitux-ui `docs/adr/ADR-0001-smolitux-design-contract.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/adr/ADR-0001-smolitux-design-contract.md) (Mirror: ADR-0001 hier) |
| Smolitux Token Contract | [smolitux-ui `docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md) |

Diese Cross-Repo-Links sind **Referenzen, keine
Runtime-Abhängigkeiten**. Smolit-Assistant importiert keine Pakete,
keine Schemas, keine Build-Artefakte aus den verlinkten Repos.

## 5. Non-goals

- **Keine** Re-Implementation kanonischer Verträge anderer Repos.
- **Keine** API-Spezifikation (lebt entweder in
  [`docs/api.md`](../api.md) für IPC oder im jeweiligen Repo für
  Cross-Repo-Wire-Shapes).
- **Keine** Code-Generierung, **keine** OpenAPI-Schemata, **keine**
  IPC-Erweiterung durch Doku-Pflege.
- **Keine** Status-Aussagen über andere Repos, die nicht durch ein
  dort kanonisches Dokument belegt sind.
- **Keine** automatische Synchronisation mit anderen Repos.

## 6. Current documents

- [`ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./ECOSYSTEM_INTEGRATION_CONTRACTS.md) —
  zentrale Matrix aller acht Repo-Paare, Status-, Risiko- und
  Lückenliste, Capability-/Approval-/Audit-/Privacy-/Transport-
  Erwartungen, explizite Non-goals.
- [`AUDIT_CORRELATION_ID_SPEC.md`](./AUDIT_CORRELATION_ID_SPEC.md) —
  Draft / Proposed (Docs-only). Format, Lebenszyklus,
  Propagationspunkte und cross-repo Erwartungen einer zukünftigen
  gemeinsamen `correlation_id`. Voraussetzung für
  `correlation_id_required = true` in
  [`ADR-0005`](../adr/ADR-0005-adminbot-safety-boundary.md).
- [`CAPABILITY_VOCABULARY.md`](./CAPABILITY_VOCABULARY.md) —
  Draft / Proposed (Docs-only). Naming-Regeln und initiales
  Vokabular (`interaction.*` / `admin.*` / `data.*` /
  `assistant.*` / `provider.*` / `audit.*`); Mappings auf
  bestehende Smolit-Assistant-Code-Identitäten und auf zukünftige
  AdminBot- und OceanData-Surfaces. Keine Runtime-Registry.
