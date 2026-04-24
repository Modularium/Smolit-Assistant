# ADR-0001: Smolitux Design Contract for Smolit-Assistant

- **Status:** Accepted
- **Date:** 2026-04-24
- **Deciders:** Smolit-Assistant Maintainer
- **Scope:** Cross-Repo — wirkt in diesem Repo (`Smolit-Assistant`)
  und hat ein Spiegel-ADR in [`smolitux-ui`](https://github.com/Modularium/smolitux-ui).

---

## Context

Smolit-Assistant ist ein Godot-nativer Desktop-Assistent mit Rust-
Core und lokaler IPC-Bridge (siehe [ROADMAP.md](../../ROADMAP.md) §1–§2
und [`docs/ui_architecture.md`](../ui_architecture.md) §1–§4). Die UI
ist ein reiner Client des Cores; sie hat bewusst keine eigene
Intelligenz, keine eigene Audio-Pipeline und keine eigene
Desktop-Automation.

Im Smolitux-Ökosystem existiert parallel die Komponentenbibliothek
**smolitux-ui** ([github.com/Modularium/smolitux-ui](https://github.com/Modularium/smolitux-ui)),
eine Web-/React-Bibliothek mit Paketen wie `@smolitux/core`,
`@smolitux/theme`, Docusaurus-Wiki und Storybook. Damit Smolit-
Assistant visuell und semantisch zum restlichen Smolitux-Ökosystem
passt, braucht es einen **expliziten Kopplungsvertrag** — ohne den
Godot-Client in eine React-Laufzeit zu zwingen.

Die naive Lösung („die UI-Library einfach importieren") funktioniert
nicht:

- Godot kann keine React-Komponenten direkt rendern.
- Eine WebView-Einbettung würde die Presence-/Avatar-Strategie, den
  Approval-Pfad und den Overlay-Pfad brechen (siehe
  [`docs/presence_desktop_interaction.md`](../presence_desktop_interaction.md)
  und [`docs/linux_window_overlay_architecture.md`](../linux_window_overlay_architecture.md)).
- Ein React↔Godot-Brücken-Layer würde eine zweite Runtime einführen —
  genau das, was [`docs/ui_architecture.md §4`](../ui_architecture.md)
  ausschließt.

Zusätzlich muss klar abgegrenzt werden, was **nicht** Quelle des
Design-Systems ist: **OceanData** ist ein Data-Layer / eine
Datenplattform im Smolitux-Ökosystem und liefert weder Komponenten
noch Design-Tokens. Eine gelegentliche Vermischung der beiden
Begriffe wird hier ausdrücklich zurückgewiesen.

## Decision

Smolit-Assistant folgt langfristig einem **Smolitux Design Contract**
mit folgenden Festlegungen:

1. **Smolit-Assistant bleibt Godot-nativ.** Die UI-Schicht wird
   weiterhin in Godot (Scenes, Themes, Autoloads) umgesetzt.
2. **Keine React-Komponenten im Client.** Smolit-Assistant importiert
   keine Komponenten aus `@smolitux/*`-Paketen zur Laufzeit.
3. **Kein WebView.** Smolit-Assistant bettet keine Smolitux-UI-Web-
   Oberfläche per WebView ein.
4. **Keine React↔Godot-Brücke.** Es wird kein Runtime-Interop zwischen
   React und Godot aufgebaut.
5. **Design Tokens als Vertragspunkt.** Sobald smolitux-ui Design
   Tokens in einem serialisierbaren Format (z. B. JSON / YAML / TOML)
   exportiert, kann Smolit-Assistant diese übernehmen. Godot mappt
   Tokens auf native Theme-Ressourcen, Styles, Buttons, Panels,
   Badges und Statusanzeigen.
6. **Semantische Kopplung.** Status-Begriffe (`neutral`, `focused`,
   `speaking`, `error_soft`, …), Approval-/Audit-/Workflow-
   Kategorien und Accessibility-/Motion-Konventionen bleiben zwischen
   beiden Repos koordiniert — in dieser Richtung ist smolitux-ui
   führend für Web, Smolit-Assistant spiegelt die Begriffe im
   Godot-Theme.
7. **Rust-Core bleibt UI-frei.** Der Rust-Core (`core/src/`) bekommt
   keine Abhängigkeit auf React, auf `@smolitux/*`-Pakete oder auf
   Token-Assets. Er bleibt zuständig für State, IPC, Provider,
   Approval, Audit, Policy und Sicherheit.
8. **smolitux-ui bleibt Single Source of Truth für Web-Komponenten.**
   Smolit-Assistant dupliziert diese Komponenten nicht und
   reimplementiert sie nicht als React-Bibliothek.
9. **Smolitux Design Tokens werden langfristig Single Source of Truth
   für cross-runtime visuelle Konsistenz.** Die tatsächliche
   Token-Definition, das Export-Format und die Versionierung werden
   auf smolitux-ui-Seite entschieden; Smolit-Assistant ist Konsument.

## Consequences

**Positiv:**

- Die UI-Schicht kann weiter eigenständig in Godot reifen
  (Presence-Modell, Avatar-Pipeline, Workflow-Overlay, Approval-Card,
  Audit-Panel), ohne auf eine noch nicht existierende Token-
  Export-Pipeline zu warten.
- Der Smolitux-UI-Refactor in seinem eigenen Repo wird nicht durch
  Godot-Anforderungen blockiert.
- Der Rust-Core bleibt frei von UI-Abhängigkeiten und damit
  testbar/stabil.

**Neutral:**

- Visuelle Drift zwischen Web und Godot ist kurzfristig akzeptabel,
  solange Tokens nicht existieren. Eine spätere Token-Migration wird
  *additiv* sein, ohne den bestehenden Godot-Theme zu ersetzen.

**Negativ / zu beobachten:**

- Wenn smolitux-ui seine Token-Export-Strategie später ändert, muss
  Smolit-Assistant den Konsumenten-Pfad anpassen.
- Semantische Drift (z. B. ein neuer Status-Begriff nur auf einer
  Seite) braucht leichtgewichtige Koordination — diese ADR ist der
  Ort, an dem der Bedarf dokumentiert wird.

## Non-goals

Dieser ADR beschreibt den Vertrag; er implementiert ihn nicht. Nicht
Teil dieses ADR bzw. des einführenden PRs sind:

- Keine Token-Implementation in Smolit-Assistant.
- Keine Theme-Generatoren.
- Keine neuen Packages in diesem Repo.
- Keine UI-Refactors.
- Keine React↔Godot-Brücke.
- Kein WebView.
- Keine Core-Änderungen.
- **Keine OceanData-Änderungen.** OceanData ist Data-Layer /
  Datenplattform und nicht Quelle des Smolitux-Design-Systems; dieser
  ADR bearbeitet OceanData nicht und benennt sie nicht als UI-Library.

## Future work

Folge-Arbeiten, die diesem ADR folgen *können* (nicht müssen):

- **Token-Import-Spike:** sobald smolitux-ui ein Token-Export-Format
  publiziert, ein kleiner, reversibler Spike in Godot (ein Button,
  eine Farbe, ein Spacing-Wert) als Machbarkeitsnachweis.
- **Semantik-Abgleich:** eine kurze Tabelle, die Smolit-Assistant-
  Begriffe (siehe [`docs/GLOSSARY.md`](../GLOSSARY.md)) auf
  smolitux-ui-Äquivalente mappt (Status, Approval-Kategorien,
  Motion-Konventionen).
- **Accessibility-Baseline:** gemeinsame Mindest-Kontraste und
  Motion-Reduktions-Regeln als separate ADR, wenn smolitux-ui einen
  Vorschlag hat.

Detailliertes Tracking: [`docs/OPEN_WORK.md`](../OPEN_WORK.md)
Workstream J.
