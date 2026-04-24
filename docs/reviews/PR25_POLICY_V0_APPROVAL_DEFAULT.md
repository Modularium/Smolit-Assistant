# PR 25 — Policy v0: Approval Default for Real Interaction Actions

- **Datum:** 2026-04-24
- **Scope:** Workstream E — Safety-/Docs-/Tests-PR. Zieht die
  Approval-Baseline für echte Interaction Actions fest; baut
  **keine** Policy-Engine.
- **Verwandte Entscheidungen:** PR 17 (Approval UX v1),
  PR 18 (Approval-Gated Demo Action Planner), PR 19 (Audit Trail v1),
  PR 23 (`focus_window` Reality Decision), PR 24 (Smolitux Design
  Contract ADR — PR-Nummern verschoben).

---

## 1. Was dieser PR tatsächlich tut

1. **Fixiert die Default-Config** als benannte Konstanten in
   [`core/src/config.rs`](../../core/src/config.rs):
   `DEFAULT_INTERACTION_REQUIRE_CONFIRMATION = true`,
   `DEFAULT_INTERACTION_ALLOW_OPEN_APP = true`,
   `DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW = false`,
   `DEFAULT_INTERACTION_ALLOW_TYPE_TEXT = false`,
   `DEFAULT_INTERACTION_ALLOW_SHORTCUTS = false`.
   Die Literale am Call-Site werden durch diese Konstanten ersetzt —
   das Verhalten ändert sich **nicht**, nur die Sichtbarkeit und
   Prüfbarkeit der Policy.
2. **Fügt zwei Tripwire-Tests** hinzu:
   `policy_v0_defaults_are_locked` und
   `policy_v0_parse_bool_with_no_env_uses_locked_defaults`.
   Beide schlagen an, wenn jemand die Defaults stumm flippt.
3. **Dokumentiert die Baseline** in
   [`docs/security/APPROVAL_UX.md`](../security/APPROVAL_UX.md)
   (neuer Abschnitt „Policy v0"),
   [`docs/api.md`](../api.md) (§2.6 „Policy v0 Defaults" + §2.5-
   Pfad-Präzisierung),
   [`docs/presence_desktop_interaction.md`](../presence_desktop_interaction.md)
   (§14b.3 Ist-Zustand korrigiert),
   [`docs/OPEN_WORK.md`](../OPEN_WORK.md) (Workstream E auf
   „gelandet", Nicht-Ziele präzisiert),
   [`docs/GLOSSARY.md`](../GLOSSARY.md) (Approval-Eintrag: Default
   statt Opt-in),
   [`ROADMAP.md`](../../ROADMAP.md) (PR 25-Zeile + §7-Formulierung).
4. **Bringt keinen neuen Code-Pfad.** Die Approval-Kette für
   `open_application` (PR 17) und die `focus_window`-Gating-Tests
   (PR 23) existierten bereits; dieser PR verhärtet nur die Defaults.

## 2. Was wirklich geschützt ist

| Aktion | Default-Verhalten | Test |
| ------ | ----------------- | ---- |
| `interaction_open_application` | `action_planned` → `approval_requested` → (nach `approval_approve`) `approval_resolved(approved)` → `action_started` → `action_step` → `action_verification` → `action_completed`. Ohne User-Zustimmung **kein** Backend-Aufruf. | [`approval_approved_produces_completed_via_broadcast`](../../core/src/ipc/server.rs) |
| `interaction_open_application` (deny) | `approval_requested` → `approval_deny` → `approval_resolved(denied)` → `action_cancelled`. **Kein** `action_started`, **kein** `action_completed`. | [`approval_denied_produces_cancelled`](../../core/src/ipc/server.rs) |
| `interaction_open_application` (timeout) | `approval_resolved(timed_out, source=timeout)` → `action_cancelled("Approval timed out")`. | `approval_timeout_produces_cancelled` |
| `interaction_focus_window` (Default-Config) | Policy `allow_focus_window=false` → `action_failed` mit `recovery_hint=fallback_unavailable`. Kein Backend-Aufruf. | [`focus_window_disallowed_emits_failed`](../../core/src/interaction/executor.rs) |
| `interaction_focus_window` (Opt-in **ohne** Template) | `action_failed` mit `recovery_hint=fallback_unavailable` (honest `BackendUnsupported("focus_window")`). | [`focus_window_without_backend_template_emits_unsupported`](../../core/src/interaction/executor.rs) |
| `interaction_focus_window` (doppeltes Opt-in) | Wie `open_application`: Approval-Kette, dann Backend-Aufruf. Template-Test nutzt `/bin/true`. | [`focus_window_with_template_emits_verification_and_completed`](../../core/src/interaction/executor.rs) |
| `interaction_type_text`, `interaction_send_shortcut` | `BackendUnsupported`; Flag-Flip hätte aktuell **keine** Wirkung auf die Ausführung. | [`type_text_action_is_unsupported_at_backend`](../../core/src/interaction/executor.rs) |

## 3. Was bewusst **nicht** geschützt / implementiert wurde

- **Keine Policy-Engine.** Kein Rollen-/Rechte-System, keine
  Regel-Matrix, keine kontextabhängige Freigabe.
- **Keine Multi-Seat- / Multi-User-Semantik.** Ein UI-Client
  entscheidet.
- **Kein AdminBot, keine Shell-Aktionen.**
- **Kein `type_text` / `send_shortcut`-Backend.** Die Default-Flags
  sind `false`, aber selbst beim Flip bleibt der Executor bei
  `BackendUnsupported`. Policy v0 schützt also primär das Signal
  der Default-Oberfläche, keine existierende Fähigkeit.
- **Kein Wayland-Fokus-Backend.** Unter Wayland bleibt
  `focus_window` ohne generisches Protokoll-Primitiv.
- **Keine Audit-Erweiterung auf den realen Interaction-Pfad.** Der
  Audit-Ring-Buffer aus PR 19 loggt **heute nur** den
  `plan_demo_action`-Lifecycle. Die realen Lifecycle-Events von
  `open_application` (planned / approval_requested / approval_resolved /
  started / step / verification / completed / cancelled) werden
  **nicht** in den Audit-Store geschrieben. Eine Ausweitung wäre
  eine eigene Design-Entscheidung: welche Felder, welche Redaction,
  wie spielt `source` aus PR 17 mit einem neuen
  `InteractionActionStarted`-Kind zusammen? Diese Arbeit ist
  **nicht** Teil von PR 25 und **nicht** als nächster E-PR gesetzt.
- **Kein Audit-Persistenz-Pfad.** Der Ring-Buffer bleibt in-memory.
- **Kein neuer IPC-Command.** Das Protokoll aus
  [`docs/api.md`](../api.md) bleibt unverändert.
- **Keine UI-Änderung.** Approval-Card und Workflow-Visibility-
  Overlay rendern unverändert.

## 4. Effektive Defaults nach PR 25

```text
SMOLIT_INTERACTION_REQUIRE_CONFIRMATION = true
SMOLIT_INTERACTION_ALLOW_OPEN_APP       = true
SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW   = false
SMOLIT_INTERACTION_ALLOW_TYPE_TEXT      = false
SMOLIT_INTERACTION_ALLOW_SHORTCUTS      = false
SMOLIT_INTERACTION_OPEN_APP_CMD         = <leer>  (honest unavailable)
SMOLIT_INTERACTION_FOCUS_WINDOW_CMD     = <leer>  (honest unsupported)
```

Quelle: [`core/src/config.rs`](../../core/src/config.rs) —
`DEFAULT_INTERACTION_*`-Konstanten, gesichert durch Tests.

## 5. Honesty Check

- ✅ `open_application` ist bei Default-Config real approval-gated.
- ✅ `focus_window` ist bei Default-Config doppelt gesperrt
  (Flag + Template).
- ✅ `type_text` / `send_shortcut` bleiben außerhalb der Executor-
  Reichweite.
- ⚠️ Audit deckt den realen Interaction-Pfad **nicht** ab; die
  Sicherheitsaussage „jede echte Aktion hinterlässt eine auditierte
  Spur" gilt **heute nicht**. Das ist der einzige Punkt, an dem
  eine Policy-v0-Formulierung „echte Aktionen laufen kontrolliert"
  über das aktuelle Code-Verhalten hinausschießen könnte — daher
  ist die Docs-Sprache durchgängig auf „Approval-gated" statt
  „auditiert" zugeschnitten.
- ⚠️ `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=0` bleibt ein
  Test-Hebel. Er ist **nicht** entfernt worden, weil die
  Executor-Unit-Tests ihn zum deterministischen Ablauf brauchen.
  Produktive Builds setzen ihn nicht.
