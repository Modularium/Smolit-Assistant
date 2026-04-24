# PR 28 — Trim `presence_desktop_interaction.md` to Current Reality

- **Datum:** 2026-04-24
- **Scope:** Workstream A (Docs & Architecture Hygiene). Reines
  Docs-Trim; keine Code-, UI-, IPC- oder Protokoll-Änderungen.
- **Verwandte Entscheidungen:** PR 20 (Docs Reality Check), PR 23
  (`focus_window` Reality Decision), PR 25 (Policy v0), PR 27
  (whisper_cpp STT).

---

## 1. Warum dieser PR

Seit PR 20 galt die Aussage:
> `presence_desktop_interaction.md` vermischt Zielbild und Ist-Zustand.

Die Datei war 1 096 Zeilen lang und las sich wie ein umgesetztes
Produkt — mit Bewegungspfaden des Avatars über Fremdfenster, OCR,
Vision, Interaction Fidelity bis Pixel-Bedienung und einem
Desktop-Interaktions-Stack mit `click` / `type` / `scroll` /
`drag&drop`. **Nichts davon existiert im Code.**

Für neue Nutzer und Reviewer hieß das: es gab kein verlässliches
Dokument, in dem klar steht, was Smolit **heute** auf dem Desktop
wirklich tut.

## 2. Was wurde entschärft

Aus dem Quelldokument wurden folgende stillschweigend zu starken
Aussagen entfernt oder in §10 / §11 umquartiert:

1. **„Der Nutzer darf den Eindruck haben, der Avatar 'laufe',
   'klicke', 'tippe'".** Der Originalsatz in §3 suggerierte, dass
   der Avatar als Ausdruck echter Ausführung agiert. Neu: der
   Avatar bleibt Visual Truth aus Action Events; ein `click`- oder
   `type`-Pfad existiert im Core nicht.
2. **„Smolit soll fremde Software bedienen können".** Stand als
   Zielbild in §2. Neu: ausdrücklich **nicht implementiert**, in §10
   Future Work als „Structured Targets aus strukturierter
   Discovery" / „MCP-/RPC-Integrationen" geparkt. §4 benennt die
   Sperre explizit.
3. **Action Mode („Avatar verlässt den Docked-Anker, bewegt sich
   sichtbar über den Bildschirm zum Ziel").** Nicht implementiert —
   der Visual Action Mode ist heute eine reine UI-Staging-
   Intensitätsachse innerhalb der Presence-Hülle. §9 stellt das
   klar; §10 führt „Echte Theatrical Action Mode" als Future Work.
4. **Visual Action Model §7.3 „guided movement" / §7.4 „full
   theatrical mode".** Die Namen bleiben für Kompatibilität, die
   Semantik ist eine Banner-/Overlay-Deckkraft-Stufe. §9 enthält eine
   Tabelle, die explizit sagt: **keine Zielkoordinaten, keine
   Bildschirmwanderung, keine echte Bewegungsbahn**.
5. **Desktop Automation Model mit vier Modi (§8 alt).** Las sich wie
   eine bereits gewählte Betriebs-Konfiguration. Neu: §5 beschreibt
   *nur* Policy v0 als reale Baseline; die alten Modi `none` /
   `assist only` / `allowed trusted actions only` sind weder
   implementiert noch aktive Policy — sie wären künftige Linien
   über Policy v0 hinaus.
6. **Interaction Fidelity Model mit vier Stufen (§9 alt).** Nur
   `native-first` ist gelebt; `hybrid` / `pixel-guided` /
   `experimental` existieren nicht. §7 (neu) benennt `native-first`
   als den einen real implementierten Pfad; §4 listet Pixel/OCR/
   Vision hart als **nicht unterstützt**.
7. **Desktop Interaction Stack v1 mit `click` / `type` / `shortcut`
   / `scroll` / `drag/drop` (§10 alt).** Nichts davon ist real.
   Neu: §3 listet nur echte Capabilities; §4 listet den Rest hart
   als nicht unterstützt; §10 stellt die nicht-implementierten
   Kinds als Future Work mit Policy-Vorbehalt.
8. **Beispielabläufe Kalender-Eintrag und Unbekannte Software
   (§11 alt).** Basierten auf nicht-implementierter Ausführung
   (OCR-Verification, Click auf „Neue Aufgabe", Tippen). Komplett
   entfernt — ein Beispielablauf über nicht-existierende Primitive
   wäre irreführend.
9. **Wayland-Fokus-Pfad.** Das alte Dokument war zur
   Compositor-Realität vage („Strategie pro Session-Typ ist
   offen"). Neu: §4 Explicitly Unsupported nennt Wayland-Fokus
   hart; §10 sagt, was fehlt (Portal / compositor-nativer Pfad).
10. **Accessibility Discovery „verified".** Der Spike hat nie
    `verified` emittiert; trotzdem blieb die Stufe im Dokument
    sichtbar. Neu: §8 stellt klar, dass `verified` **reserviert**
    bleibt und heute nur `discovered` produktiv ist.
11. **Audit-Coverage.** Das alte Dokument implizierte durch §12
    „Step Verification" eine auditierte Interaktions-Kette. Neu:
    §4 nennt explizit, dass der Ring-Buffer heute **nur** den
    `plan_demo_action`-Pfad loggt; der reale `open_application`-
    Flow ist **nicht** auditiert.

## 3. Neue 12-Abschnitt-Struktur

1. Purpose
2. Current Reality
3. Implemented Capabilities
4. Explicitly Unsupported
5. Approval / Policy v0
6. Presence UI Responsibilities
7. Desktop Interaction Core Responsibilities
8. Accessibility Spike
9. Visual Action Mode
10. Future Work
11. Explicit Non-goals
12. References

Plus Anhang: **Mapping alte → neue Abschnittsnummern**, damit
bestehende eingehende Verweise (z. B. aus PR-23-Review-Zeitdokument,
aus `ui_architecture.md`, aus `wlroots_overlay_path.md`, aus
`api.md`) nachvollziehbar auf die neue Struktur fallen.

## 4. Current Reality nach PR 28

Einzelne Capability-Aussagen, die das neue Dokument verbindlich macht:

- `open_application` — real, approval-gated by default (Policy v0);
  Verification `uncertain` / Best-effort.
- `focus_window` — X11-Template, doppeltes Opt-in (Flag +
  Template), approval-gated; **kein** Wayland-Backend.
- `type_text` — `BackendUnsupported("type_text")`.
- `send_shortcut` — `BackendUnsupported("send_shortcut")`.
- Accessibility — read-only Probe + hint-echo Discovery; **kein**
  AT-SPI-RPC, **kein** Tree-Walking, **kein** `verified` heute.
- Visual Action Mode — UI-Staging-Intensität; **keine**
  Cross-Window-Avatar-Motion.
- Godot-UI — Presentation Layer, **keine** Desktop-Automation.
- Audit — deckt **nur** `plan_demo_action`; der reale
  Interaction-Flow ist **nicht** auditiert.

## 5. Future Work, die übrig bleibt

Explizit in §10 des neuen Dokuments vermerkt (jede Zeile braucht
eigene Design-Entscheidung, kein Drift-by-PR):

- Window-Probe zur Hochstufung `uncertain` → `verified`.
- AT-SPI-Registry-Zugriff (zbus/atspi) für echte Discovery-Items.
- Wayland-Fokus-Pfad (Portal / wlroots-spezifisch).
- `type_text` / `send_shortcut` Backends — erst nach eigener
  Policy-Runde (Trust-Stufen für sensible Dialoge).
- Structured Targets aus strukturierter Discovery.
- Audit-Coverage für den realen `open_application`-Lifecycle.
- Echte Theatrical Action Mode (Avatar-Bewegung über Fremdfenster)
  — braucht Desktop-Geometrie-Binding und Compositor-Kopplung.
- Trust-Modell für Anwendungen (`trusted_only`-Flag heute ungating).

## 6. Was bewusst unverändert blieb

- **Kein Code-Change.** Kein Rust-Test geändert, kein UI-Smoke
  angefasst, kein IPC-Vokabular verändert. Das ist Docs-Work.
- **Smolitux Design Contract** (ADR-0001, PR 24) unangetastet.
- **smolitux-ui** und **OceanData** außerhalb des Scopes.
- **PR-23-Review (`PR23_FOCUS_WINDOW_DECISION.md`)** bleibt als
  Zeitdokument mit seinen ursprünglichen `§14b`-Verweisen
  unverändert — das neue Altanker-Mapping in `presence_desktop_interaction.md`
  bildet den fachlichen Inhalt auf die neuen Abschnitte ab.

## 7. Inbound-Link-Audit

| Quelle | Alt-Anker | Status |
| --- | --- | --- |
| `docs/ui_architecture.md` (§8.5) | `§7` | auf `§9` aktualisiert |
| `docs/api.md` (§2.6 „Scope-Grenzen") | `§7` | auf `§10 / §11` aktualisiert |
| `docs/wlroots_overlay_path.md` | `§12` | bewusst ungetouched — Zeitdokument; Altanker-Mapping im Anhang fängt das ab |
| `docs/reviews/PR23_FOCUS_WINDOW_DECISION.md` | `§14b`, `§14b.4` | bewusst ungetouched — historisches Review; Altanker-Mapping fängt das ab |

## 8. Honesty Check

- ✅ Kein Satz im neuen Dokument behauptet, Smolit könne heute
  klicken, tippen oder fremde UI-Elemente bedienen.
- ✅ Kein Satz behauptet zuverlässige Wayland-Fokussierung.
- ✅ Kein Satz behauptet, der Visual Action Mode bewege den Avatar
  über Fremdfenster.
- ✅ Kein Satz behauptet, Accessibility-Discovery sei `verified`.
- ✅ §10 Future Work trägt alle Zielbild-Punkte; sie sind dort
  explizit als nicht implementiert markiert.
- ✅ Altanker-Mapping im Anhang fängt bekannte eingehende Verweise
  ab.
