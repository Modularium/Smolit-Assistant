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
