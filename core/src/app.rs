use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, RwLock};
use std::time::Duration;

use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tokio::time::timeout;
use tracing::{info, warn};

use crate::actions::{
    ActionCancelledPayload, ActionCompletedPayload, ActionFailedPayload, ActionKind, ActionPhase,
    ActionPlannedPayload, ActionStartedPayload, ActionStatus, ActionStepPayload, ActionTarget,
    ActionVerificationPayload,
};
use crate::approvals::{
    ApprovalDecision, ApprovalRequest, ApprovalResolvedPayload, PendingApprovalError,
    PendingApprovalRegistry,
};
use crate::config::{
    validate_llamafile_mode, AudioConfig, CloudHttpConfig, Config, LlamafileConfig,
    LocalHttpConfig,
};
use crate::interaction::{
    AccessibilityDiscovery, AccessibilityProbe, CommandBackend, CommandBackendConfig,
    InteractionAction, InteractionExecutor, InteractionKind, InteractionPolicy, SelectedTarget,
    discover_top_level, inspect_target,
};
use crate::ipc::protocol::{
    InteractionFocusTarget, OutgoingMessage, TargetClearedPayload, TargetSelectedPayload,
};
use crate::providers::stt::{
    SttProviderChainItem, SttProviderError, SttProviderResolver,
};
use crate::providers::text::{
    CloudHttpConfigView, LlamafileConfigView, LocalHttpConfigView, TextProviderChainItem,
    TextProviderError, TextProviderResolver,
};
#[cfg(test)]
use crate::providers::text::TextProviderRuntimeStatus;
use crate::providers::tts::{
    TtsProviderChainItem, TtsProviderError, TtsProviderResolver,
};
use crate::secrets_store;
use crate::settings_store;

const EVENTS_CHANNEL_CAPACITY: usize = 256;

pub struct App {
    pub config: Config,
    /// TTS-Provider-Resolver (PR 6). Spiegelt den Text-Pfad:
    /// `handle_speak` / `maybe_auto_speak` gehen durch die Kette;
    /// heute ist das einzige Kind `command` — byte-kompatibel zum
    /// bisherigen `SMOLIT_TTS_CMD`-Verhalten.
    ///
    /// Seit PR 7 hinter einem `RwLock`, damit
    /// `settings_set_tts_config` den Resolver beim Schreibpfad atomar
    /// durch eine frisch aus [`AudioConfig`] gebaute Kette ersetzen
    /// kann — gleiche Semantik wie `text_provider`. Externe Callsites
    /// nutzen [`App::current_tts`] für einen kurzen Clone unter Read-
    /// Lock.
    tts: RwLock<Arc<TtsProviderResolver>>,
    /// STT-Provider-Resolver (PR 6). `handle_voice_once` geht durch
    /// die Kette. Seit PR 7 analog zu `tts` hinter einem `RwLock`.
    stt: RwLock<Arc<SttProviderResolver>>,
    interaction: InteractionExecutor<CommandBackend>,
    action_counter: AtomicU64,
    approval_counter: AtomicU64,
    selection_counter: AtomicU64,
    pending_approvals: Arc<PendingApprovalRegistry>,
    /// Current Interaction target, if any. Held in-memory only —
    /// cleared on explicit `interaction_clear_target`. No persistence,
    /// no cross-session memory.
    selected_target: Mutex<Option<SelectedTarget>>,
    events_tx: broadcast::Sender<OutgoingMessage>,
    /// Text/Reasoning-Provider-Resolver. PR 2 der Provider-Fallback-
    /// Linie: `handle_text_query` routet ab jetzt ausschließlich über
    /// diesen Resolver. ABrain bleibt Default-Provider — der Resolver
    /// kapselt den CLI-Aufruf.
    ///
    /// Seit PR 5 hinter einem `RwLock`, damit `settings_set_llamafile_config`
    /// den Resolver atomar durch einen frisch gebauten ersetzen kann.
    /// `handle_text_query` klont den `Arc` unter dem Read-Lock kurz
    /// heraus und hält das Lock **nicht** über den `await`-Punkt
    /// (kein Deadlock, kein Lock-Halten während Provider-Aufrufen).
    text_provider: RwLock<Arc<TextProviderResolver>>,
    /// Laufende Text-Provider-Kette. Startet aus der Startup-Config
    /// (bereits mit dem persistierten Override aus dem Settings-Store
    /// verschmolzen, siehe `App::new`) und wird durch
    /// `settings_set_text_provider_chain` (PR 9) live ersetzt. Die
    /// Struktur bleibt `TextProviderChainItem`, damit Resolver-Builder
    /// und Status-Projektion unverändert bleiben.
    live_text_chain: Mutex<Vec<TextProviderChainItem>>,
    /// ABrain-CLI-Kommando, wird beim Resolver-Rebuild wiederverwendet.
    abrain_cmd: String,
    /// Laufender editierbarer Stand der Llamafile-Config (PR 5). Startet
    /// als Kopie von `config.text_provider.llamafile`, bereits mit dem
    /// Override aus dem Settings-Store verschmolzen. Änderungen über
    /// `settings_set_llamafile_config` werden hier gespiegelt und in
    /// den StatusPayload projiziert.
    live_llamafile: Mutex<LlamafileConfig>,
    /// Laufender editierbarer Stand der Local-HTTP-Config (PR 8).
    /// Spiegel zu `live_llamafile`: startet mit der Config +
    /// Override-Merge und wird bei jedem `settings_set_local_http_config`
    /// aktualisiert. Resolver-Rebuild-Geometrie identisch zum
    /// Llamafile-Pfad; der alte Resolver-`Arc` lebt weiter, bis alle
    /// laufenden `handle_text_query`-Aufrufe fertig sind.
    live_local_http: Mutex<LocalHttpConfig>,
    /// Laufender editierbarer Stand der Cloud-HTTP-Config (PR 10).
    /// Enthält **keinen** API-Key — der liegt in [`Self::cloud_http_api_key`]
    /// und wird nur beim Resolver-Rebuild kurz in die Provider-View
    /// projiziert. Live-Updates über `settings_set_cloud_http_config`.
    live_cloud_http: Mutex<CloudHttpConfig>,
    /// API-Key für den `cloud_http`-Provider (PR 10). Lebt getrennt
    /// von allen operationalen Configs, damit das Secret nie
    /// versehentlich zusammen mit anderen Feldern serialisiert wird.
    /// Geladen aus [`crate::secrets_store::load_secrets`] beim Start,
    /// aktualisiert über `settings_set_cloud_http_secret`. Wird **nie**
    /// im StatusPayload / EventBus / Log / Probe-Response gespiegelt —
    /// der Status trägt nur einen boolschen „present"-Flag.
    cloud_http_api_key: Mutex<Option<String>>,
    /// Laufender editierbarer Stand der AudioConfig (PR 7). Startet als
    /// Kopie von `config.audio`, gemischt mit STT-/TTS-Overrides aus dem
    /// Settings-Store. Nur die UI-editierbaren Felder
    /// (`stt_enabled`/`stt_cmd`/`tts_enabled`/`tts_cmd`/`auto_speak`)
    /// werden durch `settings_set_{stt,tts}_config` verändert; Timeouts
    /// und Provider-Chains bleiben unverändert auf Startup-Werten.
    /// `build_status_payload`, `handle_speak`, `maybe_auto_speak` und
    /// `handle_voice_once` lesen nicht aus diesem Feld — die Resolver
    /// werden bei jedem Audio-Write neu instanziiert, wodurch sich der
    /// neue Stand byte-kompatibel in `self.stt` / `self.tts` spiegelt.
    live_audio: Mutex<AudioConfig>,
}

#[derive(Debug, Clone, Serialize)]
pub struct StatusPayload {
    pub tts_enabled: bool,
    pub tts_available: bool,
    pub stt_enabled: bool,
    pub stt_available: bool,
    pub auto_speak: bool,
    pub ipc_enabled: bool,
    pub interaction_enabled: bool,
    pub interaction_backend: String,
    pub approval_timeout_seconds: u64,
    /// Honest, environment-based verdict from the AT-SPI spike at
    /// core start-up. One of `"uncertain"`, `"unavailable"`,
    /// `"failed"`. See
    /// [`crate::interaction::AccessibilityProbe`] for semantics.
    pub accessibility_probe: String,
    /// Short free-form reason accompanying `accessibility_probe`.
    pub accessibility_probe_reason: String,
    // --- Text / Reasoning Provider (PR 2, additiv) ------------------
    /// Primärer (konfigurierter) Text-Provider-Kind-Name. `"none"`
    /// wenn keine gültige Kette konfiguriert ist. Entspricht dem
    /// Feld `configured_provider` aus
    /// `docs/provider_fallback_and_settings_architecture.md` §8.
    pub text_provider_configured: String,
    /// Kind des Providers, der den **letzten** `submit_text` /
    /// `voice_once`-Request erfolgreich beantwortet hat. Leer,
    /// solange noch kein Request durchgelaufen ist.
    pub text_provider_active: String,
    /// `"available"` (nominell) / `"unavailable"` (keine Kette oder
    /// kompletter Fehlschlag) / `"fallback_active"` (ein Nicht-
    /// Primary-Provider hat zuletzt geantwortet). Enum-artiges Feld
    /// — additiv, damit spätere Provider-PRs `degraded` oder
    /// Ähnliches ergänzen können, ohne das Schema zu brechen.
    pub text_provider_availability: String,
    /// Kurze Fehlerklasse der letzten komplett fehlgeschlagenen
    /// Runde (`timeout`, `process_missing`, `empty_response`,
    /// `exit_nonzero`, `invalid_response`, `unknown`). `None` im
    /// Erfolgsfall. Keine Nutzerinhalte, keine Stacktraces, keine
    /// Secrets — Freitext-Fehler laufen weiterhin über das
    /// `error`-IPC-Envelope.
    pub text_provider_last_error: Option<String>,
    /// Ob der aktuell aktive Provider eine Cloud-Komponente hat. In
    /// PR 2 existiert kein Cloud-Provider; das Feld ist additiv
    /// vorhanden, damit der UI-Transparenz-Vertrag aus §7 der
    /// Architektur-Doku („Externe Provider klar sichtbar") ohne
    /// Protokoll-Revision einlösbar bleibt, sobald ein Cloud-Pfad
    /// existiert.
    pub text_provider_cloud: bool,
    // --- Text Provider — vertiefter Status (PR 4, additiv) ----------
    /// Geordnete Liste der Provider-Kinds in der aktuellen Kette. Hält
    /// genau die Namen, die der Resolver produktiv instanziiert hat
    /// — unbekannte Kinds aus der Config wurden bereits beim Bau
    /// verworfen. Die UI rendert daraus die Fallback-Reihenfolge;
    /// fehlt das Feld (ältere Cores), fällt die Shell stillschweigend
    /// auf `text_provider_configured` zurück.
    pub text_provider_chain: Vec<String>,
    /// Ob `llamafile_local` Teil der aktuellen Kette ist. Bei `false`
    /// sind alle weiteren `llamafile_*`-Felder bedeutungslos und werden
    /// mit neutralen Werten / `None` gefüllt.
    pub llamafile_in_chain: bool,
    /// `SMOLIT_LLAMAFILE_ENABLED` ausgewertet. Spiegelt, ob der Operator
    /// den Master-Schalter gezogen hat — unabhängig davon, ob der
    /// Provider aktuell in der Kette steht. So kann die UI „konfiguriert,
    /// aber nicht in der Kette" ehrlich sichtbar machen.
    pub llamafile_enabled: bool,
    /// `enabled` **und** ein nicht-leerer `SMOLIT_LLAMAFILE_PATH`. Das
    /// ist die ehrliche „in der Config bereit für Spawn"-Grenze. Ohne
    /// Path bleibt der Provider im Lifecycle `not_configured`.
    pub llamafile_configured: bool,
    /// Lifecycle-Tag aus
    /// [`crate::providers::text::LlamafileLifecycle::as_str`], nur gesetzt,
    /// wenn `llamafile_in_chain` gilt. `None` = nicht in der Kette.
    pub llamafile_lifecycle: Option<String>,
    /// `on_demand` / `standby`. Nur gesetzt, wenn `llamafile_in_chain`
    /// gilt. Spiegelt den normalisierten Config-Wert 1:1 — unbekannte
    /// Eingaben sind schon in der Config auf den Default gefallen.
    pub llamafile_mode: Option<String>,
    /// Idle-Timeout in Sekunden, nach dem der Watchdog einen idle
    /// llamafile-Prozess wieder stoppt. Nur gesetzt, wenn
    /// `llamafile_in_chain` gilt.
    pub llamafile_idle_timeout_seconds: Option<u64>,
    // --- STT Provider (PR 6, additiv) ------------------------------
    /// Primärer (konfigurierter) STT-Provider-Kind-Name. `"none"`
    /// wenn die Kette leer aufgelöst wurde. Default `"command"`.
    pub stt_provider_configured: String,
    /// Kind des STT-Providers, der den **letzten** erfolgreichen
    /// `voice_once`-Request beantwortet hat. Leer bis zum ersten
    /// erfolgreichen Aufruf.
    pub stt_provider_active: String,
    /// `"available"` / `"unavailable"` / `"fallback_active"` — gleiche
    /// Semantik wie `text_provider_availability`. Nominell `"available"`,
    /// sobald der Primärprovider bereit ist (enabled + Command gesetzt).
    pub stt_provider_availability: String,
    /// Kurze, stabile Fehlerklasse nach komplett fehlgeschlagenem Run
    /// (`disabled` / `not_configured` / `timeout` / `process_missing` /
    /// `exit_nonzero` / `empty_response` / `invalid_response` /
    /// `unknown`). `None` im Erfolgsfall.
    pub stt_provider_last_error: Option<String>,
    /// Ob der zuletzt aktive STT-Provider Cloud-Komponenten hat. Heute
    /// immer `false` (kein Cloud-Kind implementiert).
    pub stt_provider_cloud: bool,
    /// Geordnete Liste der produktiv instanziierten STT-Kinds (PR 13).
    /// Spiegel zu `text_provider_chain` — unbekannte Env-Kinds sind
    /// hier bereits verworfen. Seit PR 13 über
    /// `settings_set_stt_provider_chain` editierbar.
    pub stt_provider_chain: Vec<String>,
    // --- TTS Provider (PR 6, additiv) ------------------------------
    pub tts_provider_configured: String,
    pub tts_provider_active: String,
    pub tts_provider_availability: String,
    pub tts_provider_last_error: Option<String>,
    pub tts_provider_cloud: bool,
    /// Geordnete Liste der produktiv instanziierten TTS-Kinds (PR 13).
    pub tts_provider_chain: Vec<String>,
    // --- Local-HTTP-Provider (PR 8, additiv) -----------------------
    /// Ob `local_http` Teil der aktuellen Text-Provider-Kette ist.
    /// Bei `false` sind die übrigen `local_http_*`-Felder bedeutungslos
    /// — analog zu `llamafile_in_chain`.
    pub local_http_in_chain: bool,
    /// Ausgewerteter Master-Schalter (`SMOLIT_LOCAL_HTTP_ENABLED`).
    /// Unabhängig davon, ob der Provider in der Kette steht.
    pub local_http_enabled: bool,
    /// `enabled` **und** ein nicht-leerer Endpoint. Die ehrliche
    /// „konfigurierte"-Grenze, analog zu `llamafile_configured`.
    pub local_http_configured: bool,
    // --- Cloud-HTTP-Provider (PR 10, additiv, security-first) -----
    /// Ob `cloud_http` Teil der aktuellen Text-Provider-Kette ist.
    /// Cloud bleibt opt-in — ohne Chain-Eintrag bedeutet `cloud=true`
    /// im Resolver-Status nichts, weil der Provider gar nicht gebaut
    /// wurde.
    pub cloud_http_in_chain: bool,
    /// Ausgewerteter Master-Schalter (`SMOLIT_CLOUD_HTTP_ENABLED`).
    /// Auch hier: unabhängig von der Chain-Mitgliedschaft.
    pub cloud_http_enabled: bool,
    /// `enabled` **und** ein nicht-leerer Endpoint **und** ein
    /// gesetzter API-Key im Secrets-Store. Nur wenn alle drei Bedingungen
    /// erfüllt sind, hat `run()` eine echte Chance. Der Status-Wert
    /// ist die ehrliche „bereit für einen Request"-Grenze.
    pub cloud_http_configured: bool,
    /// **Nur ein Boolean.** Der Key-Wert verlässt niemals den
    /// Secrets-Store in Richtung StatusPayload/EventBus/Log. Die UI
    /// benutzt diesen Flag, um „Key gespeichert ✓" vs. „Key fehlt ✗"
    /// ehrlich anzuzeigen.
    pub cloud_http_secret_present: bool,
}

/// Eingabe-Payload für `settings_set_llamafile_config` (PR 5).
/// Jedes Feld außer `enabled` ist optional — fehlende Felder bleiben
/// auf dem bisherigen Wert. `path` akzeptiert explizit den leeren
/// String zum Löschen.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsLlamafileUpdate {
    pub enabled: bool,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub idle_timeout_seconds: Option<u64>,
    /// `None`                → Pfad unverändert lassen.
    /// `Some("")` / nur Whitespace → Pfad löschen.
    /// `Some("/abs/path")`   → Pfad ersetzen.
    #[serde(default)]
    pub path: Option<String>,
}

/// Ergebnis einer `settings_probe_*`-Anfrage (PR 5 für Llamafile,
/// PR 7 für STT/TTS). Bewusst schmal: keine Pfad-/Fehler-Freitexte,
/// nur ein kleiner, stabiler Tag plus eine kurze menschenlesbare
/// Meldung, die **nie** Binary-Pfade, Command-Argumente, Cloud-Keys
/// oder Roh-Fehlerstrings enthält.
#[derive(Debug, Clone, Serialize)]
pub struct SettingsProbeResultPayload {
    /// Welche Achse geprüft wurde. `"llamafile"` (PR 5),
    /// `"stt"` oder `"tts"` (PR 7). Das Feld ist additiv und erlaubt
    /// der UI, eine Probe gezielt in den richtigen Settings-Abschnitt
    /// zu routen, ohne Anfrage-zu-Antwort-Korrelation zu tracken.
    pub axis: String,
    /// True nur, wenn der Provider in der Kette steht, enabled ist
    /// und der Preflight-Check (Pfad / Command existiert + ausführbar)
    /// erfolgreich war.
    pub ok: bool,
    /// Kurzer, stabiler Klassen-Tag. Werte für Llamafile:
    ///
    ///   * `"ok"` — Binary vorhanden, ausführbar, Config konsistent.
    ///   * `"not_in_chain"` — `llamafile_local` steht nicht in der
    ///     aktuellen Provider-Kette.
    ///   * `"disabled"` — Master-Flag aus.
    ///   * `"not_configured"` — enabled, aber Pfad leer / unset.
    ///   * `"path_missing"` — Pfad gesetzt, aber Datei existiert nicht.
    ///   * `"path_not_file"` — Pfad zeigt auf ein Verzeichnis o. ä.
    ///   * `"path_not_executable"` — Datei existiert, aber ohne
    ///     Execute-Bit (Unix).
    ///
    /// Werte für STT/TTS (PR 7, Sub-Set mit kurzer Erklärung):
    ///
    ///   * `"ok"` — Kind in Kette, enabled, Command liegt vor, erster
    ///     Token existiert und ist ausführbar.
    ///   * `"not_in_chain"` — `command` steht nicht in der Kette.
    ///   * `"disabled"` — Master-Flag aus.
    ///   * `"not_configured"` — enabled, aber Command leer / unset.
    ///   * `"command_unparseable"` — Command-String nach `split` leer
    ///     (z. B. nur Quotes).
    ///   * `"path_missing"` — erster Token existiert nicht als Datei.
    ///   * `"path_not_file"` — erster Token ist ein Verzeichnis.
    ///   * `"path_not_executable"` — erster Token ist eine Datei ohne
    ///     Execute-Bit.
    pub class: String,
    /// Kurze, menschenlesbare Begründung. **Enthält keinen Pfad,
    /// kein Secret und keinen Roh-Fehlerstring.**
    pub message: String,
    /// Aktueller Lifecycle des Providers (nur für Llamafile), falls er
    /// in der Kette steht. `null` sonst — STT/TTS-Kommandos haben
    /// heute kein Lifecycle-Modell (spawn-on-demand).
    pub lifecycle: Option<String>,
    pub in_chain: bool,
    pub enabled: bool,
    pub configured: bool,
}

/// Eingabe-Payload für `settings_set_local_http_config` (PR 8).
/// `enabled` ist Pflicht; `endpoint` optional — `None` lässt den
/// bisherigen Wert stehen, `Some("")` / nur Whitespace löscht ihn,
/// `Some("http://host:port/path")` ersetzt ihn. `request_timeout_seconds`
/// ist optional; `None` lässt den Wert unverändert, `Some(0)` wird
/// als Fehler abgelehnt.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsLocalHttpUpdate {
    pub enabled: bool,
    #[serde(default)]
    pub endpoint: Option<String>,
    #[serde(default)]
    pub request_timeout_seconds: Option<u64>,
}

/// Eingabe-Payload für `settings_set_cloud_http_config` (PR 10).
/// **Enthält keinen API-Key** — der läuft über die separate Nachricht
/// `settings_set_cloud_http_secret`. Optionalsemantik wie bei
/// `SettingsLocalHttpUpdate`: `Some("")` löscht, `None` lässt
/// unverändert.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsCloudHttpConfigUpdate {
    pub enabled: bool,
    #[serde(default)]
    pub endpoint: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub request_timeout_seconds: Option<u64>,
}

/// Eingabe-Payload für `settings_set_cloud_http_secret` (PR 10). Der
/// einzige Ort, an dem ein API-Key über IPC in den Core kommt.
/// `api_key=None` oder `Some("")` löscht den Key (Clear-Pfad); jeder
/// andere Wert wird persistiert.
///
/// **Secret-Disziplin:** der Payload selbst wird **nicht** in
/// Request-Logs zitiert; der IPC-Dispatch antwortet mit einem
/// Status-Envelope, der nur `cloud_http_secret_present` trägt, nie
/// den Key selbst.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsCloudHttpSecretUpdate {
    /// `None` **oder** leerer String → Key löschen.
    /// Jeder andere Wert → speichern.
    #[serde(default)]
    pub api_key: Option<String>,
}

/// Eingabe-Payload für `settings_set_text_provider_chain` (PR 9).
/// Trägt die gewünschte Reihenfolge der Text-Provider-Kinds. Der Core
/// validiert gegen [`crate::providers::text::KNOWN_TEXT_KINDS`],
/// lehnt Duplikate und leere Ketten ab und persistiert erst nach
/// erfolgreicher Validierung.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsTextProviderChainUpdate {
    /// Geordnete Liste der Provider-Kind-Namen. Leerer Vec → Fehler
    /// (Reset-Pfad läuft separat über `settings_reset_text_provider_chain`).
    pub chain: Vec<String>,
}

/// Eingabe-Payload für `settings_set_stt_provider_chain` (PR 13).
/// Spiegel zu [`SettingsTextProviderChainUpdate`]; der Core validiert
/// gegen [`crate::providers::stt::KNOWN_STT_KINDS`].
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsSttProviderChainUpdate {
    pub chain: Vec<String>,
}

/// Eingabe-Payload für `settings_set_tts_provider_chain` (PR 13).
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsTtsProviderChainUpdate {
    pub chain: Vec<String>,
}

/// Eingabe-Payload für `settings_set_stt_config` (PR 7). `enabled` ist
/// Pflicht; `command` ist optional — `None` lässt den bisherigen Wert
/// stehen, `Some("")` / nur Whitespace löscht ihn, `Some("whisper …")`
/// ersetzt ihn.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsSttUpdate {
    pub enabled: bool,
    #[serde(default)]
    pub command: Option<String>,
}

/// Eingabe-Payload für `settings_set_tts_config` (PR 7). Spiegel zu
/// [`SettingsSttUpdate`] plus dem TTS-spezifischen `auto_speak`-Flag.
/// `auto_speak` ist optional: wer nur enabled/command ändert, muss das
/// Feld nicht senden — der bisherige Wert bleibt erhalten.
#[derive(Debug, Clone, Deserialize)]
pub struct SettingsTtsUpdate {
    pub enabled: bool,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub auto_speak: Option<bool>,
}

impl App {
    pub fn new(config: Config) -> Self {
        // STT-/TTS-Provider-Resolver (PR 6 / PR 13). Command-Kind
        // bleibt Default, die Chain kommt primär aus der Config
        // (env-überschreibbar). **PR 13:** Zusätzlich liest der Core
        // einen persistierten `stt_chain.json` / `tts_chain.json`-
        // Override aus dem Settings-Store und legt ihn über die
        // Startup-Chain. Eine leere / fehlende Override-Datei fällt
        // geräuschlos auf die Startup-Chain zurück.
        let stt_chain_override = settings_store::load_stt_chain_override();
        let tts_chain_override = settings_store::load_tts_chain_override();
        let stt_chain_names: Vec<String> = match stt_chain_override.chain {
            Some(c) if !c.is_empty() => c,
            _ => config.audio.stt_provider_chain.clone(),
        };
        let tts_chain_names: Vec<String> = match tts_chain_override.chain {
            Some(c) if !c.is_empty() => c,
            _ => config.audio.tts_provider_chain.clone(),
        };
        let stt_chain: Vec<SttProviderChainItem> = stt_chain_names
            .iter()
            .map(|k| SttProviderChainItem { kind: k.clone() })
            .collect();
        let tts_chain: Vec<TtsProviderChainItem> = tts_chain_names
            .iter()
            .map(|k| TtsProviderChainItem { kind: k.clone() })
            .collect();
        // PR 7 — vor dem Resolver-Bau die STT/TTS-Overrides laden und
        // in die live-AudioConfig mergen, damit der Primär-Provider
        // schon beim Start den persistierten Nutzer-Zustand reflektiert.
        let stt_override = settings_store::load_stt_override();
        let tts_override = settings_store::load_tts_override();
        let mut live_audio_stage =
            settings_store::apply_stt_override(config.audio.clone(), &stt_override);
        // PR 13 — die Chain-Felder in live_audio spiegeln die aktuelle
        // produktive Kette. Damit Lese-Pfade (StatusPayload,
        // `update_stt_config`-Rebuild) vom live-Stand auslesen können,
        // nicht vom immutablen Startup-Snapshot.
        live_audio_stage.stt_provider_chain = stt_chain_names.clone();
        let mut live_audio_initial =
            settings_store::apply_tts_override(live_audio_stage, &tts_override);
        live_audio_initial.tts_provider_chain = tts_chain_names.clone();
        let stt = Arc::new(SttProviderResolver::from_chain(&stt_chain, &live_audio_initial));
        let tts = Arc::new(TtsProviderResolver::from_chain(&tts_chain, &live_audio_initial));

        let backend = CommandBackend::new(CommandBackendConfig {
            open_app_cmd_template: config.interaction.open_app_cmd_template.clone(),
            focus_window_cmd_template: config.interaction.focus_window_cmd_template.clone(),
        });
        let policy = InteractionPolicy {
            enabled: config.interaction.enabled,
            allow_open_application: config.interaction.allow_open_application,
            allow_focus_window: config.interaction.allow_focus_window,
            allow_type_text: config.interaction.allow_type_text,
            allow_shortcuts: config.interaction.allow_shortcuts,
            require_confirmation: config.interaction.require_confirmation,
        };
        let interaction = InteractionExecutor::new(backend, policy);
        let (events_tx, _) = broadcast::channel(EVENTS_CHANNEL_CAPACITY);

        // PR 9: persistierte Text-Chain aus dem Settings-Store über die
        // Startup-Chain legen. Unbekannte Kinds im Override werden hier
        // NICHT validiert — der Resolver-Baupfad in
        // `TextProviderResolver::from_chain` filtert sie weiterhin mit
        // einem sichtbaren `warn!` heraus. Eine leere persistierte
        // Kette wird als "kein Override" behandelt, damit ein
        // beschädigtes Override-File den Start nicht blockiert.
        let text_chain_override = settings_store::load_text_chain_override();
        let chain_names: Vec<String> = match text_chain_override.chain {
            Some(c) if !c.is_empty() => c,
            _ => config.text_provider.chain.clone(),
        };
        let chain: Vec<TextProviderChainItem> = chain_names
            .iter()
            .map(|k| TextProviderChainItem { kind: k.clone() })
            .collect();
        // PR 5: Persistierter Llamafile-Override aus dem Settings-Store
        // einlesen und über die Env-Defaults legen. Die Config selbst
        // bleibt unverändert (Immutable Snapshot der Startup-Werte);
        // der live-Stand lebt in `live_llamafile`.
        let override_file = settings_store::load_llamafile_override();
        let live_llamafile = settings_store::apply_llamafile_override(
            config.text_provider.llamafile.clone(),
            &override_file,
        );
        let llamafile_view = llamafile_view_from(&live_llamafile);
        // PR 8: Local-HTTP-Config analog zum Llamafile-Pfad laden und
        // mit dem persistierten Override verschmelzen.
        let local_http_override = settings_store::load_local_http_override();
        let live_local_http = settings_store::apply_local_http_override(
            config.text_provider.local_http.clone(),
            &local_http_override,
        );
        let local_http_view = local_http_view_from(&live_local_http);
        // PR 10: Cloud-HTTP-Config aus der Startup-Config übernehmen.
        // Der API-Key kommt aus dem dedizierten Secrets-Store (eigene
        // Datei, 0600). `SecretsFile::Debug` elidiert den Wert — wir
        // loggen hier nur den `api_key_present`-Bool über den
        // Resolver-Baupfad.
        let secrets = secrets_store::load_secrets();
        let cloud_http_api_key = secrets.cloud_http_api_key.clone();
        let live_cloud_http = config.text_provider.cloud_http.clone();
        let cloud_http_view =
            cloud_http_view_from(&live_cloud_http, cloud_http_api_key.clone());
        let text_provider = Arc::new(TextProviderResolver::from_chain(
            &chain,
            &config.abrain_cmd,
            &llamafile_view,
            &local_http_view,
            &cloud_http_view,
        ));
        let abrain_cmd = config.abrain_cmd.clone();

        Self {
            config,
            tts: RwLock::new(tts),
            stt: RwLock::new(stt),
            interaction,
            action_counter: AtomicU64::new(0),
            approval_counter: AtomicU64::new(0),
            selection_counter: AtomicU64::new(0),
            pending_approvals: Arc::new(PendingApprovalRegistry::new()),
            selected_target: Mutex::new(None),
            events_tx,
            text_provider: RwLock::new(text_provider),
            live_text_chain: Mutex::new(chain),
            abrain_cmd,
            live_llamafile: Mutex::new(live_llamafile),
            live_audio: Mutex::new(live_audio_initial),
            live_local_http: Mutex::new(live_local_http),
            live_cloud_http: Mutex::new(live_cloud_http),
            cloud_http_api_key: Mutex::new(cloud_http_api_key),
        }
    }

    /// Klon-Snapshot des aktuell aktiven STT-Resolvers. Siehe
    /// [`App::current_resolver`] für die Semantik — der Read-Lock
    /// wird nur kurz gehalten, Callsites dürfen den `Arc` unbegrenzt
    /// behalten.
    pub fn current_stt(&self) -> Arc<SttProviderResolver> {
        self.stt
            .read()
            .expect("stt resolver lock poisoned")
            .clone()
    }

    pub fn current_tts(&self) -> Arc<TtsProviderResolver> {
        self.tts
            .read()
            .expect("tts resolver lock poisoned")
            .clone()
    }

    /// Read-only-Snapshot des Text-Provider-Laufzeit-Status — für
    /// Tests und ggf. spätere Diagnostik-Endpoints. Kein Write-Pfad,
    /// kein Event-Fan-out; der Status wird exklusiv durch die
    /// `run`-Aufrufe in `handle_text_query` aktualisiert.
    #[cfg(test)]
    pub fn text_provider_status(&self) -> TextProviderRuntimeStatus {
        self.current_resolver().status()
    }

    /// Klon-Snapshot des aktuell aktiven Resolvers. Hält den Read-Lock
    /// nur kurz, klont den `Arc` und gibt ihn frei. Callsites dürfen
    /// das Ergebnis unbegrenzt behalten (z. B. für ein `await` auf
    /// `run`) — der Core rebuildet bei Config-Writes einen **neuen**
    /// Resolver und ersetzt die Referenz; alte Snapshots bleiben für
    /// ihre Lebensdauer konsistent.
    fn current_resolver(&self) -> Arc<TextProviderResolver> {
        self.text_provider
            .read()
            .expect("text provider lock poisoned")
            .clone()
    }

    /// Clone des aktuellen Chain-Stands (PR 9). Wird vom Resolver-
    /// Rebuild-Pfad verwendet — der Mutex wird nur kurz gehalten, der
    /// Vec geklont, dann freigegeben.
    fn current_text_chain(&self) -> Vec<TextProviderChainItem> {
        self.live_text_chain
            .lock()
            .expect("live text chain mutex poisoned")
            .clone()
    }

    /// Baut einen frischen `CloudHttpConfigView` aus dem live-Stand
    /// (PR 10). Klont sowohl Config als auch den API-Key unter
    /// getrennten kurzen Locks, damit weder der Schreibpfad noch das
    /// Probe blockieren. **Einzige Stelle in `App`, die den Key-
    /// Klartext in einer String-Allokation hält — und sie fällt am
    /// Ende der umgebenden Funktion wieder raus.**
    fn current_cloud_http_view(&self) -> CloudHttpConfigView {
        let cfg = self
            .live_cloud_http
            .lock()
            .expect("live cloud_http mutex poisoned")
            .clone();
        let key = self
            .cloud_http_api_key
            .lock()
            .expect("cloud_http api key mutex poisoned")
            .clone();
        cloud_http_view_from(&cfg, key)
    }

    /// Ob der persistierte API-Key gesetzt ist. Nur der Bool darf in
    /// `StatusPayload` — der Wert selbst nie. Separate Methode statt
    /// `current_cloud_http_view().api_key.is_some()`, damit der Log-
    /// Pfad auch ohne Secret-Allokation arbeiten kann.
    fn cloud_http_api_key_present(&self) -> bool {
        self.cloud_http_api_key
            .lock()
            .expect("cloud_http api key mutex poisoned")
            .is_some()
    }

    pub fn next_action_id(&self) -> String {
        let n = self.action_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("act_{n:06}")
    }

    fn next_approval_id(&self) -> String {
        let n = self.approval_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("apr_{n:06}")
    }

    fn next_selection_id(&self) -> String {
        let n = self.selection_counter.fetch_add(1, Ordering::Relaxed) + 1;
        format!("sel_{n:06}")
    }

    /// Read-only snapshot of the currently selected Interaction target.
    /// Used by the approval flow to embed the target in
    /// `approval_requested` and by tests.
    pub fn current_selected_target(&self) -> Option<SelectedTarget> {
        self.selected_target
            .lock()
            .expect("selected_target mutex poisoned")
            .clone()
    }

    /// Store `target` as the current Interaction context, replacing any
    /// previous selection. Returns a `target_selected` envelope the
    /// caller should flush to IPC. Validation failures produce an
    /// `Error` envelope instead — the previous selection is untouched.
    pub fn select_target(&self, target: SelectedTarget) -> Vec<OutgoingMessage> {
        let fallback_id = self.next_selection_id();
        let normalized = match target.normalize_with_fallback_id(fallback_id) {
            Ok(t) => t,
            Err(err) => {
                return vec![OutgoingMessage::Error {
                    message: err.message().to_string(),
                }];
            }
        };

        {
            let mut slot = self
                .selected_target
                .lock()
                .expect("selected_target mutex poisoned");
            *slot = Some(normalized.clone());
        }

        info!(
            target_id = %normalized.id,
            target_name = %normalized.name,
            target_role = %normalized.role,
            target_confidence = %normalized.confidence,
            "selected interaction target",
        );

        vec![OutgoingMessage::TargetSelected {
            payload: TargetSelectedPayload { target: normalized },
        }]
    }

    /// Clear the current Interaction context. Idempotent: always emits
    /// a `target_cleared` envelope, with `previous` set when a target
    /// was actually held.
    pub fn clear_target(&self) -> Vec<OutgoingMessage> {
        let previous = {
            let mut slot = self
                .selected_target
                .lock()
                .expect("selected_target mutex poisoned");
            slot.take()
        };

        if let Some(prev) = &previous {
            info!(target_id = %prev.id, "cleared interaction target");
        }

        vec![OutgoingMessage::TargetCleared {
            payload: TargetClearedPayload { previous },
        }]
    }

    /// Subscribe to async continuation events (approval outcomes,
    /// background-task progress). Used by IPC handlers to forward
    /// these to connected WS clients.
    pub fn subscribe_events(&self) -> broadcast::Receiver<OutgoingMessage> {
        self.events_tx.subscribe()
    }

    fn broadcast(&self, msg: OutgoingMessage) {
        // Ignore send errors: `broadcast::Sender::send` only errors
        // when there are zero receivers, which is a legitimate state
        // (no UI connected) rather than a bug.
        let _ = self.events_tx.send(msg);
    }

    pub async fn handle_text_query(&self, input: &str) -> Result<String> {
        // PR 2: geht ausschließlich über die Provider-Schicht. Der
        // alte direkte Aufruf in `adapters::abrain::run_task_with_cmd`
        // wohnt jetzt im `AbrainCliProvider` innerhalb des Resolvers.
        // Resolver-Fehler werden in den generischen `anyhow::Error`-
        // Rückgabetyp gemappt, damit sich die bestehende Callsite-
        // Semantik (CLI-Loop, IPC-`submit_text`) byte-identisch
        // verhält: ein Text-Antwort-Erfolg bleibt ein Erfolg, ein
        // Provider-Fehler bleibt ein `error`-Envelope mit
        // menschenlesbarer Meldung.
        let resolver = self.current_resolver();
        resolver
            .run(input)
            .await
            .map_err(|err: TextProviderError| anyhow::anyhow!(err))
    }

    pub async fn handle_voice_once(&self) -> Result<String> {
        let resolver = self.current_stt();
        resolver
            .run()
            .await
            .map_err(|err: SttProviderError| anyhow::anyhow!(err))
    }

    pub async fn handle_speak(&self, text: &str) -> Result<()> {
        let resolver = self.current_tts();
        resolver
            .run(text)
            .await
            .map_err(|err: TtsProviderError| anyhow::anyhow!(err))
    }

    pub async fn maybe_auto_speak(&self, text: &str) {
        // Auto-Speak liest den live-Stand (PR 7); ein Settings-Write
        // wirkt also ohne Core-Neustart.
        let auto_speak = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .auto_speak;
        let resolver = self.current_tts();
        if !auto_speak || !resolver.is_available() {
            return;
        }
        if let Err(err) = resolver.run(text).await {
            warn!(error = %err, "auto-speak TTS failed");
        }
    }

    /// Deliver a decision submitted by the UI to the matching pending
    /// approval. Returns an error message suitable for an IPC
    /// `error` envelope when the approval id is unknown or stale.
    pub fn resolve_approval(
        &self,
        approval_id: &str,
        decision: ApprovalDecision,
    ) -> Result<(), String> {
        match self.pending_approvals.resolve(approval_id, decision) {
            Ok(()) => Ok(()),
            Err(PendingApprovalError::Unknown) => Err(format!(
                "no pending approval with id {approval_id} (already resolved or unknown)"
            )),
            Err(PendingApprovalError::Closed) => Err(format!(
                "approval {approval_id} was already closed"
            )),
        }
    }

    /// Entry point for IPC handlers. Plans the interaction, checks
    /// policy, and either:
    ///   * refuses the action (layer disabled / kind disallowed),
    ///   * runs the backend directly (no confirmation required), or
    ///   * emits `approval_requested` and spawns a background task
    ///     that awaits the UI decision (or a timeout) before running
    ///     the backend.
    ///
    /// Returns the *immediate* Action Events the IPC handler should
    /// flush to the caller. Any further continuation events (backend
    /// progress after approval, `approval_resolved`) arrive via the
    /// broadcast channel.
    pub async fn dispatch_interaction(
        self: &Arc<Self>,
        action: InteractionAction,
    ) -> Vec<OutgoingMessage> {
        let mut out = Vec::with_capacity(3);
        out.push(self.interaction.plan_event(&action));

        if let Err(err) = self.interaction.policy().allows(action.kind()) {
            out.extend(self.interaction.refusal_events(&action.action_id, &err));
            return out;
        }

        let needs_approval =
            action.requires_confirmation && self.interaction.policy().require_confirmation;

        if !needs_approval {
            out.extend(self.interaction.run_approved(action).await);
            return out;
        }

        let approval_id = self.next_approval_id();
        let timeout_seconds = self.config.approval.timeout_seconds;
        let selected_target = self.current_selected_target();
        let request = ApprovalRequest {
            approval_id: approval_id.clone(),
            action_id: action.action_id.clone(),
            action_kind: action.kind(),
            title: action.title.clone(),
            message: approval_message(&action, selected_target.as_ref()),
            target: action.target.clone(),
            reason: None,
            timeout_seconds,
            selected_target,
        };
        let rx = self.pending_approvals.register(&approval_id);
        out.push(OutgoingMessage::ApprovalRequested { payload: request });

        let app = Arc::clone(self);
        tokio::spawn(async move {
            app.await_and_continue(action, approval_id, rx, timeout_seconds)
                .await;
        });

        out
    }

    async fn await_and_continue(
        self: Arc<Self>,
        action: InteractionAction,
        approval_id: String,
        rx: tokio::sync::oneshot::Receiver<ApprovalDecision>,
        timeout_seconds: u64,
    ) {
        let decision = match timeout(Duration::from_secs(timeout_seconds), rx).await {
            Ok(Ok(decision)) => decision,
            Ok(Err(_)) => {
                // Sender dropped without sending — treat as cancelled.
                ApprovalDecision::Cancelled
            }
            Err(_) => {
                // Timed out: remove the pending entry ourselves so any
                // late `approval_response` is rejected as Unknown.
                let _ = self.pending_approvals.take(&approval_id);
                ApprovalDecision::TimedOut
            }
        };

        info!(
            approval_id = %approval_id,
            action_id = %action.action_id,
            decision = decision.as_str(),
            "approval resolved"
        );

        self.broadcast(OutgoingMessage::ApprovalResolved {
            payload: ApprovalResolvedPayload {
                approval_id: approval_id.clone(),
                action_id: action.action_id.clone(),
                decision: decision.as_str().to_string(),
            },
        });

        match decision {
            ApprovalDecision::Approved => {
                let msgs = self.interaction.run_approved(action).await;
                for msg in msgs {
                    self.broadcast(msg);
                }
            }
            ApprovalDecision::Denied
            | ApprovalDecision::Cancelled
            | ApprovalDecision::TimedOut => {
                let message = match decision {
                    ApprovalDecision::Denied => "Action denied by user",
                    ApprovalDecision::Cancelled => "Action cancelled",
                    ApprovalDecision::TimedOut => "Approval timed out",
                    ApprovalDecision::Approved => unreachable!(),
                };
                self.broadcast(OutgoingMessage::ActionCancelled {
                    payload: ActionCancelledPayload {
                        action_id: action.action_id.clone(),
                        status: ActionStatus::Cancelled,
                        message: Some(message.to_string()),
                    },
                });
            }
        }
    }

    pub async fn execute_open_application(
        self: &Arc<Self>,
        name: &str,
    ) -> Vec<OutgoingMessage> {
        let mut action = InteractionAction::open_application(self.next_action_id(), name);
        // `open_application` is the first action that goes through the
        // approval flow — flip the confirmation flag here rather than
        // inside the factory so pure executor tests stay deterministic.
        action.requires_confirmation = true;
        self.dispatch_interaction(action).await
    }

    /// Run the environment-based accessibility probe and wrap the
    /// result into a small Action-Event sequence plus a dedicated
    /// `accessibility_probe_result` envelope. Emission is read-only
    /// and does not require approval — the probe never touches the
    /// user's desktop.
    pub async fn probe_accessibility(self: &Arc<Self>) -> Vec<OutgoingMessage> {
        let action_id = self.next_action_id();
        let probe = AccessibilityProbe::detect();
        let reason = probe.reason().to_string();
        let status = probe.status_str();

        let mut out = Vec::with_capacity(6);
        out.push(planned(
            &action_id,
            ActionKind::System,
            "Probe accessibility backend",
            ActionTarget::unknown(),
        ));
        out.push(started(&action_id));
        out.push(step(&action_id, "Checking session environment"));
        out.push(OutgoingMessage::ActionVerification {
            payload: ActionVerificationPayload {
                action_id: action_id.clone(),
                title: format!("Probe: {status}"),
            },
        });
        out.push(OutgoingMessage::AccessibilityProbeResult {
            payload: probe.clone(),
        });
        out.push(OutgoingMessage::ActionCompleted {
            payload: ActionCompletedPayload {
                action_id,
                status: ActionStatus::Completed,
                message: Some(format!("{status}: {reason}")),
            },
        });
        out
    }

    /// Run the accessibility discovery / inspection spike. When `hint`
    /// is provided the spike inspects that symbolic target; otherwise
    /// it attempts a top-level discovery. In both cases the actual
    /// RPC walk is not yet wired up, so honest `uncertain` /
    /// `unavailable` results are expected.
    pub async fn discover_accessibility(
        self: &Arc<Self>,
        hint: Option<String>,
    ) -> Vec<OutgoingMessage> {
        let action_id = self.next_action_id();
        let trimmed_hint = hint
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string);

        let (title, step_label) = match &trimmed_hint {
            Some(name) => (
                format!("Inspect accessible target `{name}`"),
                format!("Inspecting `{name}` via accessibility probe"),
            ),
            None => (
                "Discover top-level accessibles".to_string(),
                "Discovering top-level accessibles via AT-SPI probe".to_string(),
            ),
        };

        let target = match &trimmed_hint {
            Some(name) => ActionTarget::application(name.clone()),
            None => ActionTarget::unknown(),
        };

        let result = match &trimmed_hint {
            Some(name) => inspect_target(name),
            None => discover_top_level(),
        };

        let status = result.status_str();
        let reason = result.reason().to_string();

        let mut out = Vec::with_capacity(7);
        out.push(planned(&action_id, ActionKind::System, &title, target));
        out.push(started(&action_id));
        out.push(step(&action_id, "Probing accessibility backend"));
        out.push(step(&action_id, &step_label));
        out.push(OutgoingMessage::ActionVerification {
            payload: ActionVerificationPayload {
                action_id: action_id.clone(),
                title: format!("Discovery: {status}"),
            },
        });
        out.push(OutgoingMessage::AccessibilityDiscoveryResult {
            payload: result.clone(),
        });

        match &result {
            AccessibilityDiscovery::Ok { items, .. } => {
                let summary = if items.is_empty() {
                    format!("{status}: {reason}")
                } else {
                    format!("{status}: {} item(s); {reason}", items.len())
                };
                out.push(OutgoingMessage::ActionCompleted {
                    payload: ActionCompletedPayload {
                        action_id,
                        status: ActionStatus::Completed,
                        message: Some(summary),
                    },
                });
            }
            AccessibilityDiscovery::Uncertain { .. } => {
                out.push(OutgoingMessage::ActionCompleted {
                    payload: ActionCompletedPayload {
                        action_id,
                        status: ActionStatus::Completed,
                        message: Some(format!("{status}: {reason}")),
                    },
                });
            }
            AccessibilityDiscovery::Unavailable { .. }
            | AccessibilityDiscovery::Failed { .. } => {
                out.push(OutgoingMessage::ActionFailed {
                    payload: ActionFailedPayload {
                        action_id,
                        status: ActionStatus::Failed,
                        message: format!("{status}: {reason}"),
                        error: Some("recovery_hint=fallback_unavailable".to_string()),
                    },
                });
            }
        }
        out
    }

    pub async fn execute_focus_window(
        self: &Arc<Self>,
        target: InteractionFocusTarget,
    ) -> Vec<OutgoingMessage> {
        let (title, app) = match target {
            InteractionFocusTarget::Window { name, title, app } => {
                // Accept either `name` (per-spec example) or `title`
                // as the window title — `title` takes precedence when
                // both are provided.
                (title.or(name), app)
            }
            InteractionFocusTarget::Application { name } => (None, Some(name)),
        };
        let mut action = InteractionAction::focus_window(self.next_action_id(), title, app);
        action.requires_confirmation = true;
        self.dispatch_interaction(action).await
    }

    pub fn build_status_payload(&self) -> StatusPayload {
        // Feature-States (enabled/available) kommen jetzt vom
        // Primärprovider der jeweiligen Achse — byte-kompatibel zum
        // bisherigen `SttService::state()`/`TtsService::state()`.
        let stt_resolver = self.current_stt();
        let tts_resolver = self.current_tts();
        let tts = tts_resolver.feature_state();
        let stt = stt_resolver.feature_state();
        let stt_provider = stt_resolver.status();
        let tts_provider = tts_resolver.status();
        let probe = AccessibilityProbe::detect();
        let resolver = self.current_resolver();
        let text_provider = resolver.status();

        // Chain-Sicht (PR 4) kommt direkt aus dem Resolver — stabiler
        // als die Roh-Config, weil unbekannte Kinds beim Resolver-Bau
        // bereits verworfen wurden und die produktive Kette hier zählt.
        let chain: Vec<String> = resolver
            .chain_kinds()
            .into_iter()
            .map(|s| s.to_string())
            .collect();
        let llamafile_in_chain = chain.iter().any(|k| k == "llamafile_local");

        // Llamafile-Config-Sicht liest ab PR 5 den **live**-Stand aus,
        // nicht mehr den immutable Startup-Config-Snapshot: ein
        // `settings_set_llamafile_config`-Write spiegelt sich also im
        // nächsten `get_status` ohne Core-Neustart. `llamafile_configured`
        // ist nicht das Lifecycle-Wort `Configured`, sondern die
        // ehrliche „enabled + path gesetzt"-Grenze.
        let llamafile_cfg = self
            .live_llamafile
            .lock()
            .expect("live llamafile mutex poisoned")
            .clone();
        let llamafile_path_present = llamafile_cfg
            .path
            .as_deref()
            .map(|p| !p.trim().is_empty())
            .unwrap_or(false);
        let llamafile_configured = llamafile_cfg.enabled && llamafile_path_present;

        // Lifecycle wird nur dann exponiert, wenn llamafile tatsächlich
        // in der Kette steht. Sonst sagt das Feld nichts Wahres und
        // bleibt `None` — die UI unterscheidet dann ehrlich zwischen
        // „nicht in der Kette" und „Runtime kaputt".
        let (llamafile_lifecycle, llamafile_mode, llamafile_idle_timeout_seconds) =
            if llamafile_in_chain {
                let lifecycle = resolver
                    .llamafile_lifecycle()
                    .map(|lc| lc.as_str().to_string());
                (
                    lifecycle,
                    Some(llamafile_cfg.mode.clone()),
                    Some(llamafile_cfg.idle_timeout_seconds),
                )
            } else {
                (None, None, None)
            };

        // Local-HTTP-Projektion (PR 8). Liest den live-Stand; das
        // Endpoint-Feld selbst wandert **nicht** in den StatusPayload
        // (Secret-Disziplin analog zum Llamafile-Pfad).
        let local_http_in_chain = chain.iter().any(|k| k == "local_http");
        let local_http_cfg = self
            .live_local_http
            .lock()
            .expect("live local_http mutex poisoned")
            .clone();
        let local_http_endpoint_present = local_http_cfg
            .endpoint
            .as_deref()
            .map(|e| !e.trim().is_empty())
            .unwrap_or(false);
        let local_http_configured = local_http_cfg.enabled && local_http_endpoint_present;

        // Cloud-HTTP-Projektion (PR 10). Vier Felder, **alle** nicht-
        // sensitiv: chain-Mitgliedschaft, Master-Flag, „configured"-
        // Status (erfordert Endpoint **und** Key), und ein boolscher
        // „Secret vorhanden"-Flag. Weder Endpoint noch Key noch Modell
        // werden in den StatusPayload gespiegelt.
        let cloud_http_in_chain = chain.iter().any(|k| k == "cloud_http");
        let cloud_http_cfg = self
            .live_cloud_http
            .lock()
            .expect("live cloud_http mutex poisoned")
            .clone();
        let cloud_http_endpoint_present = cloud_http_cfg
            .endpoint
            .as_deref()
            .map(|e| !e.trim().is_empty())
            .unwrap_or(false);
        let cloud_http_secret_present = self.cloud_http_api_key_present();
        let cloud_http_configured = cloud_http_cfg.enabled
            && cloud_http_endpoint_present
            && cloud_http_secret_present;

        StatusPayload {
            tts_enabled: tts.enabled,
            tts_available: tts.available,
            stt_enabled: stt.enabled,
            stt_available: stt.available,
            auto_speak: self
                .live_audio
                .lock()
                .expect("live audio mutex poisoned")
                .auto_speak,
            ipc_enabled: self.config.ipc.enabled,
            interaction_enabled: self.config.interaction.enabled,
            interaction_backend: self.config.interaction.backend.clone(),
            approval_timeout_seconds: self.config.approval.timeout_seconds,
            accessibility_probe: probe.status_str().to_string(),
            accessibility_probe_reason: probe.reason().to_string(),
            text_provider_configured: text_provider.configured,
            text_provider_active: text_provider.active,
            text_provider_availability: text_provider.availability,
            text_provider_last_error: text_provider.last_error,
            text_provider_cloud: text_provider.cloud,
            text_provider_chain: chain,
            llamafile_in_chain,
            llamafile_enabled: llamafile_cfg.enabled,
            llamafile_configured,
            llamafile_lifecycle,
            llamafile_mode,
            llamafile_idle_timeout_seconds,
            stt_provider_configured: stt_provider.configured,
            stt_provider_active: stt_provider.active,
            stt_provider_availability: stt_provider.availability,
            stt_provider_last_error: stt_provider.last_error,
            stt_provider_cloud: stt_provider.cloud,
            stt_provider_chain: stt_resolver
                .chain_kinds()
                .into_iter()
                .map(|s| s.to_string())
                .collect(),
            tts_provider_configured: tts_provider.configured,
            tts_provider_active: tts_provider.active,
            tts_provider_availability: tts_provider.availability,
            tts_provider_last_error: tts_provider.last_error,
            tts_provider_cloud: tts_provider.cloud,
            tts_provider_chain: tts_resolver
                .chain_kinds()
                .into_iter()
                .map(|s| s.to_string())
                .collect(),
            local_http_in_chain,
            local_http_enabled: local_http_cfg.enabled,
            local_http_configured,
            cloud_http_in_chain,
            cloud_http_enabled: cloud_http_cfg.enabled,
            cloud_http_configured,
            cloud_http_secret_present,
        }
    }

    /// Aktualisiert den live-Stand der Llamafile-Config (PR 5).
    ///
    /// Ablauf:
    ///
    ///   1. Validiert Mode (Whitelist) und Idle-Timeout (> 0). Bei
    ///      ungültigem Input `Err(...)` mit kurzer, Secret-freier
    ///      Meldung — der Aufrufer emittiert ein `error`-Envelope.
    ///   2. Merged die Eingabe mit dem bisherigen `live_llamafile`.
    ///      Fehlende Optionen bleiben unverändert; `path=Some("")`
    ///      löscht den Pfad.
    ///   3. Persistiert den neuen Stand im Settings-Store
    ///      ([`crate::settings_store`]). Persist-Fehler werden
    ///      geloggt, aber nicht hart propagiert — der In-Memory-Stand
    ///      ist für die laufende Session autoritativ.
    ///   4. Baut einen **neuen** `TextProviderResolver` mit der alten
    ///      Kette und der neuen Llamafile-View, ersetzt atomar die
    ///      `text_provider`-Referenz. Ein evtl. laufender alter
    ///      llamafile-Prozess wird beim Drop des alten Resolvers
    ///      beendet (`kill_on_drop`).
    ///   5. Der nächste `handle_text_query` / `build_status_payload`
    ///      sieht die neue Config; der nächste `get_status` spiegelt
    ///      sie in den UI-Readout.
    ///
    /// **Secret-/Log-Disziplin:** der Binary-Pfad taucht weder im
    /// `info!`-Pfad noch in der Rückgabe-Meldung auf — wir loggen nur,
    /// ob er gesetzt ist oder nicht.
    pub fn update_llamafile_config(
        &self,
        update: SettingsLlamafileUpdate,
    ) -> Result<(), String> {
        // Mode-Validierung: wenn Feld gesetzt, muss es aus der
        // Whitelist stammen. Im Schreibpfad lehnen wir unbekannte
        // Werte ausdrücklich ab (anders als der Startup-Parser, der
        // still auf den Default fällt).
        let mode_override: Option<String> = match update.mode.as_deref() {
            Some(raw) => match validate_llamafile_mode(raw) {
                Some(canonical) => Some(canonical.to_string()),
                None => {
                    return Err(format!(
                        "unknown llamafile mode `{raw}` — expected one of on_demand, standby",
                    ));
                }
            },
            None => None,
        };

        // Idle-Timeout-Validierung: 0 ist nicht sinnvoll (Watchdog
        // würde den Prozess sofort killen). Obergrenze lassen wir frei,
        // weil große Werte legitim sind (dauerhafter Betrieb).
        let idle_override: Option<u64> = match update.idle_timeout_seconds {
            Some(0) => {
                return Err("idle_timeout_seconds must be greater than 0".to_string());
            }
            Some(n) => Some(n),
            None => None,
        };

        // Merge mit bestehendem live-Stand.
        let mut merged: LlamafileConfig = self
            .live_llamafile
            .lock()
            .expect("live llamafile mutex poisoned")
            .clone();
        merged.enabled = update.enabled;
        if let Some(m) = mode_override {
            merged.mode = m;
        }
        if let Some(idle) = idle_override {
            merged.idle_timeout_seconds = idle;
        }
        if let Some(raw_path) = update.path {
            let trimmed = raw_path.trim();
            if trimmed.is_empty() {
                merged.path = None;
            } else {
                merged.path = Some(trimmed.to_string());
            }
        }

        // Persistieren. Fehler werden geloggt, nicht propagiert — ein
        // kaputter Settings-Store soll den In-Memory-Update-Pfad nicht
        // blockieren. Der Store selbst loggt keine Pfade.
        if let Err(err) = settings_store::save_llamafile_override(&merged) {
            warn!(error = %err, "failed to persist llamafile override");
        } else {
            info!(
                enabled = merged.enabled,
                mode = %merged.mode,
                idle_timeout_seconds = merged.idle_timeout_seconds,
                path_set = merged.path.is_some(),
                "llamafile override persisted",
            );
        }

        // Resolver rebuilden. Die Chain-Items sind immutable seit
        // Startup; Llamafile- und Local-HTTP-View werden jeweils aus
        // dem aktuellen live-Stand projiziert.
        let new_view = llamafile_view_from(&merged);
        let local_http_view = local_http_view_from(
            &self
                .live_local_http
                .lock()
                .expect("live local_http mutex poisoned"),
        );
        let cloud_http_view = self.current_cloud_http_view();
        let new_resolver = Arc::new(TextProviderResolver::from_chain(
            &self.current_text_chain(),
            &self.abrain_cmd,
            &new_view,
            &local_http_view,
            &cloud_http_view,
        ));

        // Atomar ersetzen. Der alte Arc lebt weiter, solange andere
        // Callsites (z. B. ein laufender `handle_text_query`) ihn
        // klonen; sobald er fällt, wird ein eventueller llamafile-
        // Prozess via `kill_on_drop` beendet.
        {
            let mut guard = self
                .text_provider
                .write()
                .expect("text provider lock poisoned");
            *guard = new_resolver;
        }

        // Live-Config aktualisieren (nach dem erfolgreichen Resolver-
        // Replace, damit ein paralleles `build_status_payload` zwischen
        // den beiden Locks einen kohärenten Stand sieht).
        {
            let mut guard = self
                .live_llamafile
                .lock()
                .expect("live llamafile mutex poisoned");
            *guard = merged;
        }

        Ok(())
    }

    /// Prüft defensiv, ob der `llamafile_local`-Provider startbereit
    /// aussieht. Kein Spawn, kein HTTP-Call — nur Config-Inspektion
    /// und eine Filesystem-Metadatenprüfung des Pfades. Gibt einen
    /// strukturierten `SettingsProbeResultPayload` zurück (PR 5).
    ///
    /// **Secret-Disziplin:** Weder Pfad noch andere sensitive Werte
    /// landen im Result — `message` und `class` sind ausschließlich
    /// kuratierte Tags und Kurzbeschreibungen.
    pub fn probe_llamafile(&self) -> SettingsProbeResultPayload {
        let cfg = self
            .live_llamafile
            .lock()
            .expect("live llamafile mutex poisoned")
            .clone();
        let resolver = self.current_resolver();
        let chain = resolver.chain_kinds();
        let in_chain = chain.iter().any(|k| *k == "llamafile_local");
        let enabled = cfg.enabled;
        let path_present = cfg
            .path
            .as_deref()
            .map(|p| !p.trim().is_empty())
            .unwrap_or(false);
        let configured = enabled && path_present;
        let lifecycle = if in_chain {
            resolver
                .llamafile_lifecycle()
                .map(|lc| lc.as_str().to_string())
        } else {
            None
        };

        // PR 7: kleine Helfer, damit die sieben Result-Varianten den
        // neuen `axis`-Tag ohne Copy-Paste-Druck tragen.
        let build = |ok: bool, class: &str, message: &str| SettingsProbeResultPayload {
            axis: "llamafile".into(),
            ok,
            class: class.into(),
            message: message.into(),
            lifecycle: lifecycle.clone(),
            in_chain,
            enabled,
            configured,
        };

        if !in_chain {
            return build(
                false,
                "not_in_chain",
                "llamafile_local is not in the configured text provider chain",
            );
        }
        if !enabled {
            return build(false, "disabled", "llamafile_local is disabled (master flag off)");
        }
        let Some(path_value) = cfg.path.as_deref().map(str::trim).filter(|p| !p.is_empty())
        else {
            return build(
                false,
                "not_configured",
                "llamafile_local is enabled but has no binary path configured",
            );
        };

        match std::fs::metadata(path_value) {
            Err(_) => build(false, "path_missing", "configured binary path does not exist"),
            Ok(meta) if !meta.is_file() => build(
                false,
                "path_not_file",
                "configured binary path is not a regular file",
            ),
            Ok(meta) => {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if meta.permissions().mode() & 0o111 == 0 {
                        return build(
                            false,
                            "path_not_executable",
                            "configured binary is present but not executable",
                        );
                    }
                }
                let _ = meta; // silence unused on non-unix
                build(true, "ok", "llamafile_local looks ready (binary present, executable)")
            }
        }
    }

    /// Aktualisiert den live-Stand der STT-Config (PR 7). Ablauf ist
    /// eine geschrumpfte Version von [`App::update_llamafile_config`]:
    ///
    ///   1. Merged die Eingabe mit dem bisherigen `live_audio`
    ///      (STT-Felder). `command=Some("")` löscht; `command=None`
    ///      bewahrt den bisherigen Wert.
    ///   2. Persistiert in [`crate::settings_store::save_stt_override`].
    ///      Fehler werden geloggt, der In-Memory-Stand bleibt maßgeblich.
    ///   3. Baut einen **neuen** [`SttProviderResolver`] mit der
    ///      Startup-Kette und der frischen Audio-Config, ersetzt atomar
    ///      `self.stt`.
    ///
    /// Returntyp `Result<(), String>` aus Symmetrie zum Llamafile-Pfad;
    /// heute gibt es für STT keine erzwingende Validierung, also ist
    /// der Pfad bis auf Persist-Warnings nicht fehlschlaghart.
    pub fn update_stt_config(&self, update: SettingsSttUpdate) -> Result<(), String> {
        let mut merged: AudioConfig = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .clone();
        merged.stt_enabled = update.enabled;
        if let Some(raw_cmd) = update.command {
            let trimmed = raw_cmd.trim();
            if trimmed.is_empty() {
                merged.stt_cmd = None;
            } else {
                merged.stt_cmd = Some(trimmed.to_string());
            }
        }

        if let Err(err) = settings_store::save_stt_override(&merged) {
            warn!(error = %err, "failed to persist stt override");
        } else {
            info!(
                enabled = merged.stt_enabled,
                command_set = merged.stt_cmd.is_some(),
                "stt override persisted",
            );
        }

        // Resolver rebuilden. **PR 13:** Chain wird aus dem live-
        // Stand gelesen, damit ein in der Settings-Shell gesetzter
        // Chain-Override beim nächsten `update_stt_config` nicht
        // wieder durch den immutablen Startup-Snapshot ersetzt wird.
        let stt_chain: Vec<SttProviderChainItem> = merged
            .stt_provider_chain
            .iter()
            .map(|k| SttProviderChainItem { kind: k.clone() })
            .collect();
        let new_resolver = Arc::new(SttProviderResolver::from_chain(&stt_chain, &merged));
        {
            let mut guard = self.stt.write().expect("stt resolver lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self.live_audio.lock().expect("live audio mutex poisoned");
            *guard = merged;
        }
        Ok(())
    }

    /// Aktualisiert den live-Stand der TTS-Config (PR 7). Spiegel zu
    /// [`App::update_stt_config`] plus `auto_speak`-Handling.
    pub fn update_tts_config(&self, update: SettingsTtsUpdate) -> Result<(), String> {
        let mut merged: AudioConfig = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .clone();
        merged.tts_enabled = update.enabled;
        if let Some(raw_cmd) = update.command {
            let trimmed = raw_cmd.trim();
            if trimmed.is_empty() {
                merged.tts_cmd = None;
            } else {
                merged.tts_cmd = Some(trimmed.to_string());
            }
        }
        if let Some(auto) = update.auto_speak {
            merged.auto_speak = auto;
        }

        if let Err(err) = settings_store::save_tts_override(&merged) {
            warn!(error = %err, "failed to persist tts override");
        } else {
            info!(
                enabled = merged.tts_enabled,
                command_set = merged.tts_cmd.is_some(),
                auto_speak = merged.auto_speak,
                "tts override persisted",
            );
        }

        // **PR 13:** analog zu `update_stt_config` — Chain aus dem
        // live-Stand lesen, nicht aus der immutablen Startup-Config.
        let tts_chain: Vec<TtsProviderChainItem> = merged
            .tts_provider_chain
            .iter()
            .map(|k| TtsProviderChainItem { kind: k.clone() })
            .collect();
        let new_resolver = Arc::new(TtsProviderResolver::from_chain(&tts_chain, &merged));
        {
            let mut guard = self.tts.write().expect("tts resolver lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self.live_audio.lock().expect("live audio mutex poisoned");
            *guard = merged;
        }
        Ok(())
    }

    /// Probe für die STT-Achse (PR 7). Kein Spawn, kein Mikrofon-
    /// Zugriff, keine Audio-Aufnahme — nur Config-Inspektion und ein
    /// Filesystem-Metadatencheck auf das erste Token des konfigurierten
    /// Commands (sofern gesetzt). Secret-Disziplin analog zum Llamafile-
    /// Probe: Command / Pfad tauchen weder in der Antwort noch in Logs
    /// auf.
    pub fn probe_stt(&self) -> SettingsProbeResultPayload {
        let audio = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .clone();
        let resolver = self.current_stt();
        probe_audio_command(
            "stt",
            audio.stt_enabled,
            audio.stt_cmd.as_deref(),
            &resolver.chain_kinds(),
        )
    }

    /// Probe für die TTS-Achse (PR 7). Spiegel zu [`App::probe_stt`].
    pub fn probe_tts(&self) -> SettingsProbeResultPayload {
        let audio = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .clone();
        let resolver = self.current_tts();
        probe_audio_command(
            "tts",
            audio.tts_enabled,
            audio.tts_cmd.as_deref(),
            &resolver.chain_kinds(),
        )
    }

    /// Aktualisiert den live-Stand der Local-HTTP-Config (PR 8).
    /// Geometrie identisch zum Llamafile-Schreibpfad:
    ///
    ///   1. `endpoint=Some("")` löscht, `None` lässt unverändert.
    ///   2. `request_timeout_seconds=Some(0)` wird abgelehnt.
    ///   3. Persist in [`crate::settings_store::save_local_http_override`].
    ///   4. Neuer Resolver mit aktueller Kette + beiden Views.
    pub fn update_local_http_config(
        &self,
        update: SettingsLocalHttpUpdate,
    ) -> Result<(), String> {
        let timeout_override: Option<u64> = match update.request_timeout_seconds {
            Some(0) => {
                return Err(
                    "request_timeout_seconds must be greater than 0".to_string(),
                );
            }
            Some(n) => Some(n),
            None => None,
        };

        let mut merged: LocalHttpConfig = self
            .live_local_http
            .lock()
            .expect("live local_http mutex poisoned")
            .clone();
        merged.enabled = update.enabled;
        if let Some(raw_endpoint) = update.endpoint {
            let trimmed = raw_endpoint.trim();
            if trimmed.is_empty() {
                merged.endpoint = None;
            } else {
                merged.endpoint = Some(trimmed.to_string());
            }
        }
        if let Some(t) = timeout_override {
            merged.request_timeout_seconds = t;
        }

        if let Err(err) = settings_store::save_local_http_override(&merged) {
            warn!(error = %err, "failed to persist local_http override");
        } else {
            info!(
                enabled = merged.enabled,
                endpoint_set = merged.endpoint.is_some(),
                request_timeout_seconds = merged.request_timeout_seconds,
                "local_http override persisted",
            );
        }

        // Neuer Resolver. Llamafile-View aus dem aktuellen live-Stand
        // lesen — PR 8 ändert daran nichts.
        let llamafile_view = llamafile_view_from(
            &self
                .live_llamafile
                .lock()
                .expect("live llamafile mutex poisoned"),
        );
        let new_local_http_view = local_http_view_from(&merged);
        let cloud_http_view = self.current_cloud_http_view();
        let new_resolver = Arc::new(TextProviderResolver::from_chain(
            &self.current_text_chain(),
            &self.abrain_cmd,
            &llamafile_view,
            &new_local_http_view,
            &cloud_http_view,
        ));
        {
            let mut guard = self
                .text_provider
                .write()
                .expect("text provider lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self
                .live_local_http
                .lock()
                .expect("live local_http mutex poisoned");
            *guard = merged;
        }
        Ok(())
    }

    /// Aktualisiert die Text-Provider-Kette (PR 9). Ablauf:
    ///
    ///   1. `validate_text_chain` (Whitelist, Duplikat-Ablehnung,
    ///      Empty-Reject) — bei Fehler ehrliche `Err(...)`-Meldung.
    ///   2. Persistiert die validierte Kette in
    ///      [`crate::settings_store::save_text_chain_override`].
    ///      Persist-Fehler werden geloggt, nicht propagiert — der
    ///      In-Memory-Stand bleibt für die laufende Session
    ///      autoritativ.
    ///   3. Baut einen **neuen** `TextProviderResolver` mit der neuen
    ///      Kette und den aktuellen Provider-Views (Llamafile +
    ///      LocalHttp) und tauscht ihn atomar.
    ///   4. Nächster `handle_text_query` / `build_status_payload`
    ///      sieht die neue Reihenfolge.
    pub fn update_text_provider_chain(
        &self,
        update: SettingsTextProviderChainUpdate,
    ) -> Result<(), String> {
        use crate::providers::text::{validate_text_chain, TextChainValidationError};
        let normalized = match validate_text_chain(&update.chain) {
            Ok(v) => v,
            Err(TextChainValidationError::Empty) => {
                return Err(
                    "text provider chain is empty (use reset to restore default)".to_string(),
                );
            }
            Err(err) => return Err(format!("{err}")),
        };

        let new_chain_items: Vec<TextProviderChainItem> = normalized
            .iter()
            .map(|k| TextProviderChainItem { kind: k.clone() })
            .collect();

        if let Err(err) = settings_store::save_text_chain_override(&normalized) {
            warn!(error = %err, "failed to persist text provider chain override");
        } else {
            info!(
                chain = ?normalized,
                "text provider chain override persisted",
            );
        }

        // Resolver rebuilden — Views kommen aus dem aktuellen live-
        // Stand, damit wir nicht versehentlich eine ältere Llamafile-/
        // Local-HTTP-Config einfrieren.
        let llamafile_view = llamafile_view_from(
            &self
                .live_llamafile
                .lock()
                .expect("live llamafile mutex poisoned"),
        );
        let local_http_view = local_http_view_from(
            &self
                .live_local_http
                .lock()
                .expect("live local_http mutex poisoned"),
        );
        let cloud_http_view = self.current_cloud_http_view();
        let new_resolver = Arc::new(TextProviderResolver::from_chain(
            &new_chain_items,
            &self.abrain_cmd,
            &llamafile_view,
            &local_http_view,
            &cloud_http_view,
        ));
        {
            let mut guard = self
                .text_provider
                .write()
                .expect("text provider lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self
                .live_text_chain
                .lock()
                .expect("live text chain mutex poisoned");
            *guard = new_chain_items;
        }
        Ok(())
    }

    /// Reset der Text-Provider-Kette auf den Compile-Zeit-Default
    /// (PR 9). Löscht den persistierten Override im Settings-Store und
    /// rebuildet den Resolver. Der Ziel-Zustand ist `["abrain"]` —
    /// symmetrisch zum Verhalten eines frischen Starts ohne
    /// `SMOLIT_TEXT_PROVIDER_CHAIN`-Env.
    pub fn reset_text_provider_chain(&self) -> Result<(), String> {
        use crate::providers::text::DEFAULT_TEXT_PROVIDER_CHAIN;
        if let Err(err) = settings_store::clear_text_chain_override() {
            warn!(error = %err, "failed to clear text provider chain override");
        } else {
            info!("text provider chain override cleared");
        }
        let default_chain: Vec<String> = DEFAULT_TEXT_PROVIDER_CHAIN
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        // Reset geht durch den regulären Update-Pfad, damit Validator
        // und Resolver-Rebuild einheitlich behandelt werden.
        self.update_text_provider_chain(SettingsTextProviderChainUpdate {
            chain: default_chain,
        })
    }

    /// Aktualisiert die STT-Provider-Kette (PR 13). Ablauf identisch
    /// zu `update_text_provider_chain`: Validator, Persist, Resolver-
    /// Rebuild. Der Rebuild liest Enabled/Command aus dem live-Stand —
    /// die Kette wird in `live_audio.stt_provider_chain` aktualisiert.
    pub fn update_stt_provider_chain(
        &self,
        update: SettingsSttProviderChainUpdate,
    ) -> Result<(), String> {
        use crate::providers::stt::{validate_stt_chain, SttChainValidationError};
        let normalized = match validate_stt_chain(&update.chain) {
            Ok(v) => v,
            Err(SttChainValidationError::Empty) => {
                return Err(
                    "stt provider chain is empty (use reset to restore default)".to_string(),
                );
            }
            Err(err) => return Err(format!("{err}")),
        };

        if let Err(err) = settings_store::save_stt_chain_override(&normalized) {
            warn!(error = %err, "failed to persist stt provider chain override");
        } else {
            info!(chain = ?normalized, "stt provider chain override persisted");
        }

        // live_audio + Resolver atomisch umstellen.
        let mut merged: AudioConfig = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .clone();
        merged.stt_provider_chain = normalized.clone();
        let chain_items: Vec<SttProviderChainItem> = normalized
            .iter()
            .map(|k| SttProviderChainItem { kind: k.clone() })
            .collect();
        let new_resolver = Arc::new(SttProviderResolver::from_chain(&chain_items, &merged));
        {
            let mut guard = self.stt.write().expect("stt resolver lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self.live_audio.lock().expect("live audio mutex poisoned");
            *guard = merged;
        }
        Ok(())
    }

    /// Reset der STT-Provider-Kette auf den Compile-Zeit-Default
    /// `["command"]` (PR 13). Löscht den persistierten Override im
    /// Settings-Store und rebuildet den Resolver.
    pub fn reset_stt_provider_chain(&self) -> Result<(), String> {
        use crate::providers::stt::DEFAULT_STT_PROVIDER_CHAIN;
        if let Err(err) = settings_store::clear_stt_chain_override() {
            warn!(error = %err, "failed to clear stt provider chain override");
        } else {
            info!("stt provider chain override cleared");
        }
        let default_chain: Vec<String> = DEFAULT_STT_PROVIDER_CHAIN
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        self.update_stt_provider_chain(SettingsSttProviderChainUpdate {
            chain: default_chain,
        })
    }

    /// Aktualisiert die TTS-Provider-Kette (PR 13). Spiegel zu
    /// [`App::update_stt_provider_chain`].
    pub fn update_tts_provider_chain(
        &self,
        update: SettingsTtsProviderChainUpdate,
    ) -> Result<(), String> {
        use crate::providers::tts::{validate_tts_chain, TtsChainValidationError};
        let normalized = match validate_tts_chain(&update.chain) {
            Ok(v) => v,
            Err(TtsChainValidationError::Empty) => {
                return Err(
                    "tts provider chain is empty (use reset to restore default)".to_string(),
                );
            }
            Err(err) => return Err(format!("{err}")),
        };

        if let Err(err) = settings_store::save_tts_chain_override(&normalized) {
            warn!(error = %err, "failed to persist tts provider chain override");
        } else {
            info!(chain = ?normalized, "tts provider chain override persisted");
        }

        let mut merged: AudioConfig = self
            .live_audio
            .lock()
            .expect("live audio mutex poisoned")
            .clone();
        merged.tts_provider_chain = normalized.clone();
        let chain_items: Vec<TtsProviderChainItem> = normalized
            .iter()
            .map(|k| TtsProviderChainItem { kind: k.clone() })
            .collect();
        let new_resolver = Arc::new(TtsProviderResolver::from_chain(&chain_items, &merged));
        {
            let mut guard = self.tts.write().expect("tts resolver lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self.live_audio.lock().expect("live audio mutex poisoned");
            *guard = merged;
        }
        Ok(())
    }

    pub fn reset_tts_provider_chain(&self) -> Result<(), String> {
        use crate::providers::tts::DEFAULT_TTS_PROVIDER_CHAIN;
        if let Err(err) = settings_store::clear_tts_chain_override() {
            warn!(error = %err, "failed to clear tts provider chain override");
        } else {
            info!("tts provider chain override cleared");
        }
        let default_chain: Vec<String> = DEFAULT_TTS_PROVIDER_CHAIN
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        self.update_tts_provider_chain(SettingsTtsProviderChainUpdate {
            chain: default_chain,
        })
    }

    /// Probe für den Local-HTTP-Provider (PR 8). Kein Completion-
    /// Roundtrip; kein Completion-Body. Prüft defensiv:
    ///
    ///   1. Kind in der aktuellen Chain?
    ///   2. Master-Flag aktiv?
    ///   3. Endpoint gesetzt?
    ///   4. Endpoint syntaktisch parseable (`http://host:port/path`)?
    ///   5. TCP-Connect auf `host:port` innerhalb `request_timeout_seconds`?
    ///
    /// Gibt keine Completion-Antwort zurück und sendet keinen Prompt —
    /// damit die Probe ehrlich über Erreichbarkeit spricht, ohne dem
    /// Modell unnötig Arbeit zu geben.
    pub async fn probe_local_http(&self) -> SettingsProbeResultPayload {
        let cfg = self
            .live_local_http
            .lock()
            .expect("live local_http mutex poisoned")
            .clone();
        let resolver = self.current_resolver();
        let in_chain = resolver.chain_kinds().iter().any(|k| *k == "local_http");
        let enabled = cfg.enabled;
        let endpoint_present = cfg
            .endpoint
            .as_deref()
            .map(|e| !e.trim().is_empty())
            .unwrap_or(false);
        let configured = enabled && endpoint_present;

        let build = |ok: bool, class: &str, message: &str| SettingsProbeResultPayload {
            axis: "local_http".into(),
            ok,
            class: class.into(),
            message: message.into(),
            lifecycle: None,
            in_chain,
            enabled,
            configured,
        };

        if !in_chain {
            return build(
                false,
                "not_in_chain",
                "local_http is not in the configured text provider chain",
            );
        }
        if !enabled {
            return build(
                false,
                "disabled",
                "local_http is disabled (master flag off)",
            );
        }
        let Some(endpoint_value) = cfg
            .endpoint
            .as_deref()
            .map(str::trim)
            .filter(|e| !e.is_empty())
        else {
            return build(
                false,
                "not_configured",
                "local_http is enabled but has no endpoint configured",
            );
        };

        let (host, port, _path) = match crate::providers::text::LocalHttpProvider::parse_endpoint(
            endpoint_value,
        ) {
            Ok(parsed) => parsed,
            Err(err) => {
                let msg = format!("{err}");
                let class = if msg.contains("must start with http://") {
                    "endpoint_scheme_unsupported"
                } else {
                    "endpoint_unparseable"
                };
                // Messages sind kuratiert — keine Roh-Stringifizierung
                // der URL, damit der Endpoint nicht im Probe-Response
                // auftaucht.
                let human = if class == "endpoint_scheme_unsupported" {
                    "endpoint must start with http:// (https:// is not supported in this build)"
                } else {
                    "endpoint url is not parseable"
                };
                return build(false, class, human);
            }
        };

        let timeout_secs = cfg.request_timeout_seconds.max(1).min(30);
        let addr = format!("{host}:{port}");
        let connect_result = tokio::time::timeout(
            std::time::Duration::from_secs(timeout_secs),
            tokio::net::TcpStream::connect(&addr),
        )
        .await;
        match connect_result {
            Err(_) => build(
                false,
                "timeout",
                "tcp connect to configured endpoint timed out",
            ),
            Ok(Err(_)) => build(
                false,
                "http_connect_failed",
                "tcp connect to configured endpoint failed",
            ),
            Ok(Ok(_stream)) => build(
                true,
                "ok",
                "local_http endpoint reachable (tcp connect succeeded)",
            ),
        }
    }

    /// Aktualisiert die operationale Cloud-HTTP-Config (PR 10).
    /// **Enthält keinen Secret-Pfad** — der Key läuft über
    /// `set_cloud_http_api_key`. Dieser Pfad dreht nur an Endpoint /
    /// Modell / Timeout / Enabled.
    pub fn update_cloud_http_config(
        &self,
        update: SettingsCloudHttpConfigUpdate,
    ) -> Result<(), String> {
        let timeout_override: Option<u64> = match update.request_timeout_seconds {
            Some(0) => {
                return Err(
                    "request_timeout_seconds must be greater than 0".to_string(),
                );
            }
            Some(n) => Some(n),
            None => None,
        };

        let mut merged: CloudHttpConfig = self
            .live_cloud_http
            .lock()
            .expect("live cloud_http mutex poisoned")
            .clone();
        merged.enabled = update.enabled;
        if let Some(raw_endpoint) = update.endpoint {
            let trimmed = raw_endpoint.trim();
            merged.endpoint = if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            };
        }
        if let Some(raw_model) = update.model {
            let trimmed = raw_model.trim();
            merged.model = if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            };
        }
        if let Some(t) = timeout_override {
            merged.request_timeout_seconds = t;
        }

        // Kein Secret im Log: wir schreiben Bool-Flags für Endpoint-
        // und Modell-Präsenz, niemals die Werte selbst.
        info!(
            enabled = merged.enabled,
            endpoint_set = merged.endpoint.is_some(),
            model_set = merged.model.is_some(),
            request_timeout_seconds = merged.request_timeout_seconds,
            "cloud_http config updated",
        );

        let llamafile_view = llamafile_view_from(
            &self
                .live_llamafile
                .lock()
                .expect("live llamafile mutex poisoned"),
        );
        let local_http_view = local_http_view_from(
            &self
                .live_local_http
                .lock()
                .expect("live local_http mutex poisoned"),
        );
        let api_key = self
            .cloud_http_api_key
            .lock()
            .expect("cloud_http api key mutex poisoned")
            .clone();
        let new_cloud_http_view = cloud_http_view_from(&merged, api_key);
        let new_resolver = Arc::new(TextProviderResolver::from_chain(
            &self.current_text_chain(),
            &self.abrain_cmd,
            &llamafile_view,
            &local_http_view,
            &new_cloud_http_view,
        ));
        {
            let mut guard = self
                .text_provider
                .write()
                .expect("text provider lock poisoned");
            *guard = new_resolver;
        }
        {
            let mut guard = self
                .live_cloud_http
                .lock()
                .expect("live cloud_http mutex poisoned");
            *guard = merged;
        }
        Ok(())
    }

    /// Setzt (oder löscht) den Cloud-HTTP-API-Key (PR 10). Einziger
    /// IPC-Pfad für Secret-Werte — separat vom operationalen
    /// `update_cloud_http_config`, damit Schreibfehler / Log-Zeilen
    /// niemals zufällig einen Keytreffer mit einer Endpoint-Änderung
    /// vermischen.
    ///
    /// **Kein Secret im Log**: der Erfolgspfad loggt nur „key set"
    /// bzw. „key cleared".
    pub fn set_cloud_http_api_key(
        &self,
        update: SettingsCloudHttpSecretUpdate,
    ) -> Result<(), String> {
        let normalized = update
            .api_key
            .map(|v| v.trim().to_string())
            .filter(|s| !s.is_empty());
        // Persistieren — `secrets_store` selbst loggt ohne Wert.
        if let Err(err) = secrets_store::set_cloud_http_api_key(normalized.clone()) {
            // Fehler **ohne** Secret-Kontext zurückgeben; Settings-UI
            // sieht den Error-Envelope, nicht den Klartext.
            return Err(format!(
                "failed to persist cloud_http api key: {}",
                err.root_cause(),
            ));
        }
        let is_set = normalized.is_some();
        {
            let mut guard = self
                .cloud_http_api_key
                .lock()
                .expect("cloud_http api key mutex poisoned");
            *guard = normalized;
        }
        if is_set {
            info!("cloud_http api key set (value not logged)");
        } else {
            info!("cloud_http api key cleared");
        }
        // Resolver rebuilden — der neue Key muss in einem
        // `CloudHttpConfigView` landen, damit ein `run()` ihn nutzen
        // kann. Der Rebuild hält den Mutex nicht während des Baus.
        let llamafile_view = llamafile_view_from(
            &self
                .live_llamafile
                .lock()
                .expect("live llamafile mutex poisoned"),
        );
        let local_http_view = local_http_view_from(
            &self
                .live_local_http
                .lock()
                .expect("live local_http mutex poisoned"),
        );
        let new_cloud_http_view = self.current_cloud_http_view();
        let new_resolver = Arc::new(TextProviderResolver::from_chain(
            &self.current_text_chain(),
            &self.abrain_cmd,
            &llamafile_view,
            &local_http_view,
            &new_cloud_http_view,
        ));
        {
            let mut guard = self
                .text_provider
                .write()
                .expect("text provider lock poisoned");
            *guard = new_resolver;
        }
        Ok(())
    }

    /// Probe für den Cloud-HTTP-Provider (PR 10). Konservativ: kein
    /// Completion-Roundtrip, nur ein TCP-Connect gegen den geparsten
    /// Endpoint. Der API-Key wird hier **nicht** transportiert — eine
    /// echte HTTP-Runde mit Bearer-Header landet in einem Folge-PR,
    /// sobald wir TLS haben. Für den MVP ist der TCP-Connect
    /// ausreichend ehrlich:
    ///
    ///   * not_in_chain → Provider fehlt in Chain.
    ///   * disabled → Master-Flag off.
    ///   * not_configured → Endpoint fehlt.
    ///   * secret_missing → API-Key im Secrets-Store leer.
    ///   * endpoint_scheme_unsupported → `https://`.
    ///   * endpoint_unparseable → URL kaputt.
    ///   * timeout / http_connect_failed → Netzwerk.
    ///   * ok → TCP-Connect erfolgreich.
    pub async fn probe_cloud_http(&self) -> SettingsProbeResultPayload {
        let cfg = self
            .live_cloud_http
            .lock()
            .expect("live cloud_http mutex poisoned")
            .clone();
        let resolver = self.current_resolver();
        let in_chain = resolver.chain_kinds().iter().any(|k| *k == "cloud_http");
        let enabled = cfg.enabled;
        let endpoint_present = cfg
            .endpoint
            .as_deref()
            .map(|e| !e.trim().is_empty())
            .unwrap_or(false);
        let secret_present = self.cloud_http_api_key_present();
        let configured = enabled && endpoint_present && secret_present;

        let build = |ok: bool, class: &str, message: &str| SettingsProbeResultPayload {
            axis: "cloud_http".into(),
            ok,
            class: class.into(),
            message: message.into(),
            lifecycle: None,
            in_chain,
            enabled,
            configured,
        };

        if !in_chain {
            return build(
                false,
                "not_in_chain",
                "cloud_http is not in the configured text provider chain",
            );
        }
        if !enabled {
            return build(
                false,
                "disabled",
                "cloud_http is disabled (master flag off)",
            );
        }
        let Some(endpoint_value) = cfg
            .endpoint
            .as_deref()
            .map(str::trim)
            .filter(|e| !e.is_empty())
        else {
            return build(
                false,
                "not_configured",
                "cloud_http is enabled but has no endpoint configured",
            );
        };
        if !secret_present {
            return build(
                false,
                "secret_missing",
                "cloud_http is enabled but no api key is stored",
            );
        }

        let (scheme, host, port, path) =
            match crate::providers::text::CloudHttpProvider::parse_endpoint(endpoint_value) {
                Ok(parsed) => parsed,
                Err(err) => {
                    let msg = format!("{err}").to_ascii_lowercase();
                    let class = if msg.contains("missing http:// or https://")
                        || msg.contains("must start with")
                    {
                        "endpoint_scheme_unsupported"
                    } else {
                        "endpoint_unparseable"
                    };
                    let human = if class == "endpoint_scheme_unsupported" {
                        "endpoint must start with http:// or https://"
                    } else {
                        "endpoint url is not parseable"
                    };
                    return build(false, class, human);
                }
            };

        // PR 12: Auth-Header-Namen validieren (blockiert CR/LF-
        // Injektion). Produktionspfade haben das bereits in der Config
        // validiert, aber eine zweite Sicherheitsschleife ist billig.
        let auth_header = match crate::providers::text::CloudHttpProvider::validate_auth_header_name(
            &cfg.auth_header,
        ) {
            Ok(h) => h.to_string(),
            Err(_) => {
                return build(
                    false,
                    "not_configured",
                    "cloud_http auth header name is invalid",
                );
            }
        };
        // Key aus dem Secret-Store holen. `secret_present` wurde oben
        // schon geprüft; falls der Wert zwischenzeitlich verschwindet,
        // fallen wir defensiv auf `secret_missing` zurück.
        let api_key = match self
            .cloud_http_api_key
            .lock()
            .expect("cloud_http api key mutex poisoned")
            .clone()
        {
            Some(k) => k,
            None => {
                return build(
                    false,
                    "secret_missing",
                    "cloud_http is enabled but no api key is stored",
                );
            }
        };
        // Bearer-Wert bauen; lebt **nur** bis zum Ende dieses
        // `probe_cloud_http`-Frames. Der Wert geht direkt in
        // `http_request_with_header` (siehe Secret-Disziplin dort).
        let auth_value = format!("Bearer {api_key}");

        let timeout_secs = cfg.request_timeout_seconds.max(1).min(30);
        let tls_cfg = crate::providers::text::default_cloud_http_tls_config();

        // PR 12: echter authentifizierter HEAD-Request. HEAD reicht
        // für eine ehrliche Application-Layer-Probe:
        //   * Auth-Middleware validiert den Bearer genauso wie bei POST.
        //   * Kein Body, kein Modell-Inferieren, keine Tokens verbraucht.
        //   * 200-299 → auth ok, endpoint erreichbar.
        //   * 401/403 → Server hat den Key explizit zurückgewiesen.
        //   * Anderer Status (400/404/405/5xx) → `http_error` mit
        //     numerischem Status in der Meldung (Status-Code ist kein
        //     Secret).
        // TLS- und Transport-Fehler werden über
        // `TextProviderImpl::classify_error` in die bekannten Klassen
        // gemappt (timeout / http_connect_failed / tls_handshake_failed
        // / cert_untrusted / cert_invalid). Der Bearer-Wert taucht in
        // **keiner** der Fehlermeldungen auf — rustls bricht vor dem
        // ersten Data-Record ab, und der HTTP-Helfer elidiert den
        // Header-Wert in seinen Context-Strings.
        let result = crate::providers::text::http_request_with_header(
            scheme,
            &host,
            port,
            "HEAD",
            &path,
            None,
            timeout_secs,
            &auth_header,
            &auth_value,
            tls_cfg,
        )
        .await;

        match result {
            Ok((status, _body)) => {
                if (200..300).contains(&status) {
                    build(
                        true,
                        "ok",
                        "cloud_http endpoint reachable and auth accepted (HEAD returned 2xx)",
                    )
                } else if status == 401 || status == 403 {
                    build(
                        false,
                        "unauthorized",
                        "cloud_http endpoint rejected the stored api key (HEAD returned 401/403)",
                    )
                } else {
                    // Status-Code ist kein Secret — wir reichen ihn
                    // als kurze Zahl in die Meldung, damit Operator
                    // sieht, was der Server gesagt hat. **Kein**
                    // Response-Body, **kein** Endpoint in der Meldung.
                    build(
                        false,
                        "http_error",
                        &format!("cloud_http endpoint returned HTTP status {status}"),
                    )
                }
            }
            Err(err) => {
                // Reuse des bestehenden Klassifikators — er kennt
                // `timeout` / `http_connect_failed` / `tls_handshake_failed`
                // / `cert_untrusted` / `cert_invalid`. Wir mappen auf
                // kuratierte, Secret-freie Meldungen; der Roh-Fehler
                // wandert **nicht** in das Response-Objekt.
                let class =
                    crate::providers::text::TextProviderImpl::classify_error(&err);
                let (class_out, human): (&str, &str) = match class {
                    "timeout" => (
                        "timeout",
                        "cloud_http request to configured endpoint timed out",
                    ),
                    "http_connect_failed" => (
                        "http_connect_failed",
                        "tcp connect to configured endpoint failed",
                    ),
                    "tls_handshake_failed" => (
                        "tls_handshake_failed",
                        "tls handshake to configured endpoint failed",
                    ),
                    "cert_untrusted" => (
                        "cert_untrusted",
                        "tls server certificate is not trusted by the configured root store",
                    ),
                    "cert_invalid" => (
                        "cert_invalid",
                        "tls server certificate failed validation (expired / not yet valid / hostname mismatch / bad signature)",
                    ),
                    // Alles andere (z. B. `invalid_response`,
                    // `empty_response`) bei einer HEAD-Probe ist
                    // effektiv ein Protokoll-/Endpoint-Bruch — wir
                    // falten es in `http_error`, damit die UI eine
                    // bekannte Kategorie sieht.
                    _ => ("http_error", "cloud_http probe request failed"),
                };
                build(false, class_out, human)
            }
        }
    }
}

/// Gemeinsamer Kern für STT-/TTS-Probes (PR 7). Beide Achsen haben heute
/// das gleiche Default-Kind (`command`), die gleiche Preflight-Logik
/// (Chain-Mitgliedschaft, enabled, Command-Split, Filesystem-Check des
/// ersten Tokens) und die gleiche Secret-Disziplin. Das Ergebnis trägt
/// `axis` für das UI-Routing.
fn probe_audio_command(
    axis: &str,
    enabled: bool,
    command: Option<&str>,
    chain: &[&'static str],
) -> SettingsProbeResultPayload {
    let in_chain = chain.iter().any(|k| *k == "command");
    let command_present = command
        .map(|c| !c.trim().is_empty())
        .unwrap_or(false);
    let configured = enabled && command_present;

    let build = |ok: bool, class: &str, message: &str| SettingsProbeResultPayload {
        axis: axis.to_string(),
        ok,
        class: class.into(),
        message: message.into(),
        lifecycle: None,
        in_chain,
        enabled,
        configured,
    };

    if !in_chain {
        return build(
            false,
            "not_in_chain",
            "command kind is not in the configured provider chain",
        );
    }
    if !enabled {
        return build(false, "disabled", "axis is disabled (master flag off)");
    }
    let Some(cmd_value) = command.map(str::trim).filter(|c| !c.is_empty()) else {
        return build(
            false,
            "not_configured",
            "axis is enabled but has no command configured",
        );
    };
    let Some((program, _args)) = crate::audio::types::split_command(cmd_value) else {
        return build(
            false,
            "command_unparseable",
            "configured command is empty after parsing",
        );
    };

    match std::fs::metadata(&program) {
        Err(_) => build(false, "path_missing", "configured command binary does not exist"),
        Ok(meta) if !meta.is_file() => build(
            false,
            "path_not_file",
            "configured command path is not a regular file",
        ),
        Ok(meta) => {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if meta.permissions().mode() & 0o111 == 0 {
                    return build(
                        false,
                        "path_not_executable",
                        "configured command binary is present but not executable",
                    );
                }
            }
            let _ = meta;
            build(true, "ok", "command looks ready (binary present, executable)")
        }
    }
}

/// Baut eine `LlamafileConfigView` aus einer ausgewerteten
/// [`LlamafileConfig`]. Einzige Quelle der Wahrheit für die
/// Mapping-Regeln — sowohl der Startup-Konstruktor als auch der
/// PR-5-Schreibpfad gehen hier durch.
fn llamafile_view_from(cfg: &LlamafileConfig) -> LlamafileConfigView {
    LlamafileConfigView {
        enabled: cfg.enabled,
        path: cfg.path.clone(),
        mode: cfg.mode.clone(),
        idle_timeout_seconds: cfg.idle_timeout_seconds,
        port: cfg.port,
        startup_timeout_seconds: cfg.startup_timeout_seconds,
        request_timeout_seconds: cfg.request_timeout_seconds,
    }
}

/// Spiegel zu [`llamafile_view_from`] für den `local_http`-Provider
/// (PR 8). Einzige Stelle, an der `config::LocalHttpConfig` in die
/// Providers-interne View gemappt wird — analog zu Llamafile.
fn local_http_view_from(cfg: &LocalHttpConfig) -> LocalHttpConfigView {
    LocalHttpConfigView {
        enabled: cfg.enabled,
        endpoint: cfg.endpoint.clone(),
        request_timeout_seconds: cfg.request_timeout_seconds,
        prompt_field: cfg.prompt_field.clone(),
        response_field: cfg.response_field.clone(),
    }
}

/// Baut eine `CloudHttpConfigView` aus der operationalen
/// [`CloudHttpConfig`] **und** dem separat gehaltenen API-Key (PR 10).
/// Einzige Stelle, an der die beiden Quellen zusammenfinden — und
/// damit die einzige, die Secret-Klartext sieht. Das Ergebnis wird
/// nur kurz an den Resolver-Builder gereicht, der es in einem
/// `CloudHttpProvider` ablegt (auch dort mit Custom-Debug ohne
/// Key-Echo).
fn cloud_http_view_from(
    cfg: &CloudHttpConfig,
    api_key: Option<String>,
) -> CloudHttpConfigView {
    CloudHttpConfigView {
        enabled: cfg.enabled,
        endpoint: cfg.endpoint.clone(),
        model: cfg.model.clone(),
        request_timeout_seconds: cfg.request_timeout_seconds,
        prompt_field: cfg.prompt_field.clone(),
        response_field: cfg.response_field.clone(),
        auth_header: cfg.auth_header.clone(),
        api_key,
    }
}

fn planned(
    action_id: &str,
    kind: ActionKind,
    title: &str,
    target: ActionTarget,
) -> OutgoingMessage {
    OutgoingMessage::ActionPlanned {
        payload: ActionPlannedPayload {
            action_id: action_id.to_string(),
            action_kind: kind,
            title: title.to_string(),
            description: None,
            target,
            mapping: None,
        },
    }
}

fn started(action_id: &str) -> OutgoingMessage {
    OutgoingMessage::ActionStarted {
        payload: ActionStartedPayload {
            action_id: action_id.to_string(),
            phase: ActionPhase::Started,
        },
    }
}

fn step(action_id: &str, title: &str) -> OutgoingMessage {
    OutgoingMessage::ActionStep {
        payload: ActionStepPayload {
            action_id: action_id.to_string(),
            title: title.to_string(),
            description: None,
        },
    }
}

fn approval_message(
    action: &InteractionAction,
    selected_target: Option<&SelectedTarget>,
) -> String {
    let base = match action.kind() {
        InteractionKind::OpenApplication => format!("Smolit möchte {0}", action.title.to_lowercase()),
        InteractionKind::FocusWindow => {
            let label = action
                .title
                .strip_prefix("Focus ")
                .unwrap_or(&action.title);
            format!("Smolit möchte das Fenster \"{label}\" fokussieren.")
        }
        InteractionKind::TypeText => format!("Smolit möchte Text eingeben: {}", action.title),
        InteractionKind::SendShortcut => {
            format!("Smolit möchte einen Shortcut senden: {}", action.title)
        }
        InteractionKind::Noop | InteractionKind::Unknown => {
            format!("Confirm {kind}: {title}",
                kind = action.kind().as_str(),
                title = action.title
            )
        }
    };
    match selected_target {
        Some(target) => format!("{base} Ziel: {}", target.short_label()),
        None => base,
    }
}
