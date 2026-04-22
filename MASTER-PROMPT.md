# Smolit Assistant – Idempotenter Entwickler-Master-Prompt für Codex

Repository: Smolit-Assistant
Arbeitsverzeichnis: <repo-root>

## Ziel

Setze die Smolit-ROADMAP schrittweise, architekturkonform, idempotent und möglichst autonom um.

WICHTIG:

* Arbeite streng entlang von `ROADMAP.md`
* Implementiere immer nur den **nächsten sinnvollen, noch nicht abgeschlossenen Schritt**
* Keine Parallelarchitektur
* Keine Reaktivierung historischer Legacy-Pfade
* Keine zweite Wahrheit für Kernfunktionen
* Jeder Schritt muss reviewbar, testbar und mergebar sein
* Jeder Schritt muss idempotent vorbereitet werden:

  * wenn etwas schon vorhanden oder bereits gemerged ist, sauber erkennen
  * dokumentieren
  * und **nicht doppelt bauen**

---

## A. SYSTEMKONTEXT / SOURCE OF TRUTH

Nutze als primäre Wahrheiten:

1. `ROADMAP.md`
2. aktuelle `main`-Branch-Realität
3. die kanonische Smolit-Architektur:

   * UI (Godot) → Core (Rust) → ABrain → Tools
4. `core/` als einzige kanonische Runtime für:

   * Orchestrierung
   * IPC
   * Audio
   * ABrain-Integration
5. `core/src/app.rs` als zentrale Service-/Handler-Verdrahtung
6. `core/src/ipc/` als einzige IPC-Surface
7. `core/src/audio/` als einzige Audio-Surface
8. `ui/` als einzige UI-Surface
9. `README.md` als Einstieg
10. `ROADMAP.md` als Umsetzungsreihenfolge
11. `docs/` als Ort für Architektur-, Review- und Inventar-Dokumente

Wenn alte Dateien, experimentelle Reste, verworfene Ansätze oder historische Branches etwas anderes behaupten:

* zuerst aktuellen `main` prüfen
* nur übernehmen, wenn architekturkonform und nicht obsolet

---

## B. ALLGEMEINE INVARIANTEN

Diese Regeln gelten in **jedem** Schritt:

1. Keine Parallel-Implementierung
2. Keine zweite Runtime neben `core/`
3. Kein zweiter IPC-Stack neben `core/src/ipc/`
4. Kein zweiter Audio-Stack neben `core/src/audio/`
5. Keine Business-Logik in UI, Mock-Dateien oder bloßen DTO-/Schema-Dateien
6. Keine versteckte Reaktivierung von Legacy
7. Nur additive, nachvollziehbare Änderungen
8. Keine schweren neuen Abhängigkeiten ohne klare Notwendigkeit
9. Keine harte Modellkopplung, wenn ein Adapter genügt
10. Jeder Schritt braucht:

* Tests
* Review-Doku
* saubere Diff-Grenze
* Merge-Gate

Wenn eine dieser Invarianten verletzt würde:

* **nicht** direkt implementieren
* stattdessen dokumentieren, warum der Schritt so nicht zulässig ist
* eine minimale architekturkonforme Variante wählen

---

## C. IDEMPOTENTER ARBEITSMODUS

Vor **jedem** Schritt:

1. Prüfe den aktuellen `main`-Stand
2. Prüfe, ob der geplante Schritt bereits vollständig oder teilweise umgesetzt ist
3. Prüfe, ob parallele Branches oder vorhandene Dateien denselben Scope schon abdecken
4. Prüfe, ob ein Teil bereits gemerged ist
5. Prüfe, ob der Schritt aus der Roadmap inzwischen durch spätere Arbeiten überholt wurde

Wenn der Schritt:

* bereits vollständig auf `main` ist:

  * nicht neu bauen
  * nur bestätigen und nächsten Schritt wählen
* teilweise vorhanden ist:

  * nur die fehlenden, architekturkonformen Teile ergänzen
* in einem parallelen Branch bereits existiert:

  * nur sauber integrieren, reviewen oder angleichen
  * nicht neu erfinden

Immer dokumentieren:

* was schon da war
* was fehlte
* was konkret ergänzt wurde
* warum keine Doppelarbeit entstand

---

## D. ROADMAP-STEUERUNG

Arbeite streng entlang der Priorität in `ROADMAP.md`.

Stand heute gilt folgende Reihenfolge:

1. Phase 0 – Core Foundation
2. Phase 1 – Voice Interface
3. Phase 2 – IPC Bridge
4. Phase 3 – Avatar UI
5. Phase 4 – Behavioral Layer
6. Phase 5 – Personality & Memory
7. Phase 6 – Presence System
8. Phase 7 – Interaction Layer
9. Phase 8 – Tool Integration
10. Phase 9 – Intelligence Expansion
11. Phase 10 – Production

WICHTIG:

* Überspringe keine Phase ohne explizite Begründung
* Wenn eine spätere Phase logisch auf einer früheren aufbaut, aber diese noch nicht sauber abgeschlossen ist:

  * zuerst die frühere Phase zu Ende bringen
* Kleine vorbereitende Schritte innerhalb einer Phase sind erlaubt, wenn sie die Phase sauber voranbringen
* Wenn eine Phase zu groß ist:

  * teile sie in sinnvolle, reviewbare Subeinheiten
  * aber nur entlang echter Architekturgrenzen

---

## E. PRO TURN / PRO SCHRITT VORGEHEN

Für den jeweils nächsten sinnvollen Schritt:

1. `ROADMAP.md` lesen
2. aktuellen `main` analysieren
3. nächsten logisch offenen Schritt bestimmen
4. Scope präzise festlegen
5. betroffene kanonische Dateien identifizieren
6. optional Inventar-/Analyse-Dokument erzeugen
7. minimal und sauber implementieren
8. Tests ergänzen oder anpassen
9. Review-Dokument schreiben
10. Review-/Merge-Gate durchführen
11. Nur wenn grün: sauber nach `main` mergen

Wenn ein Schritt zu groß ist:

* in Subeinheiten zerlegen
* aber nicht künstlich in wertlose Mikroschritte zerstückeln

---

## F. VERPFLICHTENDE ARTEFAKTE JE SCHRITT

Für jeden Schritt sind verpflichtend:

1. Branch:

   * `codex/<phase-or-scope>`

2. Review-Doku:

   * `docs/reviews/<phase-or-scope>_review.md`

3. Optionales Inventar:

   * `docs/reviews/<phase-or-scope>_inventory.md`
   * wenn Analyse nötig ist

4. Tests:

   * gezielte neue Tests
   * plus relevante Pflichtsuite

5. Abschlussausgabe:

   * was wurde geändert
   * warum architekturkonform
   * welche Tests grün
   * merge-reif ja/nein
   * falls gemerged: `main` commit hash

---

## G. STANDARD-PRÜFLOGIK / TESTSUITE

Je nach betroffenem Scope mindestens passend ausführen.

### Wenn `core/` betroffen ist

* `cd core`
* `cargo check`
* `cargo test`
* `cargo run --quiet` Smoke, wenn sinnvoll

### Wenn IPC betroffen ist

* Parsing-/Protocol-Tests
* WebSocket-Integrationstests, wenn vorhanden oder sinnvoll

### Wenn Audio betroffen ist

* Command-Splitting / Command-Adapter-Tests
* Fehlerpfad-Tests
* Timeout-/Fallback-Prüfungen, soweit sinnvoll

### Wenn UI betroffen ist

* prüfe Godot-Projektstruktur
* prüfe, dass keine Business-Logik aus dem Core in die UI wandert
* wenn Build-/Export-/Lint-/Headless-Smokes definiert sind, führe sie aus

### Wenn Doku betroffen ist

* Konsistenzcheck:

  * `README.md`
  * `ROADMAP.md`
  * `docs/`

### Wenn Konfiguration betroffen ist

* `.env.example` prüfen
* Defaults und Fallbacks prüfen
* keine stillen Hardcodings einführen

### Grundsatz

* nur Tests fahren, die für den Schritt sinnvoll und verfügbar sind
* aber nie ohne nachvollziehbare Prüfung abschließen

---

## H. REVIEW-/MERGE-GATE (STANDARD)

Nach jeder Umsetzung **muss** ein Gate durchgeführt werden.

Prüfe mindestens:

1. Scope korrekt?
2. Nächster Roadmap-Schritt wirklich sinnvoll gewählt?
3. Keine Parallelstruktur?
4. Kanonische Pfade genutzt?
5. Keine Business-Logik in falscher Schicht?
6. Keine neue Schatten-Wahrheit?
7. Tests grün?
8. Dokumentation konsistent?
9. Merge-reif ja/nein?

Wenn **NEIN**:

* exakte Blocker auflisten
* minimalen Fix-Plan definieren
* nicht mergen

Wenn **JA**:

* `git checkout main`
* `git pull --ff-only origin main`
* `git merge --ff-only <branch>`
* `git push origin main`

Keine Merge-Commits.
Nur Fast-Forward, wenn sauber möglich.

---

## I. ENTSCHEIDUNGSLOGIK FÜR DEN NÄCHSTEN SCHRITT

Zu Beginn jeder Ausführung:

1. Lies `ROADMAP.md`
2. Prüfe aktuellen `main`-Zustand
3. Identifiziere den nächsten logisch offenen Roadmap-Schritt
4. Begründe kurz, warum genau dieser Schritt jetzt dran ist
5. Implementiere **nur diesen Schritt**

Wenn mehrere Schritte parallel sinnvoll erscheinen:

* bevorzuge den mit dem höchsten Architektur- und Produkthebel
* beachte die Roadmap-Priorität
* keine unnötige Parallelisierung ohne Mehrwert

---

## J. SPEZIFISCHE SMOLIT-REGELN

Diese Regeln sind zusätzlich verbindlich:

1. Der Rust-Core bleibt die einzige ausführende Kernlogik
2. Die Godot-UI bleibt Renderer + Interaktionsschicht, nicht Brain
3. ABrain bleibt die kognitive Instanz
4. Audio bleibt pluggable und austauschbar
5. Keine direkte harte Kopplung an einzelne TTS/STT-Engines, wenn Adapter genügen
6. Keine Tool-Logik direkt in die UI
7. Keine zweite Session-/State-Wahrheit in UI-Dateien
8. IPC bleibt lokal und core-driven
9. Präsenz-/Avatar-Verhalten nur auf bestehende Core-Signale aufsetzen
10. Jeder neue UI-Schritt muss die Trennung Core ↔ UI wahren

---

## K. ERWARTETE ABSCHLUSSAUSGABE PRO DURCHLAUF

Am Ende jedes Durchlaufs kompakt ausgeben:

1. Welcher Roadmap-Schritt wurde bearbeitet?
2. Warum war er jetzt der richtige nächste Schritt?
3. Welche Dateien wurden geändert?
4. Was war schon vorhanden?
5. Was fehlte?
6. Was wurde konkret ergänzt?
7. Welche Architektur-Invarianten wurden explizit bewahrt?
8. Welche Tests liefen grün?
9. Ist der Branch review-reif?
10. Wurde gemerged?
11. Falls ja:

* neuer `main` commit
* Push bestätigt

12. Falls nein:

* exakte Blocker

13. Welcher Schritt wäre danach logisch als nächstes dran?

---

## L. STARTANWEISUNG FÜR JEDEN DURCHLAUF

Beginne jetzt immer mit:

1. `ROADMAP.md` lesen
2. aktuellen `main` prüfen
3. nächsten offenen, logisch richtigen Schritt bestimmen
4. prüfen, ob er schon ganz oder teilweise existiert
5. den Schritt sauber umsetzen
6. Tests ausführen
7. Review-/Merge-Gate durchführen
8. Ergebnis strukturiert ausgeben

WICHTIG:

* idempotent
* keine Doppelarbeit
* keine Legacy-Reaktivierung
* keine Parallelstruktur
* nur kanonische Weiterentwicklung
* immer nur ein reviewbarer Schritt auf einmal

---

## M. AKTUELLE PRIORISIERUNG FÜR SMOLIT

Stand jetzt sind Phase 0, Phase 1 und Phase 2 bereits weitgehend umgesetzt.

Daher gilt für die nächste sinnvolle Weiterentwicklung in der Regel:

1. Phase 3 – Avatar UI
2. danach Phase 4 – Behavioral Layer
3. danach Phase 5 – Personality & Memory

Falls `main` etwas anderes zeigt, entscheide anhand der tatsächlichen Repo-Realität — nicht anhand veralteter Annahmen.

---

## N. VERHALTENSREGEL BEI UNSICHERHEIT

Wenn Unsicherheit besteht:

* erst prüfen
* dann entscheiden
* nie doppelt bauen
* nie “vorsorglich” Parallelstrukturen anlegen
* lieber minimal anschlussfähig erweitern als großflächig neu entwerfen

Bei Konflikt zwischen Roadmap und Repo-Realität:

* Repo-Realität prüfen
* Abweichung dokumentieren
* dann den nächsten architekturkonformen Schritt wählen

---

## O. ZIELZUSTAND DES PROMPTS

Dieser Prompt soll Codex dazu zwingen:

* automatisch den nächsten sinnvollen Schritt zu wählen
* vorhandene Arbeit zu respektieren
* keine Doppelarbeit zu erzeugen
* architekturkonform zu bleiben
* jeden Schritt reviewbar und mergebar zu halten
* Smolit schrittweise entlang der Roadmap in ein produktionsreifes System zu überführen
