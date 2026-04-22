# X11 Always-on-Top — Raw Messergebnisse

Roh-Artefakte der realen Messläufe, auf die
[`x11_always_on_top_verification.md`](./x11_always_on_top_verification.md)
§G verweist. Jeder Block ist eine einzelne Messung; keine Aggregation,
keine Interpretation — die steht in der Matrix.

Reihenfolge: neueste Messung oben.

---

## 2026-04-22 — GNOME/X11 (Ubuntu 24.04)

### Host

- `uname -a`: Linux (Ubuntu 24.04 Dev-Host)
- `XDG_SESSION_TYPE=x11`
- `XDG_CURRENT_DESKTOP=ubuntu:GNOME`
- `DISPLAY=:0`
- `WAYLAND_DISPLAY` unset
- `xdpyinfo`: X.Org version 21.1.11, vendor "The X.Org Foundation".
- Godot Engine v4.6.2.stable.official.71f334935.
- Renderer: OpenGL 4.6 Core / Mesa 25.2.8 / Intel HD Graphics 520.

### Lauf

```bash
SMOLIT_UI_ALWAYS_ON_TOP=1 SMOLIT_WINDOW_REPORT=1 \
  godot --path /home/dev/Smolit-Assistant/ui scenes/main.tscn
```

Messung durchgeführt, sobald die `[always-on-top]`-Zeile im Godot-Log
auftauchte (≈ 2–4 s nach Start). Fensterauswahl via
`xdotool search --pid <godot pid>`.

### xprop-Snapshot

```text
_NET_WM_STATE(ATOM) = _NET_WM_STATE_ABOVE, _NET_WM_STATE_FOCUSED
_NET_WM_WINDOW_TYPE(ATOM) = _NET_WM_WINDOW_TYPE_NORMAL
WM_NAME(STRING) = "Smolit Assistant UI (DEBUG)"
WM_CLASS(STRING) = "Godot_Engine", "Smolit Assistant UI"
```

Befund: `_NET_WM_STATE_ABOVE` ist auf dem Godot-Fenster gesetzt —
das ist die EWMH-Entsprechung dessen, was
`WINDOW_FLAG_ALWAYS_ON_TOP` anfordert. Mutter (im X11-Modus) hat den
Hint akzeptiert und im Fensterzustand mitprotokolliert.

### Controller-Log

```text
[always-on-top] requested=true session=x11 driver=x11 candidate=true applied=true observed=true active=true
[always-on-top] capability=available (X11: _NET_WM_STATE_ABOVE wird von gängigen WMs respektiert)
[always-on-top] reason: X11 WMs typically honour _NET_WM_STATE_ABOVE — behaviour still depends on the specific WM, not a universal guarantee
[always-on-top] note: X11-only special path; Wayland/GNOME intentionally not targeted here (see docs/linux_always_on_top_decision.md)
```

### Runtime-Report (gekürzt auf AOT-Block)

```text
[report] session_type        = x11
[report] display_driver      = x11
[report] desktop_environment = ubuntu:GNOME
[report]   XDG_SESSION_TYPE    = x11
[report]   XDG_CURRENT_DESKTOP = ubuntu:GNOME
[report]   WAYLAND_DISPLAY     = (unset)
[report]   DISPLAY             = :0
[report] capability.always_on_top  = available — X11: _NET_WM_STATE_ABOVE wird von gängigen WMs respektiert
[report] always_on_top.requested         = true
[report] always_on_top.session_type      = x11
[report] always_on_top.display_driver    = x11
[report] always_on_top.candidate         = true
[report] always_on_top.applied           = true
[report] always_on_top.observed          = true
[report] always_on_top.active            = true
[report] always_on_top.scope             = X11-only special path; GNOME/Wayland intentionally not targeted
```

### Nicht in dieser Messung geprüft

- UX-Verhalten (Alt-Tab-Reihenfolge, Workspace-Wechsel, Fullscreen-
  Fremdfenster-Konflikt). Die Messung ist rein protokollseitig, nicht
  visuell.
- KDE/KWin (X11), Xfce/Xfwm4, Openbox, Fluxbox — auf diesem Host
  nicht vorhanden.
- XWayland-Sonderfall (Godot unter GNOME/Wayland als XWayland-Client).
- Wayland/GNOME-Gegentest (der Controller sollte verweigern).

### Fazit für diese Zeile

Protokolllevel **usable**. UX-Level weiterhin unbestätigt und
WM-abhängig — das ist Teil der ehrlichen Produktaussage.

---

## 2026-04-22 — GNOME/X11 UX-Messung (Folgelauf)

Ergänzung zur Protokollmessung oben. Diesmal mit echter WM-Interaktion
auf demselben Host (Ubuntu 24.04 / GNOME/X11, Mutter im X11-Modus).
Test-Peer: ein nackter `xterm -e "sleep 120"`-Prozess.
Testmatrix siehe
[`x11_always_on_top_verification.md` §D](./x11_always_on_top_verification.md).

### Setup

- Smolit gestartet mit `SMOLIT_UI_ALWAYS_ON_TOP=1` (ohne Overlay /
  ohne Click-through — wir wollten den AOT-Pfad isolieren).
- Zweites Fenster: `xterm -geometry 80x24+400+300` (regulärer
  Toplevel, keine besonderen Hints).
- Messung über `xprop`, `wmctrl`, `xdotool`; Stacking-Position aus
  `_NET_CLIENT_LIST_STACKING` (Index 0 = ganz unten, höher = höher im
  Z-Order).

### Rohobservationen

```text
A. initial state
  smolit _NET_WM_STATE = _NET_WM_STATE_ABOVE, _NET_WM_STATE_FOCUSED
  smolit stacking=6/7
  xterm  _NET_WM_STATE = (empty)
  xterm  stacking=5/7

B. activate xterm (xdotool windowactivate --sync)
  smolit stacking=6/7
  xterm  stacking=5/7
  smolit _NET_WM_STATE = _NET_WM_STATE_ABOVE

C. alt-tab list (_NET_CLIENT_LIST)
  smolit in _NET_CLIENT_LIST: yes
  xterm  in _NET_CLIENT_LIST: yes

D. workspace switch (wmctrl -s 1)
  current desktop moves to 2
  smolit _NET_WM_DESKTOP = 0   (stays on WS1)
  smolit _NET_WM_STATE preserved: _NET_WM_STATE_ABOVE

E. minimize smolit (xdotool windowminimize)
  _NET_WM_STATE = _NET_WM_STATE_HIDDEN, _NET_WM_STATE_ABOVE

F. restore smolit (xdotool windowactivate --sync)
  _NET_WM_STATE = _NET_WM_STATE_ABOVE, _NET_WM_STATE_FOCUSED
  stacking=6/7

G. fullscreen xterm (wmctrl -i -r <xterm> -b add,fullscreen)
  xterm  _NET_WM_STATE = _NET_WM_STATE_FULLSCREEN
  smolit stacking=6/7
  xterm  stacking=5/7
```

### Interpretation pro Fall

- **A / B — Stacking vs. Focus.** Smolit bleibt im Stacking höher als
  xterm, selbst wenn xterm den Fokus hat. Das ist genau das von
  `_NET_WM_STATE_ABOVE` erwartete Verhalten auf GNOME/X11.
  Bewertung: **usable**.
- **C — Alt-Tab / Tasklist.** Smolit ist Teil der Task-/Alt-Tab-
  Liste (`_NET_CLIENT_LIST`). Heißt: der Sonderpfad macht Smolit
  *nicht* unsichtbar für den regulären Fenster-Switch. Bewertung:
  **usable** (das ist Konsens-Verhalten, nicht jeder Nutzer erwartet
  das Gleiche — aber es ist ehrlich sichtbar).
- **D — Workspace-Wechsel.** `_NET_WM_DESKTOP=0` bleibt bestehen.
  Smolit wandert **nicht** automatisch mit auf andere Workspaces
  (keine Sticky-Semantik). Wer „Smolit immer sichtbar auf jedem
  Workspace" möchte, braucht zusätzlich `_NET_WM_STATE_STICKY` —
  das ist ausdrücklich **nicht** Teil dieses Sonderpfads. Bewertung:
  **wie erwartet, nicht flaky**; je nach Produkterwartung als
  Limitation zu kommunizieren.
- **E — Minimize.** Minimize fügt `_NET_WM_STATE_HIDDEN` hinzu und
  **behält** `_NET_WM_STATE_ABOVE` bei. Bewertung: **usable**.
- **F — Restore.** Nach `windowactivate` zurück auf
  `_NET_WM_STATE_ABOVE, _NET_WM_STATE_FOCUSED`, Stacking wieder top.
  Kein verlorenes Flag, keine Halbzustände. Bewertung: **usable**.
- **G — Fullscreen-Peer.** Bemerkenswert: Smolit steht im Stacking
  (6/7) auch dann noch über xterm (5/7), wenn xterm
  `_NET_WM_STATE_FULLSCREEN` trägt. GNOME/Mutter behandelt in diesem
  Fall `_NET_WM_STATE_ABOVE` strenger als den Fullscreen-Hint —
  Smolit bleibt also sichtbar über Fullscreen-Apps. Das ist als
  Ergebnis **positiv überraschend**, aber nicht zwingend allgemein-
  gültig für andere Apps (echte Videospieler / Electron-Apps machen
  eigene Stacking-Tricks). Bewertung: **usable im getesteten Fall,
  mit klarer Messunsicherheit für komplexere Fullscreen-Clients**.

### Was diese Messung **nicht** hergibt

- Nur **ein** Peer-Typ (xterm). Keine Aussage über Browser-
  Fullscreen (YouTube / F11 im Firefox/Chrome), Videospieler (mpv
  im native fullscreen), Electron-Apps, Shell-Dialoge
  (Authentifizierung, Benachrichtigungen).
- Keine Messung über längere Laufzeit — nur Punktmessungen direkt
  nach Event.
- Keine Tastatur-Eingabe-Tests, nur Fenster-Stacking.
- Keine Mehrmonitor-Setups.
- Weiterhin nur **GNOME/X11** — KDE/KWin, Xfce/Xfwm4, Openbox,
  Fluxbox, XWayland/GNOME sind weiterhin offen.

### Fazit UX-Messung

Auf GNOME/X11 mit einem simplen Peer-Fenster ist der X11-AOT-
Sonderpfad **UX-level brauchbar** (Stacking, Minimize/Restore,
Alt-Tab, und sogar Fullscreen-Peer verhalten sich wie gewünscht).
Die Aussage bleibt **eng** gefasst: *lokaler GNOME/X11-Host,
ein Peer, Punktmessung*. Für andere WMs, komplexere Peers und
längere Laufzeit bleibt die Matrix offen.
