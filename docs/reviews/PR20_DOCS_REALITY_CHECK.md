# PR 20 — Documentation Reality Check

> Review date: 2026-04-24. Scope: PR 14–PR 19 gelandet; keine neuen
> Features in diesem PR. Leitprinzip: **Stop feature drift. Rebase
> documentation on reality.**

---

## 1. Executive Summary

Die Implementation ist stabil (369 Core-Tests grün; 16 UI-Smokes
grün). Die Dokumentation ist gewachsen, aber nicht mehr navigierbar
und trägt mehrere ehrliche Widersprüche.

Die drei Kernprobleme:

1. **ROADMAP.md ist zum PR-Changelog mutiert.** 1 811 Zeilen, je PR
   ein langer Absatz. Eine echte Roadmap ist nicht mehr in zwei
   Minuten erfassbar.
2. **Zwei Workflow-Overlay-Komponenten laufen parallel** (alt:
   `workflow_overlay`; neu: `workflow_visibility_panel` aus PR 16).
   Beide sind im Code; beide sind in `ui_architecture.md`
   dokumentiert. Die Beziehung ist nirgends klar formuliert.
3. **Veraltete „Ziel-Zustand"-Aussagen** in `api.md` und
   `ui_architecture.md`: Features, die längst implementiert sind,
   werden stellenweise noch als offen beschrieben (oder umgekehrt).

Keine Sicherheits-/Fähigkeits-Drift gefunden: der Core bleibt
Mock-only in den gefährlichen Pfaden (Desktop-Automation, Shell,
AdminBot, Provider-Mutationen). Die Audit-Schicht ist tatsächlich
in-memory-only. Die Approval-Gating-Kette ist ausschließlich auf
dem PR-18-Demo-Pfad ausgeführt — keine echte Policy-Integration.

Dieser Report empfiehlt **drei Docs-Only-Commits** plus eine
Folge-Reihenfolge von kleinen PRs (PR 21–PR 30) als Vorschlag für
die nächste Arbeitswelle.

---

## 2. Tatsächlicher Code-Ist-Zustand

### 2.1 Core (Rust)

Module (alle unter `core/src/`):

| Modul | Inhalt |
|-------|--------|
| `actions/` | `event.rs` (Action-Event-Modell v1), `plan.rs` (DemoPlan, PR 18), `mapping.rs`, `target.rs` |
| `app.rs` | Orchestrator, Event-Broadcast, Approval-Registry, Audit-Store |
| `approvals/` | `request.rs` (ApprovalRequest mit `risk`, PR 17), `response.rs`, `state.rs` (PendingApprovalRegistry) |
| `audio/` | Shared Audio-Types |
| `audit/` | `event.rs` (AuditEvent, AuditKind, PR 19), `store.rs` (Ring-Buffer) |
| `config.rs` | 35+ `SMOLIT_*` Env-Variablen |
| `event_loop.rs` | CLI-REPL |
| `interaction/` | InteractionExecutor + CommandBackend; FocusWindow/TypeText/Shortcuts sind **BackendUnsupported** (MVP) |
| `ipc/` | `protocol.rs` (34 Incoming, 24 Outgoing Varianten), `server.rs` |
| `providers/` | `text.rs` (`abrain`, `llamafile_local`, `local_http`, `cloud_http`), `stt.rs`, `tts.rs` (jeweils nur `command`) |
| `secrets_store.rs` | Cloud-API-Key-Persistenz (0600) |
| `settings_store.rs` | JSON-Persistenz pro Provider-Axis |

**Core-Tests:** 369 PASS, 0 FAIL.

### 2.2 IPC Incoming Commands (34 Varianten, aktueller Wire-Stand)

Gruppiert nach Thema:

- **Grundpfad:** `ping`, `get_status`, `submit_text`, `speak_text`,
  `voice_once`
- **Interaction MVP:** `interaction_open_application`,
  `interaction_focus_window`, `interaction_probe_accessibility`,
  `interaction_discover_accessibility`,
  `interaction_select_target`, `interaction_clear_target`
- **Approval-UX (PR 17):** `approval_response`,
  `approval_approve`, `approval_deny`, `request_approval_demo`
- **Approval-Gated Plans (PR 18):** `plan_demo_action`
- **Audit (PR 19):** `audit_recent`
- **Settings:** `settings_set_llamafile_config`,
  `settings_probe_llamafile`, `settings_set_stt_config`,
  `settings_set_tts_config`, `settings_probe_stt`,
  `settings_probe_tts`, `settings_set_local_http_config`,
  `settings_probe_local_http`, `settings_set_text_provider_chain`,
  `settings_reset_text_provider_chain`,
  `settings_set_cloud_http_config`,
  `settings_set_cloud_http_secret`, `settings_probe_cloud_http`,
  `settings_set_stt_provider_chain`,
  `settings_reset_stt_provider_chain`,
  `settings_set_tts_provider_chain`,
  `settings_reset_tts_provider_chain`

### 2.3 IPC Outgoing Envelopes (24 Varianten)

- **Transport-Grund:** `pong`, `status`, `thinking`, `response`,
  `heard`, `error`
- **Action Events:** `action_planned`, `action_started`,
  `action_step`, `action_completed`, `action_failed`,
  `action_cancelled`, `action_progress` **(reserviert, noch nicht
  emittiert)**, `action_verification`
- **Approval:** `approval_requested` (mit `risk`, PR 17),
  `approval_resolved` (mit `source`, PR 17)
- **TTS-Lebenszyklus (PR 14):** `speaking_started`,
  `speaking_ended`
- **Audit (PR 19):** `audit_recent`
- **Accessibility (Spike):** `accessibility_probe_result`,
  `accessibility_discovery_result`
- **Target Selection:** `target_selected`, `target_cleared`
- **Settings:** `settings_probe_result`

### 2.4 UI (Godot)

- **Autoloads (3):** `EventBus`, `IpcClient`, `MCPRuntime`
- **EventBus-Signale (26):** vollständige Spiegelung aller
  relevanten Outgoing-Envelopes plus `ipc_connected` /
  `ipc_disconnected`.
- **IpcClient-Helper (33+):** jede schmale Wire-Form hat einen
  eigenen Helper; älterer `send_approval_response` bleibt neben
  `approval_approve` / `approval_deny`.
- **Scenes (9):** `main.tscn` + `avatar_root`, `utterance_bubble`,
  `workflow_overlay_root` (alter 3-Knoten-Spike),
  `workflow_visibility_panel` (PR 16), `approval_card` (PR 17),
  `audit_panel` (PR 19), `settings_panel`, `dev_controls_panel`.
- **Scripts:** rund 60 `.gd`-Dateien, gruppiert nach Feature
  (avatar/, approval/, audit/, dev_controls/, presence/,
  settings/, utterance/, window_behavior/, workflow/,
  workflow_overlay/).
- **Dev-Controls-Sections (6):** Avatar-Appearance, Avatar-
  Expression-Preview, Visual-Action-Mode, Workflow-Visibility-
  Toggle, Approval-Demo, Plan-Demo-Action — alle hinter
  `SMOLIT_UI_DEV_CONTROLS=1`.

### 2.5 Harness (16 Smokes, alle PASS)

`resolver-smoke`, `workflow-state-smoke`, `avatar-appearance-smoke`,
`dev-controls-smoke`, `avatar-preferences-smoke`,
`avatar-identity-smoke`, `avatar-template-capabilities-smoke`,
`utterance-bubble-smoke`, `speech-sync-smoke`,
`avatar-expression-smoke`, `workflow-visibility-smoke`,
`audit-panel-smoke`, `approval-card-smoke`,
`avatar-render-polish-smoke`, `settings-shell-smoke`,
`visual-action-mode-smoke`.

### 2.6 Security- / Approval- / Audit-Bausteine

- **Approval-Kanal:** Loopback-WebSocket, `PendingApprovalRegistry`
  enforced Idempotenz (Double-Approve → `error`-Frame).
- **Gating:** `plan_demo_action` + Executor (PR 18) — **reiner
  Mock**. Deny / Cancel / Timeout blockieren den Executor hart.
- **Audit-Trail:** `AuditStore` (Ring-Buffer, Default 100 / Hard
  1000), Read-only IPC-Endpoint `audit_recent`. **Keine
  Persistenz.** Core-Restart leert den Store.
- **Sensible Felder:** `risk` / `source` / `result` über
  Whitelists, `summary` hart auf 80 Zeichen.

### 2.7 Nur dokumentiert, aber nicht implementiert

Nach Codeprüfung:

- **Echte Desktop-Automation jenseits von `open_application`:**
  `focus_window` / `type_text` / `send_shortcut` sind im Backend
  als `BackendUnsupported` deklariert. Die Dokumentation
  (insbesondere `presence_desktop_interaction.md`) beschreibt
  diese Ebenen, aber der Core-Stack emittiert nur die Planning-
  Events, nicht die Durchführung.
- **`action_progress` / `action_verification`:** Varianten im
  Enum vorhanden. `action_verification` wird vom Interaction-
  Executor nach `open_application` emittiert. `action_progress`
  wird **nirgends** emittiert — reserviert, aber ohne Sender.
- **Streaming / ABrain-Native-API / Tool-Calls:** in `api.md §5`
  als Ziel-Zustand beschrieben; kein Code-Pfad.
- **Emotion-Feld im Response:** in `api.md §8` erwähnt; kein
  Code-Pfad.
- **Stage-C-Avatar-Assets / User-Uploads:** explizit als Forschung
  markiert (`avatar_stage_c_research.md`). Kein Code.
- **Policy-Engine, echtes Tool-Gating:** PR-18-Plan ist ausdrücklich
  „Grundlage, nicht Schalter". Kein Code-Pfad verbindet eine reale
  Core-Operation mit dem Approval-Pfad.

### 2.8 Implementiert, aber schlecht dokumentiert

- **IpcClient-Frame-Routing:** alle 24 Outgoing-Typen werden via
  `_handle_frame` geroutet. Die Liste in `api.md` ist
  aktualisiert, aber die Incoming-Tabelle in §2.1 zeigt nur die
  fünf Grundpfade — PR-17/18/19-Commands tauchen erst in Prosa
  auf.
- **Dev-Controls-Sections:** sechs Sektionen leben im Panel, aber
  `ui_architecture.md` erwähnt nur einen Teil.
- **Workflow-Visibility-Model (PR 16):** neun Step-Kategorien
  (HEARD → COMPLETED/FAILED, inkl. APPROVAL aus PR 17); die
  vollständige Mapping-Tabelle existiert im Code, aber die
  Dokumentation hat zwei getrennte Sections für die ältere und
  die neue Variante.

---

## 3. Dokumentations-Ist-Zustand

| Datei | Zeilen | Rolle |
|-------|-------:|-------|
| `ROADMAP.md` | 1 811 | Roadmap + PR-Changelog (vermischt) |
| `docs/VISION.md` | 685 | Ältere Roadmap-Kopie + UI-Architektur-Snippet |
| `docs/api.md` | 2 010 | IPC-Spezifikation |
| `docs/ui_architecture.md` | 3 344 | UI-Architektur + 10+ PR-Sub-Sections |
| `docs/provider_fallback_and_settings_architecture.md` | ~650 | Provider-Schicht-Architektur |
| `docs/presence_desktop_interaction.md` | ~700 | Presence- + Desktop-Interaction-Vision |
| `docs/avatar_stage_c_research.md` | ~200 | Research-Gate für Stage C |
| `docs/linux_window_overlay_architecture.md` | ~450 | Overlay-Architektur |
| `docs/wlroots_overlay_path.md` | ~60 | wlroots-Stub |
| `docs/window_behavior_backend_verification.md` | ~120 | Verifikationsmatrix |
| `docs/linux_always_on_top_decision.md` | ~130 | AOT-Entscheidungsdoku |
| `docs/x11_always_on_top_verification.md` | ~100 | X11-Testmatrix |
| `docs/x11_always_on_top_results.md` | ~90 | X11-Messdaten |
| `docs/wayland_always_on_top_refusal_results.md` | ~70 | Wayland-Refusal-Messungen |
| `docs/linux_overlay_verification_matrix.md` | ~120 | Overlay-Verifikationsmatrix |
| `docs/linux_interaction_backends_research.md` | ~100 | AT-SPI-Spike |
| `docs/security/APPROVAL_UX.md` | ~190 | Approval-UX-Prinzipien (PR 17/18) |
| `docs/security/AUDIT_TRAIL.md` | ~140 | Audit-Trail-Prinzipien (PR 19) |

---

## 4. Kritische Inkonsistenzen

### 4.1 ROADMAP.md duplizertes UI-Architektur-Kapitel

`ROADMAP.md` enthält seit längerem einen eigenen Abschnitt „Godot UI
Architektur" (Ziel / Architektur / Komponenten / Kommunikation /
Event Flow / Designprinzipien), der inhaltlich eine verkürzte
Kopie von `ui_architecture.md` ist — und nicht synchron gehalten
wird. Duplizierung ohne Nutzen.

### 4.2 VISION.md ist eine veraltete ROADMAP-Kopie

`docs/VISION.md` (Stand: 2026-04-23) enthält Phasen 0–10 in der
alten Fassung ohne PR 14–19. Inhaltlich teilweise widersprüchlich
zur aktuellen `ROADMAP.md`. Zusätzlich ist ein UI-Architektur-Block
eingebettet. Mindestens irreführend.

### 4.3 Zwei Workflow-Overlays koexistieren ohne klare Abgrenzung

- `ui/scenes/workflow_overlay/workflow_overlay_root.tscn` +
  `workflow_overlay_controller.gd` — Phase-3.1-MVP, drei
  symbolische Knoten (Trigger / Action / Result).
- `ui/scenes/workflow/workflow_visibility_panel.tscn` +
  `workflow_visibility_panel.gd` — PR-16-Workflow-Visibility-v1,
  lineare Kartenliste über acht Kategorien.

Beide sind in `ui_architecture.md` getrennt dokumentiert, aber
nirgends wird die **Koexistenz** erklärt — ein Leser denkt, der
neuere ersetzt den älteren. Im Code sind beide aktiv im
`main.tscn`.

### 4.4 Avatar-Phasen-Terminologie kollidiert mit Roadmap-Phasen

Die UI-Dokumentation nutzt „Phase A / B / B+ / B++" für
Avatar-interne Staging-Stufen. Die Roadmap nutzt „Phase 0 – 10"
für Produktphasen. PR 15 ist in `ui_architecture.md §7` als
„Phase 4 — Behavioral Expression Layer v1" geführt — diese
Zählung kollidiert mit der Produkt-„Phase 4 – Behavioral Layer"
der ROADMAP. Für einen neuen Leser ist unklar, welches „Phase 4"
gerade gemeint ist.

### 4.5 Kaputter Cross-Link in ROADMAP.md

Der PR-15-Eintrag verweist auf:

> `[docs/ui_architecture.md §7 „Phase 4 – Behavioral Expression
> Layer v1"]`

Die tatsächliche Section ist `§8.4b`. Der Anker funktioniert nicht.

### 4.6 api.md §2.1 Incoming-Tabelle unvollständig

Die Incoming-Kommando-Tabelle zeigt weiterhin nur die fünf
Grundpfade (`ping`, `get_status`, `submit_text`, `speak_text`,
`voice_once`). Die PR-17/18/19-Commands (`approval_approve`,
`approval_deny`, `request_approval_demo`, `plan_demo_action`,
`audit_recent`) sind ausschließlich in Prosa-Abschnitten weiter
unten dokumentiert. Eine Leserin, die nur die §2.1-Tabelle scannt,
übersieht sie.

### 4.7 api.md §8 „Zukunftsfelder" ist sauber — aber §5 „Core ↔ ABrain: natives API (Ziel-Zustand)" steht neben einem realen HTTP-Provider

`§5` dokumentiert eine geplante native ABrain-API mit Request /
Response / Streaming / Tool-Calls. Gleichzeitig existiert ein
produktiver `abrain`-CLI-Provider und ein real verwendbarer
`cloud_http`-Provider. Die Scope-Abgrenzung zwischen dem „nativen
Ziel" und der real verfügbaren HTTP-Pipe fehlt.

### 4.8 `presence_desktop_interaction.md` beschreibt Fähigkeiten jenseits des Ist-Zustands

- **Desktop Automation Model** listet vier Modi (`none`,
  `assist only`, `confirm before action`, `allowed trusted actions
  only`). Real existiert nur `open_application` via CommandBackend;
  `focus_window` / `type_text` / `send_shortcut` sind
  `BackendUnsupported`.
- **Interaction Fidelity Model** (native-first / hybrid /
  pixel-guided / experimental) ist ausschließlich Ziel-Zustand.
- Das Dokument markiert diese Abschnitte nicht durchgehend als
  „noch nicht implementiert".

### 4.9 `ui_architecture.md §7 Phase B+/B++/C` und `Phase 4`-Subsektion sind parallel gewachsen

Die Datei führt sowohl „Phase B++ Micro-Animation/Personality
Layer v1" als auch „Phase 4 – Behavioral Expression Layer v1" auf
(unterschiedliche Autor:innen, unterschiedliche Zeitpunkte). Für
den Leser wirkt das wie zwei separate Systeme; im Code ist es
dasselbe: die Expression-Schicht aus PR 15.

### 4.10 Doppelte/konkurrierende Begriffe

- „Workflow Overlay" (alt) vs. „Workflow Visibility Overlay v1"
  (neu) — beide im Code aktiv.
- „Phase A/B/B+/B++/C" (Avatar-Staging) vs. „Phase 0–10"
  (Produktroadmap) — gleiche Begriffsfamilie, andere Semantik.
- „approval_response" (altes kombiniertes Kommando) vs.
  „approval_approve" / „approval_deny" (PR 17 schmalere
  Alternativen) — beide aktiv, beide dokumentiert, aber die
  Präferenz ist nicht ausgesprochen.
- „Audit" vs. „Audit Trail" vs. „Audit Snapshot" — api.md §2.7
  spricht im Prosa-Abschnitt von „audit_snapshot", das Wire-Format
  heißt aber einheitlich `audit_recent`. (Der Brief erwähnt auch
  beide; der Ist-Code kennt nur `audit_recent`.)

---

## 5. Veraltete Aussagen

- **`ui_architecture.md §7 Phase C – Erweiterter Ausdruck`:**
  „Speech-Sync mit TTS-Lebenszyklus — MVP gelandet (PR 14)." OK.
  **Aber** der gleiche Absatz listet „feinere Zustände (`curious`,
  `focused`, `alert`)" als zukünftig — `curious` und `focused`
  sind mit PR 15 bereits implementiert.
- **`ui_architecture.md §11 Offene Punkte`:** „Avatar-Rendering"
  als „Platzhalter-Grafik" — zutreffend, aber der Satz davor
  verweist auf die Render-Polish-Stufe (PR „Phase B Render
  Polish"), die bereits gelandet ist (siehe §7).
- **`ROADMAP.md §Aktueller Fokus`:** listet PRs 14–18 in Fließtext
  und sagt „tieferer Speech-Sync … bleibt in Phase C geparkt" —
  richtig, aber vermischt mit PR-19-Update in zwei verschiedenen
  Fokus-Absätzen.
- **`ROADMAP.md §Phase 3b Linux Window & Overlay Architektur`:**
  mehrere „Ist-Zustand"-Bulletpoints sind real Spikes/Messungen,
  keine produktiven Features — die Formulierung suggeriert
  stellenweise mehr Abschlussgrad als gerechtfertigt.
- **`provider_fallback_and_settings_architecture.md §Vorschlag für
  PR-Reihenfolge`:** führt PRs 3–13 als Plan auf. Alle wurden
  umgesetzt. Der Abschnitt beschreibt die Vergangenheit wie ein
  Plan.

---

## 6. Fehlende Dokumentation

- **Abgrenzung der beiden Workflow-Overlays:** notwendiger
  kurzer Absatz in `ui_architecture.md`, welches System wann
  gerendert wird, und warum beide koexistieren.
- **Legende der Avatar-Phasen:** drei Sätze, die klar machen,
  dass „Phase A / B / B++" eine Avatar-Rendering-Terminologie ist,
  nicht die Produkt-Roadmap-Phase.
- **Explicit Open Workstreams:** eine eigene Datei
  `docs/OPEN_WORK.md` fehlt. Der Brief fordert sie ein.
- **`action_progress` / `action_verification`-Verwendung:**
  `api.md §2.5` listet sie als Varianten, sagt aber nicht, dass
  `action_progress` nirgends emittiert wird und
  `action_verification` nur im Interaction-Pfad auftaucht.
- **Dev-Controls-Inventory:** die sechs aktiven Sections sind
  nirgends zusammenhängend beschrieben.

---

## 7. Doppelte / konkurrierende Konzepte

- **Workflow-Overlay-alt** (3-Knoten-MVP aus Phase 3) und
  **Workflow-Visibility-Overlay-v1** (lineare Kartenliste aus
  PR 16) — beide im Code, unterschiedliche Zielgruppe. Keine
  gemeinsame Produktstrategie.
- **Avatar-Staging „Phase A–B++/C"** und **Produktroadmap
  „Phase 0–10"** — Begriffskollision, keine Übersetzungstabelle.
- **`approval_response`** vs. **`approval_approve`/`approval_deny`**
  — technisch äquivalent, beide im Wire-Kontrakt. Keine empfohlene
  Präferenz.
- **`docs/VISION.md`** vs. **`ROADMAP.md`** — zwei Quellen derselben
  Vision, unterschiedliche Stände.
- **`ROADMAP.md §Godot UI Architektur`** vs.
  **`docs/ui_architecture.md`** — doppelte UI-Architekturquelle
  innerhalb der Roadmap.

---

## 8. Roadmap-Probleme

1. **Roadmap ist PR-Log geworden.** 1 811 Zeilen, je PR ein langer
   Absatz mit Scope-Abgrenzung. Detailhistorie gehört in
   `docs/reviews/`, nicht in die Roadmap.
2. **Mehrere Parallel-Phasen ohne klare Priorität:** Phase 3,
   3b, 4, 4b, 8, 8b, 8c — das Struktur-Signal ist verloren.
3. **Keine klare „nächster PR"-Liste:** aus dem aktuellen Text
   ist nicht ableitbar, was PR 20 / 21 sein sollten.
4. **„Aktueller Fokus"-Absatz wiederholt sich:** es gibt
   effektiv drei „Fokus"-Passagen an verschiedenen Stellen.
5. **„Nicht-Ziele" sind pro PR dupliziert:** jeder PR hat seine
   eigene „Ausdrücklich nicht Teil von …"-Liste. Eine
   zentralisierte „Explicitly Deferred"-Liste fehlt.
6. **`docs/VISION.md` ist eine eigene, veraltete Roadmap.**

---

## 9. Empfohlene neue Roadmap-Struktur

```
# ROADMAP.md

1. Vision / Zielbild            (kurz, <30 Zeilen)
2. Architekturprinzipien        (<30 Zeilen)
3. Current Stable Baseline
   - Core / IPC / UI / Audio / Providers / Settings /
     Approval / Audit / Interaction / Window
4. Completed Milestones (nur Phasen-Ebene)
   - Phase 0 Core Foundation
   - Phase 1 Voice Interface
   - Phase 2 IPC Bridge
   - Phase 3 Avatar/Presence/UI
   - Phase 4 Behavior/Visibility/Approval/Audit
5. Open Workstreams (A–I)
   - Pointer auf docs/OPEN_WORK.md
6. Next Mandatory PRs (Vorschlag)
   - PR 21 – 30 mit kurzer Einzeiler-Beschreibung
7. Explicitly Deferred
   - Streaming Audio, Phonem/Lip-Sync, echte Desktop-Automation,
     AdminBot, Stage-C-Assets, Cloud-Provider produktiv,
     Policy-Engine
8. Quellen / Detailreferenzen
   - Pointer auf docs/reviews/*.md für PR-Historie
```

**Richtwert:** < 250 Zeilen. In zwei Minuten scanbar.

---

## 10. Liste der offenen Pflichtarbeiten nach Priorität

Neun Workstreams (aus dem Brief). Pro Workstream siehe
[`docs/OPEN_WORK.md`](../OPEN_WORK.md).

### P0 — Docs & Architecture Hygiene (dieser PR)

- Reality-Check-Report (hier)
- ROADMAP.md auf tragfähige Struktur zurück
- `docs/OPEN_WORK.md` als Single-Source für offene Punkte
- `docs/api.md` Incoming-Tabelle vervollständigen; reservierte
  Varianten markieren
- `docs/ui_architecture.md` Workflow-Overlay-Abgrenzung und
  Avatar-Phasen-Klarstellung
- `docs/VISION.md` als historischer Snapshot markieren
  (Canonical-Pointer auf ROADMAP.md)

### P1 — Window / Overlay / Click-through / AOT Reality

- Saubere „Was ist heute möglich?"-Matrix in
  `linux_window_overlay_architecture.md`
- Fehlende Messläufe auf echten Wayland-Compositor-Hosts (nicht
  in diesem Dev-Host)

### P2 — Approval Policy / Tool-Gating

- Übergang von PR-18-Mock zu einer realen, aber kleinen Policy-
  Schicht für genau eine Core-Aktion (z. B. `open_application`
  mit bestehendem `require_confirmation`).

### P3 — Desktop Interaction Layer

- `focus_window` / `type_text` / `send_shortcut` Backends sind
  MVP-`BackendUnsupported`. Entweder entfernen oder ehrlich als
  Spike umsetzen.

### P4 — Audio Pipeline v2

- Streaming-Audio (noch nicht vorbereitet — explicitly deferred).
- Alternative: bessere TTS-/STT-Provider-Auswahl (z. B.
  cloud-Varianten).

### P5 — Provider / Settings Consolidation

- `cloud_http` ist real; die Produkt-UI-Story „welcher Provider
  unter welchen Bedingungen" ist nicht festgelegt.

### P6 — Avatar Animation / Stage C Research

- Dokumentiert in `avatar_stage_c_research.md`, weiterhin
  research-gated.

### P7 — ABrain Native Integration

- `api.md §5` beschreibt eine native API; ABrain läuft heute als
  externer CLI-Prozess. Keine Zeitpriorität.

### P8 — Packaging / Release / CI

- Kein Release-Pfad dokumentiert, keine CI-Pipeline in diesem
  Repo sichtbar.

---

## 11. Explizite Nicht-Ziele für die nächsten PRs

- **Keine** neuen IPC-Events außerhalb einer bewussten Protokoll-
  Erweiterung.
- **Keine** echte Desktop-Automation über `open_application` hinaus
  ohne vorherige Policy-Verdrahtung.
- **Keine** AdminBot-/Shell-/Cloud-Upload-Pfade.
- **Keine** Audit-Persistenz ohne separate Design-Entscheidung
  (siehe [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)).
- **Keine** Stage-C-Avatar-Assets / User-Uploads.
- **Keine** produktive Cloud-Provider-Standard-Aktivierung.
- **Keine** Policy-Engine im „grand design"-Sinn — stattdessen
  kleine konkrete Gating-Verdrahtung für genau eine Aktion.
- **Keine** neuen Feature-PRs, bevor die Docs-Hygiene aus diesem
  PR nicht durch die Gegenprüfung (siehe Aufgabe 10) durch ist.

---

## 12. Vorschlag: Nächste PRs (PR 21–PR 30)

Konkrete Reihenfolge, **nicht** bindend, aber navigierbar:

| PR | Workstream | Gegenstand |
|----|-----------|-----------|
| 21 | A Docs | Follow-ups aus diesem Reality Check: fixe tote Links im gesamten Repo; `docs/reviews/`-Index anlegen |
| 22 | B Window | Wayland-Compositor-Live-Messung auf separatem Host dokumentieren |
| 23 | F Interaction | `focus_window`-Backend-Spike: entweder echte `wmctrl`-Verdrahtung **hinter** Policy-Gating oder ehrliche Entfernung der `BackendUnsupported`-Variante |
| 24 | E Approval | Policy-Schicht v0: `require_confirmation=true` → echtes `open_application` durch Approval-Pfad (keine neue Fähigkeit, nur reale Verdrahtung der Gating-Kette) |
| 25 | D Providers | Provider-UX-Review: welche Default-Ketten der User beim ersten Start sieht, inkl. cloud_http-Default |
| 26 | C Audio | STT-Alternative: `whisper.cpp` oder ähnlich als zweites STT-Kind; bleibt command-basiert |
| 27 | A Docs | `presence_desktop_interaction.md` auf Ist-Zustand zurechtstutzen; Fidelity/Automation-Modelle klar als Ziel-Zustand markieren |
| 28 | G Avatar | Avatar-Phase-B-Render-Polish-Follow-up (nur rein visuell, kein neuer Kanal) |
| 29 | I Release | README-Build-Setup; erste echte Install-Anleitung |
| 30 | A Docs | Glossar: `Approval`, `Audit`, `Workflow-Overlay`, `Presence`, `Expression`, `Action Event` — stabiles Vokabular |

Jeder PR bleibt klein und conservative. Kein Schritt führt eine
neue gefährliche Fähigkeit ein, ohne eine vorgeschaltete Policy-
Verdrahtung.

---

## 13. Verifikationsergebnis (PR 20)

- **Core-Tests:** 369 PASS, 0 FAIL (unverändert, keine Feature-
  Änderungen).
- **UI-Smokes:** 16/16 PASS (unverändert).
- **Keine neuen IPC-Events, keine neuen Core-Funktionen, keine
  neuen UI-Scripts.**
- **Reiner Docs-Pass:** ROADMAP.md umstrukturiert,
  `docs/OPEN_WORK.md` neu, `docs/reviews/PR20_DOCS_REALITY_CHECK.md`
  neu, `docs/api.md` / `docs/ui_architecture.md` /
  `docs/security/*` auf Ist-Zustand angezogen, `docs/VISION.md`
  mit Historien-Hinweis versehen.
