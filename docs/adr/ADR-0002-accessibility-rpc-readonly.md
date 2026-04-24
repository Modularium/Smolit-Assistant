# ADR-0002: Accessibility RPC Spike — Read-only AT-SPI

- **Status:** Accepted (Decision only — keine Code-Implementation).
- **Date:** 2026-04-24
- **Deciders:** Smolit-Assistant Maintainer
- **Scope:** Core (`core/src/interaction/accessibility.rs` und
  zukünftige AT-SPI-RPC-Ergänzung). Nicht Teil dieses ADR: UI,
  Policy-Engine, Desktop-Automation.
- **Workstream:** F — Desktop Interaction Layer.

---

## Context

Der Interaction-Layer hat heute zwei voneinander getrennte
Capability-Pfade:

1. **`CommandBackend`** für real verdrahtete Aktionen: `open_application`
   (approval-gated by default seit PR 25) und `focus_window` (X11-only,
   doppeltes Opt-in seit PR 23 / Policy v0). `type_text` und
   `send_shortcut` bleiben ausdrücklich `BackendUnsupported` — kein
   Backend, kein Fallback.
2. **Accessibility-Spike** (`core/src/interaction/accessibility.rs`,
   512 Zeilen + Tests): environment-basierte Probe plus ein
   „Hint-Echo"-Discovery-Pfad. Siehe [`docs/api.md` §2.8](../api.md) und
   [`docs/presence_desktop_interaction.md` §8](../presence_desktop_interaction.md).

Der Spike ist bewusst so minimal, dass er **nie** gegen eine echte
AT-SPI-Registry spricht:

- `AccessibilityProbe::detect()` prüft nur Env-Variablen
  (`XDG_SESSION_TYPE`, `WAYLAND_DISPLAY` / `DISPLAY`,
  `DBUS_SESSION_BUS_ADDRESS`, optional existiert der Unix-Socket).
- `discover_top_level()` emittiert heute garantiert `Uncertain { items: [] }`
  auf einem plausiblen Linux-Desktop — „Umgebung sieht richtig aus,
  wir sprechen aber kein AT-SPI-RPC".
- `inspect_target(hint)` liefert ein einziges Item mit
  `confidence=discovered` und `source=accessibility_hint_echo` — ein
  ins Schema gehobenes Echo des Caller-Hints, ohne eigenständige
  Bestätigung gegen die Registry.
- `DiscoveryConfidence::Verified` ist **reserviert**; der Spike
  emittiert nie `verified`. Das ist ein bewusster Ehrlichkeits-Guard:
  eine falsche Registry-Bestätigung wäre ein Sicherheits-Signal, das
  nicht belegbar ist.

Für die Roadmap (Workstream F) stand die Frage offen, ob / wie ein
echter AT-SPI-RPC-Pfad folgen soll. Die Unsicherheiten sind bekannt:

- **Toolkit-Fragmentierung.** GTK, Qt, Electron/Chromium und
  terminalbasierte UIs exportieren Accessibility unterschiedlich
  vollständig. Ein Registry-Tree ist kein gleichförmiger Baum.
- **Wayland-Kompatibilität.** AT-SPI-Registry-Zugriff selbst
  funktioniert unter Wayland, das **Fokussieren** eines entdeckten
  Targets braucht jedoch zusätzliche Compositor-/Portal-Primitive,
  die nicht generisch verfügbar sind.
- **D-Bus-Permissions.** Manche Session-Setups (Flatpak-Sandboxen,
  eingeschränkte Seats) verwehren Accessibility-Reads ohne explizite
  Freigabe.
- **Missbrauchsrisiko.** Ein generischer Accessibility-RPC-Pfad in
  Kombination mit Input-Injektion würde den Approval-/Policy-Layer
  komplett umgehen. Das verletzt die Leitlinie „Control > Autonomy".

## Decision

### D1 — Accessibility-RPC bleibt **read-only**

Ein zukünftiger AT-SPI-RPC-Pfad in `core/src/interaction/accessibility.rs`
darf ausschließlich **lesen** — konkret:

- **Registry-Root-`GetChildren`** auf dem AT-SPI-Registry-Service
  (`org.a11y.atspi.Registry` auf dem Accessibility-Bus, erreichbar
  via `org.a11y.Bus/GetAddress` auf der Session-Bus).
- Lesen von Kind / Rolle / Name / App-Name pro Top-Level-Element.
- **Kein** Baum-Walk über mehr als eine Tiefe (keine transitiven
  `GetChildren`-Kaskaden) in diesem Spike. Ein Tiefen-Walker wäre
  ein separater ADR.
- **Kein** `SetCaretOffset`, kein `DoAction`, kein Methoden-Aufruf,
  der einen Seiteneffekt im beobachteten Prozess auslöst.

### D2 — Keine Input-Injektion aus Accessibility heraus

Ein entdecktes `AccessibilityItem` erzeugt **niemals** einen
Klick-/Tipp-/Shortcut-Befehl. Es darf:

- An `Selection` gehängt werden (der bestehende `target_selected`-Slot,
  siehe [`docs/api.md` §2.9](../api.md)).
- Als Kontext für einen **separaten** Interaction-Kind verwendet werden,
  der eigenen Policy-Pfad hat (heute: `open_application`, `focus_window`).
- Keine stille Eskalation von `discovered` zu ausführbarem Befehl.

Konkret: weder `type_text` noch `send_shortcut` bekommen einen Backend-
Pfad durch diesen Spike. Diese beiden Kinds bleiben `BackendUnsupported`
bis ein eigener ADR (E-Workstream-Policy) sie entsperrt.

### D3 — `verified` nur mit Registry-Evidenz

Ein Discovery-Item bekommt `confidence: verified` nur dann, wenn:

- der Aufruf über den echten AT-SPI-RPC-Weg ging (nicht Hint-Echo),
- das Item aus einem `GetChildren`-Ergebnis am Registry-Root stammt
  (kein geratenes Top-Level), und
- Rolle + Name direkt aus den jeweiligen AT-SPI-Attributen gelesen
  wurden.

Solange eine dieser drei Bedingungen nicht erfüllt ist, bleibt das
Item `discovered`. Der Spike darf **keine** UI-/Heuristik-Upgrades
nach `verified` erlauben — das Feld ist Core-gesteuert.

### D4 — Kandidaten-Bibliothek: `atspi` + `zbus` (Rust)

Wenn ein echter RPC-Pfad kommt, soll er die Rust-Bibliothek
[`atspi`](https://crates.io/crates/atspi) (über [`zbus`](https://crates.io/crates/zbus))
nutzen. Begründung:

- **Nativ Rust**, keine FFI-Brücke, keine C-Dependencies außerhalb
  von D-Bus selbst.
- **zbus** spricht Session-Bus und Accessibility-Bus ohne zusätzlichen
  nativen Stack.
- **`atspi`** hält die generierten Proxies für `Registry`, `Accessible`,
  `Application` und deckt genau den read-only Teil ab, den D1 erlaubt.
- **Sync/async-Toggle**: `atspi` hat einen blocking- und einen async-
  Adapter; der Core kann die async-Variante in den bestehenden
  Tokio-Runtime hängen, ohne einen zusätzlichen Thread-Pool.

Alternativen und warum sie *nicht* gewählt werden:

- **`libatspi` via `pyo3`/`cxx`-Bindung** — bringt eine
  C-Bibliotheksabhängigkeit auf Build-Farm und Distributionsseite.
  `atspi`+`zbus` halten den Build-Graph rein Rust.
- **Eigene D-Bus-Introspektion mit `dbus-rs`** — funktionierte, aber
  heißt AT-SPI-XML selbst zu pflegen. `atspi` macht genau das
  idiomatisch.
- **AT-SPI-RPC via Shell-Helper (`busctl` / `dbus-send`)** — wäre ein
  zusätzlicher Command-Provider; hat das gleiche Toolkit-Problem,
  nur mit mehr Parsing-Schmerz.

### D5 — Session-Bus-Anforderungen

Der RPC-Pfad braucht:

- `DBUS_SESSION_BUS_ADDRESS` gesetzt (wird heute in der Probe
  geprüft).
- Eine erreichbare `org.a11y.Bus`-Registrierung. Fehlt sie, liefert
  der RPC-Pfad `AccessibilityDiscovery::Unavailable` mit einer
  eindeutigen Reason — **kein** Degrade auf Hint-Echo unter
  stillschweigendem `Verified`-Rückfall.
- Auf Flatpak: die Session braucht die `--talk-name=org.a11y.Bus`-
  Permission. Ohne diese Permission liefert der RPC-Pfad
  `Unavailable { reason: "… permission denied on org.a11y.Bus" }`.

### D6 — Wayland vs. X11 auf Accessibility-Ebene

Der Accessibility-Lesepfad ist unter Wayland **und** X11 in diesem
Spike identisch: AT-SPI läuft auf dem Session-Bus, nicht auf dem
Compositor. Unterschiede zwischen Wayland und X11 sind hier **nicht**
Gegenstand:

- Kein Fokus-Pfad aus Discovery heraus.
- Kein AOT / kein Compositor-native Primitive.
- Wayland-Portale (`org.freedesktop.portal.*`) sind **nicht** Teil
  dieses ADR — sie sind ein separater Spike, wenn Fokus-Primitive
  jenseits von `focus_window` gebraucht werden.

## Candidate technical path (Spike-Plan, unverbindlich)

Wenn / wenn der Spike kommt, wäre die minimale Code-Oberfläche:

1. Neue Cargo-Dependency: `atspi = "<pin>"` plus `zbus = "<pin>"`.
   Feature-Flag `accessibility_rpc` (off by default), damit der
   Default-Build den bestehenden env-only Pfad behält und CI ohne
   Accessibility-Infrastruktur grün bleibt.
2. Neuer interner Trait `AccessibilityRegistry` (sync-wrapper), in
   `accessibility.rs` hinter `#[cfg(feature = "accessibility_rpc")]`.
   Einziger Kontrakt: `fn top_level(&self) -> Result<Vec<RegistryChild>>`.
3. `discover_top_level()` bekommt einen Enum-Zweig: wenn Probe
   `Uncertain` und Feature an, versuche Registry-RPC; sonst alter
   Pfad (`Uncertain { items: [] }`). Fehler aus dem RPC-Pfad werden
   auf `AccessibilityDiscovery::Unavailable { reason }` abgebildet —
   kein `Failed`, außer der D-Bus-Call panickt.
4. `inspect_target(hint)` bleibt beim Hint-Echo-Pfad; Upgrade auf
   echten `GetChildren`+Name-Match kommt in einem **zweiten**
   Folge-ADR.

### Data model (unverändert zum heutigen Schema)

Das Wire-Schema aus `docs/api.md` §2.8 bleibt stabil. Der RPC-Pfad
füllt bestehende Felder:

| Feld           | Bedeutung                                                           |
| -------------- | ------------------------------------------------------------------- |
| `kind`         | `application` (heute) oder `window` (zukünftig, per Rolle).         |
| `name`         | AT-SPI `name`-Attribut des Top-Level-Elements.                      |
| `role`         | AT-SPI-Rolle als snake_case-String (`application`, `frame`, …).     |
| `app_name`     | Einhüllender Applikationsname (bei `window` die `parent`-App).      |
| `confidence`   | `verified` genau dann, wenn D3 erfüllt — sonst `discovered`.        |
| `source`       | Neue konstante Provenienz: `accessibility_registry_root` (future).  |
| `matched_hint` | Nur beim `inspect_target`-Pfad. Unverändert.                        |

Keine Erweiterung des Wire-Schemas; keine neuen IPC-Commands, keine
neuen Outgoing-Envelopes. Der RPC-Pfad schreibt in genau diese
bestehenden Felder.

## Failure modes

Der RPC-Pfad ordnet jede erwartete Fehlklasse genau einem Status zu:

| Fehlklasse                               | Resultat                                                                  |
| ---------------------------------------- | ------------------------------------------------------------------------- |
| `DBUS_SESSION_BUS_ADDRESS` fehlt / leer  | `Unavailable { reason: "DBUS_SESSION_BUS_ADDRESS is unset" }` (heutig).   |
| Kein D-Bus-Session-Socket                | `Unavailable { reason: "D-Bus session socket not found at …" }` (heutig). |
| AT-SPI nicht installiert                 | `Unavailable { reason: "org.a11y.Bus not reachable: …" }`.                |
| D-Bus-Permission verweigert              | `Unavailable { reason: "permission denied on org.a11y.Bus" }`.            |
| Registry `GetChildren` leer              | `Uncertain { reason: "accessibility registry reports empty tree", items: [] }`. |
| Toolkit exportiert kein AT-SPI (z. B. reines CLI-Tool) | Item fehlt schlicht — kein Fehler, nur Auslassung. |
| RPC-Call-Panik / unerwarteter `zbus`-Err | `Failed { reason: "atspi rpc error: <kurzer Kontext>" }`.                 |

Alle Fehler fließen **ohne** Heuristik-Upgrade von `discovered` nach
`verified`. Eine leere Registry-Antwort ist `Uncertain`, kein
`Unavailable` — der Nutzer könnte einen Screenreader installiert
haben, der erst nach Aktivierung Top-Level-Elemente exportiert.

## Non-goals

- **Keine Input-Injection.** Kein `type_text`, kein `send_shortcut`,
  kein `DoAction`, kein synthetischer Klick.
- **Kein Fokus-/Steuerungs-Pfad.** Wayland-Fokus bleibt nicht
  verhandelt; X11-Fokus läuft weiterhin über `focus_window` (PR 23)
  und hat keine Accessibility-Abhängigkeit.
- **Kein Tree-Walker.** Keine rekursive Baum-Exploration in diesem
  ADR; nur Registry-Root-Children.
- **Keine App-spezifische Adaption.** Keine GTK-/Qt-/Electron-
  Sonderpfade, kein Browser-Accessibility-Shim.
- **Kein OCR / Pixel-Vision.** Accessibility ist Semantik, nicht
  Bildverarbeitung.
- **Keine Passwort-/Secret-Feld-Behandlung.** Selbst als Read-only
  ignoriert der Spike Felder mit Rolle `password_text` oder mit
  `STATE_INVISIBLE` — keine Namen, keine Detailstrings.
- **Kein Approval-Bypass.** `discovered` bleibt nicht genug für
  irgendeine Aktion. Wenn eine spätere Schicht Accessibility-Items
  in reale Aktionen überführt, läuft der Approval-Flow aus
  [`docs/api.md` §2.7](../api.md) unverändert.
- **Kein `verified`-Claim ohne Registry-Evidenz.** Heuristik-Upgrades
  sind strukturell ausgeschlossen.
- **Keine Wayland-Compositor-Aktion.** Keine Portal-Aufrufe, keine
  `zwlr_*`-Protokolle.
- **Keine AdminBot-/Shell-Aktionen.** Accessibility ≠ Shell.
- **Keine Smolitux-/OceanData-Änderung.** Dieser ADR betrifft
  ausschließlich den Core des Smolit-Assistant.

## Consequences

**Positiv:**

- Der Core bekommt einen klaren, sicheren Pfad, der Discovery-
  Ergebnisse real mit `verified`-Label zurückgibt — ohne die
  Eingabe-Oberfläche anzufassen.
- UI und Approval-Layer bleiben unverändert. Keine IPC-Envelopes
  müssen wachsen.
- Hint-Echo bleibt als Fallback bestehen; alte Clients (ohne
  Accessibility-Bus-Permission) sehen weiterhin dieselben
  `Uncertain`/`Unavailable`-Antworten.

**Neutral:**

- Ein neues optionales Cargo-Feature (`accessibility_rpc`) erhöht die
  Build-Matrix-Komplexität; default-off mildert die Fläche.
- Packaging-Seite muss bei Flatpak die `org.a11y.Bus`-Permission
  beilegen, sobald das Feature aktiv ist — ADR dokumentiert das.

**Negativ / zu beobachten:**

- `discovered` vs. `verified` bleibt eine Differenzierung, die in
  der UI korrekt transportiert werden muss; Drift wäre ein Regression-
  Risiko. Die Smoke-Abdeckung in PR 16/17 hat das Vokabular bereits;
  eine mögliche spätere Tripwire-Testklasse im
  `accessibility.rs`-Modul wäre die natürliche Absicherung.

## Future work

Folge-Schritte, die **nicht** Teil dieses ADR sind, aber auf seiner
Linie sitzen:

- **FA-1.** Spike-Implementation des `accessibility_rpc`-Features
  hinter dem Feature-Flag (separater PR, eigene Tests).
- **FA-2.** ADR für einen Name-Match-Pfad (`inspect_target(hint)` →
  Registry-`GetChildren` + Name-Filter + `verified`).
- **FA-3.** ADR für Toolkit-spezifische Lücken (GTK-only, Qt-only,
  Electron-Fallback) — nur falls FA-1 echte Gaps sichtbar macht.
- **FA-4.** ADR für Wayland-Portal-basierte Fokus-Primitive — völlig
  separater Scope, kein Accessibility-Pfad.

## Tracking

- Workstream F in [`docs/OPEN_WORK.md`](../OPEN_WORK.md).
- PR 37 in [`ROADMAP.md`](../../ROADMAP.md) (Docs/ADR-only).
- Wire-Vertrag: [`docs/api.md` §2.8](../api.md).
- Presence-Kontext: [`docs/presence_desktop_interaction.md` §8](../presence_desktop_interaction.md).
