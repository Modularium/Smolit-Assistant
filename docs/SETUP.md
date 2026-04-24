# Smolit Assistant — Setup & Troubleshooting

Ausführlicher Begleiter zum Quick-Start im
[README](../README.md). Zielpublikum: Entwickler:innen und erste
Tester:innen auf einem Linux-Dev-Host (Ubuntu 24.04 / GNOME/Wayland
primary; X11 für `focus_window`-Opt-in unterstützt).

**Kein Packaging**, **keine CI-Pipeline**, **keine Install-Skripte** —
das sind eigene Folge-PRs (Workstream I).

## 1. Voraussetzungen im Detail

### 1.1 Rust

- **Edition 2024** — braucht **Rust 1.85 oder neuer**. Check:

  ```bash
  rustc --version
  cargo --version
  ```

- Installation über [rustup](https://rustup.rs) ist die empfohlene
  Variante (stabiler Toolchain-Updater).
- Keine zusätzlichen System-Libraries: `cloud_http`-TLS läuft über
  `rustls` + `webpki-roots`, pure-Rust, **keine** `openssl`-Header
  nötig.

### 1.2 Godot

- **Godot 4.6** ist der getestete Zielstand
  (`ui/project.godot::config/features` = `"4.6"` + `"GL Compatibility"`).
  4.2+ funktioniert in der Praxis, 4.6 ist die verifizierte Linie.
- **Headless-Läufe** (für Smoke-Tests) brauchen die `--headless`-
  Fähigkeit der Godot-Editor-Binary; keine zweite Godot-Version.
- Unter GNOME/Wayland läuft Godot im XWayland-Modus; Overlay-
  Fähigkeiten sind plattformgebunden (siehe §5.4).

### 1.3 Optionale Tools

Je Feature:

| Feature | Tool | Warum |
| --- | --- | --- |
| ABrain-Text-Pfad | ABrain-CLI | Default-Text-Provider (`SMOLIT_TEXT_PROVIDER_CHAIN=abrain`). |
| TTS-Kind `command` | `espeak`, `kokoro`, eigenes Skript | `SMOLIT_TTS_CMD` liest stdin, spricht. |
| TTS-Kind `piper` | Piper-Binary (PR 34) | `SMOLIT_TTS_PIPER_CMD` — gleicher stdin-Spawn-Vertrag wie `command`. |
| STT-Kind `command` | `whisper`, `vosk`, eigenes Skript | `SMOLIT_STT_CMD` nimmt auf, druckt erkannten Text auf stdout. |
| STT-Kind `whisper_cpp` | whisper.cpp-Binary | `SMOLIT_STT_WHISPER_CPP_CMD` — gleicher Spawn-Vertrag wie `command`. |
| `focus_window` (X11) | `wmctrl` | X11-Template `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD="wmctrl -a {name}"`. |
| Always-on-top (X11 only) | X11-Session | `SMOLIT_UI_ALWAYS_ON_TOP=1` setzt `_NET_WM_STATE_ABOVE`. |

Keines davon ist Build-Abhängigkeit. Alles bleibt auf Laufzeit-
Opt-in.

## 2. Quick Start ausführlich

### 2.1 Clone + Initial-Test

```bash
git clone https://github.com/Modularium/Smolit-Assistant.git
cd Smolit-Assistant

# Env-Minimal-Set
cp .env.example .env

# Core-Tests (sollten 382 bestehen)
cargo test --manifest-path core/Cargo.toml
```

Ein passing `cargo test` bestätigt, dass

- die Rust-Toolchain kompatibel ist,
- die Policy-v0-Tripwire-Tests grün sind
  (`policy_v0_defaults_are_locked`),
- die STT-Whitelist `[command, whisper_cpp]` erwartet.

### 2.2 Core starten

```bash
cargo run --manifest-path core/Cargo.toml
```

Erwarteter Output:

```text
Smolit ready.
>
```

Der Core lauscht dann auf `127.0.0.1:8787` (IPC-WebSocket). Kleine
CLI-Befehle funktionieren direkt:

```text
> help
> audio-status
> exit
```

### 2.3 UI starten

In einem zweiten Terminal (Core muss laufen):

```bash
godot --path ui
```

Godot öffnet `res://scenes/main.tscn`. Nach dem Connect erscheinen:

- Avatar + Status-Header (`connected` / `disconnected`).
- Compact Input (Docked) bzw. Log + Eingabe (Expanded).
- Approval Card, sobald eine Aktion Approval braucht.

### 2.4 Verifikations-Smokes

Reproduzierbare Headless-Smokes:

```bash
scripts/run_overlay_verification.sh settings-shell-smoke
scripts/run_overlay_verification.sh speech-sync-smoke
scripts/run_overlay_verification.sh workflow-state-smoke
scripts/run_overlay_verification.sh resolver-smoke
```

Alle vier sollten mit `PASS` enden. Weitere Cases (Overlay,
Click-through, AOT-X11, Runtime-Report) sind im `--help`-Output
gelistet.

## 3. Environment-Variablen nach Gruppen

Alle hier gelisteten Variablen sind **optional mit sinnvollen
Defaults**. Leerer Wert = nicht konfiguriert (ehrlich
`unavailable` statt still fallback).

### 3.1 Core / ABrain

| Variable | Default | Zweck |
| --- | --- | --- |
| `ABRAIN_CMD` | `abrain` | Command für den Reasoning-Adapter (PATH-Lookup). |
| `LOG_LEVEL` | `info` | `trace` / `debug` / `info` / `warn` / `error`. |
| `SMOLIT_IPC_ENABLED` | `true` | Lokaler WebSocket-Server. |
| `SMOLIT_IPC_BIND` | `127.0.0.1:8787` | **Nur Loopback verwenden**. |

### 3.2 Audio / STT / TTS

| Variable | Default | Zweck |
| --- | --- | --- |
| `SMOLIT_TTS_ENABLED` | `true` | TTS-Achse an/aus. |
| `SMOLIT_TTS_CMD` | *leer* | TTS-`command`-Kind. Bekommt Text auf stdin. |
| `SMOLIT_TTS_TIMEOUT_SECONDS` | `20` | Pro Spawn. |
| `SMOLIT_STT_ENABLED` | `true` | STT-Achse an/aus. |
| `SMOLIT_STT_CMD` | *leer* | STT-`command`-Kind. Stdout = erkannter Text. |
| `SMOLIT_STT_WHISPER_CPP_CMD` | *leer* | STT-`whisper_cpp`-Kind (PR 27). Env-only. |
| `SMOLIT_TTS_PIPER_CMD` | *leer* | TTS-`piper`-Kind (PR 34). Env-only. |
| `SMOLIT_STT_TIMEOUT_SECONDS` | `20` | Pro Spawn. |
| `SMOLIT_AUDIO_AUTO_SPEAK` | `true` | Antworten automatisch über TTS sprechen. |
| `SMOLIT_STT_PROVIDER_CHAIN` | `command` | Komma-separiert. Whitelist: `command`, `whisper_cpp`. |
| `SMOLIT_TTS_PROVIDER_CHAIN` | `command` | Whitelist: `command`. |

**whisper.cpp-Pfad aktivieren** (alle drei Schritte nötig):

```bash
SMOLIT_STT_ENABLED=true
SMOLIT_STT_WHISPER_CPP_CMD="/opt/whisper.cpp/main -m /opt/whisper.cpp/models/ggml-base.bin -f {input}.wav"
SMOLIT_STT_PROVIDER_CHAIN="whisper_cpp,command"
```

Ist nur das Env gesetzt, aber `whisper_cpp` nicht in der Chain, meldet
die Settings-Shell
`configured (via SMOLIT_STT_WHISPER_CPP_CMD), aber nicht in der Chain`.

### 3.3 Text-Provider

| Variable | Default | Zweck |
| --- | --- | --- |
| `SMOLIT_TEXT_PROVIDER_CHAIN` | `abrain` | Whitelist: `abrain`, `llamafile_local`, `local_http`, `cloud_http`. |
| `SMOLIT_LLAMAFILE_ENABLED` / `_PATH` / `_MODE` / `_PORT` / `_IDLE_TIMEOUT_SECONDS` / `_STARTUP_TIMEOUT_SECONDS` / `_REQUEST_TIMEOUT_SECONDS` | *leer / 8788 / 300 / 30 / 60* | Lokaler Llamafile-Runtime-Pfad. |
| `SMOLIT_LOCAL_HTTP_ENABLED` / `_ENDPOINT` / `_PROMPT_FIELD` / `_RESPONSE_FIELD` / `_REQUEST_TIMEOUT_SECONDS` | *leer / … / prompt / content / 60* | Lokaler HTTP-Completion-Endpoint (llama.cpp-kompatibel). |
| `SMOLIT_CLOUD_HTTP_ENABLED` / `_ENDPOINT` / `_MODEL` / `_REQUEST_TIMEOUT_SECONDS` | *leer / … / 90* | Cloud-HTTP. **API-Key nicht hier!** Siehe §5.5. |

### 3.4 Desktop Interaction / Approval

| Variable | Default | Zweck |
| --- | --- | --- |
| `SMOLIT_INTERACTION_ENABLED` | `true` | Interaction-Layer insgesamt. |
| `SMOLIT_INTERACTION_BACKEND` | `command` | Einzig implementiertes Backend. |
| `SMOLIT_INTERACTION_REQUIRE_CONFIRMATION` | `true` | **Policy v0 (PR 25)**. In Produktion nicht auf `false` setzen. |
| `SMOLIT_INTERACTION_ALLOW_OPEN_APP` | `true` | `open_application` real. Weiterhin approval-gated. |
| `SMOLIT_INTERACTION_OPEN_APP_CMD` | *leer* | z. B. `gtk-launch {name}` oder `xdg-open {name}`. Leer = `BackendUnsupported`. |
| `SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW` | `false` | Doppeltes Opt-in. |
| `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD` | *leer* | z. B. `wmctrl -a {name}`. Wayland: leer lassen. |
| `SMOLIT_INTERACTION_ALLOW_TYPE_TEXT` | `false` | Kein Backend. Flag-Flip hat **keine** Wirkung. |
| `SMOLIT_INTERACTION_ALLOW_SHORTCUTS` | `false` | Kein Backend. |
| `SMOLIT_APPROVAL_TIMEOUT_SECONDS` | `20` | Approval-Wartezeit bis `timed_out`. |

### 3.5 UI / Overlay / Dev

| Variable | Default | Zweck |
| --- | --- | --- |
| `SMOLIT_UI_DEV_CONTROLS` | *leer* | `1` aktiviert Dev-Buttons, Audit-Panel, Demo-Approvals. **Nicht in Produktion setzen.** |
| `SMOLIT_WORKFLOW_OVERLAY` | *leer* | `1` blendet das Workflow Visibility Overlay v1 ein (UI-seitiges Toggle existiert ebenfalls). |
| `SMOLIT_UI_OVERLAY` | *leer* | `1` aktiviert transparentes, borderless Presence-Fenster. |
| `SMOLIT_UI_CLICK_THROUGH` | *leer* | `1` zusätzlich → Click-through im Leerraum. Braucht `SMOLIT_UI_OVERLAY=1`. |
| `SMOLIT_UI_ALWAYS_ON_TOP` | *leer* | `1` nur auf **echter X11-Session**; sonst honest No-op. |
| `SMOLIT_WINDOW_PROBE` / `_REVERT` | *leer / 1* | Einmaliger Runtime-Probe für Transparenz + Passthrough. |
| `SMOLIT_WINDOW_REPORT` | *leer* | `1` druckt einen konsolidierten Konsolen-Block mit Session / Driver / Caps. |

### 3.6 Audit

| Variable | Default | Zweck |
| --- | --- | --- |
| `SMOLIT_AUDIT_MAX_EVENTS` | `100` | Ring-Buffer-Grenze (hart max 1000). In-memory only. |

## 4. Kuratierte Beispiel-Umgebungen

### 4.1 Dev-Minimum (local-only, keine Cloud)

```bash
# .env (lokal, keine Sprache, keine Interaction)
ABRAIN_CMD=abrain
SMOLIT_IPC_BIND=127.0.0.1:8787
SMOLIT_UI_DEV_CONTROLS=1
```

### 4.2 Voice-Flow (whisper.cpp + Piper)

```bash
ABRAIN_CMD=abrain

SMOLIT_STT_ENABLED=true
SMOLIT_STT_WHISPER_CPP_CMD="/opt/whisper.cpp/main -m /opt/models/ggml-base.bin"
SMOLIT_STT_PROVIDER_CHAIN="whisper_cpp,command"

SMOLIT_TTS_ENABLED=true
SMOLIT_TTS_PIPER_CMD="piper --model /opt/piper/de-thorsten-low.onnx --output-raw"
SMOLIT_TTS_PROVIDER_CHAIN="piper,command"
SMOLIT_AUDIO_AUTO_SPEAK=true
```

Ist nur das Env gesetzt, aber `piper` nicht in der Chain, meldet
die Settings-Shell
`configured (via SMOLIT_TTS_PIPER_CMD), aber nicht in der Chain`.

### 4.3 `focus_window` auf X11 aktivieren

```bash
# Voraussetzung: echte X11-Session, wmctrl installiert.
SMOLIT_INTERACTION_ALLOW_FOCUS_WINDOW=true
SMOLIT_INTERACTION_FOCUS_WINDOW_CMD="wmctrl -a {name}"
# require_confirmation bleibt true → jede Fokussierung holt Approval.
```

### 4.4 `cloud_http` First-Run

```bash
# 1. .env: Endpoint + Enable
SMOLIT_CLOUD_HTTP_ENABLED=true
SMOLIT_CLOUD_HTTP_ENDPOINT=https://api.example.invalid/v1/chat/completions
SMOLIT_CLOUD_HTTP_MODEL=example-model

# 2. API-Key NICHT in .env. Stattdessen über die Settings-Shell
#    (Save Key-Button) oder IPC-Command `settings_set_cloud_http_secret`.
# 3. cloud_http der Chain hinzufügen — manuell über den Chain-Editor
#    in der Settings-Shell. Auto-Add ist deaktiviert (PR 26).
```

## 5. Troubleshooting

### 5.1 „WebSocket nicht erreichbar"

Symptom: UI zeigt `disconnected`, Ping schlägt fehl.

- **Läuft der Core?** `ps aux | grep smolit-assistant-core`.
- **Bind-Adresse?** Default `127.0.0.1:8787`. Kollidiert was? `ss -tlnp | grep 8787`.
- **Firewall?** Sollte bei Loopback kein Thema sein.
- **`SMOLIT_IPC_ENABLED=false` gesetzt?** Dann startet der Server nicht.

### 5.2 „STT not configured" / „TTS not configured"

```text
STT: enabled=true, available=false
```

Bedeutet: Achse ist an, aber `SMOLIT_STT_CMD` (bzw. für `whisper_cpp`
`SMOLIT_STT_WHISPER_CPP_CMD`) leer.

- `.env` auf den richtigen Command-String prüfen.
- Binary wirklich im PATH? Absoluter Pfad ist robuster.
- Ist `whisper_cpp` in `SMOLIT_STT_PROVIDER_CHAIN` enthalten?

### 5.3 Godot `.uid`-Dateien erscheinen

Ab Godot 4.4 legt der Editor `.uid`-Metadaten-Dateien neben
Scripts/Scenes an. Das Repo ignoriert sie via `.gitignore` (PR
`chore: ignore godot script .uid files`, d748521). Wenn du dennoch
welche staged siehst:

```bash
git status --ignored
# wird sie unter "Ignored files" auflisten
```

### 5.4 Wayland Always-on-top unsupported

Symptom: `SMOLIT_UI_ALWAYS_ON_TOP=1` tut unter GNOME/Wayland nichts.

Das ist **by design**. Unter GNOME/Mutter gibt es keinen
stabilen AOT-Primitiv über reguläre Toplevel-Hints; der Controller
verweigert explizit mit einem `reason` im Log. Siehe
[`docs/linux_always_on_top_decision.md`](linux_always_on_top_decision.md).

Workarounds:

- Echte X11-Session starten → AOT-Flag wird akzeptiert.
- Oder GNOMEs „Always on Top" im Fenster-Titelleistenmenü des
  Compositors benutzen (App-übergreifend, nicht unser Code).

### 5.5 `cloud_http_secret_present=true`, aber 401 vom Endpoint

`secret_present` ist nur ein **Boolean** aus dem Status — es sagt,
dass ein Key im Secrets-Store liegt, nicht dass der Key richtig ist.

- Prüfe, ob der Key aktuell ist (Provider-Konsole).
- Endpoint + Modell übereinstimmend? `SMOLIT_CLOUD_HTTP_ENDPOINT` und
  `SMOLIT_CLOUD_HTTP_MODEL` sind separate Env-Variablen.
- Der Key wird **nur** bei cloud_http-Requests im `Authorization`-
  Header verwendet; er taucht nie in Logs, Status-Payloads oder
  Probe-Responses auf (Security-Invariante, siehe PR 10/11-Scope im
  [`provider_fallback_and_settings_architecture.md`](provider_fallback_and_settings_architecture.md)).

### 5.6 `open_application` wird sofort mit `action_cancelled` beendet

Wahrscheinliche Ursachen:

1. **Template leer.** `SMOLIT_INTERACTION_OPEN_APP_CMD=""` → Backend
   meldet honest `BackendUnsupported`. Setze z. B.
   `gtk-launch {name}` oder `xdg-open {name}`.
2. **Approval timed out.** Default-Timeout 20 s. Approve in der UI
   drücken oder `SMOLIT_APPROVAL_TIMEOUT_SECONDS` erhöhen.
3. **`require_confirmation=false` + automatischer Fehler.** Ohne
   Confirmation gibt es keine zweite Chance; der Fehler aus dem
   Spawn wird direkt `action_failed`.

### 5.7 `focus_window` meldet `fallback_unavailable`

- **Kein Template gesetzt?** `SMOLIT_INTERACTION_FOCUS_WINDOW_CMD`
  muss gesetzt sein.
- **`allow_focus_window=false`?** Default. Flag setzen.
- **Wayland?** Unter Wayland gibt es kein Backend. Der Core verweigert
  ehrlich mit `BackendUnsupported("focus_window")`.

## 6. Was bei Setup-Problemen hilft

1. **`cargo test` grün?** Wenn nein: Toolchain / Rust-Version prüfen.
2. **`scripts/run_overlay_verification.sh settings-shell-smoke`
   grün?** Wenn nein: Godot-Version / headless-Fähigkeit prüfen.
3. **`SMOLIT_WINDOW_REPORT=1` auf der UI gestartet** druckt einen
   konsolidierten Konsolen-Block mit Session, Driver, Capabilities —
   ideal für Bug-Reports.
4. **Issues:**
   [github.com/Modularium/Smolit-Assistant/issues](https://github.com/Modularium/Smolit-Assistant/issues).

## 7. CI / Local verification parity

Seit PR 38 fährt GitHub Actions eine minimale CI-Linie
([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)):

| Job          | Was läuft                                                   |
| ------------ | ----------------------------------------------------------- |
| `core-test`  | `cargo test --manifest-path core/Cargo.toml --locked` auf `ubuntu-latest` mit Rust stable. |
| `ui-smoke`   | Godot 4.6 headless (offizielles Linux-Binary, pinned via `GODOT_VERSION`), fünf kuratierte Smokes: `settings-shell-smoke`, `avatar-render-polish-smoke`, `workflow-visibility-smoke`, `approval-card-smoke`, `audit-panel-smoke`. |

Beide Jobs setzen vor dem Testlauf **XDG-Isolation**:

```bash
XDG_CONFIG_HOME=${RUNNER_TEMP}/smolit-config
XDG_CACHE_HOME=${RUNNER_TEMP}/smolit-cache
```

`HOME` bleibt bewusst unverändert — rustup/cargo finden ihre
Toolchain relativ zu `$HOME/.cargo`, und Godot legt seine
User-Data ebenfalls HOME-relativ ab. Die Config-Isolation über
`XDG_CONFIG_HOME` ist die tatsächlich relevante Dimension: Smolit-
Core liest Konfiguration zuerst aus `$XDG_CONFIG_HOME/smolit-assistant/`;
der hier gesetzte leere Ordner stellt sicher, dass keine Host-
Artefakte hineinbluten. Das
ist genau die Klasse, die auf lokalen Dev-Hosts mehrmals stille
Failures ausgelöst hat (z. B. eine persistente `text_chain.json`, die
CI-Tests zu `[llamafile_local, local_http, abrain]` statt `[abrain]`
zwingt).

**Für einen lokalen Parity-Lauf** liegt
[`scripts/ci_verify.sh`](../scripts/ci_verify.sh) bei. Das Script
baut sich eine frische Temp-Isolation, ruft `cargo test` auf und —
wenn `godot` im PATH ist — die fünf Smokes. Ohne Godot bleibt es
ehrlich und überspringt den Smoke-Teil. Typische Nutzung:

```bash
scripts/ci_verify.sh            # voller Lauf
scripts/ci_verify.sh core       # nur cargo
scripts/ci_verify.sh smokes     # nur smokes (benötigt godot im PATH)
```

Bewusst **nicht** in CI heute (und nicht in diesem Setup-Guide):
Release-Tagging, Packaging-Formate (`.deb` / `.rpm` / Flatpak / Snap),
Docker-Images, Code-Signing, Auto-Publish, Secret-/Cloud-Provider-
Roundtrip-Tests. Die Entscheidung steht in ROADMAP.md § PR 38; eine
spätere Release-Line braucht einen eigenen ADR, bevor Code landet.

## 8. Nicht im Scope dieses Setup-Guides

- **Release-Pipeline / Artefakte** (`.deb`, `.rpm`, Flatpak, Snap,
  Docker-Images, signierte Releases, Auto-Update) — eigener Folge-PR
  (Workstream I, Post-PR 38).
- **Cloud-Deployment** — Smolit ist Desktop-first; kein Server-Modus.
- **smolitux-ui-Integration** — per ADR-0001 ausgeschlossen; Smolit
  bleibt Godot-nativ.
- **OceanData-Anbindung** — OceanData ist Data-Layer im Smolitux-
  Ökosystem, kein Teil dieses Repos. Ein zukünftiger Rahmen
  existiert als Proposed-ADR
  ([`docs/adr/ADR-0004-oceandata-data-layer-integration.md`](./adr/ADR-0004-oceandata-data-layer-integration.md));
  dieser Setup-Guide dokumentiert keine OceanData-Installation, weil
  es keine gibt.
