# PR 51 — v0.2 Gate Fix: CI Workflow + SETUP Smoke Drift + XDG-Isolation

- **Datum:** 2026-04-25.
- **Typ:** Docs/CI-Fix; kein Runtime-Code, kein Feature.
- **Scope:** Drei reale Blocker, die der Gate-Check aus der PR-50-
  Vorbereitung gefunden hat. PR 51 schließt sie. PR 51 setzt
  **kein** Tag, **kein** Version-Bump, **kein** Packaging.

> Leitprinzip: **The release gate must be reproducible, CI-valid,
> and aligned with documented commands.**

## 1. Scope

PR 50 (v0.2 Release Gate Review) hat „conditionally ready"
empfohlen. Der reale Gate-Check hat dann drei Blocker zutage
gefördert, die so heute ein v0.2-Tag verhindern würden. PR 51
fixt sie ohne Feature-Arbeit:

- CI-Workflow ist invalid (GitHub Actions verweigert die YAML).
- `docs/SETUP.md` zitiert einen Smoke-Case, der seit PR 33 nicht
  mehr existiert.
- Plain `cargo test` ist ohne XDG-Isolation lokal nicht
  reproduzierbar; persistierte Host-Config unter
  `~/.config/smolit-assistant/` produziert 396 / 2 fail.

## 2. Found blockers

### 2.1 GitHub Actions Workflow invalid

**Symptom (CI):**

```
.github/workflows/ci.yml
Line 98, Col 11: Unrecognized named-value: 'env'
expression: env.GODOT_VERSION
```

**Ursache.** Die Zeile

```yaml
ui-smoke:
    name: UI smokes (Godot ${{ env.GODOT_VERSION }} headless)
```

verwendet die `env`-Context-Expression im *job-level* `name:`
-Feld. Laut GitHub Actions
*[Context availability](https://docs.github.com/en/actions/learn-github-actions/contexts#context-availability)*
sind in `jobs.<job_id>.name` nur die Contexts `github`, `inputs`,
`vars`, `needs`, `strategy`, `matrix` verfügbar — **nicht** `env`.
GitHub validiert die YAML deshalb komplett rot, und alle
nachfolgenden Job-Definitionen werden ignoriert.

**Was nicht das Problem ist.** Step-level `name:` (z. B.
`Cache Godot ${{ env.GODOT_VERSION }} binary` auf Zeile 125) und
`with.key` (z. B. `key: godot-${{ env.GODOT_VERSION }}` auf Zeile
135) sind beide gültige Stellen für `env`-Expressions — diese
bleiben unverändert.

### 2.2 SETUP.md zitiert nicht-existenten Smoke-Case

**Symptom (lokal):**

```
$ scripts/run_overlay_verification.sh workflow-state-smoke
unknown case: workflow-state-smoke
```

**Ursache.** PR 33 (Workflow Overlay Consolidation, Option C —
Entfernen) hat den alten Drei-Knoten-Workflow-Overlay-Spike
inklusive `workflow-state-smoke` aus dem Repo entfernt. Die
einzig verbleibende Workflow-UI ist
`workflow-visibility-smoke`. `docs/SETUP.md §2.4` zeigte aber
weiterhin `workflow-state-smoke` als aktuellen Setup-Befehl. Der
Hilfe-Output von `run_overlay_verification.sh --help` benennt die
Entfernung sogar explizit — die SETUP-Drift ist also reine Doku-
Vergesslichkeit, kein Code-Bug.

### 2.3 Plain `cargo test` ist nicht reproduzierbar

**Symptom (lokal, ohne Isolation):**

```
$ cargo test --manifest-path core/Cargo.toml --locked
test result: FAILED. 396 passed; 2 failed; 0 ignored
failures:
    ipc::server::tests::get_status_includes_text_provider_fields
    ipc::server::tests::get_status_reports_llamafile_lifecycle_when_in_chain
```

**Symptom (mit Isolation):**

```
$ scripts/ci_verify.sh core
test result: ok. 398 passed; 0 failed
```

**Ursache.** Smolit-Core liest beim Start
`$XDG_CONFIG_HOME/smolit-assistant/text_chain.json` — falls eine
Dev-Maschine den Provider-Chain-Editor schon einmal benutzt hat,
liegt dort z. B.

```json
{ "chain": ["llamafile_local", "local_http", "abrain"] }
```

und überschreibt die in den IPC-Tests erwartete Default-Chain
`["abrain"]`. Die zwei betroffenen Tests sind Wire-Format-Asserts,
die das Status-Feld `text_provider_chain` exakt vergleichen.
README.md und SETUP.md empfehlen aber bislang plain
`cargo test --manifest-path core/Cargo.toml` als Initial-Check
für Contributors — was vor jedem Release/Gate-Check zu False
Negatives führen kann.

## 3. Fixes

### 3.1 CI Workflow

`.github/workflows/ci.yml` — `jobs.ui-smoke.name`:

```yaml
# vorher
name: UI smokes (Godot ${{ env.GODOT_VERSION }} headless)

# nachher
name: UI smokes (Godot 4.6-stable headless)
```

Die Version ist jetzt **nur an dieser einen Stelle** hardcoded;
alle anderen `env.GODOT_VERSION`-Verwendungen (step-level `name:`,
`with.key`, Shell-Steps mit `${GODOT_VERSION}`) bleiben dynamisch
und folgen weiterhin der `env:`-Konstante oben im Workflow. Der
Kommentar im Job benennt die Asymmetrie und die GitHub-Actions-
Regel, damit ein zukünftiger Bump nicht doppelt fehlt.

Zusätzlich erweitert PR 51 den `Configure XDG isolation`-Step im
`core-test`-Job um `XDG_DATA_HOME`, damit eine künftige
Persistenz-Location unter `$XDG_DATA_HOME/smolit-assistant/`
automatisch in der Isolations-Domäne landet (siehe §3.3).

### 3.2 SETUP.md Smoke Drift

`docs/SETUP.md §2.4`:

- `workflow-state-smoke` → `workflow-visibility-smoke`.
- expliziter Verweis auf PR 33 (Option C — Entfernen), damit
  Reviewer die Historie sehen.
- neuer Block mit `scripts/ci_verify.sh smokes` als CI-paritätisch
  isoliertem Komplett-Lauf.

Historische Erwähnungen von `workflow-state-smoke` in
[`docs/reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md`](./PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md)
und in PR-31-/PR-33-Review-Texten bleiben unangetastet — sie sind
korrekt als historische Aussage.

### 3.3 XDG-Isolation als kanonischer Gate-Befehl

`scripts/ci_verify.sh`:

- exportiert zusätzlich `XDG_DATA_HOME=${ISOLATE_DIR}/data`.
- legt das zugehörige Verzeichnis an.
- erweitert den `→ XDG isolation:`-Header um die dritte Zeile.
- `HOME` bleibt **bewusst unverändert** — rustup/cargo finden
  ihre Toolchain unter `$HOME/.cargo` / `$HOME/.rustup`. Ein
  isoliertes `HOME` würde die per `dtolnay/rust-toolchain@stable`
  installierte Toolchain auf dem CI-Runner verlieren.

`README.md §5 Quick Start`:

- ersetzt `cargo test --manifest-path core/Cargo.toml` durch
  `scripts/ci_verify.sh core` (Empfehlung), behält den Plain-Befehl
  als Kommentar mit Hinweis auf das `~/.config`-Drift-Risiko.

`docs/SETUP.md §2.1`:

- Initial-Test-Block zeigt `scripts/ci_verify.sh core` als
  kanonischen Gate-Befehl.
- erklärt explizit, warum: persistierte Settings unter
  `~/.config/smolit-assistant/` können IPC-Tests verfälschen.
- bestätigt erneut, dass `HOME` nicht überschrieben wird, weil
  rustup/cargo es brauchen.

## 4. Verification

| Check | Ergebnis |
|-------|----------|
| `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml')"` | **YAML OK** |
| `bash -n scripts/ci_verify.sh` | **shell OK** |
| `scripts/ci_verify.sh core` | **398 passed; 0 failed** |
| `scripts/run_overlay_verification.sh settings-shell-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh avatar-render-polish-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh workflow-visibility-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh approval-card-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh audit-panel-smoke` | **PASS** |
| `scripts/run_overlay_verification.sh workflow-state-smoke` | **unknown case** (gewollt — Case existiert nicht mehr) |
| `rg "workflow-state-smoke" README.md docs/SETUP.md ROADMAP.md docs/OPEN_WORK.md` | leer (historische Treffer in Reviews bleiben außerhalb dieser Liste) |
| `rg "ci_verify.sh core\|ci_verify.sh smokes" README.md docs/SETUP.md` | beide kanonischen Befehle sichtbar |
| `rg "env\.GODOT_VERSION" .github/workflows/ci.yml` | nur an erlaubten Stellen (step-level `name:` + `with.key`) — `jobs.ui-smoke.name` ist hardcoded |

> Hinweis: Die GitHub-CI-Bestätigung selbst kann nur nach einem
> Push erfolgen. Lokal sind alle drei Blocker geschlossen, die
> Workflow-YAML parst, der Smoke-Help-Text und `docs/SETUP.md`
> stimmen überein, und `scripts/ci_verify.sh core` produziert die
> erwarteten 398 grünen Tests. Nach dem PR-Push muss das
> GitHub-Actions-Run noch grün auf `main` durchlaufen.

## 5. Remaining gate checks before v0.2 tag

Nach PR 51 ist der v0.2-Status weiterhin nicht „released" — es
sind die folgenden Verifikations-/Konfigurations-Punkte vor einem
Tag offen, **alle nicht in PR 51 erledigt**:

1. **GitHub Actions auf `main` grün** nach Merge dieses PRs. PR
   51 fixt die YAML; ein erfolgreicher CI-Run kann erst nach dem
   Push beobachtet werden.
2. **Branch-Protection für `main`** gemäß
   [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md)
   konfiguriert (Required checks: `core-test` + `ui-smoke`,
   Required review 1, dismiss stale approvals, linear history
   empfohlen).
3. **Operator-Approval für den Tag selbst.** Kein Auto-Tag aus
   PR 51 oder einem späteren PR. Der Tag-Schritt ist ein
   bewusster manueller Akt.

`v0.2` wird **nicht** in PR 51 gesetzt. PR 51 entfernt die drei
Blocker, die ein „candidate"-Status heute verhindern.

## 6. Non-goals

PR 51 ist Gate-Fix, kein Feature-PR. Ausdrücklich **nicht** Teil:

- Kein Runtime-Feature; kein neuer Code-Pfad in `core/src/` oder
  `ui/`.
- Kein Packaging-ADR (verschiebt sich auf PR 52).
- Kein Accessibility RPC FA-1 Spike.
- Kein `correlation_id`/`capability_id`-Runtime.
- Kein neuer Provider-Kind, kein neues IPC-Command, keine
  UI-Änderung.
- Keine Branch-Protection-Automation.
- Kein Release-Tag, kein GitHub Release, kein Version-Bump im
  `Cargo.toml`.
- Keine Edits an ABrain / Smolit_AdminBot / OceanData /
  smolitux-ui.
