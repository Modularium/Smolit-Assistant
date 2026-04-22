# X11 Always-on-Top — Verifikationsmatrix

Reproduzierbares Messprotokoll für den bestehenden, opt-in X11-AOT-
Sonderpfad (`SMOLIT_UI_ALWAYS_ON_TOP=1`, implementiert in
`ui/scripts/window_behavior/overlay_always_on_top_controller.gd`,
beschrieben in [`linux_window_overlay_architecture.md` §F.4](./linux_window_overlay_architecture.md)).

Dieses Dokument ist **kein Feature-Plan**, sondern eine
Messanleitung + Ergebnisprotokoll. Ziel: produktseitig sauber bewerten
können, wo der X11-Sonderpfad wirklich taugt und wo er nicht.

Einordnung gegenüber Nachbardokumenten:

- [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
  — warum X11 der einzige Linux-AOT-Standardpfad bei Smolit ist.
- [`linux_overlay_verification_matrix.md`](./linux_overlay_verification_matrix.md)
  — die allgemeine Overlay-/Click-through-Matrix; dieses Dokument
  ergänzt sie um den AOT-Sonderfall.
- [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  §F.4 — technische Gates und Fallback-Semantik.

---

## A. Ziel

Messen, **ob** und **wo** Smolits X11-Sonderpfad unter echten X11-
Sessions sichtbar das bewirkt, was `_NET_WM_STATE_ABOVE` versprechen
soll: das Fenster bleibt über regulären Toplevels stehen.

Nicht Ziel dieses Protokolls:

- Wayland/GNOME — weiter bewusst ohne AOT-Promise (siehe
  [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)).
- layer-shell-Pfade, GNOME-Shell-Extension — ausdrücklich zurückgestellt.
- Snap-to-Edge, Multi-Monitor-AOT, Focus-Policy-Magic.

---

## B. Testumgebungen

Erwartete Bandbreite; nicht alles wird in jeder Session gemessen.

| # | Session-Typ       | WM / Shell    | Erwartung (kurz)                               |
|---|-------------------|---------------|------------------------------------------------|
| 1 | X11               | GNOME Shell   | ABOVE-Hint wird meist respektiert; Mutter/X11  |
| 2 | X11               | KWin (KDE)    | ABOVE-Hint gut unterstützt, konfigurierbar     |
| 3 | X11               | Xfwm4 (Xfce)  | ABOVE-Hint stabil                              |
| 4 | X11 (optional)    | Openbox       | EWMH sauber; Policy-abhängig konfigurierbar    |
| 5 | X11 (optional)    | Fluxbox       | EWMH unterstützt; Edge-Cases bei Fullscreen    |
| 6 | XWayland/GNOME    | Mutter/XWayl. | ABOVE-Hint technisch gesetzt, UX-Effekt flaky  |
| 7 | Wayland/GNOME     | Mutter        | **Soll** No-op sein (Sonderpfad verweigert)    |

Für Wayland-Zeile (#7) ist das „gemessene" Ergebnis: Controller
refuses, Grund `always-on-top special path is X11-only; current
session=wayland — no-op by design`. Das ist Teil der Matrix, damit der
Gegentest dokumentiert ist.

---

## C. Vorbereitung

### C.1 Projekt / Binaries

- Godot 4.6+ auf `PATH`.
- Core nicht zwingend nötig für die AOT-Messung selbst; wenn Core
  läuft, werden die Banner/Discovery-Presence-Tests aussagekräftiger.
- Auf X11-Hosts müssen `xprop`, `wmctrl`, `xdpyinfo` verfügbar sein
  (auf Ubuntu 24.04 per `sudo apt install x11-utils wmctrl`).

### C.2 Standardisierter Lauf

Szene als Runtime starten (nicht Editor), damit parallele Editor-
Instanzen nicht kollidieren:

```bash
SMOLIT_UI_OVERLAY=1 \
SMOLIT_UI_CLICK_THROUGH=1 \
SMOLIT_UI_ALWAYS_ON_TOP=1 \
SMOLIT_WINDOW_REPORT=1 \
godot --path /path/to/Smolit-Assistant/ui scenes/main.tscn
```

Alternativ über Wrapper:

```bash
scripts/run_overlay_verification.sh aot-x11         # only AOT + report
scripts/run_overlay_verification.sh aot-x11-full    # overlay + click-through + AOT + report
```

Wichtig: **ohne `--headless`**, sonst wird der AOT-Controller das
Flag nicht setzen (driver=headless fällt raus, siehe §F.4).

### C.3 Messung während der Laufzeit

Nach dem Start auf den Smolit-Fenstertitel filtern und EWMH-Zustand
lesen:

```bash
# Fenster-ID finden
WID=$(wmctrl -l | awk '/Smolit|smolit|Main/ {print $1; exit}')

# EWMH-State auslesen — hier soll _NET_WM_STATE_ABOVE stehen
xprop -id "$WID" _NET_WM_STATE _NET_WM_WINDOW_TYPE
```

Zusätzlich visuell prüfen (Checkliste §D). Idealerweise ein zweites
Fenster öffnen (z. B. Browser, Terminal), in den Vordergrund holen
und beobachten, ob Smolit oben bleibt.

---

## D. Testmatrix — was pro Session gemessen wird

Für jede Umgebung aus §B:

### D.1 Basismessung

- [ ] `SMOLIT_WINDOW_REPORT=1` ohne AOT-Flag gesetzt → `always_on_top.
      active = false`, Grund „not requested".
- [ ] Env mit `SMOLIT_UI_ALWAYS_ON_TOP=1`, ohne weitere Opt-ins:
  - [ ] Log-Zeile `[always-on-top] requested=true session=x11 driver=<driver> candidate=true applied=true observed=?`
  - [ ] `xprop` zeigt `_NET_WM_STATE = _NET_WM_STATE_ABOVE`?
- [ ] Env mit Overlay + Click-through + AOT:
  - [ ] Keine Interferenz; Overlay bleibt transparent, Avatar klickbar, AOT-Flag trotzdem gesetzt.

### D.2 Presence-Modi

Unter laufendem Core:

- [ ] Docked (nur Avatar sichtbar): AOT verhält sich wie erwartet.
- [ ] Expanded (DockPanel sichtbar): AOT verhält sich wie erwartet,
      Bounding-Union der Click-through-Zone wächst; Smolit bleibt oben.
- [ ] Action-Banner wird ausgelöst (via Core-Action): AOT-Verhalten
      ändert sich nicht.
- [ ] Approval-Banner (via Core): AOT-Verhalten ändert sich nicht,
      Approve/Deny klickbar.
- [ ] Compact Input offen: kein Layer-Problem, AOT ungebrochen.

### D.3 Fensterinteraktionen

- [ ] Fokus auf Fremdfenster (z. B. Terminal): Smolit bleibt sichtbar
      oberhalb?
- [ ] Alt-Tab-Reihenfolge: Smolit erscheint / erscheint nicht in der
      Tab-Liste (WM-Policy-abhängig)?
- [ ] Workspace/Desktop-Wechsel: Smolit bleibt auf aktuellem Desktop?
      Erscheint auf neuem Desktop?
- [ ] Fullscreen-Fremdfenster (z. B. Browser F11): Smolit bleibt
      darüber? Wird verdeckt? (Viele WMs unterdrücken ABOVE-Fenster im
      Fullscreen-Kontext — das ist *erwartet*, nicht zwingend Fehler.)
- [ ] Minimieren/Wiederherstellen von Fremdfenstern: AOT-Verhalten
      stabil?
- [ ] Smolit selbst minimieren und wiederherstellen: `_NET_WM_STATE_
      ABOVE` bleibt gesetzt? (xprop nach Restore wiederholen.)

### D.4 Hard-edges

- [ ] Long-running Stabilität (mehrere Minuten): Flag bleibt gesetzt,
      kein Flackern?
- [ ] WM-Neustart oder Logout/Login innerhalb der Session (nur wenn
      verfügbar): Smolit verhält sich wie ein regulärer Client,
      ABOVE-Hint wird beim Neu-Mapping erneut akzeptiert.

---

## E. Erfassung pro Testlauf

Vorschlag für ein kurzes Protokoll (keine Zwangsform):

```
Session:     <GNOME/X11 | KDE/X11 | Xfce/X11 | XWayland/GNOME | Wayland/GNOME>
Datum:       YYYY-MM-DD
Env-Combo:   <SMOLIT_* Variablen>
Godot:       <Version>
Log:
  [always-on-top] requested=<b> session=<x11|wayland|…> driver=<…> candidate=<b> applied=<b> observed=<b> active=<b>
  reason:    <text>
xprop:
  _NET_WM_STATE: <gefundene Atome>
  _NET_WM_WINDOW_TYPE: <gefundene Atome>
Beobachtung:
  - Smolit oberhalb bei normalem Fokuswechsel? (ja/nein/teilweise)
  - Verhalten bei Fullscreen-Fremdfenster?
  - Verhalten bei Workspace-Wechsel?
  - Sonstige Auffälligkeiten?
Fazit:       usable | flaky | unsupported | n/a (refused by design)
```

---

## F. Ergebnisse

### F.1 GNOME/X11 (Ubuntu 24.04, Mutter in X11-Modus)

Messung erfolgte am lokalen Entwicklungshost. Siehe §G für die
Kommandos, die verwendet wurden.

- **Session.** `XDG_SESSION_TYPE=x11`, `XDG_CURRENT_DESKTOP=ubuntu:GNOME`,
  `DISPLAY=:0`, `WAYLAND_DISPLAY` unset. Xdpyinfo meldet X.Org 21.1.11.
- **Capability-Detection.** `session_type=x11`, `display_driver=x11`,
  `capability.always_on_top=available`.
- **Controller-Log.** `[always-on-top] requested=true session=x11
  driver=x11 candidate=true applied=true observed=true active=true`,
  Reason: „X11 WMs typically honour `_NET_WM_STATE_ABOVE` — behaviour
  still depends on the specific WM, not a universal guarantee".
- **Protokollmessung via xprop.** `_NET_WM_STATE` enthält
  `_NET_WM_STATE_ABOVE` (siehe §G für den genauen Output). Das
  entspricht dem, was der Controller im Log behauptet: **Flag gesetzt
  und vom WM akzeptiert**.
- **Sichtbare Wirkung.** Konkrete UX-Prüfung (Alt-Tab, Fullscreen-
  Fremdfenster, Workspace-Wechsel) ist in dieser Messung **nicht**
  manuell beobachtet worden — reine Bash-/xprop-Messung. Die
  protokollseitige Aktivierung ist bestätigt, die User-Experience-
  Bestätigung bleibt einer manuellen Sichtprüfung vorbehalten.
- **Fazit.** Protokolllevel: **usable**. UX-Ebene: erwartet, aber
  nicht in dieser Session visuell bestätigt.

### F.2 KDE/X11, Xfce/X11, Openbox, Fluxbox

Keine Messung in der aktuellen Umgebung verfügbar (Host war
GNOME/X11). Dieses Dokument ist ausdrücklich Protokoll-Vorlage; die
Zeilen bleiben offen, bis sie real gemessen werden. **Keine erfundenen
Ergebnisse eingetragen.**

Erwartet laut
[`linux_window_overlay_architecture.md` §C.1](./linux_window_overlay_architecture.md):

- KDE/KWin: gut unterstützt.
- Xfwm4: gut unterstützt.
- Openbox/Fluxbox: gut unterstützt, Policy-abhängig.

### F.3 XWayland/GNOME

Nicht in dieser Messung gefahren. Der X11-Controller erkennt solche
Sessions je nach `XDG_SESSION_TYPE` entweder als `x11` (wenn gesetzt)
oder als `wayland`. Für die Matrix relevant: das sichtbare Stacking-
Verhalten ist unter GNOME-XWayland erfahrungsgemäß inkonsistent —
der Controller darf dort das Flag setzen, aber das UX-Ergebnis bleibt
Edge-Case.

### F.4 Wayland/GNOME (Gegentest)

Nicht in dieser Messung gefahren (Host war X11). Erwartetes,
protokollseitig dokumentiertes Ergebnis: der Controller verweigert
die Aktivierung. Log-Reason: `always-on-top special path is
X11-only; current session=wayland — no-op by design`. Das ist **das
gewünschte Verhalten** (siehe
[`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)).

---

## G. Mess-Artefakte

Für Reproduzierbarkeit: die Kommando-Sequenz und das tatsächliche
xprop-Ergebnis der GNOME/X11-Messung sind in
[`x11_always_on_top_results.md`](./x11_always_on_top_results.md)
hinterlegt. Das Protokoll oben bleibt stabil; Einzelergebnisse
landen dort.

---

## H. Abschlussfazit (Stand: Messung 2026-04-22, GNOME/X11 Host)

- **Protokolllevel bestätigt:** der X11-Sonderpfad setzt unter echtem
  X11 das `_NET_WM_STATE_ABOVE`-Atom, wie Godots `WINDOW_FLAG_ALWAYS_
  ON_TOP` es anfordert. Das ist der erste notwendige Beweis.
- **UX-Ebene noch nicht flächendeckend bestätigt.** Visuelle
  Stacking-Bestätigung (Alt-Tab, Fullscreen-Konflikt, Workspace-
  Wechsel) erfordert manuelle Sichtprüfung — idealerweise auf allen
  Ziel-WMs in §B.
- **Produktaussage.** Stand heute:
  > „Smolit bietet auf echten X11-Sessions einen opt-in Always-on-top-
  > Sonderpfad (`SMOLIT_UI_ALWAYS_ON_TOP=1`). Der Pfad setzt auf
  > GNOME/X11 nachweislich `_NET_WM_STATE_ABOVE`. Das sichtbare
  > Stacking-Verhalten hängt vom jeweiligen X11-Window-Manager ab und
  > ist WM-spezifisch zu bewerten. Auf Wayland/GNOME bleibt der Pfad
  > bewusst ein ehrlicher No-op."

Diese Aussage **nicht** darüber hinaus verallgemeinern.

---

## I. Offene Punkte

- Messläufe auf KDE/KWin (X11), Xfce/Xfwm4, Openbox, Fluxbox —
  manuell, mit Sichtprüfung.
- UX-Messung auf GNOME/X11 (Fullscreen-Fremdfenster-Verhalten, Alt-
  Tab-Reihenfolge, Workspace-Wechsel).
- XWayland/GNOME-Verhalten explizit protokollieren (Session-Detection,
  Flag-Setzung, UX-Ergebnis).
- Entscheidung über `_NET_WM_WINDOW_TYPE_DOCK`-Variante nur **nach**
  realen Messungen — nicht spekulativ.
