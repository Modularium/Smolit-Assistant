# Branch Protection Settings — `main`

- **Stand:** PR 42 (2026-04-25)
- **Scope:** Empfehlungen für die Branch-Protection-Regel am
  `main`-Branch von
  [`Modularium/Smolit-Assistant`](https://github.com/Modularium/Smolit-Assistant).
  Dies ist **Doku für GitHub-Settings**, nicht Automation. Es gibt
  keinen Workflow, der Branch-Protection via API setzt — die Regel
  wird **manuell** über die GitHub-UI bzw. via Admin gesetzt und
  hier nur dokumentiert.

---

## Zweck

Nach PR 38 (CI Foundation) und PR 42 (CI Hardening) existiert eine
minimale, verifizierte CI-Oberfläche. Damit die CI-Signale wirklich
wirken, muss der Schutz am Branch konfiguriert sein. Ohne Branch-
Protection kann ein direkter Push auf `main` die CI-Invarianten
umgehen.

Die hier dokumentierten Settings sind **konservativ** — sie bilden
die heutige Realität ab, nicht eine Release-Engineering-Zukunft.

## Required status checks (Pflicht)

Unter **Settings → Branches → Branch protection rules → `main` →
Require status checks to pass before merging**:

| Check-Name     | Quelle                                                    |
| -------------- | --------------------------------------------------------- |
| `core-test`    | Job `core-test` in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) |
| `ui-smoke`     | Job `ui-smoke` in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) |

**Require branches to be up to date before merging** — eingeschaltet.
Damit laufen beide Checks gegen den tatsächlichen Merge-Stand, nicht
gegen eine veraltete Commit-Basis.

## Required review (Pflicht)

**Require a pull request before merging** — eingeschaltet.

**Required approving reviews:** **1**. Solange das Projekt klein
bleibt, ist ein Reviewer genug; eine Erhöhung wäre bei wachsendem
Kreis von Maintainern trivial.

**Dismiss stale pull request approvals when new commits are pushed**
— **eingeschaltet**. Neue Pushes nach einem Approval entwerten das
Approval; Reviewer muss erneut zustimmen.

**Require review from Code Owners** — derzeit **nicht** gesetzt.
Es gibt keinen `CODEOWNERS`-File; falls einer kommt, kann die
Option nachgezogen werden.

## Direct pushes (verboten)

**Restrict who can push to matching branches** — eingeschaltet.
Niemand pusht direkt auf `main`. Auch Maintainer arbeiten über
Feature-Branches und PRs.

**Allow force pushes** — **aus.**

**Allow deletions** — **aus.**

## Lineare Historie (optional)

**Require linear history** — **empfohlen**. Verhindert Merge-
Commits in `main`; Squash- oder Rebase-Merge bleiben. Der aktuelle
Git-Log zeigt bereits eine saubere Linie (Merge-Commits nur für PR-
Integration, kein Criss-Cross); das Setting zementiert das.

## Admin-Bypass

**Do not allow bypassing the above settings** — **empfohlen**. Auch
Repo-Admins folgen der PR-Kette. Ein Notfall-Bypass (z. B. kaputter
CI-Runner-Tag) wird über einen eigenen Commit-Trail dokumentiert,
nicht durch stillschweigende Admin-Overrides.

## Auto-merge (bewusst aus)

**Allow auto-merge** — **aus.**

Scope-Grund: Auto-merge verlagert die „habe ich die Review-
Kommentare gesehen?"-Verantwortung auf die CI-Matrix. Solange
`ui-smoke` nur fünf kuratierte Smokes deckt (und z. B. keine
Pixel-/Rendering-Regressionstests), ist ein menschliches Merge-
Signal ehrlicher.

## Required deployments (bewusst leer)

Kein Deployment-Environment ist als Merge-Voraussetzung gesetzt.
Smolit-Assistant hat heute keinen Release-Flow, keine Staging-
Umgebung, kein Rollout-Gate. Wenn Workstream I (PR 48 — Release
Packaging Decision ADR) etwas ändert, wird dieser Abschnitt
gemeinsam nachgezogen.

## Nicht Teil dieser Rule (heute)

- **Keine required code scanning alerts.** Kein CodeQL-Workflow
  konfiguriert (FA der Security-Workstreams, sobald ein Ziel-
  Scope existiert).
- **Keine required signed commits.** Signing-Chain ist Teil des
  zukünftigen Packaging-ADR (PR 48), nicht dieser Settings-Seite.
- **Keine Merge-Queue.** Der Projektfluss ist heute klein genug,
  dass sequenzielle PRs ohne Queue stabil sind.
- **Kein Required-Deployments-Gate** (siehe oben).
- **Kein automatisches Dependabot-Gate.** Dependabot-PRs durchlaufen
  dieselbe Review-Kette wie andere PRs.

## Wie prüfe ich, ob die Regel aktiv ist?

```text
GitHub → Modularium/Smolit-Assistant
  → Settings → Branches → Branch protection rules
  → Eintrag für „main" öffnen
```

Oder per `gh`-CLI (read-only):

```bash
gh api -H "Accept: application/vnd.github+json" \
       /repos/Modularium/Smolit-Assistant/branches/main/protection
```

Ein erfolgreiches `200 OK` bedeutet: eine Branch-Protection-Regel
existiert. Der JSON-Output listet die aktuellen Settings — die
Soll-Werte stehen in der Tabelle oben.

## Siehe auch

- [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) —
  die Jobs, auf die sich die „Required status checks" beziehen.
- [`docs/SETUP.md` §7 — CI / Local verification parity](../SETUP.md) —
  lokaler Parity-Lauf.
- [`docs/OPEN_WORK.md` Workstream I — Packaging / Release / CI](../OPEN_WORK.md) —
  Positionierung dieses PRs in der Gesamt-Roadmap.
