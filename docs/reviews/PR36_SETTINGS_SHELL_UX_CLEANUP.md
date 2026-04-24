# PR 36 — Settings Shell UX Cleanup (Ist-Zustand)

- **Status:** gelandet
- **Date:** 2026-04-24
- **Workstream:** D — Provider / Settings Consolidation
- **Scope:** UI-only; keine Core-, IPC-, Secret- oder Default-Änderung.

## Zusammenfassung

Die Settings-Shell sammelte durch PR 26 (Provider-Onboarding),
PR 27 (whisper_cpp STT) und PR 34 (piper TTS) zusätzliche Readout-
und Editor-Blöcke. Die Labels waren historisch dev-lastig
(`Configured` / `Active` ohne kontextuellen Unterschied), und die
Privacy-Section trug einen veralteten Hinweis „(PR 5) — kein Editor
in dieser Shell", der seit PR 10 nicht mehr präzise war.

PR 36 ist der UX-Cleanup, der das ohne neue Runtime-Capability
ordnet: **Summary · Details · Editoren** pro Provider-Achse plus
einen expliziten Safety-Notes-Block in Privacy.

## Zielstruktur pro Provider-Achse

| Abschnitt     | Inhalt (seit PR 36)                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------- |
| **Summary**   | `Primary (intended)` = chain[0]; `Active (running)` = `*_provider_active`; `Availability`; `Local / Cloud` (aus `*_provider_cloud`). |
| **Details**   | `Configured`, `Active`, `Chain`, `Last error`, `Cloud`, Per-Kind-Detail-Zeilen (llamafile / local_http / whisper_cpp / piper). |
| **Editoren**  | unverändert — Chain-Editor plus Per-Kind-Editoren (llamafile, local_http, cloud_http, STT-Command, TTS-Command). |

Primary vs. Active:

- `Primary (intended)` = was der Nutzer als ersten Anlaufpunkt
  **wollte** (chain[0], sonst `*_provider_configured`).
- `Active (running)` = was der Core **jetzt** betreibt.
  Differenziert sichtbar auf Fallback (`availability=fallback_active`).

## Safety-Notes-Block (Privacy-Section)

Vier konstante Zeilen aus [`SettingsSections.safety_notes_lines`](../../ui/scripts/settings/settings_sections.gd):

- **Opt-in cloud** — `cloud_http` aktiviert sich nicht von selbst.
- **Secrets** — API-Keys werden nie im UI angezeigt; Secret-Store
  unter `user://secrets.json` mit 0600-Permissions.
- **Env-only** — `SMOLIT_STT_WHISPER_CPP_CMD` (PR 27) und
  `SMOLIT_TTS_PIPER_CMD` (PR 34) werden nicht im UI editierbar,
  nicht persistiert.
- **Probes** — Probes melden Konfigurations-Zustand, triggern keine
  realen Requests.

## cloud_http-Opt-in-Note im Text-Chain-Editor

Der Text-Chain-Editor listet bewusst nur die drei lokalen Kinds
(`abrain`, `llamafile_local`, `local_http`). PR 36 ergänzt eine
sichtbare Note direkt unter dem Editor-Titel, die den Grund
benennt — statt den neuen Nutzer rätseln zu lassen, warum
`cloud_http` fehlt.

## Nicht-Ziele

- Keine neuen Provider; keine neuen Kinds.
- Keine neuen IPC-Commands, keine neuen `StatusPayload`-Felder.
- Keine Core-Änderung.
- Keine Default-Änderung (Text bleibt `["abrain"]`, STT/TTS
  `["command"]`).
- Keine Auto-Cloud-Aktivierung; `Add cloud_http to chain` bleibt
  per Design disabled (PR 26).
- Keine Probe-Semantik-Änderung.
- Keine Token-Implementation (ADR-0001 / PR 24; Smolitux Token
  Contract v0 aus PR 35 bleibt Docs/Schema-only).
- Keine smolitux-ui-Änderung, keine OceanData-Berührung.
- Keine neue Scene-/Autoload-Architektur.

## Geänderte Dateien

- [`ui/scripts/settings/settings_sections.gd`](../../ui/scripts/settings/settings_sections.gd)
  — neue Header- und Summary-Helper, Safety-Notes-Konstanten,
  präzisere Placeholder-Texte, Safety-Notes-Block in
  `privacy_lines`.
- [`ui/scripts/settings/settings_panel_controller.gd`](../../ui/scripts/settings/settings_panel_controller.gd)
  — cloud_http-Opt-in-Note mit `name="TextChainCloudNote"` im
  `_build_text_chain_editor_block`. Kein weiteres Verhalten
  geändert, keine neuen Member-Felder.
- [`scripts/settings_shell_smoke.gd`](../../scripts/settings_shell_smoke.gd)
  — 16 neue Cases (Placeholder-Wording, Summary-Reihenfolge,
  Primary ≠ Active im Fallback, Local/Cloud-Mapping, Safety-
  Notes-Block, Chain-Editoren-Regression, Opt-in-Note,
  Default-Tooltips, IPC-Helper-Whitelist-Guard).
- Docs: `ui_architecture.md` §8d Kopfnotiz,
  `provider_fallback_and_settings_architecture.md` §13 (neu),
  `api.md` §2.10 Kopfhinweis, `OPEN_WORK.md` Workstream D
  (Erledigt-Eintrag), `ROADMAP.md` PR-36-Zeile und J-Zeile.

## Tests / Verifikation

- `cargo test` — unverändert grün (UI-only PR, keine Core-
  Berührung).
- `scripts/run_overlay_verification.sh settings-shell-smoke` —
  PASS, 16 neue Assertions zusätzlich zu den bestehenden.
- Keine echten Netzwerkrequests, keine echten STT/TTS-Binaries.
