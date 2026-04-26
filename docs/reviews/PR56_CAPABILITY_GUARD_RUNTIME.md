# PR 56 — Capability Guard Runtime Spike

- **Date:** 2026-04-26
- **Workstream:** E (Approval / Policy / Tool-Gating)
- **Branch:** `feat/capability-guard-runtime`
- **Status:** landed (code-spike, additive, fail-closed,
  deny-only). Kein Cross-Repo-Wire, keine Policy Engine.
- **Spec:** [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md)
  — implementiert §12 FA-3 (Runtime-Guard, deny-only) lokal in
  Smolit-Assistant.

---

## 1. Scope

Ein kleiner, deterministischer Guard über den in PR 55 eingeführten
Capability-Konstanten. Er nutzt die descriptive Metadaten
(`is_known_capability_id`, `is_executable_today`, plus die
spezifischen `INTERACTION_*`-Konstanten), um Future- /
Unsupported- / Unbekannte Capabilities **vor** dem bestehenden
Approval- und Policy-v0-Pfad fail-closed abzulehnen.

PR 56 bleibt eng:

- **Lokal.** Kein Cross-Repo-Wire, kein OPA/Rego, kein Distributed
  Decision Engine.
- **Additiv.** Kein neues IPC-Command, kein neues
  Outgoing-Envelope, keine UI-Änderung, kein neuer IncomingMessage-
  Variant.
- **Deny-only.** Der Guard kann nur zusätzlich verweigern. Er
  hebt **keine** bestehende Sperre auf, vergibt **keine** neuen
  Rechte und ändert **keine** Risk-Klassifikation.
- **Statisch.** Keine dynamische Registry, keine Lade-Datei, kein
  Plug-in.

Leitprinzip: *Capability metadata may deny unsupported or future
capabilities, but it must not grant new powers.*

## 2. Implemented

### 2.1 Guard-Modul

- Neues Modul [`core/src/capability_guard.rs`](../../core/src/capability_guard.rs)
  + `mod capability_guard;` in [`core/src/main.rs`](../../core/src/main.rs).
- Decision-Typ `CapabilityGuardDecision` mit Varianten
  `Allow` und `Deny { reason: &'static str, recovery_hint:
  Option<&'static str> }`. Hilfsmethoden `is_allow`, `is_deny`,
  `reason_str` für Logger.
- Input-Typ `CapabilityGuardInput` mit optionalen Feldern
  (`capability_id`, `action_kind`, `source`, `correlation_id`).
  `for_capability(id)`-Convenience-Konstruktor.
- Drei öffentliche Entry-Helfer:
  - `guard_capability(input) -> CapabilityGuardDecision` — die
    generische Variante, sortiert nach den fünf Deny-Klassen.
  - `guard_interaction_kind(InteractionKind)` — mapped via
    [`crate::capabilities::capability_id_for_interaction`].
  - `guard_demo_kind(&str)` — mapped via
    [`crate::capabilities::capability_id_for_plan`] mit Fallback
    auf `assistant.plan_demo_action`.
- Fünf kuratierte Deny-Reasons in `KNOWN_GUARD_REASONS`:
  `unknown_capability_id`,
  `capability_not_executable_today`,
  `future_capability_not_implemented`,
  `interaction_type_text_not_supported`,
  `interaction_send_shortcut_not_supported`.
- Recovery-Hint-Konstante
  `RECOVERY_HINT_FALLBACK_UNAVAILABLE` (kompatibel zum
  bestehenden [`crate::interaction::recovery::RecoveryHint`]-
  Vokabular).

### 2.2 Audit-Erweiterung

- Neuer Whitelist-Wert `RESULT_CAPABILITY_GUARD_DENIED =
  "capability_guard_denied"` in
  [`core/src/audit/event.rs`](../../core/src/audit/event.rs);
  re-export in
  [`core/src/audit/mod.rs`](../../core/src/audit/mod.rs).
- Bewusst **getrennt** von `RESULT_FAILED`: ein Guard-Deny ist
  eine deterministische Vor-Filterung, kein Backend-Fehler.
  UI/Audit-Reader können den Unterschied lesen, ohne neue Felder
  zu parsen.

### 2.3 App-Wiring

[`core/src/app.rs`](../../core/src/app.rs):

- **`dispatch_interaction`** (Hot-Path) — der Guard läuft **nach**
  IpcCommandReceived + ActionPlanned (so bleibt der Lifecycle
  audit-sichtbar) und **vor** `interaction.policy().allows`. Auf
  Deny emittiert der neue Helper `emit_capability_guard_denied`
  die Wire-Sequenz `action_started` → `action_failed` mit
  Präfix `capability_guard_denied: <reason>` und
  `error = "recovery_hint=fallback_unavailable"`. Der Audit-
  Eintrag trägt `result = "capability_guard_denied"`,
  `correlation_id`, `capability_id` und `summary` mit Suffix
  `[guard:<reason>]`. Es wird **kein** `approval_requested`
  emittiert.
- **`plan_demo_action`** — defensiver Guard nach Korrelations-
  Generierung. Heute liefert er für die drei Demo-Kinds immer
  Allow; auf einen hypothetischen Drift hin (Mapping-Bug) gibt
  er ein einzelnes `action_failed` zurück, ohne den Mock-Executor
  zu starten.
- **`request_approval_demo`** — defensiver Guard am Eingangstor.
  Heute Allow für `assistant.plan_demo_action`; auf Drift hin
  ein `error`-Envelope statt einer ApprovalRequest-Karte ohne
  ausführbare Capability.

### 2.4 Tests

- **17 Unit-Tests** in
  [`core/src/capability_guard.rs`](../../core/src/capability_guard.rs):
  `guard_allows_open_application`,
  `guard_allows_focus_window_without_overriding_executor_policy`,
  `guard_allows_demo_echo`,
  `guard_allows_demo_wait`,
  `guard_allows_plan_demo_action_for_noop_and_unknown_kind`,
  `guard_denies_unknown_capability_id`,
  `guard_denies_missing_capability_id`,
  `guard_denies_admin_future_capability`,
  `guard_denies_data_future_capability`,
  `guard_denies_type_text`,
  `guard_denies_send_shortcut`,
  `guard_denies_noop_and_unknown_interactions`,
  `guard_decision_is_descriptive_not_policy_engine`,
  `guard_allows_audit_read_recent_anti_recursion`,
  `guard_allows_provider_capabilities_descriptively`,
  `guard_allows_known_capabilities_for_existing_lifecycles`,
  `known_guard_reasons_are_short_and_safe`.
- **9 IPC-Integrationstests** in
  [`core/src/ipc/server.rs`](../../core/src/ipc/server.rs)
  (Test-Modul am Ende):
  `open_application_still_requires_existing_approval_after_guard`,
  `focus_window_still_respects_existing_disabled_default_after_guard`,
  `plan_demo_action_still_emits_capability_and_correlation_ids`,
  `guard_deny_for_type_text_emits_capability_guard_denied_audit`,
  `guard_deny_for_send_shortcut_emits_capability_guard_denied_audit`,
  `unsupported_interactions_remain_unsupported`,
  `pr54_correlation_lifecycle_still_stable`,
  `pr55_capability_audit_lifecycle_still_stable`,
  `request_approval_demo_still_emits_capability_id_after_guard`.
- Bestehende PR-54-`correlation_id`- und PR-55-`capability_id`-
  Tests bleiben grün. `cargo test` 469 passed (war 443 nach
  PR 55).

### 2.5 Docs

- [`CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md):
  Status auf "Runtime FA-1 + FA-2 (PR 55) + Runtime Guard
  (PR 56)" gesetzt; §11 Non-Goals und §12 Future Work spiegeln
  PR 56 (FA-3 teilweise erledigt; FA-4 / FA-5 / FA-6 bleiben
  Folgearbeit; AdminBot-/OceanData-Bindung bleibt eigene PR).
- [`docs/api.md`](../api.md): neuer Unterabschnitt "Capability
  Guard fail-closed Deny (PR 56)" unter Action Events;
  `audit_recent`-Eintrag listet die erweiterte Result-Whitelist
  inkl. `capability_guard_denied`.
- [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md):
  neuer Unterabschnitt mit Whitelist-only-Garantien für den
  Reason-Suffix in `summary`.
- [`docs/OPEN_WORK.md`](../OPEN_WORK.md): Workstream E mit
  PR-56-Resultaten; FA-3-Eintrag teilweise abgehakt.
- [`ROADMAP.md`](../../ROADMAP.md) §6.4: PR 56 als gelandet mit
  vollem Scope/Test-Summary; PR 57 (OceanData Privacy / Redaction
  ADR) verschoben.
- Reviews-Index aktualisiert.

## 3. Not implemented

- **Keine Policy Engine.** Die Helper aus PR 55 sind
  beschreibend; PR 56 nutzt sie deny-only. Eine Privacy-/
  Provider-/Tenancy-Auswertungs-Engine bleibt eigene Folge-Arbeit.
- **Kein OPA / Rego im Core.** Die Guard-Entscheidung ist ein
  fester Match auf die kuratierten Konstanten — keine
  Regel-Sprache, keine externe Engine, keine dynamischen Regeln.
- **Keine dynamische Capability-Registry.** Konstanten sind
  statisch einkompiliert; kein Plug-in, keine Lade-Datei.
- **Kein Cross-Repo-Wire.** Kein ABrain-Echo, kein
  AdminBot-Pflicht-Pfad, kein OceanData-Akzeptanz.
- **Kein neues IPC-Command, kein neues Outgoing-Envelope.** Die
  Wire-Form für Allow- und Deny-Pfade nutzt ausschließlich
  bestehende Envelopes (`action_planned`, `action_started`,
  `action_failed`, `error`).
- **Keine UI-Änderung.** Approval-Card, Audit-Panel und Workflow-
  Visibility-Overlay zeigen nichts Neues.
- **Keine neue Desktop-Fähigkeit.** `type_text` und
  `send_shortcut` bleiben unsupported und ohne Backend.
- **Kein Focus-Window-Verhaltenswechsel.** Default-disabled
  + double-opt-in bleibt unverändert maßgeblich.
- **Kein Approval-Bypass.** Der Guard verweigert nur zusätzlich;
  er kann nichts erlauben, was Policy v0 oder die bestehende
  Config sperrt.

## 4. Runtime behavior

### Allow-Pfad (heute live: `interaction_open_application`)

1. Core empfängt Command, generiert `corr_…` (PR 54), bestimmt
   `capability_id = interaction.open_application` (PR 55).
2. Schreibt `IpcCommandReceived` + `ActionPlanned` (Audit) mit
   `correlation_id` + `capability_id`.
3. Sendet `action_planned` (Wire mit `correlation_id`).
4. **Guard läuft.** Decision = Allow → fällt durch in den
   bestehenden `policy.allows`-Zweig + Approval-Pfad.
5. Sendet `approval_requested` (Wire mit `correlation_id` +
   `capability_id`); existierende Approval-Linie aus PR 17 /
   PR 25 läuft unverändert.
6. Nach Approve: `action_started` → `action_step` →
   `action_completed` (Wire); Audit-Frames mit beiden Feldern.

### Deny-Pfad (synthetisch konstruiert: `TypeText`)

1. Core empfängt eine `InteractionAction { payload: TypeText }`
   (Test-only — der IPC exponiert keinen `type_text`-Command).
2. `IpcCommandReceived` + `ActionPlanned` (Audit) wie oben.
3. Sendet `action_planned` (Wire).
4. **Guard läuft.** Decision = Deny mit
   `reason = interaction_type_text_not_supported`,
   `recovery_hint = fallback_unavailable`.
5. Sendet `action_started` → `action_failed { message:
   "capability_guard_denied: interaction_type_text_not_supported",
   error: "recovery_hint=fallback_unavailable" }` (Wire).
6. Schreibt einen `ActionFailed`-Audit-Eintrag mit
   `result = "capability_guard_denied"`,
   `correlation_id`, `capability_id = "interaction.type_text"`,
   `summary = "<title> [guard:interaction_type_text_not_supported]"`.
7. **Kein** `approval_requested`, **kein** Backend-Run.

### Allow-Pfad (Demo): `plan_demo_action` mit `kind=demo_echo`

Der defensive Guard liefert Allow → bestehender Mock-Executor
läuft wie in PR 55 beschrieben; Wire/Audit-Form unverändert.

### Defensiv (heute nicht erreichbar): `request_approval_demo`

Guard liefert Allow für `assistant.plan_demo_action` → bestehende
ApprovalRequested-Wire wie in PR 55. Auf hypothetischen Drift hin
würde der Core ein `error`-Envelope mit
`capability_guard_denied: <reason>` zurückgeben statt einer
ApprovalRequest-Karte.

## 5. Wire compatibility

- **Backwards-compatible.** Keine bestehenden Felder verändert.
  `RESULT_CAPABILITY_GUARD_DENIED` ist ein neuer Whitelist-Eintrag
  in der `result`-Vokabular-Whitelist; ältere Reader, die nur die
  alten Werte kennen, sehen einen unbekannten String — sicher,
  weil `result` immer optional ist und kein Code es als
  Permission-Eingabe nutzt.
- **Frontwards-tolerant.** Allow-Pfade verändern weder Wire- noch
  Audit-Form gegenüber PR 55. Tests
  `pr54_correlation_lifecycle_still_stable` und
  `pr55_capability_audit_lifecycle_still_stable` locken das.
- **Kein neuer Variant.** `IncomingMessage` /
  `OutgoingMessage` haben **keine** neue Variante. Deny-Pfade
  recyceln `ActionStarted`, `ActionFailed`, `Error`.
- **`audit_recent` kompatibel.** Pro Event ggf. zusätzlich
  `result = "capability_guard_denied"`; `summary` trägt den
  Suffix `[guard:<reason>]`. Ältere Reader ignorieren den
  unbekannten Result-Wert.

## 6. Security constraints

- **Whitelist-only.** Reason-Tokens stammen ausschließlich aus
  [`KNOWN_GUARD_REASONS`]; Test
  `known_guard_reasons_are_short_and_safe` prüft Charset, Länge
  und Snake-Case. Kein User-Input fließt jemals als Reason in
  Audit oder Wire.
- **Capability-IDs aus Konstanten.** Der Guard nimmt keine
  Strings aus IPC-Frames als Capability — er ruft
  `capability_id_for_interaction` / `capability_id_for_plan`
  auf, die wiederum aus `KNOWN_CAPABILITY_IDS` (PR 55) lesen.
- **Fail-closed.** Unbekannte / future / unsupported
  Capabilities werden lokal abgelehnt; es entsteht kein
  Approval-Request, kein Backend-Run, kein Provider-Aufruf.
- **Anti-Bypass.** Der Guard hebt **keine** bestehende Sperre
  auf. Er läuft **vor** `policy.allows`, aber `policy.allows`
  läuft danach trotzdem (Belt-and-Suspenders). Der Guard kann
  Allow nur dann liefern, wenn die Capability im Vokabular und
  `is_executable_today` ist.
- **Audit-Sanitization unverändert.** `summary` läuft weiterhin
  durch `sanitize_summary` (max. 80 Zeichen, Whitespace-Trim);
  der Guard-Reason-Suffix passt komfortabel in dieses Limit.
- **Kein Cross-Repo-Vertrauen.** Der Guard delegiert nichts an
  AdminBot / OceanData / ABrain. Eine Future-Cross-Repo-
  Variante wäre eigene PR.
- **Anti-Rekursion.** `audit.read_recent` liefert Allow im Guard,
  löst aber selbst keinen Audit-Eintrag aus — dieselbe Linie wie
  in [`AUDIT_CORRELATION_ID_SPEC.md` §9](../contracts/AUDIT_CORRELATION_ID_SPEC.md).

## 7. Verification

Lokal ausgeführt:

```bash
bash scripts/ci_verify.sh core
# → 469 passed; 0 failed; ci_verify: PASS

bash scripts/run_overlay_verification.sh settings-shell-smoke
# → settings_shell smoke: PASS

cargo test --manifest-path core/Cargo.toml --locked
# (gleiche 469 Tests; CI-Skript setzt zusätzlich XDG-Isolation,
#  damit zwei pre-existing settings_store-Tests nicht über
#  lokale Konfig-Drift fallen — siehe PR 51.)
```

Greps (alle erwartet sauber):

```bash
rg "capability_guard|CapabilityGuard|capability_not_executable_today|future_capability_not_implemented" core docs README.md ROADMAP.md
# → in core/src/capability_guard.rs, core/src/app.rs (Wiring),
#   core/src/audit/{event,mod}.rs (Result-Whitelist),
#   docs/contracts/CAPABILITY_VOCABULARY.md, docs/api.md,
#   docs/security/AUDIT_TRAIL.md, docs/OPEN_WORK.md, ROADMAP.md,
#   docs/reviews/{README,PR56_*}.md.

rg "policy engine|Policy Engine|OPA|Rego|registry|dynamic registry" core
# → ausschließlich Doc-Kommentare ("keine Policy Engine", "kein
#   OPA/Rego", "keine dynamische Registry").

rg "AdminBot|OceanData|ABrain" core
# → ausschließlich pre-existing Strings + Spec-Verweise.

rg "<<<<<<<|=======|>>>>>>>" core docs README.md ROADMAP.md
# → keine Konflikt-Marker (außer Such-Patterns selbst in den
#   Review-Dateien).
```
