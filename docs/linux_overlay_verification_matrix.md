# Linux Overlay — Verification Matrix

Reproduzierbare Forschungs-/Verifikationsanleitung für den aktuellen
Stand der Linux-Overlay-Linie. Dieses Dokument ist **keine**
Feature-Zusage und **keine** Test-Suite. Es ist eine Sammlung kleiner,
manueller Testfälle, mit denen auf einer echten Session (Wayland oder
X11) überprüft werden kann, was der bestehende Spike in der Praxis
tut — und was er ehrlich *nicht* tut.

Einordnung:

- Plattformgrundlage:
  [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  §C / §E / §F.
- UI-Verkabelung:
  [`ui_architecture.md`](./ui_architecture.md) §9.1–§9.3.
- Presence-Kontext:
  [`presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  §6.

---

## 1. Was verifiziert werden soll

Nur existierender Stand, kein Wunschdenken:

- Overlay-MVP Phase B — transparenter, borderloser Hostfenster-Modus,
  opt-in via `SMOLIT_UI_OVERLAY=1`.
- Click-through-Folgeschritt — opt-in via `SMOLIT_UI_CLICK_THROUGH=1`,
  Bounding-Rect-Union über eine Allowlist interaktiver Zonen, ein
  einziger Polygonpfad an `DisplayServer.window_set_mouse_passthrough`.
- Capability-Detection — ehrliche Status-Aussage pro Fähigkeit.
- Runtime-Report (neu) — opt-in konsolidierter Konsolenblock via
  `SMOLIT_WINDOW_REPORT=1`.

Ausdrücklich **nicht** Teil dieser Matrix:

- Always-on-top.
- Snap-to-Edge / Multi-Monitor-Logik.
- compositor-spezifische Pfade (wlroots layer-shell, GNOME-Extension).
- echtes Multi-Polygon-Passthrough / pixelgenaue Input-Regionen.

---

## 2. Zielsysteme

Primär:

- **Ubuntu 24.04 / GNOME-Wayland.** Standardsession. Mutter als
  Compositor. Der protokollbedingt schwierigste Fall (kein
  Always-on-top, Positionierung compositor-gesteuert).
- **Ubuntu 24.04 / GNOME-X11.** Fallback-Session, wählbar im Login-
  Screen. Erwartet etwas freundlicheres Verhalten bei Transparenz und
  Input-Region.

Sekundär / nur falls verfügbar:

- **XWayland** — ein X11-Client in einer Wayland-Session. Nicht
  Primärziel, aber dokumentieren, falls ein Setup das automatisch
  triggert.
- **Fractional Scaling** (z. B. 125 % oder 150 %). Separat testen, egal
  unter welchem Protokoll.

Nicht in Scope dieser Matrix:

- wlroots (Sway, Hyprland, river), KDE/KWin, XFCE, Cinnamon.
  Ergebnisse dort sind hoch willkommen, aber ohne bestätigtes Setup
  nicht Teil der „erwarteten" Ergebnisse.

---

## 3. Vorbereitung

1. `core` und `ui` wie üblich bauen / starten; Core muss nicht
   zwingend laufen, aber die UI sollte mit Core verbunden testen,
   weil Banner/Presence-Zustände den Click-through-Refresh triggern.
2. Sicherstellen, dass das Projekt-Setting
   `display/window/per_pixel_transparency/allowed = true` gesetzt ist
   (bereits im Repo).
3. Falls der Godot MCP Addon geladen ist (nur Editor-Workflow) — für
   diese Verifikation irrelevant, kann an bleiben.
4. Test immer aus `ui/` heraus starten, damit `res://` korrekt
   aufgelöst wird:
   ```bash
   cd ui/ && godot project.godot
   ```
   Oder headless:
   ```bash
   godot --headless --path ui/
   ```
5. Für konsistente Verifikationsläufe: Einzeiler-Wrapper
   [`scripts/run_overlay_verification.sh`](../scripts/run_overlay_verification.sh)
   nutzen — setzt die Env-Kombinationen pro Testfall sauber.

---

## 4. Env-Matrix

| Variable                  | Zweck                                          |
|---------------------------|------------------------------------------------|
| `SMOLIT_UI_OVERLAY=1`     | Transparent + borderless Presence-Hülle        |
| `SMOLIT_UI_CLICK_THROUGH=1` | Click-through mit Bounding-Union (setzt Overlay voraus) |
| `SMOLIT_WINDOW_PROBE=1`   | Reines Flag-Probe (setzt Flags, liest zurück, revert) |
| `SMOLIT_WINDOW_PROBE_REVERT=0` | Probe-Effekt stehen lassen                |
| `SMOLIT_WINDOW_REPORT=1`  | Einmaliger Diagnose-Konsolenblock              |

Die Env-Variablen sind unabhängig voneinander gedacht und dürfen
kombiniert werden (der Report kommt erst *nach* Overlay- und
Click-through-Aktivierung, sieht also beides).

---

## 5. Testfälle

Jeder Fall beschreibt: **Setup**, **Erwartung**, **Erfolg**,
**ehrlicher Fallback**, **nicht zu erwarten**.

### 5.1 Baseline — keine Opt-ins

- **Setup.** Keine der `SMOLIT_*`-Variablen gesetzt.
- **Erwartung.** UI verhält sich wie heute produktiv — normales
  Godot-Fenster, kein Transparenz-Stunt, kein Click-through. Log
  zeigt genau *einen* Block vom Click-through-Controller:
  `[click-through] requested=false overlay_requested=false … active=false`
  plus `reason: overlay not requested`.
- **Erfolg.** Presence-Modi funktionieren wie vor der Overlay-Linie,
  keine Regression.
- **Fallback.** n/a — Baseline hat keinen Opt-in.
- **Nicht zu erwarten.** Irgendwelche Overlay-/Capability-Logs, weil
  der Overlay-Controller nur bei `SMOLIT_UI_OVERLAY=1` loggt.

### 5.2 Overlay only

- **Setup.** `SMOLIT_UI_OVERLAY=1`.
- **Erwartung Wayland/GNOME.**
  - `[window_behavior] session=wayland driver=wayland desktop=<ubuntu:GNOME|…>`
  - `capability.transparency = available`
  - `[overlay] active=true transparency=true borderless=true`
  - Fenster sichtbar transparent, kein Title-Bar-Frame.
  - Fenster **ist kein** Always-on-top (andere Fenster können
    darüberkommen). Das ist korrekt.
- **Erwartung X11.** Analog; häufig ist die Stacking-Order gutmütiger,
  aber weiterhin kein Promise.
- **Erfolg.** Transparenter Hintergrund sichtbar, Banner/Avatar als
  Floating Entity erkennbar.
- **Fallback.** Wenn Transparenz `unsupported`/`unknown`: Overlay
  bleibt im normalen Modus, Grund steht im Log — Fenster sichtbar, UI
  funktional.
- **Nicht zu erwarten.** Click-through — wurde nicht angefordert.

### 5.3 Overlay + Click-through

- **Setup.** `SMOLIT_UI_OVERLAY=1 SMOLIT_UI_CLICK_THROUGH=1`.
- **Erwartung bei erfolgreicher Aktivierung.**
  - Beide Controller melden `active=true`.
  - `[click-through] … zones_derived=N zones_valid=M active=true`,
    `bounds=(x,y WxH)`, Zonenliste mit Avatar + Header + DockPanel (im
    Docked-Modus ggf. ohne DockPanel).
  - Klicks auf leere Fläche **außerhalb** der Bounding-Box gehen an
    das Fenster dahinter (sichtbar z. B. an einem Browser-Tab im
    Hintergrund, der auf den Klick reagiert).
  - Klicks auf Avatar / Header / Dock-/Compact-Panel bleiben beim
    Smolit-Fenster.
- **Erfolg.** Minimum: Avatar bleibt klickbar; leerer Rest ist
  passthrough. Genaue Box-Größe entspricht dem geloggten Bounds-Rect.
- **Fallback.** Overlay nicht aktiv (siehe 5.2-Fallback) → Click-
  through bleibt inaktiv, Grund „overlay inactive" im Log. Keine Zonen
  ableitbar (z. B. Scene nicht fertig) → „no valid interactive zones
  yet".
- **Nicht zu erwarten.**
  - **Leerer Raum *innerhalb* der Bounding-Box ist passthrough.** Er
    ist es im MVP nicht — das ist die bekannte Grobheit der Single-
    Polygon-Union.
  - Immer-obenauf-Verhalten.

### 5.4 Overlay + Click-through + Window Probe

- **Setup.** `SMOLIT_UI_OVERLAY=1 SMOLIT_UI_CLICK_THROUGH=1 SMOLIT_WINDOW_PROBE=1`.
- **Erwartung.** Die drei Linien sind unabhängig: der Probe läuft *vor*
  Overlay/Click-through, setzt `WINDOW_FLAG_TRANSPARENT` und
  `WINDOW_FLAG_MOUSE_PASSTHROUGH` kurz, liest sie zurück, und setzt sie
  per Default wieder zurück (Revert). Anschließend laufen Overlay und
  Click-through wie in 5.3.
- **Erfolg.** Probe-Log erscheint einmal, Overlay-/Click-through-Log
  danach. Keine kaputte Wechselwirkung.
- **Fallback.** Probe ohne `SMOLIT_UI_OVERLAY` bleibt wie 5.1 plus
  Probe-Block.
- **Nicht zu erwarten.** Doppelt gesetzte Flags, Inkonsistenz zwischen
  Probe-Ergebnis und späterem Overlay-Status.

### 5.5 Runtime-Report

- **Setup.** Ein oder mehrere der anderen Flags + `SMOLIT_WINDOW_REPORT=1`.
- **Erwartung.** Genau **ein** Block
  `─── overlay runtime report ─────` am Ende von `_ready()`, mit den
  Sektionen Session/Desktop, Capabilities, Overlay, Click-through.
- **Erfolg.** Werte stimmen mit den vorangegangenen Einzel-Logs
  überein.
- **Fallback.** Einzelne Felder mit `(none)` oder `(no result — not
  invoked?)`, wenn das zugehörige Subsystem nicht aufgerufen wurde.
- **Nicht zu erwarten.** Dauer-Log, JSON-Ausgabe, Schreibzugriff auf
  Fenster.

### 5.6 Docked vs. Expanded

- **Setup.** Overlay + Click-through, Scene läuft.
- **Erwartung.**
  - Docked (Default): Bounds decken Avatar + HeaderRow. DockPanel ist
    unsichtbar und wird entsprechend *nicht* in die Union aufgenommen.
  - Wechsel auf Expanded (über Toggle oder UI-Pfad): `visibility_changed`
    auf `VBox/DockPanel` feuert, Refresh rebuildet Bounds inkl.
    DockPanel. Der Log zeigt `[click-through] refresh (…): zones_valid=N
    bounds=(…)` genau einmal pro tatsächlicher Bounds-Änderung.
- **Erfolg.** Kein Stuck-Bound, keine verwaiste Passthrough-Box nach
  Docked-Wechsel.
- **Fallback.** Wenn ein Panel-Size beim ersten Event noch nicht
  stabil ist: `call_deferred`-Pfad fängt das mit einem
  `refresh (initial)`.
- **Nicht zu erwarten.** Refresh pro Frame, Log-Flut.

### 5.7 Action- / Approval- / Discovery-Banner erscheinen

- **Setup.** Overlay + Click-through, Core sendet `action_started`,
  `approval_requested` oder `accessibility_discovery_result`.
- **Erwartung.** Banner wird sichtbar → `visibility_changed` feuert →
  Bounds wachsen nach unten. Banner wird wieder unsichtbar → Bounds
  schrumpfen zurück. Jeweils *ein* Refresh-Log, nur bei echter
  Bounds-Änderung.
- **Erfolg.** Approve/Deny-Buttons klickbar, Select-/Clear-Buttons
  klickbar, während das Banner sichtbar ist.
- **Fallback.** Wenn ein Banner nur kurz angezeigt wird (Approval
  Resolved), rollt der Refresh ebenfalls sauber zurück.

### 5.8 CompactInputPanel offen / geschlossen

- **Setup.** Overlay + Click-through, Docked, Klick auf Avatar → Compact
  Panel geht auf.
- **Erwartung.** Panel wird sichtbar → `visibility_changed` auf
  `CompactInputPanel` → Refresh bezieht das Rect. Schließen → Refresh
  zurück.
- **Erfolg.** Input-Feld, Voice/Commands/Close-Buttons klickbar im
  offenen Zustand.

### 5.9 Fractional Scaling / HiDPI

- **Setup.** GNOME / KDE Display-Settings: Scale 100 %, 125 %, 150 %.
  Overlay + Click-through + Report.
- **Hypothesen (nicht Fakten!).**
  - Bei ganzzahligen Skalen liegt die gemeldete Bounds-Box exakt auf
    den UI-Panels.
  - Bei Fractional Scaling könnte es Off-by-<1px-Differenzen geben;
    der Viewport-Clamp sollte off-screen-Anteile abschneiden.
  - Der Report ist primäre Datenquelle: die geloggte Bounds-Box
    gegen das tatsächliche Panel-Geräterechteck vergleichen.
- **Erfolg.** Klickverhalten innerhalb der Box stimmt mit dem
  gerenderten Fenster überein.
- **Nicht zu erwarten.** Perfekte Subpixel-Genauigkeit — die
  Mindestkantenlänge (2 px) und die Bounding-Union-Natur geben das nicht
  her.

### 5.10 XWayland / Session-Edge-Cases

- **Setup.** Nur falls das Setup XWayland explizit erzwingt (z. B.
  manuelles `GDK_BACKEND` o. ä.).
- **Erwartung.** Capability-Detection sollte `session_type=x11` unter
  XWayland ausweisen; praktische Click-through-Zuverlässigkeit ist
  dort compositor-abhängig.
- **Erfolg.** Keine Crashes, ehrlicher Fallback bei
  `unsupported`/`unknown`.
- **Nicht zu erwarten.** Garantierter Always-on-top, garantierte
  pixelgenaue Passthrough-Ränder.

---

## 6. Erfassung von Beobachtungen

Vorschlag für ein kurzes Protokoll pro Lauf (keine harte Vorschrift):

```
Session type (real):    wayland | x11 | xwayland
Compositor / Desktop:   GNOME / KDE / …
Scale:                  100% | 125% | 150% | …
Env combo:              <welche SMOLIT_*-Variablen>
Observed overlay.active:
Observed click_through.active:
Observed zones_valid:
Observed bounds:
Subjektiver Eindruck:
  - Avatar klickbar?
  - Banner klickbar, wenn sichtbar?
  - Leerer Rest passthrough?
  - Offensichtliche Bugs?
```

Kurzfassung reicht; Ziel ist eine belastbare Datenbasis für spätere
Entscheidungen (Multi-Polygon, compositor-spezifische Pfade, Host-
Prozess vs. GDExtension).

---

## 7. Abgrenzung — was dieser Lauf *nicht* beantwortet

- Keine Aussage über Stabilität über längere Zeit (Stunden).
- Keine Aussage über Remote-Desktop-Sessions, Flatpak-Sandboxing,
  Snap-Containern.
- Keine Aussage über Multi-Seat / Multi-Monitor.
- Keine Aussage über Touch/Pen-Eingabe.
- Keine Aussage über Accessibility-Schnittstellen (AT-SPI) auf der
  Ziel-Application-Ebene — das ist eine andere Linie.

Alles davon ist separat und gezielt zu untersuchen, wenn es
relevant wird.
