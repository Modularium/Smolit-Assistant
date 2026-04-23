# Smolit Presence & Desktop Interaction Model v1

Architektur- und Produktentscheidung zur sichtbaren Desktop-Präsenz von
Smolit und zum Zusammenspiel zwischen Avatar-Visualisierung und echter
Desktop-Automation.

Dieses Dokument beschreibt **Zielarchitektur und Leitplanken**. Es
beschreibt **nicht** den heutigen Ist-Zustand. Was heute bereits
implementiert ist, steht in [ROADMAP.md](../ROADMAP.md) und
[docs/ui_architecture.md](./ui_architecture.md).

---

## 1. Kurzbeschreibung

Smolit soll als **persistente visuelle Desktop-Präsenz** existieren.
Der Avatar ist die **sichtbare Interaktionsoberfläche**, die den
aktuellen Zustand, die Aufmerksamkeit und die laufende Handlung des
Assistenten erlebbar macht. Die **echte Desktop-Automation** — also
das eigentliche Öffnen, Klicken, Tippen, Scrollen in Fremdsoftware —
läuft in einer **getrennten, kontrollierten Schicht** unterhalb der
UI und ist vom Avatar bewusst entkoppelt.

Smolit ist damit **weder ein dekorativer Begleiter** noch ein
unsichtbarer Hintergrund-Agent. Smolit ist eine sichtbare, aber
kontrollierte digitale Assistenz-Präsenz.

Der sichtbare Teil von Smolit umfasst perspektivisch nicht nur
Avatar und Präsenz, sondern auch einen symbolischen **Workflow-/
Action-Readout** (Ziel-Zustand, siehe Unterabschnitt „Workflow
Overlay als Presence-Erweiterung" in §5 und die UI-Seite in
[`ui_architecture.md`](./ui_architecture.md) §6a/§8a). Der Readout
ist read-only und core-driven; er führt nichts aus und ändert die
Ausführungs-Architektur nicht.

---

## 2. Zielbild

- Smolit ist auf dem Desktop **sichtbar und ansprechbar**, ohne eine
  klassische Fensterflut aufzubauen.
- Smolit **zeigt seine Aktionen visuell an** — der Nutzer kann
  jederzeit erkennen, was gerade passiert, woran Smolit arbeitet und
  wo die Aufmerksamkeit liegt.
- Smolit soll **fremde Software bedienen können**, auch wenn diese
  erst vom Nutzer neu installiert wurde und Smolit sie nicht aus
  einer festen Integrationsliste kennt.
- **Sicherheit, Ressourcenverbrauch und Stabilität** bleiben auch im
  Dauerbetrieb gewahrt; der Assistent darf das System nicht
  überlasten oder unkontrolliert eingreifen.
- Der Nutzer kann **jederzeit nachvollziehen und unterbrechen**, was
  Smolit tut.

Ausdrücklich **nicht** Ziel:

- ein rein dekorativer Avatar ohne Funktion,
- ein unsichtbarer Hintergrunddienst ohne Präsenz,
- ein autonomer Roboter, der ungefragt im System agiert.

---

## 3. Architekturgrundsatz: Sichtbare Aktion ≠ technische Ausführung

Der zentrale Entwurfsgrundsatz dieses Dokuments:

> **Visual truth, not implementation coupling.**
> Smolit zeigt wahrheitsgemäß, was passiert, ist aber nicht direkt
> an die low-level Ausführung gekoppelt.

Das bedeutet im Einzelnen:

- Der Nutzer darf den Eindruck haben, der Avatar „laufe“, „klicke“,
  „tippe“ oder „arbeite“ sichtbar auf dem Desktop.
- **Technisch** wird die Aktion jedoch nicht vom Avatar ausgeführt,
  sondern durch einen separaten **Desktop Interaction / Automation
  Layer**.
- Der Avatar erhält vom Core **Action-/Phase-Events** und
  **visualisiert** diese — er ist **Darstellung**, nicht Executor.
- Neben Avatar-Mimik und Bewegungszuständen kann Smolit
  perspektivisch einen **abstrahierten sichtbaren Handlungsfluss**
  als symbolisches Workflow-Readout zeigen. Dieser Flow ist
  ebenfalls Visual truth und bleibt von der technischen Desktop-
  Ausführung vollständig entkoppelt — er zeigt *was* gerade
  passiert, nicht *wie* die Low-Level-Interaktion implementiert
  ist. Siehe den Unterabschnitt „Workflow Overlay als Presence-
  Erweiterung" in §5 sowie
  [`ui_architecture.md` §6a/§8a](./ui_architecture.md).

Gründe für diese Trennung:

- **Stabilität.** Ein Bug in der Automatisierungsschicht darf die UI
  nicht crashen; ein Bug in der UI darf keine halben Klicks in
  fremden Anwendungen hinterlassen.
- **Fehlerbehandlung.** Retry, Verification und Recovery gehören in
  eine dedizierte Automatisierungsschicht mit klaren Zuständen, nicht
  in eine Animationspipeline.
- **Sicherheit.** Policy, Bestätigungen und Trust-Checks sitzen vor
  der eigentlichen Ausführung, nicht in der Darstellung.
- **Erweiterbarkeit.** Neue Interaktionskanäle (APIs, Accessibility,
  OCR, Pixel) lassen sich als Adapter unterhalb des Avatars
  ergänzen, ohne den Avatar umzubauen.
- **Performance.** Der Avatar kann leichtgewichtig bleiben,
  unabhängig davon, wie teuer eine bestimmte Automatisierung ist.

---

## 4. High-Level-Systemmodell

```text
                         User
                          ↕
              ┌──────────────────────────┐
              │  Smolit Avatar /         │
              │  Presence Layer          │   sichtbare Figur, Zustände,
              │  (Docked / Expanded /    │   Bewegungen, Rückmeldungen,
              │   Action Mode)           │   Workflow-Readout
              └───────────┬──────────────┘
                          ↕
              ┌──────────────────────────┐
              │  Smolit UI (Godot)       │   Rendering, Input, Overlay,
              │                          │   Window-Präsenz
              └───────────┬──────────────┘
                          ↕   WebSocket IPC (api.md)
              ┌──────────────────────────┐
              │  Smolit Core (Rust)      │   Orchestrierung, Policy,
              │                          │   Event-Fan-out, State
              └───────────┬──────────────┘
                          ↕
              ┌──────────────────────────┐
              │  ABrain / Reasoning /    │   Intent, Plan, Entscheidung
              │  Policy                  │
              └───────────┬──────────────┘
                          ↕
              ┌──────────────────────────┐
              │  Desktop Interaction     │   APIs, Accessibility,
              │  Layer (Adapter-Familie) │   Hybrid, OCR, Pixel
              └───────────┬──────────────┘
                          ↕
              ┌──────────────────────────┐
              │  Desktop / Apps /        │
              │  Windows / UI Elements   │
              └──────────────────────────┘
```

Verantwortlichkeiten pro Ebene:

| Ebene                        | Verantwortung                                           |
|------------------------------|---------------------------------------------------------|
| Presence Layer (Avatar)      | Sichtbarkeit, Zustände, Animation, Nutzerwahrnehmung, symbolischer Workflow-Readout (Ziel-Zustand) |
| Smolit UI (Godot)            | Rendering, Fenster-/Overlay-Verhalten, Input-Weiterleitung |
| Smolit Core                  | Orchestrierung, Event-Fan-out, Policy-Enforcement       |
| ABrain / Reasoning / Policy  | Intent-Erkennung, Plan, Entscheidung, Eskalation        |
| Desktop Interaction Layer    | tatsächliche Ausführung, Verifikation, Recovery         |
| Desktop / Apps               | Zielumgebung                                            |

Die Trennung ist nötig, damit:

- der Avatar nie direkte Systemrechte braucht,
- Policy und Verifikation **vor** der Ausführung wirken können,
- Fremdsoftware-Adapter ersetzt werden können, ohne die UI zu
  berühren.

---

## 5. Presence Model

Smolits Sichtbarkeit wird über vier normative Betriebsmodi
gesteuert. Diese Modi sind **nutzerseitig einstellbar**; der Core
bzw. die Konfiguration ist die Quelle der Wahrheit, nicht der
Avatar.

Presence umfasst insgesamt:

- die **sichtbare Figur** (Avatar),
- ihre **Zustände** (Idle / Thinking / Talking / Acting /
  Disconnected / Error),
- ihre **Reaktionen** auf Nutzer- und Core-Events,
- optional einen **Workflow-/Action-Readout** (siehe
  Unterabschnitt weiter unten).

Die Figur selbst ist perspektivisch **visuell personalisierbar**
(Ziel-Zustand, siehe Unterabschnitt „Avatar-Personalisierung als
Presence-Erweiterung"). Personalisierung ändert die Darstellung,
**nicht** die Presence-Modi oder das Systemverhalten.

### 5.1 Presence Modes

#### Off

- Kein sichtbares Avatar-Fenster, keine Overlay-Präsenz.
- Kern läuft weiter (z. B. Hintergrund-Services, Shortcuts).
- Ressourcenverbrauch minimal.
- Einsatz: Fokus-Arbeit, Vollbild-Apps, Präsentationen, Spiele.

#### Icon only

- Kleines, dezentes Präsenz-Icon (z. B. Dock/Tray-ähnlich).
- Keine Figur, keine Animation im Leerlauf.
- Reaktion erst bei expliziter Ansprache.
- Ressourcenverbrauch sehr niedrig.
- Einsatz: „Der Assistent ist da, soll aber nicht auffallen.“

#### Light avatar

- Kleiner, dezenter Avatar mit minimaler Mimik-/Zustandsanzeige.
- Wenige, ruhige Animationen.
- Wechselt bei Ansprache in Expanded, sonst Docked.
- Ressourcenverbrauch moderat.
- Einsatz: Standardmodus für Alltagsarbeit.

#### Full avatar

- Vollständig ausdrucksstarker Avatar.
- Reicher Zustandsraum, Animationen, Bewegungen, ggf. Szenenwechsel.
- Kann den Action Mode sichtbar ausspielen.
- Ressourcenverbrauch höher.
- Einsatz: erklärende Interaktion, Demos, Begleitung längerer Abläufe.

Die Presence Modes sind **produktseitig einstellbar** und Teil der
Nutzer-Policy. Sie bestimmen, wie stark Smolit den Bildschirm
beansprucht — unabhängig davon, was technisch gerade möglich wäre.

### Workflow Overlay als Presence-Erweiterung (Ziel-Zustand)

Perspektivisch kann die Presence-Schicht neben Avatar und Banner
einen kleinen, read-only **Workflow-/Action-Readout** zeigen —
symbolischer Flow links vom Avatar bzw. als linker Flügel derselben
Presence-Hülle.

- Das Overlay dient dem **Verständnis und der Nachvollziehbarkeit**,
  nicht der Ausführung.
- Es ist **primär im Action-Kontext** relevant (siehe §6.3); im
  Leerlauf (Docked, kein laufender Action Event) bleibt es reduziert
  oder vollständig verborgen.
- Es hat **keine eigenständige Executor-Rolle** — es projiziert nur,
  was der Core ohnehin als Action Events emittiert.
- Es trägt **keine Interaktionsversprechen** im MVP; spätere
  Collapse/Expand- oder Inspect-Formen sind architektonisch nicht
  ausgeschlossen, aber nicht Teil des Ziel-MVP.
- Es ist **kein neuer Presence Mode** und keine neue Window-
  Behavior-Fähigkeit. Es lebt innerhalb derselben Presence-Hülle
  wie Avatar und Banner (siehe
  [`linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)).

Heutiger Stand: noch nicht implementiert. Die Produkt- und UI-Seite
ist in [`ui_architecture.md` §6a/§8a](./ui_architecture.md)
beschrieben; die Event-Projektion steht in
[`api.md` „UI-Projektion: Workflow Overlay"](./api.md).

### Avatar-Personalisierung als Presence-Erweiterung (Ziel-Zustand)

Perspektivisch kann der Avatar selbst **visuell personalisiert**
werden — nicht in seinem Verhalten. Die Personalisierung erfolgt
in vier orthogonalen Ebenen (Detailsicht:
[`ui_architecture.md` §8b](./ui_architecture.md); Roadmap-Seite:
[`ROADMAP.md` Phase 4b](../ROADMAP.md)):

- **Avatar Identity** — Figurentyp (Salamander als Default, optional
  Roboter, Mensch, Tiere, abstrakte Formen).
- **Avatar Theme** — Stil der Darstellung (`default`, `tech`, `soft`,
  `neon`, `minimal`, …).
- **Appearance Overrides** — Farben, Glow, Outline, Größe, visuelle
  Intensität.
- **Behavior Profile (UI)** — rein visueller Ausdruck (ruhig / aktiv
  / verspielt / zurückhaltend); moduliert Animation und Idle-Cues,
  nichts Anderes.

Personalisierung dient:

- **Identifikation** — eigener Look fürs eigene Setup.
- **Lesbarkeit** — Avatar passt zum jeweiligen Desktop-Kontrast
  und Nutzerpräferenz.
- **Emotionaler Bindung** — Avatar darf sich vertraut anfühlen,
  ohne dass sich dadurch Systemfähigkeiten ändern.

Wichtig — **ohne jede Ausnahme**:

- **Keine Auswirkung auf Action-Ausführung.** Ob Smolit eine
  Desktop-Aktion ausführen darf oder nicht, hängt ausschließlich
  an Policy und Approval — nicht am gewählten Avatar.
- **Keine Auswirkung auf Systemverhalten.** ABrain-Prompts,
  Action-Event-Struktur, Presence-Modi, Recovery-Strategien
  bleiben unverändert.
- **Keine Auswirkung auf Sicherheit.** Avatar-Auswahl verändert
  keine Trust-Entscheidungen, keine Approval-Flows, keine
  Permission-Grenzen.

Status: **Phase A implementiert, Phase B als kuratierter Spike
aktiv, Stage C ausdrücklich nicht begonnen (Forschungs-/Designraum).**
Default bleibt Smolit Salamander; Alternativen kommen additiv hinzu
und ersetzen den Default nicht. Was „Stage C" in Zukunft überhaupt
bedeuten könnte — inklusive harter Nicht-Ziele, Sicherheitsmodell
und Exit-Kriterien für einen späteren echten Implementierungsstart —
ist separat in
[`avatar_stage_c_research.md`](./avatar_stage_c_research.md)
dokumentiert. Aus Presence-Sicht wichtig: eine spätere Stage C ändert
nichts an der Trennung „Avatar ≠ Assistentenlogik" aus dem nächsten
Unterabschnitt; visuelle Personalisierung bleibt rein visuell, auch
wenn ihr Quellenraum wächst.

Der aktuelle Phase-B-Spike (siehe
[`ui_architecture.md` §8b.8](./ui_architecture.md)) ergänzt drei
zusätzliche, fest kuratierte Identity-IDs (`robot_head`,
`humanoid_head`, `orb`) — rein prozedural gerendert, ohne Asset-
Pipeline, ohne User-Uploads. Seit der Härtung ist die Linie **kein
reiner Identity-Katalog** mehr, sondern ein kleiner **Template-
Capability-Contract**: jedes Template deklariert explizit, welche
Avatar-States es trägt (`orb` etwa klappt `TALKING` deterministisch
auf `ACTING`, weil die Figur keinen Mund hat) und wie stark es die
Ausdrucks-Achsen Theme-Tint, Behavior-Profile, State-Pulse, Wiggle
und Error-Startle umsetzt. Fallbacks sind damit sichtbar, nicht
implizit. Unbekannte Eingaben fallen in allen Schichten auf Smolit
zurück.

#### Klarstellung: Avatar ≠ Assistentenlogik

Damit die Trennung nicht verwässert:

- **Avatar ≠ Assistentenlogik.** Der Avatar ist Darstellung, keine
  Entscheidungsinstanz. Assistant-Personality, Policy, Automation-
  Regeln und Intent-Verarbeitung leben im Core bzw. in ABrain, nicht
  in der UI.
- **Gleiche Aktionen → gleiche Systemreaktion.** Unabhängig davon,
  welcher Avatar angezeigt wird (Salamander / Roboter / Mensch /
  Tier / Orb), liefert dieselbe Nutzereingabe dasselbe
  Assistenten-Ergebnis.
- **Appearance ≠ Behavior ≠ Personality ≠ Policy.** Diese vier
  Ebenen bleiben in der Architektur getrennt; ein Appearance-
  Wechsel darf keine der drei anderen Ebenen implizit mitverändern.

---

## 6. Always-on-top-Konzept

Als Zielarchitektur (nicht als Ist-Zustand) gilt ein
Drei-Zustands-Modell für das sichtbare Fenster/Overlay.

### 6.1 Docked

- Kleiner, always-on-top Präsenzpunkt bzw. Miniatur-Avatar.
- Ruhezustand — minimale Animation, minimale CPU/GPU-Last. Seit der
  Micro-Animation / Personality Layer v1 trägt der Docked-Avatar eine
  sehr dezente Körpersprache (ruhiger Idle-Atem, seltener Curious-Cue,
  State-abhängige Feinvariationen in Thinking / Talking / Acting /
  Error / Disconnected) — bewusst leise und additiv, siehe
  [docs/ui_architecture.md §7](./ui_architecture.md) „Phase B++".
- Frei positionierbar (Ecke, Kante, Nutzer-definierte Position).
- Dient als Anker, von dem aus sich Smolit in andere Zustände
  entfaltet.
- Kann eine **leichte Compact Input UX** direkt am Icon tragen:
  Klick auf den Avatar öffnet ein kleines Eingabepanel (Text, Voice,
  Add-Files-Hook, Mini-Commands, Close), das die Schnellinteraktion
  ermöglicht, ohne in Expanded zu wechseln. Implementierungsdetails
  siehe [docs/ui_architecture.md §8.3](./ui_architecture.md).

### 6.2 Expanded

- Vergrößerte Darstellung mit Sprechblase / Statusfläche /
  Avatar-Mimik.
- Reaktion auf Klick, Sprache, Rückfrage oder Core-getriebene
  Ankündigung.
- Rückkehr nach Timeout oder expliziter Nutzeraktion in Docked.

### 6.3 Action Mode

- Avatar verlässt den Docked-Anker.
- Bewegt sich sichtbar über den Bildschirm zum Ziel (Fenster,
  UI-Bereich, Symbol).
- Zeigt Handlung, Zielobjekt und Rückmeldung — entsprechend dem
  eingestellten Visual Action Mode (siehe §7).
- Kehrt nach Abschluss (oder Abbruch) in Docked zurück.
- Kann neben dem Avatar zusätzlich einen **symbolischen
  Workflow-Readout** einblenden (Ziel-Zustand). Beispielhafter
  Ablauf: `Trigger → Schritt → Aktion → Ergebnis`. Die Darstellung
  bleibt symbolisch, sicherheitsneutral und read-only; sie zeigt
  ausschließlich, was der Core ohnehin als Action Events geliefert
  hat. Siehe Unterabschnitt „Workflow Overlay als Presence-
  Erweiterung" in §5 und
  [`ui_architecture.md` §6a/§8a](./ui_architecture.md).

Diese drei Zustände sind **visuelle Zielarchitektur**. Sie
beschreiben, wie sich Smolit auf dem Desktop anfühlen soll, nicht
wie der Avatar heute bereits aussieht.

Das **Presence-Konzept selbst bleibt plattformunabhängig gültig** —
die drei Modi sind Produktachsen, keine Fenster-Features. Wie weit ein
Betriebssystem davon sichtbar unterstützt (Always-on-top, transparenter
Hintergrund, Click-through, Pixel-Positionierung), ist jedoch **plattform-
und compositor-abhängig**. Unter Linux — insbesondere Ubuntu 24.04 mit
Wayland (GNOME/Mutter) — sind mehrere dieser Overlay-Fähigkeiten
protokollbedingt nicht frei verfügbar. Die plattformtechnische
Realitätsprüfung dazu, inklusive Wayland/X11-Unterschiede und
Fähigkeits-Matrix, ist in
[`docs/linux_window_overlay_architecture.md`](./linux_window_overlay_architecture.md)
dokumentiert. Dieses Dokument bleibt auf **Produktachsen und
Leitplanken** fokussiert; es nimmt bewusst keine Plattformfähigkeiten
als selbstverständlich an.

Als erster technischer Träger für den Docked-/Presence-Modus ist ein
**opt-in Overlay-MVP Phase B** gelandet: `SMOLIT_UI_OVERLAY=1` aktiviert
einen transparenten, borderlosen Presence-Modus mit capability-
gesteuertem Fallback. Always-on-top ist bewusst **nicht** Teil dieses
Schrittes — die Presence-Modi oben bleiben gültig, die äußere
Fensterhülle ist nur ehrlicher geworden. Siehe
[`docs/linux_window_overlay_architecture.md` §F.2](./linux_window_overlay_architecture.md)
und [`docs/ui_architecture.md` §9.2](./ui_architecture.md).

Click-through mit definierten interaktiven Zonen existiert inzwischen
als **zweiter opt-in Folgeschritt** — zusätzlich zum Overlay per
`SMOLIT_UI_CLICK_THROUGH=1`. Avatar und sichtbare UI-Panels bleiben
klickbar; Klicks außerhalb dieser Zonen fallen durch auf das
darunterliegende Fenster. Der Schritt bleibt bewusst ein MVP: Godots
DisplayServer-API erlaubt pro Fenster nur *einen* Passthrough-Polygon,
der Controller fasst daher alle gültigen Zonen zu einer Bounding-Rect-
Union zusammen, innerhalb derer Leerraum noch klickbar bleibt. Auch
hier **kein** Always-on-top, **kein** compositor-spezifischer Pfad,
**keine** neue Presence-Wahrheit — die Presence-Achsen oben bleiben
unverändert, nur die Fensterhülle ist durchlässig geworden. Siehe
[`docs/linux_window_overlay_architecture.md` §F.3](./linux_window_overlay_architecture.md)
und [`docs/ui_architecture.md` §9.3](./ui_architecture.md).

---

## 7. Visual Action Model

Wie viel Smolit von einer laufenden Aktion **sichtbar macht**, wird
über die Visual Action Modes gesteuert. Diese Achse ist **unabhängig
von der tatsächlichen Fähigkeit** des Desktop Interaction Layers —
Smolit kann eine Aktion durchführen, ohne sie theatralisch zu
zeigen, und umgekehrt.

### 7.1 none

- Keine sichtbare Avatar-Handlung.
- Höchstens Statussymbol im Docked-Zustand.
- Einsatz: stille Aktionen, Fokus-Modus.

### 7.2 minimal feedback

- Kurze, zurückhaltende Signale: Blick in Richtung Ziel, kurzer
  Farbwechsel, dezenter Indikator.
- Keine Bewegung über den Bildschirm.
- Einsatz: Standard für Routineaktionen.

### 7.3 guided movement

- Avatar bewegt sich zum Ziel, zeigt Zielobjekt, führt die Handlung
  visuell an.
- Keine übertriebene Choreografie.
- Einsatz: Nutzer soll nachvollziehen, was passiert.

### 7.4 full theatrical mode

- Vollständig inszenierte Aktion: Bewegungspfad, Gestik, Reaktion
  auf Ergebnis, ggf. Sprechblase mit Kommentar.
- Höhere Last, bewusst gewählt.
- Einsatz: Demos, Onboarding, längere geführte Abläufe.

Wichtig:

- Visual Action ist **optional** und **vollständig abschaltbar**.
- Sie ist **Darstellung**, keine Voraussetzung für die eigentliche
  Ausführung.

---

## 8. Desktop Automation Model

Unabhängig davon, wie viel der Avatar zeigt, regelt diese Achse, was
Smolit **tatsächlich** am Desktop tun darf.

### 8.1 none

- Smolit führt keine Desktop-Aktionen aus.
- Reine Konversation, ggf. Vorschläge als Text.
- Default für maximale Vorsicht.

### 8.2 assist only

- Smolit darf **vorschlagen**, Anleitungen geben, Links, Shortcuts
  oder Parameter vorbereiten.
- Keine eigenständige Ausführung.
- Der Nutzer führt die Schritte selbst durch.

### 8.3 confirm before action

- Smolit darf Aktionen **vorbereiten und ausführen**, aber nur nach
  expliziter Bestätigung pro Aktion (oder pro Plan).
- Zielobjekt, Eingaben und erwartete Wirkung werden vor der
  Ausführung sichtbar gemacht.
- **Konkretisiert im MVP** durch den Approval / Confirmation Flow
  (siehe `docs/api.md`, §2.7): der Core sendet `approval_requested`,
  die UI zeigt einen Banner mit Titel, Message und Target, und
  Approve/Deny schickt ein `approval_response` zurück. Ohne Antwort
  innerhalb von `SMOLIT_APPROVAL_TIMEOUT_SECONDS` wird die Aktion
  mit `action_cancelled` verworfen — Default ist „nicht ausführen".

### 8.4 allowed trusted actions only

- Für klar definierte, als „trusted“ markierte Aktionen (z. B.
  bekannte App-Befehle, harmlose Lesezugriffe, wiederholbare
  Routineaktionen) darf Smolit ohne einzelne Rückfrage handeln.
- Alle anderen Aktionen fallen zurück auf *confirm before action*.

Leitplanken, die modusübergreifend gelten:

- **Schreibende / klickende Aktionen** sind sensibler als reine
  Leseaktionen und werden strenger behandelt.
- Sensible Interaktionen (Passwörter, Systemdialoge, Zahlungs-/
  Admin-UIs) dürfen **niemals stillschweigend** eskalieren.
- **Abbruch und Stop** müssen jederzeit möglich sein — per
  Tastenkürzel, per Klick auf den Avatar und per Sprachbefehl.
- Rechte werden **nicht automatisch erweitert**. Ein „einmal
  erlaubt“ ist keine Dauervollmacht.

---

## 9. Interaction Fidelity Model

Die fünfte Achse beschreibt, **wie** Smolit mit einer Ziel-UI
interagiert. Sie ist orthogonal zu den Automation Modes: die
Automation Modes sagen *ob und wie kontrolliert*, Interaction
Fidelity sagt *auf welchem Weg*.

### 9.1 native-first

- Bevorzugt: offizielle APIs, CLI-Aufrufe, URL-Schemes, D-Bus,
  MCP-/RPC-Integrationen, Accessibility-Baum.
- Kein Umweg über Bildschirmpixel, wenn eine strukturierte
  Schnittstelle existiert.
- Default für alle Aktionen, für die es eine zuverlässige
  Integration gibt.

### 9.2 hybrid

- Kombination aus Accessibility, Fensterstruktur, Screenshot, OCR
  und UI-Kontextanalyse.
- Einsatz: Anwendungen ohne saubere API, aber mit erkennbarer
  UI-Struktur.

### 9.3 pixel-guided

- Gezielte Interaktion über Bildschirmkoordinaten, Vision,
  Template-Matching, OCR.
- Nur **kontrolliert und verifiziert**, nicht als Dauerzustand.
- Einsatz: Lücken, die weder native noch hybride Wege schließen.

### 9.4 experimental

- Breite, explorative Desktop-Interaktion mit höherem Risiko.
- Immer klar als experimentell gekennzeichnet, nie Default.
- Einsatz: Forschung, Prototypen, Opt-in-Features.

Leitplanken:

- Pixelgenaue UI-Bedienung **ist möglich**, aber als bewusste
  Eskalationsstufe, nicht als Standardweg.
- Der Stack wählt immer den **stabilsten verfügbaren Weg** zuerst
  und eskaliert nur, wenn nötig.

---

## 10. Desktop Interaction Stack v1

Der Desktop Interaction Layer ist intern mehrstufig. Keine Stufe
darf übersprungen werden, ohne Policy, Ergebnis oder Sicherheit zu
schwächen.

### 10.1 App Discovery

- Aktive Fenster und laufende Prozesse erkennen.
- Anwendung identifizieren (Name, Pfad, Klasse, Version).
- Vorhandene Interaktionskanäle bestimmen (API? CLI? Accessibility?
  Nur Pixel?).

### 10.2 UI Targeting

- Zielwahl nach Interaction-Fidelity-Achse:
  1. API / CLI / URL-Scheme,
  2. Accessibility-Baum,
  3. UI-Strukturanalyse,
  4. Vision / OCR,
  5. Pixelkoordinaten.
- Jede Wahl wird **begründet** und ins Event-Log des Cores
  geschrieben.

### 10.3 Action Execution

Standardaktionen, die Smolit unterstützen soll:

- `open` — Anwendung/Datei öffnen,
- `focus` — Fenster in den Vordergrund holen,
- `click` — gezielter Klick auf ein UI-Element,
- `type` — Texteingabe,
- `shortcut` — Tastenkombination,
- `scroll` — Scrollen in definiertem Bereich,
- `drag/drop` — optional, spätere Ausbaustufe.

### 10.4 Verification

- Ist das richtige Fenster aktiv?
- Wurde der richtige Text eingetragen?
- Hat sich die UI erwartungsgemäß verändert (neues Dialogfeld,
  Statusänderung, OCR-Bestätigung)?
- Ohne Verification **gilt eine Aktion als nicht abgeschlossen**.

### 10.5 Recovery

- Retry mit gleichem Weg.
- Fallback auf die nächst-niedrigere Fidelity-Stufe.
- Nutzer fragen („Ich sehe X nicht wie erwartet — weiter, ändern,
  abbrechen?“).
- Harter Abbruch inkl. sichtbarer Rückmeldung am Avatar.

Ohne **Verification und Recovery** ist breite UI-Automation nicht
stabil genug und wird in v1 nicht freigegeben.

**Abgrenzung zum Workflow-Overlay.** Das in §5 beschriebene
Workflow-/Action-Readout darf **nicht** mit Adapter-Execution
verwechselt werden. Es rendert symbolisch, was der Core über
Action Events bekannt gibt, und ist bewusst read-only. Recovery,
Retry, Verification und die Wahl der Fidelity-Stufe bleiben
ausschließlich im Core / Desktop Interaction Layer — weder die
UI noch das Overlay treffen solche Entscheidungen oder führen sie
aus.

---

## 11. Beispielabläufe

### 11.1 Kalender-Eintrag

Nutzer: „Trag morgen 15 Uhr Zahnarzt in den Kalender ein.“

1. **Intent-Verarbeitung.** Core + ABrain erkennen Intent
   `calendar.create_event`, extrahieren Parameter (Datum, Zeit,
   Titel).
2. **Policy.** Aktion ist *schreibend*, Automation Mode ist z. B.
   `confirm before action`. Core bereitet Bestätigung vor.
3. **Interaktionsweg.** Desktop Interaction Layer wählt *native-first*:
   CalDAV-API oder Kalender-CLI des eingestellten Kalender-Clients.
4. **Avatar-Visualisierung.** Presence wechselt in *Expanded*,
   zeigt eine kurze Bestätigung („Termin morgen 15 Uhr — anlegen?“).
   Visual Action Mode `minimal feedback` genügt.
5. **Ausführung.** Nach Bestätigung legt der Automation Layer den
   Termin über die native API an.
6. **Verification.** Event liest Termin zurück oder bestätigt über
   Rückgabewert der API.
7. **Rückkehr.** Avatar meldet Erfolg und kehrt in *Docked* zurück.

### 11.2 Unbekannte, neu installierte Software

Nutzer: „Lege in App X eine Aufgabe an.“

1. **App Discovery.** Smolit kennt App X nicht. Discovery
   identifiziert Fenster, Prozessname, ggf. Accessibility-Baum.
2. **Interaktionsweg.** Keine native API bekannt. Stack versucht
   *hybrid*: Accessibility-Baum + UI-Strukturerkennung. Falls nicht
   ausreichend, Eskalation auf *pixel-guided* (OCR, Template).
3. **Policy.** Automation Mode `confirm before action`. Vor jedem
   schreibenden Schritt wird Bestätigung eingeholt.
4. **Avatar-Visualisierung.** Presence wechselt in *Action Mode*,
   Visual Action Mode `guided movement`. Der Avatar bewegt sich zum
   App-Fenster und zeigt das Zielobjekt.
5. **Ausführung.** Automation Layer klickt „Neue Aufgabe“, tippt den
   Text, speichert.
6. **Verification.** OCR / Accessibility prüft, ob die Aufgabe im
   UI erscheint.
7. **Recovery.** Falls kein Treffer: Retry, dann Rückfrage an den
   Nutzer, dann Abbruch. Der Avatar zeigt den Status wahrheitsgemäß.
8. **Rückkehr.** Presence geht zurück in *Docked*.

Diese Beispiele zeigen, wie „Variante 2“ (breite Bedienung auch
unbekannter Software) als Nutzererlebnis möglich wird, ohne dass der
Avatar selbst der Low-Level-Executor ist.

---

## 12. Sicherheitsmodell

Smolit trifft Entscheidungen über Desktop-Aktionen **nur entlang
einer klaren Policy**.

Mindestens:

- **Policy-gesteuerte Aktionen.** Jede Aktion wird gegen Presence-,
  Automation-, Fidelity- und Trust-Regeln geprüft, bevor sie
  ausgeführt wird.
- **Trusted vs. untrusted** Anwendungen/Fenster. Trusted-Apps
  können in `allowed trusted actions only` ohne einzelne Rückfrage
  bedient werden; untrusted-Apps **nicht**.
- **Confirm-before-action** ist Default für alle schreibenden oder
  sensiblen Aktionen, solange nichts anderes explizit konfiguriert
  ist.
- **Step verification.** Jede relevante Aktion wird nachverifiziert
  (siehe §10.4). Ohne Verification gilt sie als offen.
- **Kill switch.** Ein sofort verfügbarer Stop-Mechanismus (Shortcut,
  Avatar-Klick, Sprachbefehl) beendet laufende Automation.
- **Keine stille Rechteausweitung.** Eine einmal erteilte Erlaubnis
  gilt nur für den angefragten Kontext; sie wird nicht automatisch
  auf andere Anwendungen, Fenster oder Aktionsklassen übertragen.
- **Keine permanente globale Desktop-Überwachung** als Standard.
  Screenshots, Bildschirmanalyse oder OCR laufen nur **ereignisbasiert
  oder gezielt** auf die relevante Region.

Leitgedanke: **Kontrolle, Nachvollziehbarkeit, Nutzerhoheit** gehen
vor Bequemlichkeit und Automatisierungsbreite.

---

## 13. Performance-Modell

Smolit ist ein Always-on-Dienst. Ressourcenverbrauch ist damit ein
Architekturthema, kein Optimierungsdetail.

### 13.1 Performance Profiles

#### low

- Minimale Avatar-Intensität, bevorzugt *Icon only* oder
  *Light avatar*.
- Keine aufwändige Bildschirmanalyse.
- Animationen auf ein Minimum reduziert.
- Eignung: ältere Hardware, Akkubetrieb, Fokus-Arbeit.

#### balanced

- Standardprofil.
- Light/Full avatar je nach Presence-Einstellung.
- Bildschirmanalyse nur ereignisbasiert.
- Animation moderat.

#### high fidelity

- Volle Avatar-Ausdrucksstärke.
- Hybrid-/Vision-Wege bereit, wenn vom Automation Mode erlaubt.
- Mehr Animation und Theatralik möglich (siehe Visual Action Modes).
- Eignung: leistungsstarke Hardware, Demo-Szenarien.

### 13.2 Querschnittsregeln

- **Idle muss extrem sparsam bleiben.** Kein dauerhaftes Rendering,
  kein permanenter Vision-Loop.
- **Keine permanente Desktop-Vision** als Default. Screen-Analyse
  nur punktuell und zielgerichtet.
- **Analyse nur ereignisbasiert** oder gezielt auf definierte
  Fenster / Regionen.
- **Animationen nur bei Bedarf** (Presence-Änderung, Action, Feedback).
- **Alte Hardware** muss durch eine Kombination aus niedrigem
  Performance Profile und reduziertem Presence/Visual Action Mode
  nutzbar bleiben.

---

## 14. Was ausdrücklich nicht Ziel von v1 ist

- **Keine permanente globale Pixelüberwachung.** Kein Dauer-Screenshot,
  kein Dauer-OCR über den gesamten Desktop.
- **Keine unbeschränkte vollautonome Desktop-Kontrolle.** Smolit ist
  kein selbstständiger Operator ohne Policy.
- **Kein Avatar als direkter Executor.** Der Avatar visualisiert,
  er führt nicht aus.
- **Kein komplexes Daueranimationssystem** als Standardverhalten.
  Idle ist ruhig.
- **Keine ungeprüfte Interaktion mit sensiblen Systemdialogen**
  (Passwort, sudo, Zahlungs-UIs, Admin-Prompts).
- **Keine Annahme, dass jede unbekannte UI sofort perfekt beherrscht
  wird.** Unbekannte Software ist ein *Zielhorizont*, kein
  garantierter Funktionsumfang.

---

## 14a. Action Event Model v1 als verbindende Schicht

Seit dem Core-Update zum Action Event Model v1 (siehe
[`docs/api.md`](./api.md), §2.5) gibt es eine erste konkrete Brücke
zwischen Core, UI und der künftigen Desktop-Interaktionsschicht.

- **Verbindungsschicht.** Action Events (`action_planned`,
  `action_started`, `action_step`, `action_completed`,
  `action_failed`, …) sind der kanonische Strom, mit dem der Core
  sichtbare Handlung und Phasen kommuniziert. Jede Aktion trägt eine
  stabile `action_id`, damit UI, Logs und spätere Replay-/Trace-
  Systeme dieselbe Entität referenzieren.
- **Target-Abstraktion.** Das Feld `target` beschreibt das
  **Handlungsziel** (Anwendung, Fenster, UI-Element, Region,
  unknown). Es ist in v1 nur eine Datenstruktur — der Core emittiert
  derzeit `{"type":"unknown"}` —, aber die Schicht ist so vorbereitet,
  dass spätere Automation-Adapter strukturierte Ziele liefern können,
  ohne das Protokoll zu brechen.
- **Symbolisches Visual Mapping.** Das optionale Feld `mapping` trägt
  `space` ∈ `logical_space` · `window_space` · `screen_space` plus
  einen kurzen `hint`. Für v1 **nicht** emittiert, aber bereits
  Bestandteil des Modells. Pixelgenaue Bewegung ist explizit kein Ziel
  von v1 (siehe §9 / §14).
- **Failure States.** `action_failed` transportiert Message und
  optionalen Fehlerkontext zusätzlich zur bestehenden `error`-
  Nachricht. Das ist die Grundlage für spätere sichtbare Fehlerzustände
  des Avatars (stoppt, warnt, fragt nach, kehrt zurück) — gemäß §12
  und §14.
- **Grenzen.** Action Events beschreiben Handlung; sie führen keine
  Automation aus, enthalten keine Koordinaten und eskalieren keine
  Rechte. Sie sind eine **Darstellungs-/Synchronisationsschicht**, kein
  Executor.

---

## 14b. Desktop Interaction Layer MVP

Mit diesem Schritt bekommt der Desktop Interaction Layer eine erste,
echte Core-seitige Existenz (`core/src/interaction/`, siehe auch
[`docs/api.md`](./api.md), §2.6). Das Modul ist bewusst klein, aber
vollständig genug, um den Rest dieses Dokuments nicht mehr rein
hypothetisch dastehen zu lassen.

### 14b.1 Rollen und Trennung

- **InteractionAction** (`action.rs`) — strukturierte Core-interne
  Aktion mit `InteractionKind`, `ActionTarget`, typisiertem Payload
  und Policy-Flags (`requires_confirmation`, `trusted_only`).
- **InteractionBackend** (`backend.rs`) — schmales Trait-Interface mit
  MVP-Operationen `open_application`, `focus_window`, `type_text`,
  `send_shortcut`. Genau **ein** konkretes Backend heute:
  `CommandBackend`.
- **InteractionExecutor** (`executor.rs`) — wendet `InteractionPolicy`
  an, dispatcht an das Backend, wandelt Verifikation und Fehler in
  Action Events.
- **VerificationResult** (`verifier.rs`) — explizite Confidence
  (`verified` / `uncertain` / `failed`). MVP liefert für
  `open_application` bewusst `uncertain`, solange keine Window-Probe
  existiert.
- **RecoveryHint** (`recovery.rs`) — kleine Taxonomie (`retry`,
  `abort`, `ask_user`, `fallback_unavailable`). Wird im
  `action_failed`-Event im `error`-Feld als
  `recovery_hint=<variant>` mitgeliefert, damit UI/Logs klassifizieren
  können, ohne Freitext zu parsen.

### 14b.2 Interaction Fidelity Einordnung

Das MVP-Backend liegt strikt in der **native-first**-Zone (§9.1): es
spawnt einen konfigurierten Launcher-Command (`xdg-open`,
`gtk-launch`, o. Ä.) und verlässt sich auf das System. Kein
Pixel-Matching, kein OCR, keine Accessibility-Trees, keine
globale Eingabe. Erst mit zusätzlichen Backends können wir in die
`hybrid`- und `pixel-guided`-Zonen vordringen — dieser MVP ist
bewusst zu wenig, um missbraucht zu werden.

### 14b.3 Automation-Modus-Einordnung

In der Sprache von §8 entspricht das MVP am ehesten **assist only**
(§8.2), erweitert um eine deklarierte, aber noch nicht betretbare
Schwelle zu **confirm before action** (§8.3): Aktionen mit
`requires_confirmation=true` werden bei aktivem
`SMOLIT_INTERACTION_REQUIRE_CONFIRMATION` **abgewiesen**, solange
kein Confirmation-Kanal existiert. Das ist der ehrliche MVP-Zustand
— keine Pseudo-Automation, keine stille Eskalation.

### 14b.4 Ehrliche Scope-Grenzen

- `type_text` und `send_shortcut` sind als Hooks modelliert, liefern
  aber immer `BackendUnsupported`. Das Protokoll kennt sie bereits,
  der Executor emittiert `action_failed` mit
  `recovery_hint=fallback_unavailable`.
- `focus_window` ist als erster echter Targeting-Schritt
  implementiert, bleibt aber konservativ: das Backend ruft ein
  extern konfiguriertes Command-Template (`wmctrl -a {name}` o. Ä.)
  auf und liefert bei Erfolg bewusst `uncertain`, weil keine
  Fokus-Probe existiert. Ohne Template oder unter Wayland meldet
  der Core ehrlich `BackendUnsupported("focus_window")` statt einen
  Pseudo-Erfolg zu fälschen. Siehe [api.md](./api.md), §2.6.
- Kein Window-Probe, kein Screenshot, kein OCR, keine globale
  Eingabe. Verification bleibt „best-effort" und wird im
  `action_verification`-Event mit dem Präfix `Best-effort:` klar
  markiert.
- Kein Trust-Modell für Anwendungen: das Flag `trusted_only` wird
  durchgereicht, gated aber heute nichts — §7 bleibt offen.

### 14b.5 Nächste Schritte (nicht Teil dieses MVP)

- Echte Confirmation-UX über IPC (`interaction_confirm` / `… deny`).
- Backend für Linux mit AT-SPI oder D-Bus (§16, erste Offene Punkte).
  Eine erste, bewusst kleine Ausbaustufe ist bereits gelandet — siehe
  §14c (Linux Accessibility Backend Spike).
- Optional: Window-Probe nach `open_application` und `focus_window`,
  um von `uncertain` auf `verified` hochzustufen.
- Reichere Ziel-Auflösung für `focus_window` (strukturierte Discovery
  §10.1 statt symbolischem Substring-Match im Helper).
- Structured Targets aus einer Discovery-Stufe (§10.1), damit
  `target` jenseits von `application:<name>` strukturiert wird.
- Richtige Schaltflächen im Presence Layer für „ausführen /
  abbrechen / bestätigen".

---

## 14c. Linux Accessibility Backend Spike (Ist-Zustand, klein)

Ab der Accessibility-Spike-Phase enthält der Core einen eigenen
Capability-Pfad im Interaction Layer
(`core/src/interaction/accessibility.rs`). Dieser Pfad ist:

- **Read-only.** Er klickt nicht, tippt nicht, fokussiert nicht.
- **Environment-basiert.** Er prüft Session-Typ, `DISPLAY` /
  `WAYLAND_DISPLAY`, `DBUS_SESSION_BUS_ADDRESS` und — wo möglich —
  den Session-Bus-Socket im Dateisystem.
- **Honest by construction.** Der Probe liefert einen der drei
  Status-Werte `uncertain` / `unavailable` / `failed` mit einer
  Begründung; nie einen Fake-`available`. Die Discovery ergänzt
  zusätzlich `ok` — genau dann, wenn strukturierte Items entstehen
  (heute: Hint-Echo-Items aus `inspect_target(hint)`).
- **Getrennt vom `CommandBackend`.** Der Command-Pfad
  (`open_application`, `focus_window`) bleibt unverändert. Das
  Accessibility-Spike ergänzt ihn, ersetzt ihn nicht.

IPC-Oberfläche (Details in [api.md](./api.md), §2.8):

- `interaction_probe_accessibility` — startet die Probe.
- `interaction_discover_accessibility` — optionaler `hint`.
- Ergebnisse als `accessibility_probe_result` /
  `accessibility_discovery_result` zusätzlich zu den bekannten
  Action Events.

Was im Spike bewusst **nicht** drin ist:

- Kein AT-SPI-RPC, kein Tree-Walking, keine App-spezifischen
  Adapter. Der nächste Schritt ist eine echte zbus/atspi-Anbindung
  an das Registry-Root (z. B. `GetChildren`); erst dann können
  `items` inhaltlich gefüllt werden.
- Kein Fokus-, Klick- oder Eingabe-Pfad — das bleibt dem bestehenden
  Command-Backend (und späteren Portal-/Compositor-Pfaden)
  vorbehalten.
- Kein Approval. Probe und symbolische Discovery sind strikt
  lesend; sobald ein accessibility-getriebener Pfad schreibend
  würde, muss er durch den bestehenden Approval-Flow (§14b.3 bzw.
  `api.md` §2.7).

Damit ist Accessibility in Smolit heute ein **strukturierter,
ehrlicher Discovery-Pfad**, nicht mehr und nicht weniger. Discovery
ist ausdrücklich nicht dasselbe wie Automation.

### 14c.1 Verified vs. Discovered — ehrliche Confidence-Stufen

Discovery-Ergebnisse tragen ab dieser Phase pro Item eine explizite
`confidence`-Stufe:

- **`verified`** — Ausdrücklich **reserviert** für einen späteren
  Pfad, der ein Target über einen echten AT-SPI-Registry-Zugriff
  bestätigt (Rolle, Name, eventuell eindeutiger Pfad im A11y-Baum).
  Der aktuelle Spike emittiert `verified` nie — sonst würde er eine
  Sicherheit behaupten, die er nicht belegen kann.
- **`discovered`** — Das Item ist als strukturiertes Target
  weitergegeben, aber nicht unabhängig abgesichert. Heute ausschließ­
  lich durch den Hint-Echo-Pfad: die UI/Core-Aufrufer nennt einen
  Namen, der Spike führt ihn in der Schemaform
  (`{kind, name, role?, matched_hint, …, confidence: "discovered",
  source: "accessibility_hint_echo"}`) weiter.

Die UI-Seite (Presence/Overlay) darf beide Stufen sichtbar machen,
aber sie darf `discovered` **nicht** stillschweigend in `verified`
umetikettieren. Die Stufe ist eine Core-Aussage.

Zum Zusammenspiel mit dem Presence-Modell heißt das:

- A11y-Discovery wird als **lesende, strukturierte Target-Quelle**
  behandelt — vergleichbar mit `ActionTarget::application(name)`,
  nur mit zusätzlicher Herkunft und Confidence.
- Kein A11y-Ergebnis löst automatisch eine Action aus; zwischen
  „Target gefunden" und „Action ausgeführt" liegt weiterhin der
  Approval-Flow (§14b.3), sobald überhaupt ein schreibender Pfad
  existiert.

### 14c.2 Target Selection — der Schritt zwischen Discovery und Execution

Zwischen Discovery und Execution sitzt eine explizite, kleine Stufe:
Die UI kann ein entdecktes Target als **aktuellen Interaction-Kontext**
markieren (siehe `docs/api.md` §2.9). Der Core hält genau einen Slot
im Speicher und bestätigt mit `target_selected`; „Clear" räumt ihn
über `target_cleared`. Mehrere gleichzeitige Targets gibt es nicht.

Die Auswahl ist **keine Berechtigung**. Sie

- ist sichtbar (die UI rendert eine Badge plus Approval-Hinweis),
- ist reversibel (explicit Clear, Disconnect, Fehler),
- ist kurzlebig (kein Persistenz-Layer, kein Cross-Session-Memory),
- wird beim nächsten Approval nur als **Kontext** mitgeliefert —
  Policy-Checks und Nutzer-Bestätigung laufen unverändert.

Damit wird die Kette aus §14c und §14b.3 sichtbar:
Probe → Discovery → *Selection* → Approval → Execution.
Jede Stufe bleibt separat abschaltbar; keine Stufe leitet
stillschweigend zur nächsten durch.

---

## 15. Konsequenzen für die weitere Architektur

Aus diesem Modell ergeben sich für die folgenden Arbeitspakete
direkte Implikationen:

- **Godot UI bleibt Presentation/Presence Layer.** Keine
  Automatisierungs-Logik in Godot.
- **Desktop Automation ist eine eigene Schicht / Adapterfamilie**
  im Core bzw. hinter dem Core. Sie wird unabhängig von der UI
  versioniert und getestet.
- **IPC-/Event-Modell** muss zukünftig Action-, Verification- und
  Failure-Events tragen können (additive Erweiterung in
  [docs/api.md](./api.md)).
- **Avatar-States** müssen später auf Interaktionsphasen reagieren
  können (z. B. `targeting`, `executing`, `verifying`, `recovered`,
  `aborted`).
- **OS-/App-spezifische Integrationen** sollen bevorzugt werden,
  bevor Pixel-Fallbacks greifen — der Stack-Selektor folgt
  Interaction Fidelity.
- **Konfiguration** muss die fünf Modusachsen (Presence, Visual
  Action, Automation, Interaction Fidelity, Performance) als
  getrennte, nutzerseitig einstellbare Größen abbilden.

---

## 16. Offene Punkte / spätere Entscheidungen

- **Linux-spezifische Accessibility-/Automation-Backends**
  (AT-SPI, D-Bus, libinput-Wege, Toolkit-Unterschiede).
- **Wayland vs. X11.** Beide haben unterschiedliche Möglichkeiten
  für globale Eingaben, Overlays und Screenshots. Strategie pro
  Session-Typ ist offen.
- **OCR / Template-Erkennung.** Auswahl der Engine(s), Umgang mit
  Skalierung, Mehrmonitor-Setups, DPI.
- **Safe Sandboxing** für UI-Automation (getrennte Prozessrechte,
  optionales Capability-Modell).
- **Permission- und Approval-UX.** Wie werden Bestätigungen,
  Trust-Markierungen und Widerrufe im Avatar/Overlay angezeigt?
- **Mapping von Core-Actions auf Avatar-Motion.** Wie werden
  Action-Phasen in Bewegungs-/Mimik-Primitiven übersetzt?
- **Asset- und Animationspipeline.** Wie werden Character-Assets,
  Szenen und Animationen versioniert und ausgetauscht?
