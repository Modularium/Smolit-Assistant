# PR 33 — Workflow Overlay Consolidation Decision

- **Datum:** 2026-04-24
- **Scope:** Workstream A (Docs & Architecture Hygiene). UI-
  Cleanup-PR: der frühere Drei-Knoten-Workflow-Overlay-Spike
  aus Phase 3.1 wird entfernt; das **Workflow Visibility Overlay
  v1** (PR 16) bleibt als einzige Workflow-UI im Repo.
- **Guardrails:** keine neuen Core-/IPC-Events, keine
  Audit-/Approval-Änderung, kein Workflow-Editor, kein Drag/Drop,
  keine Persistenz.

---

## 1. Ausgangslage

Seit PR 20 (Docs Reality Check) steht dokumentiert, dass zwei
Workflow-Overlays parallel in `main.tscn` leben:

| Merkmal | **Legacy** (Phase 3.1 MVP-Spike) | **Workflow Visibility Overlay v1** (PR 16) |
| --- | --- | --- |
| Metapher | Drei-Knoten-Kausalitäts-Graph: Trigger → Action → Result | Lineare Kartenliste: HEARD → THINKING → RESPONSE → ACTION → STEP → SPEAKING → APPROVAL → COMPLETED / FAILED |
| Dateien | `ui/scripts/workflow_overlay/` (4 `.gd`) + `ui/scenes/workflow_overlay/workflow_overlay_root.tscn` | `ui/scripts/workflow/` (2 `.gd`) + `ui/scenes/workflow/workflow_visibility_panel.tscn` |
| Events konsumiert | 7 Action-Event-Signale | 14 Event-Signale (inkl. Approval, Speaking, Heard / Thinking / Response) |
| Toggle | Indirekt über Visual-Action-Mode-Staging (`workflow_overlay_allowed` / `_alpha`) | `SMOLIT_WORKFLOW_OVERLAY=1` oder session-lokaler Dev-Toggle |
| Default-Sichtbarkeit | Versteckt in NONE/MINIMAL, sichtbar in GUIDED/FULL | Versteckt (Env opt-in) |
| Smoke | `workflow_overlay_state_smoke.gd` (9 Cases) | `workflow_visibility_smoke.gd` (18 Cases) |

Die Zielkonflikt-Bestandsaufnahme aus PR 20 und PR 31
(Roadmap-Checkpoint, `§6.2` **Drift-Watchlist**) nannte diese
Koexistenz explizit als offene Design-Entscheidung.

## 2. Vergleich alt vs. neu — was bietet jedes Overlay exklusiv?

**Legacy (Drei-Knoten):** rein *visuelle* Metapher. Drei Panel-
Kapseln verbunden durch zwei gerichtete Kanten; Collapse/Expand
per Phase. Keine zusätzliche Information gegenüber der neuen
Timeline — die Knoten sind eine aggregierte Sicht auf dieselben
Action Events.

**Visibility Overlay (linear):** vollständige Lifecycle-Timeline
inkl. **Approval-Karte** (PR 17) und **Speaking-Karte** (PR 14)
— beide nicht vom Legacy-Spike dargestellt.

**Kein Funktionsverlust bei Entfernung des Legacy-Spikes.** Der
Legacy-Pfad bietet eine andere *Visualisierungs-Ästhetik*, aber
keine fachlich eigenständige Information.

## 3. Entscheidung

**Option C — Entfernen.**

Begründung:

1. Der Visibility-Overlay ist funktional vollständiger (Approval-,
   Speaking-, Audit-aware).
2. Der Smoke-Coverage-Anteil steigt statt zu sinken: 18 Cases im
   verbleibenden `workflow_visibility_smoke` vs. 9 Cases im
   entfernten `workflow_overlay_state_smoke`.
3. Die Default-Sichtbarkeit unter GUIDED/FULL-Modes hieß, dass in
   manchen Konfigurationen bis heute nur der **Legacy** sichtbar
   war — Nutzer sahen *nicht* die PR-16-Timeline. Entfernung des
   Legacy plus env-opt-in des Visibility-Panels stellt eine
   konsistente One-or-None-Sichtbarkeit her.
4. Der Leitsatz *"One visible workflow truth, no duplicate mental
   models"* verbietet Option A (beides behalten).
5. Option B (deprecate) würde dead weight halten. Option D
   (konsolidieren) würde eine neue View-Variante einführen, die
   niemand gefordert hat.

## 4. Was geändert wurde

### 4.1 Gelöscht

- `ui/scripts/workflow_overlay/` (vier `.gd`-Dateien + jeweils
  `.uid`):
  - `workflow_overlay_controller.gd`
  - `workflow_overlay_state.gd`
  - `workflow_node_view.gd`
  - `workflow_edge_view.gd`
- `ui/scenes/workflow_overlay/workflow_overlay_root.tscn`
- `scripts/workflow_overlay_state_smoke.gd`

### 4.2 `main.tscn` / `main.gd`

- `ExtResource` auf `workflow_overlay_root.tscn` entfernt.
- `WorkflowOverlay`-Node (z_index 40) entfernt.
- `main.gd`: `@onready var _workflow_overlay` entfernt.
- `main.gd`: der `if _workflow_overlay != null { … }`-Block in
  `_apply_visual_action_staging` entfernt; durch einen kurzen
  Kommentar ersetzt, der auf die PR-33-Entscheidung verweist.

### 4.3 `visual_action_mode.gd`

- Keys `workflow_overlay_allowed` und `workflow_overlay_alpha`
  aus allen vier Mode-Dicts (NONE / MINIMAL / GUIDED / FULL)
  entfernt.
- Doc-Kommentar auf zwei Felder (`banner_visible`, `banner_alpha`)
  reduziert.
- PR-33-Hinweis: das Workflow Visibility Overlay v1 reagiert
  **nicht** auf Visual-Action-Staging, sondern auf die eigene
  `SMOLIT_WORKFLOW_OVERLAY`-Env-Gate.

### 4.4 `dev_controls_controller.gd` / `dev_controls_panel.tscn`

- `workflow_overlay_path`-Export entfernt.
- `_workflow_overlay`-Feld entfernt.
- `_PHASE_PREVIEWS`-Konstante + `_phase_buttons`-Feld entfernt.
- `_build_overlay_section()`-Funktion + ihr Aufruf entfernt
  (der Preview-Block war reiner Dev-Spike-Hilfe für den
  Drei-Knoten-Overlay).
- `_on_phase_preview_pressed()` entfernt.
- `dev_controls_panel.tscn`: Zeile
  `workflow_overlay_path = NodePath("../WorkflowOverlay")` entfernt.
- Dev-Control-Dokstring im Header auf den aktuellen Zustand
  angepasst (Visibility-Toggle bleibt, Preview-Block ist weg).

### 4.5 Smoke-Tests

- `scripts/visual_action_mode_smoke.gd`: Assertions auf
  `workflow_overlay_*`-Keys entfernt; durch zwei Anti-Regressions-
  Assertions ersetzt (`not s.has("workflow_overlay_allowed")`)
  plus `banner_alpha`-Monotonie-Check ohne Overlay-Achse.
- `scripts/dev_controls_smoke.gd`: `_check_phase_names`-Case
  entfernt; `_WorkflowStateRef`-Preload entfernt; Header-Doc
  angepasst.
- `scripts/run_overlay_verification.sh`: `workflow-state-smoke`-
  Case entfernt (Case-Label + Help-Text).

### 4.6 Docs

- [`docs/GLOSSARY.md`](../GLOSSARY.md) — Eintrag "Workflow
  Overlay" auf "seit PR 33 entfernt" umformuliert; Eintrag
  "Workflow Visibility Overlay" als *einzige* Workflow-UI
  markiert.
- [`docs/ui_architecture.md`](../ui_architecture.md) §6a auf
  eine kurze Konsolidierungs-Zusammenfassung gekürzt; §8a auf
  einen Historik-Marker reduziert (der fachliche Inhalt steht
  in §8.4c).
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md) — Workstream A auf
  "PR 33 landed / Workflow-Overlay-Konsolidierung entschieden".
- [`ROADMAP.md`](../../ROADMAP.md) — PR-33-Zeile als gelandet
  markiert; Current-Stable-Baseline-Zeile "9 Scenes → 8 Scenes".

## 5. Was bewusst **nicht** geändert wurde

- **Keine Änderung am Workflow Visibility Overlay v1.** Der
  PR-16-Code ist unangetastet.
- **Keine neuen Core-/IPC-Events.** Der Cleanup ist rein UI-seitig.
- **Keine Audit-Änderung** (PR 32 bleibt gültig).
- **Keine Approval-Änderung** (Policy v0 aus PR 25 bleibt gültig).
- **Kein Workflow-Editor**, kein Drag/Drop, kein n8n-Klon.
- **Keine Persistenz**, kein Export, keine Screenshot-/Record-
  Funktion.
- **Keine Desktop-Automation**, kein `type_text`, kein
  `send_shortcut`.
- **Keine Smolitux-Token-Arbeit**, keine `smolitux-ui`-
  Änderung, keine OceanData-Änderung.

## 6. Tests / Verifikation

- `cargo test`: **387 passed, 0 failed** (unverändert — kein
  Core-Eingriff).
- `workflow-visibility-smoke`: **PASS** (18 Assertions,
  unverändert grün).
- `dev-controls-smoke`: **PASS** (nach Entfernung von
  `_check_phase_names`).
- `visual_action_mode-smoke`: **PASS** (Assertions auf die
  entfernten Overlay-Keys wurden durch Anti-Regressions-Checks
  ersetzt).
- `settings-shell-smoke`: **PASS** (nicht betroffen).
- `approval-card-smoke`: **PASS** (nicht betroffen).
- `audit-panel-smoke`: **PASS** (nicht betroffen).
- `rg "workflow_overlay"` im Repo: verbleibende Treffer sind
  ausschließlich in Review-/Historie-Dokumenten (PR 20, PR 31,
  PR 33, GLOSSARY als Abgrenzungs-Marker). Kein Runtime-Code-
  Treffer.
- `rg "WorkflowOverlay"` in `ui/`: null Treffer.

## 7. Follow-up

- **Keiner.** Der PR schließt die offene Konsolidierungsfrage aus
  der Drift-Watchlist des PR-31-Checkpoints. Falls in Zukunft
  jemand eine Drei-Knoten-Sicht wünscht, wäre das ein eigenes
  ADR-würdiges Feature, nicht ein Rollback dieses PRs.
- Die Drift-Watchlist in
  [`docs/reviews/PR31_ROADMAP_CHECKPOINT.md`](./PR31_ROADMAP_CHECKPOINT.md)
  §7 verliert den "Zwei Workflow-Overlays koexistieren"-Punkt.

## 8. Honesty Check

- ✅ Kein `.gd`/`.tscn` im Runtime-Pfad referenziert `workflow_overlay/`
  mehr.
- ✅ Keine ExtResource-Zombies in `main.tscn`.
- ✅ Dev-Controls-Panel öffnet sich ohne `preview_phase`-Block
  (getestet via `dev-controls-smoke`).
- ✅ Visual Action Mode staging-dict ist reduziert, aber
  monoton konsistent — PASS in `visual_action_mode_smoke`.
- ✅ Dokumentation nennt keine "beide koexistieren"-Stelle mehr.
- ⚠️ Ältere Review-Dokumente (PR 20, PR 28, PR 31) nennen noch
  "zwei Workflow-Overlays" oder "Workflow-Overlay-alt". Das sind
  Zeitdokumente; sie bleiben bewusst unverändert. GLOSSARY +
  §6a/§8a in `ui_architecture.md` sind die kanonische Brücke.
