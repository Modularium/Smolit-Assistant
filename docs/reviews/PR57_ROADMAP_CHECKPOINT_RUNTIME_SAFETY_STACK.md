# PR 57 — Roadmap Checkpoint after Runtime Safety Stack

- **Date:** 2026-04-26
- **Workstream:** A (Docs & Architecture Hygiene)
- **Branch:** `docs/roadmap-checkpoint-runtime-safety-stack`
- **Status:** docs-only checkpoint after PR 53–56.
- **Companion docs:**
  [`PR53_ACCESSIBILITY_RPC_FA1.md`](./PR53_ACCESSIBILITY_RPC_FA1.md),
  [`PR54_CORRELATION_ID_RUNTIME.md`](./PR54_CORRELATION_ID_RUNTIME.md),
  [`PR55_CAPABILITY_CONSTANTS_RUNTIME.md`](./PR55_CAPABILITY_CONSTANTS_RUNTIME.md),
  [`PR56_CAPABILITY_GUARD_RUNTIME.md`](./PR56_CAPABILITY_GUARD_RUNTIME.md).

---

> Leitprinzip: **After a safety foundation stack, freeze the truth
> before starting the next implementation stream.**

## 1. Scope

Reiner **Docs-only** Checkpoint nach vier kleinen, eng eingegrenzten
Runtime-Spikes (PR 53–56). Diese vier PRs haben ein Sicherheits-/
Traceability-Fundament gelegt, ohne die Wire-Form zu brechen, ohne
neue Desktop-Fähigkeiten und ohne Cross-Repo-Vertrauen.

PR 57 hält den dadurch entstandenen Stand fest und priorisiert
**vorsichtig** die Kandidaten für PR 58:

- konsolidiert die vier Reviews in einem Bild,
- formuliert ehrlich, was jetzt **nicht** implementiert ist,
- trennt die Sicherheits-/Traceability-Achse sauber von Packaging
  und Cross-Repo-Implementation,
- benennt den nächsten kleinsten Code-Kandidaten **als Vorschlag**,
  ohne andere Pfade auszuschließen.

PR 57 ändert **keinen** Code, **keine** Tests, **keine** CI-Workflow-
Datei, **keine** Runtime-Config.

## 2. Runtime Safety Stack Summary

### PR 53 — Accessibility RPC FA-1 (partial)

- Cargo-Feature `accessibility_rpc` (default-off) +
  Runtime-Env `SMOLIT_ACCESSIBILITY_RPC_ENABLED` + mockable
  `AccessibilityRegistryClient`-Trait + verified-only-from-registry-
  Konstruktor. Read-only Registry-Root-`GetChildren`; Tiefe 1 ist
  per Trait-Signatur erzwungen.
- Production hat **keinen** echten `atspi`/`zbus`-Client gewired —
  Production-Pfad fällt mit Feature+Env honest auf
  `Unavailable { reason: "accessibility_rpc_backend_not_implemented" }`
  zurück.
- Default-Verhalten **bit-für-bit** wie pre-PR-53.
- Details: [`PR53_ACCESSIBILITY_RPC_FA1.md`](./PR53_ACCESSIBILITY_RPC_FA1.md).

### PR 54 — Correlation ID Runtime

- Optionales `correlation_id: Option<String>` auf `AuditEvent`,
  allen Action-Lifecycle-Payloads, `ApprovalRequest` und
  `ApprovalResolvedPayload`. Generator + Sanitizer in
  [`core/src/audit/correlation.rs`](../../core/src/audit/correlation.rs).
- `App::plan_demo_action`, `App::dispatch_interaction`,
  `App::request_approval_demo` vergeben die ID am frühesten Punkt
  und tragen sie **lokal** durch IpcCommandReceived → ActionPlanned
  → (ApprovalRequested → ApprovalResolved) → ActionStarted/Step/
  Completed bzw. ActionCancelled. Double-Approve / Re-Resolve
  erzeugt keine zweite ID.
- **Lokal**, kein Cross-Repo-Echo, kein Distributed Tracing,
  keine Persistenz.
- Details: [`PR54_CORRELATION_ID_RUNTIME.md`](./PR54_CORRELATION_ID_RUNTIME.md).

### PR 55 — Capability Constants Runtime

- Statische Code-Konstanten + Mapping-Helfer in
  [`core/src/capabilities.rs`](../../core/src/capabilities.rs)
  für die in
  [`docs/contracts/CAPABILITY_VOCABULARY.md`](../contracts/CAPABILITY_VOCABULARY.md)
  geführten 18 IDs (`interaction.*` / `assistant.*` / `admin.*` /
  `data.*` / `provider.*` / `audit.*`).
- Optionales `capability_id: Option<String>` auf `AuditEvent`,
  `AuditFields`, `ApprovalRequest`. Sanitizer ist Whitelist-only
  (`KNOWN_CAPABILITY_IDS` + Naming-Regeln aus Vocab §3); User-
  Strings ohne Vocab-Eintrag landen **nie** im Store.
- Metadaten-Helfer (`is_executable_today`, `risk_for_capability`,
  `requires_approval_by_default`, …) sind **descriptive metadata**
  — keine Policy-Eingabe, kein Approval-Override, keine
  Risk-Verschiebung.
- Details: [`PR55_CAPABILITY_CONSTANTS_RUNTIME.md`](./PR55_CAPABILITY_CONSTANTS_RUNTIME.md).

### PR 56 — Capability Guard Runtime

- Kleiner, deterministischer **deny-only / fail-closed** Guard
  über den PR-55-Konstanten in
  [`core/src/capability_guard.rs`](../../core/src/capability_guard.rs).
- Verweigert unbekannte / future / unsupported Capabilities
  (`admin.*`, `data.*`, `interaction.type_text`,
  `interaction.send_shortcut`) **vor** dem bestehenden
  Approval-/Policy-v0-Pfad. Allow-Pfade verändern Wire/Audit-Form
  gegenüber PR 55 nicht.
- Audit-Whitelist um neuen Result-Wert
  `capability_guard_denied` erweitert; Deny-Frame nutzt
  bestehendes `action_failed`-Envelope mit Präfix
  `capability_guard_denied: <reason>` und kuratiertem
  `summary`-Suffix `[guard:<reason>]`.
- Bestehende Sperren bleiben führend — der Guard kann
  **nichts erlauben**, was Policy v0 oder die Config sperrt.
- Details: [`PR56_CAPABILITY_GUARD_RUNTIME.md`](./PR56_CAPABILITY_GUARD_RUNTIME.md).

### Test count over the stack

- Pre-PR-53: 398 Tests passed.
- Post-PR-53: 408 (+10 invariant + 1 feature-gated).
- Post-PR-54: 424 (+16 correlation lifecycle + generator).
- Post-PR-55: 443 (+13 unit + 6 IPC integration).
- Post-PR-56: 469 (+17 unit + 9 IPC integration).
- `scripts/ci_verify.sh core`: PASS.
- `scripts/run_overlay_verification.sh settings-shell-smoke`: PASS.

## 3. Current Runtime Truth after PR 56

Was Smolit-Assistant **heute lokal** kann:

- **`open_application` läuft approval-gated** (Policy v0 / PR 25);
  jede Aktion durchläuft IpcCommandReceived → ActionPlanned →
  ApprovalRequested → ApprovalResolved → ActionStarted / Step /
  Verification / Completed im Audit, mit `correlation_id` (PR 54)
  und `capability_id = interaction.open_application` (PR 55).
- **`focus_window` bleibt X11 + template + double opt-in** und
  default disabled (`SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW=1` plus
  `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`); unter Wayland honest
  `BackendUnsupported`. Der Guard hebt diese Sperre **nicht** auf.
- **`type_text` / `send_shortcut` bleiben unsupported.** PR 56
  verweigert sie zusätzlich fail-closed mit kuratierten Reasons
  (`interaction_type_text_not_supported` /
  `interaction_send_shortcut_not_supported`).
- **AdminBot, OceanData, ABrain-native** bleiben **nicht
  implementiert**. Die zugehörigen Capability-IDs (`admin.*` /
  `data.*`) existieren nur als Dokumentations-Konstanten; der
  Guard liefert für sie `future_capability_not_implemented`.
- **Accessibility RPC ist partial / stubbed.** Der Production-
  Pfad meldet honest `accessibility_rpc_backend_not_implemented`,
  weil kein realer Registry-Client gewired ist; `confidence:
  verified` ist **strukturell** unmöglich ohne Mock-Client.
- **`correlation_id` und `capability_id`** sind **lokale**
  Trace- bzw. Semantik-Metadaten — keine Cross-Repo-Identität,
  kein Distributed Tracing.
- **Capability Guard** ist deny-only und kein Ersatz für eine
  Policy Engine.

## 4. Wire / API State

- **Kein** neues `IncomingMessage` durch PR 53–56.
- **Kein** neues `OutgoingMessage` durch PR 53–56 — keine
  Variante existiert nur wegen correlation/capability/guard.
- `correlation_id` ist überall **optional und additiv**
  (`#[serde(default, skip_serializing_if = "Option::is_none")]`)
  auf:
  - allen Action-Lifecycle-Payloads,
  - `ApprovalRequest` / `ApprovalResolvedPayload`,
  - `AuditEvent` (in `audit_recent`).
- `capability_id` ist optional und additiv auf:
  - `AuditEvent` (in `audit_recent`),
  - `ApprovalRequest`.
  Action-Event-Payloads tragen es **noch nicht** — bewusst (FA-4
  → FA-6 in der Vocab-Spec).
- Guard-Deny nutzt bestehende `ActionFailed` / `Error` /
  `AuditEvent`-Muster mit dem neuen Whitelist-Wert
  `capability_guard_denied`.

Wire-Kompatibilität ist nach PR 53–56 voll erhalten: ein UI vor
PR 53 sieht weiterhin dieselbe Frame-Form, nur mit zusätzlichen
optionalen Feldern, die sie ignorieren kann.

## 5. Audit / Traceability State

- Audit-Store bleibt **bounded, in-memory, sanitized.** Default
  100 / Hard 1000 Events; Env `SMOLIT_AUDIT_MAX_EVENTS`. Ein
  Core-Restart leert den Store vollständig.
- `correlation_id` (PR 54) verbindet Lifecycle-Schritte derselben
  Aktion lokal: jeder Audit-Eintrag eines Aktionspfads trägt
  dasselbe `corr_…`-Token.
- `capability_id` (PR 55) erklärt die Aktionsklasse semantisch
  (z. B. `interaction.open_application`,
  `assistant.demo.echo`).
- `capability_guard_denied` (PR 56) ist ein neuer **sanitized
  result**-Wert in der bestehenden Whitelist. Der Reason-Suffix
  in `summary` (`[guard:<reason>]`) stammt ausschließlich aus
  `KNOWN_GUARD_REASONS`; keine User-Inhalte.
- **Kein** Export, **keine** Persistenz, **kein** Compliance-Log.
- Anti-Rekursion bleibt: ein `audit_recent`-Read löst keinen
  Audit-Eintrag aus.

## 6. Security Boundary State

Was nach PR 53–56 **weiterhin** außerhalb des Cores liegt:

- **Kein AdminBot-Client.** ADR-0005 +
  `ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md` rahmen die zukünftige
  Boundary; der Code spricht AdminBot nicht an.
- **Kein OceanData-Client.** ADR-0004 + ADR-0006 rahmen die
  zukünftige Context-Provider-Achse; kein
  `oceandata_context`-Provider, kein Schreib-Pfad.
- **Kein ABrain-native.** ADR-0003 rahmt einen zukünftigen
  Provider-Kind `abrain_native`; CLI-Pfad bleibt allein produktiv.
- **Kein Cross-Repo Action-Wire.** Weder `correlation_id` noch
  `capability_id` wird zu ABrain / AdminBot / OceanData
  propagiert.
- **Kein OPA / Rego im Core.** Der Guard ist ein
  deterministischer Match auf statische Konstanten.
- **Kein dynamisches Policy-System.** Policy v0 (PR 25)
  bleibt führend.
- **Keine Desktop-Automation-Ausweitung.** `type_text` /
  `send_shortcut` bleiben unsupported; `focus_window` bleibt
  template-gegated.

## 7. What got safer

- **Future-Capabilities sind fail-closed** (PR 56) — `admin.*` /
  `data.*` werden vor jedem Approval-/Executor-Schritt
  abgelehnt, selbst wenn sie programmatisch konstruiert würden.
- **Unsupported Interactions laufen nicht versehentlich weiter.**
  `type_text` / `send_shortcut` waren bereits
  `BackendUnsupported`; jetzt liefert der Guard zusätzlich eine
  **deterministische** Vor-Filterung mit kuratiertem Reason.
- **Reviewer können Action-/Approval-/Audit-Pfade besser
  zusammenziehen** — ein `corr_…`-Token plus eine
  `capability_id` machen den Ring-Buffer für jeden Pfad
  rekonstruierbar.
- **Capability-Semantik ist code-stabil** statt nur in Docs.
  Rename / Drift wird durch die `KNOWN_CAPABILITY_IDS`-Whitelist
  und die Naming-Regel-Tests sofort bemerkt.
- **Accessibility-`verified`-Semantik ist geschützt.** Der
  einzige Konstruktor für `confidence: verified` lebt im Code
  hinter dem Trait-Vertrag; die Trait-Signatur erzwingt Tiefe 1.

## 8. Remaining gaps

Ehrlich, ohne Beschönigung:

- **Realer AT-SPI / `zbus` Registry-Client fehlt.** PR 53 ist
  partial; ein produktiver Client braucht
  Permission-/Provenance-Review (Flatpak
  `--talk-name=org.a11y.Bus`).
- **`correlation_id` wird nicht zu ABrain / AdminBot /
  OceanData propagiert.** Cross-Repo-Echo bleibt Spec
  (`AUDIT_CORRELATION_ID_SPEC.md` FA-3 → FA-6).
- **`capability_id` ist noch nicht auf allen Action-Event-
  Payloads** — heute nur `AuditEvent` und `ApprovalRequest`.
- **Provider Privacy Guard existiert noch nicht** (z. B.
  `provider.text.generate` + `cloud_http` + Privacy-Mode).
  Vocabulary FA-4 bleibt offen.
- **Keine Policy Engine / OPA im Core.** Multi-Tenant,
  Role-Based, externe Regeln — alles eigene Designentscheidungen.
- **Kein Packaging P1 / P2.** ADR-0007 rahmt P1 (Local Build
  Script) → P2 (AppImage); kein Code, keine Presets, kein
  Bundle.
- **Kein ABrain Native FA-1.** ADR-0003 rahmt den
  Native-Pfad; kein Client, kein Wire.
- **Kein AdminBot status-read-only FA-0.**
  ADMINBOT_SAFETY_BOUNDARY_CONTRACT.md rahmt vier Klassen;
  kein Adapter.
- **Kein OceanData Context Provider.** ADR-0006 rahmt die
  Achse; kein Trait, kein Spike-Client.

## 9. Candidate Next PRs

Vorschlag, **nicht bindend**. Ein Default plus drei Alternativen.

### A. PR 58 — Packaging P1 Local Build Script

- **Grund:** v0.2.0 ist released; ADR-0007 nennt P1 als nächste
  Packaging-Stufe. Schließt eine reproducibility-Lücke, die für
  AppImage (P2) und `.deb` (P3) Vorbedingung ist.
- **Scope:** ein deterministisches Local-Build-Skript +
  README/SETUP-Update; keine AppImage/`.deb`/Flatpak in dieser
  Stufe. Eigene Verifikation ohne Cross-Repo-Berührung.
- **Risiko:** **niedrig.** Kein Runtime-Code, keine
  Sicherheits-/Approval-/Audit-Berührung, kein
  IPC-Wire-Risiko.
- **Pro:** Runtime-Safety bleibt stabil, während
  Distribution/Reproducibility verbessert wird. Lockt ADR-0007
  in Code, ohne Signing/Update zu öffnen.
- **Contra:** Keine direkte Sicherheitsverbesserung über den
  Stack hinaus.

### B. Alternative — Provider Privacy Guard

- **Grund:** Nutzt `capability_id` und `provider.text.generate`
  sinnvoll; fügt eine zweite kleine Deny-Linie hinzu (z. B.
  `cloud_http` blockieren, wenn ein Privacy-Mode aktiv ist).
- **Scope:** kleines Privacy-Config-Feld + Guard-Erweiterung;
  Wire bleibt additiv.
- **Risiko:** **mittel** — Provider-Pfade sind sensibel;
  unsorgfältige Wiring kann normale Provider-Antworten still
  blockieren. Vocabulary FA-4 wäre der Eintritt.

### C. Alternative — ABrain Native FA-1 Provider Spike

- **Grund:** Langfristig wichtig; ADR-0003 ist seit PR 39
  Proposed.
- **Scope:** typed API-Client hinter Feature-Flag,
  Chain-Whitelist-Erweiterung um `abrain_native`, Wire-Schema
  aus ADR-0003 §6 geprüft. Kein Action-Intent-Pfad, kein
  Streaming.
- **Risiko:** **höher** — Cross-Repo-Vertrag muss mit
  ABrain-Seite synchron sein; Action-Intent-Boundaries und
  Approval-Wiring brauchen einen weiteren Schritt.

### D. Alternative — Accessibility real AT-SPI client

- **Grund:** PR 53 partial schließen.
- **Scope:** `atspi` + `zbus` als Cargo-Dependency hinter
  `accessibility_rpc`; ein produktiver
  `AccessibilityRegistryClient`.
- **Risiko:** **mittel/hoch** — DBus-Permission, Flatpak-/
  Snap-Anforderungen, Real-Host-Messung. Ohne
  Permission-Review wäre die Linie nicht ehrlich.

### Empfehlung

**PR 58 = Packaging P1 Local Build Script.** Begründung:

- Runtime-Safety-Stack ist stabil und sollte konsolidiert
  bleiben.
- Packaging P1 ist die natürliche Fortsetzung von ADR-0007 und
  blockiert nichts.
- Keine Cross-Repo-Abhängigkeit, keine Sicherheits-/Approval-
  Berührung.

Alternative B (Provider Privacy Guard) wäre die nächst-naheste
**Code-Erweiterung** des Stacks, falls ein konkreter
Privacy-Use-Case auftaucht. C und D bleiben nachrangig, bis
Cross-Repo- bzw. Permission-Vorbedingungen geklärt sind.

## 10. Non-goals

- **Kein Code.** Weder Rust noch Godot.
- **Keine neue Runtime-Config**, kein neues Env, kein neues
  Provider-Kind.
- **Keine CI-Workflow-Änderung.** Falls ein docs-only smoke
  notwendig wäre, würde er als eigene PR landen.
- **Kein Packaging-Build.** Kein AppImage, kein `.deb`, kein
  Flatpak, kein Dockerfile, kein Installer.
- **Keine Branch-Protection / GitHub-Governance-Änderung.**
- **Keine Cross-Repo-Änderungen** (kein ABrain / AdminBot /
  OceanData / smolitux-ui Edit).
- **Keine Policy-Engine-Vorarbeit** — Vocabulary FA-4 bleibt
  eigene Folge-PR.

## 11. Verification

```bash
scripts/ci_verify.sh core
# → 469 passed; 0 failed; ci_verify: PASS

scripts/run_overlay_verification.sh settings-shell-smoke
# → settings_shell smoke: PASS

git diff --check
# → keine Whitespace-/Konflikt-Marker

rg "PR57|PR 57|Runtime Safety Stack|capability_guard|correlation_id|capability_id" docs ROADMAP.md README.md
# → konsistente Verweise (Reviews-Index, ROADMAP §6.4-Eintrag,
#   neuer Review-Eintrag)

rg "Policy Engine|policy engine|OPA|Rego|AT-SPI|atspi|zbus|AdminBot|OceanData|ABrain" docs ROADMAP.md README.md
# → ausschließlich Spec-/ADR-/Review-/Doc-Verweise, keine neuen
#   Runtime-Versprechen

rg "<<<<<<<|=======|>>>>>>>" docs ROADMAP.md README.md
# → keine Konflikt-Marker (außer in Review-Dateien, die diese
#   Patterns als Such-Strings dokumentieren)
```

PR-57-Selbst-Anker:

- Keine `core/` / `ui/` / `.github/workflows/` Datei geändert.
- Keine `Cargo.toml` / `Cargo.lock` Änderung.
- Keine neuen Tests; keine neuen Wire-Felder.
- ROADMAP §3 Stable Baseline und §6.4 Sequenz spiegeln den
  PR-53–56-Stack.
- OPEN_WORK Workstream E / F / I / H benennen die Folgearbeiten,
  ohne neue Versprechen zu öffnen.
