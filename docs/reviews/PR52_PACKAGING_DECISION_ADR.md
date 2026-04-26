# PR 52 — Packaging Decision ADR

- **Datum:** 2026-04-26.
- **Typ:** Docs/ADR-only; kein Runtime-Code, keine Packaging-
  Implementation, kein Build-Artefakt.
- **Scope:** Erste post-v0.2-Arbeit. Fixiert die Reihenfolge und
  Eintrittskriterien für zukünftige Linux-Desktop-Packaging-
  Pfade. Setzt **kein** Tag, **kein** Version-Bump, **kein**
  Format auf.

> Leitprinzip: **Decide packaging before building packages.**

## 1. Scope

v0.2.0 ist erfolgreich auf `main` getaggt und als
[GitHub-Release](https://github.com/Modularium/Smolit-Assistant/releases/tag/v0.2.0)
publiziert (ohne binäre Anhänge). Workstream I (Packaging /
Release / CI) ist damit beim ersten Punkt nach dem Gate: bevor
irgendein binäres Format gebaut wird, fixiert PR 52 als ADR-only
welche Strategie wir verfolgen — und welche bewusst nicht.

PR 52 enthält:

- [`docs/adr/ADR-0007-packaging-decision.md`](../adr/ADR-0007-packaging-decision.md)
  (Proposed, 2026-04-26).
- ADR-Index-Eintrag in
  [`docs/adr/README.md`](../adr/README.md).
- ROADMAP-Eintrag in §6.4 (PR 52) plus `v0.2 Release Gate —
  closed`-Block in §6.5.
- OPEN_WORK Workstream I auf den ADR-Stand gebracht; FA-1…FA-9
  als Future Work gerahmt.
- README §12 Non-goals + `docs/SETUP.md` Header zeigen jetzt
  explizit auf ADR-0007 und beschreiben den Source-/Dev-Run als
  offiziellen Install-Pfad (v0.2.0 trägt keine binären Anhänge).

PR 52 enthält **nicht**:

- Kein AppImage, `.deb`, Flatpak-Manifest, Snap-Profil, Dockerfile.
- Keine Godot-Export-Presets.
- Kein Signing-Code, keine Schlüssel.
- Kein Auto-Updater.
- Kein Version-Bump (`Cargo.toml` unverändert).
- Kein neuer Release.
- Keine Provider-/IPC-/UI-/Core-Änderung.
- Keine Änderung an ABrain / Smolit_AdminBot / OceanData /
  smolitux-ui.

## 2. Decision

Smolit-Assistant verfolgt eine **gestufte, Linux-Desktop-zuerst**
Packaging-Strategie:

- **Phase 1 (P0 + P1 + P2).** Source/Dev-Run bleibt offiziell
  (P0). Eintrittsschritt zum Binär-Pfad ist ein reproduzierbarer
  Local-Build-Helper (P1, kein Installer). **AppImage** ist der
  erste Binär-Kandidat (P2).
- **Phase 2 (P3).** `.deb` für Ubuntu/Debian — erst *nachdem*
  AppImage stabil ist. Braucht eigenes Install-/Service-/Path-
  Konzept.
- **Phase 3 (P4).** Flatpak-**Evaluation**, Output ist primär
  ein Folge-ADR (Permissions, Portals, Loopback-Socket,
  Audio, AT-SPI).
- **P5 — Signing & Update Policy ADR.** Eigener Folge-PR; vor
  P5 keine "stable binary distribution"-Aussage.
- **P6 — Multi-distro CI Matrix.** Erst nach P5.

Bewusst **nicht zuerst:**

- **Snap** — zweite Sandbox-Achse parallel zu Flatpak ohne
  klaren Mehrwert.
- **Docker als Desktop-Distribution** — falsches Modell für
  GUI-Desktop mit IPC-Loopback und Desktop-Interaction. Bleibt
  legitim für CI/Headless.
- **`.rpm`** — nicht im Ziel-Profil (Ubuntu 24.04 primary).
- **Windows / macOS** — out-of-scope auf Sicht.

## 3. Options considered

| Option | Decision |
| ------ | -------- |
| Source checkout | Bleibt offiziell unterstützt (P0). |
| Reproducible local build script | Eintritt vor jedem Binär-Pfad (P1). |
| AppImage | Erste binäre Empfehlung (P2). |
| `.deb` (Ubuntu/Debian) | Phase P3, nach AppImage. |
| Flatpak | Phase P4, evaluation, nicht implementation. |
| Snap | Bewusst nicht. |
| Docker (als Desktop-Distribution) | Bewusst nicht. |
| `tar.gz` portable | Optional als Fallback parallel zu AppImage. |
| Distro packages later (AUR/COPR/Nix-Flake) | Bei Pull akzeptieren, nicht aktiv pushen. |
| Windows / macOS | Out-of-scope auf Sicht. |

Vollständige Pros/Cons-Tabelle und Begründungen:
[ADR-0007 §5](../adr/ADR-0007-packaging-decision.md).

## 4. Non-goals

PR 52 ist Docs-only. Keine Implementation. Insbesondere:

- Kein Packaging-Code, kein Manifest, kein Build-Skript.
- Keine Export-Presets.
- Kein AppImage / `.deb` / Flatpak / Dockerfile / Snap-Profil.
- Kein Signing.
- Kein Installer, kein Auto-Updater.
- Kein Version-Bump, kein neuer Release.
- Keine Provider-/IPC-/UI-/Core-Änderung.
- Keine ABrain/AdminBot/OceanData/smolitux-ui-Änderung.

Detailliert in [ADR-0007 §14](../adr/ADR-0007-packaging-decision.md).

## 5. Verification

Lokal (CI-paritätisch, XDG-isoliert):

```bash
scripts/ci_verify.sh core
scripts/run_overlay_verification.sh settings-shell-smoke
ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'YAML OK'"
bash -n scripts/ci_verify.sh
```

Erwartung:

- `cargo test` bleibt grün (398 Tests; PR 52 ändert keinen
  Runtime-Code).
- `settings-shell-smoke` bleibt PASS.
- YAML-Workflow bleibt valide (PR 51 Härtung steht).
- `bash -n` bleibt grün.

Repo-Hygiene-Checks:

```bash
rg "v0.2.0" README.md ROADMAP.md docs
rg "AppImage|Flatpak|\\.deb|Snap|Docker|tar.gz" README.md ROADMAP.md docs
rg "packaging" README.md ROADMAP.md docs
rg "release artifact|checksum|signing|auto-update|auto updater" README.md ROADMAP.md docs
rg "<<<<<<<|=======|>>>>>>>" README.md ROADMAP.md docs .github scripts
```

- `v0.2.0` referenziert in README/ROADMAP/Reviews als released
  ohne binäre Anhänge.
- AppImage / Flatpak / `.deb` / Snap / Docker / tar.gz tauchen
  nur als ADR-Diskussion / Future Work auf, nicht als gebaute
  Artefakte.
- Keine Merge-Konflikt-Marker.
- Keine Änderung außerhalb `docs/`, `ROADMAP.md`, `README.md`.

## 6. Repo state after PR 52

- Nur Docs-Dateien geändert.
- Kein Code geändert (`core/`, `ui/`, `scripts/`, `.github/`,
  `Cargo.toml`, `Cargo.lock`, `core/Cargo.toml`,
  `ui/project.godot`, `.env.example` unverändert).
- Keine Packaging-Artefakte erzeugt.
- Keine Binärdateien.
- Keine `export_presets.cfg` angelegt oder verändert.
- v0.2.0 bleibt als Release auf `main`, ohne binäre Anhänge.
- AppImage, Flatpak, `.deb`, Docker, Snap: nur Decision /
  Future Work, nicht implementiert.
- Kein anderes Repo (ABrain / Smolit_AdminBot / OceanData /
  smolitux-ui) angefasst.

## 7. Related

- [`ADR-0007`](../adr/ADR-0007-packaging-decision.md) — der
  Entscheidungsinhalt selbst.
- [`docs/reviews/PR50_V0_2_RELEASE_GATE_REVIEW.md`](./PR50_V0_2_RELEASE_GATE_REVIEW.md)
  — Gate-Review vor v0.2.
- [`docs/reviews/PR51_V0_2_GATE_FIX.md`](./PR51_V0_2_GATE_FIX.md)
  — Gate-Fix unmittelbar vor Release.
- [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md)
  — Branch-Protection-Disziplin, die für jeden zukünftigen
  Release-PR (P5+) gilt.
- [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)
  — bleibt in-memory; Packaging ändert das nicht.
- [`docs/wayland_always_on_top_refusal_results.md`](../wayland_always_on_top_refusal_results.md)
  — Wayland-Realität, die jedes binäre Format in Release-Notes
  spiegeln muss.

## 8. Follow-ups

PR 52 setzt **keinen** zwingenden nächsten PR. Mögliche Future
Work (alle nicht priorisiert, keine Termine):

- **FA-1** — Reproducible local build script (P1).
- **FA-2** — Godot Export Presets (P1-Voraussetzung).
- **FA-3** — AppImage Prototype + Checksum (P2).
- **FA-4** — `.deb` Prototype (P3).
- **FA-5** — Flatpak Permission Review ADR (P4) — eigener
  Folge-ADR (ADR-0008+).
- **FA-6** — Signing & Update Policy ADR (P5) — eigener
  Folge-ADR.
- **FA-7** — Multi-distro CI Matrix (P6).
- **FA-8** — Release Notes Template, das Wayland-/X11-/
  `focus_window`-Realität explizit adressiert.
- **FA-9** — Re-Evaluation Snap / Docker *(optional,
  nicht priorisiert)*.

Jeder dieser Punkte ist eigener PR mit eigener Verifikation und
ggf. eigenem ADR-Update.
