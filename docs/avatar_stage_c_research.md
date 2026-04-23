# Avatar Appearance — Stage C Research & Design Notes

Status: **Forschungs- und Designdokument.**
Kein Implementierungsplan, kein Produktversprechen, kein genehmigter
Scope. Dieses Dokument bereitet lediglich eine spätere, gesonderte
Entscheidung darüber vor, ob und in welcher Form eine Stage C der
Avatar-/Appearance-Linie überhaupt begonnen wird.

Alle in diesem Dokument genannten Optionen, Manifeste, Formate,
Feldnamen und Architekturpfade sind **beispielhaft und unverbindlich**.
Nichts hier legt ein Format, eine Datei oder eine Runtime fest.

Crosslinks:
[`docs/ui_architecture.md`](./ui_architecture.md) §8b,
[`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
Unterabschnitt „Avatar-Personalisierung als Presence-Erweiterung",
[`ROADMAP.md`](../ROADMAP.md) Phase 4b.

---

## 1. Zweck des Dokuments

Stage A und Stage B der Avatar-Appearance-Linie sind geschlossen,
gemerged und durch Smoketests gedeckt
(siehe [`docs/ui_architecture.md` §8b.7 / §8b.8](./ui_architecture.md)).
Beide Stufen sind bewusst klein, markennah und prozedural gehalten:
Smolit Salamander bleibt Default und Referenz; die drei kuratierten
Alternativen (`robot_head`, `humanoid_head`, `orb`) sind prozedural
gezeichnet, ohne Binärassets, ohne Import-Pipeline und durch einen
Capability-Contract abgesichert.

Stage C wird in §8b.4 und in der Roadmap als „Ziel-Zustand" geführt —
etwa als Möglichkeit, eigene Icons / Figuren / template-basierte
Inhalte zuzulassen. Dieser Ziel-Zustand ist bisher **nicht
architektonisch ausgearbeitet** und **nicht sicherheitsmodelliert**.
Zwischen Stage B (vollständig kuratiert, vollständig prozedural) und
einer offeneren Stage C (erweiterte Quellen, evtl. externe Inhalte)
liegen mehrere grundsätzliche Entscheidungen über Sicherheitsmodell,
Dateiformate, Validierung, Vertrauensoberflächen und UX-Grenzen. Diese
Entscheidungen dürfen nicht beim ersten Implementierungs-PR beiläufig
getroffen werden.

Zweck dieses Dokuments:

- die **offenen Fragen vor Stage C** explizit festhalten,
- mögliche **Architekturpfade nüchtern vergleichen**, ohne eine Wahl
  vorwegzunehmen,
- **harte Nicht-Ziele** dieser Stufe klar markieren,
- ein **Sicherheits- und Vertrauensmodell** skizzieren, bevor Code
  geschrieben wird,
- **Exit-Kriterien** definieren, die erfüllt sein müssen, bevor aus
  Forschung eine echte Implementierungs-Stage wird.

Warum Stage B nicht direkt in offene Avatar-Erweiterbarkeit überführt
wird:

- Stage B ist bewusst ein Katalog mit vier festen, prozedural
  definierten Templates hinter einem statischen Capability-Contract.
  Der Contract ist intern — er beschreibt, was die vier im Repo
  gepflegten Templates dem Avatar-Controller anbieten. Er ist **kein
  öffentliches Eingabeformat** und keine API für externe oder
  nutzerdefinierte Inhalte.
- Der Schritt von „prozedural, kuratiert, im Repo" zu „extern
  beschreibbar, evtl. nutzerseitig" ändert die **Vertrauensoberfläche**
  des Systems, selbst wenn die Funktion rein visuell bleibt. Parser,
  Decoder, Dateizugriffe und Rendering-Pfade für nicht-kuratierte
  Inhalte sind Angriffs- und Stabilitätsflächen, die heute nicht
  existieren und die die Architektur bisher nicht adressiert.
- Ein direktes „Stage B wird zu Stage C aufgebohrt" würde diese
  Entscheidungen stillschweigend im Code treffen. Das widerspricht dem
  Architekturprinzip, dass Sicherheits- und Trust-Grenzen explizit und
  vor der Implementierung entschieden werden.

Stage C ist deshalb in diesem Zyklus ausdrücklich **research-gated** und
**security-gated**: erst Entscheidung, dann Implementierung — nicht
andersrum.

---

## 2. Aktueller Stand vor Stage C

Kurzfassung dessen, worauf Stage C aufsetzen würde, wenn sie jemals
startet. Maßgeblich bleibt die Detailbeschreibung in
[`docs/ui_architecture.md` §8b](./ui_architecture.md); hier nur die
Punkte, die für die Stage-C-Diskussion relevant sind.

- **Default ist Smolit Salamander.** Er bleibt erster-Klasse,
  Referenz-Template und einziger Fallback für alle fehlschlagenden
  Pfade. Kein alternatives Template ersetzt ihn, auch nicht bei
  expliziter Nutzerwahl über Env oder UI-Preferences.
- **Stage A (MVP-Spike).** Rein markentreue Personalisierung nur für
  Smolit: vier Themes (`default`, `soft`, `tech`, `minimal`), drei
  UI-Behavior-Profile (`calm`, `lively`, `reserved`), kleine
  Appearance-Overrides (`primary_tint`, `intensity`, `scale`).
  Steuerung über Env, gespeicherte UI-Preferences
  (`user://smolit_ui.cfg`, Sektion `[avatar_appearance]`) und harte
  Defaults — Priorität feldweise `Env > Prefs > Default`.
- **Stage B (kuratierter Spike, gehärtet).** Drei zusätzliche Identity-
  IDs (`robot_head`, `humanoid_head`, `orb`), alle prozedural über
  `avatar_identity_visual.gd` gezeichnet. Kein Asset-Import, kein
  Bildformat, keine Plugin-Sprache. Jedes Template hat einen
  **Capability-Contract** in `avatar_template_capabilities.gd`
  (`states_supported`, optional `state_fallback`, `ExpressionLevel`
  pro Achse: `theme_tint`, `behavior_profile`, `state_pulse`, `wiggle`,
  `error_startle`). Der Avatar-Controller fragt diesen Contract an,
  statt auf Identity-IDs zu verzweigen.
- **Fallback-Disziplin.** Unbekannte Identity-/Theme-/Profile-Werte
  fallen in allen Schichten auf Smolit bzw. die markennahen Defaults
  zurück — nie auf eine der Alternativen. Unbekannte States fallen
  deterministisch auf `IDLE`. Unbekannte Enum-Werte in
  Preferences-Dateien werden beim Laden verworfen und geloggt.
- **Saubere Trennung von Personality / Policy / Behavior.** Appearance
  beeinflusst weder Action-Events, noch ABrain, noch Approval-Flows,
  noch Permissions, noch Presence-Modi. Das ist bindend und wird durch
  die Architekturprinzipien in §8b und die Klarstellung in
  [`docs/presence_desktop_interaction.md`](./presence_desktop_interaction.md)
  („Avatar ≠ Assistentenlogik") abgesichert.
- **Keine neuen Core-/IPC-Semantiken.** Die Avatar-Appearance-Linie hat
  bis einschließlich Stage B keinen Core- oder IPC-Fußabdruck. Weder
  das Protokoll (`docs/api.md`) noch `core/src/` wissen von Themes,
  Identities oder Profilen.

Alles, was Stage C heute tatsächlich zur Verfügung hätte, liegt unter
`ui/scripts/avatar/`, rein in der UI, rein visuell, und rein kuratiert.

---

## 3. Was Stage C potentiell überhaupt meinen könnte

Dieser Abschnitt ist **Suchraum**, nicht Plan. Keine der genannten
Richtungen ist beschlossen, empfohlen oder priorisiert. Sie dienen nur
dazu, den Begriff „Stage C" im Team begrifflich einzugrenzen, damit
spätere Diskussionen nicht bei Null anfangen.

Denkbare Bedeutungen, sortiert nach grob ansteigender Öffnung der
Vertrauensoberfläche:

- **Mehr kuratierte prozedurale Templates.** Weitere fest im Repo
  gepflegte Identities nach Stage-B-Muster (weitere Köpfe, abstrakte
  Formen, Variationen). Kein neues Dateiformat, kein neuer Ladepfad,
  keine neue Vertrauensannahme — der Unterschied zu Stage B wäre nur
  quantitativ. Für diesen Pfad braucht es eigentlich keine eigene
  „Stage".
- **Kuratierte visuelle Varianten mit größerem Spielraum.** Z. B.
  zusätzliche Themes, zusätzliche Behavior-Profile, zusätzliche
  Ausdrucks-Achsen im Capability-Contract. Auch dies bleibt rein im
  kuratierten Raum und ist eher eine Erweiterung von Stage A/B als
  eine neue Stufe.
- **Repo-gepflegte statische Assets (z. B. PNG-Sprites, SVG).** Dateien,
  die von den Maintainern ausgewählt, geprüft und eingecheckt werden.
  Kein User-Upload, kein externer Download, aber ein echter
  Decoder-/Parser-Pfad und dadurch erstmals eine explizite
  Rendering-Surface für Nicht-Code-Inhalte.
- **Importierte 2D/3D-Darstellungen (statisch, kuratiert).** Kuratiert
  aus externen Quellen, aber mit klaren Formatgrenzen, klarer
  Lizenzherkunft und eigener Validierungsstufe. Unterscheidet sich von
  der vorigen Option durch die Menge an Decoder-/Rendering-Komplexität
  (Bild → Vektor → Mesh/Shader).
- **Deklarative lokale Avatar-Bundles mit Manifest.** Ein eng
  definiertes, rein deklaratives Bundle-Format (z. B. ein Manifest +
  validierte Assets + Capability-Deklaration im selben Vokabular wie
  Stage B), das **lokal** vom Nutzer abgelegt werden kann. Ausdrücklich
  **keine** Scripts, **keine** Shader-Eigenlogik, **keine** Remote-URLs.
- **Streng begrenzte deklarative Avatar-Bundles aus einer gepflegten
  Quelle.** Wie der vorige Punkt, aber nur aus einer vom Projekt
  verwalteten Quelle — z. B. ein signierter Satz im Repo / Release
  — statt aus beliebigen lokalen Ordnern.
- **Nutzerdefinierte Appearance-Pakete („User-supplied Avatare").** Die
  offenste in der Roadmap erwähnte Variante. Hier wären nicht nur die
  Assets, sondern auch die Capability-Deklaration nutzerseitig
  geliefert. Diese Variante hat die größte Vertrauens-, Parser- und
  UX-Oberfläche.

Wichtig: diese Liste ist **keine Treppe**, die man von oben nach unten
abläuft. Mehrere dieser Optionen können kombiniert oder ausgeschlossen
werden; einige sind explizite Nicht-Ziele (siehe §4).

Keine der Optionen ist an dieser Stelle zur Umsetzung ausgewählt. Eine
Auswahl geschieht erst am Ende der Forschungsphase, wenn Sicherheits-
und Teststrategie stehen (siehe §10).

---

## 4. Harte Nicht-Ziele

Diese Nicht-Ziele gelten für Stage C als Ganzes, unabhängig davon,
welche Option aus §3 am Ende gewählt würde. Sie sind bindend, solange
dieses Dokument gilt; eine Aufweichung ist nur durch eine neue,
dokumentierte Entscheidung möglich.

- **Kein freies Plugin-System.** Keine Ausführung externen Codes,
  keine dynamische Script-Bindung an den Avatar, keine Plugin-ABI, kein
  Hot-Reload von Avatar-Code.
- **Kein Avatar-Marktplatz.** Keine In-App-Browse/Install-UX, kein
  Third-Party-Repository, kein Pull aus externen Registries, keine
  automatische Update-Mechanik für Avatar-Inhalte.
- **Keine ausführbaren Fremdskripte.** Kein GDScript-, Lua-, JS-,
  WASM-, Shader-Hook oder sonstiger aktiver Code aus Avatar-Inhalten.
  Avatar-Inhalt ist **ausschließlich deklarativ** oder gar nicht.
- **Keine unkontrollierten User-Uploads.** Kein generischer
  „Datei hierher ziehen"-Pfad, keine transparente Akzeptanz beliebiger
  Binärformate, keine stille Übernahme beliebiger Dateitypen.
- **Keine Vermischung mit Assistant-Personality.** Avatar-Wechsel oder
  Appearance-Paket darf weder Prompts, Systemnachrichten,
  Antwortstil, noch Policy-/Approval-Semantik ändern. Die Trennung
  Appearance ≠ Behavior ≠ Personality ≠ Policy aus §8b.3 bleibt
  vollständig bindend.
- **Keine Auswirkung auf Permissions / Policy / Tool-Ausführung /
  ABrain.** Kein Avatar-Feature darf Approval-Flows verschieben,
  Trust-Stufen heben, Action-Kinds erlauben/verbieten oder ABrain-
  Entscheidungen beeinflussen.
- **Keine neue Core-/IPC-Semantik.** Stage C erzeugt in dieser Form
  weder neue Action-Events noch neue IPC-Nachrichten noch
  Protokollfelder in [`docs/api.md`](./api.md). Falls eine spätere
  Implementierung Core/IPC-Flächen berührt, ist das ein **separater,
  eigener Entscheidungspfad** — nicht Teil dieser Linie.
- **Keine implizite Desktop-Automation über Avatar-Dateien.** Avatar-
  Inhalte dürfen niemals Systemaktionen, Fenstermanipulation,
  Dateizugriffe, Prozessstarts, Audio-Ausgaben oder
  Approval-Auslösungen anstoßen, weder direkt noch über Umwege
  (Manifest-Felder, Trigger-Listen, Ereignis-Hooks).
- **Keine stillen Netzwerkzugriffe für Avatar-Inhalte.** Kein
  automatisches Laden aus dem Netz, kein „phone home", keine
  impliziten Font-/Asset-CDNs. Netzwerkzugriffe für Avatar-Inhalte sind
  in dieser Linie nicht vorgesehen.

Diese Liste beantwortet den häufigsten stillschweigenden Scope-Creep:
„Wenn wir schon Avatar-Pakete haben, können wir ja auch …". Die
Antwort ist hier explizit nein, und zwar vor der ersten Zeile Code.

---

## 5. Sicherheits- und Vertrauensmodell

Dieser Abschnitt ist der eigentliche Grund, warum Stage C nicht
beiläufig implementiert werden darf. Er beschreibt, welche
Vertrauensklassen überhaupt existieren könnten, welche Risiken damit
verbunden sind und in welcher Reihenfolge eine spätere Implementierung
sie adressieren müsste.

### 5.1 Vertrauensklassen

Aus Sicht der Codebasis lassen sich vier Klassen unterscheiden, mit
stark unterschiedlicher Vertrauensoberfläche:

1. **Prozedural kuratiert** (Stage B heute).
   Vollständig im Repo beschriebener Render-Code (`_draw()`), keine
   externen Daten, keine Decoder. Vertrauensoberfläche entspricht dem
   regulären Godot-UI-Code.
2. **Repo-gepflegte statische Assets.**
   Vom Projekt ausgewählte und eingecheckte Dateien (z. B. PNG, SVG),
   die über bekannte Decoder in die UI geladen werden. Vertrauen liegt
   auf der Kuratierung + dem Decoder-Pfad. Kein Nutzer-Input.
3. **Lokal importierte, streng validierte Bundles.**
   Vom Nutzer lokal platzierte Inhalte, die einen strengen Validator
   durchlaufen, bevor sie gerendert werden. Vertrauen liegt auf der
   Validator-Vollständigkeit und den Formatgrenzen.
4. **Offene Nutzerinhalte.**
   Beliebige externe Quellen, beliebige Formate, evtl. aus dem Netz
   oder per Share. Vertrauensoberfläche ist maximal. **Heute
   ausdrücklich nicht freigegeben.**

Stage C muss jederzeit wissen, in welcher dieser Klassen ein konkreter
Inhalt gerade verarbeitet wird — es darf keine stille Vermischung
geben („Datei im Nutzerordner, aber wir tun so, als wäre sie
kuratiert").

### 5.2 Risiken

Jede Stage-C-Richtung, die über Klasse 1 hinausgeht, eröffnet
mindestens folgende Risiken, die in der Entscheidung explizit adressiert
sein müssen:

- **Parser-/Decoder-Angriffsfläche.** Bild-, Vektor-, Mesh- oder
  Manifest-Parser können fehlerhafte Eingaben unterschiedlich gut
  tolerieren. Das Risiko steigt mit der Formatkomplexität. PNG-Decoder
  sind vergleichsweise bekannt; SVG-, Schrift-, 3D-Format-Parser sind
  es deutlich weniger.
- **Speicher-/GPU-/Crash-Risiken.** Texturgrößen, Atlas-Layouts und
  Shader-Komplexität können die UI reproduzierbar zum Absturz bringen,
  wenn sie nicht gegen Größen- und Ressourcengrenzen validiert werden.
- **Path traversal / ungeprüfte Dateizugriffe.** Sobald Avatar-Inhalte
  aus Pfaden geladen werden, die nicht hart im Repo stehen, muss der
  Pfadraum streng eingegrenzt sein (Bundle-Wurzel, keine relativen
  Ausbrüche, keine Symlinks nach außen).
- **Riesige Dateien / Dekompressionsbomben.** Gezippte Bundles, PNG-
  Bilder mit absurden Dimensionen, 3D-Meshes mit explodierender
  Polygonzahl — jede Formatklasse hat ihre eigene Bombenvariante. Ohne
  harte Limits ist das ein DoS-Risiko gegen die UI.
- **Problematische Shader / Material-Graphs / Skript-Hooks.** Jedes
  Format, das irgendeine Form aktiver Logik (Shader, Bindings,
  Eventhandler, Script-Eintrittspunkte) zulässt, bricht Nicht-Ziel §4
  („Keine ausführbaren Fremdskripte"). Solche Felder müssen vom
  Validator verworfen werden, nicht bloß ignoriert.
- **Lizenz-/Urheberrechtsrisiken.** Importierte Assets (Klasse 2, 3,
  4) tragen Lizenzpflichten. Das Projekt muss jederzeit beantworten
  können, unter welcher Lizenz ein mitgelieferter oder nachgeladener
  Avatar-Inhalt steht und wie die Herkunft nachweisbar ist.
- **Irreführende UX.** Ein Avatar, der Fähigkeiten suggeriert, die das
  System nicht hat (z. B. eine angebliche „Admin"-Persona, die mehr
  Rechte hätte als Smolit), verletzt eine fundamentale UX-Zusage.
  Appearance darf die wahrgenommene Systemrolle nicht verändern.

### 5.3 Grundsatz

**Visuelle Personalisierung ist Vertrauensoberfläche.**
Auch wenn Avatar-Inhalte rein visuell verarbeitet werden, ist ihr
Ladepfad ein Angriffsweg und ihr Erscheinungsbild ein UX-Signal über
die Systemrolle. Beides muss die Architektur respektieren — visuell zu
sein ist keine Erlaubnis, lose zu sein.

### 5.4 Sicherheits-Hierarchie

Stage-C-Entscheidungen sollen von innen nach außen wandern, nicht
umgekehrt:

1. **Prozedural kuratiert.** Maximal wenig Risiko, maximal klein; falls
   Stage C überhaupt einen Ausbau bringt, sollte dieser Pfad zuerst
   ausgeschöpft sein.
2. **Repo-gepflegte statische Assets.** Öffnet den ersten Decoder-Pfad;
   braucht Formatauswahl, Größenlimits, Decoder-Vertrauen, aber keinen
   Nutzer-Input-Pfad.
3. **Lokal importierte, streng validierte Bundles.** Öffnet erstmals
   Nutzer-Input als Datenquelle; braucht vollständigen Validator,
   Pfad-Sandbox, Format-Whitelist, Größengrenzen und deterministische
   Fallbacks.
4. **Offene Nutzerinhalte.** Ausdrücklich nicht im Scope dieses
   Dokuments; nur sinnvoll diskutierbar, nachdem Klassen 1–3 stabil
   sind.

---

## 6. Mögliche Architekturpfade für spätere Stage C

Vier Optionen werden hier nüchtern gegenübergestellt. Sie sind weder
exklusiv noch vollständig — es kann auch sein, dass ein späteres Team
eine Mischform wählt oder Stage C gar nicht umsetzt.

Bewertungskriterien pro Option:
Nutzen · Komplexität · Sicherheitsrisiko · Wartbarkeit · Einfluss auf
Godot-UI · Einfluss auf Doku/Testbarkeit · Empfehlung.

### Option C1 — Nur mehr kuratierte Templates

- **Nutzen.** Moderat. Mehr visuelle Vielfalt, ohne neue
  Vertrauensklasse zu öffnen.
- **Komplexität.** Gering. Bestehender `_draw`-Pfad +
  Capability-Contract reichen.
- **Sicherheitsrisiko.** Sehr gering. Gleiche Vertrauensoberfläche wie
  Stage B.
- **Wartbarkeit.** Hoch. Jedes neue Template ist begrenzter Godot-Code
  mit festen Eingangspunkten.
- **Einfluss auf Godot-UI.** Lokal in `ui/scripts/avatar/`. Keine neuen
  Scenes, kein neuer Lade-Pfad.
- **Einfluss auf Doku/Testbarkeit.** Gering. Erweiterung der
  bestehenden Smoketests (`avatar_identity_smoke.gd`,
  `avatar_template_capabilities_smoke.gd`).
- **Begründung.** Dies ist eigentlich keine „neue Stage", sondern eine
  quantitative Stage-B-Erweiterung. Wenn Stage C konservativ
  interpretiert wird, landet sie hier.

### Option C2 — Repo-gepflegte statische Asset-Bundles

- **Nutzen.** Höher als C1 bei visueller Qualität (Texturen, feinere
  Formen), allerdings auf Kosten eines Decoder-Pfads.
- **Komplexität.** Mittel. Format-Auswahl (z. B. PNG), Größenlimits,
  Lizenz-/Herkunftsspur, Import-Regeln.
- **Sicherheitsrisiko.** Niedrig bis mittel. Decoder-Pfad ist
  kuratiert; kein Nutzer-Input-Pfad, aber erstmals eine
  Rendering-Surface für Nicht-Code-Inhalte.
- **Wartbarkeit.** Mittel. Jede neue Datei verlangt Kuratierungs-
  Disziplin (Lizenz, Herkunft, Prüfung) — keine reine Code-Arbeit mehr.
- **Einfluss auf Godot-UI.** Spürbar: Asset-Loader, Caching, Fallback-
  Rendering wenn Datei fehlt/beschädigt.
- **Einfluss auf Doku/Testbarkeit.** Deutlich. Tests für fehlende
  Dateien, kaputte Dateien, falsche Formate, Größenlimits. Doku für
  Kuratierungs-Regeln.
- **Begründung.** Realistisch, wenn ein sichtbarer Qualitätsschub über
  C1 hinaus gewünscht wird. Ist ein echter Schritt in eine andere
  Vertrauensklasse, bleibt aber nutzerseitig unsichtbar (keine neue
  Eingabeflanke).

### Option C3 — Deklarative lokale Avatar-Bundles mit Manifest

- **Nutzen.** Potentiell hoch für Personalisierung; erlaubt erstmals
  echte Nutzer-seitige Auswahl jenseits der kuratierten Liste.
- **Komplexität.** Hoch. Manifest-Parser, Validator, Pfad-Sandbox,
  Versionsfeld, Kompatibilitätsmatrix, Fehler-UX.
- **Sicherheitsrisiko.** Mittel bis hoch. Nutzer-Input wird zum
  Datenpfad; jede Parser-/Validator-Lücke wird zur echten Oberfläche.
- **Wartbarkeit.** Aufwendig. Manifest-Format ist ein versionierter
  öffentlicher Vertrag, der nicht mehr stillschweigend gedreht werden
  kann.
- **Einfluss auf Godot-UI.** Groß. Neuer Ladepfad, neue UI-Darstellung
  („unsupported", „degraded", „fallback aktiv"), sichtbare
  Fehlermeldungen.
- **Einfluss auf Doku/Testbarkeit.** Groß. Manifest-Doku,
  Format-Referenz, Negativtests, Fuzz-Tests, Performance-Gates.
- **Begründung.** Nicht grundsätzlich ausgeschlossen, aber nur sinnvoll
  nach fertigem Sicherheitsmodell und Teststrategie. Ohne die Gates
  aus §7/§8 ist das Risiko der Öffnung dieser Oberfläche zu groß.

### Option C4 — Echte User-Imports (freie Inhalte)

- **Nutzen.** Maximal aus Nutzersicht, aber bricht mehrere Nicht-Ziele
  aus §4, sobald Inhalte aktive Logik, Remote-URLs oder beliebige
  Binärformate zulassen.
- **Komplexität.** Sehr hoch. Praktisch das gesamte Format- und
  Sicherheitsmodell aus C3 plus Authentifizierung, Signatur,
  Widerruf, UX gegen Supply-Chain-Risiken.
- **Sicherheitsrisiko.** Hoch. Deckungsfläche umfasst Parser, Shader,
  Lizenz, UX-Irreführung, evtl. Netzzugriffe.
- **Wartbarkeit.** Gering bis sehr aufwendig. Jedes freigegebene
  Format wird zu laufender Pflege.
- **Einfluss auf Godot-UI.** Sehr groß. Vollständige Import-/Verify-UX,
  Trust-Anzeigen, Abwürg-Pfade.
- **Einfluss auf Doku/Testbarkeit.** Sehr groß. Viele Flächen
  gleichzeitig.
- **Begründung.** Diese Option ist in dieser Linie **nicht empfohlen**.
  Sie kollidiert mit mehreren Nicht-Zielen aus §4 („keine
  ausführbaren Fremdskripte", „keine stillen Netzwerkzugriffe", „keine
  unkontrollierten User-Uploads") und ist nur hypothetisch aufgeführt,
  damit sie in Diskussionen ehrlich als „nicht freigegeben" markierbar
  bleibt — statt sie im Kopf weiter zu tragen.

### Zwischenfazit (ohne Wahl)

C1 ist aus heutiger Sicht deutlich günstiger als C4; C2 und C3
liegen dazwischen. Dieses Dokument empfiehlt **keine** Option als
Umsetzung. Wenn überhaupt, sollte ein späteres Team zuerst C1
ausschöpfen, dann C2 bewerten, und erst bei belastbarem
Sicherheitsmodell über C3 nachdenken. C4 bleibt ohne eigene, viel
größere Entscheidungsgrundlage außerhalb des Scopes.

---

## 7. Erforderliche Verträge, falls Stage C jemals implementiert wird

Dieser Abschnitt sammelt Verträge, die **vor** einer Stage-C-Umsetzung
stehen müssen — nicht gleichzeitig mit ihr. Jeder Punkt ist bewusst
allgemein formuliert; Feldnamen und konkrete Formate sind ausdrücklich
noch nicht festgelegt.

- **Manifest-basierter Capability-Contract.** Falls Inhalte über den
  prozeduralen Kern hinausgehen (Optionen C2–C3), muss jeder Inhalt
  einen expliziten, deklarativen Capability-Block tragen, der im selben
  Vokabular wie Stage B spricht (unterstützte States,
  State-Fallbacks, Ausdrucks-Achsen). Kein frei interpretierter
  Inhalt, kein „erkennen wir am Dateinamen".
- **Erlaubte State-Menge und Fallback-Pflichten.** Stage C muss die
  aktuelle State-Menge (§8b.5) respektieren. Jeder deklarierte State
  außerhalb der bekannten Menge wird ignoriert; jeder fehlende State
  fällt deterministisch auf `IDLE` zurück (bzw. eine dokumentierte
  Ersatzkette). Kein Inhalt darf die UI in einen undefinierten Zustand
  führen.
- **Ausdrucksachsen und Support-Level.** Ausdrucks-Achsen sind die aus
  Stage B etablierten fünf (`theme_tint`, `behavior_profile`,
  `state_pulse`, `wiggle`, `error_startle`), jeweils mit Levels `NONE
  / REDUCED / FULL`. Neue Achsen zu öffnen ist möglich, aber eine
  eigene Entscheidung — nicht Teil der Stage-C-Öffnung selbst.
- **Strikte Dateityp-Whitelist.** Jede Option, die Dateien akzeptiert
  (C2, C3), arbeitet mit einer explizit aufgezählten Whitelist; alle
  anderen Typen werden verworfen. Keine „wenn es sich laden lässt,
  nehmen wir es"-Logik.
- **Größen-/Auflösungs-/Speichergrenzen.** Harte obere Schranken für
  Dateigröße, Bilddimension, Meshkomplexität, Bundle-Gesamtumfang,
  Speicherverbrauch im geladenen Zustand. Überschreitung = Refusal,
  kein Best-Effort-Render.
- **Keine Scripts, keine Remote-URLs.** Manifeste dürfen weder aktive
  Logik tragen noch auf externe Ressourcen verweisen. Alle Ressourcen
  liegen lokal, sind im Bundle enthalten und werden nicht nachgeladen.
- **Deterministische Fallbacks auf Smolit.** Jeder Fehlerpfad (Parser-
  Fehler, Limit-Verletzung, fehlende Datei, ungültiges Manifest,
  ungültiger Capability-Block) landet bei Smolit Salamander, nicht bei
  einer der Alternativen. Fallback muss **laut** sein (sichtbar,
  geloggt) — nicht still.
- **Versionierung des Bundle-Formats.** Sobald Manifeste existieren,
  trägt jedes Manifest ein Versionsfeld. Inkompatible Versionen werden
  refused, nicht „so gut wie möglich geladen". Rückwärtskompatibilität
  ist kein Versprechen.
- **Klare Fehler-/Refusal-Semantik.** Jeder Refusal-Grund hat einen
  stabilen, UI-les­baren Code („unsupported format", „oversize",
  „invalid manifest", „capability mismatch", …) — genau ein Signal
  pro Grund, damit die UX nicht raten muss.
- **Sichtbare Kennzeichnung.** Zustände wie „unsupported",
  „degraded", „fallback active" werden in der UI erkennbar angezeigt.
  Kein stiller Downgrade, keine Fake-Vollständigkeit. Gleichzeitig gilt
  §9: die Kennzeichnung betrifft *nur* die Darstellung, nicht die
  wahrgenommene Systemrolle.

---

## 8. Test- und Verifikationsanforderungen für einen späteren Stage-C-Start

Bevor Stage C überhaupt mit Code beginnen darf, müssen die folgenden
Testflächen als Strategie stehen — nicht zwangsläufig implementiert,
aber entschieden und dokumentiert.

- **Parser-/Manifest-Smokes.** Positive und negative Fälle für jedes
  akzeptierte Format. Mindestens: leeres Manifest, gültiges Minimal-
  Manifest, überspezifiziertes Manifest, Manifest mit unbekannten
  Feldern (müssen ignoriert werden, nicht crashen).
- **Fuzz-/Negativtests.** Zufällig verstümmelte Eingaben auf allen
  akzeptierten Formaten. Ziel: kein Crash, kein Hängen, sauberer
  Refusal mit Fehlergrund.
- **Größenlimit-Tests.** Gezielt knapp über und knapp unter den
  Limits; Verhalten unter Überschreitung muss deterministisch sein.
- **Kaputte/fehlende Dateien.** Bundle-Wurzel existiert, Asset fehlt;
  Asset existiert, Manifest verweist anders; Symlink ins Nichts.
  Jeder Pfad hat einen definierten Refusal-Ausgang.
- **Capability-/Fallback-Tests.** Inhalte, die weniger States tragen
  als Smolit; Inhalte mit explizitem `state_fallback`; Inhalte mit
  absichtlich kaputter Capability-Deklaration. Nachweis, dass der
  Avatar-Controller nie auf einen nicht renderbaren State läuft.
- **Performance-/Memory-Gates.** Obergrenzen für Load-Zeit, Peak-
  Speicher, Draw-Calls pro Frame. Messbare Schwellenwerte, an denen
  ein Inhalt als „zu teuer" refused wird.
- **Lizenz-/Source-Herkunftsregeln für Demo-Assets.** Falls Demo-/
  Referenz-Bundles ausgeliefert werden: klare Lizenz- und
  Herkunftsdokumentation im Repo, nachvollziehbar pro Datei.
- **UI-Refusal-/Fallback-Sichtbarkeit.** Tests dafür, dass die UI
  Refusal und Fallback tatsächlich anzeigt — kein stillschweigender
  Smolit-Durchlauf, wenn ein Nutzer-Inhalt verworfen wurde.

Diese Teststrategie ist kein Mehraufwand, sondern Teil des Scopes
selbst. Ohne sie ist Stage C nicht freigabefähig.

---

## 9. Produkt-/UX-Grenzen

Diese Grenzen sind die UX-Seite der Sicherheitsentscheidung. Sie gelten
unabhängig von der gewählten Option aus §6.

- **Default Smolit Salamander bleibt erster-Klasse.** Der erste Start,
  der leere Zustand und jeder Fehlerpfad zeigen Smolit. Kein Avatar-
  Wechsel wirkt sich auf diesen Grundsatz aus.
- **Alternative Avatare sind additiv.** Sie erweitern die Auswahl;
  sie ersetzen den Default nicht und sind auch nicht „gleichberechtigt"
  im Sinne einer Marktplatz-Logik.
- **Gleiche Eingabe ⇒ gleiche Systemreaktion.** Dieselbe Nutzereingabe
  erzeugt dieselbe Assistant-Antwort und dieselben Aktionen,
  unabhängig vom gewählten Avatar. Diese Zusage ist ein UX-Vertrag,
  kein Implementierungsdetail.
- **Avatar darf keine Systemfähigkeiten vortäuschen.** Ein Avatar,
  dessen Erscheinung „mehr Rechte" oder „mehr Intelligenz" suggeriert,
  als das System tatsächlich hat, ist ein UX-Bug, unabhängig davon,
  wie schön er aussieht.
- **Nutzer darf nie glauben, Avatar-Wechsel ändere Assistant-Rechte
  oder Intelligenz.** Die UI kommuniziert aktiv, dass Appearance rein
  visuell ist — etwa durch konsistente Statusflächen, die
  assistant-seitige Fähigkeiten separat vom Avatar kommunizieren. Kein
  „Pro-Avatar mit Admin-Aura".

---

## 10. Entscheidungsvorlage / Exit-Kriterien

Dieser Abschnitt ist der einzige, der in einem späteren PR aktiv
konsultiert werden soll. Er definiert, wann das Team aus der
Forschungs-Stage C eine Implementierungs-Stage macht.

Stage C bleibt **research-gated**, solange auch nur eines der
folgenden Kriterien nicht erfüllt ist:

- **Sicherheitsmodell steht.** §5 ist in einer getrennten
  Entscheidungsrunde bestätigt worden; die gewählte Vertrauensklasse
  und die zugehörigen Parser-/Decoder-Risiken sind benannt und
  akzeptiert.
- **Formatgrenzen stehen.** Für die gewählte Option sind alle
  Größen-, Auflösungs-, Speicher- und Komplexitätsgrenzen aus §7
  konkret beziffert — nicht nur „es gibt Limits".
- **Teststrategie steht.** §8 ist in eine konkrete Testmatrix
  überführt. Jeder Punkt hat einen Eigentümer, ein erwartetes
  Fehlersignal und einen Refusal-Pfad.
- **Fallback-Regeln stehen.** Jeder Fehler hat einen definierten
  Ausgang; alle Ausgänge führen deterministisch entweder zu Smolit
  oder zu einer sichtbaren, klar benannten Degraded-Darstellung.
  Kein stilles Scheitern.
- **Scope ist auf eine kleine, sichere erste Unterstufe reduziert.**
  Stage C startet nicht mit der offensten Option (C4). Der
  Erststart ist bewusst eng (realistisch C1 oder C2), mit der
  expliziten Option, danach nicht weiterzugehen.
- **Dokumentation ist konsistent vorbereitet.** `ui_architecture.md`
  §8b, `presence_desktop_interaction.md` und `ROADMAP.md` Phase 4b
  sprechen dieselbe Sprache wie dieses Dokument; die Begriffe
  Appearance / Behavior / Personality / Policy bleiben getrennt;
  die Nicht-Ziele aus §4 sind in jedem der drei Dokumente auffindbar.
- **Kein Druck auf Core/IPC/ABrain.** Die gewählte Stage-C-Unterstufe
  erzwingt keine Änderung am Core, am IPC-Protokoll oder an ABrain.
  Sollte sie das doch tun, ist die erste Aufgabe, diesen Druck zu
  entfernen — nicht, ihn durch Avatar-Arbeit in Core/ABrain
  nachzuziehen.

Erst wenn alle diese Kriterien erfüllt sind, ist ein Übergang von
„Stage C Research" in „Stage C Implementation" legitim. Bis dahin ist
Stage C ausdrücklich **nicht begonnen**, unabhängig davon, wie oft
der Begriff in Tickets, Prototypen oder Gesprächen auftaucht.
