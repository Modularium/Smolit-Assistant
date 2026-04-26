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
| [`PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md`](./PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md) | PR 33 Workflow Overlay Consolidation | Entscheidung **Option C — Entfernen**: der alte Drei-Knoten-Workflow-Overlay-Spike (Phase 3.1) ist komplett aus dem Repo entfernt. Workflow Visibility Overlay v1 (PR 16) bleibt einzige Workflow-UI. Kein neues Feature, keine neuen IPC-Events, keine neue Persistenz; Smoke-Coverage steigt (18 Cases bleiben, 9 Cases des alten State-Smokes entfallen). |
| [`PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md`](./PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md) | PR 49 Roadmap Sync after Contracts (PR 43–48) | Docs-only Reality-Check nach der Contract-Serie PR 43–48 (ABrain Native Contract Draft Link, Ecosystem Integration Contracts Matrix, AdminBot Safety Boundary ADR + Capability Contract, Audit Correlation ID Spec + Capability Vocabulary, OceanData Context Provider SPI ADR). Korrigiert ROADMAP-§6.3-Drift („drei" → „vier" Folge-PRs), verschiebt den ehemaligen „PR 48 Packaging ADR"-Eintrag in OPEN_WORK Workstream I auf PR 51, setzt die konservative neue Sequenz PR 50–55 (Release Gate Review → Packaging ADR → Accessibility RPC FA-1 Spike → Correlation ID Runtime Spike → Capability Constants Runtime Spike → OceanData Privacy/Redaction ADR), benennt eine Drift-Watchlist und bestätigt unveränderte Runtime-Baseline (kein `abrain_native` / `oceandata_context` / AdminBot-Adapter / `correlation_id` / `capability_id` im Code). |
| [`PR50_V0_2_RELEASE_GATE_REVIEW.md`](./PR50_V0_2_RELEASE_GATE_REVIEW.md) | PR 50 v0.2 Release Gate Review | Docs-only Gate-Review. Bewertung **conditionally ready for v0.2 candidate** nach vier Verifikations-Punkten (GitHub-CI grün auf main, README/SETUP stimmen, keine Runtime-Drift, Branch-Protection konfiguriert oder dokumentiert). Tabelle der heute live Capabilities vs. Future Work; vier Blocker, lange Non-Blocker-Liste; Release-Risiken/Watchlist (lokale Dev-Konfigs, cloud_http opt-in, Wayland-AOT honest refusal, OceanData-Rollendrift, AdminBot-Naming-Drift im Nachbar-Repo). Lokal `cargo test` 398 passed; fünf CI-Smokes (`settings-shell` / `avatar-render-polish` / `workflow-visibility` / `approval-card` / `audit-panel`) PASS. **Kein Tag, kein Version-Bump, kein Packaging in PR 50** — Gate, kein Release. |
| [`PR51_V0_2_GATE_FIX.md`](./PR51_V0_2_GATE_FIX.md) | PR 51 v0.2 Gate Fix: CI Workflow + SETUP Smoke Drift + XDG-Isolation | Docs/CI-Fix-only nach realem Gate-Check der PR-50-Vorbereitung. Fixt drei Blocker: (1) `.github/workflows/ci.yml` Zeile 98 — `${{ env.GODOT_VERSION }}` im job-level `name:` ist GitHub-Actions-context-invalid, jetzt hardcoded; (2) `docs/SETUP.md §2.4` zitierte den seit PR 33 entfernten `workflow-state-smoke`, jetzt `workflow-visibility-smoke`; (3) plain `cargo test` (396/2 fail durch `~/.config/smolit-assistant/text_chain.json`-Drift) ersetzt durch `scripts/ci_verify.sh core` als kanonischer Gate-Befehl, mit XDG_CONFIG_HOME / XDG_CACHE_HOME / XDG_DATA_HOME Isolation; HOME bleibt unverändert für rustup/cargo. Packaging Decision ADR rückt von PR 51 auf PR 52. **Kein** Runtime-Code, **kein** Tag, **kein** Version-Bump, **keine** ABrain/AdminBot/OceanData/smolitux-ui-Änderung. v0.2-Gate-Status: *Gate fix in progress; not yet ready for v0.2 candidate* — verbleibend GitHub-CI grün auf main + Branch-Protection + Operator-Approval. |

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
