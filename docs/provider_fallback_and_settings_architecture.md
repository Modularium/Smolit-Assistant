# Provider Fallback & Settings Architecture

Status: **Architektur- und Designdokument.**
Kein Implementierungsplan, kein Produktversprechen, kein genehmigter
Scope. Dieses Dokument legt nur den Rahmen fest, unter dem spätere,
jeweils eigene PRs Text-/STT-/TTS-Provider-Fallbacks und ein
Settings-UI einführen dürfen. Keine Provider-SDK-Integration, keine
Secrets-Implementierung, keine UI-Settings-Scene, keine IPC-Änderung
sind Teil dieses PR.

Crosslinks:
[`docs/VISION.md`](./VISION.md),
[`docs/ui_architecture.md`](./ui_architecture.md),
[`docs/api.md`](./api.md) §3–§5,
[`ROADMAP.md`](../ROADMAP.md).

---

## 1. Ziel und Problem

Smolit-Assistant verwendet im heutigen Ist-Zustand **ABrain als
einzigen** Text-/Reasoning-Provider (CLI-Adapter, siehe
[`docs/api.md` §3](./api.md)). STT und TTS laufen bereits über
konfigurierbare externe Kommandos
([`docs/api.md` §4](./api.md)). Ein Lauf ohne ABrain-Kommando
scheitert heute hart beim ersten Reasoning-Request.

Diese Kopplung blockiert zwei legitime Nutzungen, die aus der
Produktperspektive erhalten bleiben müssen:

- **Standalone-Betrieb außerhalb des Smolitux-/ABrain-Ökosystems.**
  Nutzer, die Smolit-Assistant testen, evaluieren oder dauerhaft
  einsetzen, ohne ABrain vor Ort zu haben, brauchen einen
  alternativen Reasoning-Pfad (z. B. lokales Modell per CLI/HTTP
  oder ein externes Cloud-API).
- **Degraded-Betrieb bei ABrain-Ausfall.** Ist ABrain im Moment
  nicht erreichbar (Prozess fehlt, Timeout, zerbrochene Version),
  sollte die UI das ehrlich anzeigen können und — sofern der Nutzer
  das aktiv erlaubt hat — auf einen Fallback-Provider umleiten, statt
  nur Fehler zu emittieren.

Ausdrückliche **Nicht-Ziele dieses Zielbilds**:

- Kein Security-Bypass. Die Approval-/Trust-/Policy-Linien
  (Approval-Flow §2.7, Interaction-Policy §2.6 der API-Doku) bleiben
  ausschließlich an bestehenden Mechanismen verankert. Ein
  Provider-Wechsel verändert **nie** eine Berechtigung.
- Keine Aufweichung der UI-Wahrheit. Ob ABrain oder ein Fallback
  antwortet, ist für Action-Execution, Approvals, Desktop-Interaction
  irrelevant — die UI darf aus dem Provider keine Autorität ableiten.
- Kein heimlicher Cloud-Zwang. Der Default-Lauf darf niemals
  stillschweigend auf einen Cloud-Provider umleiten. Cloud-Nutzung
  ist **opt-in, sichtbar, konfigurierbar**.

---

## 2. Begriffe

Diese Begriffe sind Arbeitsdefinition für die folgenden Abschnitte.
Keine Zusage, dass jeder Begriff später als eigener Modul-Name im
Code auftauchen muss.

- **Reasoning / Text Provider.** Komponente, die einen Nutzer-Input
  (Text, optional Kontext) entgegennimmt und einen Antworttext
  produziert. ABrain ist heute der einzige Text-Provider.
- **STT Provider.** Komponente, die einen Audio-Eingabe-Schritt
  triggert und den erkannten Text liefert. Heute: ein externer
  `SMOLIT_STT_CMD`, wenn gesetzt.
- **TTS Provider.** Komponente, die einen gegebenen Text hörbar
  macht. Heute: ein externer `SMOLIT_TTS_CMD`, wenn gesetzt.
- **Local Provider.** Provider, der vollständig auf dem Host des
  Assistenten läuft (Prozess, lokales Kommando, lokaler HTTP-Daemon
  auf Loopback). Keine externe Netzwerkverbindung zum Betrieb.
- **Cloud Provider.** Provider, der über das öffentliche Netz mit
  einem externen Dienst spricht. Braucht immer sichtbare Nutzer-
  Einwilligung (siehe §7).
- **Provider Fallback.** Eine explizit konfigurierte Reihenfolge von
  Providern, die der Core nacheinander probiert, wenn der primäre
  Provider nicht verfügbar ist oder fehlschlägt. Fallback ist nie
  implizit — er wird aus der Konfiguration aufgelöst, nicht aus
  heuristischen Annahmen.
- **Provider Transparency.** Vertragszusage an den Nutzer: Zu jedem
  Zeitpunkt ist in der UI erkennbar, welcher Provider konfiguriert
  ist, welcher aktuell antwortet, und ob ein Cloud-Pfad beteiligt
  ist.

---

## 3. Architekturprinzipien

Die folgenden Prinzipien sind bindende Leitplanken für jede spätere
Provider-/Settings-Arbeit. Sie ersetzen nicht die bestehenden
Architekturprinzipien in [`ROADMAP.md`](../ROADMAP.md) („Core-driven /
UI ohne Geschäftslogik / Adapter statt Parallel-Stacks / Additiv
erweitern"), sondern präzisieren sie für diesen Strang.

- **Provider-Achsen getrennt führen.** Text, STT und TTS haben
  eigene Provider-Reihen. Die Wahl des Text-Providers darf den
  STT-/TTS-Pfad nicht implizit mitverändern und umgekehrt.
- **UI bleibt Renderer und Settings-Client.** Die UI zeigt den
  aktuellen Provider-Zustand an und nimmt Nutzereingaben für das
  Settings-UI entgegen. Sie trifft keine Provider-Entscheidungen,
  fällt nicht selbst zurück, kennt keine Provider-Endpunkte und
  hält keine Secrets.
- **Core bleibt Source of Truth.** Der Rust-Core löst die aktive
  Provider-Reihenfolge auf, ruft den nächsten verfügbaren Provider
  und emittiert das Ergebnis über bestehende Events
  (`thinking` / `response` / `error` / `status`). Der Core bleibt
  einziger Provider-Orchestrator.
- **Providerwahl ≠ Policywahl.** Keine neue Permission, keine neue
  Approval-Regel, keine neue Interaction-Policy ergibt sich aus der
  Wahl eines Providers. Ein Cloud-Text-Provider bekommt weder mehr
  noch weniger Desktop-Rechte als ABrain.
- **Fallback ist explizit, nicht still.** Der Core darf nur auf
  einen Fallback-Provider wechseln, wenn dieser in der Konfiguration
  **aktiv** als Fallback eingetragen ist. Ein Wechsel wird in der UI
  sichtbar (siehe §7 / §8). Kein Auto-Discover, kein „wir probieren
  einfach mal den nächsten aus der Liste".
- **Cloud-Nutzung braucht sichtbare Nutzersignale.** Ein Cloud-
  Provider ist nie Default. Ein Cloud-Pfad fordert mindestens
  — eine aktive Konfiguration durch den Nutzer, und
  — eine dauerhaft erkennbare UI-Kennzeichnung beim Einsatz
    (Chip / Icon / Statusfeld, siehe §8).
- **Additiv erweitern.** Das IPC-Protokoll
  ([`docs/api.md`](./api.md)) wächst nur über additive Felder und
  neue `type`-Werte, nicht über Breaking Changes. Provider-
  Identifikation läuft perspektivisch über ein zusätzliches Feld
  (z. B. in `StatusPayload`), **nicht** über neue Nachrichtenfamilien.
- **Graceful failure vor hartem Abbruch.** Fehlt jeder konfigurierte
  Provider in einer Achse, meldet der Core das als Zustand
  (`unavailable`), ohne abzustürzen — genau wie heute STT/TTS ohne
  Command (§4 der API-Doku).
- **Keine Stage-C-/Avatar-Kopplung.** Provider-Strang und Avatar-
  Linie (siehe
  [`docs/avatar_stage_c_research.md`](./avatar_stage_c_research.md))
  sind architektonisch getrennt. Ein Provider-Wechsel ändert den
  Avatar-Look nicht; eine Identity-Wahl ändert den Provider nicht.

---

## 4. Mögliche Providerklassen

Diese Liste ist **Designraum**, keine Umsetzungszusage. Jede Klasse
ist einzeln entscheid- und ablehnbar.

### 4.1 Reasoning / Text

- **ABrain (Ist-Zustand).** CLI-Adapter über `ABRAIN_CMD`
  (`docs/api.md` §3). Bleibt Default und Referenz-Provider, solange
  er konfiguriert ist. Kein Cloud-Pfad.
- **Lokaler CLI-/Command-Provider.** Beliebiges externes Kommando,
  das einen Prompt auf stdin / CLI-Argument entgegennimmt und die
  Antwort auf stdout liefert. Symmetrisch zum ABrain-CLI-Adapter,
  mit eigenem `*_CMD`-Template. Kein SDK, keine Bibliotheksabhängigkeit.
- **Lokaler HTTP-Provider.** Ein auf `127.0.0.1` lauschender Dienst
  (z. B. `llama.cpp`-Server, lokaler vLLM, Ollama). Der Core spricht
  JSON/HTTP; der Dienst läuft vollständig auf dem Host.
  Netzwerkzugriffe nur auf Loopback.
- **`llamafile_local` (architektonisch vorbereitet, Runtime folgt).**
  Konkreter kuratierter Unterfall des lokalen HTTP-Providers: ein auf
  dem Host laufendes **llamafile** (Single-Binary-LLM), das lazy
  gestartet und nach einem konfigurierten Idle-Timeout wieder
  beendet werden kann. Dieser Kind existiert seit diesem PR als
  Provider-Variante im Core-Resolver (`TextProviderImpl::LlamafileLocal`)
  mit vollständigem Config- und Lifecycle-Modell (siehe §4.1a). Die
  eigentliche Prozess- und HTTP-Orchestrierung ist **noch nicht**
  implementiert; `run()`-Aufrufe liefern deterministische
  Refusal-Klassen (`disabled` / `not_configured` / `not_implemented`),
  die der Resolver in `text_provider_last_error` spiegelt. ABrain
  bleibt Default und wird nicht berührt.
- **Cloud-Provider.** Externer Reasoning-Dienst über das öffentliche
  Netz (HTTPS). Muss den Secret-Regeln aus §7 genügen und wird in
  der UI als `cloud` gekennzeichnet.

### 4.1a `llamafile_local` — Config- und Lifecycle-Modell

Architektonisch vorbereitet seit dem Llamafile-Prep-PR. Der Provider
ist im Core-Resolver als eigener Kind geführt und **kein Sonderfall
von ABrain** — er hat eigene Config, eigenen Lifecycle und eigenen
Fehlerpfad.

**Konfiguration** (`config.rs::LlamafileConfig`, Env-basiert):

- `SMOLIT_LLAMAFILE_ENABLED` (bool, Default `false`) — harter Master-
  Schalter. Ohne diesen Flag bleibt der Provider auf `Disabled`,
  unabhängig davon, ob `llamafile_local` in der Provider-Chain steht.
- `SMOLIT_LLAMAFILE_PATH` (optionaler String, Default leer) — Pfad zum
  llamafile-Binary. Ohne Pfad: `NotConfigured`.
- `SMOLIT_LLAMAFILE_MODE` (String, Whitelist `on_demand` / `standby`,
  Default `on_demand`) — spätere Prozess-Strategie. Wird gelesen und
  in die Fehlermeldung gereicht, aber noch nicht ausgeführt.
- `SMOLIT_LLAMAFILE_IDLE_TIMEOUT_SECONDS` (u64, Default `300`) —
  Idle-Timeout für den `on_demand`-Modus. Heute gelesen, noch nicht
  ausgeführt.

Unbekannte Mode-Werte fallen beim Parsing still auf den Default
zurück; keine Freiform-Werte werden akzeptiert.

**Lifecycle** (`providers::text::LlamafileLifecycle`): ein kleines
Enum-Vokabular, das **heute nur die ersten drei Zustände produziert**
und den Rest als Scaffolding für die Runtime-Stufe reserviert.

| Zustand (heute erreichbar?) | Bedeutung                                                                                                                                                                                          |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `disabled` (ja)             | Feature-Flag aus. Provider inert, `run()` → Refusal mit Klasse `disabled`.                                                                                                                         |
| `not_configured` (ja)       | Enabled, aber Pfad leer. `run()` → Refusal mit Klasse `not_configured`.                                                                                                                            |
| `configured` (ja)           | Enabled + Pfad gesetzt. `run()` → Refusal mit Klasse `not_implemented` (Mode und Idle-Timeout werden im Fehlertext mitgeführt).                                                                    |
| `starting` / `ready` / `busy` / `failed` / `stopped` (nein) | Scaffolding für den Runtime-PR. Die Tag-Strings sind per Test eingefroren (`llamafile_lifecycle_tag_strings_are_stable`), damit spätere Runtime-Übergänge kein Enum-Umbau erfordern. |

**Resolver-Integration.** `llamafile_local` darf heute in Chains wie
`abrain,llamafile_local` oder `llamafile_local,abrain` stehen. Der
Resolver instanziiert den Stub **immer**, auch wenn er disabled /
nicht konfiguriert ist — das macht Fehlerklasse und Fallback-Pfad
(`availability=fallback_active`) auch in der Vorbereitungsstufe
überprüfbar. Kein stiller Drop, keine Auto-Discovery, kein implizites
Enablen.

**Nicht Teil des Prep-PRs:** Prozess-Spawn, HTTP-Client,
Modell-Download, Binary-Bundling, Secret-Handling, Settings-UI.
Diese sind für den **Runtime-PR** reserviert, der die Kriterien aus
§7 und die zugehörigen Tests mitbringt.

### 4.2 STT

- **Lokaler Command-Provider (Ist-Zustand).** `SMOLIT_STT_CMD` —
  beliebiges Kommando (z. B. `whisper.cpp`, `vosk`, eigenes Skript).
- **Lokaler HTTP-Provider.** Loopback-Dienst mit Audio-Endpoint.
  Gleiche Regeln wie beim Text-Provider.
- **Cloud-Provider.** Externe Erkennung; dieselbe Kennzeichnungs-
  pflicht wie beim Text-Provider.

### 4.3 TTS

- **Lokaler Command-Provider (Ist-Zustand).** `SMOLIT_TTS_CMD` —
  z. B. `piper`, `kokoro`, eigenes Skript.
- **Lokaler HTTP-Provider.** Analog.
- **Cloud-Provider.** Analog; zusätzlich beachten, dass TTS-Texte
  potenziell sensible Nutzerinhalte enthalten und die Cloud-
  Kennzeichnung entsprechend sichtbar sein muss.

Die drei Achsen werden **nie** verschränkt: ein Cloud-Text-Provider
zieht keinen Cloud-STT/TTS-Provider nach sich.

---

## 5. Fallback-Modell

Das folgende Modell ist **Beispiel**, keine endgültige
Konfigurationszusage. Es soll zeigen, wie Fallback-Ketten aussehen
könnten, damit spätere PRs denselben Denkrahmen verwenden.

### 5.1 Text-Reasoning (Beispiel)

```text
1. ABrain (local CLI)       ← Default, wenn vorhanden
2. Local Command / HTTP     ← Opt-in Fallback
3. Cloud Provider           ← Opt-in Fallback, opt-in Cloud
4. fail                     ← ehrlicher Fehler, kein Silent Fail
```

### 5.2 STT (Beispiel)

```text
1. Local Command / HTTP     ← Default, wenn konfiguriert
2. Cloud Provider           ← Opt-in Fallback, opt-in Cloud
3. fail                     ← `unavailable` statt fauler Notwert
```

### 5.3 TTS (Beispiel)

```text
1. Local Command / HTTP     ← Default, wenn konfiguriert
2. Cloud Provider           ← Opt-in Fallback, opt-in Cloud
3. silent / error           ← bewusst entschieden, keine Zwangs-Sprach-
                              ausgabe
```

### 5.4 Regeln für jeden Fallback-Übergang

- **Explizit konfiguriert.** Nur Provider aus der Kette werden
  überhaupt probiert.
- **Sichtbar.** Jeder Übergang erzeugt ein UI-Signal (Chip / Status-
  Zeile / Log-Eintrag, siehe §8).
- **Begrenzt.** Jede Kette hat eine feste Maximal-Länge; kein
  endloses Weiterprobieren.
- **Kein Blending.** Der Core nutzt pro Request **genau einen**
  Provider — keine verteilte Antwort aus mehreren Quellen.
- **Kein stilles Fehlersammeln.** Der letzte Fehler der Kette wird
  als `error`-Event mit Provider-Kennzeichnung weitergereicht, damit
  Debugging nicht erraten muss, welcher Provider gescheitert ist.

---

## 6. Settings-Scope

Das spätere Settings-UI ist **nicht Teil dieses PR**. Dieser
Abschnitt legt nur fest, welchen Scope eine solche UI hätte, damit
sie klein genug bleibt und nicht zum Universal-Konfigurationsdialog
auswuchert.

Erreichbar soll sie aus dem Expanded-Window-Modus sein (siehe
[`docs/ui_architecture.md`](./ui_architecture.md)), also **nicht**
aus dem Docked-Icon — Settings sind eine aktive Handlung, keine
Ablenkung während laufender Arbeit.

Vorgesehene Bereiche (als Liste, nicht als Layoutvorgabe):

- **General.** Spracheinstellungen, Logging-Level (soweit bereits im
  Config exponiert), „About Smolit"-Info. Keine Provider-Themen.
- **Presence / UI.** Presence-Mode, Visual Action Mode (§8.5 der
  UI-Arch-Doku), Avatar-Appearance-Basis (Theme/Profile/Intensity,
  bereits vorhanden via Dev-Steuerung). Kein Identity-Importpfad.
- **Text Provider.** Aktiver Provider, Reihenfolge, lokale
  Kommandos/Endpoints, Test-Button („is this provider reachable?").
  Cloud-Slots nur bei explizit aktivierter Cloud-Sektion.
- **STT Provider.** Dasselbe Schema wie Text.
- **TTS Provider.** Dasselbe Schema wie Text.
- **Privacy / Cloud / Data handling.** Cloud-Opt-in pro Achse,
  sichtbare Aufstellung der aktiven Cloud-Pfade, Hinweis auf
  Netzzugriff, Offline-Only-Schalter (siehe §7). Hier wohnt die
  Einwilligung — nirgendwo sonst.
- **Connection / Status.** Read-only-Ansicht auf den aktuellen
  Provider-Zustand pro Achse (aktiv konfiguriert vs. aktuell genutzt,
  `unavailable` / `degraded` / `fallback active`, siehe §8).

Explizit **nicht Teil** des Settings-Scopes:

- Keine Stage-C-/Avatar-Import-Oberfläche.
- Keine Action-/Approval-/Policy-Konfiguration (die bleibt an
  Core-Policy, siehe `docs/api.md` §2.6 / §2.7).
- Keine Workflow-Authoring-UX.
- Keine Plugin- / Marketplace-Verwaltung.
- Keine Update-/Release-Management-Steuerung.

---

## 7. Transparenz- und Sicherheitsgrenzen

Dieser Abschnitt beschreibt die harten Regeln, die jede
Provider-Implementierung einhalten muss. Ein späterer PR darf sie
nicht implizit lockern — eine Aufweichung ist nur durch eine
dokumentierte Entscheidung in diesem Dokument möglich.

- **Kein stiller Cloud-Fallback.** Ein Cloud-Provider wird niemals
  ausgeführt, wenn er nicht aktiv konfiguriert und Cloud-opt-in
  gegeben ist. Selbst bei vollständigem Ausfall aller lokalen
  Provider bleibt der Core bei `unavailable`, wenn Cloud nicht
  freigegeben ist.
- **Externe Provider klar sichtbar.** In der UI ist jederzeit
  erkennbar, ob der aktive Provider lokal oder Cloud ist. Mindestens:
  Chip / Badge in einer dafür vorgesehenen Statuszone (siehe §8).
  Keine versteckte Umleitung, keine uneindeutigen Icons.
- **Keine Secret-Leaks in Logs/UI.** API-Schlüssel, Tokens und
  URLs, die einen Schlüssel als Query-Parameter enthalten, dürfen
  **nicht** in Log-Ausgaben, Event-Payloads, `StatusPayload` oder
  UI-Feldern auftauchen. Darstellung nur als maskierter Platzhalter
  (`•••• last4`) oder gar nicht. Der konkrete Secrets-Store ist
  eigenes PR-Thema; dieses Dokument legt nur die Grenze fest.
- **Lokale Provider bevorzugbar.** Die Fallback-Reihenfolge bevorzugt
  lokale Provider vor Cloud-Providern — sowohl in den Beispielen in
  §5 als auch als Default-Vorschlag für spätere Settings-Präsets.
- **Offline-/Local-only-Modus denkbar.** Eine zukünftige globale
  Einstellung („disable all cloud providers") ist ausdrücklich
  vorgesehen, aber noch nicht festgelegt. Sie würde jeden Cloud-Pfad
  hart sperren, unabhängig davon, wie die einzelnen Provider-Ketten
  konfiguriert sind.
- **Providerwechsel ändert keine Berechtigungen/Policies.** Aus §3
  erneut, weil es der kritischste Punkt ist: ein anderer Provider
  bekommt dieselben Action-Execution-Rechte wie der vorherige,
  nicht mehr, nicht weniger. Keine Policy-Upgrade-Kopplung an
  Provider.
- **Request-Inhalte sind Nutzerinhalte.** Sobald ein Request an einen
  Cloud-Provider gesendet wird, verlassen Nutzerinhalte das Gerät.
  Die UI muss das vor der ersten Aktivierung einer Cloud-Achse
  benennen; ein späterer PR implementiert diesen Einwilligungs-Flow.

---

## 8. Status-/Health-Modell

Spätere PRs dürfen den Core erweitern, um pro Provider-Achse eine
strukturierte Statussicht zu liefern. Dieses Dokument legt nur die
Felder fest, die sinnvoll und ausreichend wären — nicht den
Serialisierungsweg.

Pro Achse (Text / STT / TTS) sollen später mindestens verfügbar
sein:

- **`configured_provider`** — Name des aktuell primär konfigurierten
  Providers (z. B. `abrain`, `local_cmd`, `cloud:acme`).
- **`active_provider`** — Name des Providers, der den letzten
  Request tatsächlich beantwortet hat. Kann vom primären abweichen,
  wenn ein Fallback gegriffen hat.
- **`availability`** — einer aus `available` / `unavailable` /
  `degraded` / `fallback_active`. `degraded` bedeutet „der Provider
  antwortet, aber mit erhöhten Latenzen oder partiellen Fehlern";
  `fallback_active` bedeutet „primärer Provider nicht nutzbar,
  aktuell antwortet ein Fallback".
- **`last_error`** — kurzer maschinenlesbarer Fehlergrund
  (`timeout` / `process_missing` / `disconnected` / `auth_failed` /
  `rate_limited` / `unknown`). Kein Stacktrace, keine Roh-Response-
  Inhalte, keine Secrets.
- **`cloud`** — boolesch, ob der aktiv genutzte Provider eine
  Cloud-Komponente hat. Ausgangspunkt für die UI-Cloud-Kennzeichnung
  aus §7.

Transporttechnisch bietet sich an, diese Felder additiv in eine
erweiterte `StatusPayload`-Unterstruktur (siehe
[`docs/api.md` §2.3](./api.md)) zu stecken — ohne neue
Nachrichtenfamilie. Die genaue Form ist Teil eines späteren
Protokoll-PRs, nicht dieses Dokuments.

---

## 9. Vorschlag für PR-Reihenfolge

Die folgende Sequenz ist ein **Vorschlag**. Sie darf umgeordnet
werden, solange jeder Teil klein, eigenständig und rückfallsicher
bleibt.

- **PR 1 — Architektur + Doku (Ist).** Dokument `provider_fallback_and_settings_architecture.md`
  plus kleine Crosslinks. Kein Code, kein Protokoll-Eingriff.
- **PR 2 — Core Provider Resolver für Text (Ist).** Provider-
  Abstraktion hinter dem bisherigen ABrain-CLI-Pfad. Realisiert als
  `enum TextProviderImpl` (Enum-Dispatch, kuratiert, kein Plug-in-
  Register) in `core/src/providers/text.rs`. Heute produktiv
  implementiert: **ein** Kind — `abrain` (CLI, Signatur
  unverändert `{cmd} task run "<input>"`, siehe
  [`api.md` §3](./api.md)). Der `TextProviderResolver` liest eine
  geordnete Kette, probiert jeden Provider in Reihenfolge, liefert
  die erste erfolgreiche Antwort und hält einen kleinen
  Laufzeit-Status (`configured` / `active` / `availability` /
  `last_error` / `cloud`). Konfiguration in `config.rs` über den
  neuen `TextProviderConfig.chain`-Vektor; Env-Override
  `SMOLIT_TEXT_PROVIDER_CHAIN` (komma-separierte Kind-Namen; unbekannte
  Namen werden sichtbar verworfen; leere Kette → Default
  `["abrain"]`). `App::handle_text_query` geht ausschließlich
  durch den Resolver. Fehlerklassen werden in einen kurzen Tag
  (`timeout` / `process_missing` / `empty_response` /
  `exit_nonzero` / `invalid_response` / `unknown`) abgebildet und in
  `StatusPayload.text_provider_last_error` gespiegelt. Kein neuer
  Eventtyp, kein Policy-Eingriff, kein Cloud-Pfad. StatusPayload
  additiv um fünf `text_provider_*`-Felder erweitert (siehe
  [`api.md` §2.3](./api.md)).
- **PR 2a — Llamafile-Local-Vorbereitung (Ist, Variante A).**
  Architektonische Vorbereitung eines zweiten lokalen Text-Providers
  (`llamafile_local`), **ohne** die Runtime bereits zu liefern. Neue
  Enum-Variante `TextProviderImpl::LlamafileLocal`, neuer
  `LlamafileLocalProvider` mit Lifecycle-Modell
  (`LlamafileLifecycle` mit acht Zuständen — heute produziert:
  `disabled`, `not_configured`, `configured`; scaffolding:
  `starting` / `ready` / `busy` / `failed` / `stopped`). Config-Sicht
  über `LlamafileConfig` (Felder `enabled` / `path` / `mode` /
  `idle_timeout_seconds`, vier neue Env-Vars) und Provider-interne
  `LlamafileConfigView`. Der Stub liefert beim Aufruf
  **deterministische Refusal**-Klassen (`disabled` /
  `not_configured` / `not_implemented`), die der Fehlerklassifikator
  im Resolver sauber in `text_provider_last_error` spiegelt —
  keine Fake-Antworten, kein stilles Verschwinden aus der Kette,
  kein impliziter Cloud-Fallback. Resolver instanziiert den Stub
  auch bei `disabled` / `not_configured`, damit Fallback-Fluss
  `llamafile_local → abrain` (Availability `fallback_active`)
  überprüfbar ist. `SMOLIT_LLAMAFILE_MODE` nimmt nur die Whitelist
  `on_demand` / `standby`; unbekannte Werte fallen auf den Default.
  StatusPayload bleibt in diesem Prep-PR unverändert — Availability
  und Fehlerklasse des bestehenden Vokabulars reichen ehrlich. Die
  eigentliche Prozess- und HTTP-Orchestrierung ist **Runtime-PR**
  (siehe PR 2b).
- **PR 2b — Llamafile Runtime (noch offen).** Prozess-Spawn,
  HTTP-Dispatch, Idle-Timeout-Scheduling, `Starting` / `Ready` /
  `Busy` / `Failed` / `Stopped`-Transitions, Healthcheck, ggf.
  additive StatusPayload-Erweiterung um Lifecycle-Sichtbarkeit. Setzt
  PR 2a voraus, bekommt eigene Review-Checkliste (Prozess-Lifecycle,
  Crash-Semantik, Log-Filterung für Modell-Output).

Tests für PR 2 + 2a: 17 neue Resolver-/Lifecycle-Unit-Tests in
`core/src/providers/text.rs`, 7 Config-Tests in `config.rs`, 3
IPC-Server-Tests. Gesamtsumme Core-Tests: 120 PASS.

- **PR 3 — Settings-Shell im UI.** Reine UI-Shell für ein
  Settings-Panel im Expanded-Window: Bereiche aus §6 als leere /
  read-only Kästen, erreichbar über einen neuen Dev-/Opt-in-Eintrag.
  Kein neues Settings-Event-Protokoll, keine Schreibaktionen in den
  Core. Erst Layout, dann Inhalte.
- **PR 4 — STT-/TTS-Provider-Settings + Status-Anzeige.** Read-only-
  Status-Felder (aktiv konfiguriert / aktuell genutzt / availability)
  für STT und TTS in der Settings-Shell. Setzt die additive
  `StatusPayload`-Erweiterung aus §8 voraus (separater Protokoll-
  Schritt).
- **PR 5 — Secrets-Handling + Verbindungsprüfung + Testaktionen.**
  Endpoint-/Credential-Eingabe für lokale HTTP- und — sofern dann
  beschlossen — Cloud-Provider. Maskierte Darstellung, Secret-Store
  hinter einer schmalen Abstraktion, Test-Button pro Provider
  („reachable? auth ok?"). Dies ist der PR mit der größten
  Sicherheitsoberfläche und bekommt daher eine eigene
  Review-Checkliste.

Zwischenprinzipien:

- Jeder PR baut die vorige Stufe **nur** aus, ändert sie nicht
  rückwirkend.
- Jeder PR liefert Tests oder eine ehrliche Smoke-Erweiterung für
  genau die neue Fläche.
- Cloud-Provider-Implementierungen sind **nicht vor PR 5** erlaubt;
  vorher existieren sie nur als Konfigurations-Platzhalter.

---

## 10. Nicht-Ziele

Diese Nicht-Ziele gelten für den gesamten Provider-/Settings-Strang,
bis sie in einem separaten Entscheidungsschritt ausdrücklich
aufgehoben werden.

- **Kein sofortiges Multi-Provider-Universum.** Der Zielzustand ist
  nicht „Smolit spricht mit zehn LLMs parallel", sondern „Smolit
  bleibt nutzbar, wenn ABrain fehlt".
- **Keine SDK-Sammlung.** Keine Bündelung von Anbieter-spezifischen
  Client-Bibliotheken. Falls ein Cloud-Provider integriert wird,
  geschieht das über schmale, im Repo sichtbare HTTP-Clients — kein
  Dependency-Wildwuchs.
- **Kein heimlicher Cloud-Zwang.** Wiederholt aus §7: ohne
  Nutzer-Einwilligung fließt kein Request ins Netz.
- **Keine Vermischung mit Avatar-/Stage-C-Themen.** Provider-Strang
  und Avatar-Appearance/Identity-Strang sind architektonisch
  getrennt (§3).
- **Kein neues Plugin-System.** Die Provider-Abstraktion ist eine
  **interne**, im Repo gepflegte Trait-/Enum-Schicht mit festen,
  kuratierten Implementierungen. Kein dynamisches Laden fremden
  Codes, keine Drittprozesse mit undefinierter Schnittstelle.
- **Keine neue Tool-/Execution-Policy.** Der Interaction-Layer
  (`docs/api.md` §2.6) und der Approval-Flow (§2.7) bleiben
  unverändert die einzigen Entscheidungsstellen für Desktop-
  Aktionen.
- **Keine IPC-Revolution.** Das Protokoll aus `docs/api.md` wächst
  nur über additive Felder und neue `type`-Werte. Breaking Changes
  sind ausgeschlossen.
- **Kein Settings-Universal-Panel.** Das Settings-UI bleibt auf die
  Bereiche aus §6 begrenzt. Keine Ad-hoc-Erweiterung für zukünftige,
  heute unklare Konfigurationsthemen.
