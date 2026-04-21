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
              │  (Docked / Expanded /    │   Bewegungen, Rückmeldungen
              │   Action Mode)           │
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
| Presence Layer (Avatar)      | Sichtbarkeit, Zustände, Animation, Nutzerwahrnehmung    |
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

---

## 6. Always-on-top-Konzept

Als Zielarchitektur (nicht als Ist-Zustand) gilt ein
Drei-Zustands-Modell für das sichtbare Fenster/Overlay.

### 6.1 Docked

- Kleiner, always-on-top Präsenzpunkt bzw. Miniatur-Avatar.
- Ruhezustand — minimale Animation, minimale CPU/GPU-Last.
- Frei positionierbar (Ecke, Kante, Nutzer-definierte Position).
- Dient als Anker, von dem aus sich Smolit in andere Zustände
  entfaltet.

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
- **Im MVP** werden freigabepflichtige Aktionen (`requires_confirmation`
  zusammen mit `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION=true`)
  schlicht abgelehnt. Der Confirmation-Kanal selbst landet in einer
  späteren Phase.

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
  MVP-Operationen `open_application`, `type_text`, `send_shortcut`.
  Genau **ein** konkretes Backend heute: `CommandBackend`.
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
- Kein Window-Probe, kein Screenshot, kein OCR, keine globale
  Eingabe. Verification bleibt „best-effort" und wird im
  `action_verification`-Event mit dem Präfix `Best-effort:` klar
  markiert.
- Kein Trust-Modell für Anwendungen: das Flag `trusted_only` wird
  durchgereicht, gated aber heute nichts — §7 bleibt offen.

### 14b.5 Nächste Schritte (nicht Teil dieses MVP)

- Echte Confirmation-UX über IPC (`approval_requested` /
  `approval_response`) — kommt in der nächsten Phase.
- Backend für Linux mit AT-SPI oder D-Bus (§16, erste Offene Punkte).
- Optional: Window-Probe nach `open_application`, um von `uncertain`
  auf `verified` hochzustufen.
- Ein `focus_window`-Kind auf demselben Action-Event-Modell
  (kommt im Anschluss an den Approval-Flow).
- Structured Targets aus einer Discovery-Stufe (§10.1), damit
  `target` jenseits von `application:<name>` strukturiert wird.
- Richtige Schaltflächen im Presence Layer für „ausführen /
  abbrechen / bestätigen".

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
