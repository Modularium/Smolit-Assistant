# Phase 3.1 – Bootstrap & IPC-Client MVP · Review

Scope-Name: `phase-3-avatar-ui` (Subeinheit 3.1)
Basis-Inventar: [phase-3-avatar-ui_inventory.md](./phase-3-avatar-ui_inventory.md)

---

## 1. Bearbeiteter Roadmap-Schritt

`Phase 3 – Avatar UI (V0.4)` / Subeinheit **3.1 Godot-Bootstrap +
IPC-Client MVP**.

Warum genau dieser Schritt: Phase 0–2 sind laut ROADMAP abgeschlossen,
Phase 3 ist der nächste logisch offene Schritt. Phase 3 wurde in der
Inventur in drei Subeinheiten entlang echter Architekturgrenzen zerlegt;
3.1 ist die erste und bildet die Basis für 3.2 (Avatar-Rendering) und
3.3 (Fenster-Präsenz).

---

## 2. Geänderte / neue Dateien

Neu:

- `ui/project.godot` – Godot-4-Projektdefinition, registriert die beiden
  Autoloads `EventBus` und `IpcClient`, setzt `scenes/main.tscn` als
  Hauptscene.
- `ui/config.cfg` – UI-eigene Konfiguration (`websocket_url`,
  `reconnect.min_backoff_ms`, `reconnect.max_backoff_ms`, `debug.verbose`).
- `ui/autoload/event_bus.gd` – reiner Signal-Hub ohne Logik. Scenes
  hängen nur hier an, nicht direkt am Transport.
- `ui/autoload/ipc_client.gd` – `WebSocketPeer`-Wrapper: lädt
  `config.cfg`, connected, re-connected mit exponential backoff,
  parsed JSON-Frames, emittiert auf `EventBus`.
- `ui/scripts/main.gd` – Scene-Controller. Verdrahtet Buttons und
  `EventBus`-Signale, zeigt Status + Event-Log.
- `ui/scenes/main.tscn` – Minimal-Scene: `Control` → VBox(StatusLabel,
  Log, InputRow[Input, Send, Ping]).
- `ui/assets/.gitkeep` – Platzhalter für Phase 3.2.
- `ui/.gitignore` – Godot-Editor-Artefakte (`.godot/`, `.import/`,
  `*.import`, `export_presets.cfg`, …).

Geändert:

- `README.md` – neuer Abschnitt „UI (Godot, Phase 3.1 Bootstrap)".
- `ROADMAP.md` – Phase 3 in drei Subeinheiten aufgeteilt, 3.1 als
  erledigt markiert.
- `docs/reviews/phase-3-avatar-ui_inventory.md` – vor der Umsetzung
  angelegt (Inventar & Scope).

Nicht angefasst (bewusst):

- `core/` – keine Protokolländerung, keine neuen Handler.
- `docs/api.md`, `docs/ui_architecture.md`, `docs/VISION.md`.

---

## 3. Was war schon vorhanden · was fehlte · was wurde ergänzt

Schon vorhanden:

- Core-WebSocket-Server mit komplettem Protokoll
  (`core/src/ipc/protocol.rs`).
- Geteilte Handler in `core/src/app.rs`.
- Konzeptionelle Doku unter `docs/ui_architecture.md` und `docs/api.md`.
- `ui/` als leeres Verzeichnis (nur `.gitkeep`).

Fehlte:

- Jegliches Godot-Projekt.
- Ein konkreter WebSocket-Client gegen die Core-Bridge.
- UI-seitige Konfiguration.
- Ein Eventbus, der die UI von der Transportwahl entkoppelt.

Ergänzt:

- Genau die in der Inventur festgelegten Artefakte, nicht mehr.
- Reconnect-Strategie wie festgelegt (500 ms → 5 s, bei Connect
  automatisch `get_status`).
- Protokollnutzung exakt nach `core/src/ipc/protocol.rs` —
  keine Erweiterung.

---

## 4. Architektur-Invarianten · explizit bewahrt

Gegen `MASTER-PROMPT.md` Abschnitt B + J geprüft:

| # | Invariante | Status |
|---|------------|--------|
| B.1 | Keine Parallel-Implementierung | OK — einzige UI unter `ui/` |
| B.2 | Keine zweite Runtime neben `core/` | OK — Godot ist Client |
| B.3 | Kein zweiter IPC-Stack | OK — nur Client gegen `core/src/ipc/` |
| B.4 | Kein zweiter Audio-Stack | OK — kein Audio in UI |
| B.5 | Keine Business-Logik in UI | OK — UI rendert Events, keine Entscheidungen |
| B.6 | Keine Legacy-Reaktivierung | OK — es existierte nichts |
| B.7 | Nur additive Änderungen | OK — `core/` unverändert |
| B.8 | Keine schweren neuen Abhängigkeiten | OK — nur Godot-Built-ins |
| B.9 | Keine harte Modellkopplung | OK — keine Engine-Annahmen in UI |
| J.1 | Rust-Core bleibt einzige Kernlogik | OK |
| J.2 | UI = Renderer, nicht Brain | OK — kein ABrain/TTS/STT-Call in UI |
| J.7 | Keine zweite Session-/State-Wahrheit | OK — UI hält keinen Verlauf über das Event-Log hinaus |
| J.8 | IPC lokal und core-driven | OK — Default `127.0.0.1:8787` |
| J.10 | Trennung Core ↔ UI | OK — EventBus entkoppelt Transport von Scenes |

---

## 5. Definition of Done (3.1) · Abgleich

| DoD | Stand |
|-----|-------|
| Godot-UI lokal stabil startet | statisch verifizierbar · Live-Smoke durch User, da keine Godot-Binary im Dev-Environment |
| Verbindung zum Rust-Core per WebSocket funktioniert | Code vollständig, Protokoll passt 1:1 zu `core/src/ipc/protocol.rs`, Unit-Tests des Core-Protokolls grün |
| `ping` und `submit_text` sendbar | implementiert in `IpcClient.ping()` / `submit_text()`; im UI per Button/Enter ausgelöst |
| `status`, `thinking`, `response`, `error` empfangbar | in `_handle_frame` gemappt, auf `EventBus` emittiert |
| Empfangene Antworten sichtbar | `main.gd` rendert alle Event-Typen als farbige Log-Zeilen |
| Reconnect funktioniert | Backoff 500 ms → 5 s, neue `WebSocketPeer` pro Versuch |
| Keine Core-Protokolländerung | bestätigt · `core/` nicht modifiziert |
| Keine Business-Logik in UI dupliziert | bestätigt · keine ABrain-/Audio-/Tool-Aufrufe, keine Entscheidungen |

---

## 6. Tests / Verifikation

Durchgeführt:

- `cargo check` und `cargo test` weiterhin grün auf `core/` (15 Tests,
  inkl. 5 Live-IPC-Integrationstests mit tokio-tungstenite als Client).
- Statische Prüfung der Godot-Dateien auf:

  - korrekte `config_version=5` und Godot-4-Sektionsnamen
    (`[application]`, `[autoload]`, `[display]`, `[rendering]`).
  - passende Autoload-Pfade (`*res://autoload/...`).
  - korrekte Scene-Knotenpfade, die mit `@onready var … = $VBox/...`
    im Script übereinstimmen.
  - Protokollkonformität der Outgoing/Incoming-JSON-Formate gegen
    `core/src/ipc/protocol.rs`.

Nicht durchgeführt (Blocker: keine Godot-Binary im Dev-Environment):

- Live-Smoke mit Godot-Editor: Projekt öffnen, Scene starten,
  gegen laufenden Core round-trippen.
- Headless-Export.

Daraus folgt ein **manueller Smoke durch den User** als finales Gate
für den Merge — siehe Abschnitt 8.

---

## 7. Review-/Merge-Gate

| Punkt | Ergebnis |
|-------|----------|
| Scope korrekt? | Ja — nur Subeinheit 3.1 umgesetzt |
| Richtiger nächster Schritt? | Ja — Phase 3 war offen, 3.1 ist Voraussetzung für 3.2/3.3 |
| Parallelstruktur? | Nein |
| Kanonische Pfade? | Ja — `ui/` wie festgelegt |
| Business-Logik in falscher Schicht? | Nein |
| Neue Schatten-Wahrheit? | Nein |
| Core-Tests grün? | Ja (`cargo test` 15/15) |
| Doku konsistent? | Ja — `README.md`, `ROADMAP.md`, `docs/reviews/` aktualisiert |
| Merge-reif? | **Bedingt ja** — static-clean, aber der Godot-Live-Smoke steht aus |

---

## 8. Offene Punkte vor dem Merge

1. **Manueller Godot-Smoke durch den User**:
   - `ui/` in Godot 4.2+ öffnen, Projekt importieren.
   - Core starten (`cd core && cargo run --quiet`), IPC default an.
   - In Godot Scene laufen lassen, `Ping` → Log zeigt `← pong`.
   - `submit_text` mit beliebigem Text → `thinking` + entweder `response`
     (bei vorhandenem ABrain) oder `error` (ohne ABrain).
   - Core beenden → UI zeigt `disconnected`; Core neu starten → UI
     verbindet neu und sendet `get_status`.
2. Optional, falls im Editor Warnings auftreten: Melden, damit 3.1
   nachgeschliffen werden kann, bevor 3.2 startet.

---

## 9. Nächster logischer Schritt

Subeinheit 3.2 – Avatar + Zustandsrendering:

- 2D-Platzhalter-Sprite als Kind-Scene.
- State-Maschine auf `EventBus`-Signalen
  (`thinking_received`, `response_received`, `error_received`,
  `heard_received`).
- Speech-Bubble ersetzt das RichText-Log als Primär-Anzeige.

Weiterhin keine Protokollerweiterung nötig.
