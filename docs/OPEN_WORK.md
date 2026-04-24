# Open Work — Smolit Assistant

> Single-Source für offene Arbeiten pro Workstream. Die
> [ROADMAP.md](../ROADMAP.md) verweist hierher. Pro Workstream:
> Status, Warum wichtig, Blocker, nächster kleinster PR,
> Nicht-Ziele, Tests / Verifikation. Ein-Datei-Format, damit Reviewer
> den gesamten „State of Open Work" in einem Scroll erfassen.

Stand: 2026-04-24 (nach PR 20 Docs Reality Check).

---

## A — Docs & Architecture Hygiene

**Status:** aktiv. PR 20 (Docs Reality Check), PR 24 (Smolitux Design
Contract ADR) und **PR 28 (2026-04-24) — `presence_desktop_interaction.md`
auf Ist-Zustand getrimmt (1096 → 491 Zeilen, 12-Abschnitt-Struktur,
Zielbild konsequent in Future Work / Non-goals isoliert)** sind
gelandet. Siehe
[`PR20_DOCS_REALITY_CHECK.md`](./reviews/PR20_DOCS_REALITY_CHECK.md)
und [`PR28_PRESENCE_DESKTOP_INTERACTION_TRIM.md`](./reviews/PR28_PRESENCE_DESKTOP_INTERACTION_TRIM.md).
**Warum wichtig:** Docs waren gegenüber dem Code gedriftet; zwei
Vokabularfamilien (Avatar-Phase A/B/B+/B++ vs. Roadmap-Phase 0–10)
kollidierten; zwei Workflow-Overlays koexistieren ohne Abgrenzung;
`presence_desktop_interaction.md` versprach Bewegungspfade, OCR,
Vision und breite Desktop-Automation, die im Code schlicht nicht
existierten. PR 28 hat diese Lücke geschlossen.
**Blocker:** keine; reine Docs-Arbeit.
**Nächster kleinster PR:** kein zwingender A-PR in der nahen Reihe.
PR 21 (tote Links, Reviews-Index, Glossar-Embryo) ist abgearbeitet;
PR 31 (Glossar fixieren) bleibt als Pflegepunkt in §6 der ROADMAP.

**Nicht-Ziele:**

- Keine neuen Features durch Doku-Änderungen.
- Keine Umbenennung bereits stabiler IPC-Types nur wegen Doku-
  Kosmetik.
- Keine automatisierten Markdown-Tooling-Setups in diesem Workstream
  (Over-Engineering).

**Tests / Verifikation:**

- `cargo test`, `scripts/run_overlay_verification.sh`-Suite bleibt
  grün.
- `grep`-Check auf „heute nicht implementiert" / „Ziel-Zustand" /
  „noch nicht" — jeder Treffer muss aktuell sein.

---

## B — Window / Overlay / Click-through / AOT Reality

**Status:** MVP gelandet (Overlay + Click-through + X11-AOT); echte
Wayland-Messungen offen. PR 22 (2026-04-24) hat bestätigt, dass
dieser Dev-Host weiterhin GNOME/X11 ist und kein nested Wayland-
Compositor (`weston` / `cage` / `labwc` / `sway` / `hyprland` /
`kwin_wayland`) installiert ist — echte Wayland-Messung bleibt ein
externer Messauftrag; der Refusal-Pfad ist per Env-Override-
Simulation am 2026-04-24 erneut reproduziert.
**Warum wichtig:** Die Versprechen der UI gegenüber dem User
(„Overlay möglich", „AOT nur X11") müssen auf realen Compositoren
verifiziert bleiben; Dev-Host ist GNOME/X11.
**Blocker:** separater Host mit Wayland-Compositor (Mutter /
wlroots) für Live-Messung. 2026-04-24 nochmals bestätigt — kein
nested-Wayland-Tool auf diesem Host verfügbar.
**Nächster kleinster PR:**

- **PR 22 B-Wayland-Live-Messung:** erledigt als ehrlicher
  Hostinventur-Eintrag in
  [`docs/wayland_always_on_top_refusal_results.md`](./wayland_always_on_top_refusal_results.md)
  §4.4 (2026-04-24). Ein realer Wayland-Messlauf bleibt als
  externer Messauftrag ausstehend und wird in §4 desselben
  Dokuments als neuer Block ergänzt, sobald ein Host verfügbar ist.

**Nicht-Ziele:**

- Keine GNOME-Shell-Extension.
- Keine Wayland-spezifischen AOT-Tricks (AOT bleibt X11-only).
- Kein wlroots-spezifischer Code ohne vorherigen Spike.

**Tests / Verifikation:**

- `scripts/run_overlay_verification.sh resolver-wayland-*`-Cases
  bleiben grün.
- Neue Messdaten werden mit Host-/Session-Tag dokumentiert.

---

## C — Audio Pipeline v2

**Status:** STT hat seit PR 27 (2026-04-24) **zwei** produktive Kinds
(`command`, `whisper_cpp`), beide command-basiert; TTS bleibt bei
einem Kind (`command`). TTS-Lifecycle-Events aus PR 14 liegen
unverändert vor. Keine Streaming-Audio-Pipeline.
**Warum wichtig:** Die Fallback-Kette `["whisper_cpp", "command"]`
ist jetzt real nutzbar — der Resolver spiegelt `active=command` /
`availability=fallback_active`, wenn whisper.cpp nicht konfiguriert
ist oder fehlschlägt. Ehrliche Tests decken beide Pfade.
**Blocker:** keiner; der Provider-Resolver aus PR 6/13 nimmt
whisper_cpp jetzt als vollwertiges Chain-Kind.
**Nächster kleinster PR:** kein zwingender C-PR in der nahen Reihe.
Mögliche Folgearbeit (ohne Priorität): zweites TTS-Kind (z. B.
`piper_http` analog zu whisper_cpp, command-basiert), oder ein
zweites STT-Kind mit anderer Spawn-Semantik (z. B. `http_local`
STT). Beides ist **nicht** Teil der nahen Reihe.

**Nicht-Ziele:**

- Kein Streaming-Audio, kein Phonem-/Lip-Sync, keine Audio-
  Timeline (explicitly deferred).
- Keine Cloud-STT/-TTS-Provider als Default.
- Kein neuer Audio-Subsystem-Stack — bestehender
  `core/src/audio/` bleibt.
- Keine Build-Abhängigkeit auf whisper.cpp; das Kind bleibt
  external-command-based.
- Kein Modell-/Download-Manager in PR 27.
- Kein Runtime-Editor für `SMOLIT_STT_WHISPER_CPP_CMD` —
  Kommando ist env-only.

**Tests / Verifikation:**

- `core/src/providers/stt.rs`: elf neue PR-27-Tests, u. a.
  `validate_stt_chain_accepts_whisper_cpp_kind`,
  `whisper_cpp_primary_without_command_reports_unavailable`,
  `fallback_chain_whisper_cpp_then_command_uses_command_when_whisper_cpp_missing`.
- Chain-Validator-Test (Whitelist, Duplikate, Empty-Reject) deckt
  das neue Kind ab.
- `speech-sync-smoke` und `settings-shell-smoke` bleiben grün;
  letzterer erhält sechs neue PR-27-Checks.

---

## D — Provider / Settings Consolidation

**Status:** 4 Text-Kinds wählbar (abrain / llamafile_local /
local_http / cloud_http); Settings-Shell zeigt alle als editierbare
Per-Kind-Blöcke (PR 5/7/8/10/11) plus Chain-Editor (PR 9/13);
cloud_http funktioniert mit API-Key aus Secrets-Store. PR 26
(2026-04-24) liefert zusätzlich einen kuratierten **Provider-
Onboarding-Block** oberhalb der Editoren: Primary + Chain mit
Lokalitäts-Tags, cloud_http-First-Run-Checklist und eine einzige
Quick-Action „Use local-first chain" (sendet den bestehenden
`settings_set_text_provider_chain`-Command mit
`["llamafile_local","local_http","abrain"]`, kein cloud_http).
**Warum wichtig:** Die UX war dev-orientiert — neue Nutzer konnten
kaum erkennen, was primary ist, was lokal bleibt und was cloud_http
vor dem First-Run noch braucht. PR 26 beantwortet das im Readout,
ohne Defaults zu ändern.
**Blocker:** keine; rein Produkt-/UX-Arbeit.
**Nächster kleinster PR:** kein zwingender D-PR in der nahen Reihe.
Mögliche Folgearbeit (ohne Priorität): `Add cloud_http to chain` von
per-Design-disabled auf kontrollierten Klick umstellen; dafür müsste
eine bewusste „ich nehme Cloud in Kauf"-Confirmation-UX kommen, die
in PR 26 ausdrücklich *nicht* gebaut ist.

**Nicht-Ziele:**

- Keine Änderung des Compile-Time-Defaults `["abrain"]`.
- Keine Auto-Cloud-Aktivierung.
- Keine neuen Provider-Kinds.
- Keine neuen IPC-Commands durch PR 26 — der Block reutilisiert das
  bestehende Settings-Protokoll.
- Keine API-Key-Anzeige (`cloud_http_secret_present` bleibt Boolean-
  only in allen Readouts).

**Tests / Verifikation:**

- `settings-shell-smoke` bleibt grün; PR 26 ergänzt acht Checks im
  selben Harness (`_check_onboarding_*`), inkl. einer expliziten
  „kein Wert für den API-Key"-Invariante.
- Der bestehende `probe`-Pfad (Llamafile / local_http / cloud_http)
  wird weiterhin genutzt; keine Änderung der Probe-Semantik.

---

## E — Approval / Policy / Tool-Gating

**Status:** Approval-UX v1 (PR 17) + Approval-Gated Demo Action
Planner (PR 18) + Policy v0 (PR 25, 2026-04-24) vollständig. Die
Default-Config zwingt jede echte Interaction-Action mit
`requires_confirmation=true` durch den Approval-Pfad; das ist
heute real nur `open_application`, beim doppelten Opt-in auch
`focus_window`. `type_text` / `send_shortcut` bleiben ohne Backend
und damit außerhalb der Policy-Oberfläche.
**Warum wichtig:** Die Sicherheitsaussage „Smolit handelt nur nach
expliziter Zustimmung" ist nun real verdrahtet — kein Demo-only-
Pfad mehr. Der Tripwire-Test `policy_v0_defaults_are_locked` in
[`core/src/config.rs`](../core/src/config.rs) schlägt an, wenn
jemand die Baseline flippt.
**Blocker:** keine.
**Nächster kleinster PR:** Kein eigener E-PR in der nahen Reihe.
Folge-Arbeiten (neue Real-Interaction-Kinds, Audit-Abdeckung des
`open_application`-Lifecycles, feinere Risk-Klassifikation) sind
bewusst noch nicht priorisiert — jede davon würde eine eigene
Design-Entscheidung brauchen.

**Nicht-Ziele:**

- Keine Policy-Engine im „grand design"-Sinn.
- Keine Multi-Seat- oder Audit-Persistenz-Features.
- Keine Erweiterung des Demo-Executor-Set um Kinds mit echten
  Seiteneffekten.
- **Kein `type_text` / `send_shortcut`-Backend** als Folgeschritt —
  solche Fähigkeiten bräuchten eigene ADR-/Policy-Runde.
- **Keine automatische Ausweitung des Audit-Ring-Buffers** auf den
  realen `open_application`-Pfad; heute deckt Audit ausschließlich
  den `plan_demo_action`-Lifecycle ab. Siehe
  [`docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md).

**Tests / Verifikation:**

- `policy_v0_defaults_are_locked` und
  `policy_v0_parse_bool_with_no_env_uses_locked_defaults` in
  [`core/src/config.rs`](../core/src/config.rs).
- Bestehende Core-/IPC-Tests `approval_approved_produces_completed_via_broadcast`,
  `approval_denied_produces_cancelled`,
  `approval_timeout_produces_cancelled`,
  `focus_window_disallowed_emits_failed`,
  `focus_window_without_backend_template_emits_unsupported`,
  `focus_window_with_template_emits_verification_and_completed`.

---

## F — Desktop Interaction Layer

**Status:** `open_application` real; `focus_window` real als
template-basierter X11-Backend-Pfad (`CommandBackend`,
`SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`, z. B. `wmctrl -a {name}`) —
ohne Template und/oder unter Wayland honest
`BackendUnsupported("focus_window")`, Verification bewusst
`uncertain`; `type_text` / `send_shortcut` bleiben
`BackendUnsupported` im `CommandBackend`. Accessibility-Probe +
Discovery antworten ehrlich mit `unavailable` / `uncertain`.
PR 23 (2026-04-24) hat `focus_window` als Option 1 bestätigt —
keine Entfernung, keine Erweiterung; Details in
[`docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`](./reviews/PR23_FOCUS_WINDOW_DECISION.md).
**Warum wichtig:** Halbfertige Interaction-Kinds dürfen nicht
Fähigkeit signalisieren, die nicht existiert — `focus_window` ist
jetzt final als „template opt-in, sonst ehrlich unsupported"
gesetzt; `type_text` / `send_shortcut` bleiben bewusst
stub-unterstützt ohne Backend.
**Blocker:** keine technischen Blocker; weitere Interaction-Kinds
(`type_text` / `send_shortcut`) brauchen eine eigene Policy-
Entscheidung vor Backend-Arbeit.
**Nächster kleinster PR:**

- **Kein eigener F-PR in der nahen Reihe.** `focus_window` ist mit
  PR 23 abgeschlossen; die offene Next-Step-Arbeit ist Workstream E
  (Policy v0, PR 25, gelandet). `type_text` / `send_shortcut`
  bekommen auch nach Policy v0 **keinen** Backend-Pfad — die
  Default-Flags bleiben `false` und das Backend meldet
  `BackendUnsupported`.

**Nicht-Ziele:**

- Kein `type_text` / `send_shortcut` Backend, solange Policy-
  Gating (Workstream E) nicht verdrahtet ist.
- Keine AT-SPI-RPC-Integration (das ist eigener Spike).
- Keine Wayland-Fokus-Lösung (kein generisches Protokoll-Primitiv;
  Core verspricht unter Wayland weiterhin keinen Fokuswechsel).
- Keine Fokus-Probe (Verification bleibt `uncertain`).

**Tests / Verifikation:**

- Bestehende Core-Tests decken alle Zweige ab:
  `focus_window_disallowed_emits_failed`,
  `focus_window_without_backend_template_emits_unsupported`,
  `focus_window_with_template_emits_verification_and_completed`,
  plus vier Backend-Direkt-Tests (ohne Template, ohne Ziel, mit
  `/bin/true`, mit `/bin/false`) und fünf IPC-Server-End-to-End-
  Tests (disallowed, unsupported ohne Template, success, application-
  target-Mapping, Approval-Flow).
- Keine UI-Referenzen (rg auf `ui/` liefert null Treffer), daher
  keine neue Smoke-Rolle nötig.

---

## G — Avatar Animation / Stage C Research

**Status:** Phase A (Smolit), Phase B (kuratierte Alternativen),
Phase B-Render-Polish und PR-15-Behavioral-Expression-Layer sind
live. Stage C ist explizit Research-Gate
([`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md)).
**Warum wichtig:** Stage-C wäre User-Upload-Territorium; ohne
sauberes Sicherheits-/Trust-Modell nicht machbar.
**Blocker:** Sicherheits-Hierarchie + Manifest-Format noch nicht
entschieden.
**Nächster kleinster PR:**

- **PR 30 G-Avatar-Render-Polish-Follow-up** *(verschoben von PR 28
  → PR 30 nach PR-28 Presence-Trim und PR-29-Swap mit README-Setup):*
  rein visuelle Feinarbeit auf den existierenden kuratierten
  Identities; *keine* Asset-Imports.

**Nicht-Ziele:**

- Kein User-Upload, keine User-supplied Identities.
- Keine Asset-Pipeline, keine Manifest-Parser.
- Keine neue State-Ebene über dem Expression-Layer.

**Tests / Verifikation:**

- `avatar-render-polish-smoke` und
  `avatar-template-capabilities-smoke` bleiben grün.
- Identitätsgarantie (Default-Smolit unverändert) bleibt bindend.

---

## H — ABrain Native Integration

**Status:** ABrain läuft als externer CLI-Prozess
(`SMOLIT_ABRAIN_CMD`). Die Native-API-Beschreibung in
[`docs/api.md §5`](./api.md) ist Ziel-Zustand.
**Warum wichtig:** CLI-Sprung bei jedem Prompt ist teuer; Streaming-
Response und Tool-Calls sind nur mit nativer API machbar.
**Blocker:** ABrain-Roadmap-seitige Entscheidung. Keine Core-
seitigen technischen Blocker.
**Nächster kleinster PR:**

- Keine Priorität in PR 21–30. Pflegepunkt.

**Nicht-Ziele:**

- Keine Tool-Call-Engine in Smolit, bevor die ABrain-Seite
  geklärt ist.
- Keine Emotion-Felder in `response` ohne Core-Signal.

**Tests / Verifikation:**

- Bestehender `abrain`-Provider-Test-Pfad (CLI-Echo) bleibt grün.

---

## I — Packaging / Release / CI

**Status:** README + Setup-Guide + `.env.example` landen mit
**PR 29 (2026-04-24, gelandet)**:
[`README.md`](../README.md) (13-Abschnitt-Struktur, 5–10 min
Quickstart) + [`docs/SETUP.md`](./SETUP.md) (ausführliche
Env-Gruppen + Troubleshooting) + aktualisiertes
[`.env.example`](../.env.example). Keine CI-Pipeline, kein
Packaging-Format — das bleibt eigener Folge-PR.
**Warum wichtig:** Ohne reproduzierbaren Build-Pfad kein Nutzer-Test.
PR 29 schließt die Einstiegs-Lücke, ohne Installations-Skripte
einzuführen.
**Blocker:** unklar, welche Ziel-Distributionen (Ubuntu 24.04 gesetzt;
Fedora / Arch / NixOS offen) und welches Tooling (GitHub Actions vs.
Self-Host) gelten sollen.
**Nächster kleinster PR:** kein zwingender I-PR in der nahen Reihe.
Mögliche Folgearbeit (ohne Priorität): eine kleine CI-Smoke-Linie
(cargo test + settings-shell-smoke) als GitHub-Action, falls das
Tooling-Frage beantwortet ist.

**Nicht-Ziele:**

- Keine Package-Manager-Pakete (deb/rpm/flatpak) in diesem Schritt.
- Keine GitHub-Actions-CI; Entscheidung Tooling separat.
- Keine Cloud-Build-Pipeline.
- Keine Install-Skripte — PR 29 dokumentiert ausschließlich.

**Tests / Verifikation:**

- `cargo test` grün (382 Tests inkl. Policy-v0-Tripwire und
  whisper_cpp-Fallback).
- `scripts/run_overlay_verification.sh settings-shell-smoke`
  bestätigt UI-Einstiegspfad.
- README/SETUP wurden auf einem frischen Dev-Host manuell
  durchgelesen; die dort dokumentierte Quick-Start-Sequenz spiegelt
  den tatsächlichen Build-Pfad.

---

## J — Smolitux Design Contract / Cross-Runtime UI Consistency

**Status:** neu, Docs/ADR-only. Eingeführt mit dem Cross-Repo-ADR
in [`docs/adr/ADR-0001-smolitux-design-contract.md`](./adr/ADR-0001-smolitux-design-contract.md)
und einem Spiegel-ADR in
[smolitux-ui](https://github.com/Modularium/smolitux-ui).

**Warum wichtig:** Smolit-Assistant soll visuell und semantisch ins
Smolitux-Ökosystem passen, ohne Godot mit React oder einer WebView
zu koppeln. Ohne expliziten Kopplungsvertrag driftet die UI
entweder in eine Eigen-Sprache oder versucht eine unmögliche
React-Godot-Brücke.

**Blocker:** Token-Format und Export-Pipeline in smolitux-ui sind
noch nicht entschieden. Bis dahin ist auf Smolit-Assistant-Seite
nur die ADR-Ebene machbar, keine Implementation.

**Nächster kleinster PR:**

- **PR 24 J-Cross-Repo-ADR:** ADR-0001 in diesem Repo +
  Spiegel-ADR in smolitux-ui; ROADMAP/OPEN_WORK/GLOSSARY/
  `ui_architecture.md` um den Design-Contract-Orientierungsblock
  ergänzen. **Reiner Docs-PR**, keine Code-Änderungen.

**Nicht-Ziele:**

- Keine Token-Implementation.
- Keine Theme-Generatoren.
- Kein React in Godot.
- Kein WebView.
- Keine neuen Packages in diesem Repo.
- Keine UI-Refactors.
- Keine Core-Abhängigkeit.
- **Keine OceanData-Änderungen.** OceanData ist Data-Layer /
  Datenplattform und nicht Quelle des Smolitux-Design-Systems;
  dieser Workstream bearbeitet OceanData nicht.

**Tests / Verifikation:**

- Markdown-Links im Repo ([`docs/adr/`](./adr/), ROADMAP,
  OPEN_WORK, GLOSSARY, `ui_architecture.md`) sind konsistent.
- Keine Code-Änderungen.
- `cargo test` und `scripts/run_overlay_verification.sh`
  optional unverändert grün, falls ausgeführt.
- `rg "OceanData" docs README.md ROADMAP.md` liefert keine
  Treffer, die OceanData als UI-Library oder Design-System-Quelle
  darstellen.

---

## Query-Checklist beim Review

Vor jedem Feature-PR folgende Query durchlaufen:

1. Berührt der PR einen Workstream oben? Falls ja: nächster
   kleinster Schritt ist dort dokumentiert.
2. Erweitert der PR den Scope in einen Explicitly-Deferred-Bereich
   (siehe [`ROADMAP.md §7`](../ROADMAP.md))? Falls ja:
   Sonderabstimmung nötig.
3. Trifft der PR eine der expliziten Nicht-Ziele dieses Workstreams?
   Falls ja: entweder rechtfertigen oder Scope kürzen.
4. Ist die Dokumentation *vor* dem Feature angepasst? Falls nein:
   PR rutscht in den A-Workstream.

---

## Historische Ablage

Detaillierte PR-Erzählungen aus der alten `ROADMAP.md` liegen in
[`docs/reviews/`](./reviews/):

- `phase-3-avatar-ui_inventory.md` — Phase-3-UI-Inventory.
- `phase-3-avatar-ui_review.md` — Phase-3-UI-Review.
- `PR20_DOCS_REALITY_CHECK.md` — dieser PR.

Für zukünftige PRs: Details in `docs/reviews/PR<N>_*.md`,
Entscheidungen in der jeweiligen `docs/`-Architekturdatei, Status
hier in `OPEN_WORK.md`.
