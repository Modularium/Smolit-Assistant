# wlroots-Overlay-Pfad — Forschungs- und Vorbereitungsdokument

Dieses Dokument ist **keine Feature-Doku** und **keine Aktivierungs-
anleitung**. Es ist das Architektur- und Forschungspapier für einen
*späteren* experimentellen Spezialpfad für wlroots-basierte Wayland-
Compositoren (Sway, Hyprland, Wayfire, river, labwc). Der aktuelle
Codestand kennt den Pfad als benannten, experimentell markierten
Platzhalter in `ui/scripts/window_behavior/backend_wayland_wlroots.gd`;
produktive wlroots-Aktivierung existiert **nicht**.

Einordnung gegenüber Nachbardokumenten:

- [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  §C und §E — Plattformrealität, Phasenmodell.
- [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
  — warum wlroots-Wege nicht als GNOME-Lösung durchgehen.
- [`window_behavior_backend_verification.md`](./window_behavior_backend_verification.md)
  — Evidenzstand pro Backend (wlroots heute: Resolver-Auswahl
  simuliert, echte Session offen).
- [`ui_architecture.md`](./ui_architecture.md) §9.0 — interne
  Rollenverteilung und Backend-Familie.

---

## A. Zielbild (spätere Stufe)

Wenn wlroots-Sessions ein relevantes Nutzersegment werden (heute
nicht quantifiziert), wäre das funktionale Zielbild:

- **Sichtbarer Dock-/Overlay-Layer.** Smolit könnte unter wlroots
  über `wlr-layer-shell-unstable-v1` einen echten Overlay-/Dock-
  Layer belegen, statt wie ein reguläres Toplevel gestapelt zu
  werden. Das ist der Weg, den Wayland-Panels (Waybar, eww, …)
  und viele andere wlroots-Tools bereits nutzen.
- **Docked-Presence als echter Anker.** Der Avatar bliebe über
  Fullscreen-Fremdfenster sichtbar, wenn der Compositor das für den
  gewählten Layer zulässt. Kein Always-on-top-„Magic", sondern die
  vom Protokoll vorgesehene Kategorie.
- **Kombinierbar mit bestehendem Overlay-MVP.** Transparenz und
  Click-through bleiben über die vorhandenen Godot-DisplayServer-
  Flags adressierbar; layer-shell ergänzt den Stacking-Aspekt, den
  Mutter unter GNOME nicht liefert.

Das ist ausdrücklich ein Wunschbild, keine Zusage.

---

## B. Warum wlroots als eigene Zielwelt

wlroots ist **nicht** „GNOME mit einem anderen Logo":

- **Layer-Shell ist verfügbar.** Im Gegensatz zu Mutter unter GNOME
  implementieren wlroots-basierte Compositoren
  `wlr-layer-shell-unstable-v1` flächendeckend. Das ändert die
  Architektur fundamental — Smolit wäre dort kein regulärer
  Toplevel-Client, sondern ein Layer-Surface-Client.
- **Dock-/Overlay-Semantik ist explizit.** `zwlr_layer_shell_v1`
  kennt Layer wie `bottom`, `top`, `overlay` und unterstützt
  Exclusive-Zones für Dock-Verhalten. Das gibt uns Begriffe, die
  wir unter Mutter nicht haben.
- **Anders ausgerichtete Plattformkultur.** Nutzer von Sway /
  Hyprland erwarten typischerweise tilende / skriptbare Setups
  mit explizitem Docking; ein Smolit-Overlay müsste in dieses
  Modell passen, nicht dagegen laufen.
- **Fokus- und Input-Modell.** wlroots-Compositoren nutzen
  in der Regel focus-follows-mouse / Tilemanagement; ein
  ständig darüber liegender Anker interagiert anders mit dieser
  UX als unter Mutter.

Konsequenz: eine wlroots-Lösung ist eine **eigene Zielwelt** mit
eigenen Grenzen — sie darf nicht mit einer GNOME-Lösung in einen
Topf geworfen werden.

---

## C. Was heute **nicht** implementiert ist

Ausdrücklich, damit keine Missverständnisse entstehen:

- **Kein layer-shell-Code.** Weder das Protokoll noch ein Wrapper
  sind eingebunden. Keine `zwlr_layer_shell_v1`-Requests, keine
  Surface-Rolle, keine Anchor/Exclusive-Zone.
- **Keine GDExtension.** Der bestehende `backend_wayland_wlroots`-
  Platzhalter arbeitet rein in GDScript über die öffentliche
  Godot-DisplayServer-API.
- **Keine produktive Aktivierung.** Alle drei Aktivierungspfade
  (Overlay, Click-through, Always-on-top) delegieren an die
  existierenden Controller. Das Verhalten ist auf wlroots heute
  **identisch** zu `backend_wayland_generic`, nur mit zusätzlicher
  Diagnose.
- **Keine Compositor-spezifische Focus-/Stacking-Policy.**
- **Kein Dock- / Panel- / Tray-Versprechen.**
- **Kein Nutzer-sichtbares Produktversprechen unter wlroots.** Die
  Overlay-MVP-/Click-through-Stance bleibt identisch zu anderen
  Wayland-Compositoren.

Was *heute* neu ist:

- `backend_wayland_wlroots` trägt eine `experimental_stance`-
  Markierung, die der Runtime-Report (`SMOLIT_WINDOW_REPORT=1`) als
  eigene Zeile sichtbar macht.
- Die Aktivierungs-Ergebnis-Dicts des wlroots-Pfads werden um einen
  *additiven* `wlroots_research`-Marker ergänzt (`target_family`,
  `target_protocol`, `state = "prepared, not implemented"`,
  `reference`). Das bricht keine bestehenden Result-Achsen.

---

## D. Was ein späterer Spike konkret prüfen müsste

Wenn jemand den Pfad produktiv machen will, sind das die Fragen,
die vor Code-Arbeit auf dem Tisch liegen:

1. **Session-Erkennung auf Code-Ebene schärfer machen.** Der aktuelle
   Resolver klassifiziert über `XDG_CURRENT_DESKTOP`-Token
   (`sway`, `hyprland`, `wayfire`, `river`, `labwc`). Im Spike
   ist zu prüfen, ob das gegen reale wlroots-Sessions belastbar ist:
   Ubuntu-Spins, Hyprland-Regular-Releases, Sway-Pakete,
   eventuell unübliche Compositoren.
2. **Godot-Grenze vs. wlroots-Protokoll.** Godots DisplayServer
   unter Wayland (Godot 4.6) nutzt `xdg-shell`. Eine layer-shell-
   Surface-Rolle ist nicht Teil der öffentlichen API. Zu prüfen:
   - Reicht es, ein bereits gemapptes xdg-toplevel nachträglich in
     eine layer-shell-Surface zu überführen? (Antwort typischer-
     weise: nein, die Surface-Rolle ist bindend.)
   - Muss Smolit stattdessen auf GDExtension oder Host-Prozess
     ausweichen? (Bewusst Scope außerhalb dieses Vorbereitungs-PRs,
     siehe §E.)
3. **wlroots-Protokoll-Verfügbarkeit zur Laufzeit.** Der Spike muss
   belastbar feststellen, ob `zwlr_layer_shell_v1` auf dem
   aktuellen Compositor tatsächlich als Global beworben wird —
   nicht jeder wlroots-Build aktiviert alle Extensions.
4. **Layer-Wahl und Anchor-Strategie.** `overlay` vs. `top` vs.
   `bottom`: welcher Layer passt zur Smolit-Presence-Philosophie?
   Exclusive-Zone ja/nein? Anker an welchen Rand, wie dimensioniert?
   Das sind UX-Fragen, keine technischen Sackgassen.
5. **Koexistenz mit dem bestehenden Overlay-MVP.** Transparenz
   (`WINDOW_FLAG_TRANSPARENT`) und Click-through-Bounding-Union
   sind heute Godot-interne Mechaniken auf dem Toplevel. Wenn
   Smolit unter wlroots auf Layer-Shell wechselt, muss
   nachgezogen werden, wie sich diese Mechaniken auf einer
   Layer-Surface verhalten. Parallelbetrieb (Mutter: Toplevel,
   wlroots: Layer-Surface) ist möglich und wäre die ehrliche
   Linie — darf aber nicht in halbparallele Implementierungen
   zerfasern.
6. **Event-/Input-Modell.** Layer-Surfaces bekommen Input je nach
   `keyboard_interactivity`-Setting. Für Smolits Compact-Input-UX
   relevant: welches Setting erlaubt sinnvolles Tippen, ohne den
   Fokus von User-Anwendungen zu stehlen?
7. **UX- und Security-Grenzen.**
   - Kein globaler Eingabe-Grab, keine impliziten Rechte-
     erweiterungen (siehe [`presence_desktop_interaction.md`](./presence_desktop_interaction.md) §12).
   - Kein Layer, der sicherheitsrelevante Systemdialoge überdeckt.
   - Ein Opt-in-Schalter, kein Default, auch nicht unter wlroots.
8. **Messstand.** Wie würden wir überhaupt reproduzierbar messen?
   Sway + Hyprland sind gute Primärziele; Wayfire / river / labwc
   als Kontrollmessungen. Harness-Anschluss analog zu
   [`docs/linux_overlay_verification_matrix.md`](./linux_overlay_verification_matrix.md).

---

## E. Klare Einordnung

- **Experimenteller Spezialpfad**, keine Standardlinie.
- **Nicht** die GNOME-Lösung; siehe
  [`linux_always_on_top_decision.md`](./linux_always_on_top_decision.md)
  §B.2: die GNOME-Extension-Option bleibt zurückgestellt, und ein
  wlroots-Spike adressiert GNOME-Nutzer ausdrücklich nicht.
- **Nicht** die allgemeine Wayland-Lösung; `backend_wayland_mutter`
  und `backend_wayland_generic` bleiben unabhängig.
- **Opt-in und reversibel**, wenn er überhaupt kommt. Kein Default-
  Aktivieren unter wlroots nur weil ein wlroots-Compositor erkannt
  wurde.
- **Eigener Projekt-Track**, falls der Aufwand sich lohnt — mit
  eigener Verifikationsmatrix, eigener ROADMAP-Zeile, eigenem
  Decision-Dokument-Update. Nicht als Seiteneffekt eines
  Overlay-MVP-PRs.

---

## F. Offene Fragen (für spätere Spike-PRs)

- Welche Godot-Version könnte layer-shell auf der öffentlichen API
  unterstützen, und ist das eine realistische Upstream-Option?
- Falls GDExtension / Host-Prozess nötig: wie schneiden sich die
  Ergebnisse mit der Plattformfrage aus §F/§H von
  [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)?
- Welche realen Nutzerzahlen rechtfertigen einen wlroots-Track
  überhaupt? (Datenfrage, keine Code-Frage.)
- Wie integriert sich ein Layer-Surface-Smolit mit Screenlockern,
  Notification-Daemons, DPMS-Pfaden? (Unter wlroots compositor-
  spezifisch konfigurierbar.)

Keine dieser Fragen wird von diesem Dokument beantwortet. Der Zweck
hier ist, sie dokumentiert auf den Tisch zu legen, damit ein
späterer Spike nicht bei null beginnt.
