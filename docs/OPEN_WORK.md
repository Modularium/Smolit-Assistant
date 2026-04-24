# Open Work — Smolit Assistant

> Single-Source für offene Arbeiten pro Workstream. Die
> [ROADMAP.md](../ROADMAP.md) verweist hierher. Pro Workstream:
> Status, Warum wichtig, Blocker, nächster kleinster PR,
> Nicht-Ziele, Tests / Verifikation. Ein-Datei-Format, damit Reviewer
> den gesamten „State of Open Work" in einem Scroll erfassen.

Stand: 2026-04-24 (nach PR 20 Docs Reality Check).

---

## A — Docs & Architecture Hygiene

**Status:** aktiv, läuft durch PR 20.
**Warum wichtig:** Docs waren gegenüber dem Code gedriftet; zwei
Vokabularfamilien (Avatar-Phase A/B/B+/B++ vs. Roadmap-Phase 0–10)
kollidierten; zwei Workflow-Overlays koexistieren ohne Abgrenzung;
ROADMAP war 1 811 Zeilen PR-Log. Siehe
[`PR20_DOCS_REALITY_CHECK.md`](./reviews/PR20_DOCS_REALITY_CHECK.md).
**Blocker:** keine; reine Docs-Arbeit.
**Nächster kleinster PR:**

- **PR 21 A-Docs Follow-up:** tote Links im gesamten Repo
  reparieren, `docs/reviews/`-Index anlegen, Glossar-Embryo
  starten (`Approval`, `Audit`, `Workflow-Overlay`, `Presence`,
  `Expression`, `Action Event`).

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
Wayland-Messungen offen.
**Warum wichtig:** Die Versprechen der UI gegenüber dem User
(„Overlay möglich", „AOT nur X11") müssen auf realen Compositoren
verifiziert bleiben; Dev-Host ist GNOME/X11.
**Blocker:** separater Host mit Wayland-Compositor (Mutter /
wlroots) für Live-Messung.
**Nächster kleinster PR:**

- **PR 22 B-Wayland-Live-Messung:** ein Messlauf auf einem realen
  Wayland/GNOME-Host; Ergebnisse in
  [`docs/wayland_always_on_top_refusal_results.md`](./wayland_always_on_top_refusal_results.md)
  ergänzen (nicht simulativ).

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

**Status:** command-basierter Ein-Kind-Provider pro Achse (TTS/STT);
keine Streaming-Audio-Pipeline; TTS-Lifecycle-Events aus PR 14
liegen vor.
**Warum wichtig:** Die Audio-Achsen sind real einsetzbar, aber eng
— ein zweites Kind je Achse macht die Fallback-Kette glaubhaft.
**Blocker:** keiner; der Provider-Resolver aus PR 6/13 akzeptiert
neue Kinds additiv.
**Nächster kleinster PR:**

- **PR 26 C-STT-Alternative:** `whisper.cpp` als zweites
  `STT`-Kind. Weiterhin command-basiert, keine Binär-Abhängigkeit
  im Core-Build.

**Nicht-Ziele:**

- Kein Streaming-Audio, kein Phonem-/Lip-Sync, keine Audio-
  Timeline (explicitly deferred).
- Keine Cloud-STT/-TTS-Provider als Default.
- Kein neuer Audio-Subsystem-Stack — bestehender
  `core/src/audio/` bleibt.

**Tests / Verifikation:**

- Neue Kind-Konstante in `core/src/providers/stt.rs::KNOWN_STT_KINDS`.
- Chain-Validator-Test (Whitelist, Duplikate, Empty-Reject) deckt
  das neue Kind ab.
- `speech-sync-smoke` bleibt grün.

---

## D — Provider / Settings Consolidation

**Status:** 4 Text-Kinds wählbar (abrain / llamafile_local /
local_http / cloud_http); Settings-Shell zeigt alle als read-only
Readout; cloud_http funktioniert mit API-Key aus Secrets-Store.
**Warum wichtig:** Die UX ist heute Dev-orientiert — ein First-Run-
Pfad für cloud_http ist nicht kuratiert; Default-Ketten sind
konservativ auf `["abrain"]`.
**Blocker:** keine technischen; rein Produkt-Entscheidung.
**Nächster kleinster PR:**

- **PR 25 D-Provider-Onboarding-UX:** beim ersten Start eine
  kuratierte Default-Ketten-Auswahl (ohne Core-Default zu ändern);
  cloud_http-API-Key-Onboarding in der Settings-Shell ehrlicher
  labeln.

**Nicht-Ziele:**

- Keine Änderung des Compile-Time-Defaults `["abrain"]`.
- Keine Auto-Cloud-Aktivierung.
- Keine neuen Provider-Kinds.

**Tests / Verifikation:**

- `settings-shell-smoke` bleibt grün.
- Der bestehende `probe`-Pfad (Llamafile / local_http / cloud_http)
  wird weiterhin genutzt; keine Änderung der Probe-Semantik.

---

## E — Approval / Policy / Tool-Gating

**Status:** Approval-UX v1 (PR 17) + Approval-Gated Demo Action
Planner (PR 18) vollständig; **real verdrahtet** ist die Kette
nur auf dem Demo-Pfad — keine echte Core-Aktion ist durch
Approval *gesperrt*, bis der User entschieden hat. Der Interaction-
Executor ruft den Approval-Pfad für `open_application` bereits auf,
wenn `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=1`.
**Warum wichtig:** Die Sicherheitsaussage „Smolit handelt nur nach
expliziter Zustimmung" braucht eine reale Verdrahtung, nicht nur
eine Demo.
**Blocker:** keine technischen; Design-Entscheidung „welche
Aktionen werden standardmäßig gated".
**Nächster kleinster PR:**

- **PR 24 E-Policy-v0:** `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=1`
  dokumentieren und als empfohlenen Default für produktive Builds
  kennzeichnen; keine neue Policy-Engine, nur ein Schritt in
  Richtung realer Gating-Verdrahtung.

**Nicht-Ziele:**

- Keine Policy-Engine im „grand design"-Sinn.
- Keine Multi-Seat- oder Audit-Persistenz-Features.
- Keine Erweiterung des Demo-Executor-Set um Kinds mit echten
  Seiteneffekten.

**Tests / Verifikation:**

- Bestehende Core-Tests `approval_approved_produces_completed_via_broadcast`
  etc. bleiben grün.
- Neuer Test für den Default-Confirmation-Pfad, falls der Default
  tatsächlich geändert wird.

---

## F — Desktop Interaction Layer

**Status:** `open_application` real; `focus_window` / `type_text` /
`send_shortcut` sind `BackendUnsupported` im `CommandBackend`.
Accessibility-Probe + Discovery antworten ehrlich mit
`unavailable` / `uncertain`.
**Warum wichtig:** Halbfertige Interaction-Kinds signalisieren
Fähigkeit, die nicht existiert. Entweder als Spike umsetzen oder
sauber entfernen.
**Blocker:** reale Wayland/X11-WM-Abhängigkeit für `focus_window`
(wmctrl / swaymsg / AT-SPI).
**Nächster kleinster PR:**

- **PR 23 F-focus_window-Spike:** entweder reale `wmctrl`-Verdrahtung
  **hinter** Policy-Gating oder ehrliche Entfernung der
  `BackendUnsupported`-Variante. Entscheidung dokumentieren.

**Nicht-Ziele:**

- Kein `type_text` / `send_shortcut` in diesem Schritt.
- Keine AT-SPI-RPC-Integration (das ist eigener Spike).
- Kein parallel-WM-Backend-Pfad.

**Tests / Verifikation:**

- Neuer `tokio::test` für `focus_window`-Pfad, falls verdrahtet.
- Harness-Case in `scripts/run_overlay_verification.sh`, falls UI
  beteiligt ist.

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

- **PR 28 G-Avatar-Render-Polish-Follow-up:** rein visuelle
  Feinarbeit auf den existierenden kuratierten Identities; *keine*
  Asset-Imports.

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

**Status:** kein Release-Pfad dokumentiert, keine CI-Pipeline im
Repo.
**Warum wichtig:** Ohne reproduzierbaren Build kein Nutzer-Test.
**Blocker:** unklar, welche Ziel-Distributionen unterstützt
werden sollen.
**Nächster kleinster PR:**

- **PR 29 I-README-Build-Setup:** erste reale Install-Anleitung
  (`cargo build`, Godot-Version, `SMOLIT_*`-Mindest-Env-Set).

**Nicht-Ziele:**

- Keine Package-Manager-Pakete (deb/rpm/flatpak) in diesem Schritt.
- Keine GitHub-Actions-CI; Entscheidung Tooling separat.
- Keine Cloud-Build-Pipeline.

**Tests / Verifikation:**

- Neue README-Anleitung wird auf einem frischen Dev-Host getestet
  (manuell, dokumentiert).

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
