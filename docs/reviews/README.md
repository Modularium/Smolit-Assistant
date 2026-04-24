# Reviews & Reality Checks

> Dieser Ordner hält **Review-Berichte**, **Reality-Checks** und
> **ehrliche Post-mortems** zu einzelnen PRs oder Phasen. Detail-
> geschichten zu einzelnen PRs leben **hier**, nicht in
> [`ROADMAP.md`](../../ROADMAP.md). Die Roadmap beschreibt den Weg
> nach vorn; dieser Ordner beschreibt, wie die Arbeit tatsächlich
> lief.

## Zweck

- **Entkoppeln von Roadmap und Historie.** ROADMAP.md bleibt in
  zwei Minuten erfassbar. Wer pro PR eine lange Erzählung sucht,
  findet sie hier.
- **Reality Checks sind kein Changelog.** Ein Eintrag hier ist ein
  Review: was war der Plan, was wurde tatsächlich gebaut, wo sind
  die Abweichungen, welche Folgearbeit bleibt offen.
- **Offene Folgearbeit ist dokumentiert**, aber die bindende
  Single-Source für offene Arbeiten bleibt
  [`docs/OPEN_WORK.md`](../OPEN_WORK.md) — nicht dieser Ordner.

## Aktueller Bestand

| Datei | Gegenstand | Kurz |
|-------|-----------|------|
| [`phase-3-avatar-ui_inventory.md`](./phase-3-avatar-ui_inventory.md) | Phase 3 Avatar UI | Inventur des Phase-3-Avatar-UI-Spikes (vor PR 14) |
| [`phase-3-avatar-ui_review.md`](./phase-3-avatar-ui_review.md) | Phase 3 Avatar UI | Review der Phase-3-Arbeit |
| [`PR20_DOCS_REALITY_CHECK.md`](./PR20_DOCS_REALITY_CHECK.md) | PR 20 Docs Reality Check | Ehrlicher Abgleich Ist-Code vs. gesamte Dokumentation; Grundlage für den ROADMAP-Rebase und `OPEN_WORK.md`. |
| [`PR23_FOCUS_WINDOW_DECISION.md`](./PR23_FOCUS_WINDOW_DECISION.md) | PR 23 focus_window Reality Decision | Entscheidung für Option 1 („bleibt, weil bereits realisiert"); Code-Inventur, Machbarkeitsprüfung X11, Doku-Pointer. |
| [`PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./PR25_POLICY_V0_APPROVAL_DEFAULT.md) | PR 25 Policy v0 | Safety-/Docs-/Tests-PR: fixiert die Default-Approval-Baseline für echte Interaction Actions (`open_application` approval-gated, `focus_window` doppeltes Opt-in, `type_text`/`send_shortcut` weiterhin unsupported). Ehrliche Audit-Grenze dokumentiert. |
| [`PR28_PRESENCE_DESKTOP_INTERACTION_TRIM.md`](./PR28_PRESENCE_DESKTOP_INTERACTION_TRIM.md) | PR 28 Presence & Desktop Interaction Trim | Docs-only: `presence_desktop_interaction.md` auf Ist-Zustand gekürzt (1096 → 491 Zeilen, 12-Abschnitt-Struktur). Zielbild komplett in Future Work / Non-goals isoliert. Altanker-Mapping für eingehende Verweise. |
| [`PR31_ROADMAP_CHECKPOINT.md`](./PR31_ROADMAP_CHECKPOINT.md) | PR 31 Roadmap Checkpoint | Docs-only Checkpoint nach der PR-21–30-Stabilisierungsserie: Summary der zehn gelandeten PRs, Current Stable Baseline, Workstream-Status A–K, Closed/Open Items, Drift-Watchlist und PR-32–40-Sequenzvorschlag. Basis für die ROADMAP-/OPEN_WORK-Synchronisation und den neuen Workstream K (OceanData-Boundary, ADR-Vorlauf). |
| [`PR32_AUDIT_INTERACTION_LIFECYCLE.md`](./PR32_AUDIT_INTERACTION_LIFECYCLE.md) | PR 32 Audit Coverage für reale Interaction-Actions | Schließt die in PR 25 dokumentierte Audit-Lücke. Generisch über `dispatch_interaction` + `await_and_continue`: `interaction_open_application` und `interaction_focus_window` laufen durch denselben Audit-Lifecycle wie der Demo-Pfad. Kein Persistenz-Pfad, keine neuen IPC-Commands, aktive Leak-Checks (Template / Env / Secret) in den Tests. |

## Konventionen für neue Einträge

- **Dateiname:** `PR<N>_<SHORT_SLUG>.md` oder
  `phase-<N>_<SLUG>.md` — kurze, maschinenlesbare Slugs.
- **Header-Block:** Kurzer Scope-Absatz, Stand-Datum, Pointer auf
  den PR-Commit-Bereich (SHA-Range), falls sinnvoll.
- **Ehrlichkeit vor Schönheit.** Reality-Checks dürfen unbequem
  sein — das ist ihre Arbeit. Wo etwas schiefgelaufen ist, steht
  es hier.
- **Keine Feature-Arbeit.** Reviews ändern keine Core-/UI-Logik.
- **Pointer statt Copy-Paste.** Wer eine technische Aussage aus
  einer Architektur-Datei (z. B. `docs/ui_architecture.md`)
  braucht, verlinkt sie hier statt sie zu duplizieren.

## Verwandte Dokumente

- [`ROADMAP.md`](../../ROADMAP.md) — kanonische Roadmap (Phasen,
  offene Workstreams, Next PRs, Explicitly Deferred).
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md) — Single-Source offene
  Arbeiten pro Workstream.
- [`docs/GLOSSARY.md`](../GLOSSARY.md) — einheitliches Vokabular
  (Approval, Audit Trail, Workflow-Overlay, Presence, Expression,
  Action Event, Interaction Layer, Provider Chain, Stage C).
