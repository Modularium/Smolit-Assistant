# Smolit Presence & Desktop Interaction — Current Reality

> **Status (PR 28, 2026-04-24).** Dieses Dokument wurde hart auf den
> tatsächlichen Stand des Repos getrimmt. Frühere Fassungen haben
> **Zielarchitektur** und **Ist-Zustand** vermischt; das war gegenüber
> dem Code eine Fiktion. Die vorher hier dokumentierten Endausbaustufen
> (Bewegungspfade, OCR, Vision, breite Desktop-Automation, pixelgenaue
> Bedienung fremder Software) stehen seitdem ausschließlich in §10
> *Future Work* und sind dort klar als **nicht implementiert**
> markiert. Siehe Abschnitt-Mapping am Ende des Dokuments für die
> Anker aus älteren Versionen.

---

## 1. Purpose

Beschreibt, **was Smolit heute tatsächlich** an Desktop-Präsenz und
Desktop-Interaktion zeigt und **was ausdrücklich nicht**. Das Dokument
ist ein Ist-Zustand-Anker, kein Zielbild.

Trennlinien, die über den Rest des Dokuments bindend bleiben:

- **Keine fake Desktop-Autonomie.** Der Avatar visualisiert; er führt
  nichts aus. Der Core hat **zwei** echte Interaction-Kinds
  (`open_application`, `focus_window`); alles andere ist
  `BackendUnsupported`.
- **Presence ist Visual Truth, keine versteckte Ausführung.** Was der
  Avatar zeigt, kommt aus Action Events des Cores — nicht aus
  Fremdsoftware-Inspektion.
- **Approval vor Ausführung.** Echte Interaction-Aktionen laufen per
  Default durch die Approval-Kette (Policy v0, PR 25).

Verwandte Quellen:

- IPC-Seite: [`docs/api.md` §2.6 / §2.7 / §2.8](./api.md).
- UI-Seite: [`docs/ui_architecture.md`](./ui_architecture.md) (§1–§8).
- Approval-/Audit-Prinzipien:
  [`docs/security/APPROVAL_UX.md`](./security/APPROVAL_UX.md),
  [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md).
- Fenster-/Overlay-Plattform-Realität:
  [`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md).
- `focus_window` Entscheidung:
  [`docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`](./reviews/PR23_FOCUS_WINDOW_DECISION.md).
- Einheitliches Vokabular:
  [`docs/GLOSSARY.md`](./GLOSSARY.md) — Presence, Interaction Layer,
  Action Event, Approval, Workflow Visibility Overlay, Godot-native UI.

---

## 2. Current Reality

Ein-Blick-Zusammenfassung des Ist-Zustands (Stand 2026-04-24, nach
PRs 23–27):

- **`open_application`** — real verdrahtet über den `CommandBackend`;
  approval-gated by default (Policy v0 / PR 25); Verification bleibt
  *best-effort / uncertain* (keine Fenster-Probe nach Spawn).
- **`focus_window`** — template-basierter X11-Pfad (z. B.
  `wmctrl -a {name}`). Default `allow_focus_window=false` sperrt die
  Aktion; bei doppeltem Opt-in (Flag + X11-Template) läuft sie
  ebenfalls approval-gated. **Unter Wayland kein Backend.**
- **`type_text` / `send_shortcut`** — `BackendUnsupported`. Das
  Protokoll kennt die Kinds, der Executor emittiert konsequent
  `action_failed` mit `recovery_hint=fallback_unavailable`.
- **Accessibility (`interaction_probe_accessibility` /
  `interaction_discover_accessibility`)** — strikt **read-only**.
  Kein AT-SPI-RPC, kein Tree-Walking, keine App-spezifischen Adapter.
  Discovery liefert heute ausschließlich einen Hint-Echo-Item-Pfad.
- **Presence-UI (Godot)** — Rendering von Avatar, Bubble, Approval-
  Card, Workflow Visibility Overlay. **Führt keine Desktop-Automation
  aus** und hat keinen direkten System-Access.
- **Visual Action Mode** — reine UI-Staging-Intensitätsachse innerhalb
  der Presence-Hülle. **Keine** Avatar-Bewegung über Fremdfenster,
  keine echte Zielkoordinaten, keine Bildschirmwanderung.
- **Audit** — Ring-Buffer deckt heute **nur** den
  `plan_demo_action`-Pfad; die Lifecycle-Events des realen
  `open_application`-Approval-Flows werden **nicht** auditiert.

---

## 3. Implemented Capabilities

| Capability | Core-Pfad | Defaults (Policy v0) | Verification |
| --- | --- | --- | --- |
| Open application | [`core/src/interaction/executor.rs`](../core/src/interaction/executor.rs), `InteractionKind::OpenApplication`, `CommandBackend` über `SMOLIT_INTERACTION_OPEN_APP_CMD` | `allow_open_application=true`, `require_confirmation=true` — approval-gated bei jedem Request | Best-effort / `uncertain`; kein Fenster-Probe |
| Focus window (X11 opt-in) | Gleicher Executor, `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD` z. B. `wmctrl -a {name}` | `allow_focus_window=false` by default; bei Opt-in weiterhin `require_confirmation=true` | `uncertain` by design (kein Fokus-Probe) |
| Accessibility-Probe | [`core/src/interaction/accessibility.rs`](../core/src/interaction/accessibility.rs) | Read-only, kein Approval nötig | Honest: `uncertain` / `unavailable` / `failed` |
| Accessibility-Discovery (hint-echo) | Gleiches Modul, `interaction_discover_accessibility{hint?}` | Read-only | Items tragen `confidence: "discovered"` (nie `verified`) |
| Target Selection slot | [`core/src/interaction/selection.rs`](../core/src/interaction/selection.rs) | Ein Slot, volatil, kein Persistenz-Layer | Core antwortet mit `target_selected` / `target_cleared` |
| Action Event-Strom | [`core/src/actions/`](../core/src/actions/) | Neun Varianten laut [`api.md §2.5`](./api.md) | — |
| Approval UX (Card + Banner) | UI-Seite: [`ui_architecture.md §8.4d`](./ui_architecture.md); Core: Policy v0 (PR 25) | Real für `open_application` und `focus_window` opt-in | — |
| Workflow Visibility Overlay v1 | [`ui_architecture.md §8.4c`](./ui_architecture.md) | Read-only Projektion von Action Events + Approvals | — |
| Visual Action Mode (UI-Staging) | [`ui_architecture.md §8.5`](./ui_architecture.md) | Intensitätsachse in der Presence-Hülle | — |

**Architektur-Invariante.** Die Godot-UI ruft **niemals** direkt einen
Interaction-Kind auf; sie sendet einen IPC-Command und rendert die
vom Core zurückkommenden Events. Die Trennung ist nicht nur
Style-Guide — sie ist der Grund, warum PR 25 die Approval-Gate-
Semantik überhaupt durchsetzen kann.

---

## 4. Explicitly Unsupported

Harte Scope-Grenzen. Kein Pfad, keine Konfiguration, kein Opt-in
macht aus einem dieser Punkte heute ein Feature.

- **`type_text`** — Der Command-Backend meldet konsequent
  `BackendUnsupported("type_text")`. Keine globale Tastatur-Injektion,
  kein D-Bus-Portal, kein `xdotool`-Pfad.
- **`send_shortcut`** — Analog zu `type_text`;
  `BackendUnsupported("send_shortcut")`.
- **Fremde UI-Elemente bedienen (Klicks, Scroll, Drag&Drop).** Es gibt
  weder einen Click-Adapter noch ein Scroll-Primitiv noch einen
  Drag&Drop-Pfad. Weder der Command-Backend noch der Accessibility-
  Spike berühren fremde UI-Elemente.
- **Wayland-Fokus.** Es existiert kein Wayland-Backend für
  `focus_window`. Der Core antwortet unter Wayland honest mit
  `BackendUnsupported("focus_window")`, egal welches Template gesetzt
  ist. Siehe
  [`docs/wayland_always_on_top_refusal_results.md`](./wayland_always_on_top_refusal_results.md).
- **AT-SPI-RPC, Tree-Walking, App-spezifische Adapter.** Der
  Accessibility-Spike ist Environment-basiert und liefert nur einen
  `uncertain` / `unavailable` / `failed`-Status plus hint-echo Items.
  Kein `GetChildren`, kein `ByName`-Lookup, kein Toolkit-Adapter.
- **OCR, Vision, Pixel-Matching, Template-Matching.** Gibt es im
  gesamten Core nicht — keine Bibliothek gebunden, kein Modul.
- **Avatar-Bewegung über Fremdfenster** (Cross-Window Motion). Der
  Visual Action Mode ist reine In-Place-Intensität in der Presence-
  Hülle. Kein Zielkoordinaten-System, kein sichtbares Wandern über
  den Bildschirm.
- **Audit-Abdeckung des realen Interaction-Pfads.** Der Audit-Ring-
  Buffer (PR 19) loggt nur den `plan_demo_action`-Lifecycle. Der
  reale `open_application`-Approval-Flow ist **nicht** auditiert.

---

## 5. Approval / Policy v0

Seit PR 25 (2026-04-24) gilt für alle echten Interaction-Aktionen:

- `require_confirmation` ist per Default `true` in `InteractionConfig`.
- Eine Aktion mit `requires_confirmation=true` läuft durch die Kette
  `action_planned → approval_requested → approval_resolved →
  action_started → action_step → action_verification →
  action_completed`. Ohne `approval_approve` kein Backend-Aufruf.
- Deny / Cancel / Timeout: `approval_resolved` plus
  `action_cancelled`; **kein** `action_started`, **kein**
  `action_completed`.
- Tripwire-Test
  `policy_v0_defaults_are_locked` in
  [`core/src/config.rs`](../core/src/config.rs) sichert, dass niemand
  die Baseline stumm flippt.

Details: [`docs/security/APPROVAL_UX.md`](./security/APPROVAL_UX.md)
(Abschnitt „Policy v0") und
[`docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md).

**Sicherheits-Leitplanken, die heute real verdrahtet sind:**

- **Approval vor Ausführung** — Kill-Switch durch Nicht-Bestätigung.
- **Idempotente Resolution** — Double-Approve / Double-Deny endet
  als `error`-Frame, nie als doppelte Ausführung.
- **Keine stille Rechteausweitung** — jede Aktion holt ihren eigenen
  Approval; keine Session-weite Dauervollmacht.
- **Timeout** — `SMOLIT_APPROVAL_TIMEOUT_SECONDS` → `timed_out`,
  `action_cancelled`.

**Was Policy v0 *nicht* ist**: keine Policy-Engine, keine Rollen-
Matrix, keine Multi-Seat-Semantik, kein Trust-Modell für Apps
(`trusted_only`-Flag wandert zwar durch, gated aber nichts).

---

## 6. Presence UI Responsibilities

Die Godot-UI ist Presentation Layer. Sie

- rendert den Avatar (Phase A Smolit-Default, Phase B kuratierte
  Spike-Identities mit Template-Capability-Contract; Details in
  [`ui_architecture.md §8b`](./ui_architecture.md));
- rendert Presence-Modi **Docked**, **Expanded** und einen
  **Action**-Substate, sowie einen **Disconnected**-Fehlerzustand
  (`ui/scripts/presence/presence_controller.gd`);
- rendert die **Approval Card** (PR 17) und das
  **Workflow Visibility Overlay v1** (PR 16/17) als passive
  Projektionen des IPC-Event-Stroms;
- rendert den Visual Action Mode als **In-Place-Intensität** (siehe
  §9), nicht als Bewegung über Fremdfenster.

Was die UI **nicht** tut:

- Kein Klick, kein Tipp, kein Scroll, kein Fokuswechsel gegen
  Fremdfenster.
- Keine direkte IPC-Schreib-Aktion gegen System-Dienste
  (D-Bus, Portals, Compositor) außerhalb der im Core verdrahteten
  Interaction-Kette.
- Keine eigene Entscheidungslogik („was tun?") — Intent und Plan
  leben in Core + ABrain.
- Keine Audio-Pipeline, keine Persistenz über
  `user://smolit_ui.cfg`-Preferences hinaus.

Presence-Modi (`Off` / `Icon only` / `Light avatar` / `Full avatar`)
bleiben Nutzer-einstellbare Intensität der Sichtbarkeit; die Modi
sind **unabhängig** davon, welche Interaction-Aktion gerade läuft
und ändern die Approval-Kette nicht.

Die Avatar-Personalisierung (Identity / Theme / Appearance Overrides
/ Behavior Profile) ist rein visuell. Sie

- **beeinflusst keine** Action-Ausführung,
- **ändert kein** Systemverhalten,
- **verändert keine** Approval- oder Trust-Entscheidungen.

Die Details stehen in
[`ui_architecture.md §8b`](./ui_architecture.md); Stage C bleibt
Forschungs-Gate
([`avatar_stage_c_research.md`](./avatar_stage_c_research.md)).

---

## 7. Desktop Interaction Core Responsibilities

Ist-Zustand des `core/src/interaction/`-Moduls:

- **`InteractionAction`** (`action.rs`) — strukturierte Core-interne
  Aktion mit `InteractionKind` (`OpenApplication`, `FocusWindow`,
  `TypeText`, `SendShortcut`, `Noop`, `Unknown`), `ActionTarget`,
  typisiertem Payload und Policy-Flags (`requires_confirmation`,
  `trusted_only`).
- **`InteractionBackend`** (`backend.rs`) — Trait mit MVP-Operationen
  für die vier Kinds. Nur **`CommandBackend`** existiert; er ist
  `native-first` im Sinn des Interaction-Fidelity-Vokabulars (offiziell
  konfigurierte Launcher-Commands wie `xdg-open` oder `wmctrl`). Keine
  hybriden / pixel-guided / experimental-Backends.
- **`InteractionExecutor`** (`executor.rs`) — wendet
  `InteractionPolicy` an (allow-Flags aus der Config plus
  `require_confirmation`-Gate), dispatcht an das Backend, wandelt
  Backend-Ergebnisse in Action Events.
- **`VerificationResult`** (`verifier.rs`) — Confidence
  `verified` / `uncertain` / `failed`. Real emittiert wird heute nur
  `uncertain` für beide echten Kinds (kein Window-Probe, kein
  Focus-Probe).
- **`RecoveryHint`** (`recovery.rs`) — Taxonomie `retry` / `abort` /
  `ask_user` / `fallback_unavailable`. Wandert im `action_failed`-Event
  als `error: "recovery_hint=<variant>"`.

**Was der Core nicht hat:**

- Keinen zweiten Backend-Typ (kein AT-SPI, kein D-Bus-Portal, kein
  Compositor-nativer Pfad).
- Keine Discovery-Pipeline, die strukturierte Fenster-/UI-Bäume
  liefert. `interaction_discover_accessibility` ist der einzige
  Discovery-Pfad und liefert hint-echo Items.
- Keine Audit-Kette um den realen `open_application`-Flow (nur der
  `plan_demo_action`-Pfad ist heute auditiert).

**Approval-Verdrahtung.** Der Executor ruft den Approval-Pfad
`App::await_and_continue` auf, sobald `requires_confirmation=true` und
`require_confirmation=true` zusammenfallen (PR 25 Default). Sequenz:

```text
action_planned
  → approval_requested
  → approval_resolved({approved|denied|cancelled|timed_out})
  → on approved: action_started → action_step* → action_verification
                 → action_completed
  → on denied|cancelled|timed_out: action_cancelled
```

---

## 8. Accessibility Spike

Stand: kleiner, read-only Spike in
[`core/src/interaction/accessibility.rs`](../core/src/interaction/accessibility.rs).

- **Probe.** `interaction_probe_accessibility` prüft Session-Typ,
  `DISPLAY`, `WAYLAND_DISPLAY`, `DBUS_SESSION_BUS_ADDRESS` und den
  Session-Bus-Socket im Dateisystem. Ergebnis ist ein ehrlicher Status
  (`uncertain` / `unavailable` / `failed`) mit kurzer Begründung.
  **Niemals** ein Fake-`available`.
- **Discovery.** `interaction_discover_accessibility { hint? }`
  liefert heute ausschließlich hint-echo Items — ein ins Schema
  gehobenes Echo des Hint-Strings als strukturiertes Target mit
  `confidence: "discovered"`, `source: "accessibility_hint_echo"`.
- **Selection.** Ein einziger Target-Selection-Slot im Core
  (`selection.rs`) kann ein entdecktes Target als aktuellen Interaction-
  Kontext markieren (`target_selected`/`target_cleared`). Die Auswahl
  ist **keine Berechtigung** — Policy-Checks und Approval laufen
  unverändert.

**Ehrliche Confidence-Stufen** (aus der Entscheidungsphase des Spikes):

- `verified` ist **reserviert** für einen späteren Pfad, der ein
  Target über einen echten AT-SPI-Registry-Zugriff bestätigt. Der
  aktuelle Spike emittiert `verified` **nie**. Seit PR 37
  ([`ADR-0002`](./adr/ADR-0002-accessibility-rpc-readonly.md)) ist
  `verified` ausdrücklich an Registry-Evidenz gebunden: der RPC-Pfad
  darf `verified` nur setzen, wenn der Aufruf über das echte
  AT-SPI-RPC ging, das Item aus `GetChildren` am Registry-Root kommt
  und Rolle/Name direkt aus AT-SPI-Attributen gelesen wurden.
- `discovered` ist heute die einzige produktive Klasse.

**Was der Spike *nicht* tut** (und wofür er *nie gedacht* war):

- Kein AT-SPI-RPC, kein `GetChildren`, kein Namens-Lookup im
  Registry-Tree.
- Kein Fokus-, Klick-, Eingabe-Pfad. Discovery ist nicht Automation.
- Kein App-spezifischer Adapter. Keine Toolkit-Anbindung (GTK, Qt,
  Electron).

Details: [`docs/api.md §2.8 / §2.9`](./api.md).

---

## 9. Visual Action Mode

Ist-Zustand einer **UI-Staging-Intensitätsachse** innerhalb der
Presence-Hülle (vier Stufen: `none`, `minimal_feedback`,
`guided_movement`, `full_theatrical`). Die Namen stammen aus einer
älteren Zielbild-Achse und bleiben aus Kompatibilitätsgründen erhalten;
inhaltlich sind sie heute **Stufen der Banner-/Overlay-Deckkraft**,
nichts Weiteres. Das heißt konkret:

- **Keine Zielkoordinaten.** Der Avatar kennt kein Fremdfenster-Target.
- **Keine Bildschirmwanderung.** Der Avatar bleibt in der Presence-
  Hülle.
- **Keine echte Bewegungsbahn** zwischen Docked und Ziel.
- **Keine Compositor-spezifische Fenster-Positionierung** (Wayland/X11-
  Realität siehe
  [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)).

Was die Modi heute wirklich tun:

| Modus | Banner | Workflow Overlay | Avatar |
| --- | --- | --- | --- |
| `none` | unsichtbar | versteckt | State-Tween + Rim-Accent weiter sichtbar |
| `minimal_feedback` (Default) | dezent (~0.75 Alpha) | ruhend (hidden, ready) | unverändert |
| `guided_movement` | klar lesbar (~0.92 Alpha) | sichtbar, leicht transparent | unverändert — **keine** Bildschirm-Wanderung |
| `full_theatrical` | voll deckend | voll sichtbar | unverändert — **kein** Avatar-Pfad über Fremdfenster |

Implementierung: [`ui_architecture.md §8.5`](./ui_architecture.md)
(Staging-Tabelle, Eingabepfade `Env > Preferences > Default`,
Dev-Controls-Picker, bindende Grenzen).

Das Staging bleibt **optional und abschaltbar**. `none` liefert keine
Action-Inszenierung jenseits des minimal nötigen Status.

---

## 10. Future Work

Ausdrücklich **nicht implementiert**. Jeder Punkt bräuchte eine eigene
Design-Entscheidung (ADR, ggf. Policy-Update) vor dem Code.

- **Window-Probe nach `open_application` / `focus_window`.** Würde
  `uncertain` auf `verified` hochstufen. Offene Fragen: Wayland-
  kompatibler Primitive, Timing, Mehrmonitor-Semantik.
- **AT-SPI-Registry-Zugriff (zbus/atspi).** Erst damit kann die
  `items`-Liste des Discovery-Pfads inhaltlich gefüllt werden und
  `confidence: "verified"` einen Sinn bekommen. Rahmen ist seit
  PR 37 in
  [`ADR-0002`](./adr/ADR-0002-accessibility-rpc-readonly.md)
  entschieden: read-only `GetChildren` auf Registry-Root,
  `atspi`+`zbus` hinter `accessibility_rpc`-Feature-Flag
  (default-off), kein Input-Injection-Pfad, kein Baum-Walk über
  eine Tiefe hinaus, keine Passwort-/Secret-Felder, kein
  Approval-Bypass. **PR 53 (2026-04-26) hat FA-1 als *partial spike*
  gelandet:** Cargo-Feature + Runtime-Env
  `SMOLIT_ACCESSIBILITY_RPC_ENABLED=1` + mockable
  `AccessibilityRegistryClient`-Trait + verified-only-from-registry-
  Konstruktor sind im Repo. Default-Build verhält sich
  bit-für-bit wie pre-PR-53. Production hat *keinen* echten
  `atspi`/`zbus`-Client gewired und fällt bei Feature+Env auf
  `Unavailable { reason: "accessibility_rpc_backend_not_implemented" }`
  zurück — der reale Registry-Client ist eigener Folge-PR mit
  Permission-Review. `confidence: verified` bleibt damit weiterhin
  exklusiv für Items mit echter Registry-Evidenz.
- **Wayland-Fokus-Pfad.** Braucht ein Compositor-natives Protokoll
  (Portal / wlroots-spezifischer Pfad) oder eine explizite
  Aufgabe-Trennung. Offen, blockiert durch fehlendes generisches
  Protokoll.
- **`type_text` / `send_shortcut` Backends.** Nicht vor einer
  dedizierten Policy-Entscheidung, die mindestens Trust-Stufen für
  sensible Dialoge definiert.
- **Structured Targets aus strukturierter Discovery.** Heute trägt
  `target` praktisch nur `application:<name>` — eine strukturierte
  Discovery-Stufe könnte `window`, `ui_element`, `region` sinnvoll
  füllen.
- **Audit-Abdeckung des realen Interaction-Flows.** Erweiterung des
  Ring-Buffers aus PR 19 auf `open_application`-Lifecycle-Events
  (planned / approval_* / started / step / verification / completed /
  cancelled) — mit eigenem Redaction-Design.
- **Echte Theatrical Action Mode** (Avatar-Bewegung über Fremdfenster)
  — braucht Desktop-Geometrie-Binding (Compositor-Kopplung,
  Mehrmonitor-Mapping, sichtbare Pfadführung). Nicht stillschweigend
  unter dem bestehenden Visual-Action-Mode-Schalter einzuziehen.
- **Trust-Modell für Anwendungen.** Das Flag `trusted_only` wandert
  heute durch den Protokoll-Pfad, gated aber nichts. Eine echte
  Trust-Stufe wäre eine eigene Policy-Linie über Policy v0 hinaus.
- **MCP-/RPC-Integrationen gegen spezifische Apps.** Nicht Teil der
  nahen Reihe.

Priorisierung / Single-Source: [`docs/OPEN_WORK.md`](./OPEN_WORK.md).

---

## 11. Explicit Non-goals

Entscheidungen, die heute **aktiv ausgeschlossen** sind — nicht nur
„noch nicht", sondern bewusst verworfen:

- **Kein permanenter Desktop-Sensor.** Kein Dauer-Screenshot, kein
  Dauer-OCR, kein Dauer-Vision-Loop.
- **Kein Avatar als direkter Executor.** Der Avatar emittiert keine
  IPC-Writes gegen System-Dienste; alle Aktionen laufen über Core +
  Approval.
- **Kein Streaming-Audio, kein Phonem-/Lip-Sync, keine Audio-
  Timeline.** Siehe [`ROADMAP.md §7`](../ROADMAP.md).
- **Keine ungeprüfte Interaktion mit sensiblen Dialogen** (Passwort,
  sudo, Zahlungs-/Admin-UIs). Eine spätere Trust-Linie muss die
  Regeln explizit aussprechen.
- **Kein AdminBot / Shell-Zugriff.** Nicht im Plan.
- **Keine Auto-Rechteausweitung.** Ein einmal erteilter Approval
  gilt ausschließlich für den angefragten Kontext; keine Session-weite
  Dauer-Permission.
- **Kein Cross-Window-Avatar-Movement** ohne dedizierte
  Desktop-Geometrie-Bindung (siehe §10 Future Work).
- **Keine OceanData-Änderungen**, **keine smolitux-ui-Änderungen**,
  **keine Smolitux-Token-Implementation** aus diesem Dokument heraus.
  Der Smolitux Design Contract (ADR-0001, PR 24) behandelt
  Cross-Runtime-Konsistenz auf Token-Ebene ohne Presence-Seiteneffekte.

---

## 12. References

**Code:**

- [`core/src/interaction/`](../core/src/interaction/) — Action,
  Backend, Executor, Verifier, Recovery, Accessibility, Selection.
- [`core/src/config.rs`](../core/src/config.rs) — Policy v0 Defaults
  (PR 25): `DEFAULT_INTERACTION_REQUIRE_CONFIRMATION=true`,
  `DEFAULT_INTERACTION_ALLOW_OPEN_APP=true`,
  `DEFAULT_INTERACTION_ALLOW_FOCUS_WINDOW=false`,
  `DEFAULT_INTERACTION_ALLOW_TYPE_TEXT=false`,
  `DEFAULT_INTERACTION_ALLOW_SHORTCUTS=false`.
- [`core/src/app.rs`](../core/src/app.rs) — `dispatch_interaction`,
  `await_and_continue`, Approval-Kette.

**Docs:**

- [`docs/api.md`](./api.md) — §2.5 Action Events, §2.6 Interaction
  Layer, §2.7 Approval Flow, §2.8 Accessibility, §2.9 Target
  Selection.
- [`docs/ui_architecture.md`](./ui_architecture.md) — §4
  Nicht-Ziele der UI, §8.4c Workflow Visibility Overlay, §8.4d
  Approval UX, §8.5 Visual Action Mode, §8b Avatar Appearance.
- [`docs/security/APPROVAL_UX.md`](./security/APPROVAL_UX.md) —
  Policy v0, Approval-UX-Invarianten.
- [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md) —
  Audit-Scope (heute nur Demo-Pfad).
- [`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  — Plattform-Realität (X11 vs. Wayland / GNOME/Mutter /
  Always-on-top / Click-through).
- [`docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`](./reviews/PR23_FOCUS_WINDOW_DECISION.md)
  — `focus_window` Option 1 bestätigt.
- [`docs/reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md`](./reviews/PR25_POLICY_V0_APPROVAL_DEFAULT.md)
  — Policy v0 Reality-Check.
- [`docs/OPEN_WORK.md`](./OPEN_WORK.md) — Workstream E / F aktueller
  Stand.
- [`docs/GLOSSARY.md`](./GLOSSARY.md) — Presence, Interaction Layer,
  Action Event, Approval, Workflow Visibility Overlay, Godot-native UI.

---

## Anhang — Mapping alte → neue Abschnittsnummern

Frühere Fassungen trugen 16 Abschnitte mit vermischtem Zielbild und
Ist-Zustand. Das Mapping für eingehende Verweise aus anderen Dateien:

| Alt | Neu | Hinweis |
| --- | --- | --- |
| §1 Kurzbeschreibung | §1 Purpose | gekürzt |
| §2 Zielbild | §10 Future Work | Zielbild-Inhalte ausschließlich dort |
| §3 „Visual truth, not implementation coupling" | §1 + §6 | Leitsatz bleibt, Avatar-als-Executor-Wording entfernt |
| §4 High-Level-Systemmodell | (entfällt) | Schichten-Diagramm ersetzt durch §6 + §7 |
| §5 Presence Model + Workflow-Overlay-Extension + Avatar-Personalisierung | §6 Presence UI Responsibilities | auf Ist-Zustand gekürzt |
| §6 Always-on-top-Konzept (Docked/Expanded/Action Mode) | §6 (Presence-Modi) + §9 (Visual Action Mode) | Plattform-Details in `linux_window_overlay_architecture.md` |
| §7 Visual Action Model | §9 Visual Action Mode | explizit als UI-Staging benannt |
| §8 Desktop Automation Model | §5 Approval / Policy v0 + §11 Explicit Non-goals | 4-Modi-Vokabular entfernt; Ist ist confirm-before-action |
| §9 Interaction Fidelity Model | §7 + §10 | einzig gelebter Pfad ist native-first |
| §10 Desktop Interaction Stack v1 | §7 + §10 Future Work | click / type / scroll / drag&drop → §10 |
| §11 Beispielabläufe | (entfällt) | basierten auf nicht-implementiertem Stack |
| §12 Sicherheitsmodell | §5 Approval / Policy v0 | nur Policy v0 als reale Baseline |
| §13 Performance-Modell | (entfällt) | Profile waren zielbild-orientiert, UI-Realität steht in `ui_architecture.md` |
| §14 Was ausdrücklich nicht Ziel von v1 ist | §11 Explicit Non-goals | geschärft |
| §14a Action Event Model v1 | §3 + §7 + `api.md §2.5` | |
| §14b Desktop Interaction Layer MVP | §3 + §7 | |
| §14b.3 Automation-Modus-Einordnung | §5 | |
| §14b.4 Ehrliche Scope-Grenzen | §4 Explicitly Unsupported | |
| §14c Accessibility Spike | §8 | |
| §14c.1/§14c.2 Confidence / Target Selection | §8 | |
| §15 Konsequenzen für die weitere Architektur | (entfällt) | Konsequenzen-Liste überholt |
| §16 Offene Punkte | §10 Future Work | präzisiert |

Historische Review-Dokumente (z. B.
[`docs/reviews/PR23_FOCUS_WINDOW_DECISION.md`](./reviews/PR23_FOCUS_WINDOW_DECISION.md))
referenzieren alte Anker wie `§14b.4`; sie bleiben als **Zeitdokumente**
unverändert. Der fachliche Inhalt ist in obenstehender Tabelle auf den
neuen Abschnitt abgebildet.
