# Smolit Assistant – Linux Window & Overlay Architecture

Dieses Dokument beschreibt die **realistische Linux-Plattformgrundlage**
für Smolits sichtbare Desktop-Präsenz. Es ist bewusst kein
Implementierungsauftrag, sondern eine Forschungs- und
Architekturgrundlage — mit ehrlicher Trennung zwischen **Ist**, **Ziel**,
**Forschung** und **offene Punkte**.

Primäre Ziel-Distribution ist **Ubuntu 24.04 mit Wayland-Session**
(GNOME/Mutter). X11 bleibt als Fallback relevant, ist aber nicht
mehr das Default-Zielbild der Nutzerumgebung.

Einordnung gegenüber Nachbardokumenten:

- [`docs/ui_architecture.md`](./ui_architecture.md) — Godot/UI-Ebene,
  Scenes, EventBus, Presence-Controller. Dieses Dokument sagt **nicht**,
  wie UI-Code strukturiert ist, sondern **was Linux unter dem UI-Fenster
  zulässt**.
- [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  — Presence-, Automation-, Fidelity-Modi als Produktachsen. Dieses
  Dokument ist die plattformtechnische Realitätsprüfung dazu.
- [`docs/api.md`](./api.md) — IPC-Protokoll. Für Window-Verhalten
  irrelevant; Window-Verhalten passiert hostseitig und nicht über IPC.

---

## A. Zielbild

Das funktionale Zielbild für Smolit auf Linux ist:

- **Sichtbare Desktop-Präsenz.** Ein kleines, erkennbares Fenster/Overlay,
  das die drei Presence-Modi aus
  [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  §6 sichtbar macht: **Docked**, **Expanded**, **Action Mode**.
- **Optional immer sichtbar.** Der Nutzer kann Smolit als always-on-top
  Anker wählen — ohne die Arbeit in Fremdfenstern zu stören.
- **Leichtgewichtig.** Im Docked-Zustand kein Dauer-Rendering, keine
  permanente CPU-/GPU-Aktivität, keine globalen Hooks.
- **Kontrollierbar.** Nutzer kann Presence-Mode, Position, Größe und
  Click-through-Verhalten explizit steuern. Keine stille Rechteausweitung.
- **Nicht störend.** Kein Fenster, das sich selbst in den Vordergrund
  drängt, Fokus klaut oder Eingaben blockiert.
- **Symbolischer Workflow-Readout neben dem Avatar.** Die sichtbare
  Presence kann künftig neben dem Avatar einen kleinen
  read-only Workflow-/Action-Readout enthalten, sofern derselbe
  Overlay-Pfad bereits aktiv ist. Das ist ausdrücklich **keine
  neue Plattformzusage** und keine eigene Window-Behavior-
  Fähigkeit — Details in
  [`ui_architecture.md` §6a/§8a](./ui_architecture.md) und im
  Unterabschnitt „Workflow-Overlay innerhalb der Presence-Hülle"
  unten.

Ausdrücklich **nicht** Teil dieses Zielbildes:

- globale Desktop-Überwachung,
- ein Overlay, das Eingaben anderer Programme grundsätzlich mitliest,
- ein Overlay, das sich vor sicherheitsrelevante Systemdialoge schiebt.

---

## B. Plattformrealität Linux

Linux ist in Bezug auf Fenster-, Overlay- und Interaktionsverhalten
**nicht einheitlich**. Drei Achsen sind relevant:

1. **Display-Server / Protokoll.** Wayland vs. X11 — fundamentale
   Unterschiede in Berechtigungen für Overlay, Positionierung,
   Click-through, globale Eingaben, Screenshots.
2. **Compositor / Shell.** GNOME/Mutter, KDE/KWin, wlroots-basierte
   Compositors (Sway, Hyprland), XFCE (X11), Cinnamon, MATE, …
   Viele Fähigkeiten hängen am Compositor, nicht am Protokoll.
3. **Toolkit / Host-Fenster.** Godot selbst stellt nur so viel
   Window-Kontrolle bereit, wie das darunterliegende
   OS-Fenster-API erlaubt. GDExtension / natives Backend kann mehr,
   aber nicht alles.

Konkret für die Zielumgebung Ubuntu 24.04:

- Default-Session ist **Wayland (GNOME/Mutter)**. Eine X11-Session bleibt
  installierbar, ist aber zunehmend ein Sonderweg.
- Mutter akzeptiert **keine** Client-seitigen Fenstertyp-Hints wie
  `_NET_WM_STATE_ABOVE` aus X11 — solche Konzepte existieren in Wayland
  nicht protokollweit.
- Eine Reihe klassischer X11-Tricks (override-redirect-Fenster,
  XInput-Grabs, globale Screenshots) sind unter Wayland
  **protokollbedingt nicht mehr verfügbar** — das ist kein Bug,
  sondern Designentscheidung des Protokolls.

Konsequenz: **Keine pauschalen Annahmen.** Jede Overlay-/Window-Fähigkeit
muss pro Session-Typ und Compositor bewertet werden; Architektur und
Doku müssen das getrennt führen.

---

## C. Overlay-Fähigkeiten nach Kategorie

Die folgenden Einschätzungen sind bewusst vorsichtig. Wo das Verhalten
compositor-abhängig ist, wird das explizit genannt statt einer
Pauschalantwort.

**Einordnung.** Das in
[`ui_architecture.md` §6a/§8a](./ui_architecture.md) beschriebene
Workflow-Overlay ist **kein eigener Plattform-Fähigkeitstyp**,
sondern zusätzliche UI *innerhalb* derselben Host-/Overlay-Hülle
wie der Avatar. Die folgenden Kategorien (Always-on-top,
Transparenz, Click-through, Positionierung, …) verändern sich
durch diesen UI-Zusatz nicht, und es entsteht kein neuer
Capability-Eintrag in `window_capabilities.gd`.

### 1. Always-on-top

- **X11.** Allgemein realistisch über `_NET_WM_STATE_ABOVE` oder
  Window-Type-Hints (z. B. `_NET_WM_WINDOW_TYPE_DOCK`). Verhalten ist
  stabil und gut verstanden; einzelne WMs variieren in Details, aber
  der Grundmechanismus ist verfügbar.
- **Wayland.** Es gibt **kein protokollweites "always-on-top"** für
  gewöhnliche Toplevel-Fenster. Mögliche Wege:
  - **`wlr-layer-shell`** (wlroots-Compositors wie Sway, Hyprland,
    river) — liefert echte Overlay-/Dock-Layer. Unter **GNOME/Mutter
    nicht verfügbar**.
  - **Compositor-eigene Mechanismen** (z. B. GNOME-Shell-Extensions,
    KWin-Skripte) — invasiv, nicht portabel, auf Extension-API des
    jeweiligen Compositors angewiesen.
  - **XWayland.** Ein X11-Client unter Wayland kann ABOVE-Hints
    setzen; der Effekt hängt davon ab, wie der Compositor XWayland
    behandelt. In GNOME ist der Effekt in der Praxis
    eingeschränkt.
- **Fazit.** Unter X11 stabil; unter GNOME/Wayland (Ubuntu 24.04
  Default) **nicht zuverlässig über Standardwege**. Eine
  protokolltreue Lösung benötigt entweder einen anderen Compositor
  (wlroots + layer-shell) oder eine compositor-spezifische Extension.
- **Entscheidungsstand.** Siehe
  [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md):
  unter GNOME/Wayland **bewusst kein Always-on-top-Versprechen** im
  Standardpfad, GNOME-Shell-Extension ausdrücklich zurückgestellt,
  X11 bleibt ein optionaler Sonderpfad für später.

### 2. Transparenter Hintergrund

- **X11.** Mit Compositing (nahezu überall seit >10 Jahren) gut
  machbar — alpha-fähiges Visual + `RGBA`-Surface + `ARGB32`-Buffer.
- **Wayland.** Transparente Fenster sind protokollkonform und
  compositor-seitig im Normalfall unterstützt; der Client liefert
  einfach einen Buffer mit Alpha.
- **Godot-Spezifika.** Godot kann seit 4.x transparentes Rendering
  (`transparent=true` in Project/Window-Settings plus passender
  Display-Config). Entscheidend ist, dass auch das **Host-Fenster**
  (vom OS bereitgestellt) mit Alpha-fähigem Visual erzeugt wird.
  Unter Linux ist das seit Jahren Standard, aber einzelne
  Edge-Cases existieren (Snap/Flatpak-Sandboxen, Treiberpfade).
- **Fazit.** Realistisch unter beiden Protokollen, mit wenigen
  Compositor-spezifischen Edge-Cases.

### 3. Click-through / Mouse Passthrough

- **X11.** Realistisch über **XShape** — ein leeres bzw. geschnittenes
  Input-Region-Shape macht das Fenster für Mauseingaben durchlässig.
  Gut verstanden, gut dokumentiert, funktioniert seit Jahren.
- **Wayland.** Realisierbar über
  **`wl_surface.set_input_region(NULL)`** bzw. eine leere Region —
  das ist Teil des Core-Protokolls und daher compositor-übergreifend
  verfügbar, **nicht** an layer-shell oder andere Protokolle
  gebunden. Die Anwendung muss nur die eigene Input-Region explizit
  leeren bzw. auf definierte Zonen reduzieren.
- **Grenzen unter Wayland.**
  - Click-through bezieht sich auf das **eigene Fenster**, nicht auf
    globale Input-Umleitung.
  - Smolit kann nicht pauschal „überall darüber" clicken/tippen;
    globale Eingaben an Fremdfenster sind Interaktion **vorbei an
    Smolit**, nicht „durch" Smolit.
- **Godot-Spezifika.** Godot unterstützt Mouse-Passthrough auf
  Fenster-Ebene plus definierbare Passthrough-Polygone für
  interaktive Zonen. Unter Wayland hängt die Zuverlässigkeit vom
  Host-Fenster-Backend ab.
- **Fazit.** Unter beiden Protokollen realistisch; die „interaktive
  Zone + transparenter Rest"-Architektur (siehe §F) ist plattformfähig.

### 4. Fensterfokus / Fensterposition

- **X11.** Client kann Position explizit setzen
  (`XMoveWindow` / entsprechende GDK/Qt-Wrapper). Fokus lässt sich
  setzen; Fokus-Stealing-Prävention der WMs greift aber.
- **Wayland.** Client setzt Position **nicht** selbst. Positionierung
  ist Sache des Compositors:
  - **Toplevel-Fenster**: keine pixelgenaue Client-Positionierung.
    Protokolle wie `xdg-positioner` betreffen nur Popups.
  - **Layer-Shell-Fenster** (falls verfügbar): Anker und Margin
    gegen Screen-Ränder, keine absoluten Koordinaten.
  - **Fokus**: Ein Wayland-Client darf sich im Normalfall nicht
    selbst in den Vordergrund ziehen; Fokuswechsel ist Nutzeraktion.
- **Fazit.** „Kleiner Docked-Anker in der rechten unteren Ecke"
  ist unter X11 trivial, unter Wayland ohne layer-shell eine
  **Compositor-Frage**. Heuristische Screen-Edge-Positionierung
  gehört auf Wayland nicht in den Client, sondern an den Compositor.

### 5. Multi-Monitor

- **X11.** RandR liefert Screen-Geometrie; Client kann Monitore
  erkennen und Pseudo-Positionierung gegen Global-Koordinaten
  berechnen. Aufwendig, aber machbar.
- **Wayland.** `wl_output` liefert Monitor-Geometrie; aber
  **Positionierung pro Monitor** ist wieder compositor-abhängig.
  Layer-shell erlaubt einen Zielmonitor pro Surface. Für reguläre
  Toplevels bleibt es beim „Compositor entscheidet".
- **DPI / Skalierung.** Unterschiedliche Skalierungsfaktoren pro
  Monitor sind Realität. Godot benötigt sauberes HiDPI-Handling und
  darf keine hartkodierten Pixelmaße für Overlay-Positionierung
  nutzen.
- **Fazit.** Multi-Monitor ist **später** und **separat** zu lösen —
  nicht Teil eines ersten Overlay-MVPs.

### 6. Globales Desktop-Targeting

"Globales Targeting" meint hier: auf Fremdfenstern klicken, dort
tippen, deren UI strukturiert lesen, Screenshots/OCR über das
gesamte Display, Fokus gezielt an fremde Fenster geben.

- **X11.** Im Prinzip mit `XTest`, `XInput`, Screen-Capture,
  Window-Tree-Walks möglich — der klassische Pfad aller X11-Automation.
  Security-Modell ist schwach (jeder Client mit Display-Zugriff darf
  viel), aber funktional breit.
- **Wayland.** **Bewusst nicht** pauschal erlaubt. Stattdessen:
  - **XDG Desktop Portals** — kontrollierte Pfade für Screenshots,
    Screen-Casting, globale Shortcuts, File-Chooser etc., mit
    Nutzerzustimmung pro Session.
  - **AT-SPI / `org.a11y.Bus`** — Accessibility-Baum, strukturierte
    UI-Auslese. Verfügbar, aber Qualität stark abhängig von der
    Zielanwendung und deren A11y-Support.
  - **D-Bus-APIs** der Anwendung selbst (MPRIS, Kalender-Clients,
    Messenger-APIs).
  - **`libei` / `libeis`** — emerging Eingabe-Injection mit
    Compositor-Zustimmung; Adoption heterogen.
  - **Keine legitime Wayland-API** für ungefragte globale
    Tastendrücke in Fremdfenster.
- **Fazit.** Globales Targeting unter Wayland ist
  **plattformseitig eingeschränkt** und geht **immer** über
  dedizierte Backends (Portals / AT-SPI / app-eigene APIs). Das ist
  kein Smolit-Mangel, sondern Protokoll-Design — und deckt sich mit
  den Security-Leitplanken aus
  [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  §12.

---

## D. Risiko- / Machbarkeitsmatrix

Grobe Einordnung pro Fähigkeit. „v1" meint den nächsten ernsthaften
Overlay-MVP nach Phase 3.3; „compositor-dependent" bedeutet:
sinnvoll spezifizierbar, aber nicht ohne Compositor-Kenntnis
implementierbar.

| Fähigkeit                               | X11              | Wayland (GNOME/Mutter)      | wlroots (Sway/Hyprland)  | Einordnung           |
|-----------------------------------------|------------------|-----------------------------|--------------------------|----------------------|
| Transparenter Hintergrund               | leicht           | leicht                      | leicht                   | v1 realistisch       |
| Always-on-top Toplevel                  | leicht           | nicht zuverlässig           | leicht (layer-shell)     | compositor-dependent |
| Click-through / Input-Region            | leicht (XShape)  | leicht (set_input_region)   | leicht                   | v1 realistisch       |
| Interaktive Zonen im transparenten Rest | mittel           | mittel                      | mittel                   | v1 realistisch       |
| Pixelgenaue Client-Positionierung       | leicht           | nicht vorgesehen            | nur via layer-shell Anker| compositor-dependent |
| Snap-to-Edge (Client-driven)            | mittel           | nicht vorgesehen            | via layer-shell          | später               |
| Multi-Monitor-Positionierung            | mittel           | compositor-dependent        | via layer-shell output   | später               |
| Globale Eingabe-Injection               | mittel           | bewusst nicht               | bewusst nicht            | nicht v1, portal-only|
| Globaler Screenshot / OCR               | mittel           | nur via Portal              | nur via Portal           | nicht v1, portal-only|
| Accessibility-Tree lesen                | mittel (AT-SPI)  | mittel (AT-SPI)             | mittel (AT-SPI)          | v2+, app-abhängig    |
| Fokus gezielt zu Fremdfenstern          | mittel           | bewusst eingeschränkt       | bewusst eingeschränkt    | compositor-dependent |

Leseanleitung:

- **leicht** — Standardmechanismen reichen, gut dokumentiert.
- **mittel** — machbar, aber mit klarer Zusatzarbeit oder
  Edge-Cases (DPI, Multi-Monitor, WM-Verhalten).
- **compositor-dependent** — Architektur muss pro Compositor/Protokoll
  eine Strategie definieren, es gibt kein universelles Rezept.
- **bewusst nicht / portal-only** — Plattform erlaubt es aus
  Sicherheitsgründen nicht direkt; jeder Weg läuft über
  kontrollierte, nutzerauthentisierte Kanäle.

Für den aktuellen Core-Spike `focus_window` (siehe
[api.md](./api.md), §2.6) bedeutet das konkret: unter X11 liefert
z. B. `wmctrl -a {name}` einen ehrlichen, command-basierten MVP;
unter Wayland existiert **kein** generisches Äquivalent, der Core
meldet daher `BackendUnsupported("focus_window")` statt einen
Pseudo-Erfolg zu produzieren. Jede spätere Integration (Portal,
Compositor-spezifische Protokolle, a11y) wird zusätzlich und
bewusst gewählt, nicht unterstellt.

---

## E. Empfohlene Architekturstrategie

### Phase A – in-window Presence zuerst (heute)

- Presence-MVP läuft bereits in-window (Phase 3.3, siehe ROADMAP.md).
- Kein natives Overlay, kein Transparenz-Stunt, kein Click-through.
- Vorteile: plattformunabhängig, stabil, sofort testbar, keine
  Compositor-Abhängigkeit.
- Diese Phase ist der aktuelle Ist-Zustand und **gut genug**, um
  Core-/UI-Zusammenspiel zu stabilisieren, bevor Overlay-Arbeit
  beginnt.

### Phase B – Opt-in Overlay-Modus

Erste echte Overlay-Stufe; bewusst **opt-in**, nicht Default:

- Transparenter Hintergrund + Click-through-Fenster + eine definierte
  **interaktive Zone** (der Avatar selbst + Banner).
- Unter X11 sofort realistisch (XShape + ABOVE-Hint).
- Unter Wayland (GNOME) **ohne** garantiertes Always-on-top — der
  Modus läuft, verhält sich aber wie ein normales Toplevel in der
  Stacking-Order. Das ist ehrlich zu dokumentieren.
- Unter wlroots-Compositors optional über layer-shell, falls
  verfügbar; dann echtes Overlay.

### Phase C – Compositor-spezifische Pfade nur bei Bedarf

Erst wenn die Nutzung zeigt, dass ein echter always-on-top Anker
gebraucht wird:

- `wlr-layer-shell`-Pfad für wlroots.
- Untersuchung, ob eine **GNOME-Shell-Extension** für den Smolit-Anker
  tragfähig ist — mit der Einschränkung, dass Extensions
  GNOME-Version-abhängig und wartungsintensiv sind.
- X11-Pfad weiter pflegen für Nutzer mit X11-Session.

Click-through / interaktive Zonen sind **quer** zu diesen Phasen —
sie kommen in Phase B, nicht erst in C.

Snap-to-Edge, Idle-Movement, Multi-Monitor-Heuristik gehören
**frühestens in Phase C** und nur für die Pfade, in denen der Client
überhaupt positionieren darf.

---

## F. Window Behavior Abstraction

Spätere native Fenster-Fähigkeiten dürfen **nicht** quer durch
UI-/Scene-Code verteilt werden. Stattdessen empfiehlt dieses Dokument
eine klar getrennte Schicht (Name indikativ, keine
Implementierungszusage):

```text
window_behavior/                (später – keine Umsetzung in diesem Schritt)
├── api.rs / api.gd    # kleines Trait/Interface:
│                      #   set_always_on_top(bool)
│                      #   set_transparent(bool)
│                      #   set_click_through(bool, zones?)
│                      #   request_position(anchor, margin)
│                      #   current_capabilities() -> Capabilities
├── backend_x11.rs          # XShape, _NET_WM_STATE_ABOVE, RandR
├── backend_wayland_mutter.rs  # „kann kein ABOVE", Input-Region, Portal
├── backend_wayland_wlroots.rs # layer-shell + Input-Region
└── backend_noop.rs         # Fallback: Tut nichts, meldet ehrlich
                            # „nicht unterstützt"
```

Leitregeln für diese Abstraktion:

- **Capabilities statt Annahmen.** Jeder Backend meldet ehrlich, was
  es kann (`can_always_on_top`, `can_click_through`,
  `can_position_absolute`, …). UI entscheidet reaktiv, nicht
  spekulativ.
- **Noop ist ein gültiger Modus.** Wenn die Umgebung keine
  Overlay-Rechte gibt, darf Smolit trotzdem laufen — in-window.
- **Kein UI-Code kennt Protokoll-Details.** Keine X11-Atome, keine
  Wayland-Objekte, keine Portal-Aufrufe in Scene-Scripts.
- **Host- vs. Godot-Zuständigkeit offen.** Dieses Layer kann
  entweder aus einer GDExtension kommen oder aus einem Host-Prozess,
  der ein natives OS-Fenster besitzt und Godot nur als Renderer
  eingebettet hat. Entscheidung steht aus und ist bewusst nicht Teil
  dieses Dokuments.

Wichtig: Die *vollständige* Schicht existiert noch nicht. Ein erster,
opt-in kleiner Spike ist aber inzwischen gelandet — siehe §F.1.
Eine interne Rollenübersicht (Detection / Probe / Activation /
Reporting + Fassade + gemeinsames Vokabular) findet sich in
[`ui_architecture.md` §9.0](./ui_architecture.md); dieses Dokument
konzentriert sich auf die plattformseitige Begründung und die
einzelnen Phasen.

### F.1. Window Behavior Capability Spike v1 (Ist)

Seit diesem Spike trägt die Godot-UI eine kleine, bewusst flache
Window-Behavior-Linie unter `ui/scripts/window_behavior/`:

```text
ui/scripts/window_behavior/
├── window_behavior.gd                        # Fassade — einziger Aufrufpunkt aus main.gd
├── window_behavior_result.gd                 # gemeinsames Ergebnis-Vokabular
├── window_capabilities.gd                    # Capability-Detection (Env + DisplayServer)
├── window_probe.gd                           # opt-in Probe (SMOLIT_WINDOW_PROBE=1)
├── overlay_controller.gd                     # opt-in Overlay-Aktivierung (§F.2)
├── overlay_click_through_controller.gd       # opt-in Click-through-Folgeschritt (§F.3)
├── overlay_always_on_top_controller.gd       # X11-only AOT-Sonderpfad (§F.4)
├── overlay_runtime_report.gd                 # opt-in Diagnose-Report
├── backend_base.gd                           # Backend-Basisklasse (interne Vorbereitung)
├── backend_noop.gd                           # first-class Fallback für unknown Sessions
├── backend_x11.gd                            # X11-Delegations-Backend
├── backend_wayland_mutter.gd                 # Wayland/GNOME — delegiert, keine GNOME-Extension
├── backend_wayland_wlroots.gd                # Wayland/wlroots-Familie — delegiert + experimental stance marker (siehe docs/wlroots_overlay_path.md)
├── backend_xwayland.gd                       # Wayland-Session + X11-Driver (XWayland-Sonderfall)
├── backend_wayland_generic.gd                # Wayland-Fallback (unbekannter Compositor, z. B. KDE/Wayland)
└── backend_resolver.gd                       # Session + Desktop → Backend-Auswahl
```

Die Backend-Familie ist ausdrücklich **interne Strukturarbeit** — alle
Backends delegieren an die bestehenden Controller und ändern weder
Plattformverhalten noch Activation-Policy. Die Aufteilung der
Wayland-Seite nach Compositor-Familie (Mutter / wlroots / XWayland /
Generic) bildet nur die real existierende Plattformheterogenität
ab; Ziel: spätere echt unterschiedliche Pfade (z. B. `wlr-layer-shell`-
Wrapper, compositor-spezifische Policy) haben klar benannte
Zielorte, ohne `main.gd`, die Fassade oder den Runtime-Report erneut
anzufassen.

Verifikation der Backend-Zuordnung (welches Backend wählt der
Resolver unter welchen Bedingungen, und wie belastbar ist das heute
gemessen): siehe
[`window_behavior_backend_verification.md`](./window_behavior_backend_verification.md).
Erster **experimenteller Sonderpfad** der Familie ist
`backend_wayland_wlroots` — benannter Platzhalter für einen
späteren `wlr-layer-shell-unstable-v1`-Pfad, heute keine
Aktivierung. Forschungs-/Decision-Dokument:
[`wlroots_overlay_path.md`](./wlroots_overlay_path.md).
Der opt-in Runtime-Report (`SMOLIT_WINDOW_REPORT=1`) zeigt die
gewählte `backend.id` + `backend.description` in einem eigenen
Block; der Resolver-Klassifikations-Smoketest
(`scripts/resolver_classification_smoke.gd`) prüft neun synthetische
Session-/Driver-/Desktop-Kombinationen gegen die dokumentierte
Auswahl.

Was der Spike wirklich tut:

- **Capability-Detection.** `SmolitWindowCapabilities.detect()` liest
  Session-Typ (`XDG_SESSION_TYPE` / `WAYLAND_DISPLAY` / `DISPLAY`),
  den Godot-`DisplayServer`-Namen, `XDG_CURRENT_DESKTOP` und das
  Projekt-Setting `display/window/per_pixel_transparency/allowed`. Pro
  Fähigkeit (`transparency`, `click_through`, `always_on_top`) wird
  ein getaggter Status ausgegeben: `available`, `experimental`,
  `unsupported` oder `unknown`, jeweils mit einer kurzen `reason`.
- **Transparency-Probe.** Nur wenn `SMOLIT_WINDOW_PROBE=1` *und* das
  Projekt-Setting erlaubt es, setzt der Probe
  `WINDOW_FLAG_TRANSPARENT` zur Laufzeit und liest ihn zurück. Ohne
  `per_pixel_transparency/allowed` wird bewusst *nichts* verändert —
  der Flag allein hat zur Laufzeit keinen sichtbaren Effekt, und das
  steht so auch im Log.
- **Click-through-Probe.** Unter `SMOLIT_WINDOW_PROBE=1` setzt der
  Probe `WINDOW_FLAG_MOUSE_PASSTHROUGH` und liest ihn zurück. Das
  Log markiert deutlich, dass ein zurückgelesenes `true` nur sagt,
  „Godot hat das Flag akzeptiert", nicht „der Compositor respektiert
  es".
- **Revert-by-default.** Nach dem Probe werden beide Flags auf den
  vorherigen Zustand zurückgesetzt, damit der normale Presence-MVP
  nicht versehentlich click-through wird. Wer das Ergebnis stehen
  lassen will, setzt zusätzlich `SMOLIT_WINDOW_PROBE_REVERT=0`.

Was der Spike bewusst **nicht** tut:

- **Kein Always-on-top.** Das Capability-Modul markiert es unter
  GNOME/Wayland korrekt als `unsupported`, und der Probe versucht
  es gar nicht erst zu setzen. Es gibt in dieser Phase kein
  Promise-Versprechen, das wir unter der Ziel-Session (Ubuntu 24.04
  / GNOME/Mutter) nicht halten könnten.
- **Keine Scene-Änderungen.** Scenes, Presence-Controller und
  Avatar-Controller kennen `window_behavior/` nicht. Der einzige
  Kopplungspunkt ist ein einzelner `run_probe_if_enabled()`-Aufruf
  am Ende von `main.gd::_ready()`.
- **Keine Autoloads, kein neuer EventBus-Kanal, keine IPC-
  Nachrichten.** Ergebnisse laufen ausschließlich per `print()` ins
  Log.
- **Kein Portal-Aufruf, keine X11-/Wayland-Objekte, keine
  GDExtension.** Reines GDScript auf der in Godot verfügbaren
  Host-API.
- **Keine Backend-Matrix.** Die in §F skizzierten
  `backend_x11` / `backend_wayland_mutter` / `backend_wayland_wlroots`
  / `backend_noop` bleiben Zielarchitektur; dieser Spike ist ein
  ehrlicher erster Fingerabdruck, kein Backend.

Dieser Spike validiert damit primär zwei Aussagen:

1. Godot *kennt* `WINDOW_FLAG_TRANSPARENT` und
   `WINDOW_FLAG_MOUSE_PASSTHROUGH` als Flag-Identifier und
   akzeptiert Schreibzugriffe auf das Hostfenster.
2. Echte, sichtbare Transparenz hängt an einer Projekt-Setting-
   Entscheidung (`display/window/per_pixel_transparency/allowed`,
   plus `Viewport.transparent_bg` auf dem Root-Viewport), nicht nur
   an einem Runtime-Flag. Diese Entscheidung ist inzwischen gefallen
   und wird in §F.2 als nächster Schritt beschrieben.

### F.2. Overlay MVP Phase B (Ist, opt-in)

Aufbauend auf dem Capability-Spike ist jetzt ein **opt-in transparenter
Presence-Modus** gelandet — ein kleiner, ehrlicher erster Schritt in
Richtung Phase B aus §E. Er ist bewusst klein gehalten und keine
vollständige Overlay-Lösung.

Neue Komponente:

```text
ui/scripts/window_behavior/
├── overlay_controller.gd  # opt-in Overlay-Aktivierung
│                          # (Transparenz + Borderless), Capability-
│                          # gesteuert, Fallback-sicher
└── …                      # Fassade, Capabilities, Probe bleiben
```

Was der MVP wirklich tut, *nur* wenn `SMOLIT_UI_OVERLAY=1`:

- `display/window/per_pixel_transparency/allowed=true` ist als Projekt-
  Setting gesetzt (Pflicht-Opt-in zur Ladezeit; ohne dieses Setting
  hätte ein Runtime-Flag keinen sichtbaren Effekt).
- `Viewport.transparent_bg = true` auf dem Root-Window — damit der
  Renderer nicht mehr auf eine opake Hintergrundfarbe clear't.
- `DisplayServer.WINDOW_FLAG_TRANSPARENT = true` — Hostfenster führt den
  Alpha-Kanal wirklich durch.
- `DisplayServer.WINDOW_FLAG_BORDERLESS = true` — Smolit wirkt als
  floating Entity, kein Title-Bar-Frame.

Was der MVP bewusst **nicht** tut:

- **Kein Always-on-top.** Unter GNOME/Wayland protokollbedingt nicht
  zuverlässig; unter X11 zwar machbar, aber in dieser Phase nicht
  versprochen. Das Capability-Modul markiert es weiterhin ehrlich.
- **Kein produktives Click-through.** Ein naives
  `WINDOW_FLAG_MOUSE_PASSTHROUGH=true` würde das gesamte Fenster —
  inklusive Avatar, Banner und Eingabefelder — für Mauseingaben
  durchlässig machen. Ein ehrlicher Click-through-Schritt braucht
  definierte interaktive Zonen (Passthrough-Polygone) und bleibt
  deshalb Folgearbeit. Der Overlay-MVP läuft bewusst **ohne**
  Click-through-Aktivierung; Transparenz reicht, damit Smolit sichtbar
  wie ein Desktop-Begleiter wirkt.
- **Keine Snap-to-Edge, keine Multi-Monitor-Heuristik, keine
  compositor-spezifischen Pfade.** Layer-shell- und GNOME-Extension-
  Pfade bleiben Phase C.
- **Keine neue Presence-Wahrheit.** Der Presence-Controller, die Modi
  (`docked` / `expanded` / `action` / `disconnected`) und der Avatar
  bleiben unverändert. Der Overlay-MVP ändert ausschließlich die
  äußere Fensterhülle.
- **Kein neuer EventBus-Kanal, keine IPC-Nachricht, keine
  Scene-Eingriffe**, abgesehen von einem einzelnen Aufruf am Ende
  von `main.gd::_ready()`.

Capability-/Fallback-Semantik im Overlay-Controller:

| Bedingung                                         | Verhalten                                        |
|---------------------------------------------------|--------------------------------------------------|
| Overlay nicht requested                           | No-op, Fenster läuft unverändert.                |
| Overlay requested, Transparenz `available`        | Overlay aktiv (transparent + borderless).        |
| Overlay requested, Transparenz `experimental`     | Overlay aktiv, Log trägt ehrliche Warnung.       |
| Overlay requested, Transparenz `unsupported`      | Normaler Modus, honest reason im Log.            |
| Overlay requested, Transparenz `unknown`          | Normaler Modus, honest reason im Log.            |

In jedem Fall landet ein Log-Block mit Session-Typ, Capability-
Snapshot und dem tatsächlich gesetzten Zustand (`active=true/false`,
`transparency=…`, `borderless=…`). Keine stillen Magie-Umschaltungen.

Einordnung gegenüber Phase B aus §E:

- Phase B sagt: *"Transparenter Hintergrund + Click-through-Fenster +
  definierte interaktive Zone"*. Dieser MVP liefert den Transparenz-
  Teil ehrlich. Click-through bleibt für einen Folgeschritt reserviert,
  sobald interaktive Zonen modelliert sind.
- Phase B sagt weiter: *"Unter Wayland (GNOME) ohne garantiertes
  Always-on-top — der Modus läuft, verhält sich aber wie ein normales
  Toplevel in der Stacking-Order. Das ist ehrlich zu dokumentieren."*
  Der MVP verhält sich exakt so.

Offene Punkte, die ausdrücklich **nicht** Teil dieses Schrittes sind
(siehe §G und ROADMAP.md Phase 3b):

- wlroots `layer-shell`-Pfad,
- Snap-to-Edge / Idle-Movement,
- Multi-Monitor-Heuristik,
- compositor-spezifische Always-on-top-Strategien,
- Packaging / Autostart.

Interaktive Zonen / Passthrough-Polygone sind inzwischen als kleiner
opt-in Folgeschritt gelandet — siehe §F.3.

### F.3. Overlay Click-through Folgeschritt (Ist, opt-in)

Auf dem Overlay-MVP aus §F.2 sitzt ein **zweiter opt-in Schritt**, der
produktives Click-through mit definierten interaktiven Zonen einführt.
Er ist bewusst so geschnitten, dass er nur auf einer bereits aktiven
Overlay-Hülle aufsetzt und ansonsten ehrlich in den normalen Overlay-
Modus zurückfällt.

Neue Komponente:

```text
ui/scripts/window_behavior/
├── overlay_click_through_controller.gd  # opt-in Click-through-Aktivierung
│                                        # mit interaktiven Zonen,
│                                        # capability-gesteuert,
│                                        # fallback-sicher
└── …                                    # Fassade, Capabilities, Probe,
                                         # Overlay-Controller bleiben
```

**Zwei Opt-ins, nie still verkettet.** Click-through wird *ausschließlich*
aktiv, wenn beide Env-Variablen gesetzt sind:

- `SMOLIT_UI_OVERLAY=1` — Voraussetzung aus §F.2 (transparent + borderless
  Hülle).
- `SMOLIT_UI_CLICK_THROUGH=1` — eigene Opt-in-Grenze für den
  Passthrough-Schritt. Ohne diese Variable läuft der Overlay-MVP wie
  bisher, ganz ohne Click-through.

**Interaktive Zonen (explizite Allowlist).** Der Controller trägt eine
bewusst geführte Liste klickbar zu haltender Knoten; nicht-gelistete
Container und „zufällig sichtbare" Layout-Reste werden *nicht* in die
Passthrough-Schutzregion aufgenommen:

| Knoten                 | Zweck                                           |
|------------------------|-------------------------------------------------|
| `Avatar`               | Klickbare Presence-Figur (immer gebraucht).     |
| `VBox/HeaderRow`       | Status-Zeile / ggf. spätere Header-Controls.    |
| `VBox/ActionBanner`    | Action-/Target-Mapping-Anzeige während Action.  |
| `VBox/ApprovalBanner`  | Approve/Deny-Buttons während Approval.          |
| `VBox/DiscoveryPanel`  | Discovery-Liste inkl. Select/Clear-Buttons.     |
| `VBox/DockPanel`       | Log + Volltext-Eingabe im Expanded-Modus.       |
| `CompactInputPanel`    | Compact-Quick-Input am Docked-Avatar.           |

Pro Knoten durchläuft das Rect vor der Aufnahme eine kleine
Validierungskette:

1. Knoten muss `is_visible_in_tree()` sein.
2. Rohsize muss `> 0` sein (Layout-noch-nicht-stabil-Fälle fallen
   heraus).
3. Rect wird an die Viewport-Bounds geclamt (`Rect2.intersection`);
   off-screen-Anteile werden abgeschnitten.
4. Die geclamte Größe muss die Mindestkantenlänge überschreiten
   (`_MIN_ZONE_DIMENSION`, aktuell 2 px) — sonst wird die Zone als
   degeneriert verworfen.

Erst gültige Zonen landen in der Bounding-Rect-Union.

**Single-Polygon-Grenze des Godot-API.** Godots
`DisplayServer.window_set_mouse_passthrough(region)` erwartet pro
Fenster genau *einen* Polygonpfad. Mehrere disjunkte interaktive
Zonen werden im aktuellen MVP daher zur **Bounding-Rect-Union** aller
gültigen Zonen vereinigt und als einzelnes Rechteckpolygon an den
DisplayServer übergeben. Leerer Raum *innerhalb* dieser Union bleibt
klickbar — das ist bewusst noch nicht das finale Interaktionsmodell,
sondern ein ehrlich grobes MVP. Ein echter Multi-Polygon-Schritt
(XShape-Multirect unter X11 bzw. `wl_surface.set_input_region` mit
mehreren Rechtecken unter Wayland) bleibt Folgearbeit.

**Refresh-Lifecycle.** Der Controller verbindet beim Aktivieren
genau einmal `visibility_changed` und `resized` auf jeden getrackten
Knoten sowie `resized` auf den Anker. Zusätzlich schedult er
*einmalig* einen `call_deferred("_initial_refresh")`, um den Fall zu
fangen, dass einzelne Panel-Größen zu `_ready()`-Zeit noch nicht
final stabil sind (ein call_deferred läuft am Ende des aktuellen
Idle-Frames, also nach dem ersten Layout-Pass). Spätere Änderungen
(neues Banner erscheint, Window resized) laufen über die Signale ins
zentrale `_refresh_region()`. Kein Polling, kein Timer-Loop.

Der Refresh-Pfad dedupliziert: feuert mehrere Signale in derselben
Frame-Tranche und ergibt sich aus den neuen Zonen *dieselbe* Bounding-
Box wie zuletzt, passiert nichts — weder API-Call noch Log. Erst eine
echte Änderung (neue Box-Position oder Box-Größe) triggert einen
erneuten `window_set_mouse_passthrough`. Fallen alle Zonen vorübergehend
weg, räumt der Controller die Region leer und setzt sich auf
`active=false`, damit kein Halb-Zustand hängt. Das sind die einzigen
Scene-seitigen Berührungspunkte — keine neuen Signale im EventBus,
keine Änderung an Presence- oder Avatar-States.

Capability-/Fallback-Semantik im Click-through-Controller:

- **`SMOLIT_UI_OVERLAY` nicht gesetzt.** No-op, Controller wird nicht
  persistiert. Log-Grund: „overlay not requested".
- **Overlay gesetzt, Click-through nicht gesetzt.** Overlay wie in
  §F.2. Log-Grund: „click-through not requested".
- **Click-through gesetzt, Overlay aber nicht aktiv.** Kein
  Passthrough. Log-Grund: „overlay inactive — click-through would
  leave avatar over an opaque window".
- **Click-through gesetzt, Capability `available` / `experimental`,
  gültige Zonen vorhanden.** Passthrough aktiv auf Bounding-Union der
  Zonen; Log enthält die Phasen-Zusammenfassung, Bounds und Zonenliste.
  Bei `experimental` zusätzlich eine honest warning.
- **Click-through gesetzt, Capability `unsupported` / `unknown`.** Kein
  Passthrough. Log-Grund: „click-through capability … — …".
- **Click-through gesetzt, Capability tragfähig, aber keine gültigen
  Zonen ableitbar (alles unsichtbar, alle Rects degeneriert, oder
  Layout noch nicht stabil).** Kein Passthrough; Controller wartet
  jedoch auf Signale und deferred-Refresh. Log-Grund: „no valid
  interactive zones yet — waiting for first stable layout".

Jeder Pfad erzeugt **eine** Phasen-Zusammenfassung mit den Achsen
`requested / overlay_requested / overlay_active / capable /
zones_derived / zones_valid / active`, optional gefolgt von Capability-
Details, Bounds, Zonenliste und einer `reason`-Zeile. Refreshes loggen
nur bei echter Bounds-Änderung (Dedup).

Keine stillen Umschaltungen.

Was der Folgeschritt bewusst **nicht** tut:

- **Kein neuer IPC-Kanal, kein neuer EventBus-Signalpfad, keine neue
  Presence-Wahrheit.** Click-through lebt ausschließlich in der
  Fensterhülle; Presence, Avatar und Scenes kennen den Controller
  nicht.
- **Keine compositor-spezifischen Pfade.** Kein layer-shell, keine
  GNOME-Extension, keine GDExtension. Nur Godots DisplayServer-API.
- **Kein Always-on-top.** Weiter ausdrücklich nicht versprochen; siehe
  §C.1 / §E.
- **Keine Multi-Polygon-Shapes, kein XShape-Feintuning.** Eine einzelne
  Bounding-Box pro Snapshot ist die bewusste MVP-Grenze.
- **Kein Snap-to-Edge, keine Multi-Monitor-Heuristik.** Gehören
  frühestens in Phase C (§E).
- **Keine stillschweigende Aktivierung.** Ein fehlendes Env-Flag, eine
  unsupported-Capability, ein nicht aktiver Overlay-Modus oder eine
  leere Zonenableitung führen immer zu einer ehrlichen Log-Zeile mit
  `active=false` und Grund.

Offene Punkte, die ausdrücklich **nicht** Teil dieses Folgeschritts
sind:

- Multi-Polygon-Passthrough (mehrere disjunkte Rechtecke statt
  Bounding-Union).
- Backend-spezifische, robustere Zonenableitung (z. B. echte
  Screen-Geometrie pro Monitor, HiDPI-bewusste Koordinatenumrechnung
  außerhalb eines Root-Controls).
- wlroots `layer-shell` und GNOME-Extension-Pfade.
- Packaging / Autostart.

---

## G. Linux-spezifische offene Punkte

Die folgenden Fragen sind explizit **Forschung**, nicht Entscheidung:

- **Wayland-Constraints, real gemessen.** Wie stabil ist
  Transparenz + Input-Region + Godot-Rendering unter GNOME 46/47 auf
  Ubuntu 24.04? Welche Edge-Cases (Fractional Scaling, Nvidia-
  Treiber, XWayland-Fallback) treffen Smolit?
- **Always-on-top unter GNOME.** Gibt es einen vertretbaren Pfad
  ohne Shell-Extension? Alternativ: Extension als offizieller,
  signierter Helfer — Aufwand und Pflegekosten realistisch
  einschätzen.
- **wlroots-Pfad.** Ist `wlr-layer-shell` der richtige Weg für
  Docked-Anker? Wie verhält er sich bei Fullscreen-Fremdfenstern,
  Idle-Inhibit, Screen-Lock?
- **X11-Fallback.** Wie lange halten wir X11 als gleichberechtigten
  Pfad? Ubuntu 24.04 hat X11 noch als wählbare Session — aber
  Upstream (GNOME, KDE) bewegt sich weg davon.
- **GNOME-/Ubuntu-Verhalten im Detail.** Was macht der Ubuntu-Stack
  mit Dock, Rightclick-Menüs, Notify-OSD, Wayland-Portal-Prompts?
  Wie integriert sich ein Smolit-Overlay in die bestehende
  Shell-UX, ohne zu kollidieren?
- **Portals.** Welche Portals brauchen wir realistisch
  (Screenshot, Screen-Cast, GlobalShortcuts, RemoteDesktop,
  OpenURI)? Wie werden Nutzerprompts UX-seitig eingebunden?
- **Accessibility / AT-SPI.** Wie gut ist AT-SPI unter GNOME heute
  für typische Smolit-Zielanwendungen (Browser, Terminals,
  Electron-Apps)? Was liefert es **nicht**?
- **Godot-Grenzen vs. natives Host-Windowing.** Reichen Godots
  Fenster-Flags für unsere Phase-B-Ziele? Oder müssen wir
  GDExtension / einen Host-Prozess planen? Diese Entscheidung
  betrifft Paketierung, Autostart, Crash-Recovery und gehört
  explizit **noch nicht** getroffen.

Jeder dieser Punkte ist eine **Forschungsaufgabe**, keine
Produktzusage.

### G.1. Aktuelle Messlinie (Verifikationsspike)

Der nächste konkrete Schritt in dieser Linie ist *kein* Feature,
sondern **reale Messung**. Grundlage ist die Verifikationsmatrix in
[`linux_overlay_verification_matrix.md`](./linux_overlay_verification_matrix.md),
angereichert durch den opt-in Diagnostic-Report
(`SMOLIT_WINDOW_REPORT=1`, siehe §F.2 / §F.3 und
`ui/scripts/window_behavior/overlay_runtime_report.gd`).

**Geprüfte Hypothesen / Messziele** — jeweils explizit *Fragen*, nicht
gesetzte Aussagen:

- **Passthrough-Polygon unter Mutter/GNOME-Wayland.** Respektiert
  Mutter das von Godot gesetzte `window_set_mouse_passthrough`-Polygon
  zuverlässig? Fallen Klicks auf leere Bereiche *außerhalb* der
  Bounding-Box tatsächlich an das darunterliegende Fenster durch,
  auch über App-Grenzen hinweg? Gibt es Unterschiede zwischen nativem
  Wayland-Client und XWayland?
- **Stabilität bei Layout-Wechsel.** Wenn ein Action-/Approval-Banner
  auftaucht oder das DockPanel sichtbar wird, greift unser signal-
  getriebener Refresh schnell genug, dass keine tot klickbaren Flächen
  hängen bleiben? Wie verhält sich die Bounding-Union im realen
  Docked→Expanded-Wechsel?
- **Transparenz unter realen Treibern.** Liefert
  `WINDOW_FLAG_TRANSPARENT` + `Viewport.transparent_bg` unter den
  verbreiteten Intel-/AMD-/Nvidia-Treiberpfaden visuell stabile
  Alphabuffer? Gibt es Compositor-/Treiber-Kombinationen, bei denen
  der Alphakanal aussetzt oder flackert?
- **Fractional Scaling.** Wie verhalten sich die geclampten
  Viewport-Koordinaten des Click-through-Controllers bei GNOME-
  Skalierung 125 %/150 %? Entstehen Off-by-<1px-Lücken am Rand der
  Bounding-Box? Schneidet der Viewport-Clamp in Subpixel-Fällen zu
  viel ab?
- **Grenze der Single-Polygon-Union.** Ab wann stört Nutzer der
  Umstand, dass Leerraum *innerhalb* der Bounding-Box klickbar bleibt?
  Das ist der primäre Trigger für einen späteren Multi-Polygon-
  Schritt — wir wollen Nutzung beobachten, bevor wir die Komplexität
  eingehen.
- **Probe vs. Overlay-Kohärenz.** Deckt sich die Probe-Aussage (setzt
  Flag, liest zurück) unter realer Session mit dem, was der Overlay-
  Controller später macht? Wenn nicht: wo liegt der Unterschied, und
  ist das ein Compositor- oder ein Godot-Effekt?

**Was architekturrelevant wäre**, je nach Messbefund:

- Starke Compositor-Abhängigkeit → Bestätigung, dass eine
  Capability-gesteuerte Matrix (§D) der richtige Rahmen ist.
- Systematische Transparenz-Ausfälle unter bestimmten Treibern →
  Opt-out-Schalter oder Fallback-Viewport-Background in §F.2
  nachziehen.
- Mutter-Edge-Cases bei Passthrough-Polygon → klarer Indikator für
  Multi-Polygon-Folgearbeit (§F.3) und ggf. GDExtension-Diskussion
  (§G).
- Fractional-Scaling-Lücken → Hinweis auf robustere Koordinaten-
  Transformation (Viewport-relativ ↔ Host-Window-Pixel).

**Nicht-Ziele der Messlinie.** Keine Entscheidung über GDExtension
vs. Host-Prozess, keine Festlegung auf einen Compositor-spezifischen
Pfad (§C/§E), kein Always-on-top-Versuch. Die Messlinie liefert
*Daten*, keine Architekturfestlegung.

### G.2. Entscheidungssnapshot — Always-on-top

Der §G-Forschungspunkt „Always-on-top unter GNOME" ist in ein eigenes
Entscheidungsdokument überführt:
[`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md).

Kurzfassung:

- **Standardpfad auf GNOME/Wayland (Ziel-Session).** Kein
  Always-on-top-Versprechen. Sichtbare Desktop-Präsenz läuft
  weiterhin über Overlay-MVP (§F.2) + opt-in Click-through (§F.3).
  Der Refusal-Pfad des X11-only Controllers ist per
  Env-Override-Simulation empirisch belegt — Controller verweigert,
  `active=false`, klarer `reason`. Rohdaten in
  [`wayland_always_on_top_refusal_results.md`](./wayland_always_on_top_refusal_results.md).
  Echter Mutter-Wayland-Compositor-Lauf steht aus.
- **GNOME-Shell-Extension.** Ausdrücklich zurückgestellt (Pflege-
  aufwand, Versionsbindung, Sicherheitsmodell). Nur bei klarer,
  messbarer Nachfrage und eigenem Projektrahmen wieder auf dem Tisch.
- **X11-Sonderpfad — umgesetzt (§F.4), protokoll- und UX-level
  gemessen (GNOME/X11).** Kleiner opt-in MVP über
  `WINDOW_FLAG_ALWAYS_ON_TOP`, capability- und session-gated. Auf dem
  Entwicklungshost (GNOME/X11, 2026-04-22) sind jetzt beide Ebenen
  gemessen: `_NET_WM_STATE_ABOVE` steht am Fenster, und ein
  Folgelauf mit xterm-Peer zeigt, dass Smolit im Stacking oberhalb
  bleibt — auch bei fokussiertem Peer, über Minimize/Restore, und
  sogar mit fullscreen-xterm. Sticky-über-Workspaces ist
  ausdrücklich nicht Teil des Pfads. Andere X11-WMs (KDE/KWin,
  Xfwm4, Openbox, Fluxbox) und komplexere Peers (Browser-F11,
  Electron, Videospieler, Auth-Dialoge) bleiben ungemessen. Details:
  [`x11_always_on_top_verification.md`](./x11_always_on_top_verification.md)
  §F.1 und
  [`x11_always_on_top_results.md`](./x11_always_on_top_results.md)
  „GNOME/X11 UX-Messung (Folgelauf)". Ausdrücklich kein Standard-MVP
  und **kein Wayland/GNOME-Promise**.
- **wlroots/layer-shell.** Dokumentierte Option, kein aktuelles Ziel.
- **Diagnostische Probe.** Der bestehende opt-in
  `SMOLIT_WINDOW_PROBE=1`-Pfad enthält einen kurzen, reversiblen
  AOT-Flag-Versuch. Er liefert empirisches Material („flag accepted
  by API — not a user-visible guarantee under Mutter") und ändert
  den produktiven Lauf nicht.

Produktseitige Kurzaussage: siehe §F in
[`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md).

### F.4. X11-only Always-on-top Sonderpfad (Ist, opt-in)

Kleiner, bewusst eng geschnittener Produktivpfad in
`ui/scripts/window_behavior/`:

```text
ui/scripts/window_behavior/
└── overlay_always_on_top_controller.gd  # opt-in AOT-Sonderpfad,
                                         # X11-only, capability-gated
```

Aktiviert **nur**, wenn alle Gates erfüllt sind:

1. `SMOLIT_UI_ALWAYS_ON_TOP=1` ist gesetzt (eigenes, separates Opt-in
   — nicht Nebeneffekt des Overlay- oder Click-through-Pfads).
2. `session_type == "x11"`. Wayland, XWayland-Grauzone und `unknown`
   fallen explizit raus.
3. `display_driver != "headless"`. Headless liefert kein
   aussagekräftiges Stacking-Verhalten.
4. Godot kennt `WINDOW_FLAG_ALWAYS_ON_TOP`.
5. Capability-Status für `always_on_top` ist `available`.

Im Erfolgspfad setzt der Controller das Flag einmalig, liest den
Godot-seitigen Zustand zurück und loggt:

```text
[always-on-top] requested=true session=x11 driver=x11 candidate=true applied=true observed=true active=true
[always-on-top] capability=available (…)
[always-on-top] reason: X11 WMs typically honour _NET_WM_STATE_ABOVE — behaviour still depends on the specific WM, not a universal guarantee
[always-on-top] note: X11-only special path; Wayland/GNOME intentionally not targeted here (see docs/linux_always_on_top_decision.md)
```

Fallback-Semantik (alle ergeben `active=false` mit konkreter
`reason`-Zeile):

- **`SMOLIT_UI_ALWAYS_ON_TOP` nicht gesetzt.** No-op, reason
  „always-on-top not requested".
- **Session ist `wayland` / `unknown` / nicht `x11`.** No-op, reason
  „always-on-top special path is X11-only; …".
- **`display_driver == "headless"`.** No-op, reason „headless does
  not reflect real WM stacking".
- **Capability-Status nicht `available`.** No-op, reason „capability
  not available on this session".
- **`WINDOW_FLAG_ALWAYS_ON_TOP` dem Godot-Build unbekannt.** No-op,
  reason „flag not known to this Godot build".
- **Flag gesetzt, Rücklesewert `false`.** `applied=true observed=false`,
  reason „flag write did not stick".

Was der Pfad bewusst **nicht** tut:

- **Kein produktiver Pfad unter Wayland/GNOME.** Die Entscheidung in
  [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
  wird hier nicht umgangen.
- **Keine GNOME-Shell-Extension, kein layer-shell, keine GDExtension.**
- **Kein Nebeneffekt von Overlay / Click-through.** Jede Linie hat ihr
  eigenes Opt-in.
- **Keine neue IPC-Nachricht, kein EventBus-Kanal, keine neue
  Presence-Wahrheit.** AOT lebt ausschließlich im Hostfenster.
- **Keine Revert-Logik beim Beenden.** Godot räumt beim Window-Close
  selbst auf.
- **Keine Feature-Zusage „Always-on-top unter Linux".** Was geht und
  was nicht, steht pro WM/Compositor — der Log-`note`-Block benennt
  das ausdrücklich.

---

## G.3 Workflow-Overlay innerhalb der Presence-Hülle (Ziel-Zustand)

Dieser Unterabschnitt ordnet den in
[`ui_architecture.md` §6a/§8a](./ui_architecture.md) beschriebenen
Workflow-Readout plattformseitig ein. Er ist **Ziel-Zustand**,
heute nicht implementiert.

MVP-Position, bewusst konservativ:

- **Teil derselben Presence-/Overlay-Hülle**, kein separates
  Multiwindow-System. Das Workflow-Overlay ist zusätzliche UI
  innerhalb des bestehenden Godot-Hostfensters, nicht ein
  zweites Toplevel. Kein `WINDOW_FLAG`-Tanz, kein neues
  Window-Spawning.
- **Gleiche Plattformgrenzen** wie das Avatar-/Presence-Fenster.
  Die Transparenz-, Click-through- und Always-on-top-Aussagen
  aus §C bleiben *punktgenau* dieselben — das Overlay erbt sie
  implizit, weil es dasselbe Fenster ist.
- **Keine zusätzlichen Rechte.** Kein globales Desktop-Wissen,
  kein Zugriff auf fremde Fenster, keine Lese-Rechte auf
  Compositor-Protokolle jenseits dessen, was der Avatar ohnehin
  nutzt.
- **Kein neuer Always-on-top-Pfad.** Das Overlay erzeugt keine
  neue Stapelungs-Anforderung.
- **Kein eigener compositor-spezifischer Sonderpfad.** Weder
  `backend_wayland_wlroots` noch irgendein anderes Backend-Target
  bekommt durch das Workflow-Overlay eine Sonderbehandlung.
- **Spätere Hilfsfenster-Experimente** (z. B. ausklappbarer
  Workflow-Graph als eigenes Toplevel) sind ausdrücklich **nicht**
  Teil des MVP/Standardpfads. Falls so etwas jemals kommt, braucht
  es seinen eigenen Entscheidungs- und Verifikationstrack.

Fazit in einem Satz: das Workflow-Readout braucht **keine neue
Capability** — es lebt innerhalb der bereits vorhandenen
Transparenz-/Overlay-/Click-through-Grenzen und wird durch
zusätzliche Sichtbarkeit erreicht, nicht durch zusätzliche
Plattformrechte.

---

## H. Konsequenzen für Smolit

Aus der Plattformrealität und der empfohlenen Strategie ergeben sich
direkte Konsequenzen:

- **Godot-UI bleibt Presence- und Rendering-Schicht.** Keine
  Plattform-Hacks in Scenes oder Autoloads. Presence-Logik und
  Animation kennen das Host-Fenster nur über eine schmale
  Capability-/Event-Grenze.
- **Native Fensterkontrolle läuft über eine eigene Schicht.** Ob als
  GDExtension oder als separater Host-Prozess, ist offen; die
  Schnittstelle ist es nicht — siehe §F.
- **Overlay-Fähigkeiten sind optional und modular.** Smolit muss auch
  dann laufen, wenn keine davon verfügbar ist. Der Noop-Pfad ist
  first-class, nicht Zweitbürger.
- **Wayland ist Default-Annahme, nicht X11.** Dokumentation,
  Feature-Matrizen und Tests müssen Wayland zuerst abdecken, X11 als
  dokumentierten Fallback.
- **Keine protokollbedingten Fähigkeiten als selbstverständlich
  dargestellt.** „Always-on-top" und „global klicken" sind unter
  Wayland **keine** Selbstverständlichkeiten; jede Kommunikation mit
  Nutzern und Stakeholdern muss das widerspiegeln.
- **Low-End-Hardware und Stabilität vor Overlay-Ehrgeiz.** Ein
  stabiles in-window Presence schlägt ein wackliges Overlay. Der
  Überlaufweg ist immer: in-window rendern statt halb funktionierender
  Overlay-Zustand.
- **Security-Leitplanken aus
  [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  §12 bleiben führend.** Plattform-Constraints sind Verbündete
  dieser Leitplanken, keine Hindernisse.

---

## I. Glossar

Kurze Begriffsklärung für dieses Dokument; keine vollständige
Referenz.

- **Compositor.** Prozess, der unter Wayland (und modernen X11-Setups)
  Fenster zu einem Desktop-Bild zusammensetzt. Beispiele:
  Mutter (GNOME), KWin (KDE), Sway/Hyprland/river (wlroots).
- **Layer-Shell.** Wayland-Protokollerweiterung
  (`wlr-layer-shell-unstable-v1`), die echte Overlay-/Dock-Layer
  oberhalb oder unterhalb normaler Toplevels erlaubt. wlroots-Pfad;
  **nicht in GNOME/Mutter**.
- **XDG Desktop Portal.** D-Bus-Dienst-Familie, die sicherheitsrelevante
  Funktionen (Screenshot, Screen-Cast, GlobalShortcuts,
  RemoteDesktop, OpenURI, …) über Nutzerzustimmungsprompts
  bereitstellt. Standardweg für sicherheitsrelevante Fähigkeiten
  unter Wayland und sandboxed Apps (Flatpak/Snap).
- **AT-SPI.** Linux-Accessibility-Bus. Erlaubt strukturierte
  UI-Auslese (Widget-Baum, Rollen, Labels) bei Anwendungen, die A11y
  unterstützen.
- **XShape.** X11-Extension, die die sichtbare und die
  Input-Region eines Fensters unabhängig voneinander schneiden kann.
  Grundlage klassischer X11-Click-through-Overlays.
- **XWayland.** X11-Kompatibilitätsschicht innerhalb eines
  Wayland-Compositors. Erlaubt X11-Clients unter Wayland, mit
  teilweise eingeschränktem Verhalten (z. B. Fokus- und
  Stacking-Semantik).
- **libei / libeis.** Emerging Eingabe-Emulations-Stack
  (Compositor-seitig opt-in), Kandidat für kontrollierte
  Eingabe-Injection unter Wayland.
