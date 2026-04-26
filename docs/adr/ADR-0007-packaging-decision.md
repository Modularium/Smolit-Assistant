# ADR-0007: Packaging Strategy for Smolit-Assistant

- **Status:** Proposed (Docs/ADR-only — keine Packaging-Implementation
  in PR 52).
- **Date:** 2026-04-26.
- **Deciders:** Smolit-Assistant Maintainer.
- **Scope:** Reihenfolge und Form der zukünftigen Linux-Desktop-
  Distributionspfade für Smolit-Assistant (Rust-Core + Godot-UI +
  externe Command-Tools). **Nicht** Teil dieses ADR: konkretes
  AppImage-/`.deb`-/Flatpak-Build-Skript, Export-Presets, Signing-
  Keys, Auto-Update-Server, Cloud-Build-Pipeline, Windows/macOS,
  AdminBot/OceanData/ABrain-/smolitux-ui-Repos.
- **Workstream:** I (Packaging / Release / CI) — Folgearbeit nach
  v0.2-Release-Tag (siehe
  [`docs/reviews/PR50_V0_2_RELEASE_GATE_REVIEW.md`](../reviews/PR50_V0_2_RELEASE_GATE_REVIEW.md)
  und [`docs/reviews/PR51_V0_2_GATE_FIX.md`](../reviews/PR51_V0_2_GATE_FIX.md)).
- **Related:**
  [`ADR-0001`](./ADR-0001-smolitux-design-contract.md),
  [`ADR-0002`](./ADR-0002-accessibility-rpc-readonly.md),
  [`ADR-0005`](./ADR-0005-adminbot-safety-boundary.md);
  [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md);
  [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md);
  [`docs/linux_window_overlay_architecture.md`](../linux_window_overlay_architecture.md);
  [`docs/wayland_always_on_top_refusal_results.md`](../wayland_always_on_top_refusal_results.md).

> Leitprinzip: **Decide packaging before building packages.**
> Dieser ADR fixiert *welcher* Distributionspfad zuerst kommt,
> *welche* explizit nicht, und *welche Vorbedingungen* (Signing,
> Permissions, Update-Modell) erfüllt sein müssen, bevor ein
> binäres Release über die heutige Source-/Dev-Linie hinausgeht.
> Er ist **kein** Build-Skript, **kein** Manifest, **kein** Code.

---

## 1. Status

**Proposed.** Es gibt heute keinen Codepfad und keine Build-
Konfiguration, die ein binäres Linux-Desktop-Artefakt erzeugt. Der
v0.2.0-Release ([Tag](https://github.com/Modularium/Smolit-Assistant/releases/tag/v0.2.0))
trägt **keine** Binär-Anhänge. Status wird auf **Accepted** angehoben,
sobald

- ein erster reproduzierbarer Local-Build-Helper (Phase P1, kein
  Installer) gelandet ist, und
- mindestens einer der Phasen P2 (AppImage-Prototyp) oder P5
  (Signing/Update-Policy) als eigener Folge-PR konzipiert ist —
  jeweils mit eigenem ADR-Update oder eigenem Folge-ADR.

Eine Status-Erhöhung passiert **nicht** allein dadurch, dass jemand
ein AppImage / `.deb` / Flatpak baut; sie braucht zusätzlich eine
explizite Anpassung von §11 (Signing) und §13 (Install/Update).

## 2. Date

2026-04-26.

## 3. Context

v0.2.0 ist der erste stabile Runtime-/Contract-Baseline-Release des
Projekts. Die heute unterstützte Installations- und Startform ist:

- **Source-Checkout** via `git clone` (siehe
  [README §5 Quick Start](../../README.md)).
- **Rust-Core** via `cargo build --manifest-path core/Cargo.toml`
  und `cargo run --manifest-path core/Cargo.toml`.
- **Godot-UI** via `godot --path ui` mit Godot 4.6.
- **Verifikation** via [`scripts/ci_verify.sh`](../../scripts/ci_verify.sh)
  (XDG-isoliert) und [`scripts/run_overlay_verification.sh`](../../scripts/run_overlay_verification.sh).

GitHub-Actions-CI ([`ci.yml`](../../.github/workflows/ci.yml)) läuft
Tests + UI-Smokes auf `ubuntu-latest`. Sie baut **keine** Binaries,
lädt **keine** Artefakte hoch, signiert **nichts**.

Packaging muss vier Realitäten berücksichtigen, die der Source-Pfad
heute schon offenlegt:

1. **Zwei Runtimes.** Godot-UI-Binary plus Rust-Core-Binary. Beide
   müssen aufeinander finden (heute über `127.0.0.1:8787`-Loopback,
   siehe [`docs/api.md`](../api.md)). Ein Single-File-Bundle muss
   beide Prozesse starten oder ein klar dokumentiertes Start-Skript
   mitliefern.
2. **WebSocket-IPC-Boundary.** Default-Bind ist Loopback und darf
   beim Packaging nicht gehärtet *aus Versehen* aufgeweicht werden
   (z. B. Flatpak-`--share=network` ohne Begründung).
3. **User-scoped Config + Secrets.** `~/.config/smolit-assistant/`
   für Settings, separater 0600-Secrets-Store. Jeder Sandbox-Pfad
   (Flatpak, Snap) braucht ein bewusstes Mapping.
4. **Linux-Desktop-Wahrheiten.** Wayland verweigert Always-on-top
   (siehe
   [`docs/wayland_always_on_top_refusal_results.md`](../wayland_always_on_top_refusal_results.md)),
   X11 erlaubt es per Opt-in. `focus_window` braucht `wmctrl` o. ä.
   und ist Wayland-unsupported. AT-SPI-Pfade sind hinter
   [ADR-0002](./ADR-0002-accessibility-rpc-readonly.md) entschieden,
   nicht implementiert. Ein Packaging-Format darf **keinen**
   Eindruck erwecken, diese Grenzen würden durch das Bundle
   verschwinden.

Packaging darf außerdem *keine falschen Versprechen* machen:

- **Keine** AdminBot-/Shell-/Sudo-Erwartung beim Install.
- **Kein** native `abrain_native`-Provider (ist
  [ADR-0003](./ADR-0003-abrain-native-integration.md) Future Work).
- **Kein** native OceanData-Adapter (ist
  [ADR-0004](./ADR-0004-oceandata-data-layer-integration.md) /
  [ADR-0006](./ADR-0006-oceandata-context-provider-spi.md) Future Work).
- **Keine** persistente Audit-Storage (Ring-Buffer bleibt in-memory,
  siehe [`docs/security/AUDIT_TRAIL.md`](../security/AUDIT_TRAIL.md)).
- **Kein** Auto-Updater vor Signing-Entscheidung (siehe §11).

## 4. Decision

Smolit-Assistant verfolgt eine **gestufte, Linux-Desktop-zuerst**
Packaging-Strategie. Die Entscheidung in diesem ADR betrifft nur
die *Reihenfolge* und die *Eintrittskriterien* — kein Format wird
in PR 52 implementiert.

**Phase 1 — Source/Dev bleibt offiziell unterstützt.** Der
heutige Source-Checkout-Pfad bleibt bis auf Weiteres die kanonische
Entwickler-/Tester-Form. README + `docs/SETUP.md` bleiben die
Single-Source. Kein Packaging-Format ersetzt diesen Pfad.

**Phase 1 zusätzlich — AppImage als erster binärer Linux-Desktop-
Kandidat.** Sobald ein reproduzierbarer Local-Build-Helper (P1)
existiert, ist **AppImage** der erste Binär-Format-Kandidat
(Phase P2). AppImage braucht keine systemweite Service-
Installation, keinen Paketmanager, kein Repository-Hosting. Es ist
das einfachste Format, um den Source-/Dev-Run mit dem geringsten
Linux-Desktop-Reibungsverlust zu spiegeln.

**Phase 2 — `.deb` für Ubuntu/Debian** *erst nachdem* der
AppImage-Prototyp stabil ist (P3). `.deb` ist im Smolit-Ziel-
Profil (Ubuntu 24.04 / GNOME) der nächste sinnvolle Distributions-
weg, braucht aber zusätzlich ein Install-/Service-/Path-Konzept
(siehe §9, §13). `.deb` kommt **nicht zuerst**, weil die Install-
Konventionen auf Debian-Seite mehr Designentscheidungen
voraussetzen, als heute getroffen sind.

**Phase 3 — Flatpak-Evaluation** (P4). Flatpak braucht eine
explizite Permission-/Portal-Entscheidung für: Loopback-Socket
(IPC), Settings-/Secrets-Store, optionale Desktop-Interaktion
(`open_application`, `wmctrl`-Template), Audio (TTS/STT-Commands),
Accessibility (`org.a11y.Bus` für eine spätere
[ADR-0002](./ADR-0002-accessibility-rpc-readonly.md) FA-1).
Flatpak ist nicht „erst Phase 3 weil schwer", sondern weil seine
Permissions **die Sicherheitsaussagen des Cores spiegeln müssen**;
das verlangt eigene Design-Runden.

**Nicht zuerst:**

- **Snap** — primär Ubuntu-Store, fügt eine zweite
  Sandbox-/Confinement-Achse parallel zu Flatpak hinzu. Kein
  Vorteil, der nicht bereits durch AppImage + spätere Flatpak-
  Evaluation abgedeckt wäre.
- **Docker als Desktop-App-Distribution** — Container-Image passt
  nicht als primärer Desktop-Distribute-Pfad für eine GUI mit
  Avatar/Overlay/IPC-Loopback und systemnaher Interaction-
  Surface. Container bleiben sinnvoll für CI/Headless-Testen,
  nicht für „install den Assistant".
- **`.rpm`** — nicht im Ziel-Profil (Ubuntu 24.04 primary).
  Kommt höchstens als späterer Distribution-Pull, nicht als
  Push.
- **Windows / macOS** — out-of-scope für die nahe Zukunft. Kein
  Wayland-/X11-/AT-SPI-Pendant; `focus_window` und Overlay-Pfade
  hängen heute explizit am Linux-Desktop.

**Begründung in einem Satz.** AppImage ist für früh-stabile
Linux-Desktop-Tester einfacher als `.deb` und braucht weniger
Sandbox-Vorentscheidungen als Flatpak; `.deb` ist für die Ziel-
Distro Ubuntu 24.04 der „native" Pfad, braucht aber zuerst ein
Install-/Service-/Path-Konzept; Flatpak ist langfristig
strategisch für Multi-Distro-Linux-Desktop, braucht aber zuerst
eine Portal-/Permission-Entscheidung; Snap und Docker bringen
keinen zusätzlichen Wert für Smolit-Assistants Desktop-Profil.

## 5. Packaging options considered

| Option | Pros | Cons | Decision |
| ------ | ---- | ---- | -------- |
| **Source checkout** *(heute)* | Vollkontrolle; deckt Dev + Tester; keine zusätzliche Build-Pipeline; CI bereits parity. | Erfordert Rust + Godot vor Ort; nicht für Endnutzer ohne Toolchain. | **Bleibt offiziell unterstützt** als Phase P0. |
| **Reproducible local build script (P1)** | Brückt Source → Binary, bleibt aber im Repo; kein Installer; keine Toolchain-Erwartung am Endnutzer-Host (sondern am Builder-Host); deterministische Ausgabe. | Kein User-facing-Installer; nur Vorstufe. | **Eintritt vor allem Binär-Packaging** (Phase P1). |
| **AppImage (P2)** | Single-File; kein Paketmanager nötig; keine systemweite Service-Installation; gut für Tester ohne Adminrechte; einfachstes Format um Source-Parity zu prüfen. | Kein Auto-Update ohne `AppImageUpdate`-Konvention; Sandbox-Garantien begrenzt; FUSE-Anforderung; AT-SPI/Audio über Host-Pfade. | **Erste binäre Empfehlung (Phase P2).** |
| **`.deb` für Ubuntu/Debian (P3)** | Native Install auf Ziel-Distro; vertrautes `apt`-Modell; einfache Service-Pfade. | Braucht Install-/Path-Konzept (`/usr/bin` vs. `/opt`), eigene Service-Definition falls Core als systemd-User-Service laufen soll, Repository-Hosting für Updates, ggf. Dependency-Liste auf Distro-Pakete. | **Phase P3, erst nach AppImage.** |
| **Flatpak (P4)** | Multi-Distro; saubere Sandbox; klare Portal-Modelle für Filesystem/Audio/A11y; gute Update-Story über Flathub. | Permission-/Portal-Modell braucht eigene Designrunde (Loopback-Socket, Secrets-Store, `open_application`, AT-SPI, Audio); Sandbox kann Funktionen wie `wmctrl`-Template verhindern; eigener Build-Prozess. | **Phase P4, evaluation, nicht implementation.** |
| **Snap** | Zentral im Ubuntu-Store, eigenes Update-System. | Zweite Sandbox-Achse neben Flatpak ohne klaren Mehrwert; Confinement-Konflikte mit Desktop-Interaction-Pfaden plausibel; Store-Bindung an Canonical. | **Bewusst nicht.** |
| **Docker image** | Reproduzierbare Headless-Runs (CI). | Falsches Distribute-Modell für GUI-Desktop-App mit IPC-Loopback und Desktop-Interaction; macht das Sicherheitsmodell schwerer zu erklären, nicht leichter. | **Bewusst nicht** als Desktop-Distribute-Pfad; bleibt für CI/Headless legitim. |
| **`tar.gz` portable bundle** | Simpel; null-Sandbox; kein FUSE; gut als Backup-Pfad. | Keine Desktop-Integration (`.desktop`-Datei, Icon-Theme); kein Update; keine Signaturkette. | **Optional** als Fallback parallel zu AppImage, nicht primär. |
| **Distro packages later (Arch AUR / Fedora COPR / Nix Flake)** | Community-getrieben, niedriger Maintenance-Aufwand für uns. | Wartungs-Drift; Sicherheitsversprechen schwer zu halten ohne Owner-Audit. | **Nicht aktiv pushen**, bei Pull akzeptieren. |
| **Windows / macOS** | Größerer Nutzerkreis. | Kein Wayland/X11-/AT-SPI-Pendant; Overlay/`focus_window`-Pfade greifen nicht; massiver Designoverhead. | **Out-of-scope** auf Sicht. |

## 6. Recommended packaging sequence

Die Sequenz ist **konservativ, Docs/Build vor Distribution**, und
jede Phase braucht eigene Folge-PRs. Phasen P0–P6 sind **Reihenfolge**,
nicht Termin.

### P0 — Source checkout *(current, no work)*

- **Ziel:** Heutiger Pfad aus README §5 + `docs/SETUP.md` bleibt
  offiziell.
- **Eintrittskriterien:** Bereits erfüllt durch v0.2.0.
- **Nicht-Ziele:** keine Änderung am Quick-Start; kein Versprechen
  von „Installer kommt bald".

### P1 — Reproducible local build script *(no installer)*

- **Ziel:** Ein Helper, der `cargo build --release` + Godot-Export
  + Bundle-Layout deterministisch lokal erzeugt — Output landet
  unter `target/` oder `dist/` im Repo, nicht systemweit.
- **Eintrittskriterien:** Godot-Export-Presets entschieden (siehe
  §8). Kein neuer Provider-Kind, kein neuer IPC-Command.
- **Nicht-Ziele:** kein AppImage-Bau; keine Installation; kein
  Auto-Run nach Bau; keine GitHub-Releases-Anhängung.

### P2 — AppImage prototype

- **Ziel:** Aus dem P1-Bundle ein lauffähiges AppImage erzeugen
  (Linux-Desktop, ohne Adminrechte, ohne Paketmanager).
- **Eintrittskriterien:** P1 stabil; SHA512-Checksum-Erzeugung ist
  Teil des Helpers; Release-Notes erklären Wayland-/X11-Grenzen
  (§8).
- **Nicht-Ziele:** keine Signing-Chain; kein AppImageUpdate; kein
  Hochladen auf Flathub; keine Auto-Aktualisierung.

### P3 — `.deb` prototype (Ubuntu/Debian)

- **Ziel:** Ubuntu-24.04-`.deb`, das Core + UI installiert,
  optional ein systemd-*User*-Service-Stub mitliefert (default-off),
  und `wmctrl`/Audio-Commands als optionale Dependencies markiert.
- **Eintrittskriterien:** Install-/Path-Konzept aus §9 + §10 +
  §13 entschieden; klare Antwort auf „User-Daten unter
  `~/.config/`?"; klare Antwort auf „Installation als root
  oder nur per User-Service?".
- **Nicht-Ziele:** keine systemweite root-Service-Aktivierung als
  Default; keine apt-Repository-Bereitstellung in dieser Stufe;
  kein Auto-Restart der Core-Binary.

### P4 — Flatpak evaluation

- **Ziel:** Schreiben eines Manifest-Entwurfs **plus** eines
  expliziten Permission-/Portal-Reviews. Output ist primär ein
  *Folge-ADR* (ADR-0008 oder höher), nicht zwangsläufig ein
  veröffentlichtes Flatpak.
- **Eintrittskriterien:** P2/P3 lieferten genug Erfahrung mit
  Bundle-Layout; AT-SPI- und Audio-Pfade sind in der gewünschten
  Sandbox-Form geklärt; Wayland-Compositor-Grenzen sind explizit
  in Release-Notes adressiert.
- **Nicht-Ziele:** keine Flathub-Veröffentlichung in P4; keine
  Sandbox-Loopback-Lockerung ohne ADR.

### P5 — Signing / update policy

- **Ziel:** Eigener ADR (Folge-PR) für: Schlüssel-Management,
  Release-Signaturen, Auto-Update-Mechanismus *oder* manuelles
  Update als Default, Provenance.
- **Eintrittskriterien:** Mindestens ein binäres Format aus
  P2/P3 ist real veröffentlicht und hat reale Tester.
- **Nicht-Ziele:** kein Auto-Update vor diesem Schritt;
  keine Signing-Schlüssel im Repo.

### P6 — Multi-distro matrix

- **Ziel:** Cross-Linux-CI-Matrix (Ubuntu 24.04 + Arch-Container
  + ggf. Fedora) und/oder akzeptierte Community-Pull-Pakete (AUR /
  COPR / Nix-Flake).
- **Eintrittskriterien:** P5 abgeschlossen; Trust-Modell für
  Community-Pakete dokumentiert.
- **Nicht-Ziele:** kein Push in Distros, die wir nicht selbst
  unterstützen können; kein Snap.

## 7. Linux desktop target

- **Primärziel:** Ubuntu 24.04 LTS, GNOME-Session. X11 zusätzlich
  unterstützt für `focus_window`-Opt-in und Always-on-top
  ([siehe X11-AOT-Decision](../linux_always_on_top_decision.md)).
- **Best-effort:** andere Linux-Desktops (KDE, XFCE) — solange der
  Loopback-IPC + GTK/Qt-unabhängige Godot-UI laufen, ist nichts
  spezifisch zu tun. Keine Versprechen über Compositor-spezifische
  AOT-/Overlay-Erweiterungen.
- **Out-of-scope:** Windows, macOS, ChromeOS, Mobile.

## 8. Godot export considerations

- **Godot 4.6.x ist gepinnt** (CI: `GODOT_VERSION` +
  `GODOT_SHA512`). Packaging muss derselben Version folgen.
- **Export-Presets müssen eingeführt werden, bevor irgendein
  binäres UI-Artefakt gebaut wird.** Kein Bundle entsteht aus
  einem Live-Editor-Run.
- **Keine User-Uploads / keine Asset-Pipeline in Packaging-PRs.**
  Stage-C-Avatar-Research bleibt Research-Gate (siehe
  [`docs/avatar_stage_c_research.md`](../avatar_stage_c_research.md)).
- **Headless-Smokes bleiben Verifikation.** Pixeltests sind nicht
  Teil von v0.2 und auch nicht Teil von P2/P3.
- **Wayland-/X11-Grenzen sind Release-Notes-Pflicht.** Jedes
  binäre Release-Artefakt erwähnt: AOT funktioniert nur unter X11
  (Opt-in), Wayland-`focus_window` ist `BackendUnsupported`,
  AT-SPI-RPC ist nicht implementiert.

## 9. Rust Core packaging considerations

- **Core-Binary muss zusammen mit der UI ausgeliefert oder
  zuverlässig gefunden werden.** Default ist *bundled mit der UI*.
  Ein getrenntes Deployment (`.deb` + System-Service) ist möglich,
  aber nicht Default vor P5.
- **IPC-Bind-Default bleibt Loopback** (`127.0.0.1:8787`). Kein
  Packaging-Format öffnet diesen Bind.
- **Keine systemweite Service-Installation im ersten Schritt.**
  Wenn Core als systemd-User-Service läuft, dann opt-in mit
  default-off Unit-File.
- **Keine root-/sudo-Erwartung** beim Install. Kein Postinst-Skript
  ändert systemweite Configs ohne Default-off.
- **Keine AdminBot-/Shell-Rechte** — siehe
  [ADR-0005](./ADR-0005-adminbot-safety-boundary.md). Packaging
  darf nicht implizit Capabilities erweitern, die der Core selbst
  fail-closed hält.
- **Config bleibt user-scoped** (`~/.config/smolit-assistant/`).
- **Secrets bleiben 0600**, user-scoped, nie im Bundle.

## 10. Runtime dependencies

Das Bundle zieht **keine** der folgenden Tools, sondern erkennt
sie zur Laufzeit über die heute schon dokumentierten Env-Variablen
(siehe README §6 + [`docs/SETUP.md`](../SETUP.md)):

- **Godot-Runtime / Export-Templates** — Pflicht im Bundle (siehe §8).
- **Rust-Core-Binary** — Pflicht im Bundle (siehe §9).
- **ABrain-CLI** (`SMOLIT_ABRAIN_CMD`) — optional; nicht gebundled.
- **STT-Command** (`SMOLIT_STT_CMD`) — optional.
- **whisper.cpp-Command** (`SMOLIT_STT_WHISPER_CPP_CMD`) — optional.
- **TTS-Command** (`SMOLIT_TTS_CMD`) — optional.
- **piper-Command** (`SMOLIT_TTS_PIPER_CMD`) — optional.
- **`open_application`-Template** — optional, kommt aus Distro
  oder User-Pfad.
- **`focus_window`-Template** (z. B. `wmctrl`) — optional, X11-only,
  Opt-in.

**Keine Modell-Downloads.** Packaging zieht keine LLM-Gewichte,
keine STT-/TTS-Modelle. Das bleibt User-Verantwortung — jede
andere Wahl bräuchte eine eigene Datenschutz-/Lizenz-Runde.

## 11. Security / signing expectations

- **Checksums sind Pflicht** für jedes binäre Release-Artefakt
  (Phase P2 aufwärts) — analog zur SHA512-Praxis im CI für das
  Godot-Binary.
- **Signing ist Pflicht**, bevor wir „stable binary distribution"
  behaupten. Vor P5 ist jede binäre Veröffentlichung ausdrücklich
  als *Prototype/Preview* zu kennzeichnen.
- **Kein Auto-Update** vor P5. Updates erfolgen manuell durch
  Nutzer; das vermeidet eine implizite Trust-Chain ohne explizite
  Schlüssel-Strategie.
- **Keine Secrets im Package.** Packaging darf keine API-Keys,
  Tokens, Provider-Endpunkte einbacken.
- **Keine breite Filesystem-Permission** als Default. Insbesondere
  Flatpak (P4) startet mit minimalem Manifest und erweitert nur
  per ADR-Begründung.
- **Flatpak braucht Permission-Review** (P4) bevor Veröffentlichung.
- **AppImage braucht Checksum + Provenance** (P2) als Minimum,
  Signing folgt in P5.

## 12. CI / release pipeline expectations

- **Aktuelle CI tested nur** ([`ci.yml`](../../.github/workflows/ci.yml)):
  `core-test` + `ui-smoke`. Keine Build-Artefakte, keine
  Packaging-Schritte.
- **Packaging-CI ist Future Work.** Sobald sie kommt:
  - **Läuft nach Tests**, nicht parallel — ein roter Test
    blockiert das Artefakt.
  - **Build in isolated environment**, kein Shared-Cache
    außerhalb des reproduzierbaren Helpers (siehe P1).
  - **Artefakte nur auf Tag/Release-Workflow** anhängen, nicht
    pro PR.
  - **Checksums werden im Workflow berechnet** und veröffentlicht.
  - **Keine Secrets** für normalen Build (Signing-Keys ggf. nur
    im Tag-Release-Workflow, hinter Environment-Schutz).
- **Kein Auto-Publish** vor manueller Approval. Auch nach P5 muss
  ein Maintainer den Tag bewusst freigeben, Branch-Protection-
  Disziplin (siehe [`docs/ci/BRANCH_PROTECTION.md`](../ci/BRANCH_PROTECTION.md))
  bleibt.

## 13. Install / update model

- **Install heute:** `git clone` + `cargo build` + `godot --path ui`.
  Bleibt offiziell.
- **Install P2 (AppImage):** Download → `chmod +x` → run.
  Update = neues AppImage runterladen; kein Auto-Update.
- **Install P3 (`.deb`):** `apt install ./smolit-assistant_<ver>.deb`.
  Update = `apt upgrade` *erst* nachdem ein Repository-Modell
  entschieden ist (eigener Folge-ADR oder Notiz in P5).
- **Install P4 (Flatpak):** `flatpak install` aus eigenem
  Manifest oder Flathub. Update via Flatpak-System.
- **User-Daten bleiben unter `~/.config/smolit-assistant/`**, auch
  unter Flatpak (Portal-Mapping). Niemals in
  `/etc/smolit-assistant/` als Default.
- **Uninstall ist verlustfrei** für Code; User-Daten werden nur
  auf explizite Bestätigung mitentfernt.

## 14. Non-goals

- **Kein Packaging-Code in PR 52.** Dieser ADR ist Docs-only.
- **Keine Export-Presets in PR 52.** Sie kommen mit P1, in eigenem PR.
- **Kein AppImage bauen.** Kommt mit P2.
- **Kein `.deb` bauen.** Kommt mit P3.
- **Kein Flatpak-Manifest.** Kommt mit P4-Evaluation, ggf. als ADR.
- **Kein Dockerfile** für Desktop-Distribution.
- **Kein Signing in PR 52.** Kommt mit P5.
- **Kein Installer.** Kommt mit P3 frühestens.
- **Kein Auto-Updater.** Kommt mit P5 frühestens, falls überhaupt.
- **Kein Version-Bump** in PR 52. v0.2.0 bleibt aktueller Tag.
- **Kein neuer Release** durch PR 52.
- **Keine Provider-/IPC-/UI-/Core-Änderung** durch PR 52.
- **Keine ABrain/AdminBot/OceanData/smolitux-ui-Änderung** durch PR 52.
- **Keine Snap-Strategie.**
- **Kein Windows-/macOS-Pfad** auf Sicht.

## 15. Future work

- **FA-1 — Reproducible local build script** (P1).
- **FA-2 — Godot Export Presets** (Voraussetzung für P1/P2).
- **FA-3 — AppImage Prototype + Checksum** (P2).
- **FA-4 — `.deb` Prototype** (P3).
- **FA-5 — Flatpak Permission Review ADR** (P4) — als eigener
  ADR (ADR-0008 oder höher), spiegelt Loopback-Socket / Secrets /
  Audio / AT-SPI-Permissions.
- **FA-6 — Signing & Update Policy ADR** (P5) — Schlüssel-
  Management, Release-Signaturen, Auto-Update-Frage.
- **FA-7 — Multi-distro CI Matrix** (P6).
- **FA-8 — Release Notes Template**, das Wayland-/X11-/`focus_window`-
  Realität explizit adressiert (siehe §8).
- **FA-9 — Re-Evaluation Snap / Docker** *(optional, nicht
  priorisiert)* — falls externe Anforderung explizit auftaucht.

Jeder dieser Punkte ist ein *eigener* PR mit eigener
Verifikation; keiner ist durch PR 52 als „nächster" gesetzt.
