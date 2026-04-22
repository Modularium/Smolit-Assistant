# Window-Behavior-Backend — Verifikationsmatrix

Reproduzierbare Zuordnung der internen Backend-Familie (`backend_x11`,
`backend_wayland_mutter`, `backend_wayland_wlroots`, `backend_xwayland`,
`backend_wayland_generic`, `backend_noop`) zu realen und simulierten
Sessions. Dieses Dokument ist **keine Feature-Doku** — die
Plattformversprechen stehen unverändert in
[`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
und [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md).
Hier geht es ausschließlich um die Frage: *welches Backend wählt der
Resolver unter welchen Bedingungen, und wie belastbar ist diese
Wahl heute gemessen?*

Einordnung gegenüber Nachbardokumenten:

- [`ui_architecture.md`](./ui_architecture.md) §9.0 — interne
  Rollenverteilung, Resolver-Regeln, Fassaden-Signatur.
- [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  §F.1 — Datei-Layout und Stance pro Backend.
- [`linux_overlay_verification_matrix.md`](./linux_overlay_verification_matrix.md)
  — Verifikationsmatrix für die Aktivierungspfade
  (Overlay / Click-through).
- [`x11_always_on_top_verification.md`](./x11_always_on_top_verification.md)
  und [`wayland_always_on_top_refusal_results.md`](./wayland_always_on_top_refusal_results.md)
  — AOT-spezifische Messergebnisse.

---

## A. Ziel

Empirisch belegen:

1. dass der Resolver jedes der sechs Backends unter den in
   `backend_resolver.gd` dokumentierten Bedingungen wirklich wählt,
2. dass der Runtime-Report die gewählte `backend_id` sichtbar macht,
3. dass kein Backend zu neuem Plattformverhalten führt — alle
   delegieren weiterhin an die existierenden Controller (siehe
   `backend_base.gd` Kopf).

Die Backend-Familie wurde bewusst aufgetrennt, weil die Wayland-Welt
intern nicht einheitlich ist (GNOME/Mutter vs. wlroots-Familie vs.
XWayland-Sonderfall vs. unbekannter Compositor). Ohne diese Trennung
würde jede spätere compositor-spezifische Arbeit in „einem großen
Wayland-Block" landen. Die Aufteilung ist architektonisch; sie erzeugt
keine neuen Produktversprechen.

---

## B. Erwartete Zuordnung

Aus dem Resolver (`backend_resolver.gd`):

- `session_type == "x11"` → `x11`.
- `session_type == "wayland"` + `display_driver == "x11"` → `xwayland`.
- `session_type == "wayland"` + GNOME-artiger Desktop → `wayland-mutter`.
- `session_type == "wayland"` + wlroots-artiger Desktop
  (Allowlist: `sway`, `hyprland`, `wayfire`, `river`, `labwc`)
  → `wayland-wlroots`.
- `session_type == "wayland"` + sonst → `wayland-generic`.
- alles andere → `noop`.

Measured on this host (Ubuntu 24.04 / GNOME-X11 login session), plus
Env-Override-Simulationen:

| Case                                                              | Expected `backend_id` | Observed `backend_id` | Messung   |
|-------------------------------------------------------------------|-----------------------|-----------------------|-----------|
| Real X11 session (Dev-Host login)                                 | `x11`                 | `x11`                 | real      |
| X11 session, Godot headless driver (harness `--headless`)         | `x11`                 | `x11`                 | real      |
| Wayland/GNOME (Mutter), native wayland driver                     | `wayland-mutter`      | `wayland-mutter`      | simuliert |
| Wayland/GNOME, Godot headless driver                              | `wayland-mutter`      | `wayland-mutter`      | simuliert |
| Wayland/Sway (wlroots)                                            | `wayland-wlroots`     | `wayland-wlroots`     | simuliert |
| Wayland/Hyprland (wlroots)                                        | `wayland-wlroots`     | `wayland-wlroots`     | simuliert |
| Wayland/KDE (unbekannte Compositor-Familie → Fallback)            | `wayland-generic`     | `wayland-generic`     | simuliert |
| XWayland — Wayland session + X11 display driver                   | `xwayland`            | `xwayland`            | simuliert |
| Unknown session_type (kein `XDG_SESSION_TYPE`/`DISPLAY`/`WAYLAND_DISPLAY`) | `noop`         | `noop`                | simuliert |

Quellen der Einträge:

- **real**: echter Lauf auf diesem Dev-Host (GNOME/X11), siehe §D.1.
- **simuliert**: Env-Override entweder direkt im Resolver-
  Klassifikations-Smoketest
  ([`scripts/resolver_classification_smoke.gd`](../scripts/resolver_classification_smoke.gd))
  oder als Harness-Fall
  ([`scripts/run_overlay_verification.sh`](../scripts/run_overlay_verification.sh)),
  siehe §D.2.

---

## C. Evidenzniveau pro Backend

Unterschied zwischen „Klasse existiert", „Resolver wählt sie unter
den dokumentierten Signalen" und „echte Compositor-Session
beobachtet". Dieses Raster macht transparent, wo wir stehen:

| Backend                 | Klasse existiert | Resolver-Auswahl bewiesen | Echte Session beobachtet                    |
|-------------------------|------------------|---------------------------|---------------------------------------------|
| `backend_x11`           | ja               | ja (real)                 | **ja** — GNOME/X11, siehe §D.1              |
| `backend_wayland_mutter`| ja               | ja (simuliert)            | offen — echte Mutter-Wayland-Session fehlt |
| `backend_wayland_wlroots`| ja              | ja (simuliert)            | offen — keine wlroots-Session auf Host      |
| `backend_xwayland`      | ja               | ja (simuliert)            | offen — benötigt echte Wayland-Login-Session mit Godot `--display-driver x11` |
| `backend_wayland_generic`| ja              | ja (simuliert)            | offen — echte KDE/Wayland- oder exotische Session fehlt |
| `backend_noop`          | ja               | ja (simuliert)            | offen — echte „unknown session" schwer reproduzierbar |

Merken: *alle* Backends delegieren heute an dieselben Controller.
Ein „real beobachtet" auf der Aktivierungsseite steht für die
Overlay-/Click-through-/AOT-Pfade in den anderen
Verifikationsdokumenten (siehe Linkliste oben). Was hier gemessen wird,
ist ausschließlich die Routing-Ebene.

---

## D. Messläufe

### D.1 Real — GNOME/X11 Dev-Host

```bash
scripts/run_overlay_verification.sh --headless report
```

Ergebnisausschnitt (Log-gefiltert):

```text
[report] session_type        = x11
[report] display_driver      = headless
[report] desktop_environment = ubuntu:GNOME
[report] backend.id                 = x11
[report] backend.description        = real X11 session — delegates to existing controllers
```

Der eigentliche „Dev-Host-mit-echtem-Display-Driver"-Lauf (nicht
`--headless`) wurde für die X11-AOT-Messungen bereits vollzogen,
siehe
[`x11_always_on_top_results.md`](./x11_always_on_top_results.md) §2.
Dort steht `driver=x11` mit denselben `session_type`-/`desktop`-
Werten; die Backend-Zeile im Report würde identisch `backend.id =
x11` zeigen.

### D.2 Simuliert — Wayland-Familie + Noop

Alle vier Fälle folgen demselben Muster: Env-Override mit passenden
`XDG_SESSION_TYPE` / `WAYLAND_DISPLAY` / `XDG_CURRENT_DESKTOP` /
`DISPLAY`, `SMOLIT_WINDOW_REPORT=1`, Godot headless.

**Wayland/Mutter** (`resolver-wayland-mutter`):

```text
[report] backend.id                 = wayland-mutter
[report] backend.description        = Wayland/GNOME (Mutter) — overlay/click-through delegate; always-on-top refuses by design
```

**Wayland/wlroots** (`resolver-wayland-wlroots`, Desktop=sway):

```text
[report] backend.id                 = wayland-wlroots
[report] backend.description        = Wayland/wlroots-family compositor — overlay/click-through delegate; always-on-top refuses by design; no layer-shell yet
```

**Wayland/Generic-Fallback** (`resolver-wayland-generic`, Desktop=KDE):

```text
[report] backend.id                 = wayland-generic
[report] backend.description        = generic Wayland fallback (no known compositor family) — overlay/click-through delegate; always-on-top refuses by design
```

**Noop** (`resolver-noop`, alle Session-Env-Variablen leer):

```text
[report] backend.id                 = noop
[report] backend.description        = unknown / non-classifiable session — all activation paths will refuse via their own capability gates
```

Warnung zur Einordnung: all diese Fälle setzen `XDG_SESSION_TYPE=
wayland` plus einen leeren `DISPLAY`. Die Capability-Detection
klassifiziert daraufhin `session_type=wayland`. Godot selbst hat
aber keinen echten Wayland-Socket — `display_driver` bleibt
`headless`. Das ist genau die Grenze, die wir in §C als „offen"
markieren: der Resolver-Pfad ist beobachtet, der Compositor-Pfad
nicht.

### D.3 Resolver-Klassifikations-Smoketest

```bash
scripts/run_overlay_verification.sh resolver-smoke
```

ruft [`scripts/resolver_classification_smoke.gd`](../scripts/resolver_classification_smoke.gd)
auf. Das Skript prüft neun synthetische Capability-Snapshots gegen
die erwartete `backend_id`. Letzter Lauf:

```text
PASS  real X11 session (dev host pattern)
PASS  X11 session, Godot headless driver
PASS  Wayland/GNOME (Mutter) — native wayland driver
PASS  Wayland/GNOME — Godot headless driver (simulation)
PASS  Wayland/Sway (wlroots family)
PASS  Wayland/Hyprland (wlroots family)
PASS  Wayland/KDE (unknown family → generic fallback)
PASS  XWayland — Wayland session + X11 display driver
PASS  Unknown session_type → noop
overall: PASS
```

Exit 0 = alle klassifiziert wie dokumentiert. Exit 1 zeigt eine
Regression im Resolver.

---

## E. XWayland — besondere Einordnung

XWayland ist der Grenzfall, bei dem man am ehesten „X11 wie immer"
annimmt und trotzdem falsch liegt. Unsere Einordnung:

- **Was Godot sieht.** Unter einer Wayland-Login-Session, in der
  Godot mit `--display-driver x11` läuft, ist
  `session_type == "wayland"` (Env-getrieben) und
  `display_driver == "x11"` (Godot-getrieben). Der Resolver erkennt
  das Signal-Paar und wählt `backend_xwayland`.
- **Was der Compositor sieht.** Das Smolit-Fenster ist ein
  XWayland-Client. EWMH-Atome wie `_NET_WM_STATE_ABOVE` können
  gesetzt werden, *werden* gesetzt vom X11-AOT-Controller — sein
  Gate prüft nur `session_type`, und Wayland fällt auch hier durch
  die Refusal-Klausel. Der Controller selbst ändert sich nicht.
- **Produktstance.** Keine AOT-Zusage unter XWayland. Overlay und
  Click-through laufen weiterhin über ihre eigenen Gates. Der
  `backend_xwayland`-Codeplatz existiert für spätere, bewusste
  Spezialfeinpfade (z. B. „unter XWayland dürfen wir AOT-Flag doch
  setzen und dem Nutzer ehrlich sagen: WM-abhängig") — aber
  **keine** dieser Policies ist in diesem Repo aktiv.
- **Wichtig.** XWayland ist **nicht** dasselbe wie „X11-Session".
  Das Stacking-Verhalten entscheidet der Wayland-Compositor, nicht
  der (XWayland-)X-Server. Die Doku in
  [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
  §A.3 und der Hinweis in
  [`x11_always_on_top_verification.md` §F.3](./x11_always_on_top_verification.md)
  gelten unverändert.

---

## F. Offene Messaufträge

- **Echte GNOME/Mutter-Wayland-Session.** Nicht auf diesem Host
  verfügbar. Lauf: `scripts/run_overlay_verification.sh --scene
  report` unter einer Mutter-Wayland-Login-Session. Erwartung:
  identischer Output wie §D.2 „wayland-mutter", aber mit
  `display_driver=wayland` statt `headless`.
- **Echte wlroots-Session** (Sway / Hyprland / Wayfire / river /
  labwc). Wie oben, mit dem jeweiligen Compositor. Erwartung:
  `backend_wayland_wlroots`.
- **Echte KDE/Wayland-Session.** Erwartung: `backend_wayland_generic`
  (keine bekannte Compositor-Familie auf der Allowlist).
- **Echte XWayland-Kombination.** Unter einer Wayland-Login-Session
  Godot explizit mit `--display-driver x11` starten. Erwartung:
  `backend_xwayland`. Sichtbares Stacking-Verhalten ist
  Compositor-abhängig und separat zu protokollieren.
- **Langzeitstabilität der Resolver-Wahl.** Ob sich `backend_id`
  zur Laufzeit jemals ändern müsste (z. B. weil ein Compositor-
  Restart durchschlägt) — bislang nicht relevant, weil
  `apply_all()` nur einmal in `_ready()` läuft.

Keine dieser offenen Punkte benötigt neue Plattformarbeit — sie sind
reine Verifikationsaufgaben.
