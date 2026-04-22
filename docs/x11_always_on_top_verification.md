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

Pro Umgebung aus §B gibt es zwei Ebenen: *Protokoll* (was steht als
EWMH-State auf dem Fenster) und *UX* (was passiert tatsächlich im
Alltag). Die Matrix ist bewusst so strukturiert, weil die zwei
Ebenen in der Praxis auseinanderlaufen können.

### D.1 Protokoll — Fenster-/Stacking-Zustand

Reine `xprop` / `wmctrl` / `xdotool`-Messung. Ergibt pro Fall eine
harte Ja/Nein-Aussage, ohne UX-Interpretation.

- [ ] **Baseline ohne AOT.** `SMOLIT_UI_ALWAYS_ON_TOP` unset, kein
      `_NET_WM_STATE_ABOVE` auf dem Fenster.
- [ ] **AOT only.** `SMOLIT_UI_ALWAYS_ON_TOP=1`. Erwartung:
      `_NET_WM_STATE_ABOVE` gesetzt; Controller-Log
      `active=true observed=true`.
- [ ] **Overlay + AOT.** Zusätzlich `SMOLIT_UI_OVERLAY=1`. Keine
      Interferenz: Transparenz + Borderless bleiben wie in §F.2 der
      Overlay-Architektur, AOT-Flag unabhängig gesetzt.
- [ ] **Overlay + Click-through + AOT.** Alle drei Opt-ins gleichzeitig.
      Erwartung: Click-through-Bounding-Union und AOT-Hint koexistieren,
      kein Halbzustand.
- [ ] **Presence-Modi (Docked / Expanded).** Wechsel zwischen Docked
      und Expanded ändert *nicht* den AOT-Zustand.
- [ ] **Banner-Sichtbarkeit (Action/Approval/Discovery).** Auftauchen
      eines Banners (core-seitig ausgelöst) ändert nicht den
      AOT-Zustand.
- [ ] **CompactInputPanel offen / geschlossen.** Kein Seiteneffekt auf
      den AOT-Zustand.

### D.2 UX — WM-/Desktop-Interaktion

Hier geht es explizit um *sichtbares Verhalten* unter realer
WM-Kontrolle. Je Fall bitte `usable | flaky | unsupported | n/a`
einordnen plus eine kurze Beobachtung.

- [ ] **Fokuswechsel zu Fremdfenster.** Anderes Fenster (z. B.
      Terminal, Editor, Browser) anklicken/aktivieren; Smolit bleibt
      sichtbar oberhalb?
- [ ] **Alt-Tab.** Smolit erscheint / erscheint nicht in der Tab-
      Reihenfolge (`_NET_CLIENT_LIST` vs. `_NET_CLIENT_LIST_STACKING`)?
      Ist das das gewünschte Produkt-Verhalten?
- [ ] **Workspace-/Desktop-Wechsel.** Smolit bleibt auf aktueller
      Workspace? Erscheint auf anderen Workspaces? `_NET_WM_DESKTOP`
      bzw. `_NET_WM_STATE_STICKY`?
- [ ] **Minimieren/Wiederherstellen von Smolit.** `_NET_WM_STATE_ABOVE`
      bleibt über Minimize/Restore erhalten?
- [ ] **Minimieren/Wiederherstellen anderer Fenster.** AOT-Verhalten
      von Smolit stabil, während Peer-Fenster zugeklappt / wieder
      hervorgeholt werden.
- [ ] **Fremdfenster verdeckt Smolit teilweise.** Anderes Fenster
      über Smolits Bereich schieben; verschwindet Smolit hinter dem
      Fremdfenster, oder bleibt es oberhalb?
- [ ] **Fullscreen-Fremdfenster.** Peer-Fenster auf `_NET_WM_STATE_
      FULLSCREEN` (z. B. Browser F11, Videospieler, `wmctrl -b
      add,fullscreen`). Bleibt Smolit darüber? Wird es verdeckt? Beides
      sind legitime WM-Policies — das *Messergebnis* zählt.
- [ ] **Panel-/Dock-/Systemdialog-Konflikte.** Notifications,
      Auth-Dialoge, Shell-Menüs — kollidiert Smolit mit ihnen? Wird es
      darüber gesetzt, darunter, oder vom WM verdrängt?
- [ ] **Smolit selbst neustarten.** Fenster schließen, Prozess neu
      starten, ABOVE-Hint wird beim Neu-Mapping erneut akzeptiert und
      reflektiert.

### D.3 Bewertung pro Fall

Für jede Zeile der UX-Matrix:

- **Erwartetes Verhalten** (ein Satz).
- **Beobachtetes Verhalten** (ein Satz, konkret — Stacking-Position,
  Atom-Status, sichtbare Reaktion).
- **Kategorie:** `usable`, `flaky`, `unsupported` oder `n/a` (nicht
  getestet in dieser Umgebung).
- **Notes / WM-Caveats** (optional, aber hilfreich).

### D.4 Hard-edges

- [ ] **Long-running Stabilität.** Mehrere Minuten Laufzeit; Flag
      bleibt gesetzt, kein Flackern, keine Drift.
- [ ] **WM-Neustart / Logout-Login.** Smolit verhält sich wie ein
      regulärer Client, Hint wird beim Neu-Mapping gesetzt.

---

## E. Erfassung pro Testlauf

Vorschlag für ein kurzes Protokoll (keine Zwangsform):

```text
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
- **Sichtbare Wirkung.** In einem Folgelauf wurde die UX-Ebene mit
  einem simplen Peer-Fenster (`xterm`) auf demselben Host wirklich
  programmatisch gemessen (`xdotool`, `wmctrl`, `xprop` auf dem
  `_NET_CLIENT_LIST_STACKING`-Atom). Kernaussagen:
  - Stacking im Ruhezustand: Smolit oberhalb xterm.
  - Nach `windowactivate` auf xterm: Smolit **bleibt** oberhalb.
  - `_NET_CLIENT_LIST` enthält Smolit (Alt-Tab sichtbar).
  - Workspace-Wechsel: Smolit nicht sticky, bleibt auf seinem Workspace.
  - Minimize → `_NET_WM_STATE_HIDDEN, _NET_WM_STATE_ABOVE`; Restore
    → zurück zu `ABOVE, FOCUSED`, Stacking wieder oben.
  - Fullscreen-xterm (`_NET_WM_STATE_FULLSCREEN` per `wmctrl -b
    add,fullscreen`): Smolit bleibt im Stacking oberhalb.
  Rohdaten siehe
  [`x11_always_on_top_results.md`](./x11_always_on_top_results.md)
  („GNOME/X11 UX-Messung (Folgelauf)").
- **Fazit.** Protokolllevel **usable**. UX-Level auf GNOME/X11 mit
  dem getesteten Peer (xterm) **usable**, mit klar benannter
  Messenge: ein Peer, punktuelle Momentaufnahme, keine Langzeit-,
  keine Multi-Monitor-, keine Browser-Fullscreen-Tests.

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

## H. Abschlussfazit (Stand: Messungen 2026-04-22, GNOME/X11 Host)

- **Protokollebene bestätigt.** Der X11-Sonderpfad setzt unter echtem
  X11 das `_NET_WM_STATE_ABOVE`-Atom, wie Godots
  `WINDOW_FLAG_ALWAYS_ON_TOP` es anfordert. Erster notwendiger Beweis
  steht (Messung 2026-04-22, siehe §F.1).
- **UX-Ebene auf GNOME/X11 mit xterm-Peer jetzt gemessen.** Stacking,
  Fokuswechsel, Minimize/Restore, Workspace-Verhalten und
  Fullscreen-Peer-Konflikt sind programmatisch observiert
  (`_NET_CLIENT_LIST_STACKING`, `_NET_WM_STATE`). Innerhalb dieser
  engen Messenge verhält sich der Sonderpfad wie erwartet: Smolit
  bleibt im Stacking oberhalb, bleibt es auch bei fokussiertem
  Peer und bei fullscreen-xterm, verliert `ABOVE` nicht über
  Minimize/Restore, ist nicht sticky auf Workspaces.
- **Was weiterhin nicht bestätigt ist.** Browser-Fullscreen
  (Firefox/Chrome F11), Electron-Apps im Fullscreen, Videoplayer im
  native-fullscreen, Multi-Monitor, längere Laufzeit, reale
  Auth-/Shell-Dialoge, und alle anderen X11-WMs (KDE/KWin, Xfwm4,
  Openbox, Fluxbox) und XWayland/GNOME.
- **Produktaussage.** Stand heute:
  > „Smolit bietet auf echten X11-Sessions einen opt-in Always-on-top-
  > Sonderpfad (`SMOLIT_UI_ALWAYS_ON_TOP=1`). Auf GNOME/X11 ist
  > `_NET_WM_STATE_ABOVE` nachweislich gesetzt und bleibt über
  > Fokuswechsel, Minimize/Restore und Fullscreen-Peer erhalten
  > (punktuell gemessen mit einem simplen xterm-Peer). Workspace-
  > Sticky ist **nicht** Teil des Sonderpfads; wer Smolit über mehrere
  > Workspaces sichtbar halten will, braucht separate Shell-Mittel.
  > Sichtbares Stacking-Verhalten hängt weiterhin vom jeweiligen
  > X11-Window-Manager ab — die hier gemachte Aussage gilt *explizit
  > für GNOME/X11 + einfachen Peer*. Andere WMs und komplexere Peers
  > bleiben unvermessen. Auf Wayland/GNOME bleibt der Pfad bewusst
  > ein ehrlicher No-op."

Diese Aussage **nicht** darüber hinaus verallgemeinern.

---

## I. Offene Punkte

- **Andere X11-WMs.** Messläufe auf KDE/KWin (X11), Xfce/Xfwm4,
  Openbox, Fluxbox — manuell, mit Sichtprüfung. Auf diesem Host
  nicht verfügbar; Matrix bleibt offen.
- **Komplexere Peers auf GNOME/X11.** Echte Fullscreen-Fälle jenseits
  xterm: Firefox/Chrome F11, Electron-Apps, mpv native fullscreen,
  VLC. Die xterm-Messung zeigt, dass Mutter im X11-Modus
  `ABOVE`-Fenster über einem einfachen Fullscreen-Toplevel lässt;
  sobald der Fullscreen-Client aber compositor-nähere Signale
  benutzt (z. B. unredirect), kann das anders aussehen.
- **Langzeitstabilität.** Mehrere Minuten/Stunden: bleibt `ABOVE`
  konsistent? Entstehen Drift, Flackern, Interferenzen mit dem
  Shell-State?
- **Shell-/System-Dialoge.** Wie verhält sich Smolit gegenüber
  Notifications, Authentifizierungsdialogen, GNOME-Overview,
  Lock-Screen? Nicht Ziel dieses Sonderpfads, aber relevante
  Randbedingung.
- **XWayland/GNOME.** Session-Detection, Flag-Setzung und
  tatsächliches UX-Verhalten explizit protokollieren.
- **Wayland/GNOME-Gegentest.** Der Code verweigert hier by design;
  der Lauf sollte trotzdem einmal protokolliert werden, damit der
  No-op-Pfad dokumentiert ist.
- **`_NET_WM_WINDOW_TYPE_DOCK`-Variante.** Erst **nach** mehr realen
  Messungen und nur bei klarem Nutzen — nicht spekulativ.
