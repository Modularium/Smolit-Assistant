# PR 31 — Roadmap Checkpoint after PR 21–30

- **Datum:** 2026-04-24
- **Scope:** Workstream A (Docs & Architecture Hygiene). Docs-only
  Checkpoint nach der PR-21–30-Stabilisierungsserie. Keine Code-,
  UI-, IPC- oder Protokoll-Änderungen.
- **Ziel:** ROADMAP und OPEN_WORK synchronisieren, stale „next PR"-
  Angaben aufräumen, PR-32–40-Sequenz verankern, Drift-Watchlist
  benennen.

---

## 1. Scope

Zehn PRs in Folge haben Sicherheit, Provider-Onboarding, Docs-
Hygiene und den Einstiegspfad nach vorn gebracht. Jetzt ist der
richtige Moment, Roadmap und Workstream-Status einmal
durchzugehen, statt in den nächsten Feature-PR zu kippen. Der
Checkpoint ist ausdrücklich **kein** Freischuss für
Scope-Erweiterung — alle Zielbild-Einträge bleiben in
OPEN_WORK / Explicitly Deferred.

## 2. Summary PR 21–30

| PR | Workstream | Gegenstand |
| --- | --- | --- |
| 21 | A | Docs-Follow-ups nach PR 20 (tote Links, `docs/reviews/`-Index, Glossar-Embryo) |
| 22 | B | Wayland-Compositor-Live-Messung (Hostinventur-Realitätseintrag, externer Messauftrag bleibt offen) |
| 23 | F | `focus_window` Reality Decision (Option 1 bestätigt: template-basierter X11-Backend) |
| 24 | J | Smolitux Design Contract ADR (Docs-only, Spiegel-ADR in smolitux-ui) |
| 25 | E | Policy v0 — Approval-Default für echte Interaction Actions (Tripwire im Config) |
| 26 | D | Provider-Onboarding UX v1 (Readout + kuratierte Quick-Action; kein Auto-Cloud) |
| 27 | C | whisper_cpp STT Provider Kind (env-only, command-basiert; Default bleibt `[command]`) |
| 28 | A | `presence_desktop_interaction.md` Reality Trim (1096 → 491 Zeilen) |
| 29 | I | README Build Setup + First Install Docs (608 → 286 Zeilen + `docs/SETUP.md` + `.env.example`) |
| 30 | G | Avatar Render Polish Follow-up (Orb Core-Glow, Robot Pupil-Specular, Humanoid Two-Layer-Cheeks + Eyebrows; `avatar_palette.gd`) |

Detailreviews (wo vorhanden):

- [`PR20_DOCS_REALITY_CHECK.md`](./PR20_DOCS_REALITY_CHECK.md)
- [`PR23_FOCUS_WINDOW_DECISION.md`](./PR23_FOCUS_WINDOW_DECISION.md)
- [`PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./PR25_POLICY_V0_APPROVAL_DEFAULT.md)
- [`PR28_PRESENCE_DESKTOP_INTERACTION_TRIM.md`](./PR28_PRESENCE_DESKTOP_INTERACTION_TRIM.md)

## 3. Current Stable Baseline (nach PR 30)

Knapp; Details in [`ROADMAP.md §3`](../../ROADMAP.md).

**Core.** `core/src/app.rs` Orchestrator, `core/src/approvals/`
(idempotent), `core/src/audit/` (Ring-Buffer, in-memory),
`core/src/interaction/` (`open_application` real + Approval-gated;
`focus_window` X11-template-basiert mit doppeltem Opt-in),
`core/src/providers/` (text: abrain / llamafile_local / local_http /
cloud_http; **stt: command + whisper_cpp**; tts: command).

**Config-Defaults (Policy v0).** `DEFAULT_INTERACTION_REQUIRE_CONFIRMATION
= true`, `DEFAULT_INTERACTION_ALLOW_OPEN_APP = true`,
`DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW = false`,
`DEFAULT_INTERACTION_ALLOW_TYPE_TEXT = false`,
`DEFAULT_INTERACTION_ALLOW_SHORTCUTS = false`. Tripwire-Tests in
`core/src/config.rs`.

**IPC.** Unverändert seit PR 27; PR 26/27/28/29/30 haben das
Protokoll **nicht** erweitert. StatusPayload hat zwei additive
PR-27-Booleans (`stt_whisper_cpp_in_chain`,
`stt_whisper_cpp_configured`), jeweils `#[serde(default)]`.

**UI.** Settings-Shell mit Provider-Onboarding-Block (PR 26),
Approval-Card (PR 17), Workflow Visibility Overlay v1 (PR 16/17),
Dev-only Audit-Panel (PR 19). Avatar: Phase B Render Polish
Follow-up (PR 30) mit kuratierter `avatar_palette.gd`; Smolit
Salamander TEXTURE-Pfad unverändert.

**Docs.** README/SETUP/.env.example konsolidiert (PR 29);
`presence_desktop_interaction.md` auf 12-Abschnitt-Struktur
getrimmt (PR 28); ADR-0001 Smolitux Design Contract (PR 24) mit
Spiegel in smolitux-ui.

**Tests.** `cargo test` 382 passed; vier Avatar-Smokes
(`avatar-render-polish-smoke` 52 Assertions,
`avatar-expression-smoke`, `avatar-identity-smoke`,
`avatar-template-capabilities-smoke`) sowie
`settings-shell-smoke` (inkl. PR-26- und PR-27-Erweiterungen) und
`speech-sync-smoke` grün.

## 4. Workstream Status A–J

| WS | Status nach PR 30 | Nächster Schritt |
| --- | --- | --- |
| **A** Docs & Architecture Hygiene | PRs 20 / 21 / 24 / 28 / 29 gelandet; presence-Doc getrimmt, Glossar-Embryo / Reviews-Index vorhanden | Keine zwingende nahe Arbeit. PR 31 (dieser Checkpoint) selbst läuft hier ein. |
| **B** Window / Overlay / AOT | MVP lebt (Overlay + Click-through + X11-AOT); PR 22 hat den Dev-Host als GNOME/X11 bestätigt; echte Wayland-Messung bleibt externer Messauftrag | Warten auf verfügbaren Wayland-Host; keine Codearbeit |
| **C** Audio Pipeline v2 | STT: `command` + `whisper_cpp` (PR 27); TTS: `command` (unverändert) | Möglich: PR 34 — zweites TTS-Kind analog zu whisper_cpp (`piper_http` o. ä.), **command-basiert**, env-only |
| **D** Provider / Settings Consolidation | Provider-Onboarding UX v1 gelandet (PR 26); Quick-Action „Use local-first chain" verdrahtet; „Add cloud_http"-Button per Design disabled | Möglich: PR 36 — Settings-Shell-Cleanup nach Onboarding (z. B. visuelle Trennung Onboarding-Block ↔ Per-Kind-Editoren), **kein** Auto-Cloud |
| **E** Approval / Policy / Tool-Gating | Policy v0 gelandet (PR 25); Tripwire-Test fix; Approval-Kette real für `open_application` und — bei Opt-in — `focus_window` | **Offene Lücke:** Audit-Ring-Buffer deckt nur `plan_demo_action`; realer `open_application`-Lifecycle ist nicht auditiert. → PR 32 |
| **F** Desktop Interaction Layer | `focus_window` Reality Decision (PR 23) abgeschlossen; `type_text` / `send_shortcut` bleiben `BackendUnsupported` | Kein eigener F-PR nötig. Mögliche Folgearbeit: PR 37 — AT-SPI-RPC-Spike-Entscheidung (read-only Discovery) |
| **G** Avatar Animation / Stage C | Phase A + Phase B + Phase B Render Polish + **PR 30 Follow-up** live; `avatar_palette.gd` als Token-Andockpunkt; Stage C bleibt Research-Gate | Wartet auf Token-Export auf smolitux-ui-Seite (ADR-0001). Vorher kein sinnvoller G-PR in Smolit-Assistant |
| **H** ABrain Native Integration | Unverändert — ABrain weiterhin CLI | Möglich: PR 39 — ADR, der Native-API-Spike formalisiert, bevor Code gebaut wird |
| **I** Packaging / Release / CI | README + SETUP + .env.example gelandet (PR 29); weiterhin keine CI, keine Packaging-Formate | Möglich: PR 38 — erste minimale CI-Smoke-Linie (`cargo test` + `settings-shell-smoke` auf GitHub Actions), **kein** Release-Pipelineschuss |
| **J** Smolitux Design Contract | ADR-0001 gelandet (PR 24); `avatar_palette.gd` als Dock-Punkt aufbereitet; **keine** Token-Implementation | Möglich: PR 35 — Cross-Repo-Token-Contract-Prep in smolitux-ui (Docs/Schema only, kein Export-Build) |

## 5. Closed Items

- `focus_window` Endzustand entschieden (PR 23).
- Policy-v0-Baseline verdrahtet und tripwire-gelockt (PR 25).
- Provider-Onboarding-UX-Gap geschlossen (PR 26).
- STT-Zweit-Kind (`whisper_cpp`) gelandet (PR 27).
- `presence_desktop_interaction.md` vs. Ist-Zustand driftet nicht mehr (PR 28).
- README/SETUP/`.env.example`-Konsolidierung (PR 29).
- Avatar-Render-Polish-Follow-up inkl. Palette-Andockpunkt (PR 30).
- Cross-Repo Smolitux Design Contract ADR (PR 24, in beiden Repos).

## 6. Still Open Items

### 6.1 Audit-Lücke auf dem realen Interaction-Pfad

Audit-Ring-Buffer deckt ausschließlich den `plan_demo_action`-
Lifecycle. Der reale `open_application`-Approval-Flow
(planned / approval_requested / approval_resolved / started / step /
verification / completed / cancelled) wird **nicht** in den
Audit-Store geschrieben. Details:
[`PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./PR25_POLICY_V0_APPROVAL_DEFAULT.md)
§3. → **PR 32**.

### 6.2 Zwei Workflow-Overlays koexistieren

`Workflow-Overlay` (Phase 3.1) und `Workflow Visibility Overlay v1`
(PR 16) leben parallel — sauber abgegrenzt, aber verwirrend. Eine
Konsolidierungs-Entscheidung (entweder zusammenführen oder einen
formal deprecaten) wäre ehrlich. → **PR 33**.

### 6.3 Zweites TTS-Kind

TTS-Whitelist ist weiterhin `[command]`. Ein zweites Kind wäre eine
echte Fallback-Kette auch für die TTS-Achse. → **PR 34**.

### 6.4 Token-Contract-Seite auf smolitux-ui

ADR-0001 sieht Design Tokens vor, aber smolitux-ui hat das
Token-Schema noch nicht publiziert. Vor einem Import-Spike im
Smolit-Assistant braucht es auf der Web-Seite einen Vorschlag
(Schema, Export-Format, Namensraum). → **PR 35** (cross-repo
Docs-PR).

### 6.5 Settings-Shell-Cleanup nach Provider-Onboarding

Der PR-26-Onboarding-Block sitzt oberhalb der bestehenden Per-Kind-
Editoren. Die visuelle Hierarchie könnte klarer werden (z. B.
Section-Header, Kollapsierung alter Editoren). → **PR 36**, rein
UI-Cleanup, **keine** neuen IPC-Commands.

### 6.6 AT-SPI-RPC Entscheidung

Der Accessibility-Spike ist environment-basiert + hint-echo. Ein
`GetChildren` auf dem AT-SPI-Registry-Root wäre der nächste ehrliche
Schritt, um `confidence: verified` überhaupt emittieren zu können.
Wegen Wayland-Portal-Abhängigkeit und Toolkit-Fragmentierung ist das
eine **ADR-würdige Entscheidung** vor Codearbeit. → **PR 37**.

### 6.7 CI-Pipeline

Weiterhin keine CI. Eine minimale Smoke-Linie (`cargo test` +
`settings-shell-smoke`) als GitHub-Action wäre ein kleiner Schritt,
ohne sich auf Packaging-Formate festzulegen. → **PR 38**, bewusst
**keine** Release-/Signing-/Artifact-Upload-Stufe in diesem Schritt.

### 6.8 ABrain Native Integration ADR

CLI-Sprung pro Request bleibt teuer. Bevor Code gebaut wird, lohnt
sich ein ADR, der Native-API-Scope, Ownership der
API-Definition (Smolit-Assistant vs. ABrain) und Migration
festhält. → **PR 39**.

### 6.9 OceanData-Integration als eigenes ADR-Thema

OceanData ist heute **nicht** Teil des Smolit-Assistant-Stacks.
Mehrere Docs haben die Abgrenzung wiederholt (ADR-0001,
`README.md` §12, `GLOSSARY.md`), aber es gibt **kein** formales ADR
für eine *zukünftige* Anbindung. Sobald OceanData-Seitig ein Data-
Layer-Interface existiert, das Smolit-Assistant sinnvoll
konsumieren könnte, wäre ein ADR der ehrliche Startpunkt —
**nicht** ein Code-Spike. → **PR 40** (reines ADR-Thema, cross-repo
wenn nötig).

## 7. Risks / Drift Watchlist

Punkte, die in den nächsten Monaten am ehesten still driften könnten,
wenn niemand sie anschaut:

- **Audit-Story.** Solange §6.1 offen ist, ist „Smolit handelt
  nachvollziehbar" teilweise Marketing. Jeder künftige PR, der einen
  neuen realen Interaction-Kind einführt, sollte Audit mitfordern —
  PR 32 legt die Basis dafür.
- **TTS-Fallback-Monokultur.** Mit nur einem TTS-Kind (`command`)
  gibt es de facto keinen Fallback. Ein einzelner Command-Ausfall
  wirkt heute wie ein Feature-Ausfall.
- **Smolitux Token Drift.** ADR-0001 verspricht langfristige
  visuelle Konsistenz. Ohne Token-Contract auf smolitux-ui-Seite
  (PR 35) wandert die Smolit-Assistant-UI-Palette weiter als
  autonom geführte Konstanten-Sammlung.
- **`type_text` / `send_shortcut` Erwartungsdrift.** Die Flags
  bleiben in `InteractionConfig` sichtbar; ein neuer Nutzer könnte
  annehmen, dass `=true` genügt. Policy v0 + Docs benennen die
  Grenze, aber eine ADR („keine Eingabe-Injektion bis …") wäre
  robuster als ein Readme-Absatz.
- **CI-Lücke.** Ohne CI ist jeder grüne Build ein lokaler Build.
  PR 38 sollte minimal-invasiv kommen — sonst blockiert die
  Packaging-Frage den Einstieg.
- **OceanData-Begriffsunschärfe.** OceanData erscheint an mehreren
  Stellen als „nicht UI-Library / Data-Layer" — aber die positive
  Aussage, *was* OceanData ist, fehlt bislang (bewusst). Solange es
  kein ADR gibt, das den zukünftigen Berührungspunkt beschreibt,
  sollten Docs weiterhin nur abgrenzen, nicht annähern.
- **Wayland-Host-Abhängigkeit (Workstream B).** PR 22 hat den
  externen Messauftrag bestätigt, aber kein Timing gesetzt.
  Drift-Gefahr: die Tage werden immer gestern gewesen sein.

## 8. Recommended PR 32–40 Sequence

| PR | Workstream | Gegenstand (Kurzfassung) |
| --- | --- | --- |
| **32** | E | **Audit Coverage für realen `open_application`-Lifecycle.** Ring-Buffer (PR 19) auf die Real-Interaction-Kette ausweiten; Felder defensiv redacted; Tripwire-Test. Kein Persistenz-Pfad. |
| **33** | A | **Workflow-Overlay-Konsolidierungs-Entscheidung.** Entweder Merge der zwei Overlays oder formales Deprecaten des älteren Spike-Pfads. Docs + evtl. Smoke-Update, **keine** neue Feature-Fläche. |
| **34** | C | **Zweites TTS-Kind** (z. B. `piper_http`), command-basiert, env-only — analog zu whisper_cpp; Default bleibt `[command]`. |
| **35** | J | **Smolitux Token Contract Prep in smolitux-ui.** Cross-Repo-Docs-PR auf smolitux-ui-Seite: Schema-Vorschlag, Export-Format, Namensraum. **Kein** Export-Build, **kein** Import in Smolit-Assistant. |
| **36** | D | **Settings-Shell-UX-Cleanup** nach Provider-Onboarding (visuelle Hierarchie, Kollapsierung alter Editoren). Keine neuen IPC-Commands, keine Default-Änderung. |
| **37** | F | **Accessibility RPC Spike Decision (AT-SPI read-only).** ADR für einen echten `GetChildren`-Pfad auf Registry-Root; Toolkit-/Wayland-Fragmentierung benennen, entscheiden vor Code. |
| **38** | I | **Release/CI Foundation.** Minimale GitHub-Action mit `cargo test` + `settings-shell-smoke`. Kein Packaging, keine Signing. |
| **39** | H | **ABrain Native Integration ADR.** API-Scope, Ownership, Migration aus dem CLI-Pfad. Noch kein Code. |
| **40** | — | **OceanData Data-Layer Integration ADR** (cross-repo falls nötig). Beschreibt *hypothetischen* Anbindungsweg eines Data-Layers an Smolit-Assistant, ohne UI-Library-Rolle. Nur ADR, keine Implementation. |

Reihenfolge ist **nicht bindend**. Jede Priorisierungs-Änderung
wandert zuerst in `OPEN_WORK.md`, dann ggf. hier.

## 9. Explicitly Deferred (bleibt unverändert)

- Streaming-Audio / Audio-Timeline / Phonem-/Lip-Sync.
- Echte Desktop-Automation jenseits `open_application` +
  `focus_window`.
- `type_text` / `send_shortcut` Backends.
- Wayland-Fokus-Backend (braucht Compositor-nativen Pfad).
- AdminBot-Integration / Shell-Zugriff.
- Stage-C-Avatar-Assets / User-Uploads.
- Cloud-Provider als Default.
- Policy-Engine im „grand design"-Sinn.
- Audit-Persistenz / Audit-Export über den in-memory Ring-Buffer
  hinaus.
- Multi-Seat / Multi-User / kryptografische Signatur.
- Emotion-Feld in `response`-Payloads ohne Core-Signal.
- OceanData-Code-Integration (vor einem ADR → PR 40).

## 10. Verification

- `cargo test` (core/): **382 passed, 0 failed** — unverändert, da
  PR 31 Docs-only ist.
- `scripts/run_overlay_verification.sh settings-shell-smoke`:
  **PASS** (Sanity-Check).
- `rg "PR 24" ROADMAP.md docs/OPEN_WORK.md
  docs/reviews/PR31_ROADMAP_CHECKPOINT.md`: mehrere Treffer, alle
  konsistent als *PR 24 = Smolitux Design Contract ADR, gelandet*.
- `rg "PR 25"` in denselben Dateien: konsistent als *PR 25 = Policy
  v0, gelandet*.
- `rg "OceanData"` über ROADMAP/docs/README: jeder Treffer benennt
  OceanData als **Data-Layer**, **nicht** als UI-Library. Kein
  Trägereintrag impliziert eine Smolit-Assistant-Integration; das
  bleibt PR 40 vorbehalten.
- `rg "whisper_cpp"`: konsistent als PR-27-Eintrag; whisper.cpp ist
  externer Command-Adapter, keine Build-Abhängigkeit.
- `rg "focus_window"`: konsistent als „template-basierter X11-Backend
  mit doppeltem Opt-in, Wayland unsupported" (PR 23 + PR 25 Linie).
- `git diff`: nur Text-Dateien (kein Binär-Asset, kein Code-Eingriff).

## 11. Honesty Check

- ✅ Kein Workstream-Status hier behauptet Code, der nicht existiert.
- ✅ Alle „gelandet"-Markierungen verweisen auf tatsächliche Commits
  (PR 21–30 in `git log`).
- ✅ Die Audit-Lücke wird ehrlich als offen geführt (§6.1).
- ✅ OceanData wird ausschließlich als Data-Layer / nicht-UI-Library
  framed.
- ✅ Die vorgeschlagene PR-32–40-Reihe ist Vorschlag, kein
  Commitment — OPEN_WORK bleibt Single-Source für Priorisierung.
- ✅ Zielbild-Inhalte bleiben in §9 Explicitly Deferred, nicht in der
  PR-Tabelle.
