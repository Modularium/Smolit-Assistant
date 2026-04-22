# Linux Interaction Backends – Research Notes

Arbeitsdokument, ehrlich und schmal gehalten. Jede Eintragung hier
ist ein Fundstück aus einem konkreten Spike, nicht aus einer
Marketing-Beschreibung von Linux-Desktop-Integration.

Die produktive Desktop-Interaktion des Cores liegt heute in
`core/src/interaction/`. Dieses Dokument erweitert
[`presence_desktop_interaction.md`](./presence_desktop_interaction.md)
um plattformspezifische Fundstücke und grenzt sie zum separaten
Thema der Window-/Overlay-Architektur ab (siehe — sofern vorhanden —
`docs/linux_window_overlay_architecture.md`; Overlay ≠ Accessibility
Backend).

---

## 1. Ausgangslage

Smolit braucht auf Linux strukturierte Wege, Desktop-Aktionen
vorzubereiten und (später) auszuführen. In der Reihenfolge ihres
Informationsgehalts:

1. **App-native APIs / Portale.** Am robustesten, wenn verfügbar
   (z. B. `xdg-open`, `xdg-desktop-portal`). Bevorzugter Pfad.
2. **Accessibility (AT-SPI).** Strukturierter Pfad, aber App- und
   Toolkit-abhängig. Gegenstand dieses Dokuments.
3. **Command-Helfer.** `wmctrl`, `gtk-launch` u. ä. Bereits im
   Interaction Layer MVP genutzt (`CommandBackend`).
4. **Pixel-/OCR-Fallbacks.** Explizit **nicht** Scope; bewusst
   ausgespart.

---

## 2. Spike 1 – AT-SPI Capability Probe (abgeschlossen)

Erste Ausbaustufe, bewusst ohne echten RPC-Client. Ziel war nicht,
AT-SPI zu bedienen, sondern einen getrennten, ehrlichen Capability-
Pfad im Core zu etablieren und die Protokolloberfläche dafür zu
öffnen.

### 2.1 Was der Spike tut

- `AccessibilityProbe::detect()` liest Umgebungsvariablen
  (`XDG_SESSION_TYPE`, `DISPLAY`, `WAYLAND_DISPLAY`,
  `DBUS_SESSION_BUS_ADDRESS`, optional `AT_SPI_BUS_ADDRESS`) und —
  falls die Session-Bus-Adresse ein `unix:path=`-Transport ist —
  prüft die Existenz des Sockets auf dem Dateisystem.
- Das Ergebnis wird als getagtes Enum
  (`uncertain` / `unavailable` / `failed` + `reason`) serialisiert
  und sowohl im `StatusPayload` (`accessibility_probe`,
  `accessibility_probe_reason`) als auch als neuer Outgoing-Typ
  `accessibility_probe_result` auf die IPC-Ebene gebracht.
- `discover_top_level()` und `inspect_target(hint)` setzen auf der
  Probe auf und reichen ihr Verdikt durch. `items` bleibt in dieser
  Phase leer — das Schema ist da, aber die RPC-Füllung fehlt.
- IPC-Nachrichten `interaction_probe_accessibility` und
  `interaction_discover_accessibility` sind additiv; der Flow
  emittiert normale Action Events (`planned` / `started` / `step` /
  `verification` / `completed`|`failed`) **plus** das jeweilige
  `accessibility_*_result`-Envelope.

### 2.2 Was funktioniert

- **Deterministische Erkennung „kein Linux-Desktop".** Auf Systemen
  ohne Session-Bus bzw. ohne `DISPLAY`/`WAYLAND_DISPLAY` liefert die
  Probe stabil `unavailable` mit einem lesbaren Grund.
- **Ehrlicher Default auf echtem Desktop.** Unter einer normalen
  GNOME/Wayland- oder X11-Session antwortet die Probe mit
  `uncertain` und einer Begründung, die klarmacht, dass kein echter
  RPC-Schritt durchgeführt wurde.
- **Unix-Socket-Vorprüfung.** Falls die D-Bus-Adresse ein
  `unix:path=`-Transport ist, fängt die Probe fehlende Sockets im
  Dateisystem ab, bevor es zu einem pseudo-erfolgreichen
  `uncertain` kommt.
- **Action-Event-Integration.** UI-Clients, die bereits das Action
  Event Model konsumieren, rendern die neuen Flows ohne Anpassung —
  inkl. der honest `Best-effort` / `recovery_hint=…`-Semantik.

### 2.3 Nachzug — Verified Target Discovery (kleine, ehrliche Stufe)

Zwischen der ersten Capability-Probe und einem echten AT-SPI-RPC-Pfad
liegt eine kleine, ehrliche Zwischenstufe, die jetzt im Core
implementiert ist. Sie macht die Discovery-Semantik explizit, ohne
neuen Code außerhalb des bestehenden Spikes:

- **Payload-Status vierstufig.** `AccessibilityDiscovery` hat jetzt
  zusätzlich einen `Ok { items }`-Fall neben den bisherigen
  `Uncertain` / `Unavailable` / `Failed`. Serialisiert wird das als
  `"status":"ok" | "uncertain" | "unavailable" | "failed"`. Der
  Probe-Payload bleibt dreistufig (`uncertain` / `unavailable` /
  `failed`) — ein Probe ohne RPC kann niemals ehrlich „ok" melden.
- **Per-Item-Confidence zweistufig.** Jedes `AccessibilityItem` trägt
  jetzt `confidence: "verified" | "discovered"`. `verified` ist in
  diesem Spike **ausdrücklich reserviert**: ohne echten Registry-
  Zugriff gibt es keine belastbare Quelle, die das rechtfertigen
  würde.
- **Hint-Echo als einzige ehrliche `Ok`-Quelle.** `inspect_target(hint)`
  liefert bei plausibler Probe genau ein Item mit
  `confidence=discovered` und `source=accessibility_hint_echo`, samt
  `matched_hint`. Das ist die stärkste Aussage, die ohne RPC
  verantwortbar ist: die Aufrufer-Seite hat uns den Namen genannt,
  wir führen ihn in der Schemaform weiter, mehr nicht.
- **`discover_top_level()` bleibt bei `Uncertain` mit leerer Liste.**
  Top-Level-Enumeration ohne RPC wäre reines Raten; das wird bewusst
  nicht gemacht.

Damit ist die Grenze zwischen „behauptet, dass das Target existiert"
und „gibt dem Target eine strukturierte Form" im Code und auf der
IPC-Ebene sichtbar. Die UI kann jede Stufe als Badge rendern, ohne
semantisch hochzustufen (siehe `docs/ui_architecture.md` §8.1).

### 2.4 Was offen bleibt

- **Echter RPC-Probe** gegen `org.a11y.Bus.GetAddress` auf
  `/org/a11y/bus` via zbus oder `atspi-connection`. Erst damit wird
  aus einem Umgebungs-Verdikt ein tatsächlicher Reachability-Check.
- **Registry-Root-GetChildren.** Nächster sinnvoller
  Discovery-Schritt: top-level Accessibles namentlich auflisten,
  Rollen/Descriptions weitergeben. Das Schema (`AccessibilityItem`)
  ist dafür bereits vorbereitet.
- **Namens-/Rollen-basierte Inspection.** Inspection-Modus des
  Spikes (`hint`) reicht den Namen heute nur durch — ein echter
  Lookup im Accessibility-Tree ist die nächste Ausbaustufe.
- **Toolkit-Unterschiede.** GTK-, Qt-, Electron- und
  Terminal-Anwendungen unterscheiden sich stark in der
  AT-SPI-Exposition. Ein späterer Spike sollte exemplarisch
  mindestens zwei Toolkits vergleichen.
- **Fokus-/Write-Pfad.** Bewusst nicht Teil dieser Phase. Sobald
  ein A11y-getriebener Fokuspfad erprobt wird, muss er zurück durch
  den Approval-Flow, analog zum bestehenden `focus_window`-Spike.

### 2.5 Wo Vorsicht angebracht ist

- **AT-SPI ≠ volle UI-Kontrolle.** Viele Anwendungen exponieren nur
  Fragmente; Browser, Terminals, Password-Dialoge sind notorisch
  unvollständig oder bewusst beschränkt.
- **Wayland ≠ Accessibility.** Wayland betrifft Fenstersteuerung
  und Input-Injection, nicht primär AT-SPI. Ein AT-SPI-Pfad kann
  unter Wayland funktionieren *und* trotzdem keinen Fokuswechsel
  erlauben. Die beiden Fragen sind getrennt zu beantworten.
- **Discovery ≠ Automation.** Ein erfolgreicher Namens-Lookup heißt
  nicht, dass man das Element auch klicken darf oder kann.
- **Portable Behauptung vermeiden.** Alles, was hier dokumentiert
  ist, gilt für Linux-Desktop-Sessions. macOS UIA und Windows
  Automation sind separate Themen und nicht Teil dieses Dokuments.

---

## 3. Abgrenzung zu Window- / Overlay-Themen

AT-SPI adressiert *was eine App exponiert*. Die Frage *wie Smolits
eigenes Fenster gerendert und platziert wird* (randlos, transparent,
always-on-top, click-through) ist davon unabhängig. Beide Linien
laufen parallel und teilen bewusst keine gemeinsame Abstraktion,
solange keine echte Brücke zwischen ihnen nötig ist.

---

## 4. Offene Entscheidungen für nächste Spikes

- **zbus vs. atspi-connection** als RPC-Client: zbus ist generisch
  und bereits ausgereift; `atspi`/`atspi-connection` bringt
  AT-SPI-spezifische Typen. Entscheidung offen; der Spike bleibt
  bewusst dependency-frei, bis eine Richtung gewählt ist.
- **Discovery-Umfang**: Nur Top-Level oder bis zu einer definierten
  Tiefe? Für v2 empfiehlt sich strikt Top-Level plus optionaler
  Name-Lookup, weil tieferer Tree-Walk App-spezifisch wird.
- **Caching**: Sollen Probe-/Discovery-Ergebnisse zwischengespeichert
  werden? Der aktuelle Pfad cached nichts; die Probe ist billig
  genug, dass das erst mit echtem RPC wieder relevant wird.
- **UI-Darstellung**: Heute rendert die UI Probe-Ergebnisse nur
  indirekt (über Action Events und `StatusPayload`-Felder). Ob ein
  eigener Diagnostik-View sinnvoll ist, entscheidet sich mit der
  ersten RPC-Stufe.
