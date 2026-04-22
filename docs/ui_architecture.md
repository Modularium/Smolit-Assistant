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
| Godot UI       | Rendering (Avatar, Presence, Workflow-Overlay), Animation, lokale Eingabe, Statusanzeige; **keine** Ausführung von Desktop-Aktionen |
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

### Ziel-Zustand – Workflow-Overlay-Erweiterung

Dieser Block beschreibt die **geplante** Erweiterung der Projekt-
struktur um einen Workflow-Overlay-Renderer. Er ist **noch nicht
implementiert**; die Dateinamen sind architektonische Platzhalter,
keine API-Zusage.

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
│       ├── workflow_overlay_layout.gd
│       ├── workflow_overlay_state.gd
│       ├── workflow_node_view.gd
│       └── workflow_edge_view.gd
```

Wichtig:

- Zielstruktur, **heute nicht zwingend implementiert**. Weder die
  Szene `workflow_overlay_root.tscn` noch die genannten Scripts
  existieren derzeit im Repo.
- Die Namen sind architektonische Platzhalter für spätere Arbeit.
  Keine davon darf als fixierte API interpretiert werden.
- Das Overlay lebt innerhalb derselben Presence-/Overlay-Hülle
  (siehe [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)),
  kein separates Toplevel-Fenster, kein neues Multiwindow-System
  im MVP.

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

## 6a. Workflow Overlay als passiver Action-Readout (Ziel-Zustand)

Dieser Abschnitt beschreibt die geplante Rolle des Workflow-Overlays
an der Schnittstelle zum Event-Strom. Er ist **Ziel-Zustand**; der
Renderer existiert heute nicht im Repo.

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

## 8a. Workflow-Overlay-System (Ziel-Zustand)

Dieser Abschnitt beschreibt das Workflow-Overlay als eigenständigen
UI-Baustein. Er ist **Ziel-Zustand**: keine der genannten Klassen,
Szenen oder Zustände existiert heute im Repo. Die Nummer §8a
markiert einen Ziel-Zustand-Nachtrag zu §8 (dort: Ist-Zustand) und
kollidiert nicht mit bestehenden Cross-References auf §8/§9/§10/§11.

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
