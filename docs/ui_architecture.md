# Smolit Assistant – UI- und Avatar-Architektur

Dieses Dokument beschreibt den **heutigen Stand** der UI nach Phase 3.1 sowie
den geplanten Ausbau. Alles, was noch nicht implementiert ist, ist explizit
als Ziel-Zustand markiert.

Für das übergeordnete Zielbild von Smolit als sichtbare Desktop-Präsenz
und für das Zusammenspiel mit echter Desktop-Automation siehe
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md).
Dieses Dokument hier bleibt auf die **UI-/Godot-Ebene** fokussiert.

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
│   └── workflow_overlay/
│       └── workflow_overlay_root.tscn
├── scripts/
│   ├── main.gd
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

## 6a. Workflow Overlay als passiver Action-Readout (MVP-Spike, Ist-Zustand)

Dieser Abschnitt beschreibt die Rolle des Workflow-Overlays an der
Schnittstelle zum Event-Strom. Seit dem MVP-Spike existiert der
Renderer im Repo
(`ui/scripts/workflow_overlay/`,
`ui/scenes/workflow_overlay/workflow_overlay_root.tscn`,
eingebettet in `main.tscn` unterhalb des Avatars). Die Leitlinien
unten gelten unverändert für den Spike — er ist bewusst klein und
ergänzt §8a um ein konkretes erstes Rendering.

- **Definition.** Rein visuelle, read-only Darstellung von Core-
  Zuständen. Das Overlay ist keine zweite Session-Logik, sondern
  eine Projektion.
- **Quelle der Wahrheit.** Ausschließlich Core / EventBus. Das
  Overlay erzeugt keinen eigenen Zustand, sondern leitet sein
  Bild aus den vom Core emittierten Action Events ab.
- **Ziel.** Verständlicher Handlungszusammenhang (Trigger → Schritt
  → Aktion → Ergebnis) statt rein textueller Log-Ausgabe, damit
  der Nutzer sieht, *was* gerade passiert — nicht *wie* eine
  Low-Level-Interaktion implementiert ist.
- **Position.** Links vom Avatar/Icon bzw. als linker Overlay-
  Flügel innerhalb derselben Presence-Hülle. Kein separates
  Toplevel-Fenster, keine neue Plattformfähigkeit.
- **MVP.** Kleine feste Darstellung (2–4 Knoten im Standardfall),
  kein freier Canvas. Siehe §8a für Detailscope.
- **Visuals.** Knoten, gerichtete Kanten, Hervorhebung des aktiven
  Schrittes, semantische `Success-` / `Failure-` / `Active-`
  Zustände — ohne feste Farbzusage an dieser Stelle, Farbregeln
  leben in der späteren Implementierungsdoku.
- **Interaktion.** Im MVP keine Interaktionsversprechen. Spätere
  Formen wie Collapse/Expand oder Inspect sind architektonisch
  nicht ausgeschlossen, aber ausdrücklich nicht Teil des MVP.

Was §6a explizit **nicht** verspricht:

- keine Ausführung, kein Executor, kein Zugriff auf den Desktop —
  Desktop-Interaktion bleibt vollständig im Core / Interaction
  Layer;
- kein eigenes Protokoll neben den Action Events;
- keine Pflichtaktivierung — das Overlay bleibt Teil derselben
  Presence-Hülle und erscheint in denselben Presence-Kontexten
  (Action Mode, siehe
  [`presence_desktop_interaction.md`](./presence_desktop_interaction.md)).

---

## 7. Avatar-System (Phasen)

Avatar-Rendering ist **noch nicht implementiert**. Die Phasen unten sind
die geplante Ausbaustrecke, nicht der heutige Stand.

### Phase A – MVP-Log (Ist-Zustand 3.1)

- `StatusLabel` zeigt `connected` / `disconnected`.
- `RichTextLabel` rendert eingehende Events farbcodiert als Event-Log.
- `LineEdit` + Buttons „Send" / „Ping" bedienen `submit_text` und `ping`.
- Kein Avatar, keine Animation, keine Sprechblase.

### Phase B – 2D-Avatar + Zustände (Ziel 3.2)

- 2D-Sprite als Kind-Scene, zentrale State-Machine auf EventBus-Signalen
  (`thinking_received`, `response_received`, `error_received`,
  `heard_received`).
- Animationen für: `idle`, `thinking`, `talking`, `error`.
- Speech-Bubble ersetzt das RichText-Log als Primär-Anzeige; das Log
  kann als Debug-Panel bleiben.
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

### Phase C – Erweiterter Ausdruck (Ziel > 3.x)

- Feinere Zustände (z. B. `curious`, `focused`, `alert`).
- Speech-Sync mit TTS-Lebenszyklus (setzt TTS-Events im Protokoll voraus —
  aktuell nicht vorhanden).
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

---

## 8a. Workflow-Overlay-System (MVP-Spike, Ist-Zustand)

Dieser Abschnitt beschreibt das Workflow-Overlay als eigenständigen
UI-Baustein. Seit dem ersten MVP-Spike existieren die drei
Renderer-Scripts (`workflow_overlay_controller.gd`,
`workflow_overlay_state.gd`, `workflow_node_view.gd`,
`workflow_edge_view.gd`) und die Szene
(`workflow_overlay_root.tscn`) im Repo. Die Nummer §8a markiert
einen zusätzlichen Abschnitt neben §8 (Zustands- und Eventmodell
Ist-Zustand) und kollidiert nicht mit bestehenden Cross-References
auf §8/§9/§10/§11. Die ursprünglich in der Planungsphase geschriebenen
Regeln (unten) gelten weiterhin; wo der Spike Feinentscheidungen
getroffen hat, sind sie benannt.

### 8a.1 Rolle

- Sichtbarer Ablauf: Workflow-Overlay macht den aktuellen Handlungs-
  zusammenhang auf einen Blick erkennbar.
- Ergänzung zum Avatar, nicht Ersatz. Avatar bleibt die primäre
  Presence-Figur; das Overlay ist eine begleitende Sicht.
- Keine zweite Wahrheit: der Core bleibt Source of Truth, das
  Overlay ist reine UI-Projektion.

### 8a.2 Darstellung

- **Knotenarten (symbolisch).** `Trigger`, `Step`, `Action`,
  `Result`. Keine feste Typhierarchie im MVP, nur diese vier
  Kategorien.
- **Kanten.** Gerichtet, folgen dem zeitlichen Ablauf der Action
  Events.
- **Semantische Zustände pro Knoten/Kante.** `geplant` / `aktiv` /
  `erfolgreich` / `fehlgeschlagen` / `abgebrochen` / `unklar`.
  Farbzuweisung und konkrete Glyphensprache werden in der späteren
  Implementierungsdoku festgelegt, nicht hier fixiert.
- **Aktivität.** Kleine, dezente Animationen auf Kanten /
  Fokus-Knoten. Keine aufmerksamkeitsheischende Choreografie.

### 8a.3 Scope-Grenzen

- **Kein Editor.** Knoten und Kanten sind nicht nutzer-editierbar,
  nicht verschiebbar, nicht verkabelbar.
- **Kein unendlicher Canvas.** MVP-Darstellung passt in eine feste,
  kleine Fläche links vom Avatar. Kein Zoom, kein Pan.
- **Kein Graph-Authoring.** Smolit wird durch das Overlay
  ausdrücklich **kein** visueller Workflow-Builder.
- **Kein Debug-Graph als neue Runtime-Wahrheit.** Das Overlay
  rekonstruiert bestehende Action-Event-Abläufe; es ist keine
  eigene Execution-Engine.
- **Kein zweites Logiksystem.** Keine Policy, kein Scheduler, keine
  Retry-Logik in der UI — Recovery / Retry / Verification gehören
  in den Core / Interaction Layer.

### 8a.4 Datenbindung

- **EventBus-Quelle.** Das Overlay konsumiert die bestehenden
  Action Events (`action_planned`, `action_started`, `action_step`,
  `action_completed`, `action_failed`; optional später zusätzlich
  `action_verification`, `action_cancelled`). Siehe
  [`api.md`](./api.md) §2.5 und „UI-Projektion: Workflow Overlay".
- **Lokaler UI-State nur als Projektion / Ableitung.** Der
  Workflow-State in der UI ist keine persistierte Wahrheit,
  sondern die reine Ableitung aus dem beobachteten Event-Strom
  seit Session-Start oder seit dem letzten `action_planned`.
- **Kein Workflow-DSL-Zwang im MVP.** Das Overlay erwartet keinen
  vorab gelieferten Workflow-Graphen. Es rekonstruiert einen
  kleinen symbolischen Kurz-Flow aus dem bestehenden Eventstrom
  (Trigger aus dem auslösenden Event, Schritte aus `action_step`,
  Result aus `action_completed`/`action_failed`).

### 8a.5 Nicht-Ziele

- **Kein n8n-Klon.** Weder Authoring noch programmierbare Knoten,
  weder Webhook-Management noch Integrations-Katalog.
- **Keine Desktop-Automation in Godot.** Keine Klicks, keine
  Tastatureingaben, kein OCR, kein Fensterzugriff aus der UI —
  genau wie §4 der Nicht-Ziele festhält.
- **Kein generisches Node-Framework in Phase 1.** Keine
  wiederverwendbare Graph-Infrastruktur, keine Plug-in-Architektur
  für fremde Graphen, kein Export.

### 8a.6 Darstellungsmodi (Collapse / Expand) — PR 2

Seit PR 2 kennt das Overlay zwei bewusst kleine Darstellungsstufen.
Sie werden **automatisch** aus der aktuellen Phase abgeleitet
(siehe `workflow_overlay_state.display_mode_for_phase`) — es gibt
keinen Nutzerschalter, keine neue Presence-State-Maschine und keine
zweite State-Quelle:

- **`COLLAPSED`** — sehr kompakte Kurzprojektion. Wird bei
  `PLANNED` (und defensiv bei `HIDDEN`) verwendet. Kleinere
  Mindestgrößen der Node-Kapseln, kürzere Schrift, schmalere
  Kanten, knappere Zeilenseparation.
- **`EXPANDED`** — lesbarere Kurzprojektion. Wird bei `ACTIVE`,
  `COMPLETED`, `FAILED`, `UNKNOWN` verwendet. Größere
  Mindestgrößen, etwas mehr Schrift, optionale zusätzliche Hint-
  Zeile.

Zweck: in der ruhigen Planungsphase bleibt das Overlay klein und
unauffällig; sobald wirklich etwas passiert (aktiver Schritt,
Ergebnis), wird die Darstellung spürbar lesbarer — ohne den
Scope in Richtung freier Canvas / Editor zu verschieben.

Der Darstellungsmodus ist:

- **keine Interaktion**, sondern eine reine Funktion der Phase.
- **kein Ersatz für die Presence-Modi** (Docked / Expanded / Action
  / Disconnected) — diese bleiben unabhängig und kollidieren nicht.
- **keine neue Wahrheit** — der Modus wird pro Phase neu aus dem
  State-Modul abgeleitet und nicht persistiert.

### 8a.7 Robustere Event-Rekonstruktion — PR 2

PR 2 härtet die Projektion an drei Stellen, ohne neue Event-Typen
zu verlangen:

- **Mehrere `action_step`-Events.** Das Overlay zählt Schritte in
  einem flach gehaltenen `step_count` und zeigt ab dem 2. Schritt
  einen kleinen Hint („Step 3") *nur im EXPANDED-Modus*. Kein
  History-Log, kein Scrollback.
- **Anti-Flicker bei leeren Payloads.** `action_step` mit leerem
  `title`/`description` überschreibt den bestehenden Action-Titel
  nicht mehr; frühere Label-Entscheidungen bleiben sichtbar, bis
  ein neues belastbares Feld ankommt.
- **Späte oder fehlende Vor-Events.** Wenn ein `action_step`
  eintrifft, ohne dass zuvor `action_planned`/`action_started`
  gesehen wurde (z. B. späte Verbindung), promotet das Overlay
  den Flow still auf `ACTIVE` mit neutralen Trigger- und Action-
  Defaults; ein darauffolgendes `action_completed`/`failed`
  funktioniert normal.
- **Label-Auflösung als pure Helfer.** Alle Label-Defaults leben
  jetzt in `workflow_overlay_state.gd` als static Funktionen
  (`trigger_label_from_payload`, `action_label_from_payload`,
  `step_label_from_payload`, `result_label_from_payload`,
  `cancel_label_from_payload`). Sie sind ohne Scene-Tree testbar
  (siehe `scripts/workflow_overlay_state_smoke.gd`). Default-
  Ketten sind dokumentiert im State-Modul.
- **action_id informativ, nicht steuernd.** Das Overlay
  speichert die `action_id` des laufenden Flows im State, nutzt
  sie aber **nicht** zur Korrelation. Ein neuer `action_planned`
  überschreibt immer — kein Queue, kein Merge.

Verifikation: `scripts/workflow_overlay_state_smoke.gd` deckt diese
Helfer mit ~40 Assertions ab und läuft über den Harness-Case
`workflow-state-smoke` (`scripts/run_overlay_verification.sh
workflow-state-smoke`). Der Controller selbst wird über Szenenlauf
geprüft; für echte `action_*`-Events bleibt ein Lauf gegen einen
laufenden Core die sinnvollste End-to-End-Verifikation.

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
- Kein Template-Marktplatz, kein User-Upload-Pfad — siehe §8b.4
  (Stufe C bleibt Ziel-Zustand).
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
Stufe C aus §8b.4 bleibt Ziel-Zustand. Die Linie ist seit dem
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

---

## 8c. Dev-/MVP-Steuerung für Workflow-Overlay und Avatar-Appearance

Kleine, dev-/preview-orientierte Hilfsschicht. Ausdrücklich **kein**
Settings-System, **kein** Customization-Marktplatz, **kein**
Persistenzsystem — sie macht nur die beiden bestehenden UI-Linien
(Workflow-Overlay, Avatar-Appearance Phase A) zur Laufzeit
beobachtbar und umschaltbar.

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
- Kein alternatives Avatar-Template, kein User-Upload, kein 3D-
  Editor — Phase A bleibt Smolit Salamander only.
- Keine Auswirkung auf Presence-Controller, Approval-/Action-/
  Discovery-Banner, Compact-Input, Overlay/Click-through/AOT,
  Window-Behavior-Backend-Familie.

**Verifikation.** `scripts/dev_controls_smoke.gd` (15 Assertions,
alle PASS): Panel-Phase-Namen gegen State-Modul gematcht,
Theme-/Profile-Round-Trips, 4×3×3-`make_appearance`-Matrix auf
Identität und Konsistenz geprüft, Identity-Invarianz bestätigt.
Harness-Case `dev-controls-smoke` läuft den Test.

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
- **TTS-Lebenszyklus-Events** — aktuell gibt es kein `speaking_started` /
  `speaking_ended` im Protokoll; Animation-Sync hängt davon ab.
- **Emotion-Feld** — heute transportiert das Protokoll keine Emotion in
  `response`-Payloads. Sobald ABrain Emotionen liefert, wird das Feld in
  [`docs/api.md`](./api.md) additiv ergänzt.
- **Headless/Export** — Export-Pipeline und CI-Smoke für Godot stehen aus.
