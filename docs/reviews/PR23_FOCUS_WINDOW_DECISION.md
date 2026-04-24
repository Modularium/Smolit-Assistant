# PR 23 — focus_window Reality Decision

Stand: 2026-04-24. Scope: Entscheidung, wie der Desktop Interaction
Layer mit `focus_window` umgeht — **nicht** ein neues Feature, sondern
ein Reality-Check über das, was heute schon im Repo liegt, plus
formale Dokumentation der Richtung.

**Entscheidung:** Option 1 (bevorzugt) — **focus_window bleibt**,
weil die minimale X11-Backend-Verdrahtung bereits existiert und
allen Anforderungen des PR-23-Briefs genügt. Keine Entfernung,
keine Erweiterung, keine Wayland-Lösung.

Verwandte Dokumente:

- [`docs/api.md §2.6`](../api.md) — IPC-Schnittstelle und
  Event-Sequenz für `interaction_focus_window`.
- [`docs/presence_desktop_interaction.md §14b`](../presence_desktop_interaction.md)
  — Rolle im Desktop Interaction Layer.
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md) Workstream F — Status vor
  und nach PR 23.
- [`ROADMAP.md`](../../ROADMAP.md) §6 / §7 — PR-Reihe und Explicitly
  Deferred.

---

## 1. Aufgabe 1 — Code-Inventur

Alle Stellen, die `focus_window` direkt adressieren (Stand main vor
PR 23):

### Core — Protokoll und Ausführung

- [`core/src/ipc/protocol.rs`](../../core/src/ipc/protocol.rs)
  Line ~32 — `IncomingMessage::InteractionFocusWindow { target }`,
  Line ~189 — `InteractionFocusTarget` Envelope-Struct (`window {
  name, title?, app? }` oder `application { name }`).
- [`core/src/ipc/server.rs`](../../core/src/ipc/server.rs) Line ~151
  — Dispatch in `App::execute_focus_window(target)`.
  Plus zahlreiche Testkonfigurationen (`allow_focus_window=true`,
  `focus_window_cmd_template=Some("/bin/true".into())`) ab
  Line ~742.
- [`core/src/app.rs`](../../core/src/app.rs) Line ~1576 —
  `execute_focus_window` erzeugt `InteractionAction::focus_window`,
  setzt `requires_confirmation=true` und läuft über
  `dispatch_interaction`, d. h. den Approval-Flow.
- [`core/src/interaction/action.rs`](../../core/src/interaction/action.rs)
  — `InteractionKind::FocusWindow`, Payload-Variante `FocusWindow
  { title, app }`, Constructor `InteractionAction::focus_window(id,
  title, app)`.
- [`core/src/interaction/executor.rs`](../../core/src/interaction/executor.rs)
  — `InteractionPolicy { allow_focus_window: bool, … }`; Policy-
  Check refuses mit `ActionKindDisallowed("focus_window")` wenn
  nicht erlaubt; Dispatch-Zweig für `InteractionPayload::FocusWindow`
  in `run_approved` und `execute`. Step-Title `"Focusing window"`.
- [`core/src/interaction/backend.rs`](../../core/src/interaction/backend.rs)
  — `InteractionBackend::focus_window` Default liefert
  `BackendUnsupported("focus_window")`. `CommandBackend::focus_window`
  (ab Line ~152) ist die **echte Implementierung**: ohne Template
  honest `BackendUnsupported`; mit Template werden `{name}`,
  `{title}`, `{app}` substituiert und das Kommando asynchron
  ausgeführt. Exit-0 → `VerificationResult::uncertain`
  („best-effort, keine Fokus-Probe"); Exit-≠0 → `BackendFailed`;
  Spawn-Fehler → `BackendFailed`.
- [`core/src/config.rs`](../../core/src/config.rs) Line ~132 —
  `allow_focus_window: bool` (Default `false`), Line ~146 —
  `focus_window_cmd_template: Option<String>` (Default `None`).
  Env-Variablen:
  - `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW` (Default `false`).
  - `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD` (Default leer).

### Approval-Flow

- [`core/src/app.rs`](../../core/src/app.rs) Line ~3137 —
  `approval_message(action, …)` erzeugt für `FocusWindow` die
  deutschsprachige Zustimmungsfrage `„Smolit möchte das Fenster
  \"{label}\" fokussieren."` Der Approval-Pfad aus PR 17/18 greift
  unverändert.

### Tests (Core)

Sechs konkrete Tests belegen alle ehrlichen Zweige:

- `interaction::executor::focus_window_disallowed_emits_failed` —
  Policy verweigert mit `recovery_hint=fallback_unavailable`.
- `interaction::executor::focus_window_without_backend_template_emits_unsupported`
  — ohne Template kommt `BackendUnsupported` als `action_failed`
  heraus.
- `interaction::executor::focus_window_with_template_emits_verification_and_completed`
  — mit `/bin/true` läuft die komplette Event-Sequenz bis
  `action_completed` mit `Best-effort:` Präfix.
- `interaction::backend::focus_window_without_template_is_unsupported`
  — Backend direkt: ohne Template `BackendUnsupported`.
- `interaction::backend::focus_window_without_target_reports_preconditions`
  — leere Ziele → `Preconditions`.
- `interaction::backend::focus_window_with_true_is_uncertain` —
  Exit 0 → `VerificationResult::uncertain`.
- `interaction::backend::focus_window_failing_command_reports_backend_failed`
  — Exit ≠ 0 → `BackendFailed`.
- IPC-Server-Ebene: `interaction_focus_window_fails_when_disallowed`,
  `…_without_backend_template_reports_unsupported`,
  `…_emits_verification_and_completed_when_allowed`,
  `…_application_target_maps_to_app`,
  `…_with_approval_flow_runs_end_to_end`.

### UI

`rg -n "focus_window|FocusWindow|interaction_focus_window" ui/`
liefert **keine Treffer**. Weder das Workflow Visibility Overlay
(PR 16), die Approval Card (PR 17), die Audit-Panel-Linie (PR 19)
noch irgendein Dev-Control referenziert `focus_window`. Das ist
gut: Entfernen des Protokoll-Kinds hätte keine UI-Dangling-Referenzen
hinterlassen — aber genauso wenig gibt es heute eine UI, die
`focus_window` versehentlich auslöst.

### Docs

- [`docs/api.md §2.6`](../api.md) dokumentiert `interaction_focus_window`,
  die Ziel-Schemata, die Eventfolge inkl. Approval, die Verification-
  Semantik und die Env-Variablen sauber.
- [`docs/presence_desktop_interaction.md §14b.4`](../presence_desktop_interaction.md)
  erklärt die MVP-Grenzen („uncertain ohne Fokus-Probe; ohne
  Template oder unter Wayland: ehrlich `BackendUnsupported`").
- `docs/GLOSSARY.md` `Interaction Layer` listet `FocusWindow` in der
  Kind-Familie und nennt den heutigen MVP-Zustand.
- [`README.md`](../../README.md) Line ~169 ff. enthält bereits ein
  konkretes Beispiel-JSON und erklärt den `allow_focus_window=false`-
  Default.
- `.env.example` Line ~29–33 zeigt das empfohlene X11-Template
  (`wmctrl -a {name}`) und rät unter Wayland zum Leerlassen.
- [`ROADMAP.md`](../../ROADMAP.md) §7 behauptete bislang „Kein
  focus_window / type_text / send_shortcut Backend-Pfad" — das ist
  **veraltet** (PR 20 Reality-Check hat diesen Halbsatz übersehen).
  Wird in PR 23 korrigiert.

---

## 2. Aufgabe 2 — Machbarkeitsprüfung (X11 only)

**Host (Dev-Maschine, 2026-04-24):**

- Ubuntu 24.04.4 LTS, GNOME Shell 46.0, `XDG_SESSION_TYPE=x11`,
  `DISPLAY=:0`.
- `/usr/bin/wmctrl` vorhanden. `wmctrl -m` liefert `Name: GNOME
  Shell`.
- `/usr/bin/xdotool` vorhanden (als zweites mögliches Tool, nicht
  empfohlen — `wmctrl` genügt für Window-Name/Class-Matching).

**Option A — wmctrl-/xdotool-basiert.** Realistisch, bereits
verdrabaut. `wmctrl -a <title-or-app>` macht genau das: activate
window by (partial) name. Kein Fuzzy-Magic — `wmctrl` matcht
Substring auf dem Fenstertitel, das ist dokumentierte
Semantik und deckt den MVP-Scope.

**Option B — Feature streichen.** Würde bedeuten:

- `InteractionKind::FocusWindow` aus der Enum entfernen.
- `InteractionPayload::FocusWindow` entfernen.
- Executor-Dispatch zurückbauen.
- CommandBackend-Implementation entfernen.
- IPC-Type `interaction_focus_window` aus Protokoll und Server-
  Router entfernen.
- `App::execute_focus_window` und Approval-Nachrichten-Zweig
  entfernen.
- Alle 11+ Tests löschen.
- api.md §2.6 kürzen, presence_desktop_interaction.md §14b.4
  umschreiben, README.md kürzen, `.env.example`-Zeilen entfernen,
  `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW` + `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`
  aus der Config entfernen.

Das wäre erheblicher Rückbau einer **funktionierenden** Linie.

**Bewertung:**

- Die Implementation ist bereits minimal: ein Command-Template, ein
  Spawn, eine ehrliche `uncertain`-Verification. Keine Heuristik,
  keine Fuzzy-Fenstersuche, keine eigene Window-Probe.
- Unter Wayland ist die Default-Konfiguration (kein Template)
  bereits die ehrliche Ablehnung — die Architekturaussage „keine
  Wayland-Lösung" ist durch die Leere-Template-Regel erfüllt.
- Der Entfernungs-Pfad würde bestehende Arbeit (6+ Tests, saubere
  IPC-Schnittstelle, Approval-Integration) zerstören, ohne dass
  sich die Produktgeschichte ändert — `focus_window` blieb
  sichtbar nur mit Template opt-in, sonst `BackendUnsupported`.

---

## 3. Aufgabe 3 — Entscheidung

**Option 1.** `focus_window` **bleibt**, weil:

1. **Implementation existiert und ist ehrlich.** Template-basiert,
   `wmctrl -a {name}` empfohlen, ohne Template und/oder unter
   Wayland liefert der Core `BackendUnsupported("focus_window")`.
   Kein Fake-Success, kein stiller No-Op.
2. **Scope deckt sich exakt mit Option-1-Anforderungen** des
   Briefs: nur wmctrl als empfohlenes Tool, nur Window-Name/Class-
   Matching (keine Fuzzy-Heuristik im Core — was wmctrl selber
   macht, ist dessen dokumentierte Semantik), kein Wayland-Fallback
   (Template leer), klarer Fehler auf unsupported
   (`BackendUnsupported` → `action_failed` mit
   `recovery_hint=fallback_unavailable`).
3. **Approval-Gating ist bereits greifend.** `requires_confirmation=true`
   zwingt jede `focus_window`-Aktion durch den Approval-Flow aus
   PR 17; `allow_focus_window=false` Default schützt vor
   versehentlicher Nutzung.
4. **Keine UI-Regression möglich.** UI ruft `focus_window` heute
   nirgends auf — sowohl Beibehaltung als auch Entfernung wären
   UI-neutral, aber Beibehaltung bewahrt die IPC-Schnittstelle für
   einen späteren Zeitpunkt, an dem ein UI-Pfad sinnvoll wird.

Keine Code-Änderung notwendig, um Option 1 zu realisieren —
**die Entscheidung ist, den bestehenden Stand als final-for-now zu
bestätigen** und die Dokumentation anzupassen, damit ROADMAP §7
nicht weiter das Gegenteil behauptet.

---

## 4. Aufgabe 4 — Docs-Änderungen in PR 23

- [`ROADMAP.md`](../../ROADMAP.md) §6: PR 23 markiert als erledigt
  (Option 1 — bestätigt, keine Entfernung).
- [`ROADMAP.md`](../../ROADMAP.md) §7: der veraltete Halbsatz „Kein
  `focus_window` / `type_text` / `send_shortcut` Backend-Pfad" wird
  auf den realen Stand korrigiert — `focus_window` hat einen
  template-basierten Backend-Pfad, `type_text` / `send_shortcut`
  sind weiterhin `BackendUnsupported`.
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md) Workstream F: Status auf
  „Option 1 bestätigt; `focus_window` bleibt; type_text /
  send_shortcut bleiben BackendUnsupported". Nächster kleinster
  PR bleibt Policy-Verdrahtung (Workstream E).
- [`docs/api.md §2.6`](../api.md): präzisere Ist-Aussage in
  einem Satz hinzufügen — dies ist eine bestätigte Entscheidung,
  keine offene Frage mehr.
- [`docs/presence_desktop_interaction.md §14b.4`](../presence_desktop_interaction.md):
  kleine Präzisierung, dass der Status per PR 23 als stabil-MVP
  gesetzt ist; keine weitere Backend-Arbeit vor Policy-PR.

---

## 5. Aufgabe 5 — Tests

**Core:** keine neuen Tests. Die bestehenden 11+ Tests decken alle
Pfade ab (`success`, `not found / preconditions`, `disallowed`,
`backend failed`, `unsupported ohne Template`). Neue Tests wären
Duplikate.

**UI:** `scripts/run_overlay_verification.sh workflow-visibility-smoke`
prüft das Workflow-Overlay weiterhin — `focus_window` taucht dort
nicht auf, also keine kaputten Steps zu erwarten.

Verifikation in PR 23 (2026-04-24):

- `cargo test` → **369 PASS, 0 FAIL**.
- `scripts/run_overlay_verification.sh workflow-visibility-smoke` →
  **PASS**.
- Kein dangling reference in UI.

---

## 6. Aufgabe 6 — Nicht-Ziele (bewusst)

- **Kein `type_text`-Backend.** Bleibt `BackendUnsupported`.
- **Kein `send_shortcut`-Backend.** Bleibt `BackendUnsupported`.
- **Keine Desktop-Automation jenseits `open_application` und
  `focus_window`.**
- **Kein AdminBot, kein Shell-Abstraktions-Layer.**
- **Keine Policy-Engine-Erweiterung** (das ist Workstream E /
  PR 24).
- **Keine Wayland-Unterstützung** — kein protokollweiter
  Fokus-Primitiv-Pfad; Template leer → `BackendUnsupported`.
- **Keine komplexe Window-Discovery** — was wmctrl an
  Title-Substring kennt, reicht. Keine AT-SPI-RPC-Integration hier.

---

## 7. Bekannte Einschränkungen

- **Verification bleibt `uncertain`.** Exit-0 des Helfers belegt
  nur, dass der Prozess gelaufen ist — nicht, dass der Fokus
  tatsächlich gewechselt hat. Eine Fokus-Probe wäre ein eigener,
  größerer Schritt (XInput, `_NET_ACTIVE_WINDOW`-Read o. Ä.) und
  ist ausdrücklich nicht Teil dieses PRs.
- **Wayland-Operator-Escape-Hatch.** Wenn ein Operator unter
  Wayland trotzdem ein Template setzt (z. B. Richtung
  `swaymsg` oder GNOME-Extension), blockiert der Core das heute
  nicht hart — er führt das Kommando aus. Der Ausgang hängt am
  Helper. Dieses Verhalten ist bewusst neutral („der Operator
  weiß, was er tut"); das Produkt verspricht Wayland-Fokus
  weiterhin nicht.
- **Keine App-Disambiguierung.** `wmctrl -a <name>` trifft das
  erste passende Fenster. Wer `{app}` zusätzlich reicht, kann
  präziser templaten (z. B. `wmctrl -x -a {app}.<class>`), aber
  das ist Operator-Konfiguration, keine Core-Logik.

---

## 8. Abschluss

`focus_window` war nie das Problem — die Implementation ist sauber,
der Approval-Flow korrekt, die Tests belegen alle Zweige. Was fehlte,
war eine formale Entscheidung „das ist der finale MVP-Stand", damit
ROADMAP und OPEN_WORK nicht weiter das Gegenteil suggerieren.

PR 23 ist diese Entscheidung.
