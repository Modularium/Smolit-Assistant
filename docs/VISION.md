# Smolit AI Assistant – ROADMAP

## Vision

Smolit ist ein persistenter, personalisierter, visueller AI-Assistent im Smolit-Ökosystem.
Er basiert auf **ABrain** als kognitivem Kern, nutzt einen **leichtgewichtigen Rust-Core** als lokale Laufzeit- und Orchestrierungsschicht und erhält eine eigenständige **Godot-UI** als Avatar- und Interaktionsoberfläche.

Smolit soll sich nicht wie ein klassischer Chatbot anfühlen, sondern wie ein präsenter, lernfähiger digitaler Begleiter mit eigener visueller Identität, Stimme, Reaktionsverhalten und langfristiger Nutzeranpassung.

---

## Leitprinzipien

* Control > Autonomy
* Lightweight > Feature-rich
* Modular > Monolith
* Core-driven > UI-driven
* Always-on, minimal resource usage
* Personality through behavior, not hype
* Clean separation of reasoning, interface and execution

---

## Architektur-Entscheidungen

### Core

* Rust
* leichtgewichtig
* performant
* stabil für Always-on-Betrieb
* zentrale Laufzeit- und IPC-Schicht

### UI

* Godot Engine
* Start mit 2D-Avatar
* später optional 2.5D / 3D
* separater Prozess
* Kommunikation mit dem Core via lokalem WebSocket
* perspektivisch zusätzlich ein kleiner, read-only Workflow-/
  Action-Readout neben dem Avatar (Ziel-Zustand, keine Ausführung)

### AI

* ABrain als zentrale Instanz für:

  * Reasoning
  * Planung
  * Kontext
  * Persönlichkeitsmodulation
  * Lernen

### Audio

* Lightweight STT/TTS
* zunächst command-basiert und austauschbar
* später engine-spezifische Presets und Streaming

### Tools / Execution

* AdminBot für Systemoperationen
* LabOS für Labor-/Modul-/Sensor-Kontext
* spätere Plugin- und Tool-Architektur

---

## Zielarchitektur

```text
User
  ↓
Smolit UI (Godot Avatar)
  ↓
Smolit Core (Rust)
  ├── IPC
  ├── Audio (STT/TTS)
  ├── Session / State
  ├── Tool Routing
  └── ABrain Adapter
        ↓
      ABrain
        ↓
  AdminBot / LabOS / weitere Tools
```

---

## Phase 0 – Core Foundation (V0.1)

### Ziel

Ein minimaler, stabiler, lokaler Kern, der Text entgegennimmt, ABrain aufruft und Antworten robust verarbeitet.

### Inhalt

* Rust Core Daemon
* ABrain CLI Adapter
* Minimal CLI Loop
* Logging + Config
* `.env`-basierte Konfiguration
* Fehlerbehandlung + Timeout Handling
* saubere modulare Struktur

### Status

Implemented

### Ergebnis

* stabiler lokaler Kern
* klarer Startpunkt für alle weiteren Phasen
* keine Legacy-Abhängigkeit vom alten Smolit-Assistant

---

## Phase 1 – Voice Interface (V0.2)

### Ziel

Smolit erhält einen modularen Audio-Layer, ohne den Core unnötig aufzublähen.

### MVP – bereits umgesetzt

* command-based STT/TTS Adapter
* `voice` Command im CLI
* `speak <text>` Command für direkte TTS-Ausgabe
* `audio-status` Diagnose-Kommando
* konfigurierbares auto-speak für ABrain-Antworten
* sauberes Fallback-Verhalten ohne Crash bei fehlenden Commands
* konfigurierbare Timeouts

### Folgeschritte

* Push-to-talk
* Wake word
* streaming audio pipeline
* robustere Audioaufnahme / Format-Handling
* Modell-/Engine-spezifische Presets

  * Kokoro
  * Piper
  * Whisper.cpp
  * Vosk
  * weitere lokale Engines
* Audio Queue / Cancellation
* bessere Synchronisierung zwischen Erkennung, Antwort und Wiedergabe

### Ergebnis

* Voice ist additiv zum Textsystem
* Audio ist austauschbar und nicht hart verdrahtet
* gute Grundlage für spätere UI- und Avatar-Synchronisierung

---

## Phase 2 – IPC & UI Bridge Foundation (V0.3)

### Ziel

Der Rust-Core wird über einen lokalen IPC-Layer für eine spätere Godot-UI ansprechbar.

### Bereits umgesetzt

* local WebSocket bridge im Rust-Core
* `.env`-basierte IPC-Konfiguration
* JSON-Protokoll für UI/Core-Kommunikation
* Core-driven Events:

  * `pong`
  * `status`
  * `thinking`
  * `heard`
  * `response`
  * `error`
* Shared App Handler
* keine doppelte Business-Logik zwischen CLI und IPC
* robuste Fehlerpfade ohne Crash bei ungültigem JSON oder fehlender Konfiguration

### Folgeschritte

* Godot Client als separater Prozess
* sauberer Reconnect-Mechanismus
* Event-Kategorisierung erweitern
* TTS-/STT-bezogene UI-Ereignisse ergänzen
* spätere Streaming-/Chunk-Events vorbereiten

### Ergebnis

* UI und Core sind sauber entkoppelt
* der Core bleibt Source of Truth
* die Godot-UI kann später rein als Darstellungsschicht aufsetzen

---

## Phase 3 – Avatar UI (V0.4)

### Ziel

Smolit erhält eine erste sichtbare, interaktive Avatar-Oberfläche in Godot.

### Inhalt

* Godot UI Projekt
* WebSocket Client
* Verbindung zur bestehenden IPC-Bridge
* Avatar Rendering (2D)
* transparentes / borderless Fenster
* always-on-top Verhalten
* Basic Interaction
* Textanzeige / Speech Bubble
* einfache Statusanzeigen
* Start-/Stop-/Reconnect-Verhalten

### Minimale UI-Komponenten

* Avatar Scene
* Animation Controller
* Input Layer
* IPC Client
* Overlay Layer

### Ergebnis

* Smolit ist erstmals sichtbar und präsent
* erste direkte Nutzerinteraktion über Avatar/UI
* stabile Trennung von Core und Darstellung

---

## Phase 4 – Behavioral Layer (V0.5)

### Ziel

Smolit reagiert nicht nur funktional, sondern mit konsistentem Verhalten, Stimmung und visueller Reaktion.

### Inhalt

* Emotion Mapping
* Animation Reactions
* Talking Animation
* Idle States
* Thinking State
* Error / Recovery Reactions
* Speech Sync
* Verhalten abhängig von Antworttyp
* Context Awareness im Verhalten
* erste Persönlichkeitsmerkmale über Reaktionsstil

### Spätere Erweiterungen

* Mikroreaktionen
* Blickrichtung / Fokusreaktion
* kontextabhängige Animationen
* Voice-to-motion Mapping

### Ergebnis

* Smolit fühlt sich lebendiger an
* Verhalten wird zum Differenzierungsmerkmal
* UI wird Ausdruck des internen Zustands

---

## Phase 5 – Personality & Memory System (V0.6)

### Ziel

Smolit entwickelt einen persistenten, nutzerspezifischen Interaktionsstil.

### Inhalt

* User Profile
* Session State
* Conversation Memory
* Preference Storage
* Context Awareness
* Behavior Modulation via ABrain
* Personalisierung von Sprache, Reaktion und Prioritäten
* längerfristige Nutzeranpassung
* erste Profile für:

  * Kommunikationsstil
  * technische Tiefe
  * Proaktivität
  * UI-/Avatar-Präsenz

### Spätere Erweiterungen

* explizite Persona-Parameter
* lernbare Gewohnheiten
* adaptive Proaktivität
* Memory-Scopes
* per-user behavior tuning

### Ergebnis

* Smolit wird persönlicher
* Antworten und Verhalten passen sich an den Nutzer an
* Persönlichkeit entsteht aus Verlauf, Kontext und Verhalten

---

## Phase 6 – Presence System (V0.7)

### Ziel

Smolit erhält räumliche und visuelle Präsenz auf dem Desktop.

### Inhalt

* Screen Movement
* Idle Behavior
* Attention System
* Interaction Zones
* Snap-to-edge Verhalten
* Presence Rules
* Click-through optional
* Aktivitäts-/Inaktivitätslogik
* kleine Bewegungsmuster und Verhaltenszyklen

### Spätere Erweiterungen

* mehrere Präsenzmodi
* ruhig / produktiv / aufmerksam / zurückhaltend
* situationsabhängige Bewegung
* Desktop-Kontextreaktionen

### Ergebnis

* Smolit wirkt nicht wie ein statisches Fenster
* Desktop-Präsenz wird Teil der UX
* Avatar-Verhalten unterstützt die Identität des Systems

---

## Phase 7 – Interaction Layer & Multimodal Routing (V0.8)

### Ziel

Smolit verarbeitet unterschiedliche Eingabemodalitäten und Ereignisse in einem einheitlichen Flow.

### Inhalt

* Voice conversation loop
* Text + Voice + UI kombiniert
* Multi-modal input routing
* Event-driven interactions
* Bild-, Audio- und später Video-Inputs als Routing-Fälle
* Input-Typ-Erkennung
* Weitergabe an ABrain / Toolchain
* Reaktions- und Ausgabeformat abhängig von Modalität

### Erweiterungen

* Datei-Drop auf Avatar/UI
* Screenshot-Input
* Kamera-/Mikrofon-Events
* später Video-/Vision-Workflows

### Ergebnis

* Smolit wird zu einer echten multimodalen Interface-Schicht
* Eingabearten werden vereinheitlicht
* der Nutzer interagiert natürlicher und flexibler

---

## Phase 8 – Tool Integration (V0.9)

### Ziel

Smolit wird zur zentralen Nutzeroberfläche für operative Systeme und Werkzeuge.

### Inhalt

* AdminBot Integration
* LabOS Integration
* Plugin System
* Tool Call Routing
* Status- und Aktionsrückmeldungen im Avatar
* sichere Trennung zwischen Reasoning und Execution
* strukturierte Tool-Antworten
* UI-Reaktionen auf Tool-Zustände

### Tool-Kategorien

* Systemtools
* Lab-/Reaktor-/Modultools
* Datei- und Medienwerkzeuge
* Kontext- und Retrieval-Tools
* externe Services

### Ergebnis

* Smolit wird ein echter Assistent, nicht nur ein Antwortsystem
* operative Fähigkeiten wachsen kontrolliert
* ABrain entscheidet, Smolit vermittelt, Tools führen aus

---

## Phase 9 – Intelligence Expansion (V0.95)

### Ziel

Die kognitive Tiefe und Lernfähigkeit des Gesamtsystems wächst.

### Inhalt

* Multi-agent orchestration
* Continuous learning
* Context persistence
* bessere Langzeitkontexte
* adaptive Toolwahl
* Verbesserung von Persönlichkeit durch Feedback
* multimodale Reasoning-Flows
* geplante Aufgabenketten
* bessere Verknüpfung mit ABrain-internen Agents und Evaluation

### Erweiterungen

* Trace-/Replay-Integration
* Qualitätsbewertung von Antworten
* Profil- und Verhaltenskalibrierung
* aktive Lernschleifen

### Ergebnis

* Smolit wird intelligenter, nicht nur hübscher
* Reasoning, Erinnerung und Verhalten wachsen zusammen
* ABrain-gestützte Weiterentwicklung wird sichtbar

---

## Phase 10 – Production & Distribution (V1.0)

### Ziel

Smolit wird releasefähig als echtes Produkt.

### Inhalt

* Performance optimization
* Packaging
* Installer
* Cross-platform support
* Autostart / background service integration
* Config UX
* Crash resilience
* update strategy
* logs / diagnostics
* release hardening
* Security Review
* Ressourcenprofiling
* Basis-Telemetrie nur lokal / optional
* Dokumentation für Nutzer und Entwickler

### Zielplattformen

* Linux zuerst
* später optional Windows
* SBC-/low-power-Tauglichkeit als Designziel mitdenken

### Ergebnis

* erster produktionsreifer Release
* stabile Grundlage für reale Nutzung im Smolit-Ökosystem

---

# Godot UI Architektur

## Ziel

Smolit soll als lebendiger Avatar auf dem Desktop erscheinen und nicht wie eine klassische App wirken.

## Architektur

```text
Godot App
├── Avatar Scene
├── Animation Controller
├── Input Layer
├── IPC Client (Rust Core)
├── Overlay Layer
└── State Renderer
```

## Komponenten

### Avatar Scene

* 2D als Start
* später optional 2.5D / 3D

### Animation States

* idle
* talking
* thinking
* reacting
* error

### Kommunikation

Godot ↔ Rust Core via lokalem WebSocket

Option A:

* WebSocket lokal
* empfohlen

Option B:

* stdin/stdout bridge
* nur Fallback / Sonderfall

### Event Flow

```text
User speaks
→ Rust Core (STT)
→ ABrain
→ Response
→ Godot (Animation + Text + Speech)
```

### Designprinzipien

* minimal UI
* keine klassische Fenster-App
* Fokus auf Präsenz, Verhalten und Reaktion
* Core bleibt Logikzentrum
* UI bleibt Renderer + Interaktionsschicht

---

# API-Spezifikation – Smolit ↔ ABrain

## Ziel

Ein stabiles, erweiterbares Protokoll zwischen Smolit Core und ABrain.

## Request

```json
{
  "type": "task",
  "input": "string",
  "context": {
    "user_id": "string",
    "session_id": "string",
    "history": []
  },
  "modalities": ["text", "audio", "image"]
}
```

## Response

```json
{
  "status": "ok",
  "response": {
    "text": "string",
    "actions": [],
    "emotion": "neutral | happy | thinking | alert",
    "voice": {
      "tone": "calm",
      "speed": 1.0
    }
  }
}
```

## Event Stream (optional später)

```json
{
  "type": "stream",
  "chunks": []
}
```

## Tool Call (ABrain → Smolit)

```json
{
  "type": "tool_call",
  "tool": "adminbot",
  "payload": {}
}
```

## Error

```json
{
  "status": "error",
  "message": "..."
}
```

## Erweiterbarkeit

Das Schema muss offen bleiben für:

* Vision
* Video
* Audio-Streaming
* Sensor-Daten
* LabOS-Kontext
* Multi-Agent Responses
* Tool-Routing
* UI-/Emotion-Metadaten

---

# Statusübersicht

## Bereits umgesetzt

* Phase 0 – Core Foundation
* Phase 1 – Voice Interface MVP
* Phase 2 – IPC & UI Bridge Foundation MVP

## Als Nächstes sinnvoll

* Phase 3 – Avatar UI
* danach Phase 4 – Behavioral Layer
* danach Phase 5 – Personality & Memory System

---

# Strategische Priorisierung

## Kurzfristig

* Godot UI Minimal Client
* Dummy Avatar
* WebSocket-Verbindung
* Basis-Animationen
* erste sichtbare Präsenz

## Mittelfristig

* Verhalten
* Emotion Mapping
* Speech Sync
* Nutzerprofil
* Memory

## Langfristig

* Toolsystem
* Multimodalität
* tiefe Personalisierung
* produktionsreifer Hintergrundassistent im Smolit-Ökosystem

---

# Grundsatz

Smolit ist nicht nur ein Chat-Frontend.

Smolit ist:

* die verkörperte Oberfläche von ABrain
* die visuelle und auditive Präsenz des Smolit-Ökosystems
* ein persönlicher Assistent mit Verhalten, Kontext und Präsenz
* ein langfristig lernfähiger digitaler Begleiter
