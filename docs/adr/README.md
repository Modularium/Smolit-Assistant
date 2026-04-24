# Architecture Decision Records (ADRs)

Dieses Verzeichnis sammelt architektur­relevante Entscheidungen für
Smolit-Assistant. Jeder ADR hat eine laufende Nummer, einen Status
(`Proposed` / `Accepted` / `Superseded`) und ein Datum. ADRs werden
nur ergänzt, nicht rückwirkend umgeschrieben — wenn eine Entscheidung
sich ändert, wird ein neuer ADR angelegt, der den alten als
`Superseded` markiert.

## Geltungsbereich

ADRs in diesem Verzeichnis beschreiben Entscheidungen, die entweder

- das **Verhältnis zwischen Code-Bereichen** (Core / UI / IPC / Adapter)
  oder
- das **Verhältnis zu anderen Repositories im Smolitux-Ökosystem**
  (z. B. `smolitux-ui`)

festlegen. Rein lokale Implementation-Details gehören in die
jeweilige Architekturdatei unter [`docs/`](../), nicht in einen ADR.

## Abgrenzung zu anderen Smolitux-Teilen

- **Smolitux-UI** ist die Web-/React-Komponentenbibliothek des
  Smolitux-Ökosystems ([github.com/Modularium/smolitux-ui](https://github.com/Modularium/smolitux-ui)).
- **OceanData** ist der Data-Layer / eine Datenplattform und **kein**
  Design-System; ADRs in diesem Repo behandeln OceanData nicht.
- **Smolit-Assistant** ist ein Godot-nativer Client mit Rust-Core und
  IPC-Bridge, siehe [ROADMAP.md](../../ROADMAP.md).

## Index

| ADR | Titel | Status | Datum |
| --- | ----- | ------ | ----- |
| [ADR-0001](./ADR-0001-smolitux-design-contract.md) | Smolitux Design Contract for Smolit-Assistant | Accepted | 2026-04-24 |
| [ADR-0002](./ADR-0002-accessibility-rpc-readonly.md) | Accessibility RPC Spike — Read-only AT-SPI | Accepted | 2026-04-24 |
| [ADR-0003](./ADR-0003-abrain-native-integration.md) | ABrain Native Integration Path | Proposed | 2026-04-24 |
| [ADR-0004](./ADR-0004-oceandata-data-layer-integration.md) | OceanData Data-Layer Integration Path | Proposed | 2026-04-24 |
