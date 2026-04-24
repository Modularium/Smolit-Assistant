# Smolit Assistant – UI- und Avatar-Architektur

Dieses Dokument beschreibt den **heutigen Stand** der UI nach PR 19
sowie den geplanten Ausbau. Alles, was noch nicht implementiert ist,
ist explizit als Ziel-Zustand markiert.

Für das übergeordnete Zielbild von Smolit als sichtbare Desktop-Präsenz
und für das Zusammenspiel mit echter Desktop-Automation siehe
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).
Dieses Dokument hier bleibt auf die **UI-/Godot-Ebene** fokussiert.

**Terminologie (PR 20 Reality Check).** Diese Datei verwendet zwei
disjunkte Phasen-Vokabulare. Das ist historisch gewachsen; sie
kollidieren nur in der Wortwahl, nicht im Scope:

- **Produkt-Roadmap-Phasen (`Phase 0–10`):** siehe
  [`ROADMAP.md`](../ROADMAP.md). Wenn in dieser Datei z. B. „Phase
  3.1", „Phase 3.2", „Phase 3.3 Presence MVP" oder „Phase 4
  Behavioral Layer" steht, ist die Produkt-Phase gemeint.
- **Avatar-interne Rendering-Stufen (`Phase A / B / B+ / B++ /
  C`):** siehe §7 weiter unten. Diese Stufen beziehen sich
  ausschließlich auf die Avatar-Identitäts- und Render-Pipeline.
  Eine Avatar-„Phase B" hat **nichts** mit einer Produkt-„Phase 4"
  zu tun.

Die **Behavioral Expression Layer v1** aus PR 15 lebt technisch in
der Avatar-Pipeline (siehe §8.4b), ist aber ein Produkt-Ergebnis
der Roadmap-Phase 4 — sie wird deshalb an beiden Stellen referenziert.

**Zwei Workflow-Overlays koexistieren.** Der Code trägt **zwei**
Workflow-Overlay-Komponenten parallel — beide aktiv im `main.tscn`:

1. **Workflow-Overlay (MVP-Spike, Phase 3.1):** drei-Knoten-
   Kurzprojektion (Trigger / Action / Result). Siehe §6a und §8a.
2. **Workflow Visibility Overlay v1 (PR 16):** lineare
   Kartenliste über neun Schritt-Kategorien inkl. `APPROVAL`
   (aus PR 17). Siehe §8.4c.

Die Koexistenz ist bewusst: der ältere Overlay bleibt für Action-
Event-Kurzprojektionen, der neuere deckt die vollständige
Lifecycle-Reihe (inkl. Approval/Audit) ab. Ein zukünftiger PR
kann die Konsolidierung beider Komponenten angehen — siehe
[`docs/OPEN_WORK.md`](./OPEN_WORK.md) Workstream A.

**Einheitliches Vokabular.** Begriffe wie `Approval`, `Audit Trail`,
`Workflow-Overlay`, `Workflow Visibility Overlay`, `Presence`,
`Expression`, `Action Event`, `Interaction Layer`, `Provider Chain`
und `Stage C` sind in
[`docs/GLOSSARY.md`](./GLOSSARY.md) definiert. Wenn in dieser
Datei ein Begriff anders erscheint, gewinnt das Glossar.

**Smolitux Design Contract (Cross-Repo-Orientierung).** Smolit-
Assistant ist **Godot-nativ**. Die UI folgt perspektivisch einem
*Smolitux Design Contract* gegenüber der Web-/React-Komponenten-
bibliothek [smolitux-ui](https://github.com/Modularium/smolitux-ui).
Das heißt konkret für diese Datei:

- **Keine direkte React-Komponentennutzung** in der Godot-UI. Es
  werden keine `@smolitux/*`-Pakete zur Laufzeit importiert.
- **Keine WebView-Einbettung** einer Smolitux-UI-Oberfläche.
- **Keine React↔Godot-Brücke.**
- **Design Tokens dürfen später in Godot-native Theme-Ressourcen
  gemappt werden**, sobald smolitux-ui Tokens in einem
  serialisierbaren Format (z. B. JSON / YAML / TOML) bereitstellt.
  Heute ist das nicht implementiert.
- **OceanData** ist Data-Layer / Datenplattform und ausdrücklich
  **nicht** Quelle des UI-Designs; sie wird in dieser Datei und im
  Design Contract nicht als UI-Library behandelt.

Details: [`docs/adr/ADR-0001-smolitux-design-contract.md`](./adr/ADR-0001-smolitux-design-contract.md)
und [`docs/OPEN_WORK.md`](./OPEN_WORK.md) Workstream J.

---



## 1. Rolle der UI

Die Godot-UI ist ein **reiner Client** des Rust-Cores. Sie hat:

- **keine eigene Intelligenz** (kein ABrain-Aufruf, kein Prompting),
- **keine eigene Audio-Pipeline** (kein STT/TTS, kein Mikrofon, keine
  Lautsprecher-Ausgabe),
- **keine eigene Session-Wahrheit** (keine Chat-Historie, kein Profil,
  keine Preferences),
- **keine Protokollerweiterung** am IPC, die über das in
  [`docs/api.md`](./api.md) festgelegte Format hinausgeht.

Die UI konsumiert Events vom Core und rendert sie. Alle Interaktionen
werden als wohldefinierte IPC-Nachrichten an den Core zurückgespielt.

Im Sinne des Presence-Modells ist die UI der **Presence Layer**:
sichtbare Figur, Zustände, Overlay-Verhalten, Rückmeldung. Sie ist
ausdrücklich **nicht** die Stelle, an der Desktop-Automation
implementiert wird — siehe
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md),
Abschnitt 3 („Visual truth, not implementation coupling“) und
Abschnitt 15.

---

## 2. Systemübersicht

```text
┌────────────────────────────┐        ws://127.0.0.1:8787        ┌────────────────────┐
│  Godot UI (ui/)            │  ◀─────────────────────────────▶  │  Rust Core (core/) │
│  - Autoload EventBus       │     JSON Frames (siehe api.md)    │  - CLI Event-Loop  │
│  - Autoload IpcClient      │                                   │  - IPC-Server      │
│  - Scenes (Renderer)       │                                   │  - App (Handlers)  │
└────────────────────────────┘                                   │  - Audio-Adapter   │
                                                                 │  - ABrain-Adapter  │
                                                                 └────────────────────┘
                                                                          │
                                                                          ▼
                                                                 ┌────────────────────┐
                                                                 │  ABrain (CLI)      │
                                                                 │  externe Commands  │
                                                                 │  (STT / TTS)       │
                                                                 └────────────────────┘
```

Der Core ist die einzige Quelle der Wahrheit. UI und ABrain/Audio sind
jeweils Adaptergrenzen.

Die Godot-UI besteht perspektivisch nicht nur aus Avatar-/Presence-
Rendering, sondern zusätzlich aus einem **Workflow-Overlay-Renderer
als passivem Action-Readout** (Ziel-Zustand, siehe §6a und §8a).
Beide konsumieren denselben Event-Strom aus dem Core — das Overlay
projiziert bestehende Action Events symbolisch, es führt nichts
aus und erzeugt keine eigene Wahrheit.

---

## 3. Verantwortlichkeiten

| Schicht        | Verantwortlich für                                           |
|----------------|--------------------------------------------------------------|
| Rust Core      | Orchestrierung, Konfiguration, Logging, Audio, IPC, ABrain   |
| IPC-Bridge     | lokaler WebSocket-Server, JSON-Protokoll, Event-Fan-out      |
| Godot UI       | Rendering (Avatar, Presence, Workflow-Overlay; perspektivisch zusätzlich Avatar Appearance System), Animation, lokale Eingabe, Statusanzeige; **keine** Logik, **keine** Execution |
| ABrain-Adapter | Textanfrage → Antworttext (heute CLI-Prozess)                |
| STT/TTS-Adapter| externe Commands, austauschbar per Env-Config                |

---

## 4. Nicht-Ziele der UI

Ausdrücklich **nicht** in der UI:

- keine Entscheidungslogik („was soll der Assistent antworten?"),
- keine Tool-Orchestrierung,
- keine zweite Runtime / kein zweiter Prozess-Manager,
- keine zweite Audiopipeline,
- keine persistente Wahrheit über den Verlauf (Event-Log ist volatil),
- keine direkten Zugriffe auf ABrain, Dateisysteme oder Subsysteme außerhalb
  der IPC-Nachrichten,
- **keine Desktop-Automation** (kein Klicken, Tippen, Fenster-Steuern,
  kein OCR/Screenshot). Desktop-Interaktion gehört in eine eigene
  Adapterfamilie unterhalb des Cores, nicht in Godot — siehe
  [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).
- **kein Settings-Universal-Panel im heutigen MVP.** Ein späteres,
  bewusst eng geschnittenes Settings-UI ist in
  [`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md)
  §6 als Architekturgrundlage vorbereitet (Bereiche:
  General / Presence-UI / Text-/STT-/TTS-Provider / Privacy /
  Connection), ist in diesem MVP aber ausdrücklich nicht implementiert
  und wird in eigenen, kleinen Folge-PRs angelegt. Die UI bleibt bis
  dahin Settings-Client, nie Settings-Eigentümer.

---

## 5. Godot-Projektstruktur (Ist-Zustand Phase 3.1)

```text
ui/
├── project.godot        # Godot-4-Projektdefinition, registriert Autoloads
├── config.cfg           # UI-eigene Config: websocket_url, reconnect, debug
├── autoload/
│   ├── event_bus.gd     # reiner Signal-Hub, keine Logik
│   └── ipc_client.gd    # WebSocketPeer-Wrapper, Reconnect, Frame-Parsing
├── scenes/
│   └── main.tscn        # Control → VBox(StatusLabel, Log, InputRow)
├── scripts/
│   └── main.gd          # Scene-Controller, verdrahtet EventBus + UI
├── assets/              # Platzhalter für 3.2
└── .gitignore
```

Scenes hängen ausschließlich am `EventBus`. Der Transport (`IpcClient`) ist
damit austauschbar, ohne Scene-Code anzufassen.

### Workflow-Overlay-Erweiterung (MVP-Spike, Ist-Zustand)

Ein erster kleiner Spike des Workflow-Overlays ist jetzt im Repo
verankert. Er ist bewusst minimal: drei feste UI-Knoten (Trigger →
Action → Result), zwei Kanten, dezente Aktivierungsanimation,
read-only, core-driven. Keine Persistenz, keine neuen IPC-Events,
keine neuen Protokoll-Pflichten — die Kurzprojektion entsteht aus
den bestehenden Action Events. Die ursprüngliche Platzhalter-
Dateiliste hat sich dadurch zur **tatsächlich existierenden**
Struktur verfestigt (`workflow_overlay_layout.gd` aus der ersten
Doku-Skizze ist bewusst entfallen — das MVP braucht keinen
separaten Layout-Algorithmus, der HBoxContainer reicht):

```text
ui/
├── scenes/
│   ├── main.tscn
│   ├── settings/
│   │   └── settings_panel.tscn
│   └── workflow_overlay/
│       └── workflow_overlay_root.tscn
├── scripts/
│   ├── main.gd
│   ├── settings/
│   │   ├── settings_sections.gd
│   │   └── settings_panel_controller.gd
│   └── workflow_overlay/
│       ├── workflow_overlay_controller.gd
│       ├── workflow_overlay_state.gd
│       ├── workflow_node_view.gd
│       └── workflow_edge_view.gd
```

Wichtige Grenzen des MVP:

- **Read-only / core-driven.** Der Controller konsumiert
  ausschließlich `EventBus`-Signale (`action_planned`,
  `action_started`, `action_step`, `action_completed`,
  `action_failed`, `action_cancelled`) und sendet **keine**
  neuen IPC-Nachrichten.
- **Drei feste Rollen.** Trigger, Action, Result. Kein Graph-
  Framework, keine dynamische Knotenzahl, keine freie Verkabelung.
- **Sichtbarkeit an den Flow gebunden.** Der Overlay zeigt sich
  erst, wenn ein `action_planned` gesehen wurde; er versteckt sich
  wieder bei `ipc_disconnected`. Presence-/Docked-Logik wird
  dadurch nicht angefasst — es gibt **keine** zweite globale
  Presence-State-Maschine.
- **Keine fixen Markenfarben als API.** Zustandsfarben sind
  Tönungen (`modulate`) auf den Panel-Views, keine veröffentlichte
  Palette.
- **Keine Kollision mit Approval-/Action-/Discovery-Bannern.** Der
  Overlay sitzt absolut positioniert unterhalb des Avatars
  (x=18..346, y=162..210) und liegt per `z_index=40` unter dem
  Compact-Input-Panel (z=50) und dem Avatar (z=100); Banner im
  VBox-Stack verwendet z=0 und wird bei Bedarf vom Overlay
  *oberhalb* überlagert, ohne Interaktion zu stören (Overlay ist
  `mouse_filter = IGNORE`).

Was bewusst offen bleibt:

- **Keine Step-ID-Korrelation.** Der MVP nimmt jedes
  `action_planned` als neuen Flow an, unabhängig vom
  `action_id`-Feld — Multi-Action-Sequenzen werden also nicht
  visuell unterschieden, sondern überschrieben.
- **Kein Rewind, kein History-Scroller.** Nach einem
  `action_completed`/`action_failed` bleibt der Endzustand stehen,
  bis ein neuer Flow startet.
- **Kein Docked-vs-Expanded-Fallback im Layout.** Visibility ist
  rein flow-getrieben; eine spätere Feinanpassung pro Presence-
  Mode ist möglich, aber nicht Teil dieses Spike.

---

## 6. IPC-Bindung der UI

- Default-URL: `ws://127.0.0.1:8787`, überschreibbar in `ui/config.cfg`
  unter `[ipc] websocket_url`.
- Reconnect-Strategie: exponentielles Backoff von `min_backoff_ms = 500`
  bis `max_backoff_ms = 5000`, Verdopplung, gecapped.
- Nach jedem erfolgreichen Connect wird automatisch ein `get_status`
  als Handshake gesendet.
- Während *disconnected* bleibt die UI sichtbar und benutzbar; Send/Ping
  deaktivieren sich jedoch, da kein Transport offen ist.
- Ungültige JSON-Frames führen zu einer lokalen `error_received`-Emission,
  nicht zu einem Crash.
- Für freigabepflichtige Aktionen versteht die UI die zusätzlichen
  Approval-Frames (`approval_requested` / `approval_resolved`) aus
  [`docs/api.md`](./api.md) §2.7. `IpcClient.send_approval_response`
  ist der einzige Weg, Approve/Deny zurück an den Core zu schicken;
  `EventBus` vermittelt sie an die Scene, die einen modalen Banner
  mit Approve-/Deny-Buttons einblendet, solange eine Approval-ID
  offen ist.

Das genaue Protokoll (Eingangs- und Ausgangs-Nachrichten, Felder,
Semantik) ist in [`docs/api.md`](./api.md) beschrieben und ist die
autoritative Quelle; diese Datei dupliziert das Schema nicht.

---

## 6a. Workflow-UI — eine einzige Wahrheit (PR 33, Ist-Zustand)

Seit **PR 33 (2026-04-24)** gibt es genau **eine** Workflow-UI im
Smolit-Assistant: das *Workflow Visibility Overlay v1* aus PR 16
(detailliert in §8.4c). Der frühere Drei-Knoten-MVP-Spike
(`ui/scripts/workflow_overlay/`,
`ui/scenes/workflow_overlay/workflow_overlay_root.tscn`) ist mit
PR 33 vollständig entfernt worden; die Koexistenzlücke aus PR 20
(Docs Reality Check) ist damit geschlossen.

Leitlinien für die verbleibende Workflow-UI:

- **Rein visuelle, read-only Projektion von Core-Zuständen.** Die
  UI erzeugt keinen eigenen Zustand, sondern leitet ihr Bild aus
  den vom Core emittierten Action Events + Approval-Lifecycle-
  Signalen ab.
- **Quelle der Wahrheit.** Ausschließlich Core / EventBus.
- **Ziel.** Verständlicher Handlungszusammenhang (HEARD → THINKING
  → RESPONSE → ACTION → STEP → SPEAKING → APPROVAL → COMPLETED /
  FAILED) statt rein textueller Log-Ausgabe.
- **Position.** Als eigenes PanelContainer-Node in der Main-Scene,
  neben dem Avatar. Kein separates Toplevel-Fenster, keine neue
  Plattformfähigkeit.
- **Interaktion.** Keine Interaktionsversprechen — read-only.

Was §6a explizit **nicht** verspricht:

- keine Ausführung, kein Executor, kein Zugriff auf den Desktop —
  Desktop-Interaktion bleibt vollständig im Core / Interaction
  Layer;
- kein eigenes Protokoll neben den bestehenden Action- und
  Approval-Events;
- keine Pflichtaktivierung — das Overlay ist per Default
  **versteckt** (`SMOLIT_WORKFLOW_OVERLAY=1` oder session-lokaler
  Dev-Toggle schalten es sichtbar). Siehe §8.4c für die
  Rendering-Details.

---

## 7. Avatar-System (Phasen)

Avatar-Rendering ist **noch nicht implementiert**. Die Phasen unten sind
die geplante Ausbaustrecke, nicht der heutige Stand.

### Phase A – MVP-Log (Ist-Zustand 3.1)

- `StatusLabel` zeigt `connected` / `disconnected`.
- `RichTextLabel` rendert eingehende Events farbcodiert als Event-Log.
- `LineEdit` + Buttons „Send" / „Ping" bedienen `submit_text` und `ping`.
- Kein Avatar, keine Animation, keine Sprechblase.

### Phase B – 2D-Avatar + Zustände (Ist 3.2, weiter prozedural)

- 2D-Sprite als Kind-Scene, zentrale State-Machine auf EventBus-Signalen
  (`thinking_received`, `response_received`, `error_received`,
  `heard_received`).
- Animationen für: `idle`, `thinking`, `talking`, `error`.
- Speech-Bubble (Utterance MVP) zeigt `heard`/`response` neben dem
  Avatar an. Seit Phase 3.2 im Repo (siehe §8.4); das RichText-Log
  bleibt unverändert als Debug-/Event-Log.
- Keine Protokolländerung nötig; es werden nur bestehende Events gemappt.

### Phase B+ – Reaktion auf Action Events (Ziel)

Zusätzlich zu `thinking` / `response` / `heard` / `error` emittiert der
Core seit Action Event Model v1 (siehe [`docs/api.md`](./api.md), §2.5)
standardisierte **Action Events** (`action_planned`, `action_started`,
`action_step`, `action_completed`, `action_failed`, …). Sie sind die
vorgesehene Grundlage für:

- Avatar-/Präsenz-Reaktion auf Handlungsphasen statt nur auf
  `thinking`/`response`,
- spätere sichtbare Fehlerdarstellung (`action_failed` → Warn-/Failure-
  State am Avatar),
- spätere symbolische Bewegung Richtung Ziel (über `target` und
  `mapping`).

Wichtig für die UI-Ebene:

- **Mapping ist symbolisch.** `mapping.space` ∈
  `logical_space` / `window_space` / `screen_space`, ohne Geometrie.
  Die UI soll daraus eine Richtung / Intention ableiten, keine
  Pixelpositionen berechnen.
- **Additiv.** Die bestehenden Signale bleiben. Action Events werden
  schrittweise eingebunden, keine Umschreibung des Scene-Codes auf
  einmal.
- **Keine UI-Geschäftslogik.** Die UI reagiert auf die Events, sie
  interpretiert keine Targets eigenständig und löst keine
  Desktop-Aktionen aus.

### Phase B++ – Micro-Animation / Personality Layer v1 (Ist)

Auf Phase B/B+ sitzt eine reine **UI-Ausdrucksschicht** auf: kleine
Mikro-Animationen, die Smolit lebendig wirken lassen, ohne neue States,
neue Events oder Emotions-Protokollfelder zu benötigen. Sie ist ein
bewusst kleiner Vorgriff auf Phase 4 — kein volles Emotionssystem, kein
Sprite-Rig.

Zentrale Idee: der Ausdruck sitzt auf **drei orthogonalen
Transform-Layern**, die sich nie um dieselbe Property streiten:

- **Root `self.scale`** — Hover-Pop (kurzer Tween auf enter/leave).
- **`_body.scale`** — State-Cycle-Pulse: `idle` atmet ruhig,
  `thinking` atmet enger/langsamer, `acting` leicht zielgerichteter,
  `talking` rhythmisch aktiv, `error` zeigt einen einmaligen Startle
  (Flinch + Rebound + Settle). Es läuft immer höchstens **einer** dieser
  Scale-Tweens — `_apply_state_visuals` killt den vorherigen sauber
  beim Statuswechsel.
- **`_body.rotation`** — seltener „curious wiggle" im Idle: ein
  kleiner Rotations-Nudge, alle 14–28 s randomisiert, nur wenn
  weiterhin idle und nicht gerade ein Drag läuft.
- **`_body.modulate:a`** — Thinking-Alpha-Puls (aus dem MVP
  übernommen).

Weitere Eigenschaften:

- **Disconnected** bleibt bewusst still — matte Tönung, keine
  Tween-Last, niedriger Idle-Footprint.
- Hover-Tweens killen den vorherigen Tween, damit schnelles
  Enter/Leave keine überlappenden Animationen akkumuliert.
- Jeder State-Wechsel setzt `_body.scale`/`_body.rotation` wieder auf
  Ruhe und stoppt Timer/Tweens, damit keine Animationsreste
  hängenbleiben.
- Ausdruck basiert **ausschließlich** auf vorhandenen Core-Events /
  Avatar-States. Keine neue Entscheidungs- oder Emotionslogik, keine
  neuen IPC-Nachrichten, kein neues State-Feld im Protokoll.

### Phase B Render Polish (Ist 3.2, rein prozedural)

Kleine, bewusst konservative Qualitätsanhebung des bestehenden 2D-MVPs.
**Keine** Sprite-/Spritesheet-Animation, **keine** Frame-Sequenzen,
**keine** neuen Assets, **keine** 2.5D-/3D-Arbeit, **keine** Stage-C-
Vorarbeit. Zweck ist lediglich, die Figur als Figur besser lesbar zu
machen, statt sie wie einen technischen Block-/Rect-Placeholder wirken
zu lassen.

Zwei additive Bausteine sitzen auf der bestehenden Avatar-Scene:

- **Rim Accent (`ui/scripts/avatar/avatar_rim_accent.gd`,
  `$AvatarRoot/RimAccent`).** Ein dünner prozeduraler State-Ring an der
  Silhouette, oberhalb von `Body` / `IdentityShape` gezeichnet. Der
  Ring ist **identitäts-neutral** — Smolit-Texture und alle drei
  kuratierten Alternativen teilen sich denselben Rim, die Farbe kommt
  ausschließlich aus dem Avatar-State
  (`IDLE` / `THINKING` / `TALKING` / `ACTING` / `DISCONNECTED` /
  `ERROR`). Der Controller stupst den Ring in jedem
  `_apply_state_visuals`-Durchlauf per `set_state(effective_state)`
  an; für kuratierte Identities mit `state_fallback` (z. B.
  `orb.TALKING → ACTING`) zeigt der Rim die Farbe des *tatsächlich*
  gerenderten States — keine zweite Wahrheit neben dem Capability-
  Contract. Rein statisch: keine Tweens, keine Timer, keine
  Eingabe-Annahme (`mouse_filter = MOUSE_FILTER_IGNORE`). Smolit
  profitiert hier sichtbar, obwohl der `TEXTURE`-Pfad selbst
  unverändert bleibt.
- **Polish im prozeduralen Zeichnen
  (`ui/scripts/avatar/avatar_identity_visual.gd`).** Die drei
  kuratierten Alternativen bekommen eine kleine, tastefully zurück-
  gehaltene Qualitätsanhebung, weiter rein prozedural:
  - **Robot-Head** — abgesetzte dunklere „Face-Plate" im Augenband,
    Pupillen in den Augen, sichtbarer Antennen-Stalk zum Dot,
    schmale Mund-Slit-Linie.
  - **Humanoid-Head** — sehr dezente Wangen-Blush-Kreise, kleine
    weiße Highlight-Dots in den Pupillen, zusätzlicher weicher
    Kinn-Schatten-Arc unter dem Mund.
  - **Orb** — vier konzentrische Halo-Layer mit abnehmender Alpha
    statt des früheren zweistufigen Verlaufs, plus ein kleiner
    Sekundär-Highlight unten-rechts für Tiefe.
  - **Smolit-Salamander** — `TEXTURE`-Pfad unverändert, damit die
    Identitätsgarantie (Default + CALM + Unity-Overrides = vor-PR-
    Verhalten) bytegleich gültig bleibt. Die sichtbare Qualitäts-
    anhebung für Smolit kommt über den gemeinsamen Rim-Accent.

Harte Grenzen dieses Schritts, bindend für spätere PRs in dieser Linie:

- **Kein Sprite-/Asset-Import.** Keine neuen PNG/SVG/GLB-Dateien,
  kein Asset-Loader, keine Import-Pipeline.
- **Kein `if identity == …`-Branch im Controller.** Template-Fallbacks
  und Expression-Levels laufen weiterhin ausschließlich über
  `avatar_template_capabilities.gd` (§8b.8). Der Rim-Accent selbst ist
  identitätsneutraler Presence-Polish — keine neue Ausdrucks-Achse
  im Capability-Contract.
- **Kein State-Maschinen-Umbau.** Die sechs Avatar-States
  (`IDLE` / `THINKING` / `TALKING` / `ACTING` / `DISCONNECTED` /
  `ERROR`) bleiben unverändert; keine neuen Phasen, kein neues
  Ausdrucks-Feld im Protokoll.
- **Kein TTS-/Speech-Sync an diesem Polish-Schritt.** Der Polish
  reagiert rein auf den Avatar-State. Der tatsächliche Speech-Sync
  via `speaking_started` / `speaking_ended` ist in PR 14 gelandet
  (siehe §8.5) und ändert nicht den Polish-Pfad — er füttert nur
  den bestehenden State.
- **Default-Smolit und Fallback-Verhalten bleiben geschützt.**
  Unbekannte Identity-IDs werden weiterhin auf Smolit geklemmt
  (`avatar_identity.gd::identity_from_string`); unbekannte States am
  Rim fallen still auf die `IDLE`-Farbe zurück, ohne den Controller-
  State zu ändern.

Verifikation: `scripts/avatar_render_polish_smoke.gd` (19 Assertions,
alle PASS) deckt die Rim-Farbtabelle, den Unbekannte-State-Fallback,
Distinctness der sechs State-Farben, `set_state` / `current_state` am
Rim-Node sowie einen Redraw-Sanity-Durchlauf aller vier kuratierten
Identities (inkl. unbekannter ID clamp) ab. Harness-Case
`scripts/run_overlay_verification.sh avatar-render-polish-smoke`.

### Phase B Render Polish Follow-up (PR 30, Ist-Zustand)

PR 30 setzt einen kleinen, eng umrissenen zweiten Polish-Schritt
**ausschließlich in den bestehenden prozeduralen `_draw_*`-Pfaden
aus `avatar_identity_visual.gd`** obendrauf. Keine neuen Identities,
keine neuen States, keine neuen Capabilities, keine Stage-C-
Vorarbeit, keine Core-/IPC-Änderung.

Strukturell neu: eine kuratierte Polish-Palette
[`ui/scripts/avatar/avatar_palette.gd`](../ui/scripts/avatar/avatar_palette.gd)
(pure `RefCounted`) bündelt die neuen Konstanten zentral — statt sie
als Magic-Numbers in die `_draw_*`-Funktionen zu streuen. Die
Palette duplizert **keine** bestehenden Paletten (Rim-Accent-Tabelle
bleibt in `avatar_rim_accent.gd`, Theme-Tints in
`avatar_appearance.gd`, State-Modulates in `avatar_controller.gd`);
sie ist der Andockpunkt für einen späteren, reversiblen Token-
Import-Spike gemäß [ADR-0001](./adr/ADR-0001-smolitux-design-contract.md)
(Smolitux Design Contract, PR 24). Heute werden **keine** Tokens
konsumiert, keine JSON/YAML/TOML-Dateien geladen, keine Generatoren
ausgeführt.

Identity-spezifische Feinarbeit:

- **Robot-Head** — dünner heller Innen-Rim auf der Face-Plate
  (verankert die dunklere Plate visuell im Kopf), kleiner
  Specular-Dot pro Pupille (lebendigerer Blick ohne Animation),
  Mini-Highlight oben-links auf der Antennen-Kuppe.
- **Orb** — zusätzliche weiche Core-Glow-Scheibe zwischen Kern-
  Kreis und Primär-Highlight, nach oben-links in Richtung der
  bestehenden Licht-Quelle versetzt. Nutzt die Base-Color mit
  reduziertem Alpha und fügt dem Orb eine weitere Tiefenstufe
  ohne Shader.
- **Humanoid-Head** — Zweischicht-Blush (größerer, sehr zarter
  Außenkreis plus kleinerer, etwas dichterer Innenkreis statt des
  bisherigen Einzeltupfens) und dezente statische Augenbrauen-
  Linien leicht nach außen geneigt (prägen den Ruhe-Ausdruck, keine
  Animation, kein neuer State).
- **Smolit-Salamander** — `TEXTURE`-Pfad weiterhin unverändert. Die
  Identitätsgarantie (Default + CALM + Unity-Overrides =
  vor-PR-Verhalten) bleibt bytegleich gültig. Smolit profitiert
  indirekt über den gemeinsamen Rim-Accent; der Rim selbst wird
  nicht angefasst.

Bindende Grenzen (zusätzlich zu denen des Vor-Polish):

- **Keine Änderung des Template-Capability-Contract.**
  `orb.wiggle == NONE` bleibt, `orb.TALKING → ACTING`-Fallback
  bleibt, Smolit bleibt `reference-all-FULL`. Smoke-Lock:
  `_check_capabilities_unchanged_by_polish`.
- **Kein `if identity == …`-Branch im Controller.** Alle neuen
  Details leben in denselben `_draw_*`-Methoden wie vorher; der
  Controller orchestriert nach wie vor nur State + Transform-
  Mirror.
- **Keine Änderung der Default-Identität.** `DEFAULT` bleibt
  `SMOLIT_SALAMANDER`; unbekannte IDs klemmen weiterhin dorthin.
  Smoke-Lock: `_check_default_identity_unchanged_by_polish`.
- **Keine neuen Assets.** `git diff` bleibt rein textuell (keine
  PNG / SVG / GLB / AUDIO-Binaries).
- **Keine Token-Implementation.** Die Palette ist ein Andockpunkt —
  kein Token-Loader, kein Generator, keine `@smolitux/*`-
  Abhängigkeit.

Verifikation:
`scripts/avatar_render_polish_smoke.gd` wächst von 19 auf 52 PASS-
Assertions — die sechs zusätzlichen Cases
(`_check_palette_constant_names_are_declared`,
`_check_palette_float_constants_in_range`,
`_check_palette_color_alphas_are_sane`,
`_check_palette_rim_table_unchanged_by_polish`,
`_check_capabilities_unchanged_by_polish`,
`_check_default_identity_unchanged_by_polish`) sichern die neue
Palette und die drei Regressions-Locks (Rim-Tabelle,
Capability-Contract, Default-Identity) ab. Die existierenden
Smokes `avatar-expression-smoke`, `avatar-identity-smoke` und
`avatar-template-capabilities-smoke` bleiben grün.

### Phase 4 – Behavioral Expression Layer v1 (PR 15, Ist-Zustand)

Auf Phase B/B+/B++ und dem Speech-Sync-MVP aus PR 14 sitzt eine
**UI-only Ausdrucksschicht** oberhalb der bestehenden Avatar-State-
Maschine (`avatar_state.gd`). Sie ist der erste kleine Schritt in
Richtung Phase C und bleibt bewusst minimal: keine neuen Events, kein
neues Protokoll, kein Emotion-Feld, kein Audio-/Lip-Sync.

- **Modul:** [`ui/scripts/avatar/avatar_expression.gd`](../ui/scripts/avatar/avatar_expression.gd) — reine
  `RefCounted`-Logik (Enum `Kind`, Namen-Parser, Hold-Semantik,
  Multiplier, `default_for_state`). Kein Scene-Knoten, kein Signal,
  keine eigene State-Maschine.
- **Wiring:** [`ui/scripts/avatar/avatar_controller.gd`](../ui/scripts/avatar/avatar_controller.gd) hält
  die aktuelle Expression als UI-Nebenfeld (`_expression`,
  `_expression_is_transient`, `_expression_hold_timer`) und faltet
  drei Multiplikatoren auf den bestehenden Render-Pfad:
  - Puls-Amplitude (`_start_breath_tween` — `pulse_mult × expression_pulse`)
  - Wiggle-Winkel (`_play_wiggle` — `angle_mult × expression_wiggle`)
  - Appearance-Tint (`_apply_expression_tint`, multiplikativ auf das
    Ergebnis von `_appearance_tint`).

  Alle drei Faltungen sitzen **nach** der bestehenden Template-
  Capability-Multiplikation (`avatar_template_capabilities.gd`). Ein
  Template mit `wiggle = NONE` bleibt damit in jeder Expression
  still; der Expression-Layer kann eine Fähigkeit nicht „nachrüsten".
- **Modi:** `neutral`, `focused`, `curious`, `speaking`, `pleased`,
  `error_soft`. Sticky sind `neutral`, `focused`, `speaking`;
  transient (mit kurzem Hold-Timer) sind `curious`, `pleased`,
  `error_soft`. Transient-Holds sind bewusst ≤ 1.5 s, damit der
  Layer ein Mikro-Cue bleibt und nicht zu einem Schatten-State wird.
- **Event-Mapping (rein UI-seitig):**
  - `thinking` → `focused` (via `default_for_state(THINKING)` beim
    State-Wechsel auf `THINKING`).
  - `response_received` → `pleased` (transient). Ohne TTS rollt der
    Hold den Ausdruck anschließend auf den State-Default.
  - `speaking_started` → `speaking` (sticky). Pinnt den Ausdruck und
    löst einen eventuell noch laufenden `pleased`-Cue sauber ab. Der
    PR-14-Guard (steigt nicht aus `ACTING`/`ERROR` auf `TALKING`)
    bleibt bindend — keine Expression wird gesetzt, wenn der Handler
    früh zurückkehrt.
  - `speaking_ended(ok=true)` → kurzer `pleased`-Cue, danach via
    State-Hold zurück auf `neutral`.
  - `speaking_ended(ok=false)` → `error_soft` *vor* dem State-Wechsel
    auf `ERROR`, damit kein Flackerfenster TALKING→ERROR sichtbar
    wird. Der bestehende Fehler-Pfad bleibt führend: der State wird
    wie vor PR 15 auf `ERROR` geschaltet.
  - `heard_received` → `curious` (transient). Kein State-Wechsel; nur
    visueller „Hm, gehört"-Cue. STT-Ergebnisse bleiben Core-seitig
    bindend für Thinking/Approval-Entscheidungen.
  - `disconnected` → State-Default über
    `default_for_state(…, connected=false)` = `neutral`.
    `DISCONNECTED_MODULATE` aus der State-Visualisierung färbt
    weiterhin den Offline-Look; der Expression-Layer bleibt stumm.
- **Dev-Preview:** `preview_expression(kind)` auf dem Controller ist
  ein kleiner Lese-/Schreib-Hook für zukünftige Dev-Controls. PR 15
  verdrahtet ihn noch nicht in ein Panel — das passiert nur, wenn
  die bestehende `ui/scripts/dev_controls/`-Struktur sauber wieder-
  verwendbar ist. Kein Settings-/Auto-Save-System.
- **Smoke:** [`scripts/avatar_expression_smoke.gd`](../scripts/avatar_expression_smoke.gd),
  als Case `avatar-expression-smoke` im
  [`scripts/run_overlay_verification.sh`](../scripts/run_overlay_verification.sh) registriert.
  Prüft pure Logik (Parser, Holds, Multiplier-Grenzen, Tint-Shift-
  Shape, `default_for_state` inkl. Disconnect-Dominanz) und
  Controller-Verdrahtung (Multiplier-Fold, Event-Mapping, PR-14-
  Guard, Template-Capability-Gates bleiben bindend) auf
  Quelltextebene.

**Abgrenzungen:**

- Keine Emotion-Protokollerweiterung. Kein `emotion`-Feld auf
  `response`, `action_*` oder `thinking`.
- Kein Phonem-/Lip-Sync, keine Audio-Timeline, keine Streaming-
  Audiodaten — der Layer reagiert rein auf die bestehenden
  Lifecycle-Events aus §8.4a.
- Kein Stage-C-Asset-Import. Alle Cues sitzen auf prozeduralen
  Nodes/Properties; es gibt keine neuen Binärassets.
- Kein State-Ersatz. `avatar_state.gd` bleibt die Wahrheit für
  idle/thinking/talking/acting/error/disconnected. Der Expression-
  Layer ist eine parallele, subtile Projektion — sichtbar nur als
  Puls-/Wiggle-/Tint-Modulation.
- Kein Personality-/Policy-Kanal. Der Layer kennt keine Provider,
  keine Approval-Semantik, keine Settings.


### Phase C – Erweiterter Ausdruck (Ziel > 3.x)

- Feinere Zustände (z. B. `curious`, `focused`, `alert`).
  **Hinweis:** `curious` und `focused` sind seit PR 15 als
  UI-Expressions verfügbar (siehe Phase 4). Phase C meint zusätzlich
  tiefere Zustandsfeinheit im Core-Protokoll — das ist nicht Teil
  des Expression-Layers.
- Speech-Sync mit TTS-Lebenszyklus — **MVP gelandet (PR 14).** Der
  Core meldet `speaking_started` / `speaking_ended` (siehe §8.4a);
  tieferer Sync (Phonem-/Lip-Sync, Audio-Timeline) bleibt bewusst
  offen.
- Optional höher aufgelöste 2.5D/3D-Darstellung.

Jede Phase nach A ist additiv zum vorherigen Stand und erfordert entweder
reine UI-Arbeit oder eine klar dokumentierte Protokollerweiterung im
Core.

---

## 8. Zustands- und Eventmodell (Ist-Zustand)

Die UI kennt drei Zustandsquellen:

1. **Transportzustand** (`connected` / `disconnected`) — von `IpcClient`.
2. **Statuspayload** (`status_received`) — zuletzt gemeldetes Core-Status-Dict.
   Seit der Accessibility-Spike-Phase enthält dieses Dict zusätzlich die
   rein informativen Felder `accessibility_probe` und
   `accessibility_probe_reason`. Die UI darf sie anzeigen, aber **nicht**
   interpretieren (keine Logik-Abhängigkeit).
3. **Event-Strom** (`thinking`, `response`, `heard`, `error`, `pong`,
   sowie optional `accessibility_probe_result` /
   `accessibility_discovery_result`) — rein reaktiv, wird vom `EventBus`
   verteilt. Accessibility-Payloads sind für die UI reine Darstellungsdaten
   (status + reason + optionale strukturierte Items mit `confidence`,
   `source`, optional `matched_hint`); es gibt keinen UI-seitigen
   Discovery-Entscheidungszweig.

### 8.1 Discovery-Panel (Accessibility-Darstellung)

Seit der „verified target discovery"-Stufe rendert `ui/scenes/main.tscn`
ein kleines **DiscoveryPanel** zwischen Approval-Banner und Avatar. Es
hört ausschließlich am `EventBus` — konkret an den Signalen
`accessibility_probe_result_received` und
`accessibility_discovery_result_received`. Verhalten:

- **`status=ok`** — Liste der Items mit Name, Rolle/Kind und einem
  Confidence-Badge (`[verified]` / `[discovered]`) pro Item.
  Optional erscheint eine Zusatzinfo (`hint=…` / `detail` / `source`),
  wenn sie vom Core transportiert wurde.
- **`status=uncertain`** — Panel zeigt den Grund und einen neutralen
  Leer-Hinweis („probe plausible, no structured items yet"). Items
  werden angezeigt, falls welche mitgeliefert wurden.
- **`status=unavailable`** / **`failed`** — Panel zeigt den Grund und
  eine ehrliche, negative Meldung. Keine Items.

Die UI **interpretiert die Werte nicht** (kein Upgrade von
`discovered` auf `verified`, keine Filterlogik, keine
Ausführung von Targets). Sie malt nur, was der Core liefert.
Fehlen Felder im Payload, fällt die Darstellung still auf neutrale
Defaults zurück — das Panel darf nicht crashen, nur weil `role` oder
`matched_hint` fehlt.

Status- und Confidence-Badges nutzen ausschließlich symbolische
Farb-Tints zur Unterscheidbarkeit. Keine Designbaustelle,
keine Iconografie.

### 8.2 Target Selection (klickbare Auswahl)

Auf dem Discovery-Panel sitzt eine kleine, ehrliche Auswahlschicht
(siehe `docs/api.md` §2.9). Sie ist rein visuell:

- Jeder Item-Row bekommt einen **„Select"**-Button. Klick sendet
  `interaction_select_target` mit `name`, `role`, `confidence`,
  `source` und optional `matched_hint` / `app_name`. Die UI synthetisiert
  **keine** ID — der Core vergibt `sel_NNNNNN` bei leerem Feld.
- Das Panel zeigt eine dedizierte **SelectedTargetRow**
  (`selected: <name> (role, confidence)` + „Clear"-Button). Die Row
  wird erst sichtbar, wenn der Core `target_selected` bestätigt hat —
  es gibt keine optimistische UI-Annahme.
- Die bereits ausgewählte Row im Items-Container hebt ihren Button auf
  „Selected" (deaktiviert) um. Das ist der einzige visuelle Hinweis —
  keine Farbverläufe, keine Listenhervorhebung.
- **„Clear"** sendet `interaction_clear_target`. Die UI räumt die
  SelectedTargetRow erst, wenn `target_cleared` eintrifft.
- Beim `ipc_disconnected` räumt die UI die SelectedTargetRow lokal,
  weil der Core-Slot beim Reconnect sowieso leer ist.

Die **Approval-Darstellung** erweitert das bestehende Banner um eine
Zeile `Target: <name> (role, confidence)`, sofern der Core im
`approval_requested`-Payload `selected_target` mitgeliefert hat.
Auswahl ersetzt dabei **niemals** Approval: der Approve/Deny-Flow
bleibt identisch.

Auswahlsemantik, die die UI **nicht** selbst implementiert:

- kein Upgrade von `discovered` auf `verified`,
- keine Heuristik für „bestes Target",
- keine Auto-Selection nach Discovery,
- keine UI-seitige Permission-Logik,
- keine Persistenz jenseits der aktuellen Session.

Es gibt **keinen** von der UI gehaltenen Dialogzustand. Jede neue
Conversation-Turn startet mit einem `submit_text` oder `voice_once`.

### 8.3 Compact Input UX (Docked Presence)

Ergänzend zum reinen Presence-Layer trägt der Docked-Modus eine kleine
**Compact Input UX**: ein Klick auf den Avatar öffnet ein leichtes
Eingabepanel direkt am Icon. Es ist explizit **kein** neuer globaler
Presence-Mode, sondern ein lokaler UI-Substate (`_compact_input_open`)
in `ui/scripts/main.gd`, der nur im Docked-Zustand Sinn hat. Das
Compact Panel tritt als leichte Schnellinteraktion **neben** die große
Expanded-Ansicht — es ersetzt sie nicht.

Inhalt des Panels:

- **Text Input + Send** — geht über denselben `IpcClient.submit_text`-
  Pfad wie die bestehende Expanded-Eingabe; es gibt keine zweite
  Sendearchitektur.
- **Voice** — ruft `IpcClient.voice_once()` auf, also denselben
  Voice-Pfad wie bisher.
- **Add Files** — in dieser Phase nur UI-Hook mit ehrlichem
  Platzhalter (`Datei-Anhänge noch nicht implementiert`). Kein
  echtes Attachment-Backend, keine Fake-Dateiauswahl.
- **Show Commands** — togglet eine kompakte Mini-Hilfe mit genau den
  heute tatsächlich unterstützten Flows (`help`, `voice`,
  `audio-status`, `interaction_probe_accessibility`,
  `interaction_discover_accessibility`). Keine Kommandopalette.
- **Close / Escape** — schließen das Panel wieder.

Öffnen / Schließen:

- Klick auf den Avatar im Docked-Modus toggelt das Panel (das
  `clicked`-Signal vom Avatar-Controller ist bewusst die einzige
  Kopplung — die Avatar-Scene bleibt selbst darstellend).
- Wechsel nach Expanded oder Disconnected schließt das Panel
  kontrolliert (Expanded bringt die Volleingabe ohnehin mit;
  Disconnected sperrt Send/Voice sowieso).
- Nach erfolgreichem Senden bleibt das Panel offen und behält den
  Fokus im Textfeld — bewusst für schnelle Folgeeingaben. Der Nutzer
  schließt per Close-Button oder Escape.

Zusammenspiel mit anderen UI-Schichten:

- **Approval-Banner** bleibt visuell prioritär: er sitzt in
  `main.tscn` weiterhin oberhalb des Compact Panels. Das Panel darf
  offen bleiben, die Approval-UI ist nicht verdeckt.
- **Action-Banner** erscheint ebenfalls oberhalb; das Compact Panel
  bleibt stehen und kollidiert nicht.
- **Discovery-Panel** ist ebenfalls oberhalb eingeordnet — die
  vertikale Reihenfolge (Header → ActionBanner → ApprovalBanner →
  DiscoveryPanel → CompactInputPanel → Avatar → Log → Input) bleibt
  stabil.

Abgrenzungen (wichtig):

- Compact Input UX ≠ `type_text`. Dieses Panel ist
  **Nutzer → Smolit** (Eingabe an den Assistenten), während
  `type_text` Smolits Schreiben **in fremde Apps** wäre (bleibt
  Interaction-Layer-Thema, keine UI-Arbeit).
- Kein natives Overlay, kein zweites Eingabesystem, keine Drag-&-Drop-
  oder Multi-Line-Composer-Arbeit.
- Kein eigener Transport und keine Parallel-IPC; alles läuft über
  den bestehenden `IpcClient` und den bestehenden EventBus.

### 8.4 Utterance-Bubble (Speech-Bubble MVP, Phase 3.2, Ist-Zustand)

Kleine, rein rendernde Presence-Fläche für die beiden EventBus-Signale
`heard_received` und `response_received`. Die Bubble zeigt das jeweils
*aktuelle* Utterance neben dem Avatar — kein Konversationsverlauf, kein
Transcript-Renderer, kein Ersatz für das Event-Log. Sie ist Phase 3.2
in der Avatar-UI-Linie aus §7 und seit diesem PR im Repo.

**Datei-Layout.**

```text
ui/scenes/utterance/
└── utterance_bubble.tscn

ui/scripts/utterance/
├── utterance_bubble_state.gd       # pure Helfer, Kind-Enum, Konstanten
└── utterance_bubble_controller.gd  # Scene-Controller
```

**Rolle.** Rein rendernd, core-/EventBus-getrieben, ohne eigene Wahrheit.
Der Controller abonniert auf `heard_received` / `response_received` /
`ipc_disconnected` und pflegt genau einen Einzel-Slot
(`Kind.NONE / HEARD / RESPONSE`). Jedes neue Event ersetzt Inhalt und
Kind deterministisch; Timer und Tween werden bei jedem Übergang
kill-and-replace behandelt (keine Mehrfach-Timer, keine Tween-Leichen).

**Bindende Grenzen.**

- **Ein Utterance.** Immer nur der letzte Inhalt ist sichtbar. Keine
  Historie, keine Scroll-Liste, keine Message-Collection.
- **Rein visuell.** Keine Interaktion, keine Buttons, keine Aktionen;
  `mouse_filter = MOUSE_FILTER_IGNORE` auf Bubble und Kind-Labels.
- **Kein Markdown/BBCode.** Inhalte landen in einem `Label`, nicht in
  `RichTextLabel` — eingehender Text wird nicht als Formatierung
  interpretiert. Das hält die Vertrauensoberfläche klein.
- **Defensives Text-Shaping.** `normalize_text` strippt Whitespace und
  kürzt auf `MAX_CHARS = 240` mit Unicode-Ellipsis. Keine
  Bildschirmwand, keine Log-artige Wall-of-Text.
- **Stummer Fallback.** Leerer Text und Whitespace-only-Text blenden
  die Bubble aus und setzen den internen Zustand auf `Kind.NONE` —
  kein Crash, keine halbsichtbare Leertafel.
- **Weicher TTS-Sync seit PR 14.** Der Kernpfad bleibt
  `heard`/`response` + `ipc_disconnected`. Zusätzlich verlängert ein
  eintreffendes `speaking_started` den Anzeige-Timer einmalig, wenn
  aktuell eine `response`-Bubble sichtbar ist (siehe §8.4a). Kein
  Phonem-/Lip-Sync, kein Audio-Stream-Pfad.
- **Keine Stage-C-/Appearance-Kopplung.** Die Bubble kennt weder
  Identity noch Theme; die Presence-Personalisierung aus §8b bleibt
  davon unberührt.
- **Keine IPC-/Protokolländerung.** Die EventBus-Signale selbst sind
  unverändert; der Controller ist reiner Konsument.

**Lifecycle.** Bubble startet unsichtbar (`modulate.a = 0.0`). Ein
belastbares `heard`/`response` startet einen Fade-in-Tween
(`FADE_IN_SECONDS = 0.12`) und einen Hide-Timer
(`DISPLAY_SECONDS_HEARD = 3.5`, `DISPLAY_SECONDS_RESPONSE = 6.0`).
Nach Timer-Ablauf fadet die Bubble aus (`FADE_OUT_SECONDS = 0.30`) und
räumt ihren Slot auf `Kind.NONE` zurück. Jedes neue Event während eines
laufenden Cycles ersetzt Text und Kind, killt den bestehenden Tween und
startet Timer + Fade neu. `ipc_disconnected` räumt sofort ohne Fade auf.

**Platzierung.** Die Bubble hängt als Direkt-Kind von `Main` neben dem
Avatar (`offset_left=130`, `offset_top=46`, `offset_right=460`,
`offset_bottom=150`, `z_index=45`). Sie liegt damit über dem Workflow-
Overlay (`z_index=40`) und unter Compact-Input (`z_index=50`), Avatar
(`z_index=100`) und Dev-Panel (`z_index=120`). Presence-Banner in der
VBox (Action / Approval / Discovery) können bei gleichzeitig aktiven
Flüssen sichtbar neben der Bubble liegen — das ist bewusst akzeptiert;
in der Praxis konkurrieren `heard`/`response` und aktive Desktop-Flows
selten um denselben Slot, und wenn doch, bleibt die Bubble durch ihre
kurze Standzeit schnell wieder still.

**Scope-Grenzen (nicht Teil dieses MVPs).** Kein Chat-Transcript,
kein Markdown-/BBCode-Renderer, keine Sprecherrollen-Konversation,
keine Dateianhänge, keine Bubble-Actions, keine Phonem-/Lip-Sync-
Animation, keine Audio-Timeline, keine Presence-Mode-abhängige
Zweitgröße. Das Event-Log (`RichTextLabel` im `DockPanel`) bleibt
unverändert als Entwickler-/Debug-Anzeige.

**Verifikation.** `scripts/utterance_bubble_smoke.gd` (52 Assertions,
alle PASS): pure Helfer (Kind-Namen, Chip-Labels, `has_content`,
`display_seconds_for`, `normalize_text` inkl. Truncation/Ellipsis und
Identitätsgrenzen bei exakt `MAX_CHARS`) plus Scene-Verhalten des
Controllers (`set_utterance`, `clear_utterance`, leere und
whitespace-only Eingaben, Response-ersetzt-Heard, wiederholte Updates
ohne Tween- oder Timer-Leichen, Long-Text-Ellipsis). Harness-Case:
`scripts/run_overlay_verification.sh utterance-bubble-smoke`.

### 8.4a Speech-Sync via TTS-Lebenszyklus-Events (PR 14, Ist-Zustand)

Konservativer MVP für den in der ROADMAP offenen Punkt
„Speech-Sync via TTS-Lebenszyklus-Events". Der Core meldet ab PR 14
`speaking_started` / `speaking_ended` (siehe
[`api.md` §2.11](./api.md)); die UI spiegelt diese Events an zwei
Stellen, ohne die bestehende State-Maschine umzubauen.

**Datei-Layout (Diff zu §8.4).**

```text
ui/autoload/
├── event_bus.gd        # zwei neue Signale: speaking_started_received /
│                       # speaking_ended_received
└── ipc_client.gd       # Routing `speaking_started` / `speaking_ended`
                        # → EventBus

ui/scripts/avatar/
└── avatar_controller.gd     # _on_speaking_started / _on_speaking_ended;
                             # neue TALK_SETTLE_SECONDS-Konstante

ui/scripts/utterance/
└── utterance_bubble_controller.gd  # weicher Sync: speaking_started
                                    # verlängert den Anzeige-Timer einer
                                    # aktiven `response`-Bubble
```

**Rolle des Avatars.** Der Avatar-Controller behandelt den Core-Pfad
jetzt als Taktgeber. Bisher war `response` → `TALKING` + fester
`TALK_HOLD_SECONDS`-Timer (1.8 s) der einzige Signalweg. PR 14 schaltet
zwei additive Übergänge daneben:

- `speaking_started` → `TALKING` und `_hold_timer.stop()`. Der
  Fallback-Timer läuft nicht mehr; der Avatar bleibt talking, solange
  der Core spricht. Wichtig: aus `ACTING` oder `ERROR` wird **nicht**
  hart in `TALKING` gewechselt — späte/verzögerte Lifecycle-Events
  überschreiben keinen laufenden Desktop-/Fehler-Cue.
- `speaking_ended` mit `ok=true` → kurzes `TALK_SETTLE_SECONDS`-Hold
  (0.35 s) und anschließend der normale Zurückfall auf `IDLE` bzw.
  `DISCONNECTED`. Mit `ok=false` geht der Controller über den
  bestehenden `ERROR`-Pfad (`ERROR_HOLD_SECONDS`).

Damit bleibt auch der Fallback tragfähig: schickt der Core keine
Lifecycle-Events (ältere Version, TTS-Kette leer), greift weiterhin
der alte `TALK_HOLD_SECONDS`-Pfad aus `_on_response`. Dieser Pfad
wird bewusst **nicht** entfernt — er ist die Resilienz gegen fehlende
Events (z. B. Verbindungsabbruch zwischen `started` und `ended`).

**Rolle der Utterance-Bubble.** Ein einziger weicher Sync-Hook:
kommt `speaking_started`, während gerade eine `response`-Bubble
sichtbar ist, wird der Hide-Timer einmal zurückgesetzt
(`DISPLAY_SECONDS_RESPONSE`). Der Nutzer liest die Antwort also
nicht weg, während Smolit sie noch spricht. Für `heard`-Bubbles und
einen leeren Zustand ist der Handler ein No-op —
`heard`-Bubbles markieren den STT-Moment, nicht die Sprechdauer, und
ein leerer Zustand darf nicht durch vagabundierende Events sichtbar
werden. `speaking_ended` ist auf dem Bubble-Pfad bewusst ein No-op:
der normale Display-Timer läuft zu Ende, damit das Sprechende
nicht hart abgeschnitten wird.

**Bindende Grenzen (konservative Schnittwahl).**

- **Kein Streaming-Audio, kein Lip-Sync.** Die Events sagen „jetzt
  läuft TTS" bzw. „TTS ist fertig" — nichts über den Audio-Puffer.
- **Keine neue globale State-Maschine.** Avatar-States und
  Bubble-Kinds bleiben identisch; die Lifecycle-Events sind nur
  zusätzliche Trigger.
- **Keine Stage-C-/Appearance-/Avatar-Asset-Arbeit.** Der Polish aus
  §8b.10 ist unverändert; der Sync füttert nur den bestehenden
  State-Pfad.
- **Keine Approval-/Interaction-/Desktop-Automation-Änderung.** PR 14
  berührt weder die Action-Event-Klammer noch den Approval-Flow.
- **Core bleibt Source of Truth.** Die UI entscheidet nicht, „ich tue
  mal so, als werde gesprochen". Wer die Events nicht sieht, zeigt
  keinen erzwungenen Talking-Avatar — der Fallback-Pfad greift
  konservativ.

**Verifikation.** Core-seitig prüfen die neuen Tests in
`core/src/ipc/server.rs` (vier `speak_text_*` / `auto_speak_*`-Tests)
und `core/src/ipc/protocol.rs` (Encoder-Roundtrips) das
Pairing-/Payload-Verhalten. UI-seitig prüft
`scripts/speech_sync_smoke.gd` (19 Assertions, alle PASS) die
EventBus-Signale, das `IpcClient`-Routing, die
Avatar-Controller-Handler auf Quelltext-Ebene sowie den weichen
Bubble-Sync auf Scene-Ebene. Harness-Case:
`scripts/run_overlay_verification.sh speech-sync-smoke`.

**Offene Restschuld.** Phonem-/Lip-Sync und Audio-Timeline sind
weiterhin in Phase C (§7) geparkt. Feinere Ausdrucksstufen wie
`curious`, `focused`, `pleased` sind mit PR 15 als **Behavioral
Expression Layer v1** gelandet (UI-only, siehe §8.4b) — sie ersetzen
weder den Lifecycle noch diese Scope-Grenze.

### 8.4b Behavioral Expression Layer v1 (PR 15, Ist-Zustand)

Erster kuratierter Schritt aus Phase 4 „Persönlichkeit / Ausdruck":
eine kleine UI-Schicht, die **oberhalb** der bestehenden Avatar-State-
Maschine lebt und sichtbares Verhalten feiner zeichnet, ohne dafür
neue Protokolle, Audio-Streams oder Assets zu brauchen.

**Datei-Layout.**

```text
ui/scripts/avatar/
├── avatar_expression.gd          # NEU: RefCounted-Modell
│                                 # (Enum, Multiplier, Tint,
│                                 # default_for_state)
└── avatar_controller.gd          # hängt Expression ein (Event-
                                  # Handler, Multiplier-Fold,
                                  # preview_expression)

ui/scripts/dev_controls/
└── dev_controls_controller.gd    # optionale Preview-Zeile
                                  # (`SMOLIT_UI_DEV_CONTROLS=1`)

scripts/
└── avatar_expression_smoke.gd    # NEU: Smoke für Modell + Wiring
```

**Sechs kuratierte Ausdrucksmodi.** Alle Werte sind bewusst subtil;
wer den Layer abschaltet (oder auf `neutral` stellt) sieht das
Rendering byte-identisch zum vor-PR-Verhalten:

| Ausdruck     | hold | Puls-Mult. | Wiggle-Mult. | Tint-Shift        |
|--------------|------|------------|--------------|-------------------|
| `neutral`    | 0.0  | 1.00       | 1.00         | identity          |
| `focused`    | 0.0  | 0.85       | 0.30         | leicht kühl       |
| `curious`    | 0.9  | 1.10       | 1.70         | leicht grünlich   |
| `speaking`   | 0.0  | 1.20       | 0.50         | leicht warm       |
| `pleased`    | 0.6  | 1.05       | 0.80         | leicht warm-gelb  |
| `error_soft` | 0.9  | 0.90       | 0.00         | leicht rötlich    |

`hold=0.0` bedeutet *sticky*: der Ausdruck bleibt, bis ein neuer Event
oder ein State-Wechsel ihn ablöst. `hold>0.0` markiert **transiente
Cues** — der Controller fährt nach Ablauf automatisch auf den
`default_for_state` zurück (siehe unten).

**Zuordnung State → Default-Expression.** `AvatarExpression.default_for_state`
bildet eine deterministische Pfeilstruktur:

| Avatar-State    | Default-Expression |
|-----------------|--------------------|
| `IDLE`          | `neutral`          |
| `THINKING`      | `focused`          |
| `TALKING`       | `speaking`         |
| `ACTING`        | `neutral`          |
| `ERROR`         | `error_soft`       |
| `DISCONNECTED`  | `neutral`          |

Ein zusätzlicher `connected`-Parameter dominiert: offline ist die
Expression immer `neutral`, selbst wenn der State später auf `ERROR`
oder `TALKING` geraten sollte (stilles Sleeping-Verhalten).

**Event-Mapping (aus `avatar_controller.gd`).**

- `thinking_received` → State `THINKING` → Default `focused`.
- `response_received` → State `TALKING` + **transienter** `pleased`-
  Cue (0.6 s). Folgt `speaking_started`, ersetzt es den Cue durch
  sticky `speaking`; bleibt es aus, fällt die Expression nach dem
  Hold auf den `TALKING`-Default (`speaking`) zurück und nach
  `TALK_HOLD_SECONDS` über den State-Default-Pfad auf `neutral`.
- `speaking_started` → State `TALKING` + sticky `speaking`. Der
  bestehende PR-14-Guard (kein Übernehmen aus `ACTING`/`ERROR`)
  bleibt bindend.
- `speaking_ended(ok=true)` → transienter `pleased`-Cue + Settle-Hold.
- `speaking_ended(ok=false)` → transienter `error_soft`-Cue +
  State-Wechsel auf `ERROR` (dort übernimmt der State-Default
  `error_soft` nahtlos).
- `heard_received` → transienter `curious`-Cue (0.9 s). Kein
  State-Wechsel.
- `ipc_disconnected` → State `DISCONNECTED` → Default `neutral`; ein
  noch laufender transienter Cue wird fallen gelassen.

**Visuelle Wirkung.** Der Layer greift ausschließlich über drei
multiplikative Faktoren:

- **Puls-Amplitude** (`_start_breath_tween`): Expression-Multiplier
  multipliziert sich mit dem Template-Capability-Multiplier. `speaking`
  hebt den Talking-Puls leicht an, `focused` dämpft den Thinking-Puls;
  `error_soft` dämpft den Rest.
- **Wiggle-Auslenkung** (`_play_wiggle`): gleiche Komposition. Eine
  Figur mit `wiggle = NONE` auf Template-Ebene bleibt in jeder
  Expression still — der Capability-Gate in `_arm_wiggle_timer`
  bleibt die primäre Bremse.
- **Tint-Shift** (`_apply_expression_tint`): multiplikativ auf die
  `_appearance_tint`-Ausgabe; zusätzlich mit dem `EXPR_THEME_TINT`-
  Multiplier des Templates gedämpft. Templates mit
  `theme_tint = NONE` sehen den Shift nicht.

Andere Render-Pfade (Rim-Accent, Tween-Timings, Texturen,
Disconnected-Tint, ACTING-Tint-Tabelle, Error-Startle) bleiben
bindend — der Layer modifiziert sie nicht, er kommentiert sie nur.

**Optional: Dev-Preview.** Bei `SMOLIT_UI_DEV_CONTROLS=1` ergänzt
`dev_controls_panel` eine Zeile mit sechs Buttons (einer pro
Expression). Klick → `avatar_controller.preview_expression(kind)`,
kein Auto-Save, keine Persistenz, keine Core-Kommunikation. Die
transiente Hold-Semantik bleibt aktiv — ein Preview von `pleased`
fällt nach 0.6 s automatisch auf den State-Default zurück, genauso
wie bei echten Events.

**Bindende Grenzen.**

- **Kein neues Protokoll.** Der Core weiß nichts vom Expression-Layer.
  Kein `emotion`-Feld, kein neues IPC-Event, kein neuer Core-Hook.
- **Keine neue State-Maschine.** Expressions sind ein Multiplier-
  Patch, nicht die Wahrheit. Avatar-State bleibt Source für
  idle/thinking/talking/acting/error/disconnected.
- **Kein Streaming-Audio, kein Phonem-/Lip-Sync.** Der Layer
  konsumiert weiterhin nur den binären TTS-Lifecycle aus PR 14
  (`speaking_started` / `speaking_ended`) — keine Audio-Bytes, keine
  Timeline, keine Mundform-Simulation.
- **Keine Asset-Imports, keine User-Uploads.** Ausschließlich
  prozedurale Parameter auf existierenden Nodes. Phase C bleibt
  geparkt.
- **Template-Capability bleibt bindend.** Expressions dürfen nicht
  an der Kapazitätsgrenze vorbei. `orb.wiggle = NONE` ist auch in
  `curious` still; `theme_tint = NONE` filtert auch den Expression-
  Tint.
- **Keine Personality-/Policy-Verwechslung.** Der Layer weiß nichts
  über Approval, Interaction, Provider oder Settings. Er reagiert
  rein auf bestehende Presence-Events.

**Verifikation.** `scripts/avatar_expression_smoke.gd` (Harness-Case
`avatar-expression-smoke`) prüft das Modell (Enum, Namen, Parser,
Multiplier-Schranken, Tint-Shift-Schranken, sticky-vs-transient-
Klassifizierung, `default_for_state` inkl. `connected`-Dominanz)
und das Controller-Wiring über Quelltext-Assertions (Multiplier-
Fold in Puls-/Wiggle-/Tint-Pfad, Existenz der Event-Handler, PR-14-
Guard intakt, Template-Capability-Gates bleiben bindend). Scene-
Spawn-Tests entfallen, weil der Headless-`--script`-Modus die
`EventBus`-/`IpcClient`-Autoloads nicht registriert — die echte
Laufzeit-Integration läuft beim regulären Start der Main-Scene.

**Offene Restschuld (nicht Teil von PR 15).**

- **Phase C Deep-Expression** — Phonem-/Lip-Sync, Audio-Timeline,
  feinere Tempo-Achsen, Emotion-Mapping aus ABrain-Responses. Diese
  Pfade würden ein neues Protokoll und/oder Streaming-Audio brauchen
  und sind ausdrücklich ausgeklammert.
- **Persistenz des Expression-Defaults.** Heute kommen Expressions
  ausschließlich aus Events; es gibt keinen gespeicherten User-
  Default. Falls Bedarf entsteht, wäre das eine eigene kleine
  Preferences-Linie — nicht Teil von PR 15.
- **Emission aus dem Core.** Der Core sendet weiterhin keine
  Expressions und nimmt keine entgegen. PR 15 ist UI-only.

### 8.4c Workflow Visibility Overlay v1 (PR 16, Ist-Zustand)

Kleiner, ehrlicher MVP für „Smolit zeigt, was er gerade tut": ein
read-only Panel neben dem Avatar, das die bestehenden UI-Events in
eine lineare Kette sichtbarer Workflow-Schritte projiziert. Keine
neue Protokoll-Ebene, keine Historie, kein Editor.

**Datei-Layout.**

```text
ui/scripts/workflow/
├── workflow_visibility_model.gd    # NEU: pure RefCounted-Projektion
│                                   # (Enums, Snippet-Kürzung, Event-
│                                   # → Step-Mapping)
└── workflow_visibility_panel.gd    # NEU: Panel-Controller

ui/scenes/workflow/
└── workflow_visibility_panel.tscn  # NEU: PanelContainer-Root,
                                    # default visible=false

ui/scripts/dev_controls/
└── dev_controls_controller.gd      # Toggle im bestehenden Dev-Panel

scripts/
└── workflow_visibility_smoke.gd    # NEU: Smoke für Modell + Panel
```

**Rolle.** Rein rendernd, EventBus-getrieben. Der Panel-Controller
abonniert `heard_received`, `thinking_received`, `response_received`,
`action_planned_received`, `action_started_received`,
`action_step_received`, `action_completed_received`,
`action_failed_received`, `action_cancelled_received`,
`speaking_started_received`, `speaking_ended_received` und
`ipc_disconnected`. Das Modell upserted pro Kategorie genau einen
Schritt; der Renderer zeichnet die Kette als kurze vertikale
Kartenliste mit Status-Badge (`·` pending, `▶` active, `✓` done,
`✕` failed, `—` skipped) und tintedem Kind-Label.

**Acht kuratierte Schritt-Kategorien.**

| Kind        | Quelle / Auslöser                                                        |
|-------------|--------------------------------------------------------------------------|
| `heard`     | `heard_received` (STT-Ergebnis, nur im `voice_once`-Flow).               |
| `thinking`  | `thinking_received` (ABrain-Anfrage läuft).                              |
| `response`  | `response_received` (ABrain-Text; schließt `thinking` auf `done`).       |
| `action`    | `action_planned_received` bzw. `action_started_received`.                |
| `step`      | `action_step_received`; mehrere Events erhöhen `step_count`.             |
| `speaking`  | `speaking_started_received` / `speaking_ended_received` (PR 14).         |
| `completed` | `action_completed_received` (Terminal-Zustand, DONE).                    |
| `failed`    | `action_failed_received` / `action_cancelled_received` (Terminal, FAIL). |

Jede Karte trägt `kind`, `label`, `status`, optional `snippet`,
optional `action_id` und einen `timestamp_ms`. Snippets werden im
Modell hart auf `MAX_SNIPPET_CHARS = 60` gekürzt und mit `…`
abgeschlossen — das Overlay ist keine Transcript-Wand.

**Workflow-Lifecycle.**

- Leerer Start. Ein erstes relevantes Event (`heard`, `thinking`,
  `response`, `action_planned`, `speaking_started`) beginnt einen
  Workflow.
- Nach einem Terminal-Event (`completed` / `failed`) startet das
  nächste nicht-terminale Event einen **neuen** Workflow — kein
  Anhäufen von Zuständen.
- `action_planned` mit abweichender `action_id` resettet die Kette
  ebenfalls.
- `ipc_disconnected` kippt offene `active`-Schritte auf `skipped`,
  setzt `offline=true` und markiert den Workflow **nicht** als
  terminal — ein Reconnect rendert sofort wieder frische Events.

**Resilienz.**

- Unbekannte Event-Reihenfolgen (z. B. ein `action_step` ohne
  vorheriges `action_planned`, ein verwaistes `speaking_ended`)
  werden toleriert; das Modell fügt den Step ein, ohne zu crashen.
- Fehlende Payload-Felder werden durch neutrale Defaults ersetzt
  (leeres Snippet, leere `action_id`).
- Ein älterer Core ohne `speaking_started` / `speaking_ended` bleibt
  voll lesbar: der Workflow schließt über `response` +
  `action_completed` sauber ab.
- Zu lange User-/Response-Texte werden hart gekürzt — das MVP soll
  Kontext zeigen, nicht Inhalt ausliefern.

**Sichtbarkeit / Toggle.**

- Standardmäßig **hidden**. Opt-in per Env `SMOLIT_WORKFLOW_OVERLAY=1`
  (gleiches Muster wie `SMOLIT_UI_OVERLAY` / `SMOLIT_UI_DEV_CONTROLS`).
- Bei aktivem `SMOLIT_UI_DEV_CONTROLS=1` ergänzt das Dev-Panel eine
  Toggle-Checkbox. Der Toggle ist **session-only** — kein Auto-Save,
  keine Persistenz.
- Auch im hidden-Modus laufen die Event-Handler weiter; das Modell
  bleibt aktuell, damit ein späteres Sichtbar-Machen direkt die
  laufende Interaktion rendert.

**Bindende Grenzen (Scope-Kuratierung).**

- **Kein neuer IPC-Event, kein Emotion-Kanal.** Der Core sendet und
  empfängt nichts Neues wegen PR 16.
- **Kein Editor, kein n8n-Ersatz.** Keine Drag/Drop-Knoten, keine
  editierbaren Steps, keine Graph-DSL, keine Action-Trigger aus
  dem Overlay heraus.
- **Keine Historie, kein Export, kein Speichern.** Nur die aktuelle
  Interaktion lebt im Modell; ein neuer Workflow überschreibt.
- **Keine langen Inhalte.** Snippets ≤ 60 Zeichen inklusive Ellipsis;
  vertrauliche Texte gehören nicht ins Overlay.
- **Keine Eingabe, kein Klick-Fang.** Panel und sämtliche Labels
  laufen auf `MOUSE_FILTER_IGNORE` — Avatar und Compact-Input
  bleiben ungehindert erreichbar.
- **Kein Desktop-Automation-Pfad, kein Approval-Hook.** Der Layer
  beeinflusst weder Policy, Interaction noch Provider-Wahl.
- **Keine zweite State-Wahrheit.** Avatar-State, Bubble-Kind und
  Action-Event-Stream bleiben autoritativ; das Panel ist
  Zusatzprojektion.

**Verifikation.** `scripts/workflow_visibility_smoke.gd` (Harness-
Case `workflow-visibility-smoke`) prüft Enum-Helfer, Snippet-
Kürzung, happy-path-Kette für Voice- und `speak_text`-Flows,
`speaking_ended(!ok)` → FAILED, `action_failed` → Terminal,
Reset bei neuer `action_id`, Disconnect-Pfad (active → skipped),
Resilienz gegen unbekannte Reihenfolgen, Snippet-Trimming am
Response-Text, Default-hidden des Panels, Toggle-Roundtrip und
`reset_for_tests`. Scene-Spawn läuft im Headless-`--script`-Modus
ohne EventBus-Autoload — die echte EventBus-Integration wird beim
regulären Start der Main-Scene geprüft.

**Offene Restschuld (nicht Teil von PR 16).**

- **Tieferer Detail-Layer.** Zeitleiste, Dauer-Balken pro Step,
  Tooltip mit vollem Action-Payload. Das würde das Panel zu einem
  Debug-Tool ausbauen — bewusst außerhalb MVP.
- **Parallele Workflows / Warteschlangen.** Das Modell hält genau
  einen aktuellen Workflow; mehrere parallele Aktionen wären eine
  eigene Design-Entscheidung.
- **Export / Persistenz.** Kein Speichern, kein Teilen. Falls das
  kommen soll, braucht es ein eigenes Produkt-Konzept (welche
  Daten, welche Vertraulichkeit, welche Speicherform).
- **Core-Emission von Workflow-Zuständen.** Das Panel projiziert
  bestehende Events. Ein zukünftiges „workflow_snapshot"-Envelope
  vom Core wäre eine additive Protokoll-Erweiterung — PR 16 führt
  bewusst keines ein.

### 8.4d Approval UX v1 — Card + Integrationen (PR 17, Ist-Zustand)

Leitprinzip: **Control > Autonomy.** Smolit darf geplante Aktionen
erklären und um Zustimmung bitten; PR 17 führt **keine gefährlichen
Aktionen** ein. Die Schicht bündelt drei ehrliche Bausteine:
eine neue Approval-Card-UI, eine additive Erweiterung des Workflow-
Visibility-Overlays aus §8.4c und einen weichen Avatar-Expression-
Hook aus §8.4b. Der Core bekommt ein additives `risk`-Feld und
einen **harmlosen Demo-Pfad**, damit die UX evaluiert werden kann,
ohne Desktop-Automation oder andere gefährliche Seiteneffekte zu
triggern.

**Datei-Layout.**

```text
core/src/approvals/request.rs        # + `risk` (ApprovalRequest)
                                     # + `source` (ApprovalResolvedPayload)
                                     # + sanitize_risk/KNOWN_RISKS
core/src/ipc/protocol.rs             # + approval_approve / approval_deny
                                     # + request_approval_demo (incoming)
core/src/app.rs                      # + request_approval_demo (no-op
                                     #   after resolve; no backend action)

ui/scripts/approval/
├── approval_model.gd                # NEU: Risk-Sanitizer, Summary-Trim,
│                                    #      Decision-Outcome-Mapping
└── approval_card.gd                 # NEU: Scene-Controller

ui/scenes/approval/
└── approval_card.tscn               # NEU: PanelContainer-Root

ui/autoload/ipc_client.gd            # + approval_approve / approval_deny
                                     # + request_approval_demo Helfer

ui/scripts/workflow/workflow_visibility_model.gd
                                     # + StepKind.APPROVAL
                                     # + apply_approval_requested/resolved

ui/scripts/avatar/avatar_controller.gd
                                     # + weicher Expression-Hook

ui/scripts/dev_controls/dev_controls_controller.gd
                                     # + drei harmlose Demo-Auslöser
                                     #   (low / medium / high)

scripts/
└── approval_card_smoke.gd           # NEU: Smoke für Card + Model
```

**Approval-Card.** Ein schmaler `PanelContainer`, der genau einen
offenen Approval anzeigt:

- **Header** — kurzer `title` (gekürzt auf `MAX_TITLE_CHARS = 80`) plus
  ein kleiner `risk`-Badge mit stabiler Farbtabelle
  (`low` = grünlich, `medium` = gelblich, `high` = rötlich).
- **Summary** — kurze `message` des Core, gekürzt auf
  `MAX_SUMMARY_CHARS = 140` mit Ellipsis. **Keine** langen
  Full-Payloads; sensible Inhalte sollen nicht in die UX leaken.
- **Buttons** — zwei nebeneinander: `Approve` und `Deny`. Klick
  sendet direkt `approval_approve` bzw. `approval_deny` (fallback auf
  den älteren kombinierten Command `approval_response`).

Nach einem Klick geht die Card in einen **Resolving-Zustand**: beide
Buttons sind deaktiviert, der Status zeigt „waiting for core…". Das
Pairing wird durch das Core-seitige `approval_resolved` abgeschlossen;
der Status wird kurz finalisiert (`resolved: approved (user)`) und
der Slot geleert. Doppelte Klicks sind durch den Core-Registry-Pfad
idempotent gesichert: ein zweiter `approve`/`deny` landet als
`error`-Frame, nicht als zweites `approval_resolved`.

**Ist die Card klickfähig?** Die Card selbst läuft auf
`MOUSE_FILTER_PASS`; Klicks auf die Buttons werden entgegengenommen,
der übrige Bereich leitet Klicks weiter. Bei `ipc_disconnected`
werden beide Buttons disabled und der Status zeigt
„offline — buttons disabled"; die Card versteckt sich nicht hart,
damit ein nachträglich eintreffendes `approval_resolved` mit
`source: timeout` sauber in der Historie-Zeile landen kann.

**Integration in das Workflow Visibility Overlay (§8.4c).** Ein neuer
Step-Kind **`APPROVAL`** kommt zu den acht bestehenden hinzu. Der
Workflow-Step wird bei `approval_requested` auf `ACTIVE` gesetzt
(Snippet: `[risk] title`) und bei `approval_resolved` je nach
Decision-Outcome umgemappt:

| decision    | Workflow-Status                      |
|-------------|--------------------------------------|
| `approved`  | `DONE`                               |
| `denied`    | `FAILED`                             |
| `cancelled` | `FAILED`                             |
| `timed_out` | `SKIPPED`                            |
| `expired`   | `SKIPPED`                            |
| unbekannt   | `SKIPPED` (defensiv, kein DONE-Leak) |

Der APPROVAL-Step bleibt in der linearen Kette sichtbar — kein
eigenes Historien-System, kein Export.

**Avatar-Expression-Hook (§8.4b).** Sehr weich: `approval_requested`
zieht den Ausdruck auf `curious` (transient), sofern wir gerade
nicht in `ACTING` oder `ERROR` sind. `approval_resolved` mit
`denied` / `cancelled` / `timed_out` / `expired` kippt auf
`error_soft` (transient). `approved` ist bewusst stumm — eine
reguläre `action_*`-Kette übernimmt meist die Expression danach.
Die PR-14- und PR-15-Guards bleiben intakt: keine Überschreibung
von ACTING/ERROR, keine neue State-Maschine.

**Demo-Auslöser in Dev-Controls.** Drei kleine Buttons im bereits
env-gateten Dev-Panel (`SMOLIT_UI_DEV_CONTROLS=1`) — einer pro
Risikostufe. Klick → IpcClient sendet `request_approval_demo` mit
festen, harmlosen Default-Texten. Der Core issued ein
`approval_requested`, startet den üblichen Timeout-Watchdog und
resolvet nach Approve/Deny mit **keiner** weiteren Aktion. Kein
`action_cancelled` folgt; es gibt keine zweite Action-Kette.

**Harte Grenzen (Scope-Kuratierung).**

- **Keine gefährlichen Aktionen.** PR 17 führt **keinen** Tool-
  Gating-Pfad aus, keine echte Desktop-Automation, keinen Shell-
  Call, keinen AdminBot. Der Demo-Pfad ist bewusst ein No-Op.
- **Keine neuen Sicherheitsgarantien.** Der Loopback-WebSocket
  bleibt Vertrauensgrenze wie in §2.7; PR 17 verändert die
  Approval-Engine nicht, sondern baut nur UX drumherum.
- **Keine sensiblen Full-Payloads in der UI.** Summary ist auf
  140 Zeichen hart gekürzt; Titel auf 80. Fremde Strings werden
  sanitisiert (`risk`) bzw. defensiv gerendert.
- **Keine Persistenz, keine Approval-Historie.** Ein Card-Slot
  lebt, solange der Core kein `approval_resolved` geschickt hat.
  Kein Export, kein Speichern.
- **Keine Provider-/Settings-/Approval-Policy-Änderung.** Der
  bestehende Interaction-Approval-Flow aus §2.7 bleibt unverändert;
  die Card und die Banner-UI (ApprovalBanner in `main.tscn`) laufen
  parallel — beide sehen dasselbe `approval_requested`.
- **Keine Umbenennung existierender Envelopes.** `approval_response`
  bleibt gültig. `approval_approve` / `approval_deny` sind rein
  additive, schmale Commands für UI-Code-Stil-Präferenzen.
- **Idempotente Resolution bleibt bindend.** Ein zweiter approve/
  deny am gleichen `approval_id` kommt als `error`-Frame zurück,
  niemals als zweites `approval_resolved`.

**Verifikation.**

- Core: `cargo test` deckt `sanitize_risk`, die neuen Protokoll-
  Encoder/Decoder und den Demo-Flow ab (Approve/Deny mit
  `source: user`, keine Folgeevents, doppelter Approve = Error,
  Risk-Sanitization). Der bestehende Interaction-Approval-Flow
  bleibt grün (`interaction_approval_request_carries_risk_medium_by_default`).
- UI: `scripts/approval_card_smoke.gd` (Harness-Case
  `approval-card-smoke`) prüft pure `SmolitApprovalModel`-Logik
  und das Card-Scene-Verhalten (Default-hidden, Render bei
  `approval_requested`, Resolving-Flow mit Idempotenz,
  Mismatched-ID-Ignore, Disconnect-Pfad, Missing-Fields,
  `reset_for_tests`). `scripts/workflow_visibility_smoke.gd` wurde
  um `APPROVAL`-Step-Mapping erweitert.

**Offene Restschuld (nicht Teil von PR 17).**

- **Echtes Tool-Gating.** Ein Policy-Layer, der ausgewählte
  Core-Aktionen automatisch durch den Approval-Pfad zwingt, bleibt
  Folgearbeit — PR 17 bietet nur die UX dafür.
- **Feinere Risk-Achse.** Heute sind nur drei Stufen kuratiert;
  ein „unknown risk" wird defensiv auf `medium` gemappt. Eine
  feinere Skala (Risiko-Score, Begründung) kann additiv folgen.
- **Persistenz / Audit-Trail.** Kein „remember this choice", kein
  Log ins Dateisystem. Ein späterer Audit-Log-Pfad wäre eine
  eigene Design-Entscheidung.
- **Multi-Seat / Multi-Window.** Die UX nimmt weiterhin genau einen
  entscheidenden UI-Client an.

### 8.4e Approval-Gated Action Planner v1 (PR 18, Ist-Zustand)

Konsequenter Folgeschritt zu PR 17: eine geplante Aktion darf erst
ausgeführt werden, wenn ihre Approval-Bedingung erfüllt ist. PR 18
liefert ausdrücklich **nur** einen harmlosen Mock-Pfad — es ist
keine echte Tool-, Shell-, Desktop- oder Provider-Verdrahtung.

**Zusammenspiel Core ↔ UI.**

- **Core** (`core/src/actions/plan.rs` + `App::plan_demo_action`)
  erzeugt einen [`DemoPlan`](../core/src/actions/plan.rs) mit
  sanitisiertem Titel (≤ 80), Summary (≤ 140), Kind (`demo_echo` /
  `demo_wait` / `noop`; unbekannt → `noop`) und Risk (`low` /
  `medium` / `high`; unbekannt → `medium`). `action_planned` geht
  immer raus; bei `requires_approval=true` folgt ein
  `approval_requested`, der Executor blockiert bis zum
  `approval_approve`/`approval_deny`/Timeout. Ein Mock-Executor
  emittiert `action_started → action_step → action_completed`
  **nur** bei `approved`; bei Deny/Cancel/Expire kommt
  `action_cancelled` mit sprechender `message`. Kein Seiteneffekt.
- **Approval-Card (§8.4d)** rendert plan-getriggerte
  `approval_requested`-Frames unverändert. Unterschied zur
  PR-17-Demo-Approval: `action_id` ist jetzt gesetzt (nicht leer).
  Die Card bleibt action_id-agnostisch und räumt ihren Slot nach
  `approval_resolved` auf.
- **Workflow Visibility Overlay (§8.4c)** spiegelt die Gating-
  Kette: `ACTION` (von `action_planned`) → `APPROVAL` (von
  `approval_requested`) → nach `approved`: `APPROVAL` DONE + `STEP`
  active + `COMPLETED` DONE; nach `denied`/`cancelled`: `APPROVAL`
  FAILED + `ACTION` FAILED (durch nachfolgendes `action_cancelled`).
  Bei `timed_out`: `APPROVAL` SKIPPED plus `ACTION` FAILED.
- **Avatar-Expression (§8.4b)** reagiert weich wie bei jedem
  Approval: `curious` bei Request, `error_soft` bei Deny/Cancel/
  Timeout. PR-14-Guards gelten unverändert.

**Neue Dev-Control-Zeile.** Bei `SMOLIT_UI_DEV_CONTROLS=1` erscheinen
zwei Buttons neben der Approval-Demo-Zeile aus PR 17:

- **Run (no approval)** — sendet `plan_demo_action` mit
  `requires_approval=false`. Der Mock läuft inline durch
  (`planned → started → step → completed`).
- **Run (needs approval)** — sendet `plan_demo_action` mit
  `requires_approval=true`. Die Approval-Card erscheint, der
  Executor wartet.

Beide Buttons verwenden feste, harmlose Default-Texte; kein
Auto-Save, keine Persistenz. Fehlt der IPC-Client-Hook (älterer
Build), bleiben die Zeilen stumm.

**Bindende Grenzen.**

- **Keine echten Aktionen.** Der Mock-Executor emittiert genau die
  Event-Klammer. Kein Shell, kein Dateisystem, kein Desktop-
  Automation-Call, keine Provider-Mutation, kein AdminBot.
- **Keine neue Approval-Semantik.** Deny, Cancel, Timeout gehen
  durch die bestehende [`PendingApprovalRegistry`](../core/src/approvals/state.rs)
  aus PR 17; Idempotenz ist dort enforced.
- **Kein Persistenz-/Historien-Pfad.** Plans leben nur bis zu
  ihrem Terminal-Event.
- **Keine Policy-Engine.** Der Caller entscheidet per
  `requires_approval`-Flag; der Core interpretiert das nicht
  intelligent. Ein echtes Tool-Gating bleibt Folgearbeit.
- **Keine neuen Action-Typen.** PR 18 nutzt `ActionKind::System`
  für alle Demo-Plans — keine neue Protokoll-Kategorie.

**Offene Restschuld (nicht Teil von PR 18).**

- **Tool-Gating-Verdrahtung.** Eine reale Policy, die Provider-/
  Interaction-/Settings-Pfade durch den Approval-Pfad zwingt, ist
  ausdrücklich Folgearbeit. PR 18 zeigt das Muster, nicht die
  Integration.
- **Weitere Demo-Kinds.** `demo_echo` / `demo_wait` / `noop` sind
  ein kuratiertes Minimum. Eine Erweiterung müsste ihre
  Seiteneffekt-Freiheit selbst garantieren.
- **Persistenz / Audit-Log.** Die Audit-Linie landet mit PR 19
  (siehe §8.4f); Persistenz bleibt weiter offen.

### 8.4f Local Audit Trail v1 — Dev-Only View (PR 19, Ist-Zustand)

*Accountability without surveillance.* PR 19 ergänzt eine **kleine,
lokale, in-memory** Audit-Schicht oberhalb des
Approval-Gated-Demo-Pfads aus PR 18. Der Store erfasst Lifecycle-
Ereignisse und ein paar IPC-Grenzfälle als redacted
`AuditEvent`s; eine schmale, Dev-only UI macht sie sichtbar. Kein
Produkt-Feature, keine Persistenz, kein Export.

**Datei-Layout.**

```text
core/src/audit/
├── event.rs                      # AuditEvent, AuditFields, Sanitizer
├── store.rs                      # AuditStore (Ring-Buffer)
└── mod.rs                        # Re-Exports

ui/scripts/audit/
├── audit_model.gd                # Pure UI-Formatter (Kind-Labels,
│                                 # Color-Tabelle, short_id/summary/time)
└── audit_panel.gd                # Dev-only Panel-Controller

ui/scenes/audit/
└── audit_panel.tscn              # default visible=false

scripts/
└── audit_panel_smoke.gd          # Smoke für Modell + Panel
```

**Core.** `AuditStore` ist ein thread-safer Ring-Buffer über
`VecDeque<AuditEvent>`. Default 100 Einträge, hartes Maximum 1000
(`SMOLIT_AUDIT_MAX_EVENTS` klemmt hinein). Neue Einträge evictieren
den ältesten. Jeder Eintrag trägt:

- `audit_id` (`aud_NNNNNN`), `timestamp_ms` (Unix epoch ms),
- eine der neun `AuditKind`-Kategorien,
- optional `action_id`, `approval_id`, `risk`, `result`, `source`,
- eine **hart gekürzte** `summary` (≤ 80 Zeichen).

`source` und `result` werden gegen fest kuratierte Whitelists
geprüft; unbekannte Werte fallen auf `None`, damit sie nicht
serialisiert werden. `risk` nutzt die Whitelist aus PR 17 /
[`crate::approvals`](../core/src/approvals/request.rs).
`App::plan_demo_action` und der Executor aus PR 18 rufen den Store
an sechs Stellen (IPC-Received, Planned, Approval-Requested,
Approval-Resolved, Action-Started, Action-Completed/Cancelled).
`handle_approval_response` zeichnet außerdem einen
`ipc_command_rejected`-Eintrag, wenn ein Approve/Deny auf eine
unbekannte oder bereits aufgelöste `approval_id` trifft — so wird
die Idempotenz-Garantie aus PR 18 auditiv sichtbar.

**Wire-Form.** Ein neuer read-only Command `audit_recent { limit? }`
antwortet mit `audit_recent { payload: { events: [...] } }` (siehe
[`docs/api.md` §2.7](./api.md)). Kein Schreib-Pfad, kein Clear-
Command, kein Export.

**UI.** Das `AuditPanel` rendert pro Event eine schmale Zeile:

- Uhrzeit (`HH:MM:SS`) — nur informativ, keine Zeitzone, kein Datum.
- Kind-Kurzlabel (`planned`, `apr req`, `apr res`, `started`,
  `done`, `cancel`, `cmd rej`, …), farblich gemäß `result`.
- Optional ein Risk-Badge, gekürzte ID (`aud_00001…`), und ein
  Summary (weitere visuelle Kürzung auf 60 Zeichen, die hartem
  Kürzen durch den Core vorgeschoben ist).

Sichtbarkeit: **standardmäßig hidden**. Nur bei
`SMOLIT_UI_DEV_CONTROLS=1` sichtbar geschaltet. Ein „Refresh"-
Button sendet einen `audit_recent`-Request; es gibt **keinen**
Auto-Refresh. `ipc_disconnected` deaktiviert den Button-Text
visuell, ohne die bestehende Liste hart zu löschen.

**Bindende Grenzen (Scope-Kuratierung).**

- **Keine Persistenz.** Weder Datei, noch DB, noch Cloud-Upload.
- **Keine Export-Funktion.** Kein `audit_save`, kein Copy-to-
  Clipboard.
- **Keine vollständigen User-Prompts / Response-Texte.** Summaries
  sind ≤ 80 Zeichen; der Core übergibt dem Store keine langen
  Inhalte.
- **Keine Audio-Bytes, keine Transkripte.** Der TTS-Lifecycle aus
  PR 14 hat bereits keinen Text im Event; PR 19 erweitert das
  nicht.
- **Keine Approval-Historie als Produktfeature.** Die UI zeigt
  nur den aktuellen Ring-Inhalt — keine Suche, keine Filterung.
- **Keine kryptografische Signatur.** Der Store ist weder
  manipulationssicher noch authentifiziert. Wer den Core-Prozess
  kompromittiert, kann Einträge frei manipulieren.
- **Keine Policy-Engine.** Der Store beobachtet, entscheidet aber
  nichts.
- **Read-only IPC-Oberfläche.** Nur `audit_recent`; kein
  `audit_clear`, kein `audit_save`, kein Schreib-Pfad.

**Verifikation.**
[`scripts/audit_panel_smoke.gd`](../scripts/audit_panel_smoke.gd)
(Harness-Case `audit-panel-smoke`) prüft pure Model-Helfer
(Kind-Labels, Color-Tabelle, defensive Payload-Lesung, Short-ID/
Summary/Time) plus das Panel (default hidden, Render einer
gesetzten Liste, Toleranz bei fehlenden Feldern, Toggle,
`reset_for_tests`). Core-Tests (`cargo test`) decken Event-
Sanitisierung, Ring-Buffer-Verhalten (Eviction, Limit-Clamp,
`clear_for_tests`), die volle Plan-Lifecycle-Kette (ohne/mit
Approval, Deny, Doppel-Approve) und den IPC-Roundtrip ab.

**Offene Restschuld (nicht Teil von PR 19).**

- **Persistenz.** Falls ein späteres PR Persistenz braucht, gelten
  die in [`docs/security/AUDIT_TRAIL.md`](./security/AUDIT_TRAIL.md)
  formulierten Leitplanken (opt-in, verschlüsselt, rotiert).
- **Filter / Suche / Export.** Nicht in PR 19. Jede Erweiterung
  erhöht die Surveillance-Oberfläche und muss eine eigene
  Produkt-Entscheidung rechtfertigen.
- **Manipulationssicherheit.** PR 19 liefert keine Tamper-
  Detektion. Ein zukünftiger `audit_chain`-Pfad (hash-linked
  entries) wäre eine eigene Design-Entscheidung.
- **Workflow-Overlay-Integration.** Das Overlay bleibt passiv.
  Audit-Einträge erscheinen nicht als Workflow-Step.

### 8.5 Visual Action Mode (UI-Staging MVP, Phase 3.3, Ist-Zustand)

Kleine, ehrliche MVP-Umsetzung der UI-Staging-Achse aus
[`docs/presence_desktop_interaction.md` §9](./presence_desktop_interaction.md).
**Kein** Feature-Bau Richtung echter Avatar-Bahn über Fremdfenster,
**kein** Desktop-Targeting, **keine** IPC-/Core-Änderung. Der Modus
moduliert rein innerhalb der Presence-Hülle, **wie laut** bestehende
Action Events im UI auftreten. Die vier Produktnamen (`none` /
`minimal_feedback` / `guided_movement` / `full_theatrical`) bleiben
erhalten, werden aber in diesem Schritt bewusst als **UI-Intensitäts-
Achse** interpretiert — nicht als Choreografie oder Bewegungspfad.

**Datei-Layout.**

```text
ui/scripts/presence/
├── presence_controller.gd           # (unverändert)
├── presence_state.gd                # (unverändert)
├── visual_action_mode.gd            # NEU: Enum + Parser + Staging
└── visual_action_preferences.gd     # NEU: lokale UI-Persistenz
```

**Rolle.** Rein deklarativ: pure statische Helfer, keine Scene, kein
Tween, keine Event-Subscription. Der Main-Controller löst den Mode in
`_ready()` einmalig über die Kette `Env > Preferences > Default` auf
und pusht das Staging auf zwei existierende UI-Bausteine:

- **Action-Banner (`$VBox/ActionBanner`).** Das Banner wird in
  `none` unabhängig vom laufenden Action-State **unsichtbar** gehalten.
  In den anderen drei Modi moduliert `banner_alpha` nur die Deckkraft
  — Inhalte (Titel, Step, Target, Status) bleiben unverändert. Die
  Kette ist monoton: `NONE < MINIMAL < GUIDED < FULL`.
- **Workflow-Overlay (`$WorkflowOverlay`).** Der Overlay-Controller
  bekommt ein externes Gate (`set_external_enabled`) und einen
  externen Alpha-Multiplikator (`set_external_alpha`). Im Mode
  `none` / `minimal_feedback` bleibt das Overlay **unabhängig von
  seinem Flow-Status** versteckt — das Flow-Modell selbst läuft
  weiter, es wird nur nicht gerendert. In `guided_movement` /
  `full_theatrical` wird das Overlay freigegeben, mit einer
  zusätzlichen Alpha-Abschwächung im Guided-Modus.

**Staging-Tabelle (Ist-MVP):**

| Mode              | `banner_visible` | `banner_alpha` | `workflow_overlay_allowed` | `workflow_overlay_alpha` |
|-------------------|------------------|----------------|----------------------------|--------------------------|
| `none`            | false            | 0.00           | false                      | 0.00                     |
| `minimal_feedback`| true             | 0.75           | false                      | 0.00                     |
| `guided_movement` | true             | 0.92           | true                       | 0.80                     |
| `full_theatrical` | true             | 1.00           | true                       | 1.00                     |

**MVP-Interpretation der Produktachse (bindend für diesen Zyklus).**

- `none` — Action-Inszenierung aus: Banner und Workflow-Overlay bleiben
  während aktiver Actions versteckt; der Avatar zeigt den Acting-State
  weiter über den bestehenden Rim-Accent und die State-Tween-Kette.
- `minimal_feedback` — Banner-orientiert, dezent (Alpha ≈ 0.75);
  Workflow-Overlay ruhend (versteckt, aber betriebsbereit).
- `guided_movement` — Banner klar lesbar (Alpha ≈ 0.92), Workflow-
  Overlay sichtbar mit leichter Alpha-Absenkung. Weiterhin **keine**
  Ziel-Koordinaten, **keine** Bildschirmwanderung, **keine** echte
  Bewegungsbahn — der Name bleibt bewusst, weil wir die Produktachse
  nicht umbenennen wollen, der heutige UI-Stand liefert aber nur eine
  stärkere In-Place-Inszenierung.
- `full_theatrical` — stärkste heute ehrlich darstellbare UI-
  Intensität innerhalb der Presence-Hülle (Banner 1.00, Overlay 1.00).
  Keine neue Plattformfähigkeit, kein Avatar-Pfad über fremde Fenster.

Die endgültige Vollausprägung aus §7.3 / §7.4 der Presence-Doku
(Avatar zeigt Zielobjekt, Bewegungspfad, Gestik, Reaktion) bleibt
ausdrücklich **offen**; dieser MVP implementiert sie nicht vor.

**Eingabepfade (Env > Preferences > Default).**

1. **Env.** `SMOLIT_UI_VISUAL_ACTION_MODE` akzeptiert kanonische
   Namen (`none` / `minimal_feedback` / `guided_movement` /
   `full_theatrical`) und kurze Aliasse (`off` / `min` / `guide` /
   `demo`). Unbekannte Werte fallen im Parser still auf Default.
2. **UI-Preferences.** `user://smolit_ui.cfg`, Sektion `[presence]`,
   Key `visual_action_mode`. Es werden nur **kanonische** Namen
   akzeptiert — Aliasse werden beim Laden verworfen, damit eine alte
   Alias-Datei nicht unbemerkt als Referenz durchschlägt.
3. **Default.** `minimal_feedback` — reproduziert den aktuellen
   Presence-MVP-Ist-Stand, damit Nutzer ohne Konfiguration dieselbe
   UI sehen wie bisher. Ohne Env und ohne Preferences-Datei bleibt
   der Start-Log stumm.

Live-Umschaltung läuft über die env-gated Dev-Steuerung
(`SMOLIT_UI_DEV_CONTROLS=1`, siehe §8c): ein vierstufiger Picker
ruft `main.set_visual_action_mode(mode)` auf; ein kleiner
„Save as default"-Button persistiert den Wert via
`main.save_visual_action_preference()` in dieselbe
`user://smolit_ui.cfg`. Kein Auto-Save, kein Settings-System.

**Bindende Grenzen.**

- **Kein Core-/IPC-/Protokoll-Eingriff.** Action Events, Event-
  Schema, EventBus-Signale bleiben unverändert.
- **Keine neue Wahrheit.** Der Mode schaltet Darstellung, erzeugt
  keine Events, filtert keine. Der Overlay-Flow läuft auch in
  `none` / `minimal_feedback` intern weiter — er wird nur nicht
  gerendert.
- **Keine neue Presence- oder Avatar-State-Maschine.** Die
  bestehenden Modi (Docked/Expanded/Action/Disconnected bzw.
  Idle/Thinking/Talking/Acting/Disconnected/Error) bleiben die
  maßgeblichen Achsen.
- **Keine Pixel-Geometrie, keine Zielkoordinaten.** Die vier
  Staging-Felder sind Booleans und Alpha-Floats — nichts davon
  referenziert Fensterposition oder Bildschirm-Koordinaten.
- **Keine Policy-/Approval-/Trust-Kopplung.** Der Mode ist UI-
  Darstellung; er darf nie Grundlage für „darf Smolit das tun?"
  werden.
- **Default-Smolit-Prinzip bleibt.** Unbekannte Werte fallen auf
  `minimal_feedback` zurück, nicht auf eine stärkere Stufe.

**Verifikation.** `scripts/visual_action_mode_smoke.gd` (41 Assertions,
alle PASS): Enum-Namen/Labels, Parser (kanonisch + Aliasse),
`coerce` für unbekannte Ints, `all_modes`-Reihenfolge, die vier
Staging-Tabellen inkl. monotoner Alpha-Skala, sowie Preferences-
Roundtrip (Load/Save, Whitelist für unbekannte String-Werte,
Ablehnung von Nicht-String-Werten, Unknown-Int-Coerce, Erhaltung
anderer Sektionen in der Config-Datei). Harness-Case:
`scripts/run_overlay_verification.sh visual-action-mode-smoke`.

---

## 8a. Workflow-Overlay-System *(entfernt, PR 33)*

Dieser Abschnitt beschrieb den früheren Drei-Knoten-MVP-Spike
(`ui/scripts/workflow_overlay/`,
`ui/scenes/workflow_overlay/workflow_overlay_root.tscn`). Der
Spike rekonstruierte Trigger → Action → Result aus dem
Action-Event-Strom und ergänzte den Avatar.

**Stand heute (PR 33, 2026-04-24):** der Spike ist komplett aus
der UI entfernt. Die Entscheidung und der fachliche Inhalt dieses
Abschnitts sind unter §8.4c (Workflow Visibility Overlay v1)
aufgegangen, das die gleichen Invarianten in einer linearen
Kartenliste abbildet und zusätzlich `APPROVAL` / `SPEAKING` /
`COMPLETED` / `FAILED` trägt. Detail-Review:
[`docs/reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md`](./reviews/PR33_WORKFLOW_OVERLAY_CONSOLIDATION.md).

Die frühere Untergliederung §8a.1–§8a.7 (Rolle, Darstellung,
Scope-Grenzen, Datenbindung, Nicht-Ziele, Collapse/Expand,
Event-Rekonstruktion) ist in §8.4c konsolidiert. Ältere
Dokumente, die §8a referenzieren, finden dort die gültige Fassung.

---

## 8b. Avatar Appearance System (Phase A Ist, Phase B Spike, sonst Ziel-Zustand)

Dieser Abschnitt beschreibt die geplante Erweiterung des Avatar-
Renderings um ein strukturiertes **Appearance-System** als rein
visuelle Darstellungsschicht. Er ist **Ziel-Zustand**; heute
existieren weder Templates noch Themes noch Override-Persistenz
im Repo. Der Default-Avatar (Smolit Salamander) aus §7 bleibt
unverändert und erster-Klasse.

Die Abschnittsnummer §8b reiht sich parallel zu §8a (Workflow-
Overlay-System) und vermeidet einen Renumber bestehender
Cross-References auf §8/§9/§10/§11.

### 8b.1 Rolle

- **Rein visuelle Darstellungsschicht.** Appearance rendert;
  Appearance entscheidet nichts.
- **Getrennt von Core und ABrain.** Appearance-Auswahl darf
  weder Action-Events verändern noch ABrain-Requests beeinflussen
  noch Presence-/Approval-Flows anfassen.
- **Ergänzung, nicht Ersatz** des bestehenden Avatar-Systems (§7).
  Das bestehende State-Mapping (`idle` / `thinking` / `talking` /
  `acting` / `disconnected` / `error`) bleibt die maßgebliche
  Zustandsmaschine.

### 8b.2 Architektur

Vier orthogonale Ebenen; jede einzelne ist optional, und jede
höhere Ebene setzt auf den unteren auf, ohne sie zu verändern:

1. **Avatar Identity** — *definiert die Figur.* Beispiele:
   Salamander (Default, Smolit), Roboter, Mensch, Tiere, abstrakte
   Formen (Orb, Nebel). Ein Identity-Wechsel verändert nur die
   Figur, keine Verhaltensregeln.
2. **Avatar Theme** — *Stil der Darstellung.* Mehrere Varianten pro
   Identity (z. B. `default`, `tech`, `soft`, `neon`, `minimal`).
   Themes sind Rendering-Presets, keine Zustandsmaschinen.
3. **Appearance Overrides** — *konkrete Anpassungen.* Farben,
   Glow, Outline, Größe, visuelle Intensität. Rein visuell,
   additiv zum Theme.
4. **Behavior Profile (UI)** — *Ausdruck / Animation.* Modulation
   von Animationsintensität, Idle-Cues und Übergangsstil. **Keine
   Logik**, kein Einfluss auf die Avatar-State-Maschine, kein
   Einfluss auf Action Events.

### 8b.3 Wichtige Trennung

Explizit und bindend für die gesamte Linie:

- **Appearance ≠ Behavior ≠ Personality ≠ Policy.**
- Die UI darf keine Systementscheidungen beeinflussen.
- Ein „verspielter" Behavior-Profile-Wert führt weder zu anderer
  Assistant-Antwort noch zu anderer Desktop-Aktion noch zu
  anderer Approval-Semantik.
- Die Avatar-Wahl verändert **nicht**: Action-Execution,
  Permissions, ABrain-Entscheidungen, Sicherheitsmodelle.

### 8b.4 Template-System (Ziel)

Jede Identity wird als **Template** beschrieben — eine bewusst
kleine, deklarative Struktur, die **was ein Template anbietet**
festhält, nicht **wie der Assistent reagiert**:

- **Unterstützte States.** Jedes Template deklariert, welche
  Avatar-States es visuell abdeckt (mindestens `idle`; alle
  übrigen optional).
- **Optionale Animationen.** Pro State kann ein Template eigene
  Animationen mitliefern; wo keine geliefert wird, greift der
  Fallback (§8b.5).
- **Fallback-Regeln für nicht unterstützte Zustände.** Templates
  dürfen nicht-deklarierte States an den neutralen `idle`-Pfad
  delegieren.

Templates sind **datengetrieben** beschreibbar; eine API-Zusage
(Feldnamen, Dateiformat) ist an dieser Stelle ausdrücklich noch
nicht fixiert.

### 8b.5 Fallback-Prinzip

- Fehlende States dürfen die UI **nicht brechen**. Die bestehende
  deterministische Rückfall-Logik des Avatar-Systems (siehe §7
  „Phase B") bleibt maßgeblich.
- Ersatzstrategie bei fehlenden Assets:
  1. neutraler Zustand (in der Regel `idle`-Pose);
  2. reduzierte Darstellung ohne State-spezifische Animation;
  3. Log-Eintrag, damit das Fehlen diagnostisch sichtbar wird
     — **kein Crash, keine UI-Blockade**.
- Der Default Smolit Salamander gilt als Referenztemplate: seine
  State-Abdeckung definiert, welche Zustände überhaupt mit voller
  visueller Qualität existieren.

### 8b.6 Nicht-Ziele

- **Kein 3D-Character-Editor, kein Rigging-System** im MVP.
- **Kein Einfluss auf ABrain, Core-Logik, Permissions, Security.**
- **Kein automatisches Persönlichkeits-Upgrade durch Avatar-Wahl.**
- **Kein Ersetzen des Defaults.** Smolit Salamander bleibt
  primärer Avatar; andere Identities sind additive Optionen.
- **Kein impliziter Scope-Creep Richtung Animation-Pipeline,
  Plug-in-Store, User-generated-Content-Plattform.** Jede dieser
  Richtungen wäre ein eigener Track mit eigenem Entscheidungs-
  und Verifikationsrahmen.

Einordnung in der Roadmap:
[`ROADMAP.md`](../ROADMAP.md) Phase 4b.
Presence-Seite:
[`presence_desktop_interaction.md`](./presence_desktop_interaction.md),
Unterabschnitt „Avatar-Personalisierung als Presence-Erweiterung".

### 8b.7 Phase A (Ist-Zustand, MVP-Spike)

Phase A der Appearance-Linie ist jetzt im Repo gelandet — bewusst
klein, markentreu, Smolit Salamander only. Die in §8b.1–§8b.6
beschriebene Architektur (vier orthogonale Ebenen) ist für **genau
eine** Identity realisiert:

- **Identity:** implizit `smolit_salamander`. Kein Identity-Wechsel
  in Phase A. Keine alternativen Figuren (Roboter / Mensch / Tier /
  Orb) im Code.
- **Theme:** vier markentreue Presets — `default`, `soft`, `tech`,
  `minimal`. Jedes Theme ist nur ein `tint_multiplier`-Eintrag, der
  multiplikativ auf die bestehende State-Modulate-Kette angewandt
  wird (`NORMAL`, `THINKING`, `DISCONNECTED`, `ERROR`,
  `ACTING_TINT_BY_TARGET`). Keine Texturwechsel.
- **Behavior Profile (UI):** drei UI-only Profile — `calm`
  (Referenzlinie), `lively`, `reserved`. Modulation erfolgt über
  drei Multiplikatoren (`amplitude_multiplier`, `tempo_multiplier`,
  `wiggle_interval_multiplier`). Amplituden werden nicht
  absolut skaliert, sondern ihr *Delta zur Ruhelage* (Vector2.ONE)
  — das erhält die Richtung der Mikroanimation und vermeidet
  Clippen.
- **Appearance Overrides:** `primary_tint` (multiplikative Farbe
  nach Theme-Tint), `intensity` (zusätzlicher Amplitude-
  Multiplikator, geclampt auf 0.5–1.5), `scale` (Root-Scale-
  Multiplikator, geclampt auf 0.75–1.5).

**Steuerung** (pragmatisch, MVP-Niveau):

Drei Eingabepfade, streng priorisiert:

1. **Env-Variablen** (höchste Priorität). Gesetzte Env übersteuert
   immer — sinnvoll für CI, Entwickler-Shells und Debug-Runs.
   - `SMOLIT_AVATAR_THEME` — `default` / `soft` / `tech` / `minimal`.
     Unbekannte Werte → `default`.
   - `SMOLIT_AVATAR_PROFILE` — `calm` / `lively` / `reserved`.
     Unbekannte Werte → `calm`.
   - `SMOLIT_AVATAR_INTENSITY` — Float, geclampt auf 0.5–1.5.
     Unparsebare Werte → nächster Schritt in der Kette (Prefs /
     Default), plus eine `push_warning`-Zeile.
2. **Lokal gespeicherte UI-Preferences** in `user://smolit_ui.cfg`,
   Abschnitt `[avatar_appearance]`. Nur dann aktiv, wenn das
   entsprechende Feld nicht per Env gesetzt ist — die Kette greift
   feldweise, nicht blockweise. Ohne Datei: diese Stufe ist
   vollständig transparent.
3. **Harte Defaults** — `ThemePreset.DEFAULT` / `BehaviorProfile.CALM`
   / `intensity=1.0` (Identitätswerte, Phase-A-Referenzlinie).

Beispiel (Entwickler-Lauf mit Env-Override):

```bash
SMOLIT_AVATAR_THEME=tech SMOLIT_AVATAR_PROFILE=lively \
SMOLIT_AVATAR_INTENSITY=1.2 godot --path ui
```

Beispiel (gespeicherte Preferences, kein Env):

```ini
; ~/.local/share/godot/app_userdata/…/smolit_ui.cfg
[avatar]
x=1740.0
y=980.0

[avatar_appearance]
theme="tech"
profile="lively"
intensity=1.2
```

Bei irgendeiner aktiven Quelle (Env oder Prefs) gibt der Controller
einmalig eine Diagnose-Log-Zeile aus, die pro Feld kennzeichnet,
woher der Wert kam:

```text
[avatar-appearance] identity=smolit_salamander theme=tech(env) profile=lively(prefs) intensity=1.20(env) scale=1.00
```

Ohne gesetzte Env **und** ohne Preferences-Datei bleibt der Start-Log
**byte-identisch** zum vor-PR-Stand — der Standard-Lauf hat keinen
neuen Log-Output.

**Preferences-Semantik.** Die UI-Preferences sind ausdrücklich ein
kleiner, lokaler, UI-naher Persistenzpfad — kein Settings-System,
kein Nutzerprofil, kein Account. Sie teilen sich die Datei
`user://smolit_ui.cfg` mit der Avatar-Position (Sektion `[avatar]
x/y`), ohne dass sich die beiden Sektionen beim Schreiben in die
Quere kommen. Invalide Einträge (falscher Typ, unbekannter Name,
Intensity außerhalb 0.5–1.5) werden beim Laden verworfen und durch
`push_warning` dokumentiert; der Aufrufer fällt dann auf Env oder
Default zurück. Beim Speichern werden alle drei Felder sanitisiert
(Enum-Clamping, `clampf(intensity, 0.5, 1.5)`), damit selbst eine
absichtlich korrupte Datei nicht durch die UI-API geschleust werden
kann.

**Datei-Layout:**

```text
ui/scripts/avatar/
├── avatar_state.gd         # (unverändert)
├── avatar_controller.gd    # Env > Prefs > Default, wrapt Konstanten
├── avatar_appearance.gd    # Enums, Presets, resolve-Helfer
└── avatar_preferences.gd   # NEU: kleine lokale UI-Persistenz
```

**Identitätsgarantie (geprüft im Smoketest).** `DEFAULT`-Theme +
`CALM`-Profile + Unity-Overrides (`primary_tint=Color(1,1,1,1)`,
`intensity=1.0`, `scale=1.0`) reproduzieren das exakte vor-PR-
Verhalten der Avatar-Mikroanimation:

- `resolved_tint(base) == base` (Theme-Tint und Override-Tint sind
  multiplikative Identitäten).
- `resolved_amplitude(base) == base` (Delta-Skalierung mit
  Multiplikator 1.0).
- `resolved_half_seconds(base) == base` (Tempo 1.0).
- `resolved_scale(base) == base` (Scale 1.0).
- `resolved_wiggle_interval(base) == base` (Wiggle 1.0).

Der Smoketest
`scripts/avatar_appearance_smoke.gd` deckt diese fünf Invarianten
zusammen mit Parser-Fallbacks, Clamping und erwarteten Profil-/
Theme-Effekten ab (insgesamt 32 Assertions, alle PASS unter
`scripts/run_overlay_verification.sh avatar-appearance-smoke`).

**Fallback-Prinzip in Phase A konkret:**

- Unbekanntes Theme (String oder Int) → `DEFAULT`.
- Unbekanntes Profile → `CALM`.
- Intensity/Scale außerhalb des Clamp-Bereichs → auf Min/Max
  begrenzt.
- `primary_tint` als Nicht-`Color` → Identität `Color(1,1,1,1)`.
- Kein Pfad kann den Avatar unsichtbar oder zu groß/klein machen —
  alle resolve-Helfer clampen oder fallen sicher zurück.

**Was Phase A explizit nicht tut:**

- Keine alternativen Figuren (Roboter / Mensch / Tier / Nebel) —
  siehe §8b.1.
- Kein Template-Marktplatz, kein User-Upload-Pfad — Stage C ist
  ausdrücklich nicht begonnen, siehe §8b.9 und
  [`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md).
- Kein Nutzerprofil, kein Account, keine Cloud-Sync. Die lokalen
  UI-Preferences sind bewusst auf die drei Phase-A-Felder begrenzt
  und landen in derselben ConfigFile, die schon die Avatar-Position
  hält.
- Keine neuen Events, keine IPC-Nachrichten, keine neue Core-API,
  keine Presence-Mode-Änderung.
- Keine visuellen Stil-Explosionen: alle Themes bleiben erkennbar
  als Smolit; `tint_multiplier`-Werte sind bewusst klein.
- Keine Auswirkung auf Workflow-Overlay, Presence-Controller,
  Window-Behavior, Approval-/Action-/Discovery-Banner, Compact-
  Input oder das Overlay-/Click-through-/AOT-/Runtime-Report-
  System.

### 8b.8 Phase B (kuratierter Spike, Ist-Zustand)

Phase B öffnet den Identity-Punkt aus §8b.2 ausdrücklich **klein und
kuratiert**: vier Identity-IDs sind Teil des MVPs —
`smolit_salamander` (Default), `robot_head`, `humanoid_head` und
`orb`. Das ist kein Template-Marktplatz und kein User-Upload-Pfad;
Stage C ist ausdrücklich nicht begonnen und bleibt Forschungs-/
Designraum (siehe §8b.9 und
[`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md)). Die Linie ist seit dem
Hardening-PR kein reiner „Identity-Name-Katalog" mehr, sondern ein
kleiner **Template-Capability-Contract**: jedes Template deklariert
explizit, welche Avatar-States es trägt und wie stark es die fünf
Ausdrucks-Achsen (Theme-Tint, Behavior-Profile, State-Pulse,
Wiggle, Error-Startle) umsetzt.

**Datei-Layout (erweitert):**

```text
ui/scripts/avatar/
├── avatar_state.gd                    # (unverändert)
├── avatar_controller.gd               # Env > Prefs > Default, Identity-Switch,
│                                      # State-Resolve via Capabilities
├── avatar_appearance.gd               # Themes / Profile / Overrides
├── avatar_preferences.gd              # lokale UI-Persistenz (inkl. identity)
├── avatar_identity.gd                 # kuratierter Identity-Katalog
├── avatar_identity_visual.gd          # prozeduraler Zweitrenderer
└── avatar_template_capabilities.gd    # NEU: Capability-Contract +
                                       # State-Fallback + Expression-Levels

ui/scenes/avatar/
└── avatar_root.tscn             # IdentityShape (Sibling zu Body)
```

**Render-Strategie.**

- Smolit bleibt **Render-Kind `TEXTURE`**: `Body: TextureRect` mit
  `smolit_idle.png` / `smolit_active.png` und dem Circle-Mask-Shader
  aus `avatar_root.tscn`. Genau dieses Verhalten ist Phase A und
  bleibt in Phase B byte-identisch für den Default.
- `robot_head`, `humanoid_head` und `orb` sind **Render-Kind
  `PROCEDURAL`**. Der Avatar-Controller versteckt dann `Body` und
  zeigt stattdessen `IdentityShape: Control` (Script
  `avatar_identity_visual.gd`), die ihre Grundform per `_draw()`
  rendert:
  - `robot_head` → Rounded-Rect-Körper + zwei Augen + Antennen-Dot,
  - `humanoid_head` → Hautton-Kreis + zwei Augen + sanfter Smile-Arc,
  - `orb` → drei konzentrische Kreise (Halo / Körper / Highlight).
  Keine Binärassets, keine Import-Pipeline.

**Zustands-Ausdruck bei kuratierten Alternativen.** Um die
bestehende Tween-Logik nicht zu verzweigen, zielt sie weiterhin auf
`_body`. Der Controller spiegelt pro Frame im `_process`-Tick die
drei relevanten Felder (`scale`, `rotation`, `modulate`) auf
`IdentityShape`. Dadurch:

- State-Tints (NORMAL / THINKING / DISCONNECTED / ERROR /
  ACTING-by-target) greifen genauso wie bei Smolit — nur dass sie
  jetzt auf der prozeduralen Form landen.
- Idle/Thinking/Acting/Talking-Breath und Error-Startle-Pulse
  laufen weiter auf `_body.scale` und werden gespiegelt.
- Curious-Wiggle (Idle-Rotations-Cue) läuft weiter und wird
  gespiegelt.
- Thinking-Alpha-Breath (`modulate:a`) läuft weiter und wird
  gespiegelt.

Der einzige Ausdruckspfad, den kuratierte Alternativen **nicht**
nutzen, ist der `IDLE_TEXTURE` ↔ `ACTIVE_TEXTURE`-Swap; das
Capability-Flag `supports_texture_swap` im Identity-Katalog
dokumentiert das ehrlich. In der Praxis ist das unkritisch, weil
`_body.texture =` auf ein verstecktes TextureRect geschrieben wird
und die Alternativen keinen eigenen Frame-Wechsel brauchen — ihr
State-Feedback kommt vollständig aus Tint + Pulse.

**Template-Capability-Contract.** Jedes Template deklariert in
`avatar_template_capabilities.gd` explizit:

- **`states_supported`** — Array über `AvatarState.State`-Werte, die
  direkt (ohne Fallback) gerendert werden können.
- **`state_fallback`** — optionaler Map-Eintrag
  `{ unsupported_state: replacement_state }`. Nur konsultiert, wenn
  der Ursprungs-State nicht `states_supported` ist. Der End-Fallback
  ist `IDLE`, damit `resolve_state` niemals einen nicht renderbaren
  State zurückgibt.
- **`expression`** — Dictionary über fünf Ausdrucks-Achsen auf
  `ExpressionLevel`-Werte:
  - `theme_tint` — wie stark das Theme auf die State-Modulate wirkt.
  - `behavior_profile` — wie stark Profile-Multiplier (Amplitude,
    Tempo, Wiggle-Intervall) greifen.
  - `state_pulse` — wie stark der Idle/Thinking/Acting/Talking-
    Breath-Tween ausschlägt.
  - `wiggle` — wie stark der Idle-Rotations-Cue ausschlägt; `NONE`
    schaltet ihn aus.
  - `error_startle` — wie stark der Error-Flinch ausschlägt.

`ExpressionLevel` hat drei Werte: `NONE` (Multiplikator 0.0 → Pfad
ausgeschaltet), `REDUCED` (0.5 → halbes Delta zur Ruhelage) und
`FULL` (1.0 → Smolit-Referenzlinie). Der Controller übersetzt den
Level via `capabilities.multiplier(...)` in einen Zahlenfaktor und
skaliert damit Amplituden, Winkel und Tint-Deltas um die
Ruhelage `Vector2.ONE` bzw. die identitätsneutrale Basis.

**Aktuelle Capability-Matrix (Phase-B-Spike):**

| Identity          | TALKING supported? | `state_fallback`    | wiggle  | pulse | startle | tint | profile |
|-------------------|--------------------|---------------------|---------|-------|---------|------|---------|
| smolit_salamander | ja                 | —                   | FULL    | FULL  | FULL    | FULL | FULL    |
| robot_head        | ja                 | —                   | REDUCED | FULL  | FULL    | FULL | FULL    |
| humanoid_head     | ja                 | —                   | REDUCED | FULL  | FULL    | FULL | FULL    |
| orb               | **nein**           | `TALKING → ACTING`  | NONE    | FULL  | FULL    | FULL | FULL    |

`orb` hat keinen „Mund": der Talking-State wird vor dem Rendern auf
`ACTING` gemappt (der vorhandene Acting-Pulse + Acting-Tint trägt
den Ausdruck). `robot_head` und `humanoid_head` dämpfen den
Idle-Wiggle, weil ein mechanischer bzw. menschlich gelesener Kopf
mit dem vollen Smolit-Wiggle unnatürlich wirkt. Alle anderen
Achsen bleiben für alle Templates voll — `theme_tint` und
`behavior_profile` sind Teil des Contract-Vokabulars, werden aber
von keinem aktuellen Template abgesenkt (die Skalierungslogik ist
trotzdem implementiert, damit spätere kuratierte Templates sie ohne
Controller-Umbau nutzen können).

**Eingabepfade für die Identity** (gleiche Prioritätskette wie die
Phase-A-Felder):

1. `SMOLIT_AVATAR_IDENTITY` — `smolit_salamander` / `robot_head` /
   `humanoid_head` / `orb`, plus Convenience-Aliasse (`smolit`,
   `salamander`, `robot`, `humanoid`, `human`). Unbekannte Werte →
   Smolit.
2. Gespeicherte UI-Preferences (`user://smolit_ui.cfg`, Key
   `identity` in Sektion `[avatar_appearance]`). Es werden nur
   kanonische Namen als gültig akzeptiert; Aliasse in der
   Config-Datei fallen durch (bewusst, siehe `avatar_preferences.gd`).
3. Harter Default: Smolit Salamander.

Ein gesetzter Identity-Wert aktiviert die Diagnose-Log-Zeile des
Appearance-Controllers genauso wie Theme/Profile/Intensity — der
Default-Lauf bleibt stumm und byte-kompatibel.

**Fallback-Garantien.**

- Unbekannter Identity-String → Smolit. Nie auf Robot oder Orb.
- Unbekannter Identity-Int (z. B. zukünftiger Enum-Wert, der in
  einer alten Preferences-Datei landen sollte) → Smolit.
- `set_appearance()` akzeptiert jetzt Identity-Namen, klemmt aber
  unbekannte Werte ebenfalls auf Smolit (`avatar_identity.gd::
  identity_from_string`).
- Wird der Identity-Shape sichtbar, aber das Script verliert
  später eine Ziel-ID, zeichnet `_draw()` via `Shape.NONE` gar
  nichts — der Node bleibt leer, aber der Controller crasht nicht.

**Verifikation.** `scripts/avatar_identity_smoke.gd` (45 Assertions,
alle PASS): Default-Garantie, kanonische + Alias-Parser, Fallback-
auf-Smolit, Render-Kind/Shape/Capability-Lookups, Name-Round-Trips,
`all_ids`-Reihenfolge. Der Harness-Case `avatar-identity-smoke`
läuft den Test. `scripts/avatar_template_capabilities_smoke.gd`
(65 Assertions, alle PASS) prüft den Capability-Contract:
States-Support, `state_fallback`-Auflösung (inkl. orb TALKING →
ACTING), Expression-Levels pro Achse, Multiplier-Mapping und das
stille Zurückfallen unbekannter Identity-IDs auf Smolit. Der
Harness-Case heißt `avatar-template-capabilities-smoke`. Zusätzlich
deckt die erweiterte `avatar_preferences_smoke.gd` den Identity-
Round-Trip (inkl. Humanoid), Alias-Rejection und invalide
identity-Einträge ab.

**Was Phase B ausdrücklich nicht tut:**

- Keine User-Uploads, kein Template-Marktplatz, kein Content-
  Pipeline.
- Keine Asset-Imports (PNG, SVG, GLB, …) — Alternativen sind
  prozedural.
- Keine alternative Logik, keine alternative Security-/Policy-
  Semantik — Identity ≠ Behavior ≠ Personality ≠ Policy, unverändert
  aus §8b.3.
- Keine Presence-Mode-Änderung, keine Workflow-Overlay-Interaktion,
  keine Window-Behavior-Änderung, keine neue IPC.
- Kein Default-Austausch. Smolit bleibt Referenz und erste Option
  im Picker.

### 8b.9 Stage C — Forschungs- und Designraum (nicht begonnen)

Stage C der Appearance-Linie ist **ausdrücklich nicht begonnen**.
Sie ist weder eine laufende Implementierungsphase noch ein fest
zugesagter Ausbaupfad, sondern ein gesondert dokumentierter
Forschungs-/Designraum. Stage B ist bewusst geschlossen und wird nicht
stillschweigend in offene Avatar-Erweiterbarkeit überführt.

Die Begründung, die offenen Fragen, die harten Nicht-Ziele, das
Sicherheits- und Vertrauensmodell, der Vergleich möglicher
Architekturpfade (C1–C4) sowie die Exit-Kriterien für einen späteren
echten Implementierungsstart stehen vollständig und ausschließlich in
[`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md).

Für diesen Abschnitt gelten drei harte Klarstellungen:

- **Stage C öffnet heute keinen neuen Codepfad.** Es gibt keinen
  Asset-Loader, keinen Manifest-Parser, keinen File-Picker für
  Avatar-Inhalte, keinen Plugin-Kontrakt. Der Capability-Contract aus
  §8b.8 ist intern und bleibt intern.
- **Stage C bleibt security-gated.** Ein späterer Übergang in eine
  Implementierungsphase ist erst zulässig, wenn die Exit-Kriterien
  in [`docs/avatar_stage_c_research.md` §10](./avatar_stage_c_research.md)
  erfüllt sind — insbesondere ein beschlossenes Sicherheitsmodell,
  konkrete Formatgrenzen, eine Teststrategie und deterministische
  Fallback-Regeln.
- **Trennung bleibt bindend.** Auch unter Stage C ändert sich nichts
  an der Grundregel Appearance ≠ Behavior ≠ Personality ≠ Policy aus
  §8b.3. Keine erweiterte Avatar-Quelle darf Assistant-Rechte,
  Approval-Flows, Action-Execution, Permissions oder ABrain-
  Entscheidungen beeinflussen.

### 8b.10 Stage-C-Guardrails für spätere PRs

Operationale Leitplanken für jeden zukünftigen PR, der Stage-C-Themen
berührt. Sie ersetzen nicht §8b.9 oder
[`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md),
sondern fassen deren Konsequenzen für den PR-Review-Alltag zusammen.

- **Research-/Security-Bezug ist Voraussetzung.** Ein Stage-C-PR muss
  explizit auf einen beschlossenen Abschnitt in
  [`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md)
  verweisen — insbesondere auf die Exit-Kriterien in §10 dort. Ohne
  diesen Bezug ist der PR research-gated und nicht mergefähig.
- **Keine Runtime-Vorimplementierung ohne explizite Entscheidung.**
  Kein Asset-Loader, kein Manifest-Parser, kein File-Picker, kein
  Import-Dialog, keine neue Scene, kein neues Runtime-Skript für
  Avatar-Import unter dem Vorwand „Vorbereitung" oder „nur
  Skelett". Auch Prototypen gehören nicht in den Produktivpfad,
  solange das Sicherheitsmodell nicht beschlossen ist.
- **Keine User-Import-Wege ohne festes Vertrauensmodell.** Jede Form
  von nutzerseitigem Input in die Avatar-Linie (lokale Bundles,
  externe Assets, Drag-and-Drop) ist nur zulässig, nachdem die
  Vertrauensklasse (§5 der Research-Doku), die Formatgrenzen und
  die Refusal-Semantik (§7) als Entscheidung stehen — nicht im
  selben PR.
- **Kein Vermischen von Avatar-Look und Assistant-Fähigkeiten.**
  Ein Stage-C-PR darf keinen Pfad öffnen, in dem Avatar-Wahl,
  Theme, Identity oder Bundle-Inhalt Approval-Flows, Policy,
  Permissions, Action-Execution oder ABrain-Prompts beeinflusst —
  weder direkt noch über neue Felder oder Metadaten.
- **Default-Smolit und Fallback-Verhalten bleiben geschützt.**
  Smolit Salamander bleibt Default, Referenz und einziger
  Endfallback. Jeder Fehlerpfad landet deterministisch dort. Kein
  Stage-C-PR darf diesen Fallback aufweichen, austauschbar machen
  oder hinter einem Flag versteckt deaktivieren.
- **Kein Core-/IPC-Druck durch Avatar-Arbeit.** Wenn ein Stage-C-
  Entwurf Änderungen am Core, am IPC-Protokoll (siehe
  [`docs/api.md`](./api.md)) oder an ABrain erzwingen würde, ist
  die korrekte Reaktion, den Entwurf zu reduzieren — nicht, den
  Core/ABrain nachzuziehen. Appearance bleibt UI-lokal.

Reviewer dürfen sich auf diese Guardrails direkt berufen.
Stage-C-Inhalt, der eine dieser Leitplanken verletzt, ist nicht
„nur eine Änderungsbitte" — er ist außerhalb des Scopes, solange
die Research-Exit-Kriterien nicht erfüllt sind.

---

## 8c. Dev-/MVP-Steuerung für Workflow-Overlay und Avatar-Appearance

Kleine, dev-/preview-orientierte Hilfsschicht. Ausdrücklich **kein**
Settings-System, **kein** Customization-Marktplatz, **kein**
Persistenzsystem — sie macht nur die beiden bestehenden UI-Linien
(Workflow-Overlay, Avatar-Appearance Phase A + Phase B) zur Laufzeit
beobachtbar und umschaltbar. Die Avatar-Seite schaltet dabei
ausschließlich die **kuratierte** Stage-B-Template-Linie durch; sie
öffnet keinen Stage-C-Importpfad, keine neue Avatar-Quelle und keine
Kopplung an Assistant-Logik, Policy oder Core-/IPC-Modell.

**Gating.** Das Panel ist standardmäßig unsichtbar und stumm.
Sichtbar wird es ausschließlich mit
`SMOLIT_UI_DEV_CONTROLS=1`. Ohne Opt-in:

- kein `[dev-controls]`-Log,
- kein Input-Steal,
- keine Änderung am bestehenden Startverhalten.

Die 8 bestehenden Harness-Cases bleiben byte-identisch.

**Datei-Layout.**

```text
ui/
├── scenes/
│   └── dev_controls/
│       └── dev_controls_panel.tscn
└── scripts/
    └── dev_controls/
        └── dev_controls_controller.gd
```

Das Panel ist in `main.tscn` bottom-right verankert (z_index=120,
über Compact-Input und Workflow-Overlay), damit es bestehende UI
nicht verdeckt.

**Was die Steuerung kann.** Zwei klar getrennte Bereiche.

1. **Avatar-Appearance (Phase A + Phase-B-Identity-Picker).**
   Identity-OptionButton (4 Optionen, Phase-B-kuratiert: Smolit /
   Robot-Head / Humanoid-Head / Orb), Theme-OptionButton (4 Optionen),
   Profile-OptionButton (3 Optionen), Intensity-Slider (0.5 .. 1.5).
   Änderungen rufen `avatar_controller.set_appearance()` auf, das
   das Appearance-Dict ersetzt, die Root-Scale aktualisiert und
   `_apply_state_visuals()` neu startet. Unbekannte Identity-Werte
   werden vom Avatar-Controller auf Smolit zurückgeklemmt (§8b.8). Ein kleiner **„Save as default"**-Button persistiert
   die aktuellen drei Werte via
   `avatar_controller.save_current_preferences()` in
   `user://smolit_ui.cfg` (Sektion `[avatar_appearance]`); jede
   anschließende Änderung am Picker/Slider entfernt wieder die
   „saved"-Statusanzeige, damit der Panel-Zustand ehrlich bleibt.
   Standardverhalten ist weiter **session-only** — der Save-Klick
   ist eine explizite, einmalige Geste, nicht Auto-Save.
2. **Workflow-Overlay-Preview.** Sechs Preview-Knöpfe (`Hidden`,
   `Planned`, `Active`, `Completed`, `Failed`, `Cancelled`). Sie
   rufen `workflow_overlay_controller.preview_phase(name)` auf, das
   einen synthetischen Flow direkt im Overlay setzt — **ohne**
   Action Events an den EventBus zu emittieren. Andere Subscriber
   (insbesondere der Avatar) reagieren nicht; die Preview ist
   lokal an die Overlay-Darstellung gebunden.

**Warum `preview_phase` statt EventBus-Injection.** Synthetische
`action_*`-Events auf dem EventBus würden durch den Avatar-
Controller und jeden anderen Konsumenten laufen — das wäre eine
Fake-Action-Wahrheit in der UI, und genau das hat der PR-Scope
ausgeschlossen. Der direkte Preview-Hook bleibt read-only und
beeinflusst nur den Overlay-Renderer.

**Was die Steuerung bewusst nicht tut.**

- Keine Persistenz — Änderungen gelten nur für die laufende
  Session. Keine ConfigFile-Writes, kein Nutzerprofil, kein
  Sync mit dem Core.
- Keine neuen Protokolle, keine neuen IPC-Nachrichten, keine
  Core-/ABrain-/Policy-Kopplung.
- Kein Workflow-Authoring, kein Graph-Editor, kein Action-
  Auslöser. Die sechs Preview-Phasen sind canned Snapshots, keine
  Event-Erzeugung.
- Kein neues Avatar-Template, kein User-Upload, kein 3D-Editor —
  die Steuerung schaltet nur zwischen den vier kuratierten Stage-B-
  Identities (Smolit / Robot-Head / Humanoid-Head / Orb) um.
  Default-Smolit bleibt erster-Klasse und harter Fallback; unbekannte
  Identity-Werte werden auf Smolit zurückgeklemmt (§8b.8).
- Keine Auswirkung auf Presence-Controller, Approval-/Action-/
  Discovery-Banner, Compact-Input, Overlay/Click-through/AOT,
  Window-Behavior-Backend-Familie.

**Verifikation.** `scripts/dev_controls_smoke.gd` (15 Assertions,
alle PASS): Panel-Phase-Namen gegen State-Modul gematcht,
Theme-/Profile-Round-Trips, 4×3×3-`make_appearance`-Matrix auf
Identität und Konsistenz geprüft, Identity-Invarianz bestätigt.
Harness-Case `dev-controls-smoke` läuft den Test.

---

## 8d. Settings-Shell im Expanded Window (Phase 8c PR 3, Ist-Zustand)

Smolit bekommt im Expanded Window einen eigenständigen, sichtbaren
Einstieg in ein späteres Settings-Menü. Dieser PR liefert bewusst nur
die **Shell** — Struktur, Navigation und read-only Readout. Keine
Schreib-Aktionen, keine Secrets-Eingabe, kein Cloud-Pfad.

> **Seit PR 36 (UX Cleanup):** Die drei Provider-Sections (Text /
> STT / TTS) folgen derselben dreiteiligen Lesereihenfolge **Summary
> · Details · Editoren**. Die Privacy-Section trägt einen expliziten
> `— Safety notes —`-Block mit konstanten Zeilen (Opt-in cloud,
> Secrets nie angezeigt, env-only Kommandos, Probes side-effect-frei).
> Der Text-Chain-Editor hat eine zusätzliche Note, die cloud_http als
> Opt-in ausweist. Keine neuen IPC-Commands, keine neuen Provider —
> die Shell bleibt Shell. Details:
> [`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md)
> §13.

Crosslinks:
[`docs/provider_fallback_and_settings_architecture.md`](./provider_fallback_and_settings_architecture.md)
§6 (Settings-Scope), §9 (PR-Reihenfolge); `docs/api.md` §2.3
(StatusPayload-Felder, inkl. `text_provider_*`).

### 8d.1 Rolle und Scope-Grenzen

- **Rolle.** Additiver UI-Substate auf dem Expanded-Window. Die
  Settings-Shell ersetzt das Dock-Panel *innerhalb derselben
  Presence-Hülle* — kein neues Toplevel-Fenster, kein Overlay, kein
  neuer Presence-Mode.
- **Nicht erreichbar in Docked.** Der Settings-Button ist nur sichtbar,
  wenn der Presence-Mode `expanded` (oder `disconnected` mit offener
  Shell) ist. In Docked bleibt Smolit bewusst ruhig; Settings sind eine
  aktive Handlung, keine Ablenkung.
- **Avatar / Banner / Overlay bleiben unberührt.** Action-Banner,
  Approval-Banner, Discovery-Panel, Avatar, Workflow-Overlay und
  Utterance-Bubble liegen weiter in derselben Scene und behalten ihre
  Sichtbarkeitslogik. Die Shell sitzt im selben `VBox` wie das
  Dock-Panel und toggelt nur die Sichtbarkeit mit ihm.
- **Keine Schreib-Aktionen.** Alle Bereiche sind read-only. Der
  Controller emittiert ausschließlich ein `close_requested`-Signal;
  sonst kennt er weder IPC noch Side-Effects.

### 8d.2 Datei-Layout

```text
ui/
├── scenes/
│   └── settings/
│       └── settings_panel.tscn
└── scripts/
    └── settings/
        ├── settings_sections.gd          # pure Helfer (Sections, Labels, *_lines)
        └── settings_panel_controller.gd  # Scene-Controller
```

- `settings_sections.gd` ist ein `RefCounted` ohne Scene-Kopplung:
  `SectionId`-Enum, `all_sections()`, `label_for()`, `placeholder_for()`,
  `slug_for()` und je Abschnitt eine `*_lines(status, extras)`-Funktion,
  die eine flache Liste von `{label, value, muted}`-Rows liefert.
- `settings_panel_controller.gd` ist ein `PanelContainer`: baut den
  UI-Rahmen programmatisch auf (Header mit Back-Button + Titel,
  ScrollContainer, Content-VBox), rendert die Sections aus
  `SettingsSections` und hält nur zwei schwache Caches
  (`_last_status`, `_last_extras`).

### 8d.3 Navigation im Expanded-Flow

- `main.tscn` hat einen neuen `SettingsButton` im `HeaderRow` (`⚙ Settings`,
  `flat = true`). Der Button ist nur in Expanded sichtbar.
- `main.gd` trackt `_settings_open: bool` und cached das letzte
  `StatusPayload` als `_last_status_payload`. Umschaltung passiert in
  zwei Methoden:
  - `_open_settings()` versteckt `DockPanel`, versteckt Compact-Input,
    zeigt `SettingsPanel`, ruft `apply_status` + `apply_extras` (Visual-
    Action-Mode-Name, Presence-Mode-Name, Connected-Bool) auf und
    macht ein finales `open_panel()`.
  - `_close_settings()` versteckt das Panel wieder und zeigt das
    Dock-Panel zurück, solange der Presence-Mode `expanded` oder
    `disconnected` ist (in Docked bleibt das Dock-Panel versteckt).
- Der Back-Button im Panel emittiert `close_requested` →
  `_on_settings_close_requested` → `_close_settings()`. Ein zweiter
  Klick auf den Header-Settings-Button schließt die Shell ebenfalls.
- Bei Wechsel zu Docked wird die Shell hart geschlossen; bei Wechsel
  zurück zu Expanded wird sie nur wiederhergestellt, wenn sie vor dem
  Wechsel offen war. Bei `disconnected` bleibt sie sichtbar, falls sie
  offen war — der Nutzer soll auch ohne Core-Verbindung zurück
  navigieren können.

### 8d.4 Sichtbare Bereiche (read-only)

In der festen Reihenfolge: **General**, **Presence / UI**,
**Text Provider**, **STT**, **TTS**, **Privacy / Cloud / Data
handling**, **Connection / Status**. Jeder Abschnitt trägt:

- Titel + kleiner deutscher Shell-Hinweis (`placeholder_for`),
- eine Liste von `label · value`-Zeilen, die aus dem letzten bekannten
  StatusPayload plus UI-Extras gerendert werden,
- eine dünne Trennlinie.

Gerenderte Felder (StatusPayload-Quelle siehe `docs/api.md` §2.3):

- **General** — App-Name, Shell-Marker.
- **Presence / UI** — `visual_action_mode` (aus `main.gd`),
  `presence_mode` (aus `PresenceState.name_of`), Avatar-Appearance-
  Hinweis auf Dev-Controls.
- **Text Provider** — `text_provider_configured`,
  `text_provider_active`, `text_provider_availability`,
  `text_provider_last_error`, `text_provider_cloud`. Seit PR 4
  zusätzlich: `text_provider_chain` als „→"-getrennte Fallback-
  Reihenfolge und ein vertiefter `llamafile_local`-Block mit
  `lifecycle` / `mode` / `idle timeout` sowie booleschem `enabled`
  (Env-Flag) und `configured (path set)`. Der Block wird genau
  dann gezeigt, wenn `llamafile_in_chain=true`; sonst rendert die
  Shell ehrlich „nicht in der Chain" und — wenn der Env-Flag
  trotzdem gesetzt ist — benennt den zuständigen
  `SMOLIT_TEXT_PROVIDER_CHAIN`-Knopf. Alte Cores ohne
  `llamafile_in_chain`-Feld fallen stillschweigend auf den
  PR-3-Sammelhinweis zurück.
- **STT / TTS** — `stt_enabled` / `stt_available` bzw. `tts_enabled` /
  `tts_available` / `auto_speak` als Legacy-Feature-Flags. Seit PR 6
  zusätzlich die fünf Resolver-Zeilen pro Achse: `Configured`,
  `Active`, `Availability`, `Last error`, `Cloud`. Gerendert über
  den gemeinsamen Helfer `_audio_provider_lines(status, prefix)` in
  [`ui/scripts/settings/settings_sections.gd`](../ui/scripts/settings/settings_sections.gd).
  Fehlen die neuen `*_provider_*`-Felder (alter Core), bleibt eine
  ehrliche Fallback-Zeile „Core liefert keine `stt_provider_*`/
  `tts_provider_*`-Felder" stehen.
- **Privacy** — Cloud-Flag für Text-Achse. Seit PR 4 zusätzlich
  eine „Text: lokaler Pfad"-Zeile, die
  `text_provider_cloud` + `llamafile_in_chain` + `llamafile_enabled`
  zu einer ehrlichen Lokal-Aussage verdichtet (aktiver Lokalpfad
  vs. „in Chain, aber disabled" vs. „nur abrain in Chain"). Seit
  PR 6 zwei separate Cloud-Zeilen für STT und TTS, sobald die
  `stt_provider_cloud` / `tts_provider_cloud`-Felder im Status
  vorhanden sind; fallbackweise bleibt die Legacy-Sammelzeile
  „STT/TTS Cloud — noch nicht modelliert" erhalten. Weitere Zeilen
  bleiben Platzhalter für Offline-Only und Secrets (PR 5).
- **Connection / Status** — `IPC (connected/disconnected)`,
  `ipc_enabled`, `interaction_enabled`, `interaction_backend`,
  `approval_timeout_seconds`, `accessibility_probe` (+ optional
  `accessibility_probe_reason`).

Defensive Regeln:

- Fehlende oder `null`-Felder werden als `—` gerendert, nie als
  geratener Default.
- Unbekannte Booleans (z. B. String `"yes"`) werden tolerant
  interpretiert; nicht interpretierbare Werte werden ebenfalls als `—`
  gerendert.
- Nicht-Dictionary-Eingaben an `apply_status` / `apply_extras` werden
  still zu leeren Defaults — die Shell crasht nicht, zeigt aber
  ehrlich nichts an.

### 8d.5 Nicht-Ziele dieses PR

- Keine Secrets-/Path-/Binary-Eingabe (kein Input-Feld in dieser Shell).
- Keine Start/Stop-Buttons für `llamafile_local` oder andere Provider.
- Keine Cloud-Provider-Integration, keine Opt-in-Flüsse.
- Keine STT-/TTS-Provider-Abstraktion, keine neue IPC-Familie.
- Keine neue Toplevel-Window-Struktur, kein Overlay-Verhalten.
- Keine Stage-C-/Avatar-Appearance-Kopplung.
- Keine Änderung an Approval / Interaction / Policy.
- Kein generischer Settings-Router, kein Multi-Page-Framework.

### 8d.5a Erste editierbare Oberfläche (PR 5, Ist-Zustand)

Mit PR 5 bekommt die Shell die ersten kleinen, kuratierten Schreib-
und Probe-Aktionen. Scope bleibt bewusst eng: nur
`llamafile_local`. Alle anderen Felder bleiben read-only.

**Direkt unter dem Text-Provider-Readout** rendert der Controller
einen eigenen „llamafile_local · Edit"-Block mit:

- **Enabled** — `CheckBox` spiegelt `SMOLIT_LLAMAFILE_ENABLED`.
- **Mode** — `OptionButton` mit der Whitelist `on_demand` /
  `standby`. Unbekannte Werte werden im Core **ausdrücklich**
  abgelehnt (im Gegensatz zum Startup-Parser, der still auf den
  Default fällt).
- **Idle timeout (s)** — `SpinBox` (1 .. 86 400). `0` wird vom Core
  als Fehler zurückgeschickt.
- **Binary path** — `LineEdit` mit Tooltip „Wird nicht in Logs
  ausgegeben". Leerer String löscht den Pfad. Der Core loggt nur
  `path_set=true/false`; weder Shell noch Core schreiben den Pfad
  in Status, Event-Envelopes oder Fehler-Meldungen.
- **Apply-Button** — löst `IpcClient.settings_set_llamafile_config`
  aus. Der Core validiert, rebuildet den Resolver atomar,
  persistiert atomar (siehe
  [`docs/provider_fallback_and_settings_architecture.md` §11](./provider_fallback_and_settings_architecture.md))
  und echoed einen frischen `status`-Envelope. Die UI
  synchronisiert ihre Widgets beim nächsten `apply_status`-Tick —
  sie hält **keine** zweite Wahrheit.
- **Probe-Button** — löst `IpcClient.settings_probe_llamafile` aus.
  Seiten-effektfrei (kein Spawn, kein HTTP). Die Antwort kommt als
  `settings_probe_result` auf einem neuen EventBus-Signal
  (`settings_probe_result_received`); das Panel zeigt den Tag
  (`[ok]` / `[path_missing]` / `[not_configured]` / …) plus die
  kurze Core-Meldung. Die UI setzt **keinen** eigenen grünen
  Haken; Erfolg wird ausschließlich durch den Core-Tag `ok`
  angezeigt.

Defensive Regeln:

- Alle Widget-Stände kommen beim Render aus dem letzten
  `StatusPayload`. Ein `_syncing_*`-Flag verhindert
  Change-Handler-Kaskaden während des Re-Syncs.
- Wenn der Core offline ist, bleibt Apply/Probe stumm — die
  Buttons setzen lokal `"offline"`/`"probe: offline"` und senden
  nichts.
- Der Renderer baut den Editor-Block **nach** jedem Re-Render neu
  auf; alte Widget-Referenzen werden explizit auf `null` gesetzt,
  bevor die neuen Nodes entstehen.

EventBus-/IPC-Erweiterungen (additiv):

- Neues Signal `settings_probe_result_received(payload: Dictionary)`
  in [`ui/autoload/event_bus.gd`](../ui/autoload/event_bus.gd).
- Neue Client-Methoden in [`ui/autoload/ipc_client.gd`](../ui/autoload/ipc_client.gd):
  `settings_set_llamafile_config(enabled, mode=null, idle_timeout_seconds=null, path=null)`
  und `settings_probe_llamafile()`.

Sicherheitsgrenzen für diese erste editierbare Fläche:

- **Keine Secrets** werden über `settings_set_*` transportiert —
  API-Keys, Tokens usw. bleiben für einen späteren dedizierten
  Pfad reserviert.
- **Keine Pfade in Logs / Status / Fehler / Probe-Ergebnissen.**
- **Kein UI-seitiger Secret-Store.** Der Core bleibt einziger
  Persistenz-Ort.

### 8d.5b STT-/TTS-Settings-Editor (PR 7, Ist-Zustand)

PR 7 zieht die PR-5-Linie auf die Audio-Achsen, bewusst kleiner
gehalten: **direkt unter dem jeweiligen Read-only Readout** rendert
der Controller einen eigenen „stt · Edit"- bzw. „tts · Edit"-Block.

- **Enabled (STT/TTS)** — `CheckBox` spiegelt
  `SMOLIT_STT_ENABLED` bzw. `SMOLIT_TTS_ENABLED`.
- **Command (STT/TTS)** — `LineEdit` mit Tooltip „Wird nicht in Logs
  ausgegeben". Leer/whitespace löscht den Command; leeres Feld beim
  Apply sendet `null`, damit ein versehentlich leer geklicktes Feld
  den konfigurierten Wert nicht löscht (analog zum Llamafile-Pfad).
- **Auto-speak (nur TTS)** — `CheckBox` spiegelt `SMOLIT_AUTO_SPEAK`.
  Ergänzt den bestehenden read-only Readout; der Wert wandert
  zusammen mit `enabled`/`command` als ein einziger
  `settings_set_tts_config`-Aufruf an den Core.
- **Apply / Probe / Status-Labels** — Symmetrisch zum Llamafile-
  Block. Die Probe-Antwort kommt weiterhin als
  `settings_probe_result_received`, trägt jetzt aber ein `axis`-Feld
  (`"stt"` / `"tts"` / `"llamafile"`) und wird im Panel in den
  passenden Block geroutet; ältere Cores ohne `axis` fallen auf den
  Llamafile-Block zurück (Backwards-Kompatibilität).

Defensive Regeln:

- Das `command`-Feld wird **nicht** aus dem StatusPayload
  vorbelegt — die Shell hält keinen zweiten Wahrheits-Anker. Die
  Probe-Ergebnisse zeigen über `configured=true/false`, ob der Core
  einen Command konfiguriert findet.
- STT-/TTS-Probes lösen weder Mikrofon-Aufnahme noch Audio-Output
  aus. Der Core prüft ausschließlich Chain/Enabled/Command-Parsing +
  Filesystem-Status des ersten Tokens.

EventBus-/IPC-Erweiterungen (additiv, PR 7):

- Neue Client-Methoden in
  [`ui/autoload/ipc_client.gd`](../ui/autoload/ipc_client.gd):
  `settings_set_stt_config(enabled, command=null)`,
  `settings_set_tts_config(enabled, command=null, auto_speak=null)`,
  `settings_probe_stt()`, `settings_probe_tts()`.
- Der bestehende `settings_probe_result_received`-Signal-Payload
  trägt jetzt zusätzlich `axis`; andere Felder unverändert.

Sicherheitsgrenzen erweitert um:

- **Kein Command-Leak.** Der Command-String taucht weder in Logs
  noch im `settings_probe_result` noch im `error`-Envelope auf.
  Gleiche Posture wie der Llamafile-Pfad.
- **Kein Mikrofon-/Audio-Zugriff in der Probe.**

### 8d.5c local_http-Settings-Editor (PR 8, Ist-Zustand)

PR 8 zieht die Editor-Linie auf die Text-Achse in der Breite: neben
dem bestehenden `llamafile_local`-Block rendert die Settings-Shell
direkt darunter einen zweiten „local_http · Edit"-Block. Scope
bewusst klein, loopback-first.

- **Enabled** — `CheckBox` spiegelt `SMOLIT_LOCAL_HTTP_ENABLED`.
- **Endpoint** — `LineEdit` mit Tooltip „Wird nicht in Logs
  ausgegeben". Leer/whitespace löscht den Endpoint; leeres Feld
  beim Apply sendet `null` (Wert unverändert), analog zum
  Llamafile-Pfad. `https://` wird vom Core abgelehnt — die UI
  leitet das 1:1 als Probe-Klasse `endpoint_scheme_unsupported`
  weiter, ohne eigene Fehlerlogik.
- **Apply / Probe / Status-Labels** — Symmetrisch zum Llamafile-
  Block. Der Probe-Button löst einen reinen TCP-Connect-Check
  aus; es werden **keine** Prompt-Daten gesendet. Das
  `settings_probe_result` trägt `axis="local_http"` und wird im
  passenden Block angezeigt.

Defensive Regeln:

- Das `endpoint`-Feld wird **nicht** aus dem StatusPayload
  vorbelegt — die Shell hält keinen zweiten Wahrheits-Anker für
  Pfad-artige Werte.
- Request-Timeout ist in dieser Stufe nicht editierbar — das
  bleibt env-/Startup-gesteuert, damit der Erst-Editor klein
  bleibt.
- Chain-Reihenfolge bleibt env-gesteuert
  (`SMOLIT_TEXT_PROVIDER_CHAIN`); die UI editiert nur die
  Per-Kind-Konfiguration.

EventBus-/IPC-Erweiterungen (additiv, PR 8):

- Neue Client-Methoden in
  [`ui/autoload/ipc_client.gd`](../ui/autoload/ipc_client.gd):
  `settings_set_local_http_config(enabled, endpoint=null, request_timeout_seconds=null)`,
  `settings_probe_local_http()`.
- Der `settings_probe_result_received`-Payload trägt
  `axis="local_http"` für das Routing; andere Felder unverändert.

Sicherheitsgrenzen erweitert um:

- **Kein Endpoint-Leak.** Die Endpoint-URL taucht weder in Logs
  noch im `settings_probe_result` noch im `error`-Envelope auf.
- **Kein Completion-Roundtrip in der Probe.** Die Probe macht
  ausschließlich einen TCP-Connect — kein Prompt, keine
  LLM-Inferenz.
- **Kein TLS.** Die UI akzeptiert HTTP-URLs; der Core lehnt
  `https://` hart ab, weil PR 8 keine TLS-/Trust-Infrastruktur
  mitbringt.

### 8d.5d Text-Provider-Chain-Editor (PR 9, Ist-Zustand)

PR 9 gibt der Settings-Shell einen eigenen kleinen Chain-Editor
**direkt über** den beiden Per-Kind-Editoren (llamafile,
local_http). Bewusst klein: kein Drag-and-Drop, keine freie
Namenseingabe, keine Multi-Achsen-Matrix. Nur die bereits
bekannten Text-Provider-Kinds (`abrain` / `llamafile_local` /
`local_http`) stehen als Zeilen zur Verfügung.

Pro Row:

- **Enable-CheckBox** mit dem Kind-Namen — toggelt
  In-Chain-Mitgliedschaft.
- **↑-Button** — verschiebt die Zeile einen Slot nach oben.
  Deaktiviert, wenn die Row bereits oben steht **oder** der
  Eintrag nicht in der Kette ist.
- **↓-Button** — symmetrisch. Deaktiviert, wenn unterhalb kein
  weiterer in-Chain-Eintrag mehr kommt.

Unter der Row-Liste: **Apply / Reset / Statuslabel**.

- **Apply** — sammelt alle aktiven Zeilen in der aktuellen
  Reihenfolge und sendet `settings_set_text_provider_chain`. Der
  Controller hat einen UI-seitigen Empty-Guard (wenn der Nutzer
  alle Checkboxes deaktiviert, wird **kein** Request geschickt
  sondern `"chain empty — enable at least one provider"`
  gerendert); der Core-Validator ist Second-Line-of-Defense.
- **Reset** — sendet `settings_reset_text_provider_chain`. Der
  Core löscht den Override und fällt auf `["abrain"]` zurück; die
  Shell synchronisiert sich beim nächsten `apply_status`-Tick.

Defensive Regeln:

- **Single Source of Truth.** Nach Apply wird die Widget-
  Reihenfolge **nicht** lokal gefeiert — sie wird erst beim
  eintreffenden `status`-Envelope aus dem Core wieder aufgebaut
  (`_sync_text_chain_widgets_from_status`). So sieht die UI nie
  einen anderen Zustand als der Core.
- **Nur bekannte Kinds.** Das Widget-Modell ist fest an
  `_KNOWN_TEXT_KINDS` gebunden. Eine Abweichung zwischen UI und
  `crate::providers::text::KNOWN_TEXT_KINDS` wird im Core als
  `unknown text provider kind` sichtbar — beschädigt aber nie die
  Persistenz.
- **Keine freie Texteingabe.** Es gibt kein LineEdit für
  Provider-Namen.

EventBus-/IPC-Erweiterungen (additiv, PR 9):

- Neue Client-Methoden in
  [`ui/autoload/ipc_client.gd`](../ui/autoload/ipc_client.gd):
  `settings_set_text_provider_chain(chain: Array)` und
  `settings_reset_text_provider_chain()`.
- `StatusPayload.text_provider_chain` bleibt der einzige
  Readout-Kanal; keine neuen Felder.

### 8d.5e Cloud-HTTP-Editor + Secret-Pfad (PR 10 + PR 11, Ist-Zustand)

PR 10 führt den ersten Cloud-/Remote-Text-Provider `cloud_http`
ein — mit **visuell deutlich abgesetztem** „external · cloud"-
Block unter den lokalen Editoren. Der Block ist gold-orange
getönt und trägt einen kuratierten Warnhinweis:

> Achtung: externer / cloud Pfad. Requests verlassen diese
> Maschine in dem Moment, in dem dieser Provider in der Chain
> steht und enabled ist.

**Felder:**

- **`enabled` CheckBox** — Master-Schalter. Ohne Flag bleibt der
  Provider inert, auch mit Key im Store.
- **`endpoint` LineEdit** — `http://host:port/path` **oder**
  `https://host:port/path`. Seit PR 11 akzeptiert der Core beide
  Schemes; bei `https://` wird der Request über `tokio-rustls`
  mit dem webpki-roots-Trust-Store abgewickelt. Ein kleiner
  Insecure-Transport-Hinweis (siehe unten) wird sichtbar, sobald
  der Nutzer einen `http://`-Endpoint tippt.
- **`model` LineEdit** — optional.
- **`api_key` LineEdit mit `secret = true`** — Godot maskiert
  den Text. Wird **nie** von `apply_status` befüllt; der
  StatusPayload trägt das Feld schlicht nicht. Zwei Buttons
  daneben: **Save key** / **Clear key**.
- **Status-Label** — zeigt nur die kuratierten Strings
  `key: saved ✓` vs. `key: not set ✗` vs. `key: sent (field
  cleared)` vs. `key: clear requested`. Der Wert selbst
  erscheint an keiner Stelle.
- **Apply** (enabled/endpoint/model) + **Probe** (TCP-Connect
  gegen den geparsten Endpoint, kein Completion-Roundtrip, kein
  Bearer-Header auf der Leitung).

**Security-first-UX-Regeln:**

- **Secret-Feld wird sofort geleert.** Sobald der Nutzer auf
  „Save key" klickt, wird der Text aus dem LineEdit **zuerst**
  in eine lokale Variable kopiert und das Feld **sofort**
  geleert — bevor die IPC-Message den Core erreicht. Auch im
  Offline-Fall (kein IpcClient verfügbar) bleibt das Feld leer;
  der Nutzer tippt bei Bedarf neu. Kein Klartext lebt in der UI
  länger als eine Frame-Grenze.
- **Kein Rückspiegeln aus dem Status.** `_sync_cloud_http_widgets_from_status`
  berührt das `_cloud_http_secret_edit`-Widget ausdrücklich
  nicht. Selbst wenn der Status `cloud_http_secret_present=true`
  trägt, bleibt das Feld leer.
- **Bool-Flag statt Wert.** Die einzige Secret-Information, die
  aus dem Core zurückkommt, ist `cloud_http_secret_present: bool`.
  Die UI rendert daraus nur einen Status-Label-Text, nie einen
  maskierten Proxy-Wert (keine „●●●●●●●●"-Illusion von Länge).

**EventBus-/IPC-Erweiterungen (additiv, PR 10):**

- Neue Client-Methoden in
  [`ui/autoload/ipc_client.gd`](../ui/autoload/ipc_client.gd):
  `settings_set_cloud_http_config(enabled, endpoint, model,
  request_timeout_seconds)`,
  `settings_set_cloud_http_secret(api_key)` (akzeptiert `null`
  zum Clear) und `settings_probe_cloud_http()`.
- StatusPayload bekommt vier additive Felder
  (`cloud_http_in_chain` / `_enabled` / `_configured` /
  `_secret_present`) — alle nicht-sensitiv.

**PR 11 — Insecure-Transport-Hinweis:**

Direkt unter dem Endpoint-LineEdit sitzt ein kleines, gold-
getöntes Label, das leer ist, solange der Endpoint leer oder
`https://` ist. Sobald der Nutzer `http://...` tippt, erscheint
ein ehrlicher Hinweistext:

> insecure transport: http:// sends the api key in plaintext.
> Prefer https:// or a trusted reverse proxy.

**Keine moralische Flut, kein Toggle, kein Bypass-Schalter.**
Der Hinweis ist rein informativ — der Core führt für `http://`
weiterhin den bisherigen Plaintext-Pfad aus; er wird nicht
blockiert. Auch bei insecure-Konfiguration bleibt der
Secret-Pfad unverändert (Store, Masking, Keine-Rückspiegelung).

### 8d.5f STT-/TTS-Chain-Editor (PR 13, Ist-Zustand)

PR 13 bringt den Chain-Editor-Mechanismus aus PR 9 auf die
Audio-Achsen. Jede Section (STT und TTS) bekommt **oberhalb**
des bestehenden Per-Kind-Command-Editors einen kleinen
„stt/tts provider chain · Edit"-Block. Der Block ist
axis-parametrisiert über einen gemeinsamen Helper
`_build_audio_chain_editor_block(axis: String)`; die
axis-spezifischen State-Variablen (`_stt_chain_*` /
`_tts_chain_*`) und Whitelists (`_KNOWN_STT_KINDS` /
`_KNOWN_TTS_KINDS`) spiegeln die Core-Whitelists aus
[`crate::providers::stt::KNOWN_STT_KINDS`](../core/src/providers/stt.rs)
und
[`crate::providers::tts::KNOWN_TTS_KINDS`](../core/src/providers/tts.rs) —
heute pro Achse nur `command`.

Eine Zeile pro bekannter Kind mit:

- **Enable-CheckBox** (Kind-Name als Label) — toggelt
  In-Chain-Mitgliedschaft.
- **↑/↓-Buttons** — verschieben die Zeile; deaktiviert für
  Kopf-/Fuß-Positionen und für nicht-in-Chain-Zeilen.
- **Apply** (schickt `settings_set_{stt,tts}_provider_chain`)
  und **Reset** (schickt `settings_reset_{stt,tts}_provider_chain`).
- Kleines Info-Label: weist ehrlich darauf hin, dass heute nur
  `command` verfügbar ist — der Mechanismus bleibt aber für
  zukünftige Kinds vorbereitet.

Defensive Regeln identisch zur Text-Achse:

- **UI-seitige Empty-Guard.** Apply blockt eine leere Kette mit
  kuratiertem Text, bevor die IPC-Message den Core erreicht.
  Der Core-Validator bleibt Second-Line-of-Defense.
- **Single Source of Truth.** Nach Apply wird die Widget-
  Reihenfolge erst beim eintreffenden `status`-Envelope aus
  `stt_provider_chain` / `tts_provider_chain` wieder aufgebaut
  (`_sync_audio_chain_widgets_from_status(axis)`).
- **Nur bekannte Kinds.** Keine freie Texteingabe; eine
  Abweichung zwischen UI- und Core-Whitelist wird im Core als
  `unknown {stt|tts} provider kind` abgelehnt.

**Readout-Integration:** In der STT- und TTS-Section-Readout
rendert
[`settings_sections::_audio_provider_lines`](../ui/scripts/settings/settings_sections.gd)
das `stt_provider_chain` / `tts_provider_chain`-Feld als
führende „Chain"-Zeile (Pfeil-separiert); fehlt das Feld in
einem älteren Core, bleibt eine ehrliche „—"-Zelle stehen.

**EventBus-/IPC-Erweiterungen (additiv, PR 13):**

- Neue Client-Methoden in
  [`ui/autoload/ipc_client.gd`](../ui/autoload/ipc_client.gd):
  `settings_set_stt_provider_chain(chain: Array)`,
  `settings_reset_stt_provider_chain()`,
  `settings_set_tts_provider_chain(chain: Array)`,
  `settings_reset_tts_provider_chain()`.
- `StatusPayload` bekommt additiv `stt_provider_chain` /
  `tts_provider_chain`.

### 8d.5g Provider-Onboarding-Block (PR 26, Ist-Zustand)

PR 26 setzt **über** den bestehenden Text-Provider-Editoren einen
kuratierten, erklärenden Onboarding-Block in die Settings-Shell. Er
erweitert die Shell um eine Onboarding-Perspektive, ohne eine neue
Settings-Architektur einzuführen: keine neue Scene, keine neuen IPC-
Commands, keine neuen `StatusPayload`-Felder.

**Position im Layout.** Der Block lebt als erster Eintrag unter der
`TEXT_PROVIDER`-Sektion in
[`settings_panel_controller._render_sections`](../ui/scripts/settings/settings_panel_controller.gd) —
direkt über dem Chain-Editor aus PR 9 und über den Per-Kind-Editoren
(llamafile, local_http, cloud_http).

**Aufbau.** Der Block ist in zwei Dateien geteilt:

- **Pure Helper.**
  [`ui/scripts/settings/provider_onboarding.gd`](../ui/scripts/settings/provider_onboarding.gd)
  hält die Klassifikations-Logik (`primary_provider`,
  `chain_with_locality`, `locality_for`,
  `cloud_http_readiness`, `cloud_http_readiness_rows`,
  `add_cloud_disabled_reason`,
  `add_cloud_button_should_stay_disabled`) und die Konstanten
  (`LOCAL_FIRST_CHAIN`, `LOCAL_FIRST_HINT_TEXT`,
  `NO_AUTO_CLOUD_TEXT`, Button-Labels, Disabled-Reasons). Keine
  Scene-Nodes, kein EventBus — die Logik ist direkt im Smoke
  prüfbar.
- **Panel-Integration.** `_build_provider_onboarding_block()` im
  bestehenden `settings_panel_controller.gd` baut die Widgets
  einmal pro Re-Render, `_sync_provider_onboarding_from_status()`
  aktualisiert Werte in-place. Ein
  `provider_onboarding_snapshot()`-Helfer und ein
  `simulate_local_first_chain_for_test()`-Hook bedienen den
  Smoke-Test ohne SceneTree-Introspektion.

**Sichtbare Zeilen.**

- **Primary** — `text_provider_active` > `text_provider_chain[0]` >
  `text_provider_configured` > `—`; jeder Name mit `[local]` /
  `[cloud]` / `[unknown]` nachgestellt.
- **Chain** — `text_provider_chain` als `kind [locality]`-Pfeilliste.
  Unbekannte Kinds bekommen ehrlich `[unknown]`.
- **cloud_http first-run checklist** — vier Boolean-Rows plus eine
  Zusammenfassungszeile. `cloud_http_secret_present` wird **nur** als
  `present` / `not set` gerendert — niemals ein Wert.
- **Quick Actions.**
  - `Use local-first chain` sendet den bestehenden
    `settings_set_text_provider_chain`-Command mit der kuratierten
    Liste `["llamafile_local", "local_http", "abrain"]`. Kein
    `cloud_http`.
  - `Add cloud_http to chain` bleibt **per Design disabled** — die
    Shell aktiviert Cloud nicht automatisch; der Erklärtext aus
    `add_cloud_disabled_reason()` wandert mit dem Bereitschafts-
    Zustand mit.
- **No-auto-cloud Hinweis** — fester Erklärtext unter den Actions:
  „Cloud wird nicht automatisch aktiviert. cloud_http landet nur
  dann in der Chain, wenn du es explizit setzt — diese Shell
  schaltet das nicht für dich."

**Was der Block bewusst *nicht* tut.**

- Kein neuer Secrets-Pfad. Key-Änderungen bleiben im
  `cloud_http`-Editor darunter (`settings_set_cloud_http_secret`
  und `settings_clear_cloud_http_secret`).
- Keine API-Key-Anzeige — nur das Boolean `cloud_http_secret_present`.
- Keine neuen IPC-Commands. Der Core-Kontrakt bleibt unverändert.
- Keine Änderung der Text-Provider-Defaults oder der Compile-Time-
  Chain.
- Kein Auto-Add von `cloud_http` zur Chain — auch dann nicht, wenn
  alle vier Bereitschafts-Flags grün sind.

**Smoke-Abdeckung** (ergänzt in
[`scripts/settings_shell_smoke.gd`](../scripts/settings_shell_smoke.gd)):

- `_check_onboarding_pure_logic` — primary_provider /
  locality_for / chain_with_locality / cloud_http_readiness /
  add_cloud_disabled_reason auf Dictionary-Ebene.
- `_check_onboarding_block_renders_primary_and_chain` — Widgets
  bauen sich auf, primary + chain zeigen `[local]` / `[cloud]`.
- `_check_onboarding_cloud_readiness_rows_render` — vier Rows mit
  ehrlichen First-Run-Klassen.
- `_check_onboarding_cloud_secret_never_leaks_value` — API-Key-Row
  zeigt nur `present`, nie einen Wert.
- `_check_onboarding_local_first_hint_and_no_auto_cloud_present`
  / `_check_onboarding_add_cloud_button_stays_disabled_by_design`
  — Explain-Konstanten + Button-Policy.
- `_check_onboarding_local_first_quick_action_sends_expected_chain`
  — LOCAL_FIRST_CHAIN-Invariante inklusive „kein cloud_http".
- `_check_onboarding_empty_status_renders_dashes` — leerer Status
  crasht nicht.

### 8d.6 Verifikation

- `scripts/settings_shell_smoke.gd` (seit PR 13 zusätzlich um sechs
  Audio-Chain-Blöcke erweitert — Build+Sync / Empty-Guard pro
  STT und TTS, Single-Kind-Info-Hinweis, Readout-Chain-Zeile;
  seit PR 11 um zwei weitere
  Cloud-HTTP-Blöcke erweitert — Insecure-Hint erscheint bei
  `http://`-Endpoints, Insecure-Hint bleibt bei `https://` leer;
  +3 Assertions seit PR 10, alle grün):
  Section-Reihenfolge,
  Slug-Eindeutigkeit, defensive `*_lines`-Renderer für leere /
  partielle / vollständige StatusPayloads inklusive PR-4-Felder
  (`text_provider_chain`, `llamafile_in_chain`, `llamafile_lifecycle`,
  `llamafile_mode`, `llamafile_idle_timeout_seconds`,
  `llamafile_enabled`, `llamafile_configured`), Privacy-Rollup mit
  Lokal-/Cloud-Aussage, Scene-Verhalten des Panel-Controllers
  (Default unsichtbar, `open_panel` / `close_panel`,
  `close_requested`-Signal, crash-freies `apply_status` /
  `apply_extras` bei Nicht-Dictionary-Eingaben, Rückfall-Pfad für
  alte Cores ohne PR-4-Felder). Seit PR 5: Editor-Block wird beim
  `open_panel()` gebaut, Widgets synchronisieren sich mit
  `apply_status`-Payloads (Enabled / Mode / Idle-Timeout),
  Probe-Ergebnisse werden 1:1 mit Core-Tag gerendert, Pfad-Leak-
  Disziplin im Probe-Label verifiziert. Harness-Case
  `settings-shell-smoke` in `scripts/run_overlay_verification.sh`.
- Core-Tests (PR 8 gelandet): 210 PASS (+25 gegenüber PR 7,
  +40 gegenüber PR 6, +60 gegenüber PR 5). Zusätzlich zur
  PR-7-Basis: neun Unit-Tests im Text-Provider-Modul für
  `local_http` (Endpoint-Parser mit `https://`-Rejection, User-
  Info-Rejection, Port-Default, Non-200-Pfad), drei neue
  `settings_store`-Unit-Tests für den Override-Roundtrip, drei
  neue Protocol-Parser-Tests (`settings_set_local_http_config`
  full/minimal + `settings_probe_local_http`), fünf neue
  IPC-Ende-zu-Ende-Tests (Apply-Echo ohne Endpoint-Leak,
  Zero-Timeout-Reject, Probe `not_configured`/
  `endpoint_scheme_unsupported` ohne Leak,
  `http_connect_failed`/`timeout` bei geschlossenem Port). Der
  zugehörige UI-Smoke ergänzt vier Blöcke
  (Editor-Bau + Sync, axis-Routing zum local_http-Label,
  Scheme-unsupported ohne Leak, `text_provider_lines`-
  Sichtbarkeit für `local_http_in_chain`). Weiter ab PR 7: zusätzlich
  zur PR-6-Basis:
  vier neue `settings_store`-Unit-Tests für die STT-/TTS-Override-
  Roundtrips und Apply-Merge-Semantik, fünf neue Protocol-Parser-
  Tests für `settings_set_{stt,tts}_config` /
  `settings_probe_{stt,tts}` inklusive `axis`-Feld im Encoded-
  Probe-Result, fünf neue IPC-Ende-zu-Ende-Tests (`settings_set_*`-
  Echo, Probe-Ergebnisse mit `axis`-Tag, Secret-Disziplin:
  Command-String leakt weder in `message` noch in `class`). Die
  STT-/TTS-Probe-Tests laufen weiterhin gegen `/bin/true` / `/bin/false`
  als Dummy-Kommandos — keine Audio-Hardware nötig.
- Bestehende Smokes (`visual-action-mode-smoke`,
  `avatar-render-polish-smoke`, `avatar-appearance-smoke`,
  `avatar-identity-smoke`, `avatar-template-capabilities-smoke`,
  `avatar-preferences-smoke`, `dev-controls-smoke`,
  `workflow-state-smoke`, `resolver-smoke`, `utterance-bubble-smoke`)
  bleiben grün.

---

## 9. Always-on-top- und Overlay-Verhalten (Ziel-Zustand)

Phase 3.3 liefert das **Presence-MVP** in-window: die Modi
**Docked / Expanded / Action / Disconnected** laufen bereits als
eigenständige State-Maschine (`ui/scripts/presence/`). Presence-State
(UI-Umfang) und Avatar-State (visueller Ausdruck) sind bewusst
orthogonal geführt.

Was das MVP umsetzt:

- eigener `PresenceController` als Autoload-artiger Node in `main.tscn`,
- Hold-Timer für Completed / Failed / Cancelled als Nachhall nach einer
  Action, bevor die Presence in den gewählten Base-Mode zurückfällt,
- Action-Banner mit Titel, Step und **symbolischem** Target-Text
  (`→ Anwendung`, `→ Fenstertitel`, `→ Label (Rolle)`, `→ Region`) —
  ohne Pixelgeometrie,
- angereicherter Target-/Mapping-Readout im selben Banner: ein kleines
  Kind-Chip (`[application]`, `[window]`, `[ui_element]`, `[region]`,
  `[unknown]`) plus Primärname und Sekundärdetail, sowie eine separate
  Mapping-Zeile mit `mapping.space` und `mapping.hint` (bei Window-
  Scope ergänzt um `mapping.window`). Fehlen Target- oder Mapping-
  Felder, bleibt der jeweilige Bereich unsichtbar — kein Fehlerpfad,
- der Avatar wendet im ACTING-State eine sehr leise, rein symbolische
  Farbvariante je nach Target-Kind an (Application/Window/UiElement/
  Region). Keine Bewegung, keine Koordinaten,
- manuelle Umschaltung zwischen Docked und Expanded über den
  Header-Toggle; Docked blendet Log und Eingabezeile aus.

Noch **nicht** umgesetzt und explizit ausserhalb des MVP:

- randloses Fenster,
- transparenter Hintergrund,
- optionales Click-through (togglebar),
- Snap-to-Edge / Idle-Movement / Multi-Monitor-Heuristik.

Die Architektur ist so vorbereitet, dass ein späteres natives Overlay
(GDExtension oder Window-Mode-Wechsel) nur Rendering und Fenstermodus
berühren muss — die Presence-Logik bleibt unverändert und zieht ihren
Modus weiterhin aus den Core-Events. Das Zielbild bleibt
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md),
§6.

Wichtig: **natives Overlay ist nicht automatisch Teil von Godot selbst.**
Fähigkeiten wie Always-on-top, Click-through, transparenter Desktop-
Überzug und Pixel-Positionierung hängen an Protokoll (Wayland vs. X11)
und Compositor (Mutter, KWin, wlroots, …) und sind unter Ubuntu 24.04
Wayland nicht pauschal verfügbar. Die UI-Architektur bleibt deshalb
bewusst **host-window-neutral**: Scenes und Presence-Controller kennen
kein Always-on-top, keine Input-Region, keine Portal-Aufrufe. Die
Linux-spezifische Fenster- und Overlay-Strategie — inklusive der
geplanten separaten Window-Behavior-Abstraktion — ist in
[`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
dokumentiert.

### 9.0 Interne Rollenverteilung in `ui/scripts/window_behavior/`

Die Schicht ist inzwischen gewachsen und intern nach **vier Rollen**
plus Fassade und gemeinsamem Vokabular getrennt. Diese Übersicht
ersetzt keine Detaildoku der einzelnen Pfade — sie macht nur
sichtbar, wo welcher Baustein sitzt, damit spätere Arbeit nicht
halbparallele Sonderpfade neben einander baut:

- **Detection / Capability** — `window_capabilities.gd`. Session-Typ,
  Display-Driver, Capability-Status (`available` / `experimental` /
  `unsupported` / `unknown`). Keine Schreibzugriffe.
- **Probe / Verification** — `window_probe.gd`. Opt-in, reversibel,
  diagnostisch. Keine Produktaktivierung.
- **Activation (pro Pfad ein eigenes Env-Flag)**:
  - `overlay_controller.gd` (`SMOLIT_UI_OVERLAY`)
  - `overlay_click_through_controller.gd` (`SMOLIT_UI_CLICK_THROUGH`)
  - `overlay_always_on_top_controller.gd` (`SMOLIT_UI_ALWAYS_ON_TOP`)

  Jeder Pfad hat eigene Gates und verweigert ehrlich; kein stiller
  Nebeneffekt zwischen den drei.
- **Reporting** — `overlay_runtime_report.gd`. Opt-in
  `SMOLIT_WINDOW_REPORT=1`; konsolidierter Diagnose-Block ohne
  Scene-Eingriff.
- **Fassade** — `window_behavior.gd`. Einziger Einstieg aus
  `main.gd`. Enthält `apply_all(anchor)` als kanonische Reihenfolge
  (Probe → Backend-Resolve → Overlay → Click-through → AOT → Report)
  sowie `resolve_backend(capabilities)` als reine Diagnose-API.
- **Gemeinsames Vokabular** — `window_behavior_result.gd`. Definiert
  die Standard-Achsen pro Aktivierungspfad:
  `requested / capable / applied / observed / active / reason`
  (siehe unten).
- **Backend-Familie (intern, Vorbereitung)** —
  `backend_base.gd` + `backend_noop.gd` + `backend_x11.gd` +
  `backend_wayland_mutter.gd` + `backend_wayland_wlroots.gd` +
  `backend_xwayland.gd` + `backend_wayland_generic.gd` +
  `backend_resolver.gd`. Der Resolver wählt pro `apply_all()`-Lauf
  **ein** Backend anhand des Capability-Snapshots:
  - `session_type == "x11"` → `backend_x11`.
  - `session_type == "wayland"` + `display_driver == "x11"`
    → `backend_xwayland` (Godot als X11-Client in einer Wayland-
    Session).
  - `session_type == "wayland"` + GNOME-artiger Desktop (Mutter)
    → `backend_wayland_mutter`.
  - `session_type == "wayland"` + wlroots-artiger Desktop
    (Sway / Hyprland / Wayfire / river / labwc) →
    `backend_wayland_wlroots`.
  - `session_type == "wayland"` + alles andere (KDE/Wayland,
    unbekannte Compositoren) → `backend_wayland_generic` als
    ehrlicher Fallback.
  - sonst → `backend_noop`.

  Alle Backends delegieren aktuell 1:1 an die existierenden
  Controller — die Aufteilung ist **ehrliche interne
  Plattformstruktur**, keine neuen Features. Keine neue IPC-/
  EventBus-/Presence-Logik. Spätere compositor-spezifische Pfade
  (`backend_wayland_wlroots` mit echter `wlr-layer-shell`-Integration,
  `backend_wayland_mutter` mit offizieller GNOME-Extension-Anbindung,
  falls jemals angebracht) haben jetzt klar benannte Zielorte.

  **Verifikation der Backend-Familie**: der opt-in Runtime-Report
  (`SMOLIT_WINDOW_REPORT=1`) zeigt die gewählte `backend.id` und
  `backend.description` als eigenen Block, damit man pro Lauf
  sehen kann, welches Backend der Resolver gewählt hat. Der
  Resolver-Klassifikations-Smoketest
  [`scripts/resolver_classification_smoke.gd`](../scripts/resolver_classification_smoke.gd)
  überprüft die Zuordnung gegen neun synthetische Capability-
  Snapshots. Messmatrix und Evidenzniveau pro Backend stehen in
  [`docs/window_behavior_backend_verification.md`](./window_behavior_backend_verification.md).

  **Experimenteller Sonderpfad.** Backends dürfen optional einen
  `experimental_stance`-String tragen; der Runtime-Report zeigt
  ihn als zusätzliche Zeile `backend.experimental = …`. Aktuell
  ist das **ausschließlich** `backend_wayland_wlroots.gd` —
  benannter Platzhalter für einen späteren
  `wlr-layer-shell-unstable-v1`-Pfad. Kein produktiver Code, keine
  Aktivierung, kein Compositor-spezifischer Effekt heute; die
  Aktivierungs-Ergebnis-Dicts enthalten additiv einen
  `wlroots_research`-Marker (`state = "prepared, not implemented"`).
  Forschungs- und Decision-Dokument:
  [`docs/wlroots_overlay_path.md`](./wlroots_overlay_path.md).

`main.gd` ruft in `_ready()` nur noch `SmolitWindowBehavior.apply_all(
self)` auf und hält den Click-through-Controller (falls aktiv) als
Lifetime-Anker, damit dessen Signal-Subscriptions bestehen bleiben.
Keine Plattformdetails wandern in Scene-Code.

Gemeinsame Achsen pro Aktivierungspfad (siehe
`window_behavior_result.gd`):

- `requested` — Nutzer hat den Pfad explizit per Env angefordert.
- `capable`   — Vorbedingungen (Capability, Session, Flag-Known)
  erfüllt.
- `applied`   — DisplayServer-Seite wurde tatsächlich geschrieben.
- `observed`  — Rücklesewert bestätigt die Schreibung.
- `active`    — Konsolidierter Endzustand.
- `reason`    — Einzeiler, warum der Pfad so endete.

Pfad-spezifische Zusatzachsen (Bounds, Zonenliste, Session-Details)
bleiben erhalten — sie ergänzen das Skeleton, ersetzen es nicht.

### 9.1 Window Behavior Spike v1 (opt-in)

Ein erster kleiner Capability-/Probe-Pfad ist in
[`ui/scripts/window_behavior/`](../ui/scripts/window_behavior/)
gelandet und bewusst aus der Presence-Schicht herausgehalten:

- `window_capabilities.gd` liest Session-Typ, DisplayServer und
  Projekt-Setting `display/window/per_pixel_transparency/allowed` und
  tagt Transparenz, Click-through und Always-on-top pro Eintrag als
  `available` / `experimental` / `unsupported` / `unknown`.
- `window_probe.gd` ist ein opt-in Runtime-Probe. Er läuft **nur**,
  wenn die Umgebungsvariable `SMOLIT_WINDOW_PROBE=1` gesetzt ist,
  setzt testweise `WINDOW_FLAG_TRANSPARENT` und
  `WINDOW_FLAG_MOUSE_PASSTHROUGH`, liest sie zurück und revertet die
  Änderungen standardmäßig.
- `window_behavior.gd` ist eine dünne Fassade — die einzige Klasse,
  die `main.gd` kennt.

Die Presence-, Avatar- und EventBus-Ebene kennt diese Schicht
**nicht**. Sie erzeugt weder neue IPC-Nachrichten noch neue
UI-Elemente. Ergebnisse landen ausschließlich per `print()` im
Log. Immer-obenauf wird hier ausdrücklich **nicht** gesetzt — die
Capability-Detection markiert das unter GNOME/Wayland zu Recht als
nicht zuverlässig. Details zur Einordnung des Spikes innerhalb der
Phasen A/B/C siehe
[`docs/linux_window_overlay_architecture.md` §F.1](./linux_window_overlay_architecture.md).

### 9.2 Overlay MVP Phase B (opt-in transparentes Presence-Fenster)

Auf dem Capability-Spike sitzt jetzt ein **opt-in Overlay-MVP** als
reine Host-/Fensterschicht. Die Presence-, Avatar- und Scene-Ebene
bleibt unverändert — Overlay ändert nur die äußere Fensterhülle.

Komponenten:

- `overlay_controller.gd` (neu) — schaltet Transparenz und Borderless
  capability-gesteuert ein. Aktiv nur, wenn `SMOLIT_UI_OVERLAY=1`
  gesetzt ist *und* die Transparenz-Capability im aktuellen Setup
  tragfähig ist.
- `window_behavior.gd` (erweitert) — trägt
  `activate_overlay_if_requested(anchor)` als Fassaden-Einstiegspunkt;
  `main.gd` ruft den Einstieg am Ende von `_ready()` auf.

Im Erfolgspfad passiert exakt dies:

- Projekt-Setting `display/window/per_pixel_transparency/allowed=true`
  (Pflicht-Opt-in zur Ladezeit — ohne dieses Setting hätte ein
  Runtime-Flag keine sichtbare Wirkung).
- `Viewport.transparent_bg = true` auf dem Root-Window.
- `DisplayServer.WINDOW_FLAG_TRANSPARENT = true`.
- `DisplayServer.WINDOW_FLAG_BORDERLESS = true`.

Fallback-sicher: ohne Opt-in ist der Einstieg ein No-op; wenn die
Capability-Detection Transparenz als `unsupported` oder `unknown`
meldet, bleibt das Fenster im normalen Modus und der Grund landet
im Log. Kein Always-on-top, kein stilles Click-through, keine
Scene-Eingriffe, keine neuen EventBus-Signale. (Für produktives
Click-through mit definierten interaktiven Zonen siehe §9.3.)

Sichtbarer Effekt auf der UI: die PanelContainer-Flächen
(Action-/Approval-/Discovery-/Dock-/Compact-Input-Panel) behalten
ihre halbopake `StyleBoxFlat`-Tönung aus
[`ui/themes/compact_panel.tres`](../ui/themes/compact_panel.tres),
während die leeren Bereiche zwischen ihnen transparent werden. Der
Docked-Avatar steht damit als echte Floating Entity frei auf dem
Desktop, ohne Fensterrahmen. In Expanded wirkt das Log/Input-Panel
weiterhin als kompakter opaker Block — kein Re-Design nötig.

Vollständige Einordnung inklusive Phase-B/C-Grenzen siehe
[`docs/linux_window_overlay_architecture.md` §F.2](./linux_window_overlay_architecture.md).

### 9.3 Overlay Click-through (opt-in Folgeschritt auf §9.2)

Aufbauend auf dem Overlay-MVP sitzt ein **zweiter opt-in Schritt** in
`window_behavior/` — produktives Click-through mit definierten
interaktiven Zonen. Die Scene-Ebene bleibt unverändert; es wird nur
die äußere Fensterhülle um eine Passthrough-Region ergänzt.

Komponenten:

- `overlay_click_through_controller.gd` (neu) — trägt eine explizite
  Allowlist interaktiver Anker (Avatar, Header, Action-/Approval-/
  Discovery-Banner, DockPanel, CompactInputPanel), validiert pro Zone
  (`is_visible_in_tree()`, Rohsize > 0, Viewport-Clamp,
  Mindestkantenlänge), baut daraus eine **Bounding-Rect-Union** und
  ruft `DisplayServer.window_set_mouse_passthrough(region)` mit einem
  einzelnen Rechteckpolygon auf. Godots API erlaubt pro Fenster genau
  *einen* Polygonpfad — echte Multi-Polygon-Shapes bleiben Folgearbeit,
  und leerer Raum *innerhalb* der Union bleibt klickbar.
- `window_behavior.gd` (erweitert) — trägt
  `activate_click_through_if_requested(anchor, overlay_result)` als
  Fassaden-Einstieg, kettenbar auf
  `activate_overlay_if_requested(anchor)`.
- `main.gd` (minimale Erweiterung) — ruft die beiden Fassadenpunkte am
  Ende von `_ready()` nacheinander auf und hält eine Referenz auf den
  Controller, damit seine Signal-Subscriptions (`visibility_changed` pro
  Zone, `resized` am Anker) und der einmalige `call_deferred`-Refresh
  für die Scene-Lebenszeit leben. Die UI hat sonst keinerlei Kopplung
  zur Click-through-Schicht.

Zwei ausdrückliche Opt-ins, nie still verkettet:

- `SMOLIT_UI_OVERLAY=1` — Voraussetzung aus §9.2.
- `SMOLIT_UI_CLICK_THROUGH=1` — eigene Opt-in-Grenze. Ohne diese
  Variable bleibt der Overlay-MVP genau wie bisher, ganz ohne
  Passthrough.

Fallback-sicher: ist Overlay nicht angefordert / nicht aktiv, oder
meldet die Capability-Detection Click-through als `unsupported` /
`unknown`, oder lässt sich aus dem aktuellen Layout keine gültige Zone
ableiten, bleibt das Fenster vollständig interaktiv und der Grund landet
im Log. Logging ist pro Aktivierung auf *eine* Phasen-Zusammenfassung
mit `requested / overlay_requested / overlay_active / capable /
zones_derived / zones_valid / active` konsolidiert; Refreshes loggen
nur bei echter Bounds-Änderung (Dedup).

Sichtbarer Effekt auf der UI: der Avatar und die sichtbaren Panels
bleiben klickbar; Klicks außerhalb dieser Bounding-Box fallen durch
auf das darunterliegende Fenster. Leerer Raum *innerhalb* der Box
bleibt im aktuellen MVP noch klickbar — das ist bewusst nicht das
finale Interaktionsmodell (siehe §F.3). Presence-, Avatar- und
EventBus-State bleiben unberührt. Vollständige Einordnung siehe
[`docs/linux_window_overlay_architecture.md` §F.3](./linux_window_overlay_architecture.md).

Für die **reale Verifikation** auf einer echten Wayland-/X11-Session
gibt es einen kleinen opt-in Diagnosebaustein im gleichen
`window_behavior/`-Verzeichnis:

- `overlay_runtime_report.gd` (neu) — rein diagnostisch. Druckt am
  Ende von `_ready()` *einen* konsolidierten Konsolenblock mit
  Session/Desktop, Capabilities und dem Zustand von Overlay, Click-
  through **und** Always-on-top (jeweils inkl. Bounds- und Zonenliste
  bzw. X11-Session-Gate). Kein-op ohne `SMOLIT_WINDOW_REPORT=1`,
  keine Scene-Logik, keine neuen Signale.

Zusätzlich existiert ein **X11-only Always-on-top Sonderpfad** —
eigenes Opt-in, unabhängig von Overlay und Click-through:

- `overlay_always_on_top_controller.gd` (neu) — aktiv nur, wenn
  `SMOLIT_UI_ALWAYS_ON_TOP=1` gesetzt ist *und* die Session wirklich
  X11 ist (nicht headless, nicht Wayland, nicht unknown). Unter
  GNOME/Wayland bleibt der Pfad ausdrücklich ein No-op mit klarem
  Log-Grund. Keine neue Presence-Wahrheit, keine IPC-/EventBus-
  Erweiterung, kein Nebeneffekt des Overlay- oder Click-through-
  Pfads. Entscheidungsgrundlage:
  [`docs/linux_always_on_top_decision.md`](./linux_always_on_top_decision.md).

Einordnung und Testfälle:
[`docs/linux_overlay_verification_matrix.md`](./linux_overlay_verification_matrix.md).

---

## 10. Designprinzipien

- **Core-driven**: UI reagiert, sie entscheidet nicht.
- **Transport-entkoppelt**: Scenes kennen nur den EventBus, nicht den
  WebSocket.
- **Additiv**: neue Fähigkeiten kommen über zusätzliche Events, nicht über
  Umschreiben bestehender.
- **Graceful failure**: fehlende Core-Verbindung, ungültige Frames oder
  fehlende Audiocommands dürfen die UI nicht abstürzen lassen.
- **Minimalismus**: keine klassische Fensterflut, Fokus auf Präsenz statt
  auf Bedien-UI.
- **Action-driven Avatar**: Avatar-Zustände und -Reaktionen sind
  Core-/Action-getrieben. Die UI animiert, sie entscheidet nicht über
  Handlung, Ziel oder Erfolg einer Desktop-Aktion — das kommt als
  Event-Strom aus Core und Desktop Interaction Layer.
- **Interaction Layer bleibt im Core**: Desktop-nahe Ausführung
  (`core/src/interaction/`) läuft strikt serverseitig. Die UI sendet
  höchstens einen symbolischen Auslöser
  (`interaction_open_application`, `interaction_focus_window`, siehe
  [`docs/api.md`](./api.md), §2.6) und konsumiert die zurückkommenden
  Action Events — sie führt nichts selbst aus. Selbst der
  Fenster-Fokus ist Core-entscheidung: die UI stellt nur das
  Approval-Banner dar, der Core entscheidet per Policy und Backend
  über Ausführbarkeit, Verifikation und Recovery.

---

## 11. Offene Punkte

- **Avatar-Rendering** — Platzhalter-Grafik; echte Sprite-/
  Charakteranimation steht aus.
- **Natives Overlay** (Folge zu 3.3) — Always-on-top, Transparenz,
  Click-through, Snap-to-Edge. Presence-Logik ist bereits in-window
  fertig; das Desktop-Overlay hängt nur noch am Fenstermodus.
- **Tieferer Speech-Sync** — der MVP-Lifecycle `speaking_started` /
  `speaking_ended` ist in PR 14 gelandet (siehe §8.4a). Offen bleiben
  Phonem-/Lip-Sync, Audio-Timeline und tiefer gehende
  Ausdrucksbewegungen (Phase C); der heutige Pfad transportiert nur
  „TTS läuft / TTS ist fertig".
- **Behavioral Expression Layer v2+** — v1 (sechs kuratierte
  Ausdrucksmodi, UI-only) ist in PR 15 gelandet (siehe §8.4b). Offen
  bleiben feinere Zustände wie `alert`, antwortabhängige Reaktionen
  auf Basis von Text-Tonalität, und ein optionales Emotion-Mapping
  aus ABrain — der nächste Punkt.
- **Emotion-Feld** — heute transportiert das Protokoll keine Emotion in
  `response`-Payloads. Sobald ABrain Emotionen liefert, wird das Feld in
  [`docs/api.md`](./api.md) additiv ergänzt.
- **Headless/Export** — Export-Pipeline und CI-Smoke für Godot stehen aus.
