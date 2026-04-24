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
  Netzwerkzugriffe nur auf Loopback. **Seit PR 8** gibt es dafür den
  allgemeinen Provider-Kind `local_http` — siehe §4.1c.
- **`llamafile_local` (lokaler Runtime-Provider, Ist-Zustand).**
  Konkreter kuratierter Unterfall des lokalen HTTP-Providers: ein auf
  dem Host laufendes **llamafile** (Single-Binary-LLM), das lazy beim
  ersten Request gestartet und nach einem konfigurierbaren Idle-Timeout
  vom internen Watchdog wieder beendet wird. Seit PR 2b mit echter
  Prozess-Orchestrierung (Spawn über `tokio::process::Command` mit
  `kill_on_drop`, Readiness-Poll gegen `GET /health`, Completion-
  Dispatch gegen `POST /completion` über einen kleinen internen
  HTTP/1.1-Client — keine SDK-Abhängigkeit). Lifecycle-Transitions
  `Configured → Starting → Ready → Busy → Ready → Stopped → Starting …`
  werden real durchlaufen (siehe §4.1a). ABrain bleibt Default und
  wird nicht berührt.
- **Cloud-Provider.** Externer Reasoning-Dienst über das öffentliche
  Netz (HTTPS). Muss den Secret-Regeln aus §7 genügen und wird in
  der UI als `cloud` gekennzeichnet.

### 4.1a `llamafile_local` — Config- und Lifecycle-Modell

Seit PR 2b als echter lokaler Runtime-Provider implementiert. Der
Provider ist im Core-Resolver als eigener Kind geführt und **kein
Sonderfall von ABrain** — er hat eigene Config, eigenen Lifecycle und
eigenen Fehlerpfad.

**Konfiguration** (`config.rs::LlamafileConfig`, Env-basiert):

- `SMOLIT_LLAMAFILE_ENABLED` (bool, Default `false`) — harter Master-
  Schalter. Ohne diesen Flag bleibt der Provider auf `Disabled`,
  unabhängig davon, ob `llamafile_local` in der Provider-Chain steht.
- `SMOLIT_LLAMAFILE_PATH` (optionaler String, Default leer) — Pfad zum
  llamafile-Binary. Ohne Pfad: `NotConfigured`. Der Runtime-Pfad
  führt das Binary mit `--server --host 127.0.0.1 --port <port>
  --nobrowser` aus. Host ist fest auf Loopback (siehe §7); der Pfad
  wird **nicht** in Fehlertexte oder Status-Felder gespiegelt, um
  Pfad-Leaks in Logs zu vermeiden.
- `SMOLIT_LLAMAFILE_MODE` (String, Whitelist `on_demand` / `standby`,
  Default `on_demand`) — Prozess-Strategie. `on_demand` ist in PR 2b
  vollständig umgesetzt; `standby` wird gelesen, gespeichert und in
  einem `info!`-Log beim Spawn benannt, verhält sich aber heute
  identisch zu `on_demand`. Echter Standby-Unterschied (Prozess
  dauerhaft halten) bleibt einem späteren PR vorbehalten.
- `SMOLIT_LLAMAFILE_IDLE_TIMEOUT_SECONDS` (u64, Default `300`) —
  Idle-Timeout für den `on_demand`-Modus. Wird vom internen Watchdog
  real überwacht: nach dieser Zeit ohne neuen Request stoppt der
  Watchdog den Prozess und setzt den Lifecycle auf `Stopped`.
- `SMOLIT_LLAMAFILE_PORT` (u16, Default `8788`) — TCP-Port des lokalen
  Servers. Loopback-only. Well-Known-Ports (< 1024) werden beim Parsen
  abgelehnt und fallen auf den Default zurück, damit der Provider
  nicht versehentlich in privilegierte Bereiche ausweicht.
- `SMOLIT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS` (u64, Default `30`) —
  Zeitbudget zwischen Prozess-Spawn und `GET /health` 200 OK.
  Überschreitung → Lifecycle `Failed`, Klasse `startup_timeout`.
- `SMOLIT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS` (u64, Default `60`) —
  Zeitbudget pro Completion-Request. Überschreitung → Klasse
  `timeout` im `text_provider_last_error`.

Unbekannte Mode-Werte fallen beim Parsing still auf den Default
zurück; keine Freiform-Werte werden akzeptiert.

**Runtime-Pfad** (PR 2b):

1. `run()` prüft Lifecycle. `Disabled` / `NotConfigured` → sofortige
   Refusal mit entsprechender Klasse.
2. Wenn Lifecycle nicht `Disabled`/`NotConfigured` **und** kein Kind-
   Prozess aktiv, Spawn:
   - `Command::new(path)` mit `--server --host 127.0.0.1 --port <port>
     --nobrowser`, `stdin=null`, `stdout=null`, `stderr=piped`,
     `kill_on_drop(true)`. Letzteres ist die zentrale
     Sicherheitsleine: wird der Provider (oder der Resolver) gedroppt,
     stirbt der Prozess zuverlässig.
   - Lifecycle `Starting`.
3. Readiness-Poll (Intervall 250 ms) gegen `GET /health`, bis 200 OK
   ankommt oder `startup_timeout_seconds` erreicht sind. Bei Prozess-
   Exit während der Probe → Klasse `process_exit_early`.
   Bei Timeout → Klasse `startup_timeout`, Prozess gedroppt,
   Lifecycle `Failed`.
4. Lifecycle `Ready`. Request: Lifecycle `Busy`, `POST /completion`
   mit `{"prompt": ..., "n_predict": 256, "stream": false}`. Antwort-
   `content` wird getrimmt und zurückgegeben; leere Antworten →
   Klasse `empty_response`.
5. Bei Erfolg: Lifecycle zurück auf `Ready`, `last_used = now()`.
   Der Watchdog wird **einmalig** nach dem ersten Erfolg gestartet
   (siehe §4.1a Watchdog) und läuft, bis er den Prozess stoppt oder
   der Provider freigegeben wird.
6. Bei Fehler: Lifecycle `Failed`, Kind-Prozess gedroppt (kill), Fehler
   hochreichen. Der nächste `run()` versucht einen frischen Spawn —
   kein Dauerzustand `Failed`, damit ein Admin nach einer Fehlklick-
   Konfiguration nicht erst neu starten muss.

**Watchdog**: eigener `tokio::spawn`-Task, hält eine `Weak`-Referenz
auf den inneren Arc (verlängert die Lebenszeit des Providers nicht).
Check-Intervall = `max(100 ms, min(5 s, idle_timeout/2))`. Bei jedem
Tick: Wenn kein Prozess aktiv → Watchdog beendet sich. Wenn
`last_used.elapsed() ≥ idle_timeout` → Prozess wird gedroppt
(`kill_on_drop` schickt SIGKILL und reap't), Lifecycle auf `Stopped`
gesetzt. Single-Request-MVP: die Runtime-Mutex serialisiert Spawn,
Readiness und Completion — keine stillen Mehrfachinstanzen, keine
verschränkten Requests.

**Lifecycle** (`providers::text::LlamafileLifecycle`): alle acht
Zustände sind heute erreichbar:

| Zustand            | Bedeutung                                                                                                                                                      |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `disabled`         | Feature-Flag aus. Provider inert, `run()` → Refusal mit Klasse `disabled`.                                                                                     |
| `not_configured`   | Enabled, aber Pfad leer. `run()` → Refusal mit Klasse `not_configured`.                                                                                        |
| `configured`       | Enabled + Pfad gesetzt, Prozess noch nicht gestartet. Nächster `run()` triggert den Spawn.                                                                     |
| `starting`         | Prozess ist gespawnt, Readiness-Poll läuft. Übergang nach `Ready` (bei 200 OK auf `/health`) oder `Failed` (bei `startup_timeout` / `process_exit_early`).     |
| `ready`            | Prozess läuft und ist idle. Nächster `run()` nimmt ihn direkt als `Busy`.                                                                                      |
| `busy`             | Prozess bearbeitet gerade einen Request. Nach Antwort zurück auf `Ready`.                                                                                      |
| `failed`           | Letzter Start oder Request ist gescheitert, Prozess gedroppt. Nächster `run()` versucht einen frischen Spawn.                                                  |
| `stopped`          | Watchdog hat den Prozess nach `idle_timeout_seconds` beendet. Nächster `run()` spawnt neu.                                                                     |

**Resolver-Integration.** `llamafile_local` darf heute in Chains wie
`abrain,llamafile_local` oder `llamafile_local,abrain` stehen. Der
Resolver instanziiert den Provider **immer**, auch wenn er disabled /
nicht konfiguriert ist — das hält Fehlerklasse und Fallback-Pfad
(`availability=fallback_active`) konsistent überprüfbar. Kein stiller
Drop, keine Auto-Discovery, kein implizites Enablen.

**Fehlerklassen** (Tags in `text_provider_last_error`): `disabled`,
`not_configured`, `process_missing` (Spawn-Fehlschlag),
`process_exit_early` (Prozess stirbt während Readiness),
`startup_timeout`, `timeout` (HTTP-Lese-/Schreib-Timeout bzw.
Request-Timeout), `http_connect_failed`, `http_error` (non-200-Status),
`empty_response`, `invalid_response` (UTF-8 / JSON-Parse). Die Tags
sind absichtlich kurz und stabil; spätere UI-Arbeit kann sie 1:1
abbilden, ohne neue Nachrichtenfamilie einzuführen.

**Bewusst nicht Teil von PR 2b:**

- Kein Modell-Download, kein Repo-Bundling großer Artefakte — der
  Operator liefert das llamafile-Binary/-Modell selbst.
- Kein Streaming-Pfad (`stream: false` ist fest gesetzt).
- Keine GPU-/Thread-/Advanced-Tuning-Oberfläche.
- Kein echter `standby`-Modus; der Wert wird geparst und beim Spawn
  geloggt, die Runtime verhält sich identisch zu `on_demand`.
- Keine Exposition des Lifecycle-Feldes über IPC-StatusPayload. Das
  bestehende `text_provider_availability`/`text_provider_last_error`-
  Vokabular trägt die sichtbare Seite ehrlich; eine zusätzliche
  Lifecycle-Sichtbarkeit landet erst dann im Protokoll, wenn eine
  konkrete Settings-UI (PR 3/4) sie braucht.
- Keine Secrets-Oberfläche; llamafile läuft unprivilegiert und lokal.
- Kein Auto-Restart bei Crash; ein gestorbener Prozess wird bei
  nächsten `run()`-Aufruf neu gespawnt.

### 4.1c `local_http` — allgemeiner lokaler HTTP-Text-Provider (PR 8)

`local_http` ist der erste **allgemeine** externe Text-Provider
außerhalb von `abrain` und `llamafile_local`. Ziel: ein schmaler,
produktiver HTTP-Adapter gegen einen lokal laufenden, llama.cpp-
kompatiblen Completion-Server (vLLM, Ollama-kompatible
`/completion`-Route, eigene Dienste). Bewusst **kein**
pseudo-generischer LLM-Universaladapter — wer mehr will, bekommt
einen eigenen Provider-Kind.

**Konfiguration** (`config.rs::LocalHttpConfig`, Env-basiert):

- `SMOLIT_LOCAL_HTTP_ENABLED` (bool, Default `false`) — harter
  Master-Schalter.
- `SMOLIT_LOCAL_HTTP_ENDPOINT` (optionaler String, Default leer) —
  Ziel-URL, z. B. `http://127.0.0.1:8080/completion`. Muss mit
  `http://` beginnen; `https://` wird vom Provider explizit
  abgelehnt, weil PR 8 keine TLS-/Cert-/Trust-Infrastruktur
  mitbringt. Host-Teil darf beliebig sein; in der Praxis ist der
  Provider loopback-first gedacht (siehe §7).
- `SMOLIT_LOCAL_HTTP_REQUEST_TIMEOUT_SECONDS` (Default `60`) —
  Zeitbudget pro Completion-Request. `0` wird vom Schreibpfad
  abgelehnt.
- `SMOLIT_LOCAL_HTTP_PROMPT_FIELD` (Default `"prompt"`) — JSON-
  Feldname im Request-Body.
- `SMOLIT_LOCAL_HTTP_RESPONSE_FIELD` (Default `"content"`) — JSON-
  Feldname im Response-Body.

**Runtime-Pfad**:

- Genau ein `POST <path>`-Aufruf pro Request. Body:
  `{"<prompt_field>": "<input>", "stream": false}`. Response-Body
  wird als JSON geparst; `<response_field>` muss ein Text-Feld sein.
- Nutzt denselben internen HTTP/1.1-Helfer (`http_request`) wie der
  llamafile-Runtime-Pfad — keine neue Dependency, keine neue Secret-
  Oberfläche.
- Kein Streaming, kein Tool-/Schema-Mode, kein `messages`-Array, kein
  `system`-Prompt. Wer das braucht, schreibt einen eigenen Provider.
- Kein Auth-Header, keine API-Keys. Sensitive-Credentials-Pfad
  bleibt für einen späteren PR reserviert (siehe §7/§11).

**Fehlerklassen** (additiv in `text_provider_last_error`):
`disabled`, `not_configured`, `endpoint_scheme_unsupported`
(`https://` oder anderes Schema), `endpoint_unparseable`,
`http_connect_failed`, `http_error` (Non-200), `timeout`,
`empty_response`, `invalid_response`.

**Probe** (`settings_probe_local_http`): TCP-Connect auf den
geparsten `host:port` innerhalb eines kleinen Timeout-Fensters
(max. 30 s). **Kein** Completion-Request — die Probe spricht über
Erreichbarkeit, nicht über Qualität. Das Ergebnis trägt kuratierte
Klassen (`ok` / `not_in_chain` / `disabled` / `not_configured` /
`endpoint_scheme_unsupported` / `endpoint_unparseable` /
`http_connect_failed` / `timeout`).

**Leitplanken** (siehe Nicht-Ziele in §10):

- Kein TLS in dieser Stufe.
- Keine Streaming-Pipeline.
- Keine SDK-Sammlung; der Adapter bleibt ein schmaler HTTP-MVP.
- Kein Endpoint-Echo im StatusPayload, Probe-Response oder
  `error`-Envelope — analog zur Pfad-Disziplin des
  `llamafile_local`-Providers.
- `local_http` ist **kein** Unterfall von `llamafile_local` oder
  `abrain`; er steht als eigener, gleichrangiger Provider-Kind in
  der Chain.

### 4.2 STT

- **Lokaler Command-Provider (Ist-Zustand, PR 6).** `SMOLIT_STT_CMD`
  — beliebiges Kommando (z. B. `vosk`, eigenes Skript). Seit PR 6
  hinter einer kleinen Provider-Abstraktion
  ([`providers::stt`](../core/src/providers/stt.rs)) mit Resolver,
  Laufzeitstatus und Fehlerklassifikator — das bisherige Verhalten
  bleibt byte-kompatibel.
- **`whisper_cpp`-Kind (PR 27, Ist-Zustand).** Zweiter command-
  basierter Adapter unter einer eigenen Env-Variable
  `SMOLIT_STT_WHISPER_CPP_CMD`. Inhaltlich identischer Spawn-Vertrag
  wie das `command`-Kind (stdin-frei, stdout = erkannter Text,
  trim, empty → Fehler); die Trennung ist bewusst — so macht die
  Fallback-Kette `["whisper_cpp", "command"]` real Sinn (z. B.
  whisper.cpp als primärer Lokal-Pfad, ein einfacheres Fallback-
  Kommando auf `command`). **whisper.cpp selbst ist keine Build-
  Abhängigkeit und kein Download-Manager** — der Nutzer orchestriert
  Binary und Modell außerhalb des Cores; der Core ruft nur den
  konfigurierten Command auf. Env-only konfigurierbar; keine
  Persistenz und kein Runtime-Editor in der Settings-Shell.
- **Lokaler HTTP-Provider.** Loopback-Dienst mit Audio-Endpoint.
  Gleiche Regeln wie beim Text-Provider. **Noch nicht implementiert.**
- **Cloud-Provider.** Externe Erkennung; dieselbe Kennzeichnungs-
  pflicht wie beim Text-Provider. **Noch nicht implementiert.**

### 4.3 TTS

- **Lokaler Command-Provider (Ist-Zustand, PR 6).** `SMOLIT_TTS_CMD`
  — z. B. `piper`, `kokoro`, eigenes Skript. Seit PR 6 hinter einer
  kleinen Provider-Abstraktion
  ([`providers::tts`](../core/src/providers/tts.rs)) mit Resolver,
  Laufzeitstatus und Fehlerklassifikator (inkl. spezifischer Klasse
  `stdin_write_failed`).
- **Lokaler HTTP-Provider.** Analog. **Noch nicht implementiert.**
- **Cloud-Provider.** Analog; zusätzlich beachten, dass TTS-Texte
  potenziell sensible Nutzerinhalte enthalten und die Cloud-
  Kennzeichnung entsprechend sichtbar sein muss. **Noch nicht
  implementiert.**

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

### 8.1 Vertiefter Status-Readout (PR 4, Ist-Zustand)

Der in §8 skizzierte Rahmen ist für die **Text-Achse** mit PR 4
bereits produktiv — weiterhin streng additiv auf dem bestehenden
`StatusPayload` (siehe [`docs/api.md` §2.3](./api.md)), ohne neue
Eventfamilie und ohne Push-Kanal. `get_status` liefert den
kompletten Readout in einer Nachricht.

**Text-Achse (produktiv).**

- `text_provider_configured` / `text_provider_active` /
  `text_provider_availability` / `text_provider_last_error` /
  `text_provider_cloud` — unverändert aus PR 2.
- `text_provider_chain` — Geordnete Liste der produktiv
  instanziierten Provider-Kinds (Resolver-Sicht, nicht Roh-Config).
  Die UI rendert daraus die Fallback-Reihenfolge („abrain"
  vs. „llamafile_local → abrain").
- `llamafile_in_chain` — Boolean, `true` wenn der lokale Provider
  überhaupt Teil der aktuellen Kette ist. Entscheidet, ob die
  folgenden Lifecycle-Felder Semantik haben.
- `llamafile_enabled` / `llamafile_configured` — Config-Readout.
  Beide Booleans stehen auch außerhalb der Chain sinnvoll zur
  Verfügung, damit „aktiviert, aber nicht in der Kette" ehrlich
  sichtbar ist.
- `llamafile_lifecycle` — Lifecycle-Tag aus dem kuratierten
  Vokabular (`disabled` / `not_configured` / `configured` /
  `starting` / `ready` / `busy` / `failed` / `stopped`). Nur
  gesetzt, wenn `llamafile_in_chain=true`; sonst `null`.
- `llamafile_mode` — `on_demand` / `standby`. Nur gesetzt, wenn
  `llamafile_in_chain=true`.
- `llamafile_idle_timeout_seconds` — Watchdog-Fenster in Sekunden.
  Nur gesetzt, wenn `llamafile_in_chain=true`.

**STT-Achse (produktiv seit PR 6, zweites Kind seit PR 27).**
`stt_enabled` / `stt_available` bleiben als Legacy-Feature-Flags
erhalten. Ergänzt um fünf additive Felder strukturell analog zur
Text-Achse: `stt_provider_configured` / `stt_provider_active` /
`stt_provider_availability` / `stt_provider_last_error` /
`stt_provider_cloud`. Produktive Kinds:

- `command` — bestehender `SMOLIT_STT_CMD`-Pfad (PR 6).
- `whisper_cpp` — zweiter command-basierter Adapter unter
  `SMOLIT_STT_WHISPER_CPP_CMD` (PR 27). Env-only, keine
  Persistenz, keine Build-Abhängigkeit auf whisper.cpp.

Chain env-überschreibbar via `SMOLIT_STT_PROVIDER_CHAIN`. Default
bleibt `["command"]` — PR 27 ändert den Compile-Time-Default
nicht.

PR 27 ergänzt zwei additive StatusPayload-Booleans:

- `stt_whisper_cpp_in_chain` — Sichtbarkeits-Hebel für die UI.
- `stt_whisper_cpp_configured` — spiegelt, ob
  `SMOLIT_STT_WHISPER_CPP_CMD` einen nicht-leeren Wert trägt
  (analog zu `llamafile_configured` / `local_http_configured` /
  `cloud_http_configured`). Beide Felder sind Booleans; der
  Command-String selbst landet **nicht** im StatusPayload.

**TTS-Achse (produktiv seit PR 6).** `tts_enabled` / `tts_available`
/ `auto_speak` bleiben als Legacy-Feld-Tripel erhalten. Ergänzt um
fünf additive Felder analog STT (`tts_provider_configured` usw.).
Einziges Kind heute `command`; Chain env-überschreibbar via
`SMOLIT_TTS_PROVIDER_CHAIN`.

**Privacy-Rollup (UI-Projektion, kein Core-Feld).** Die Shell
kombiniert `text_provider_cloud`, `llamafile_in_chain` und
`llamafile_enabled` zu einer ehrlichen Lokal-/Cloud-Aussage pro
Achse (siehe [`docs/ui_architecture.md`](./ui_architecture.md) §8d).
Kein Core-Feld und keine neue Datenquelle — nur eine defensiv
zusammengesetzte Zeile.

**Bewusst nicht in PR 4 gelandet** (für PR 6 aufgelöst):

- ~~Keine STT-/TTS-Provider-Abstraktion und damit keine
  `stt_provider_*` / `tts_provider_*`-Felder~~ — gelandet in PR 6.
- Kein Cloud-Provider für Text (und damit kein neuer
  `text_provider_cloud=true`-Pfad).
- Kein `degraded`-Zustand in `text_provider_availability` — ohne
  Latenz-/Partial-Fehler-Signale im Core wäre das ein rein
  künstliches Feld.
- Kein zusätzlicher Lifecycle-Push (`provider_status_changed`-
  Event o. ä.). `get_status` reicht heute; ein Streaming-Kanal wäre
  Scope-Creep.

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
- **PR 2b — Llamafile Runtime (Ist).** Realer `on_demand`-Runtime für
  `llamafile_local`. Prozess-Spawn via `tokio::process::Command` mit
  `kill_on_drop(true)`, Readiness-Poll gegen `GET /health`, Completion
  via `POST /completion` mit `stream: false`. Kleiner eigener HTTP/1.1-
  Client auf `tokio::net::TcpStream` (keine SDK-Abhängigkeit). Watchdog-
  Task hält `Weak`-Referenz, schließt den Prozess nach
  `idle_timeout_seconds` Ruhe. Alle acht Lifecycle-Zustände werden
  real durchlaufen. Drei neue Env-Vars (`SMOLIT_LLAMAFILE_PORT`,
  `SMOLIT_LLAMAFILE_STARTUP_TIMEOUT_SECONDS`,
  `SMOLIT_LLAMAFILE_REQUEST_TIMEOUT_SECONDS`). Acht neue Fehler-
  klassen im Klassifikator (`process_missing`, `process_exit_early`,
  `startup_timeout`, `timeout`, `http_connect_failed`, `http_error`,
  `empty_response`, `invalid_response`). `standby`-Mode bleibt
  reserviert (verhält sich heute wie `on_demand`). IPC-StatusPayload-
  Surface unverändert — Lifecycle-Sichtbarkeit bleibt für PR 3/4
  offen, weil das bestehende `availability`/`last_error`-Vokabular
  den Failure-Pfad ehrlich trägt. Kein Modell-Download, kein Bundling,
  keine Secrets, keine Settings-UI.

Tests für PR 2 + 2a + 2b: 26 Resolver-/Lifecycle-/Runtime-Unit-Tests
in `core/src/providers/text.rs` (darunter drei Integrationstests
gegen einen lokalen Fake-HTTP-Server plus ein Shell-Skript als
`/bin/sleep`-Stand-in für den Spawn-Pfad), 7 Config-Tests in
`config.rs`, 3 IPC-Server-Tests. Gesamtsumme Core-Tests: 129 PASS.

- **PR 3 — Settings-Shell im UI (Ist).** Reine UI-Shell für ein
  Settings-Panel im Expanded-Window. Sieben Bereiche aus §6 als
  sichtbare, read-only Kästen in fester Reihenfolge: **General**,
  **Presence / UI**, **Text Provider**, **STT**, **TTS**,
  **Privacy / Cloud / Data handling**, **Connection / Status**.
  Erreichbar über einen sichtbaren `⚙ Settings`-Button im Header-Row
  des Expanded-Window (kein Dev-Gating — die Shell ist Teil des
  normalen Produkt-UX). Text-Provider-Readout bindet an die fünf
  additiven `text_provider_*`-Felder aus §8 (StatusPayload) und
  benennt `llamafile_local` ehrlich als lokalen Runtime-Fallback.
  Kein neues Settings-Event-Protokoll, keine Schreibaktionen in den
  Core, kein Secret-Editor. Defensive Renderer: fehlende Felder →
  `—`, Nicht-Dictionary-Eingaben werden still abgefangen. Scene:
  `ui/scenes/settings/settings_panel.tscn`; pure Helfer in
  `ui/scripts/settings/settings_sections.gd`; Controller in
  `ui/scripts/settings/settings_panel_controller.gd`; Einbindung
  additiv in `ui/scenes/main.tscn` + `ui/scripts/main.gd`. Navigation
  als UI-Substate: Settings ersetzt das Dock-Panel innerhalb
  derselben Presence-Hülle, Avatar / Banner / Workflow-Overlay /
  Utterance-Bubble bleiben unberührt. Siehe
  [`docs/ui_architecture.md`](./ui_architecture.md) §8d. Tests:
  `scripts/settings_shell_smoke.gd` (70 Assertions PASS), Harness-
  Case `settings-shell-smoke`.
- **PR 4 — Vertiefter Status-Readout (Ist).** Der Text-Provider-
  Readout ist jetzt belastbar: zusätzlich zu den fünf PR-2-Feldern
  exponiert `StatusPayload` sieben weitere additive
  Text-/Llamafile-Felder (`text_provider_chain`,
  `llamafile_in_chain`, `llamafile_enabled`, `llamafile_configured`,
  `llamafile_lifecycle`, `llamafile_mode`,
  `llamafile_idle_timeout_seconds`, siehe §8.1 und
  [`docs/api.md` §2.3](./api.md)). Die Settings-Shell rendert die
  Kette als geordnete Fallback-Reihenfolge, öffnet bei
  `llamafile_in_chain=true` einen vertieften Lifecycle-/Mode-/Idle-
  Timeout-Block und projiziert die Cloud-/Lokal-Aussage im
  Privacy-Abschnitt ehrlich. STT und TTS bleiben in dieser Stufe
  bewusst auf dem bisherigen `*_enabled`/`*_available`/`auto_speak`-
  Basisstatus — eine Provider-Abstraktion folgt in einem späteren
  PR. Keine neuen IPC-Nachrichten, keine Schreibaktionen. Tests:
  `scripts/settings_shell_smoke.gd` um 18 Assertions erweitert, zwei
  neue IPC-Server-Tests (`get_status`-Baseline-Erweiterung und
  `llamafile_in_chain`-Pfad) und fünf neue Resolver-/Lifecycle-Tests
  in `core/src/providers/text.rs`. Gesamtsumme Core-Tests: 135 PASS
  (+6 gegenüber PR 2b).
- **PR 5 — Erste Schreib-/Probe-Oberfläche (Ist, konservativ).**
  Die Settings-Shell bekommt erstmals einen kleinen, kuratierten
  Schreibpfad — ausschließlich für die editierbaren Teile der
  `llamafile_local`-Config (`enabled`, `mode`, `idle_timeout_seconds`,
  `path`). Port, Startup- und Request-Timeout bleiben env-gesteuert
  und erscheinen **nicht** im Schreibweg. Änderungen laufen über die
  neue additive IPC-Nachricht `settings_set_llamafile_config`;
  Core validiert (Whitelist für Mode, `idle > 0`), persistiert atomar
  in einer kleinen JSON-Datei (Auflösungsreihenfolge:
  `SMOLIT_SETTINGS_DIR` → `$XDG_CONFIG_HOME/smolit-assistant/` →
  `$HOME/.config/smolit-assistant/`, Permissions 0600) und ersetzt
  den `TextProviderResolver` atomar durch einen frisch gebauten.
  Der Core antwortet mit einem frischen `status`-Envelope; Fehler
  kommen als `error`-Envelope ohne Pfad-/Secret-Leck.
  Zusätzlich eine schmale Diagnoseaktion
  `settings_probe_llamafile` → `settings_probe_result` mit
  kuratierten Tags (`ok` / `not_in_chain` / `disabled` /
  `not_configured` / `path_missing` / `path_not_file` /
  `path_not_executable`) und Secret-freier Kurzmeldung. Kein Spawn,
  kein HTTP — nur Config-/Filesystem-Inspektion. Siehe §11 für die
  Secrets-/Sensitive-Kategorien. UI-Widgets im Settings-Panel:
  Enabled-CheckBox, Mode-OptionButton, Idle-Timeout-SpinBox,
  Path-LineEdit, Apply-Button, Probe-Button plus zwei kleine
  Status-Labels. Tests: neues Core-Modul `settings_store` (6 Unit-
  Tests), vier Resolver-/Update-/Probe-Szenarien in
  `ipc/server.rs`, vier Protocol-Tests, fünf neue UI-Smokes. Core
  gesamt: 150 PASS (+15 vs. PR 4); UI-`settings-shell-smoke` auf
  103 Assertions erweitert (+15). Bewusst **nicht** Teil von PR 5:
  Cloud-Credentials-Editor, STT-/TTS-Provider-Auswahl, Secret-
  Store für API-Keys, Chain-Reihenfolge-Editor, Port-/Timeouts-
  Editor, Start/Stop-Buttons für den llamafile-Prozess.
- **PR 6 — STT-/TTS-Provider-Abstraktion (Ist, konservativ).** Die
  Audio-Achsen werden architektonisch an den Text-Pfad angeglichen:
  zwei neue Core-Module
  [`providers::stt`](../core/src/providers/stt.rs) und
  [`providers::tts`](../core/src/providers/tts.rs) mit Enum-Dispatch,
  Resolver, Laufzeitstatus und Fehlerklassifikator — gleiche
  Leitplanken wie Text-Resolver. Einziges heute produktives Kind pro
  Achse: `command`, das den bisherigen `SMOLIT_STT_CMD` /
  `SMOLIT_TTS_CMD`-Pfad 1:1 übernimmt (Timeouts, Fehlertexte,
  Legacy-`available`-Semantik bleiben byte-kompatibel). Config
  bekommt zwei zusätzliche Listen `audio.stt_provider_chain` und
  `audio.tts_provider_chain`, env-überschreibbar via
  `SMOLIT_STT_PROVIDER_CHAIN` / `SMOLIT_TTS_PROVIDER_CHAIN`;
  unbekannte Kinds werden sichtbar verworfen, die Kette fällt dann
  auf `["command"]` zurück. `App::handle_voice_once` und
  `App::handle_speak` routen ausschließlich durch die Resolver —
  das alte `audio::SttService` / `audio::TtsService` wurde
  eingemottet, `audio/types.rs` bleibt für geteilte Helfer
  (`split_command`, `AudioFeatureState`). StatusPayload additiv um
  zehn Felder erweitert
  (`stt_provider_configured` / `_active` / `_availability` /
  `_last_error` / `_cloud` und TTS-Spiegel; siehe §8.1 und
  [`docs/api.md` §2.3](./api.md)). UI-Settings-Shell: `stt_lines`
  und `tts_lines` erweitern sich um fünf Resolver-Zeilen pro Achse,
  mit ehrlichem Fallback-Hinweis für alte Cores; der Privacy-
  Abschnitt verdichtet STT-/TTS-Cloud separat statt der
  Sammelzeile. **Bewusst nicht Teil von PR 6:** kein Cloud-SDK,
  keine Cloud-Kinds, kein HTTP-Kind, keine Streaming-Pipeline, kein
  STT-/TTS-Provider-Editor in der UI, keine neuen Audio-Events
  (`speaking_started` u. ä. bleiben offen). Tests: zwei neue
  Resolver-Test-Module mit je ~7 Unit-/Integration-Tests, drei neue
  Config-Parser-Tests, zwei neue IPC-Server-Tests, zwei neue UI-
  Smoke-Blöcke. Gesamttests: Core 170 PASS (+20 vs. PR 5);
  UI-`settings-shell-smoke` auf 118 Assertions erweitert (+15).
- **PR 7 — STT-/TTS-Settings-Editor + Probe-Pfade (Ist).**
  Editierbare Audio-Settings analog zu PR 5, bewusst kleiner:
  pro Achse `enabled` + `command`, für TTS zusätzlich `auto_speak`.
  Timeouts und Provider-Chains bleiben env-/Startup-gesteuert (ein
  leerer Legacy-Override soll eine zukünftige Cloud-Kette nicht
  abschalten können). Neue IPC-Messages `settings_set_stt_config` /
  `settings_set_tts_config` / `settings_probe_stt` /
  `settings_probe_tts` (alle additiv). Der
  [`settings_store`](../core/src/settings_store.rs) kennt zwei
  weitere Dateien `stt.json` / `tts.json` (gleiche Verzeichnis-
  Auflösung, 0600-Permissions, temp+rename). Der `probe_*`-Pfad ist
  Side-Effect-frei: kein Mikrofon-Zugriff, kein Audio-Output, kein
  Spawn — nur `split_command` + Filesystem-Check des ersten Tokens.
  `SettingsProbeResultPayload` trägt neuerdings `axis`
  (`"llamafile"` / `"stt"` / `"tts"`) für das UI-Routing; ältere
  Cores ohne das Feld fallen UI-seitig auf `llamafile` zurück. Die
  Settings-Shell bekommt zwei weitere Editor-Blöcke direkt unter
  dem jeweiligen Read-only-Abschnitt (Enabled-Checkbox + Command-
  LineEdit + Probe + Apply; Auto-Speak-Checkbox nur TTS). Der
  STT-/TTS-Resolver sitzt seit PR 7 hinter einem `RwLock<Arc<…>>`
  (gleicher Swap-Mechanismus wie beim Text-Resolver in PR 5), damit
  der Schreibpfad atomar einen neuen Resolver aufhängt; externe
  Callsites holen den aktuellen Resolver über
  `App::current_stt()` / `current_tts()`. **Bewusst nicht Teil von
  PR 7:** kein STT-/TTS-Timeout-Editor, keine Chain-Reihenfolge-
  Umordnung, keine Cloud-Achse, keine Audio-Level-Anzeige, kein
  Secrets-Store. Tests: fünf neue IPC-Ende-zu-Ende-Tests, vier
  neue `settings_store`-Unit-Tests, fünf neue Protocol-Parser-
  Tests, sechs neue UI-Smoke-Blöcke. Gesamttests: Core 185 PASS
  (+15 vs. PR 6); UI-`settings-shell-smoke` auf 136 Assertions
  erweitert (+18).
- **PR 8 — erster zusätzlicher externer Text-Provider `local_http`
  (Ist).** Neuer, gleichrangiger Provider-Kind auf der Text-Achse,
  weder Unterfall von `abrain` noch von `llamafile_local`. Siehe
  §4.1c für das vollständige Modell. Kleiner HTTP-MVP gegen einen
  konfigurierbaren Endpoint (Default llama.cpp-kompatibel,
  `prompt` + `content`-Felder), nutzt den bereits bestehenden
  `http_request`-Helfer — keine neue Dependency, kein TLS, kein
  Streaming, kein Auth-Header. `TextProviderConfig` bekommt ein
  additives `local_http`-Unterobjekt
  ([`LocalHttpConfig`](../core/src/config.rs)); neue Env-Variablen
  `SMOLIT_LOCAL_HTTP_ENABLED` / `_ENDPOINT` /
  `_REQUEST_TIMEOUT_SECONDS` / `_PROMPT_FIELD` / `_RESPONSE_FIELD`.
  Der [`settings_store`](../core/src/settings_store.rs) kennt
  zusätzlich `local_http.json` (gleiche Verzeichnis-Auflösung,
  0600, temp+rename). `App` hält einen neuen `live_local_http`-
  Stand, rebuildet den `TextProviderResolver` atomar beim
  Schreibpfad. Neue IPC-Messages
  `settings_set_local_http_config` / `settings_probe_local_http`;
  `StatusPayload` bekommt drei additive Felder
  (`local_http_in_chain` / `_enabled` / `_configured`). Der
  Probe-Pfad macht **nur** einen TCP-Connect auf `host:port`, kein
  Completion-Roundtrip, kein Prompt-Versand. UI: eigener
  „local_http · Edit"-Block direkt unter dem Llamafile-Editor,
  Axis-geroutetes Probe-Ergebnis (`axis="local_http"`).
  **Bewusst nicht Teil von PR 8:** kein TLS / `https://`, keine
  Streaming-Pipeline, keine Auth-/API-Key-Eingabe, keine
  generische OpenAI-/`messages`-Welt, keine Chain-Reihenfolge-
  Umordnung in der UI, keine Cloud-Provider-Implementierung. Tests:
  neun neue Core-Unit-Tests im Text-Provider-Modul
  (Endpoint-Parser + Request/Response-Path gegen den bestehenden
  Fake-Server + Resolver-Fallback), drei neue
  `settings_store`-Unit-Tests, drei neue Protocol-Parser-Tests,
  fünf neue IPC-Ende-zu-Ende-Tests, vier neue UI-Smoke-Blöcke.
  Gesamttests: Core 210 PASS (+25 vs. PR 7);
  UI-`settings-shell-smoke` auf 154 Assertions erweitert (+18).
- **PR 9 — Text-Provider-Chain-Editor in der Settings-Shell (Ist).**
  Erstmals kann der Nutzer die **Text-Provider-Fallback-Reihenfolge**
  über die Shell editieren — klein, kuratiert, ohne freie Namens-
  eingabe. `providers::text` bekommt eine
  [`KNOWN_TEXT_KINDS`](../core/src/providers/text.rs)-Whitelist
  (`abrain` / `llamafile_local` / `local_http`), eine
  `DEFAULT_TEXT_PROVIDER_CHAIN`-Konstante und einen
  `validate_text_chain`-Helper (Whitelist + Duplikat-Ablehnung +
  Empty-Reject). `App.text_provider_chain` wird zu
  `App.live_text_chain: Mutex<Vec<TextProviderChainItem>>`; ein
  neuer `App::update_text_provider_chain` führt die Validierung aus,
  persistiert über den Settings-Store (neues `text_chain.json`,
  gleiche Verzeichnisauflösung / 0600-Permissions / temp+rename wie
  die anderen Override-Files, siehe §11) und rebuildet den
  `TextProviderResolver` atomar. Ein zusätzlicher
  `App::reset_text_provider_chain`-Pfad löscht den Override und
  fällt auf `["abrain"]` zurück. Neue IPC-Messages
  `settings_set_text_provider_chain` /
  `settings_reset_text_provider_chain` (alle additiv); Response bei
  Erfolg ist der reguläre `status`-Envelope, bei
  Validation-Fehlern ein kuratiertes `error`-Envelope. UI-Seite: ein
  kleiner „text provider chain · Edit"-Block direkt über dem
  Llamafile-Editor mit einer Row pro bekanntem Kind
  (Enable-Checkbox + Up/Down-Buttons), plus Apply/Reset. Bewusst
  klein gehalten: kein Drag-and-Drop, keine freie Namenseingabe,
  kein STT-/TTS-Chain-Editor in diesem PR. Tests: sieben neue
  Core-Unit-Tests (Validator: Happy-Path, Normalisierung, Empty,
  Unknown, Empty-Token, Duplicate, Known-Kinds-Frozen-Set), vier
  neue `settings_store`-Unit-Tests (Roundtrip, Reject-Empty,
  Clear-Idempotenz, Missing-File-Is-None), drei neue Protocol-
  Parser-Tests, sechs neue IPC-Ende-zu-Ende-Tests (Apply,
  Reject-Unknown, Reject-Duplicate, Reject-Empty, Reset-To-Default,
  Case-/Whitespace-Normalisierung), drei neue UI-Smoke-Blöcke
  (Build + Sync, Toggle/Move, UI-Seiten-Empty-Guard). Gesamttests:
  Core 230 PASS (+20 vs. PR 8); UI-`settings-shell-smoke` auf
  erweitert (+9 Assertions).
- **PR 10 — erster Cloud-/Remote-Text-Provider + dedizierter
  Secret-Pfad (Ist).** Einziger Cloud-Kind heute: `cloud_http`.
  Sehr bewusster MVP — **nicht** ein „OpenAI-Universum-Adapter":
  POST JSON mit einem Prompt-Feld + optionalem `model`, Response
  trägt ein Text-Feld, Bearer-Auth über einen konfigurierbaren
  Header. Kein Streaming, kein Tool-Calling, kein `messages`-
  Array. **Plaintext HTTP nur**; `https://` wird hart abgelehnt,
  weil PR 10 keine TLS-/Trust-Infrastruktur mitbringt — Betreiber
  stellen einen vertrauenswürdigen Reverse-Proxy vor den
  Endpoint. Der Secret-Pfad ist der Herzschlag dieses PRs: ein
  dedizierter [`crate::secrets_store`](../core/src/secrets_store.rs)
  mit eigener Datei `secrets.json`, eigener Serde-Struktur
  (`SecretsFile`) und eigenem `Debug`-Impl, das Werte **durchgängig**
  elidiert (`<set>`/`<unset>`). Der Key fließt vom UI-Masked-
  LineEdit per IPC direkt in den Store; `App.cloud_http_api_key`
  lebt als `Mutex<Option<String>>` getrennt von allen operationalen
  Configs. `StatusPayload` bekommt vier schmale, **nicht
  sensitiven** Felder: `cloud_http_in_chain`, `cloud_http_enabled`,
  `cloud_http_configured`, `cloud_http_secret_present` — der
  Key-Wert verlässt den Store niemals. Neue IPC-Messages
  `settings_set_cloud_http_config` (operational),
  `settings_set_cloud_http_secret` (einziger IPC-Pfad mit
  Key-Klartext), `settings_probe_cloud_http` (TCP-Connect only,
  kein Completion-Roundtrip, kein Bearer-Header auf der Leitung).
  UI: ein deutlich markierter „external · cloud"-Block mit
  Warnhinweis, maskiertem Secret-LineEdit und sofortigem Leeren
  des Felds nach Save-Klick (auch offline, security-first). Tests:
  acht neue Secret-Store-Unit-Tests (inkl. 0600-Permission-Test,
  Debug-Leak-Guard und Parse-Error-ohne-Panic), elf neue
  Text-Provider-Unit-Tests (URL-Parser, classify_error-Tags,
  Resolver-Fallback cloud → local, Debug-Leak-Guard auf
  `CloudHttpProvider`), vier neue Protocol-Parser-Tests, sechs
  neue IPC-Ende-zu-Ende-Tests (davon vier mit **aktiven**
  Secret-Leak-Guards: weder `status` noch Probe-Response noch
  `error`-Envelope dürfen den Key-Marker oder den Endpoint
  enthalten). Gesamttests: Core 260 PASS (+30 vs. PR 9);
  UI-`settings-shell-smoke` +4 Cloud-HTTP-Blöcke (Editor-Bau,
  Secret-Edit bleibt nach Status-Tick leer, Status-Label
  spiegelt `secret_present`-Flag, Edit-Feld ist sofort nach Save
  geleert). Alle übrigen UI-Smokes grün; Headless-Boot sauber.
- **PR 11 — TLS für `cloud_http` + sicherer Probe-/Request-Pfad
  (Ist).** Der `cloud_http`-Provider akzeptiert jetzt zusätzlich
  zu `http://` auch `https://`. Der HTTPS-Pfad läuft über
  `tokio-rustls` (pure-Rust, `ring`-Crypto-Provider) mit dem in
  `webpki-roots` eingebetteten Mozilla-Trust-Store — hermetisch
  kompiliert, **keine** Abhängigkeit auf System-Cert-Stores oder
  native TLS-Libraries. Keine stille Zertifikats-Deaktivierung,
  kein UI-Schalter „unsichere TLS-Verbindung erlauben", keine
  `accept_invalid_certs`-Abkürzung. Die bestehende harte
  `https://`-Ablehnung aus PR 10 fällt weg; `endpoint_scheme_unsupported`
  meldet jetzt nur noch nicht-http/https-Schemes (z. B. `ftp://`).
  Der interne `http_request_with_header` bekommt einen fünften
  Parameter [`CloudHttpScheme`](../core/src/providers/text.rs)
  plus einen `Arc<rustls::ClientConfig>`, und ein gemeinsamer
  `do_http_exchange<S>`-Helfer teilt den Write/Read-Pfad zwischen
  TcpStream und `tokio_rustls::client::TlsStream`. Neue
  Fehlerklassen in `classify_error` (alle stabil und kuratiert):
  `tls_handshake_failed`, `cert_untrusted` (UnknownIssuer),
  `cert_invalid` (Expired / NotYetValid / BadSignature /
  DNS-Mismatch). Der Probe-Pfad in `App::probe_cloud_http` macht
  für `https://` jetzt einen echten TLS-Handshake (noch kein
  Completion-Roundtrip und kein Bearer-Header auf der Leitung —
  die Rückgabe-Klassen unterscheiden aber sauber zwischen
  Transport-Problemen, Cert-Problemen und Config-Problemen) und
  meldet `"ok"` nur, wenn der Handshake gelang. Für `http://`
  bleibt der TCP-Connect-only-Pfad und die Rückmeldung
  `"ok_http"` kennzeichnet den Transport ehrlich. UI-Seite: ein
  kleiner Insecure-Transport-Hinweis, der sichtbar wird, sobald
  der Nutzer einen `http://`-Endpoint tippt (kein Toggle, kein
  Bypass). Tests: fünf neue Provider-Unit-Tests, davon einer mit
  einem **echten** HTTPS-Fake-Server (rcgen selbstsigniertes
  Cert, injiziert über `CloudHttpProvider::new_with_tls_config`)
  plus Regressions-Guards für den plaintext-HTTP-Pfad, einer für
  `cert_untrusted` gegen den Produktions-Trust-Store, einer für
  `tls_handshake_failed` (HTTPS-Client gegen Plain-HTTP-Port),
  einer für `unauthorized` (401), und ein IPC-Ende-zu-Ende-Test,
  der die Probe-Fehlerklasse gegen den Fake-HTTPS-Server in der
  Produktions-Config prüft. **Secret-Leak-Guards bleiben aktiv:
  weder der Bearer-Wert noch der Endpoint tauchen je in
  TLS-Fehlermeldungen oder Probe-Responses auf.** Gesamttests:
  Core 268 PASS (+8 vs. PR 10); UI-`settings-shell-smoke` +3
  Assertions (`http://`-Hint erscheint, verweist auf `https://`,
  bleibt bei `https://` leer). Alle übrigen UI-Smokes grün;
  Headless-Boot sauber. **Bewusste Restschuld:** Probe macht
  noch keinen authentifizierten HTTP-Request über TLS (der
  Handshake ist erstmal die Grenze; ein `unauthorized`-Tag in
  `classify_error` existiert schon für den Run-Pfad, wird in der
  Probe aber erst mit dem nächsten Ausbau erreichbar).
- **PR 12 — authentifizierter `cloud_http`-Probe-Roundtrip (Ist).**
  Die Probe wertet sich von einer Transport-/TLS-Prüfung zu einer
  echten Application-Layer-Probe auf. Der Core sendet einen
  `HEAD`-Request gegen den konfigurierten Endpoint mit
  `Authorization: Bearer <key>` (Header-Name aus Config,
  Key aus dem Secrets-Store). **Kein** Completion-Request,
  **kein** Prompt, **kein** Nutzer-Inhalt auf der Leitung —
  HEAD reicht, weil Auth-Middleware den Bearer genauso
  validiert wie bei POST. Die Probe kann jetzt ehrlich
  unterscheiden: `ok` (Status 2xx → Auth ok, Endpoint
  erreichbar), `unauthorized` (Status 401/403 → Server lehnt
  den gespeicherten Key explizit ab), `http_error` (Status
  außerhalb 2xx/401/403 → numerischer Status in der Meldung),
  plus die bereits bestehenden Transport-/TLS-/Config-Klassen.
  Die PR-11-only-Klasse `ok_http` (TCP-Connect-only für
  `http://`) entfällt — beide Transporte gehen jetzt durch
  denselben authentifizierten HEAD-Pfad. Der Probe-Code sitzt
  in `App::probe_cloud_http` und ruft das bestehende
  `http_request_with_header(scheme, …, "HEAD", …)` auf; der
  existierende Secret-Disziplin-Pfad im Helfer (kuratierte
  Kontext-Strings, kein Header-Echo) trägt damit direkt in den
  Probe-Ergebnispfad durch. Tests: vier neue IPC-Ende-zu-Ende-
  Tests — `ok` über plaintext-HTTP gegen Fake-Server mit
  Bearer-Check, `unauthorized` bei Mismatched Bearer,
  `http_error` bei Server-500, Cert-Pfad über HTTPS-Fake-Server
  (bestätigt weiterhin, dass untrusted cert den Probe-Pfad
  sauber blockiert, auch mit Auth im Spiel). Alle vier Tests
  tragen aktive **Secret-Leak-Guards**: weder Bearer-Marker
  noch Endpoint-Host im Response. Die fake-Server-Infrastruktur
  bekam einen neuen `FakeHttpsMode::RequiresBearer`-Modus und
  einen `HttpErrorStatus(u16)`-Modus; ein neuer
  `start_fake_http_auth_server`-Helper erlaubt die gleiche
  Semantik über plain HTTP. Gesamttests: Core 272 PASS (+4 vs.
  PR 11); UI-Smokes unverändert grün; Headless-Boot sauber.
  **Bewusste Restschuld:** kein End-to-End-Happy-Path-Test über
  echtes TLS mit injiziertem Test-Trust-Store durch den
  Probe-Pfad (der Unit-Test auf Provider-Ebene deckt die
  TLS-Kette ab; die Probe verwendet fest die Produktions-
  `default_cloud_http_tls_config`, damit kein Test-Footgun in
  Produktion aktiv werden kann). Sobald ein Admin-UX für
  Custom-CA-Bundles kommt, kann der Probe-Trust-Store
  konfigurierbar werden.
- **PR 13 — STT/TTS Chain-Editor in der Settings-Shell (Ist).**
  Spiegel zum Text-Chain-Editor aus PR 9, aufgesetzt auf die
  Audio-Achsen. Beide Achsen bekommen eine Whitelist
  ([`crate::providers::stt::KNOWN_STT_KINDS`](../core/src/providers/stt.rs)
  und
  [`crate::providers::tts::KNOWN_TTS_KINDS`](../core/src/providers/tts.rs) —
  heute pro Achse nur `command`), einen `validate_*_chain`-Helper
  (Empty-Reject / UnknownKind / Duplicate / Trim+Lowercase) und
  je einen `DEFAULT_*_PROVIDER_CHAIN`-Reset-Default. `App`
  bekommt `update_stt_provider_chain` / `reset_stt_provider_chain` /
  `update_tts_provider_chain` / `reset_tts_provider_chain`;
  `live_audio.{stt,tts}_provider_chain` ist seit PR 13 der
  Source-of-Truth-Stand (die Startup-`config.audio`-Kette wirkt
  nur noch als erster Startwert). Der Settings-Store erweitert
  die Override-Dateien um `stt_chain.json` und `tts_chain.json`
  (gleiches `AudioChainOverrideFile { chain: Option<Vec<String>> }`-
  Format, gleiche atomare Write-/0600-Linie wie
  `text_chain.json`). Neue IPC-Messages
  `settings_set_{stt,tts}_provider_chain` /
  `settings_reset_{stt,tts}_provider_chain` sind additiv; bei
  Erfolg frischer `status`-Envelope mit `stt_provider_chain` /
  `tts_provider_chain` als neuer Reihenfolge, bei Validation-
  Fehler kuratiertes `error`-Envelope. UI-Seite: ein gemeinsamer
  `_build_audio_chain_editor_block(axis)`-Helper baut beide
  Editoren parametrisiert; die axis-spezifischen State-Variablen
  (`_stt_chain_*` / `_tts_chain_*`) und Whitelists (`_KNOWN_STT_KINDS` /
  `_KNOWN_TTS_KINDS`) spiegeln die Core-Whitelists 1:1. Ein
  kleines Info-Label in jedem Editor weist ehrlich darauf hin,
  dass heute nur `command` verfügbar ist — die UI verspricht
  keine zusätzlichen Provider, die nicht existieren.
  `settings_sections::stt_lines` / `tts_lines` rendern das neue
  `stt_provider_chain` / `tts_provider_chain`-Feld als
  „Chain"-Zeile; fehlt das Feld (alter Core), bleibt die Zeile
  mit einem ehrlichen „—" stehen. Tests: sechs neue Validator-
  Unit-Tests pro Achse (Happy-Path, Normalisierung, Empty,
  Unknown, Duplicate, Frozen-Set), sechs neue `settings_store`-
  Unit-Tests (Roundtrip, Reject-Empty, Clear-Idempotenz pro
  Achse), vier neue Protocol-Parser-Tests, sieben neue IPC-
  Ende-zu-Ende-Tests, sechs neue UI-Smoke-Blöcke (Build + Sync
  pro Achse, Empty-Guard pro Achse, Single-Kind-Info-Hinweis,
  Readout-Chain-Zeile). Gesamttests: Core 302 PASS (+30 vs.
  PR 12); UI-`settings-shell-smoke` +6 Assertions. Alle übrigen
  UI-Smokes grün; Headless-Boot sauber.

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

---

## 11. Secrets- und Sensitive-Config-Kategorien (Ist, PR 5 + PR 7 + PR 8 + PR 9 + PR 10 + PR 11 + PR 12 + PR 13)

Ab PR 5 existiert in
[`core/src/settings_store.rs`](../core/src/settings_store.rs) ein
kleiner persistenter Store für die editierbaren Teile der
Llamafile-Config; PR 7 ergänzt dort die STT-/TTS-Overrides; PR 8
bringt den `local_http`-Override dazu; PR 9 ergänzt einen
`text_chain.json`-Override für die Text-Provider-Fallback-
Reihenfolge. **PR 10** führt zusätzlich einen **dedizierten
Secrets-Store** in
[`core/src/secrets_store.rs`](../core/src/secrets_store.rs) mit
eigener Datei `secrets.json` ein — getrennt von allen
operationalen Overrides. Dieser Abschnitt legt die Trennlinien
fest, die jede künftige Schreibfläche einhalten muss.

**Kategorien.**

- **Operational.** Boolesche Feature-Flags, Mode-Strings aus einer
  geschlossenen Whitelist, Timeouts, Ports, Pfade zu lokalen
  Binaries. Dürfen persistiert werden, dürfen im StatusPayload
  erscheinen, dürfen in Logs stehen — mit der Sonderregel, dass
  **Binary-Pfade** defensiv behandelt werden (siehe unten).
- **Sensitive.** API-Keys, Tokens, Basic-Auth-Credentials, URLs mit
  Schlüsseln im Query-String. Diese Kategorie ist heute **leer** —
  es gibt keinen Cloud-Provider. Wenn sie entsteht, bekommt sie
  einen separaten Store mit identischer Dateirechte-Disziplin
  (0600 auf Unix), **darf nicht** in `StatusPayload`, Event-Envelopes,
  Log-Zeilen oder UI-Readouts sichtbar werden, und wird in der UI
  nur als maskierter Platzhalter dargestellt (`•••• last4`).

**Pfad-Disziplin.** Ein Binary-Pfad ist formal operational, wird
aber wie eine sensitive-lite-Ressource behandelt:

- In Logs taucht er nicht als Literal auf; nur als
  `path_set=true/false`.
- Im Probe-Ergebnis (`settings_probe_result`) wird er **nicht**
  zurückgeschickt; die `message` bleibt kuratiert.
- Im Fehler-Envelope zu einem fehlgeschlagenen
  `settings_set_llamafile_config` wird er nicht echo't.
- Der StatusPayload enthält heute kein Pfad-Feld. Wenn ein späterer
  PR ein solches Feld einführt, muss es als hashing-/masking-
  kompatibel dokumentiert sein.

**Schreib-/Persistenz-Pfade.**

- **Editierbare Operational-Werte.** Sieben kleine Override-Dateien
  im Settings-Verzeichnis:
  `llamafile_local.json` (PR 5), `stt.json` (PR 7), `tts.json`
  (PR 7), `local_http.json` (PR 8), `text_chain.json` (PR 9),
  `stt_chain.json` + `tts_chain.json` (PR 13).
  Auflösungsreihenfolge:
  `SMOLIT_SETTINGS_DIR` → `$XDG_CONFIG_HOME/smolit-assistant/` →
  `$HOME/.config/smolit-assistant/`. Atomarer Write
  (temp + rename). Unix-Permissions 0600, damit die Oberfläche
  derselben Posture folgt wie ein zukünftiger Secret-Store.
  STT-/TTS-Override persistieren ausschließlich die UI-editierbaren
  Felder (`enabled`, `command`, TTS zusätzlich `auto_speak`);
  `local_http`-Override persistiert nur `enabled`, `endpoint` und
  `request_timeout_seconds` — Prompt-/Response-Feldnamen bleiben
  env-/Startup-gesteuert. `text_chain.json` / `stt_chain.json` /
  `tts_chain.json` persistieren jeweils eine bereits validierte
  Reihenfolge bekannter Kinds (Validator läuft im App-Schreibpfad,
  nicht im Store). Die Audio-Chains sind seit PR 13
  UI-editierbar; andere Env-Gated-Felder (Prompt-/Response-Feldnamen
  von `local_http`, Timeouts, Auth-Header) bleiben weiterhin
  env-gesteuert, damit ein altes Override-File keine späteren
  Feature-Entscheidungen überstimmt.
- **Sensitive-Werte.** Seit PR 10 existiert ein eigener Secrets-
  Store ([`core/src/secrets_store.rs`](../core/src/secrets_store.rs))
  in einer **separaten** Datei `secrets.json` (gleiche
  Verzeichnisauflösung, Permissions 0600, atomarer Write).
  Aktuell ein einziges Feld: `cloud_http_api_key`. Der Store
  ist der **einzige** Code-Pfad, der Secret-Klartext sieht —
  weder das operationale `settings_store`-Modul noch das
  `StatusPayload`-Projektions-Layer noch Logs oder IPC-Responses
  sehen je den Wert. `SecretsFile::Debug` elidiert jedes Feld
  ausdrücklich zu `<set>`/`<unset>`. Weitere Sensitive-Werte in
  Folge-PRs landen im gleichen File unter neuen optionalen
  Feldern — **nie** gemeinsam mit operational-Werten serialisiert,
  und nie aus dem Core in Richtung
  UI/IPC exponiert — die UI sieht nur „gesetzt ja/nein" + Masking.

**IPC-Disziplin.**

- `settings_set_*`-Nachrichten transportieren nur Operational-
  Werte **außer** `settings_set_cloud_http_secret` (PR 10) —
  diese eine Message trägt bewusst Sensitive-Klartext und ist
  **die einzige**, die das darf. Der Response-Pfad antwortet mit
  einem Status-Envelope, der nur `cloud_http_secret_present: bool`
  trägt; der Key-Wert verlässt den Core niemals in Richtung UI.
  Künftige Cloud-Provider nutzen denselben Pfad (pro Provider-
  Kind eine eigene `settings_set_*_secret`-Message und ein
  eigenes Feld im Secrets-Store-Schema). Ausgestaltung für
  weitere Sensitive-Kategorien (Ausgestaltung offen, nicht Teil von
  PR 5/7/8).
- Antworten auf Schreibaktionen spiegeln ausschließlich den
  StatusPayload — kein Raw-Echo der Eingabe.
- Probe-Aktionen (`settings_probe_{llamafile,stt,tts,local_http,cloud_http}`)
  sind Side-Effect-frei im Sinne der Nutzer-Intention und liefern
  kuratierte Tags. STT/TTS-Probes greifen ausdrücklich nicht auf
  Mikrofon oder Audio-Output zu; der `local_http`-Probe macht
  einen TCP-Connect auf `host:port`, aber **keinen**
  Completion-Request und sendet keine Prompt-Daten. Der
  `cloud_http`-Probe sendet seit PR 12 einen authentifizierten
  HEAD-Request (Bearer-Header aus dem Secrets-Store), bei
  `https://` nach erfolgreichem TLS-Handshake. Sie kann jetzt
  ehrlich zwischen `ok` (2xx), `unauthorized` (401/403) und
  `http_error` (sonstige Non-2xx) unterscheiden. **Weiterhin
  keinen** Completion-Request, **kein** Prompt und **kein**
  Nutzer-Inhalt auf der Leitung — HEAD reicht für die
  Application-Layer-Validierung. Der Bearer-Wert verlässt den
  Core ausschließlich in dieser einen HEAD-Request-Geometrie
  und wird nirgendwo zurückgespiegelt; die Probe-Response
  trägt nur die kuratierten Klassen und numerische Status-
  Codes.

## 12. Provider-Onboarding UX v1 (PR 26)

PR 26 legt oberhalb der bestehenden Editoren einen kuratierten
**Provider-Onboarding-Block** ab, der das *Lesen* der Provider-
Konfiguration anleitet. Keine neue Provider-Fähigkeit, kein neues
IPC-Command, keine Default-Änderung.

### 12.1 Was der Block zeigt

- **Primary provider** — bevorzugt `text_provider_active`, fällt auf
  das erste Kind der `text_provider_chain` zurück, dann auf
  `text_provider_configured`, zuletzt auf einen `—`-Platzhalter. Jeder
  Name wird mit seiner Lokalitäts-Klassifikation gerendert
  (`abrain [local]`, `cloud_http [cloud]`, …).
- **Chain mit Lokalität** — `text_provider_chain` wird als `kind
  [locality]`-Liste mit `→` getrennt dargestellt. Unbekannte Kinds
  bekommen `[unknown]` — die UI erfindet keine Sicherheitsaussage.
- **cloud_http First-Run Checklist** — vier Zeilen plus eine
  Zusammenfassungszeile, die direkt aus den bestehenden Status-
  Feldern gespeist wird:
  - `cloud_http enabled` — `cloud_http_enabled`
  - `cloud_http endpoint` — `cloud_http_configured` (set/missing)
  - `cloud_http api key` — `cloud_http_secret_present` (present/not set;
    **nie** ein Wert)
  - `cloud_http in chain` — `cloud_http_in_chain`
  - `cloud_http ready` — `ready` (alle vier true) vs.
    `first-run steps pending`

### 12.2 Quick Actions

- **`Use local-first chain`** — sendet
  `settings_set_text_provider_chain` mit der kuratierten Liste
  `["llamafile_local", "local_http", "abrain"]`. Keine Persistenz
  außerhalb des bestehenden Settings-Store-Pfads; der Core-Validator
  filtert unbekannte Kinds wie in PR 9 beschrieben.
- **`Add cloud_http to chain`** — **bleibt per Design disabled**,
  selbst wenn alle vier Bereitschafts-Flags grün sind. Der Button
  ist Sichtbarkeits-Artefakt, keine Quick-Action. Daneben steht der
  Erklärtext aus `add_cloud_disabled_reason()` bzw. ein neutraler
  „use the cloud_http editor below"-Hinweis. Grund: Cloud bleibt
  bewusst Opt-in, das Hinzufügen zur Chain soll eine bewusste
  Handlung im `cloud_http`-Editor sein.

### 12.3 Cloud-HTTP First-Run — Klartexte

Die UI-Konstanten in `ui/scripts/settings/provider_onboarding.gd`
halten die Erklärtexte an einem Ort:

- `LOCAL_FIRST_HINT_TEXT` — begründet den lokalen Default.
- `NO_AUTO_CLOUD_TEXT` — hält fest: „Cloud wird nicht automatisch
  aktiviert. cloud_http landet nur dann in der Chain, wenn du es
  explizit setzt — diese Shell schaltet das nicht für dich."

### 12.4 Security-Invarianten des Onboarding-Blocks

- **Kein API-Key im Readout.** Die Checklist liest
  `cloud_http_secret_present` als Boolean und rendert `present` /
  `not set` — niemals den Wert. Smoke:
  `_check_onboarding_cloud_secret_never_leaks_value`.
- **Kein neuer Secrets-Pfad.** Der Block setzt / löscht keine
  Schlüssel; der bestehende `settings_set_cloud_http_secret` /
  `settings_clear_cloud_http_secret`-Pfad im `cloud_http`-Editor
  darunter bleibt Single-Source für Key-Änderungen.
- **Keine Auto-Cloud-Aktivierung.** Die Quick-Action setzt *keine*
  Chain, die `cloud_http` enthält; der Add-Cloud-Button bleibt
  disabled. Smoke:
  `_check_onboarding_local_first_quick_action_sends_expected_chain`
  und `_check_onboarding_add_cloud_button_stays_disabled_by_design`.
- **Keine echten Netzwerk-Requests im Smoke.** Der UI-Smoke benutzt
  keinen `IpcClient` und prüft nur die Datenflüsse im Panel-Controller
  (`simulate_local_first_chain_for_test` mit `null`-Stub).

### 12.5 Nicht-Ziele (PR 26)

- Keine neuen Provider-Kinds, kein Änderung des Compile-Time-Defaults
  `["abrain"]`.
- Keine Auto-Cloud-Aktivierung, keine automatische Chain-Injektion.
- Keine neuen `*_snapshot`-IPC-Envelopes — der Block liest nur aus
  dem bestehenden `StatusPayload`.
- Keine API-Key-Anzeige, kein zweiter Secret-Store.
- Keine Änderung am Core-Policy-v0-Verhalten (PR 25).
- Kein Smolitux-Design-Token-Mapping in diesem PR (siehe ADR-0001,
  PR 24).
