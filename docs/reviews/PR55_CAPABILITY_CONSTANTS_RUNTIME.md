# PR 55 — Capability Constants Runtime Spike

- **Date:** 2026-04-26
- **Workstream:** E (Approval / Policy / Tool-Gating)
- **Branch:** `feat/capability-constants-runtime`
- **Status:** landed (code-spike, additive, default-on within
  Smolit-Assistant; no cross-repo wire).
- **Spec:** [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md)
  — implements §12 FA-1 + FA-2 locally.

---

## 1. Scope

Erste Code-Implementation des Capability-Vokabulars als kleine,
**rein deskriptive** Konstanten-/Mapping-Schicht im Smolit-Assistant
Core. Eine Aktion, die der Core lokal plant, trägt ab jetzt einen
kanonischen Capability-Namen (`interaction.open_application`,
`assistant.demo.echo`, …) durch Audit- und Approval-Lifecycle.

PR 55 bleibt eng:

- **Lokal.** Kein Cross-Repo-Wire, kein Echo, kein
  AdminBot-Mapping, kein OceanData-Mapping.
- **Additiv.** Kein neues IPC-Command, kein neues
  Outgoing-Envelope, keine UI-Änderung.
- **Descriptive metadata.** Die Capability-ID ist **kein**
  Eingabewert für eine Permission-Entscheidung. Approval / Risk /
  Policy v0 bleiben führend.
- **Statisch.** Keine dynamische Registry, keine Lade-Datei, kein
  Plug-in.

## 2. Implemented

### 2.1 Capability-Modul

- Neues Modul [`core/src/capabilities.rs`](../../core/src/capabilities.rs)
  + `mod capabilities;` in [`core/src/main.rs`](../../core/src/main.rs).
- 18 String-Konstanten gemäß
  [`CAPABILITY_VOCABULARY.md` §5](../contracts/CAPABILITY_VOCABULARY.md):
  - **Interaction:** `interaction.open_application`,
    `interaction.focus_window`, `interaction.type_text`,
    `interaction.send_shortcut`.
  - **Assistant:** `assistant.plan_demo_action`,
    `assistant.demo.echo`, `assistant.demo.wait`.
  - **Admin** (Dokumentations-Konstanten — `is_executable_today`
    = `false`): `admin.status.read`, `admin.capability.describe`,
    `admin.action.dry_run`, `admin.action.execute`.
  - **Data** (Dokumentations-Konstanten):
    `data.context.query`, `data.context.summary`,
    `data.decide_access`.
  - **Provider:** `provider.text.generate`,
    `provider.stt.transcribe`, `provider.tts.speak`.
  - **Audit:** `audit.read_recent`.
- `KNOWN_CAPABILITY_IDS: &[&str]`-Whitelist (Reihenfolge spiegelt
  die Spec-Reihenfolge).
- Format-Konstanten `MAX_CAPABILITY_ID_LEN = 64`,
  `MIN_CAPABILITY_SEGMENTS = 2`, `MAX_CAPABILITY_SEGMENTS = 4`.

### 2.2 Mapping-Helfer

- `capability_id_for_interaction(InteractionKind) -> Option<&'static str>`
  — `OpenApplication` / `FocusWindow` / `TypeText` /
  `SendShortcut` → kanonische ID; `Noop` / `Unknown` → `None`.
- `capability_id_for_demo_kind(&str) -> Option<&'static str>` —
  `demo_echo` → `assistant.demo.echo`,
  `demo_wait` → `assistant.demo.wait`,
  `noop` → `assistant.plan_demo_action`. Unbekannte Strings → `None`.
- `capability_id_for_plan(&str) -> &'static str` — Convenience
  mit Fallback auf `assistant.plan_demo_action`.

### 2.3 Metadaten-Helfer (descriptive, NOT enforcement)

- `is_known_capability_id(&str) -> bool`.
- `is_executable_today(&str) -> bool` — heute lokal ausführbare
  Capabilities (alle Admin/Data IDs liefern `false`).
- `risk_for_capability(&str) -> Option<&'static str>` —
  spiegelt das `risk_level` aus Vocab §5; nutzt die kanonischen
  `RISK_LOW` / `RISK_MEDIUM` / `RISK_HIGH`-Konstanten.
- `requires_approval_by_default(&str) -> Option<bool>`,
  `audit_required_by_default(&str) -> Option<bool>`,
  `correlation_required_by_default(&str) -> Option<bool>` —
  spiegeln die Soll-Linie aus §5; **keine** Eingabe in eine
  Policy-Engine.

### 2.4 Sanitization

- `sanitize_capability_id(Option<String>) -> Option<String>`
  validiert gegen Naming-Regeln aus Vocab §3 (Charset, Segmente,
  Maximallänge) **und** gegen die `KNOWN_CAPABILITY_IDS`-
  Whitelist. Unbekannte oder kaputte Tokens werden zu `None`
  geklemmt.

### 2.5 Audit-Felder

- [`AuditEvent.capability_id: Option<String>`](../../core/src/audit/event.rs)
  und `AuditFields.capability_id` sind neu, optional, mit
  `#[serde(default, skip_serializing_if = "Option::is_none")]`.
- `AuditFields::with_capability_id(...)` und
  `with_capability_id_opt(Option<...>)` als Builder.
- `AuditFields::sanitized()` läuft über
  `crate::capabilities::sanitize_capability_id` — User-Strings
  ohne Vocab-Eintrag landen **nie** im Store.
- [`AuditStore::build_event`](../../core/src/audit/store.rs)
  spiegelt das Feld in den `AuditEvent`.

### 2.6 Approval-Felder

- [`ApprovalRequest.capability_id: Option<String>`](../../core/src/approvals/request.rs)
  als zweites additives Feld neben `correlation_id` (PR 54).

### 2.7 App-Wiring

[`core/src/app.rs`](../../core/src/app.rs):

- **`request_approval_demo`** — schreibt
  `assistant.plan_demo_action` in `ApprovalRequest.capability_id`.
- **`plan_demo_action`** — bestimmt einmal
  `let capability_id = capability_id_for_plan(&plan.kind);`
  und schreibt es in:
  - `IpcCommandReceived` (Audit)
  - `ActionPlanned` (Audit)
  - `ApprovalRequest` (Wire) + `ApprovalRequested` (Audit) auf
    dem Approval-Pfad.
- **`await_and_execute_demo_plan`** — schreibt es in
  `ApprovalResolved` (Audit). Cancel-Branches erben es über
  `record_plan_cancel_audit`.
- **`record_plan_cancel_audit`** — leitet die Capability aus
  `plan.kind` ab.
- **`execute_demo_plan`** — schreibt es in `ActionStarted` und
  `ActionCompleted` (Audit).
- **`dispatch_interaction`** — bestimmt einmal
  `let capability_id = capability_id_for_interaction(action.kind());`
  und schreibt es in `IpcCommandReceived`, `ActionPlanned`,
  Policy-Refusal `ActionFailed`, `ApprovalRequest` (Wire) +
  `ApprovalRequested` (Audit).
- **`await_and_continue`** — schreibt es in `ApprovalResolved`
  (Audit) und in den Cancel-Branch `ActionCancelled` (Audit).
- **`record_interaction_lifecycle_audit`** — schreibt es in alle
  vier Audit-Lifecycle-Frames (`ActionStarted`,
  `ActionCompleted`, `ActionFailed`, `ActionCancelled`).

Read-only-Pfade (`probe_accessibility`, `discover_accessibility`,
`submit_text` / `speak_text`-Helper, `ping`, `get_status`,
`audit_recent` selbst, Settings-Probes) **lassen** das Feld leer
— entsprechend Vocab §5.6 *Anti-Rekursion*.

### 2.8 Tests

- **13 Unit-Tests** in
  [`core/src/capabilities.rs`](../../core/src/capabilities.rs):
  `known_capability_ids_match_documented_values`,
  `capability_ids_match_naming_rules`,
  `interaction_kind_maps_to_expected_capability_ids`,
  `demo_kind_maps_to_expected_capability_ids`,
  `unknown_demo_kind_has_no_capability_id`,
  `executable_today_is_false_for_admin_and_data_capabilities`,
  `executable_today_is_true_for_local_live_capabilities`,
  `requires_approval_metadata_matches_current_interaction_policy`,
  `audit_metadata_marks_real_interactions_audit_required`,
  `correlation_required_metadata_marks_high_risk_capabilities`,
  `sanitize_capability_id_accepts_known_values`,
  `invalid_capability_id_is_not_accepted`,
  `risk_for_capability_uses_known_risk_constants`.
- **6 IPC-Lifecycle-Tests** in
  [`core/src/ipc/server.rs`](../../core/src/ipc/server.rs):
  `plan_demo_action_audit_events_include_capability_id`,
  `open_application_approved_chain_includes_capability_id`,
  `open_application_denied_chain_keeps_capability_id`,
  `capability_id_is_additive_in_audit_recent_serialization`,
  `invalid_capability_id_is_not_accepted_into_audit_fields`,
  `unsupported_interactions_are_mapped_but_not_enabled`.
- Bestehende PR-54-`correlation_id`-Tests bleiben grün.
  `cargo test` 443 passed (war 424 vor PR 54, 437 nach den
  Capabilities-Unit-Tests).

### 2.9 Docs

- [`CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md)
  Status auf "Runtime FA-1 implemented" gesetzt; §11 Non-Goals
  und §12 Future Work mit den PR-55-Resultaten ergänzt
  (FA-1 + FA-2 erledigt).
- [`AUDIT_CORRELATION_ID_SPEC.md`](../contracts/AUDIT_CORRELATION_ID_SPEC.md)
  notiert, dass AuditEvents nun `correlation_id` und
  `capability_id` gemeinsam tragen.
- [`docs/api.md`](../api.md): neuer Unterabschnitt "Optional:
  `capability_id` (PR 55)" und Erweiterung des
  `audit_recent`-Eintrags.
- [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md):
  neuer Unterabschnitt mit den Whitelist- und
  Sanitisierungs-Garantien.
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md): Workstream E mit
  PR-55-Resultaten; Vocabulary-FA-3-Eintrag als erledigt markiert.
- [`ROADMAP.md`](../../ROADMAP.md) §6.4: PR 55 von "Vorschlag" auf
  "gelandet" umgestellt.
- Reviews-Index aktualisiert (siehe
  [`docs/reviews/README.md`](./README.md)).

## 3. Not implemented

- **Keine Policy Engine.** Die Metadaten-Helfer sind
  beschreibend; sie fließen in keine Approval-Entscheidung. Die
  Policy v0 (PR 25) bleibt führend.
- **Keine Runtime-Registry.** Die Konstanten sind statisch
  einkompiliert; kein Plug-in, keine Lade-Datei.
- **Kein Cross-Repo-Wire.** Kein ABrain-Echo, kein
  AdminBot-Pflicht-Pfad, kein OceanData-Akzeptanz.
- **Kein neues IPC-Command, kein neues Outgoing-Envelope.**
- **Keine UI-Änderung.** Approval-Card und Audit-Panel zeigen
  `capability_id` heute nicht.
- **Action-Event-Payloads tragen kein `capability_id`.** Eine
  spätere additive Erweiterung wäre möglich (Vocab FA-4 → FA-6).
- **Kein `type_text` / `send_shortcut`-Backend.** Mapping-
  Konstanten existieren, aber `is_executable_today` liefert
  `false` und der Backend-Pfad bleibt `BackendUnsupported`.
- **Kein Auto-Approval, keine Risk-Verschiebung.** Capability-
  Metadata darf Risk nicht still ändern; das wird in den Tests
  geprüft.

## 4. Runtime behavior

Beispielablauf für ein
`{"type":"interaction_open_application","application":"calendar"}`:

1. Core empfängt Command, generiert `corr_…` (PR 54), bestimmt
   `capability_id = interaction.open_application` (PR 55),
   schreibt `IpcCommandReceived` (Audit) mit beiden Feldern.
2. Sendet `action_planned` (Wire trägt `correlation_id`),
   schreibt `ActionPlanned` (Audit) mit `correlation_id` +
   `capability_id`.
3. Sendet `approval_requested` (Wire trägt `correlation_id` +
   `capability_id`), schreibt `ApprovalRequested` (Audit) mit
   beiden Feldern.
4. UI antwortet mit `approval_response`/`approval_approve`.
5. Core sendet `approval_resolved` (Wire trägt
   `correlation_id`), schreibt `ApprovalResolved` (Audit) mit
   `correlation_id` + `capability_id`.
6. Executor läuft: `action_started`, `action_step`,
   `action_step`, `action_verification`, `action_completed`
   (Wire trägt `correlation_id`); parallele Audit-Frames mit
   beiden Feldern.

Cancel-Pfade (Denied / Cancelled / TimedOut) verzweigen,
schreiben `action_cancelled` (Wire mit `correlation_id`) und
`ActionCancelled` (Audit mit beiden Feldern). Re-Approve auf
demselben `approval_id`: `ipc_command_rejected` Audit, **keine**
zweite Capability-/Korrelations-ID.

Demo-Pfad
`{"type":"plan_demo_action","kind":"demo_echo","requires_approval":false}`:

- `IpcCommandReceived` / `ActionPlanned` / `ActionStarted` /
  `ActionCompleted` (Audit) tragen alle
  `capability_id = "assistant.demo.echo"`.

## 5. Wire compatibility

- **Backwards-compatible.** Das neue Feld ist überall optional
  und wird dank `skip_serializing_if = "Option::is_none"` nur
  emittiert, wenn der Core es gesetzt hat.
- **Frontwards-tolerant.** Ältere UIs (vor PR 55) ignorieren
  `capability_id` und sehen sonst dieselbe Wire-Form wie vorher.
- **Kein neuer Variant.** `IncomingMessage` /
  `OutgoingMessage` haben **keine** neue Variante; PR 55 fügt
  Felder zu `AuditEvent` (audit_recent payload) und
  `ApprovalRequest` (approval_requested payload) hinzu.
- **`audit_recent` kompatibel.** Pro Event ggf. zusätzlich
  `capability_id`; ältere Reader ignorieren es. Test
  `capability_id_is_additive_in_audit_recent_serialization`
  lockt das.

## 6. Security constraints

- **Whitelist-only.** `AuditFields::sanitized()` und
  `sanitize_capability_id` erlauben ausschließlich Werte aus
  `KNOWN_CAPABILITY_IDS`. Test
  `invalid_capability_id_is_not_accepted_into_audit_fields`
  verteidigt gegen User-Strings.
- **Naming-Regeln aus Vocab §3 erzwungen.** Charset, Segmente,
  Maximallänge werden vor der Whitelist-Prüfung geprüft —
  CamelCase, Bindestriche, leere Segmente und übergroße Tokens
  scheitern.
- **Beschreibend, nicht enforcend.** `risk_for_capability`,
  `requires_approval_by_default`, `audit_required_by_default`,
  `correlation_required_by_default` sind reine Soll-Spiegel; sie
  ändern keine Approval-Entscheidung. Tests
  `requires_approval_metadata_matches_current_interaction_policy`
  und Verwandte locken das Soll gegen Drift, ohne die
  Runtime-Linie zu verändern.
- **Admin/Data sind Dokumentations-Konstanten.**
  `is_executable_today` liefert für `admin.*` und `data.*`
  `false`. Test
  `executable_today_is_false_for_admin_and_data_capabilities`
  verteidigt das gegen versehentliche Aktivierung.
- **Audit-Sanitization-Regeln aus
  [`AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md) bleiben
  unverändert.** `capability_id` darf weder Command-Templates
  noch Env-Namen noch Secrets transportieren — der Whitelist-
  Filter macht das strukturell unmöglich.

## 7. Verification

Lokal ausgeführt:

```bash
bash scripts/ci_verify.sh core
# → 443 passed; 0 failed; ci_verify: PASS

bash scripts/run_overlay_verification.sh settings-shell-smoke
# → settings_shell smoke: PASS

cargo test --manifest-path core/Cargo.toml --locked
# (gleiche 443 Tests; CI-Skript setzt zusätzlich XDG-Isolation,
#  damit zwei pre-existing settings_store-Tests nicht über
#  lokale Konfig-Drift fallen — siehe PR 51.)
```

Greps (alle erwartet sauber):

```bash
rg "<<<<<<<|=======|>>>>>>>" core docs README.md ROADMAP.md
# → keine Konflikt-Marker (außer den Such-Patterns selbst in
#   den Review-Dateien)

rg "Policy Engine|registry" core
# → ausschließlich Doc-Kommentare, die "keine Policy Engine /
#   keine Registry" festhalten

rg "AdminBot|OceanData|ABrain" core
# → ausschließlich pre-existing Test-Strings + Spec-Verweise

rg "capability_id" core/src
# → capabilities.rs, audit/{event,store}.rs, approvals/request.rs,
#   ipc/{server,protocol}.rs, app.rs
```
