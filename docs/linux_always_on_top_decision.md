# Always-on-Top unter Linux — Entscheidungsdokument (Phase 3b)

Dieses Dokument ist **keine Feature-Implementierung** und **keine
Produktzusage**. Es ist ein Entscheidungs- und Forschungsspike. Ziel:
belastbar festlegen, wie Smolit das Thema „Always-on-Top" (AOT)
unter Ubuntu 24.04 / GNOME/Wayland — und den Nachbarstacks — behandelt.

Einordnung gegenüber Nachbardokumenten:

- [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  — Plattformrealität, Capability-Matrix, Overlay-Stufen.
- [`linux_overlay_verification_matrix.md`](./linux_overlay_verification_matrix.md)
  — Verifikationsläufe für den bestehenden Overlay-MVP.
- [`ui_architecture.md`](./ui_architecture.md) — UI-Seite der Presence-
  und Overlay-Linie.

Geltungsbereich: **heute**. Wenn die Plattform sich ändert (neue
Protokollerweiterung, offizieller GNOME-Pfad), ist dieses Dokument
eine explizite Revisionsstelle, kein Naturgesetz.

---

## A. Problemstellung

### A.1 Warum AOT attraktiv wirkt

Ein sichtbarer, stets anwesender Desktop-Begleiter ist eine zentrale
UX-Idee für Smolit. „Always-on-top" im klassischen Sinn — Fenster
bleibt über anderen Toplevels stehen, bis der Nutzer es bewegt —
klingt wie der passende Baustein:

- Smolit verschwindet nicht hinter dem gerade aktiven Fenster.
- Der Docked-Avatar ist als Anker ständig erreichbar.
- Action-/Approval-Banner bleiben sichtbar, auch wenn der Fokus
  wandert.

Diese Attraktivität ist real. Deshalb ist „AOT einfach einschalten"
eine naheliegende, aber irreführende Antwort.

### A.2 Warum GNOME/Wayland dafür problematisch ist

Siehe
[`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
§C.1 und §D. Kurz:

- **Wayland kennt protokollweit kein „always-on-top"** für reguläre
  Toplevels. `_NET_WM_STATE_ABOVE` ist ein X11-/EWMH-Konzept und hat
  in Wayland keine Entsprechung.
- **Mutter (GNOME)** respektiert keine client-seitigen Stacking-Hints
  für reguläre Toplevels. Das ist Design, nicht Bug.
- **Layer-Shell** (`wlr-layer-shell-unstable-v1`) würde echte Overlay-/
  Dock-Layer liefern — ist aber **wlroots-only** und unter GNOME/
  Mutter nicht verfügbar.
- **XWayland** erlaubt ABOVE-Hints technisch, der beobachtete Effekt
  unter GNOME ist in der Praxis eingeschränkt und inkonsistent.

Unsere Capability-Detection (`window_capabilities.gd`) markiert AOT
unter GNOME/Wayland konsequent als `unsupported`. Das ist keine
Vorsicht, sondern eine beobachtete Tatsache.

### A.3 Warum „einfach einschalten" keine ehrliche Lösung ist

Godot erlaubt zwar zur Laufzeit
`DisplayServer.window_set_flag(WINDOW_FLAG_ALWAYS_ON_TOP, true)`.
Das Flag wird gesetzt, lässt sich zurücklesen — und wird vom
Compositor unter GNOME/Wayland ignoriert. Der Nutzer sieht **kein**
Always-on-top, aber die Log-Kette „requested/applied" sähe positiv
aus.

Das ist die klassische Falle: **„Flag accepted by API ≠ user-visible
guarantee".** Ein Produktversprechen auf dieser Basis wäre ein stilles
„halb funktioniert manchmal". Smolits Designgrundsatz ist das genaue
Gegenteil (ehrliche Fallbacks, explizite Capabilities).

Kleine empirische Fußnote: die opt-in Probe
(`SMOLIT_WINDOW_PROBE=1`, siehe
[`linux_window_overlay_architecture.md` §F.1](./linux_window_overlay_architecture.md))
enthält dafür einen kurzen, reversiblen AOT-Flag-Probe-Block, der die
Trennung zwischen „Flag wurde akzeptiert" und „Nutzer sieht wirklich
Always-on-top" ehrlich im Log dokumentiert. Der Probe setzt das Flag,
liest es zurück und setzt es per Default wieder zurück; es entsteht
kein produktives AOT-Verhalten.

---

## B. Optionen

### B.1 Option 1 — Verzicht unter GNOME/Wayland

Smolit verspricht unter GNOME/Wayland **kein** Always-on-top und
implementiert es dort auch nicht. Die Presence-Stärke kommt aus
Transparenz + opt-in Click-through + bewusstem Docked-Anker.

Konkret:

- Overlay-MVP Phase B (`SMOLIT_UI_OVERLAY=1`) bleibt der standardisierte
  Weg zu sichtbarer Desktop-Präsenz.
- Click-through-Folgeschritt (`SMOLIT_UI_CLICK_THROUGH=1`) bleibt
  optionale Präsenz-Verstärkung.
- Das AOT-Flag wird in keinem produktiven Pfad gesetzt.
- Capability-Detection markiert AOT weiterhin ehrlich als
  `unsupported` unter GNOME/Wayland.

Wenn ein Nutzer Smolit sichtbar oberhalb halten will, ist der
Nutzerpfad der übliche Fenstermanager-Kontext: „Always on Top"-
Kontextmenü von GNOME (Titelleiste / Fensterliste), das auch für
reguläre Toplevels in GNOME heute existiert — das ist **Compositor-
Sache**, nicht unsere.

### B.2 Option 2 — GNOME-Shell-Extension

Eine offizielle Smolit-GNOME-Shell-Extension würde auf
Compositor-Seite einen Handler registrieren, der ein als „Smolit"
erkanntes Toplevel-Fenster dauerhaft in einen Overlay-Layer hebt,
über andere Toplevels.

Technisch machbar. Aber als Produktpfad teuer:

- **Versionsbindung.** GNOME Shell erwartet eine `metadata.json` mit
  einer `shell-version`-Liste. Mutter/Shell-APIs ändern sich
  regelmäßig (oft pro 6-Monats-Release). Eine Smolit-Extension wäre
  de facto ein **paralleles Produkt** mit eigenem Release-Rhythmus und
  eigener Compat-Matrix.
- **Distribution.** Offizieller Pfad ist `extensions.gnome.org` mit
  Review-Prozess. Ohne den Review-Pfad müssten Nutzer die Extension
  manuell installieren — mit erhöhtem Trust-Aufwand.
- **Sicherheitsmodell.** Eine Shell-Extension läuft mit den Rechten
  des Compositors; sie hat erheblich mehr Sichtbarkeit auf Desktop
  und andere Fenster als ein normaler Client. Das ist ein scharfer
  Bruch mit Smolits Security-Leitplanken (siehe
  [`presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  §12).
- **Architekturbruch.** Aktuell gilt: Godot-UI bleibt Presence-
  Schicht, Plattform-Details leben in einer schmalen Host-/Capability-
  Grenze (siehe
  [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
  §F/§H). Eine Shell-Extension führt eine *zweite* Codebasis in
  fremder Sprache ein, in fremdem Prozess, mit eigenem Lifecycle.
- **UX-Klarheit.** „Lade Smolit + GNOME-Extension installieren +
  aktivieren + Shell-Restart" ist ein schwer kommunizierbarer
  Erstkontakt.
- **Portabilität.** Trägt nichts zu KDE, wlroots, X11 bei — löst also
  ausdrücklich *nur* den GNOME-Fall, den wir uns oben schon als
  schwierigsten Fall gewünscht hätten.

### B.3 Option 3 — Compositor-/Backend-spezifischer Pfad

Statt eines pauschalen AOT-Versprechens: differenzierte Strategie,
ausgerichtet an der bereits existierenden Capability-Matrix.

- **X11-Session.** `WINDOW_FLAG_ALWAYS_ON_TOP` (bzw. zugrundeliegend
  `_NET_WM_STATE_ABOVE`) ist dort gut unterstützt. Könnte in einem
  späteren, expliziten Schritt als optionaler Presence-Modus
  aktiviert werden — weiterhin capability-gesteuert, mit ehrlichem
  Fallback, kein Default-Pfad.
- **wlroots-Sessions (Sway / Hyprland / river).** Der „richtige"
  Wayland-Weg wäre `wlr-layer-shell`. Das wäre ein separater,
  eigenständiger Schritt (eigenes Protokoll-Wrapping), nicht einfach
  ein weiteres `window_set_flag`.
- **GNOME/Wayland.** Bleibt bewusst ohne Promise. Nutzer, die AOT
  dort wirklich wollen, verwenden die GNOME-eigene „Always on Top"-
  Option im Titelleistenmenü — Compositor-Sache.

Diese Option ist keine sofortige Arbeit, sondern eine
**Architektur-Linie**: die Backend-Trennung aus
[`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
§F wird so verstanden, dass AOT als eines von mehreren Capability-
abhängigen Features dort landet — wenn es überhaupt irgendwann nötig
wird.

---

## C. Bewertungskriterien

| Kriterium                              | O1 — Verzicht | O2 — Extension       | O3 — Backend-spezifisch |
|----------------------------------------|---------------|----------------------|-------------------------|
| Technische Machbarkeit heute           | trivial       | machbar, aufwendig   | teilweise trivial (X11) |
| Stabilität / Wartbarkeit               | hoch          | niedrig (GNOME-Rev.) | mittel, getrennt        |
| UX-Klarheit für Erstnutzer             | hoch          | niedrig              | mittel                  |
| Portabilität über Desktops             | voll          | GNOME-only           | pro Backend, ehrlich    |
| Release-/Supportaufwand                | null          | sehr hoch            | mittel, opt-in          |
| Sicherheits-/Vertrauensmodell          | neutral       | Compositor-Rechte    | neutral                 |
| Architektur-Konsistenz mit Smolit      | voll          | bricht §F / §H       | passt zu §F             |
| Risiko „halb funktioniert manchmal"    | null          | mittel–hoch          | null (capability-gated) |

Erklärungen zu den Schlüsselpunkten:

- **„Stabilität" bei Option 2.** GNOME Shell Extensions werden
  empirisch häufig durch Mutter-/Shell-Updates gebrochen. Der Pflege-
  Aufwand steigt linear mit der Zahl unterstützter GNOME-Versionen.
- **„Sicherheit" bei Option 2.** Extensions laufen privilegiert; das
  vergrößert die Vertrauensoberfläche deutlich — unvereinbar mit
  Smolits Linie „keine stille Rechteausweitung".
- **„Halb funktioniert manchmal" bei Option 1.** Entfällt, weil wir
  dort gar nichts versprechen.
- **„Halb funktioniert manchmal" bei Option 3.** Entfällt nur, solange
  die Capability-Detection ehrlich bleibt und kein Backend still
  „es irgendwie probiert".

---

## D. Empfehlung

**Primärentscheidung: Option 1 — Verzicht unter GNOME/Wayland.**
Smolit verspricht auf der Ziel-Session (Ubuntu 24.04 / GNOME/Mutter
unter Wayland) **kein** Always-on-top und baut keinen Codepfad, der
den Nutzer in dem Glauben lassen würde. Die sichtbare Desktop-
Präsenz wird durch den existierenden Overlay-MVP (Transparenz +
Borderless) plus optionales Click-through gebildet — das ist der
heutige produktive Presence-Weg, mehr versprechen wir nicht.

**Sekundärer, optionaler Seitenpfad: Option 3 für X11.** Wenn sich in
Nutzung zeigt, dass X11-Sessions ein echter, häufiger Fall sind und
dort ein optionales AOT für Docked-Presence merklich hilft, kann ein
schmaler X11-only Seitenpfad nachgezogen werden: capability-gesteuert,
opt-in, dokumentierter Sonderfall — **nicht** Teil des Standard-
MVPs. Aufwand klein, Risiko klein, passt zur bestehenden Backend-
Matrix.

**Ausdrücklich zurückgestellt: Option 2 — GNOME-Shell-Extension.**
Das wäre ein eigenes Parallelprojekt mit Kostenstruktur, die nicht
zum aktuellen Produktstadium passt. Nicht für immer ausgeschlossen —
aber nur, wenn es später eine klare, messbare Nutzernachfrage gibt,
der Extension-Pflegeaufwand realistisch geplant ist und das
Sicherheitsmodell sauber durchgezogen wird.

**wlroots/layer-shell**: bleibt dokumentierte Möglichkeit für
wlroots-Compositors; kein Anspruch, dass Smolit dort AOT liefert,
solange niemand das explizit einführt.

---

## E. Konsequenzen

### E.1 Was das für Roadmap / Doku / Featureversprechen bedeutet

- **Roadmap.** Die bisherige Zeile „Entscheidungsspike always-on-top
  unter GNOME" wird auf `[x]` entschieden (mit Verweis auf dieses
  Dokument). Ein möglicher späterer X11-AOT-Seitenpfad wird als
  kleiner, optionaler Folgeposten aufgenommen, nicht als Standardziel.
- **README.** Der Overlay-/Click-through-Abschnitt bekommt eine
  klare, knappe Aussage: „unter GNOME/Wayland bewusst kein Always-
  on-top-Versprechen".
- **Linux-Overlay-Architektur.** Neuer „Decision snapshot"-Abschnitt,
  der diese Entscheidung kompakt referenziert.
- **Capability-Detection.** Keine Änderung nötig — sie markiert AOT
  unter GNOME/Wayland bereits korrekt als `unsupported`.
- **Overlay-/Click-through-Controller.** Keine Änderung. Sie setzen
  kein AOT-Flag und dokumentieren explizit, dass sie es nicht tun.

### E.2 Was kurzfristig gemacht wird

- Dieses Entscheidungsdokument.
- Kleine diagnostische Ergänzung im bestehenden `window_probe.gd`:
  das AOT-Flag wird im Probe-Pfad **einmalig** gesetzt, zurückgelesen
  und per Default wieder revertiert. Log macht ausdrücklich klar:
  *„Flag accepted by API — this is not a user-visible guarantee under
  Mutter."* Kein produktiver Pfad. Opt-in.
- Updates an Roadmap, README, und der Linux-Overlay-Doku.

### E.3 Was explizit nicht gemacht wird

- Kein produktives Always-on-top im Standardpfad.
- Keine GNOME-Shell-Extension.
- Kein layer-shell-Pfad.
- Keine GDExtension.
- Keine IPC-/EventBus-Änderung.
- Keine neue Presence-Wahrheit oder UI-Mode.
- Kein stilles Setzen eines AOT-Flags im produktiven Lauf.

### E.4 Was nur bei klarer Nachfrage später wieder auf den Tisch kommt

- **X11-AOT-Sonderpfad.** Wenn reale X11-Nutzung spürbar wird und AOT
  dort merklich hilft: capability-gesteuerter opt-in Modus,
  dokumentierter Sonderpfad, bleibt Sonderpfad.
- **wlroots layer-shell-Pfad.** Nur wenn wlroots-Sessions ein
  relevantes Nutzersegment werden und eine eigene Phase rechtfertigen.
- **GNOME-Extension (Option 2).** Nur wenn (1) eindeutige Nachfrage
  da ist, (2) Pflegeaufwand realistisch eingeplant werden kann und
  (3) das Sicherheitsmodell sauber durchgezogen wird. Dann: eigenes
  Produktprojekt, eigene Review-/Release-Kette, eigene Doku.

---

## F. Produktversprechen — auf den Punkt

Unter Ubuntu 24.04 / GNOME/Wayland verspricht Smolit heute:

- **Ja.** Overlay-Hülle mit transparentem, borderlosem Fenster
  (`SMOLIT_UI_OVERLAY=1`).
- **Ja.** Opt-in Click-through mit interaktiven Zonen
  (`SMOLIT_UI_CLICK_THROUGH=1`) — auf aktuellem MVP-Stand mit
  Bounding-Rect-Union.
- **Ja.** Ehrliche Capability-Aussage über das, was geht und was
  nicht.
- **Nein.** Kein Always-on-top. Weder automatisch, noch opt-in,
  noch „es könnte gehen".
- **Nein.** Keine stillen Compositor-Tricks, keine stille
  Rechteausweitung.

Auf einer X11-Session gelten dieselben produktiven Versprechen. Ein
späterer, opt-in X11-AOT-Sonderpfad ist dokumentierte Option, kein
Standard.

Auf einer wlroots-Session (Sway/Hyprland/river) gelten dieselben
produktiven Versprechen. layer-shell-Pfad ist dokumentierte Option,
kein Standard.

Auf sonstigen Linux-Desktops (KDE, XFCE, Cinnamon) sind die opt-in
Overlay-/Click-through-Pfade verfügbar; alles Darüberhinausgehende
ist keine Smolit-Zusage.
