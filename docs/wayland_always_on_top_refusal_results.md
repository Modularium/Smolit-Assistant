# Wayland/GNOME Always-on-Top — Refusal-Messungen

Reproduzierbarer Gegentest zum X11-AOT-Sonderpfad: **unter
GNOME/Wayland soll der Controller Always-on-top nicht aktivieren**
und die Ablehnung mit klarem `reason` ins Log schreiben.

Dieses Dokument ist die Messseite der in
[`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
getroffenen Entscheidung. Es enthält **keine** Feature-Vorschläge,
sondern Belege, dass der Verzicht kein Zufall ist, sondern ein
reproduzierbarer, gelabelter Code-Pfad.

Einordnung gegenüber Nachbardokumenten:

- [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
  — Architekturentscheidung (warum unter GNOME/Wayland keine AOT-
  Zusage).
- [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  §F.4 — technische Gates im Controller.
- [`x11_always_on_top_verification.md`](./x11_always_on_top_verification.md)
  — Messmatrix für die X11-Seite.
- [`x11_always_on_top_results.md`](./x11_always_on_top_results.md)
  — X11-Rohartefakte.

---

## 1. Was verifiziert wird

Unter einer echten GNOME/Wayland-Session:

1. `SMOLIT_UI_ALWAYS_ON_TOP=1` führt **nicht** zu einer Flag-Aktivierung.
2. Der Controller liefert genau einen klar gelabelten Refusal-Log-
   Block (`active=false`, `candidate=false`, `applied=false`,
   `observed=false` + konkreter `reason`).
3. Overlay und Click-through bleiben davon strukturell unberührt —
   jedes Opt-in aktiviert / verweigert unabhängig.
4. Es entsteht **kein** stilles Flag-Set-Nebeneffekt, der dann
   „funktioniert manchmal" aussehen könnte.

Explizit **nicht** Teil dieser Verifikation:

- Irgendeinen Wayland-AOT-Pfad einführen.
- Irgendeinen layer-shell- oder GNOME-Extension-Schritt vorbereiten.
- Die Überwachung anderer Wayland-Compositors (wlroots etc.).

---

## 2. Testumgebung und Werkzeuge

Realer Wayland-Gegentest erfordert eine GNOME/Wayland-Login-Session
(oder eine vergleichbare Mutter/KWin/wlroots-Wayland-Session). Diese
Messkampagne wurde in einem Setup gefahren, in dem der Entwicklungs-
host **kein** aktives Wayland-Backend hatte (Login war GNOME/X11,
kein nested Wayland-Compositor installiert).

Daher gibt es zwei unterscheidbare Messpfade:

### 2.1 „Real-Wayland"-Messung (ausstehend)

Auf einem Host mit laufender Wayland-Session (`echo
$XDG_SESSION_TYPE` = `wayland`, `$WAYLAND_DISPLAY` gesetzt):

```bash
scripts/run_overlay_verification.sh --scene --report aot-x11
# (Der Harness-Case heißt aot-x11, aber die Env-Variable ist
# SMOLIT_UI_ALWAYS_ON_TOP=1 — der Controller soll gerade hier
# verweigern, nicht aktivieren.)
```

Alternativ der dedizierte Refusal-Case (siehe §5):

```bash
scripts/run_overlay_verification.sh --headless aot-wayland-refusal
```

Erwartete Log-Zeilen:

```text
[always-on-top] requested=true session=wayland driver=<wayland|headless> candidate=false applied=false observed=false active=false
[always-on-top] capability=unsupported (Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels)
[always-on-top] reason: always-on-top special path is X11-only; current session=wayland — no-op by design (see docs/linux_always_on_top_decision.md)
```

Ergebnisartefakte landen dann als neuer Block in §4 dieses Dokuments,
sobald reale Messung möglich ist.

### 2.2 Env-Override-Simulation (auf diesem Host bereits gelaufen)

Der Capability-Detector (`ui/scripts/window_behavior/window_capabilities.gd`)
entscheidet die Session ausschließlich anhand von Umgebungsvariablen
(`XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, `DISPLAY`,
`XDG_CURRENT_DESKTOP`) und des gemeldeten DisplayServer-Namens. Eine
Env-Override-Messung setzt diese Variablen auf die Werte, wie sie
unter einer GNOME/Wayland-Session stehen würden, und exerziert so den
exakten Gate-Code.

**Unterscheidung:** Das ist eine Simulation der *Erkennungslogik*,
nicht eine Messung gegen einen echten Compositor. Godot bleibt hier
unter `--headless`, weil `--display-driver wayland` ohne echten
Wayland-Socket ohnehin abbricht (siehe §4.2). Die Simulation zeigt
also nur, dass der **Controller-Pfad korrekt verweigert**, wenn die
Detection „wayland" sagt. Sie zeigt nicht, wie Mutter reagieren
würde — das ist der ausstehende Real-Test.

---

## 3. Erwartetes Verhalten (Soll)

| Bedingung                                                                 | Soll                                                                                 |
|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| `SMOLIT_UI_ALWAYS_ON_TOP` unset                                           | Controller: `requested=false`, reason „not requested".                               |
| `SMOLIT_UI_ALWAYS_ON_TOP=1`, `session_type == "wayland"`                  | Controller: `active=false`, reason „X11-only; current session=wayland".              |
| `SMOLIT_UI_ALWAYS_ON_TOP=1`, `display_driver == "headless"`               | Controller: `active=false`, reason „display_driver=headless".                        |
| `SMOLIT_UI_ALWAYS_ON_TOP=1`, Capability `unsupported` / `unknown`         | Controller: `active=false`, reason „capability not available".                       |
| Overlay / Click-through unabhängig davon                                  | Beide folgen ihren eigenen Gates, werden von AOT-Refusal nicht berührt.              |

---

## 4. Messungen

### 4.1 Env-Override-Simulation (2026-04-22, Dev-Host)

Kommando:

```bash
XDG_SESSION_TYPE=wayland \
WAYLAND_DISPLAY=wayland-0-fake \
XDG_CURRENT_DESKTOP=ubuntu:GNOME \
DISPLAY= \
SMOLIT_UI_ALWAYS_ON_TOP=1 \
SMOLIT_WINDOW_REPORT=1 \
godot --headless --path /home/dev/Smolit-Assistant/ui
```

Beobachteter Controller-Log:

```text
[always-on-top] requested=true session=wayland driver=headless candidate=false applied=false observed=false active=false
[always-on-top] capability=unsupported (Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels)
[always-on-top] reason: always-on-top special path is X11-only; current session=wayland — no-op by design (see docs/linux_always_on_top_decision.md)
```

Relevanter Runtime-Report-Ausschnitt:

```text
[report] session_type        = wayland
[report] display_driver      = headless
[report] desktop_environment = ubuntu:GNOME
[report]   XDG_SESSION_TYPE    = wayland
[report]   XDG_CURRENT_DESKTOP = ubuntu:GNOME
[report]   WAYLAND_DISPLAY     = wayland-0-fake
[report]   DISPLAY             = (unset)
[report] capability.always_on_top  = unsupported — Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels
[report] always_on_top.requested         = true
[report] always_on_top.session_type      = wayland
[report] always_on_top.display_driver    = headless
[report] always_on_top.capability        = unsupported (Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels)
[report] always_on_top.candidate         = false
[report] always_on_top.applied           = false
[report] always_on_top.observed          = false
[report] always_on_top.active            = false
[report] always_on_top.scope             = X11-only special path; GNOME/Wayland intentionally not targeted
[report] always_on_top.reason            = always-on-top special path is X11-only; current session=wayland — no-op by design (see docs/linux_always_on_top_decision.md)
```

Befund:

- Der Controller verweigert wie gewollt. `applied=false` bedeutet:
  das Flag wurde nie gesetzt, nicht „Flag wurde gesetzt und
  zurückgelesen als false".
- Der Grund im Log ist klar, zeigt auf das Entscheidungsdokument,
  und enthält die konkrete Session-Kategorie.
- Capability-Detection meldet zusätzlich die zugrundeliegende
  Plattformrealität („Wayland (GNOME/Mutter): kein protokollweiter
  …").
- Der Runtime-Report reproduziert beide Aussagen inklusive
  `scope = X11-only special path; GNOME/Wayland intentionally not
  targeted`.

Messgrenzen:

- **Simulation, kein echter Compositor.** Wir haben nur gezeigt,
  dass der Erkennungs- und Refusal-Pfad *bei Wayland-Signalen im
  Env* greift. Ein echter Mutter-Wayland-Compositor wurde **nicht**
  angesprochen.
- `display_driver=headless`, nicht `wayland` — weil Godot auf diesem
  Host kein echtes Wayland-Backend hat. Unter einer echten
  Wayland-Session wäre `display_driver=wayland`.

### 4.2 `--display-driver wayland` ohne Compositor (Gegenprobe)

Für die Vollständigkeit: wenn jemand auf einem Host ohne
Wayland-Socket versucht, Godot mit `--display-driver wayland`
zu starten, meldet Godot sauber Fehler und fällt auf X11 zurück —
kein stiller Pseudo-Wayland-Modus:

```text
ERROR: Can't connect to a Wayland display.
   at: init (platform/linuxbsd/wayland/wayland_thread.cpp:4845)
ERROR: Could not initialize the Wayland thread.
   at: DisplayServerWayland (platform/linuxbsd/wayland/display_server_wayland.cpp:2058)
ERROR: Can't create the Wayland display server.
   at: create_func (platform/linuxbsd/wayland/display_server_wayland.cpp:2026)
WARNING: Display driver wayland failed, falling back to x11.
```

Nach dem Fallback ist der Lauf effektiv eine X11-Session — die
AOT-Messung wäre dort identisch zur reinen X11-Messung aus
[`x11_always_on_top_results.md`](./x11_always_on_top_results.md) und
sagt **nichts** über Wayland aus. Wir dokumentieren das hier nur,
damit niemand auf die Idee kommt, `--display-driver wayland` als
Wayland-Test zu verkaufen, wenn kein Compositor vorhanden ist.

### 4.3 Realer Wayland-Compositor-Lauf (ausstehend)

Auf diesem Host nicht verfügbar — kein `weston`, kein `cage`, kein
`labwc`, kein Hyprland / Sway / Mutter-Nested-Modus installiert,
und die Login-Session ist GNOME/X11. Eine echte
Wayland-Messung gegen Mutter, KWin (Wayland) oder einen wlroots-
Compositor bleibt als offener Messauftrag.

Stand 2026-04-24 (PR 22 B-Wayland-Live-Messung): unverändert
ausstehend. Siehe §4.4 unten für die Host-Inventur.

Vorschlag für den Real-Test, sobald Hardware/Session verfügbar:

```bash
# Unter einer echten GNOME/Wayland-Login-Session (nicht via
# --display-driver manuell erzwungen):
echo "$XDG_SESSION_TYPE"   # sollte "wayland" sein
echo "$WAYLAND_DISPLAY"    # sollte gesetzt sein (z. B. wayland-0)

SMOLIT_UI_ALWAYS_ON_TOP=1 SMOLIT_WINDOW_REPORT=1 \
  godot --path /path/to/Smolit-Assistant/ui scenes/main.tscn
```

Erwartung: `display_driver=wayland`, sonst identisch zur Simulation
oben. Ergebnis bitte als neuer Block hier anhängen.

### 4.4 Host-Inventur 2026-04-24 (PR 22 B-Wayland-Live-Messung)

PR 22 hatte als Ziel einen echten Wayland/GNOME-Messlauf. Auf dem
Dev-Host ist dieser Lauf **weiterhin nicht möglich** — ehrlich
dokumentiert statt als X11-Messung getarnt.

**Host-Signale (ermittelt durch Inspektion der Login-Session):**

| Signal                 | Wert                              |
|------------------------|-----------------------------------|
| OS                     | Ubuntu 24.04.4 LTS (Noble Numbat) |
| Desktop                | `ubuntu:GNOME`, GNOME Shell 46.0  |
| `XDG_SESSION_TYPE`     | `x11`                             |
| `WAYLAND_DISPLAY`      | (unset)                           |
| `DISPLAY`              | `:0`                              |
| `DESKTOP_SESSION`      | `ubuntu-xorg`                     |
| Godot                  | 4.6.2.stable.official.71f334935   |

**Verfügbarkeit nested Wayland-Compositoren (alle `command -v`):**

- `weston` — absent
- `cage` — absent
- `labwc` — absent
- `sway` — absent
- `hyprland` — absent
- `mutter` — absent (nur als Login-Compositor unter einer Wayland-
  Session startbar, nicht als nested binary auf diesem Host)
- `kwin_wayland` — absent

Konsequenz: weder eine reale Wayland-Login-Session noch ein nested
Wayland-Compositor stehen zur Verfügung. Ein Start mit
`godot --display-driver wayland` würde auf diesem Host wie in §4.2
gezeigt auf X11 zurückfallen — das ist kein Wayland-Beweis.

**Re-Run der Env-Override-Simulation, 2026-04-24.** Als Kontrolle,
dass der Refusal-Pfad (§4.1) nach PR 17–21 Docs-/Code-Arbeiten
unverändert greift, wurde die Simulation erneut gefahren:

```bash
scripts/run_overlay_verification.sh --headless aot-wayland-refusal
```

Beobachteter Controller-Log:

```text
[always-on-top] requested=true session=wayland driver=headless candidate=false applied=false observed=false active=false
[always-on-top] capability=unsupported (Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels)
[always-on-top] reason: always-on-top special path is X11-only; current session=wayland — no-op by design (see docs/linux_always_on_top_decision.md)
```

Report-Auszug:

```text
[report] session_type        = wayland
[report] display_driver      = headless
[report] desktop_environment = ubuntu:GNOME
[report] always_on_top.capability        = unsupported (Wayland (GNOME/Mutter): kein protokollweiter Always-on-top-Pfad für reguläre Toplevels)
[report] always_on_top.active            = false
[report] always_on_top.scope             = X11-only special path; GNOME/Wayland intentionally not targeted
[report] always_on_top.reason            = always-on-top special path is X11-only; current session=wayland — no-op by design (see docs/linux_always_on_top_decision.md)
```

Zusätzlich wurde `resolver-wayland-mutter` gefahren — der Resolver
wählt korrekt `backend.id = wayland-mutter`, Capability-Tabelle
zeigt `transparency=available`, `click_through=experimental`,
`always_on_top=unsupported`. Das ist konsistent mit §4.1 und dem
Zielbild aus [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
§B.

**Honest outcome:**

- Refusal-Pfad bleibt reproduzierbar — der Controller verweigert
  AOT bei Erkennung `session_type=wayland`, unabhängig vom realen
  Compositor.
- Real-Wayland-Messung bleibt ausstehend. Produktaussage ändert
  sich nicht: unter GNOME/Wayland kein AOT, klare Ablehnung,
  Overlay + Click-through als reguläre Presence-Mittel verfügbar.
- Für echte Mutter-Wayland-/KWin-Wayland-Daten wird ein
  dedizierter Messtermin auf einem Host mit Wayland-Login-Session
  benötigt. Die Frage ist nicht „geht es?" (Simulation belegt den
  Code-Pfad), sondern „wie reagiert der echte Compositor auf das
  ausbleibende Flag-Set?" — letzteres ist nur gegen einen echten
  Mutter messbar.

---

## 5. Harness-Einbindung

`scripts/run_overlay_verification.sh` hat einen dedizierten Fall
`aot-wayland-refusal`. Er setzt `SMOLIT_UI_ALWAYS_ON_TOP=1` plus
Wayland-Env-Overrides (ausschließlich zu Diagnosezwecken) und den
Runtime-Report — so lässt sich die Refusal-Messung ohne
Copy-Paste-Reproduzieren einfach fahren.

```bash
scripts/run_overlay_verification.sh --headless aot-wayland-refusal
```

Wichtig: Der Case ist **nur** für den Refusal-Test gedacht. Er
stellt **keine** echte Wayland-Session her und darf nicht als
„funktioniert unter Wayland"-Beleg gedeutet werden.

---

## 6. Zentrale Aussage nach dieser Messkampagne

- Auf diesem Host ist per Env-Override-Simulation **empirisch
  belegt**, dass der Controller bei Erkennung `session_type ==
  "wayland"` (und GNOME als Desktop) sauber verweigert und einen
  klaren Grund loggt. Overlay und Click-through sind davon
  unbeeinflusst.
- **Echte Wayland-Session** bleibt ausstehend — keine Fake-
  Messung eingetragen. Sobald eine GNOME/Wayland-Session verfügbar
  ist, wird §4.3 mit realen Rohdaten ergänzt.
- Produktseitig ändert diese Messkampagne **nichts**. Unter
  GNOME/Wayland bleibt Smolits Versprechen: kein AOT, klare
  Ablehnungsmeldung, Overlay + Click-through als reguläre Presence-
  Mittel verfügbar.

---

## 7. Offene Punkte

- **Echter Wayland-Lauf** auf einer Mutter-Wayland-Session (GNOME,
  Ubuntu 24.04 Default).
- **KDE/Wayland** (KWin-Wayland) als Kontrollmessung.
- **wlroots-Wayland** (Sway/Hyprland) als Kontrollmessung —
  ausdrücklich **nicht**, um dort AOT einzubauen, sondern um zu
  sehen, ob die Capability-Detection die Subkategorie
  `experimental` dort sauber ausweist.
- **XWayland-Fall** (Godot als XWayland-Client unter einer
  Wayland-Session) — der Controller erkennt hier je nach
  `XDG_SESSION_TYPE` entweder x11 oder wayland; das reale Verhalten
  ist zu beobachten und in §4 einzutragen.
