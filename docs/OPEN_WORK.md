# Open Work — Smolit Assistant

> Single-Source für offene Arbeiten pro Workstream. Die
> [ROADMAP.md](../ROADMAP.md) verweist hierher. Pro Workstream:
> Status, Warum wichtig, Blocker, nächster kleinster PR,
> Nicht-Ziele, Tests / Verifikation. Ein-Datei-Format, damit Reviewer
> den gesamten „State of Open Work" in einem Scroll erfassen.

Stand: 2026-04-24 (nach PR 31 Roadmap Checkpoint — konsolidiert den
Zustand nach der PR-21–30-Stabilisierungsserie). Sammelblick:
[`docs/reviews/PR31_ROADMAP_CHECKPOINT.md`](./reviews/PR31_ROADMAP_CHECKPOINT.md).

---

## A — Docs & Architecture Hygiene

**Status:** aktiv. PR 20 (Docs Reality Check), PR 24 (Smolitux Design
Contract ADR), **PR 28 (2026-04-24) — `presence_desktop_interaction.md`
auf Ist-Zustand getrimmt (1096 → 491 Zeilen, 12-Abschnitt-Struktur,
Zielbild konsequent in Future Work / Non-goals isoliert)**,
**PR 44 (2026-04-25) — Ecosystem Integration Contracts Matrix**
([`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md),
Docs-only, indexiert ABrain / AdminBot / OceanData / smolitux-ui
ohne diese Repos anzufassen) und **PR 49 (2026-04-25) — Roadmap
Sync after Contracts PR 43–48** ([`docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md`](./reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md);
Reality-Check, der die tatsächliche Sequenz PR 43–48 dokumentiert,
Roadmap §6.3-Header von „drei" auf „vier" Folge-PRs korrigiert,
OPEN_WORK Workstream I PR-48-Eintrag auf PR 51 verschiebt und die
neue konservative PR-50–55-Sequenz setzt; Runtime-Baseline
unverändert) sind gelandet.

**Folgearbeiten aus PR 44 (alle Docs/ADR-only, kein Code, in-scope
für dieses Repo):**

- Smolit-Assistant ↔ AdminBot Safety Boundary ADR (schließt die
  *missing by design*-Lücke aus
  [`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md` §6](./contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md)).
- Audit Correlation ID Spec (cross-repo Korrelation zwischen
  Smolit-Assistant Audit, ABrain-Adapter und AdminBot-Aktionen).
- Capability Vocabulary (gemeinsames Vokabular für Capability-
  Klassen, das die Cross-Repo-Verträge konsumieren).
- ABrain ↔ OceanData Handoff Review (Konsistenz zwischen
  ADR-0003 / ADR-0004 und der bestehenden OceanData-seitigen
  Vertragslinie — kein neuer Vertrag in ABrain).

Ausdrücklich **out-of-scope** für dieses Repo: Edits an
ABrain / Smolit_AdminBot / OceanData / smolitux-ui. Ein Spiegel-
Vertrag in ABrain für ABrain ↔ OceanData liegt im ABrain-Repo,
nicht hier.

Hintergrund: Siehe
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
**PR 33 (2026-04-24, gelandet)** hat die Workflow-Overlay-
Konsolidierungsfrage entschieden (**Option C — Entfernen**): der
Drei-Knoten-Phase-3.1-Spike ist komplett aus der UI entfernt; das
Workflow Visibility Overlay v1 (PR 16) ist die einzige
Workflow-UI. Details:
[`docs/reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md`](./reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md).

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

**Status:** STT (seit PR 27) und TTS (seit **PR 34, 2026-04-24**)
haben **je zwei** produktive command-basierte Kinds: STT
`[command, whisper_cpp]`, TTS `[command, piper]`. Audio-Pipeline
bleibt command-basiert; TTS-Lifecycle-Events aus PR 14 tragen
unverändert ein `provider`-Feld (heute ein echter Unterschied —
`piper` oder `command` je nach Resolver-Ausgang). Keine
Streaming-Audio-Pipeline.
**Warum wichtig:** Die Fallback-Ketten `["whisper_cpp", "command"]`
und `["piper", "command"]` sind jetzt beide real nutzbar — der
Resolver spiegelt `active=command` / `availability=fallback_active`,
wenn das Primär-Kind nicht konfiguriert ist oder fehlschlägt. Die
in der PR-31-Drift-Watchlist benannte **TTS-Monokultur** (nur ein
produktives Kind) ist damit geschlossen.
**Blocker:** keiner; der Provider-Resolver aus PR 6/13 nimmt
sowohl `whisper_cpp` als auch `piper` als vollwertiges Chain-Kind.
**Nächster kleinster PR:** kein zwingender C-PR in der nahen Reihe.
Mögliche Folgearbeit (ohne Priorität): ein drittes Kind mit
anderer Spawn-Semantik (z. B. `http_local` STT/TTS), oder das
`sanitize_*`-Vokabular um Cloud-Kennzeichnung erweitern — beides
bräuchte eigene Design-Entscheidungen. **Keine** Streaming-Pipeline,
**kein** Modell-Manager.

**Nicht-Ziele:**

- Kein Streaming-Audio, kein Phonem-/Lip-Sync, keine Audio-
  Timeline (explicitly deferred).
- Keine Cloud-STT/-TTS-Provider als Default.
- Kein neuer Audio-Subsystem-Stack — bestehender
  `core/src/audio/` bleibt.
- Keine Build-Abhängigkeit auf whisper.cpp oder Piper; beide
  Kinds bleiben external-command-based.
- Kein Modell-/Download-Manager in PR 27 oder PR 34.
- Kein Runtime-Editor für `SMOLIT_STT_WHISPER_CPP_CMD` oder
  `SMOLIT_TTS_PIPER_CMD` — beide Kommandos sind env-only.

**Tests / Verifikation:**

- `core/src/providers/stt.rs`: elf PR-27-Tests.
- `core/src/providers/tts.rs`: elf PR-34-Tests, u. a.
  `validate_tts_chain_accepts_piper_kind`,
  `piper_primary_without_command_reports_unavailable`,
  `fallback_chain_piper_then_command_uses_command_when_piper_missing`.
- Chain-Validator-Tests (Whitelist, Duplikate, Empty-Reject)
  decken beide neuen Kinds ab.
- `speech-sync-smoke` und `settings-shell-smoke` bleiben grün;
  letzterer erhält sechs neue PR-27-Checks plus sechs neue
  PR-34-Checks (`_check_tts_chain_editor_*`,
  `_check_tts_lines_piper_*`).

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
**Erledigt:**

- **PR 36 D-Settings-Shell-UX-Cleanup** *(2026-04-24, gelandet)*. Die
  drei Provider-Sections (Text / STT / TTS) teilen jetzt dieselbe
  dreiteilige Lesereihenfolge **Summary · Details · Editoren**.
  Summary expandiert die Begriffe `Primary (intended)` (chain[0]),
  `Active (running)` (`*_provider_active`), `Availability` und
  `Local / Cloud` in eigene Zeilen, damit Fallback-Fälle auf den
  ersten Blick sichtbar sind. Die Privacy-Section trägt einen
  expliziten `— Safety notes —`-Block (Opt-in cloud, Secrets nie
  angezeigt, env-only `SMOLIT_STT_WHISPER_CPP_CMD` /
  `SMOLIT_TTS_PIPER_CMD`, Probes side-effect-frei). Der Text-
  Chain-Editor hat eine zusätzliche Note, die `cloud_http` als
  Opt-in ausweist (kein Auto-Add). **Keine** neuen IPC-Commands,
  **keine** neuen `StatusPayload`-Felder, **keine** Core-Änderung,
  **keine** Default-Änderung. Regression-Lock:
  `_check_no_new_ipc_command_helpers_in_controller`. Details:
  [`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md)
  §13.

**Nächster kleinster PR:** kein zwingender D-PR in der nahen Reihe.
Mögliche Folgearbeit (ohne Priorität): Pro-Kind-Editoren nach
Onboarding kollabierbar machen; der Chain-Editor bekommt nach
Onboarding keinen zusätzlichen Hinweis, wenn die Reihenfolge bereits
die empfohlene lokale Kette ist — beides wäre ein UX-Detail-PR ohne
Protokoll-Auswirkung.

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
**Nächster kleinster PR:** kein zwingender E-PR in der nahen Reihe.
PR 32 (2026-04-24, gelandet) hat den Audit-Ring-Buffer generisch
auf beide Real-Interaction-Pfade (`open_application` und
`focus_window`) erweitert — kein Persistenz-Pfad, keine neuen
IPC-Commands, keine Erweiterung des `sanitize_*`-Whitelist-
Vokabulars. Details:
[`PR32_AUDIT_INTERACTION_LIFECYCLE.md`](./reviews/PR32_AUDIT_INTERACTION_LIFECYCLE.md)
und [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md)
Abschnitt „Coverage für reale Interaction-Actions (PR 32)".

**Erledigt in PR 32:**

- Generisches Audit-Tracing im geteilten `dispatch_interaction` +
  `await_and_continue`-Pfad (`core/src/app.rs`).
- Neuer Helper `record_interaction_lifecycle_audit`, der aus dem
  vom `InteractionExecutor` zurückgegebenen Event-Vektor die
  Lifecycle-Grenzen (`ActionStarted` / `ActionCompleted` /
  `ActionFailed` / `ActionCancelled`) in den Audit-Store schreibt.
- Fünf neue IPC-Integrationstests:
  `audit_recent_records_open_application_approved_full_chain`,
  `audit_recent_records_open_application_denied_chain`,
  `audit_recent_records_open_application_timeout_chain`,
  `audit_recent_records_focus_window_approved_chain_generic`,
  `audit_recent_open_application_double_approve_does_not_double_complete`.
- Aktive Leak-Checks: `/bin/true`, `wmctrl`,
  `SMOLIT_INTERACTION_OPEN_APP_CMD` tauchen **nicht** in der
  Audit-Antwort auf.

**Erledigt in PR 45 (2026-04-25, Docs/ADR-only):**
[`ADR-0005`](./adr/ADR-0005-adminbot-safety-boundary.md) fixiert
den Smolit-Assistant ↔ AdminBot Safety-Boundary-Rahmen, bevor
Code entsteht. Kernlinien: read-only / status-first, capability-
whitelisted, kein Shell-Pfad, kein generischer Tool-Passthrough,
Approval-/Audit-Hop für jede Mutation, Audit-Correlation-ID
sobald Spec existiert, lokal-first, default-off; kein Bypass via
ABrain-`action_intents` oder Desktop-Interaction; AdminBot ↔
OceanData bleibt eigener ADR. Implementation aufgeschoben:
**Status weiterhin not implemented** — kein Code, kein IPC, kein
Adapter, kein Provider-Kind. Begleitend aktualisiert:
[`docs/contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md`](./contracts/ECOSYSTEM_INTEGRATION_CONTRACTS.md)
Pair 3 (jetzt mit ADR-0005-Verweis) und §6 *Explicit gaps*
(Lücke ist jetzt nur noch Implementation-Gap).

**Erledigt in PR 46 (2026-04-25, Docs/Contract-only):** zwei
cross-repo Verträge für die noch fehlenden Grundlagen liegen jetzt
im Repo vor —
[`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](./contracts/AUDIT_CORRELATION_ID_SPEC.md)
(Draft / Proposed: Format, Lebenszyklus, Propagationspunkte,
cross-repo Erwartungen, Privacy/Sanitization, Failure-Modes) und
[`docs/contracts/CAPABILITY_VOCABULARY.md`](./contracts/CAPABILITY_VOCABULARY.md)
(Draft / Proposed: Naming-Regeln, sechs Kategorien
`interaction.*` / `admin.*` / `data.*` / `assistant.*` /
`provider.*` / `audit.*`, initiales Vokabular mit Mappings auf
bestehende Smolit-Assistant-Code-Identitäten und auf zukünftige
AdminBot-/OceanData-Surfaces, Risk-Levels, Pflicht-Metadaten).
ADR-0005 FA-2/FA-3-Verweise und der Matrix-Eintrag „Explicit gaps"
sind aktualisiert: die *dokumentarische* Lücke ist geschlossen,
der *Implementation*-Gap bleibt offen — keine Runtime-Registry,
kein `correlation_id`-Feld im Code, keine String-Konstanten.

**Erledigt in PR 47 (2026-04-25, Docs/Contract-only):**
[`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`](./contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md)
schließt ADR-0005 FA-1 auf Doku-Ebene. Vier Initial-Klassen
(`admin.status.read`, `admin.capability.describe`,
`admin.action.dry_run`, `admin.action.execute`), 13-Eintrags-
Deny-Baseline (`admin.shell.execute`, `admin.sudo.execute`,
`admin.filesystem.write_unscoped`, `admin.secret.read`,
`admin.network.exfiltrate`, `admin.process.kill_unscoped`,
`admin.service.restart_unscoped`, `admin.package.install_unscoped`,
`admin.user.modify`, `admin.auth.modify`, `admin.backup.delete`,
`admin.audit.clear`, `admin.policy.disable`), 15 Pflichtfelder pro
Capability-Eintrag, 15 benannte Failure-Modes, vier JSON-Beispiele
(drei akzeptierte Klassen + ein abgelehntes `admin.shell.execute`).
Begleitend: Matrix Pair 3 + ADR-0005 FA-1 + contracts/README
verlinken den neuen Contract.

**Folgearbeiten aus PR 45 + PR 46 + PR 47 (alle Docs/ADR-only oder
hinter expliziem Opt-in, kein zwingender Code-PR in der nahen
Reihe):**

- **FA-1.** ~~`ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`~~ — **erledigt
  in PR 47**
  ([`docs/contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md`](./contracts/ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md)).
  *Implementation* (Capability-Konstanten, AdminBot-Client, Wire,
  pro `target_capability_id` ein eigener Contract-Eintrag) bleibt
  eigene Folge-PR-Reihe (siehe ADMINBOT_SAFETY_BOUNDARY_CONTRACT
  §17 AC-1…AC-7).
- **FA-2.** ~~Audit Correlation ID Spec~~ — **erledigt in PR 46**.
  *Implementation* (Feld in `AuditEvent`, Cross-Repo-Wire,
  fail-closed-Verhalten) bleibt eigene Folge-PR-Reihe.
- **FA-3.** ~~Capability Vocabulary~~ — **erledigt in PR 46**.
  *Implementation* (Code-Konstanten, Validation-Tests, UI-Display-
  Names) bleibt eigene Folge-PR-Reihe.
- **FA-4.** Spike-PR (Stufe 0 read-only) hinter Feature-Flag, erst
  nach Implementation-Teil von FA-2 (`correlation_id` in
  `AuditEvent`) + FA-3 (Capability-Konstanten).
- **FA-5.** Approval-Card-Erweiterung für AdminBot-Capabilities
  mit Pflichtfeldern aus
  ADMINBOT_SAFETY_BOUNDARY_CONTRACT §10
  (`target_capability_id`, `risk_level`, kuratiertes
  `side_effects`-Summary, `rollback_supported`-Anzeige,
  `timeout_ms`, `correlation_id`).
- **FA-6.** Mutating spike (Stufe 1 dry-run) hinter Feature-Flag,
  erst nach FA-4 + FA-5.

**Nicht-Ziele:**

- Keine Policy-Engine im „grand design"-Sinn.
- Keine Multi-Seat- oder Audit-Persistenz-Features.
- Keine Erweiterung des Demo-Executor-Set um Kinds mit echten
  Seiteneffekten.
- **Kein `type_text` / `send_shortcut`-Backend** als Folgeschritt —
  solche Fähigkeiten bräuchten eigene ADR-/Policy-Runde.
- **Keine Audit-Persistenz**, auch nach PR 32 nicht. Der
  Ring-Buffer bleibt in-memory; ein Persistenz-/Export-Pfad
  braucht eine eigene Security-Review
  ([`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md)).
- **Keine feinere Risk-Klassifikation** als heute (`low` /
  `medium` / `high`) vor einer eigenen Policy-Runde.
- **Kein direkter AdminBot-Codepfad** durch PR 45. ADR-0005 ist
  Docs-only; der Implementation-Gap bleibt bewusst offen, bis
  FA-1 (Capability Contract) und FA-2 (Audit Correlation ID Spec)
  geschrieben sind.

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
**Erledigt (Decision only):**

- **PR 37 F-Accessibility-RPC-Spike-Decision** *(2026-04-24, gelandet,
  Docs/ADR-only)*. [`ADR-0002`](./adr/ADR-0002-accessibility-rpc-readonly.md)
  entscheidet den Rahmen für einen späteren AT-SPI-RPC-Pfad:
  **read-only** `GetChildren` am Registry-Root, **kein** Klick,
  **kein** Tipp, **kein** `DoAction`, **kein** Baum-Walk über eine
  Tiefe hinaus. Kandidaten-Stack ist `atspi` + `zbus` (pure-Rust)
  hinter einem `accessibility_rpc`-Feature-Flag (default-off). Das
  Wire-Schema aus [`docs/api.md` §2.8](./api.md) bleibt unverändert;
  `confidence: verified` bleibt exklusiv für Items, die aus einem
  echten Registry-Call stammen, heutige Hint-Echos bleiben
  `discovered`. Kein Code in diesem PR.

**Nächster kleinster PR (Future Work, nicht priorisiert):**

- **FA-1 — accessibility_rpc-Feature-Spike.** Setzt ADR-0002 D1–D5
  um: `atspi`+`zbus` hinter Feature-Flag, Registry-Root-Children-
  Read, Failure-Mode-Mapping aus ADR-0002. Eigener PR mit eigenen
  Tests und Packaging-Note (Flatpak: `--talk-name=org.a11y.Bus`).
- **FA-2/FA-3/FA-4 — eigene ADRs vor Code** für Name-Match-Pfad,
  Toolkit-Gaps und Wayland-Portal-Fokus.

`focus_window` bleibt mit PR 23 abgeschlossen; `type_text` /
`send_shortcut` bekommen auch hier **keinen** Backend-Pfad.

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
- PR 37 ist Docs/ADR-only — keine neuen Tests. Die bestehenden
  Accessibility-Unit-Tests in
  [`core/src/interaction/accessibility.rs`](../core/src/interaction/accessibility.rs)
  decken den Ehrlichkeits-Guard weiterhin ab (`verified` wird in
  keinem Pfad emittiert, Hint-Echo produziert `discovered` mit
  `matched_hint`).

---

## G — Avatar Animation / Stage C Research

**Status:** Phase A (Smolit), Phase B (kuratierte Alternativen),
Phase B Render Polish, **PR 30 Phase B Render Polish Follow-up
(2026-04-24, gelandet)** und PR-15-Behavioral-Expression-Layer
sind live. Stage C bleibt explizit Research-Gate
([`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md)).
PR 30 hat keine neuen Assets, keine neuen Identities, keine neuen
States und keine neuen Capabilities eingeführt — rein prozeduraler
Polish in den bestehenden `_draw_*`-Pfaden plus eine kuratierte
Palette-Datei als Andockpunkt für einen späteren Smolitux-Design-
Token-Import (heute nicht implementiert).
**Warum wichtig:** Stage-C wäre User-Upload-Territorium; ohne
sauberes Sicherheits-/Trust-Modell nicht machbar. PR 30 arbeitet
bewusst *innerhalb* des bestehenden Capability-Contracts statt
Stage-C-Territorium aufzumachen.
**Blocker:** Sicherheits-Hierarchie + Manifest-Format für Stage C
noch nicht entschieden. Für einen Token-Import-Spike blockiert
zusätzlich Workstream J (smolitux-ui Token-Contract steht aus).
**Nächster kleinster PR:** kein zwingender G-PR in der nahen Reihe.
Die Palette-Datei aus PR 30 ist der Andockpunkt; sie wartet auf
PR 35 (Token-Contract-Prep auf smolitux-ui-Seite). Erst danach wäre
ein kleiner reversibler Smolit-Assistant-Spike sinnvoll.

**Nicht-Ziele:**

- Kein User-Upload, keine User-supplied Identities.
- Keine Asset-Pipeline, keine Manifest-Parser.
- Keine neue State-Ebene über dem Expression-Layer.
- Keine neue Capability-Achse im Template-Contract (PR 30 hat
  keinen neuen `EXPR_*`-Key eingeführt).

**Tests / Verifikation:**

- `avatar-render-polish-smoke` wächst mit PR 30 auf 52 Assertions
  (sechs neue Cases: Palette-Konstanten-Namen, Float-Ratio-Ranges,
  Color-Alpha-Sanity, Rim-Tabellen-Lock, Capability-Contract-Lock,
  Default-Identity-Lock).
- `avatar-expression-smoke`, `avatar-identity-smoke`,
  `avatar-template-capabilities-smoke` bleiben grün.
- Identitätsgarantie (Default-Smolit unverändert) bleibt bindend.
- `git diff` bleibt binärfrei — keine neuen Assets.

---

## H — ABrain Native Integration

**Status:** ABrain läuft als externer CLI-Prozess
(`SMOLIT_ABRAIN_CMD`). Die Native-API-Beschreibung in
[`docs/api.md §5`](./api.md) ist Ziel-Zustand.
**Warum wichtig:** CLI-Sprung bei jedem Prompt ist teuer; Streaming-
Response und Tool-Calls sind nur mit nativer API machbar.
**Blocker:** ABrain-Roadmap-seitige Entscheidung. Keine Core-
seitigen technischen Blocker.
**Erledigt (Decision only):**

- **PR 39 H-ABrain-Native-Integration-ADR** *(2026-04-24, gelandet,
  Docs/ADR-only, Status **Proposed**)*.
  [`ADR-0003`](./adr/ADR-0003-abrain-native-integration.md) fixiert den
  Rahmen für einen zukünftigen Native-Pfad, bevor ABrain-seitig ein
  verbindlicher API-Vertrag steht. Kernaussagen: der Native-Pfad
  kommt als **zusätzlicher** Text-Provider-Kind (Arbeitsname
  `abrain_native`, Default-Chain bleibt `["abrain"]`), nicht als
  Ersatz — `ABRAIN_CMD` und der heutige `AbrainCliProvider` bleiben
  unverändert. Typed request/response, lokal-first (Unix-Socket /
  Loopback), **jede** ABrain-induzierte Action läuft durch den
  bestehenden Approval-/Policy-/Audit-Gate (PR 25 / PR 19 / PR 32),
  kein AdminBot-/Shell-/Desktop-Bypass, kein Streaming und keine
  Tool-Call-Execution in der ersten Version. Status bleibt
  **Proposed**, bis ABrain-Seite einen Gegenvorschlag gegen §4+§7
  publiziert.

**Nächster kleinster PR (Future Work, nicht priorisiert):**

- **FA-1 — `abrain_native`-Provider-Spike.** Typed API-Client hinter
  Feature-Flag, Chain-Whitelist-Erweiterung, Wire-Schema aus
  ADR-0003 §6 geprüft. Kein Action-Intent-Pfad, kein Streaming.
- **FA-2 — Cross-Repo-Contract-ADR** (Smolit-Assistant ↔ ABrain):
  fixiert das JSON-Schema als verbindlich, inkl. Versionierung und
  Breaking-Change-Regeln.
- **FA-3 — Action-Intent-Schema + Approval/Audit-Integration.**
  Strukturiertes `action_intents`-Array wird im Core in
  `action_planned`-Events verdrahtet — Kind-Whitelist startet mit
  `open_application` / `focus_window`.
- **FA-4 — Streaming.** Eigenes Lifecycle-Protokoll
  (`response_started` / `response_chunk` / `response_ended`),
  eigener ADR vor Code.
- **FA-5 — ABrain-seitiger Contract-Doc.** ABrain-Repo spiegelt den
  Vertrag als Gegenstück zu ADR-0003 §6.

**Nicht-Ziele (unverändert):**

- Keine Tool-Call-Engine in Smolit, bevor die ABrain-Seite
  geklärt ist.
- Keine Emotion-Felder in `response` ohne Core-Signal.
- Kein AdminBot-/Shell-/Desktop-Bypass über den Native-Pfad.
- Kein Cloud-Default für `abrain_native`; Cloud-Endpoints brauchen
  eigenen Follow-up-ADR analog zu `cloud_http`.
- Keine Änderung an `ABRAIN_CMD` oder am bestehenden CLI-Pfad.

**Tests / Verifikation:**

- Bestehender `abrain`-Provider-Test-Pfad (CLI-Echo) bleibt grün
  (PR 39 ist Docs-only, keine Code-Änderung).
- `cargo test` und `settings-shell-smoke` bleiben unverändert grün.

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
Self-Host) gelten sollen. Für die minimale CI-Smoke-Linie reicht
eine GitHub-Actions-Entscheidung; Packaging bleibt weiter aufgeschoben.
**Erledigt:**

- **PR 38 I-Release-CI-Foundation** *(2026-04-24, gelandet)*. Minimaler
  GitHub-Actions-Workflow unter
  [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) mit zwei
  Jobs: `core-test` (`cargo test --manifest-path core/Cargo.toml
  --locked` auf `ubuntu-latest` mit Rust stable) und `ui-smoke`
  (Godot 4.6 headless, offizielles Linux-Binary pinned via
  `GODOT_VERSION`, fünf kuratierte Smokes: `settings-shell-smoke`,
  `avatar-render-polish-smoke`, `workflow-visibility-smoke`,
  `approval-card-smoke`, `audit-panel-smoke`). Beide Jobs laufen mit
  `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` unterhalb `runner.temp`,
  damit das wiederkehrende lokale Dev-Artefakt-Problem unter
  `~/.config/smolit-assistant/` strukturell unmöglich ist.
  Parity-Helper für lokale Läufe:
  [`scripts/ci_verify.sh`](../scripts/ci_verify.sh). **Keine**
  Packaging-Formate (`.deb` / `.rpm` / Flatpak / Snap), **keine**
  Signing-Stufe, **kein** Artifact-Upload, **kein** Release-Tagging,
  **kein** Docker-Image — das bleibt eigener Folge-PR.

- **PR 42 I-CI-Hardening** *(2026-04-25, gelandet)*. Zwei kleine
  Härtungen am bestehenden Workflow — kein Release-Engineering:
  (1) **SHA512-Verifikation** des Godot-Binaries gegen die
  upstream-publizierte `SHA512-SUMS.txt`; `GODOT_SHA512` ist hart
  im Workflow gepinnt, `sha512sum -c` läuft nach dem Download und
  bricht fail-fast. Warum SHA512 statt SHA256: Godot veröffentlicht
  ausschließlich SHA512; eine selbst abgeleitete SHA256 wäre
  schwächer als der upstream-signierte Hash. (2) **Binary-Cache**
  via `actions/cache@v4` unter dem Single-Key `godot-${GODOT_VERSION}`
  — spart 30–60 s pro Run, kein Multi-Version-Scheme. Zusätzlich:
  Branch-Protection-Empfehlungen für `main` als Doku in
  [`docs/ci/BRANCH_PROTECTION.md`](./ci/BRANCH_PROTECTION.md) —
  Required checks `core-test` + `ui-smoke`, Required review 1,
  keine Auto-merge, keine Required deployments, keine Merge-Queue.
  **Keine** Packaging-Formate, **keine** Signing-Chain, **kein**
  Docker, **kein** Release-Tag, **kein** Dependabot, **keine**
  Matrix, **kein** Rust-Toolchain-Pinning.

**Nächster kleinster PR (Future Work, nicht priorisiert):**

- **PR 51 — Release Packaging Decision ADR** *(Vorschlag, Docs/
  ADR-only)*. Welche Distributionen zuerst (Ubuntu 24.04 gesetzt;
  Fedora / Arch / NixOS offen), welches Format (`.deb` vs.
  AppImage vs. Flatpak), wie Signing-Chain funktioniert. **Rein
  ADR, keine Implementation**, vor Code. *Hinweis:* PR-Nummer von
  ehemals PR 48 verschoben — PR 48 ist seit der Contract-Serie
  ADR-0006 (OceanData Context Provider SPI), siehe
  [`docs/reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md`](./reviews/PR49_ROADMAP_SYNC_AFTER_CONTRACTS.md).
- **CI-Folgearbeit (ohne Priorität):** optionale Cross-Linux-Matrix
  (Ubuntu 24.04 + Arch-Container) sobald Packaging-ADR landet,
  Rust-toolchain-Pinning via `rust-toolchain.toml` wenn Edition-/
  MSRV-Stabilität zum Thema wird.

**Nicht-Ziele (unverändert):**

- Keine Package-Manager-Pakete (deb/rpm/flatpak) in diesem Schritt.
- Keine Cloud-Build-Pipeline.
- Keine Install-Skripte — PR 29 / PR 38 dokumentieren ausschließlich.
- Kein Release-Tagging, keine signierten Releases, kein Auto-Update.
- Keine Secrets in CI, keine echten Provider-Endpunkte, keine
  echten TTS/STT-Binaries.

**Tests / Verifikation:**

- `cargo test` grün (398 Tests inkl. Policy-v0-Tripwire,
  whisper_cpp-Fallback und piper-Fallback).
- Fünf UI-Smokes laufen headless durch; lokal via
  `scripts/ci_verify.sh` reproduzierbar.
- README/SETUP wurden auf einem frischen Dev-Host manuell
  durchgelesen; die dort dokumentierte Quick-Start-Sequenz spiegelt
  den tatsächlichen Build-Pfad. Seit PR 38 ergänzt
  `docs/SETUP.md §7 — CI / Local verification parity` den
  Isolations-Kontext.

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

**Blocker:** Export-Pipeline in smolitux-ui ist weiterhin **nicht**
entschieden. Seit PR 35 existiert der
[Smolitux Token Contract v0](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md)
als Docs/Schema-only — die *Datenform* ist damit dokumentiert, die
*Implementation* weiterhin offen (kein Export-Format gewählt, kein
Generator, kein Validator). Bis dahin bleibt auf Smolit-Assistant-
Seite nur die ADR-Ebene plus der lokale Andockpunkt in
[`ui/scripts/avatar/avatar_palette.gd`](../ui/scripts/avatar/avatar_palette.gd)
machbar.

**Nächster kleinster PR (Future Work, nicht priorisiert):**

- **Token-Example-Validation-ADR** *(cross-repo, primär in
  smolitux-ui)*. Entscheidet, ob das Beispiel
  `docs/design/examples/smolitux.tokens.example.json` aus PR 35
  durch einen kleinen, repo-lokalen Validator geprüft wird — oder
  ob die Validation-Expectations (§11 des Token Contract) erst mit
  einem echten Export-Target umgesetzt werden. **Kein** Export-
  Build in Smolit-Assistant, **kein** Import, **keine**
  `@smolitux/*`-Abhängigkeit in diesem Repo.
- **Alternativ: Token-Generator-ADR** *(cross-repo, smolitux-ui)*.
  Style Dictionary vs. eigener Transformer vs. „gar nicht".
  Entscheidung *vor* Code. Ebenfalls keine Assistant-Änderung.

**Erledigt** (kein offener J-PR mehr im Smolit-Assistant-Repo):

- PR 24 J-Cross-Repo-ADR: ADR-0001 in beiden Repos, Glossar /
  ROADMAP / OPEN_WORK / `ui_architecture.md` um den
  Design-Contract-Orientierungsblock ergänzt.
- **PR 35 J-Smolitux-Token-Contract-Prep** *(2026-04-24, gelandet,
  cross-repo, primär in smolitux-ui)*. Token Contract v0 als
  Docs/Schema-only auf der smolitux-ui-Seite
  ([`docs/design/SMOLITUX_TOKEN_CONTRACT.md`](https://github.com/Modularium/smolitux-ui/blob/main/docs/design/SMOLITUX_TOKEN_CONTRACT.md))
  inkl. non-authoritatives JSON-Beispiel. In Smolit-Assistant
  selbst: ADR-0001 verlinkt den Token Contract, `ui_architecture.md`
  markiert `avatar_palette.gd` als **lokalen** Andockpunkt (kein
  Token-Consumer), ROADMAP und dieser Abschnitt spiegeln den
  Docs-Status. **Keine** Code-Änderung, **keine** Token-
  Implementation, **keine** Generatoren, **keine** OceanData-
  Berührung.

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

## K — OceanData Data-Layer Boundary

**Status:** **Kein** Berührungspunkt zu Smolit-Assistant heute.
OceanData bleibt Data-Layer / Datenplattform im Smolitux-
Ökosystem — **keine** UI-Library, **kein** Design-System,
**kein** UI-Komponenten-Lieferant, **kein** Token-Quellen-Repo.
Seit PR 40 existiert der Rahmen für eine zukünftige Anbindung als
Proposed ADR.
**Warum wichtig:** Ohne schriftlich fixierten Rahmen könnte eine
spätere OceanData-seitige Designwahl Smolit-Assistant zu einer
Anpassung zwingen, die die Lokal-first-Linie oder die
Gate-Pfade (Approval, Audit, Secret-Store, Policy) umgeht.
**Blocker:** OceanData-seitiges Interface / Scope-Definition
liegt außerhalb dieses Repos. Vor dem Gegenstück-ADR auf
OceanData-Seite (FA-1) entsteht kein Smolit-Assistant-Code.
**Erledigt (Decision only):**

- **PR 40 K-OceanData-Data-Layer-Integration-ADR**
  *(2026-04-24, gelandet, Docs/ADR-only, Status **Proposed**)*.
  [`ADR-0004`](./adr/ADR-0004-oceandata-data-layer-integration.md)
  formt aus der bisherigen rein-negativen Abgrenzung einen aktiven
  Designrahmen. Kernaussagen: OceanData wird als **Data-/Kontext-
  Provider** betrachtet (nicht als Text-LLM-Provider); erste
  Integration ist **read-only** (`query_context` /
  `list_available_contexts` / `fetch_context_summary`), lokal-
  first (Unix-Socket / Loopback), **kein** Cloud-Default,
  **kein** UI-Komponentenimport, **kein** Token- oder
  Design-System-Bezug, **kein** Tool-/Desktop-/AdminBot-Bypass
  über OceanData. Jede Action, die aus Kontext abgeleitet wird,
  läuft durch Approval/Policy/Audit (PR 25 / PR 19 / PR 32).
  ABrain bekommt **keinen** unrestrictierten OceanData-Zugriff —
  nur indirekt, als redacted Summary über den Core. Ein
  Privacy-/Redaction-Layer ist bindende Voraussetzung, bevor
  OceanData-Kontext an externe Provider geht. Heute **keine**
  Code-Änderung, **keine** IPC-Commands, **keine** neue
  Abhängigkeit.

**Erledigt in PR 48 (2026-04-25, Docs/ADR-only):**
[`ADR-0006`](./adr/ADR-0006-oceandata-context-provider-spi.md)
schließt ADR-0004 §11 FA-2 auf Doku-Ebene. Context-Provider-
Achsen-Form fixiert (parallel zu Text/STT/TTS, kandidaten Kinds
`local_static_context` / `oceandata_context`); ProviderConfig +
Request/Response Object-Model (`contract_version`, `request_id`,
optionale `correlation_id`, `redaction = local_only|external_safe`,
`include_provenance`); Capability-Mapping auf
`data.context.query` / `data.context.summary` /
`data.decide.access`; 13 benannte Failure-Modes
(`context_scope_not_allowed`, `sensitivity_not_allowed`,
`provenance_missing`, `too_many_results`, `redaction_required`,
`external_forwarding_denied`, …); explizite Ausschlüsse: keine
Write-/Sync-/Vector-DB-Operationen, niemals in
`text_provider_chain`, default-off. Begleitend: ADR-0004 FA-2 mit
Link versehen, Matrix Pair 4 + Pair 5 aktualisiert,
CAPABILITY_VOCABULARY §5.4 + AUDIT_CORRELATION_ID_SPEC §7
verlinken ADR-0006.

**Nächster kleinster PR (Future Work, nicht priorisiert):**

- **FA-1 — OceanData-side contract doc** *(cross-repo)*. OceanData-
  Repo spiegelt ADR-0004 §6 / ADR-0006 §7 als verbindliches
  Wire-Schema (Versionierung, Auth-Modell, Rate-Limits,
  Sensitivity-Semantik).
- **FA-2 — Context-provider SPI ADR** — **erledigt in PR 48**
  ([`ADR-0006`](./adr/ADR-0006-oceandata-context-provider-spi.md)).
  *Implementation* (Trait, Config-Namespace, Spike-Client) bleibt
  eigene Folge-PR-Reihe (siehe ADR-0006 §17 OC-1…OC-7).
- **FA-3 — Read-only local endpoint spike** *(Smolit-Assistant)*.
  Erster Client hinter Feature-Flag, Unix-Socket / Loopback,
  Wire-Schema aus ADR-0004 §6 + ADR-0006 §7 geprüft. Vorbedingung:
  AUDIT_CORRELATION_ID_SPEC FA-1 (`correlation_id` in `AuditEvent`)
  + CAPABILITY_VOCABULARY FA-1 (Code-Konstanten).
- **FA-4 — Sensitivity-/Provenance-Schema** als eigener ADR.
- **FA-5 — Privacy/Redaction-Layer** vor externer Weitergabe
  (Cloud-fähige ABrain, `cloud_http`); Eintrittsbedingung für
  `redaction = external_safe` aus ADR-0006.
- **FA-6 — ABrain-context handoff ADR** *(cross-repo)*. Format
  des redacted Summaries, niemals OceanData-Handle-Pass-Through;
  spiegelt ADR-0006 §13.

**Nicht-Ziele (unverändert):**

- **Keine OceanData-Code-Integration** vor FA-1/FA-2.
- **Keine Uminterpretation** von OceanData als UI-/Design-System.
- **Keine neuen Kern-Abhängigkeiten** auf OceanData-Pakete.
- **Kein Cloud-Default**, kein Auto-Aktivieren.
- **Kein Schreib-Pfad** in v1 (read-only first).
- **Kein direct-Transit** von OceanData zu ABrain.

**Tests / Verifikation:**

- `rg "OceanData"` im gesamten Repo darf **nie** OceanData als
  UI-Library, Design-System-Quelle oder Smolit-Assistant-
  Backend beschreiben. Mit ADR-0004 aktiv eingehalten —
  alle Treffer sind entweder Abgrenzung oder Future-Work-
  Verweis.
- Markdown-Links bleiben konsistent.
- PR 40 ist Docs/ADR-only, keine neuen Tests: bestehende
  `cargo test` (398 pass) und `settings-shell-smoke` (PASS)
  bleiben unverändert grün.

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
