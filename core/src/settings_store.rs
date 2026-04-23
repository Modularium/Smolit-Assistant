//! Persistenter Settings-Store (PR 5 der Provider-Fallback-/Settings-Linie).
//!
//! Scope dieses Moduls ist bewusst eng: wir brauchen **jetzt** nur einen
//! schmalen, sicheren Schreibpfad für den editierbaren Teil der
//! `LlamafileConfig` (enabled / mode / idle_timeout_seconds / path). Das
//! Modul ist der einzige Ort, an dem diese Konfiguration persistent
//! geschrieben oder gelesen wird — kein paralleler zweiter Ort.
//!
//! # Kategorien sensibler Werte
//!
//! Der Store kennt zwei Kategorien und behandelt sie bewusst anders:
//!
//!   * **Operational.** Pfade zu lokalen Binaries, Ports, Timeouts,
//!     boolesche Feature-Flags. Dürfen persistiert werden, dürfen in
//!     UI-Readouts erscheinen, dürfen in Logs stehen — unter der
//!     Einschränkung, dass Pfade selbst defensiv behandelt werden (siehe
//!     unten).
//!   * **Sensitive.** API-Keys, Tokens, Basic-Auth-Credentials. Diese
//!     existieren heute nicht und werden **nicht** in diesem Modul
//!     gespeichert. Wenn sie jemals auftauchen, bekommen sie einen
//!     eigenen Store mit Datei-Permissions 0600 und **dürfen nicht** in
//!     das StatusPayload, in Event-Envelopes oder Logs gelangen.
//!
//! Pfade zu lokalen Binaries sind formal „operational", werden aber in
//! Logs nur als „present"/"unset" vermerkt — der tatsächliche Pfad
//! taucht weder im `info!`-Pfad noch im `SettingsProbeResult` auf, damit
//! ein versehentlicher Screenshot oder Log-Snippet keinen Pfadhinweis
//! preisgibt. Das hält die Oberfläche konservativ, auch wenn der Wert
//! selbst kein Secret ist.
//!
//! # Dateiformat
//!
//! Eine kleine JSON-Datei mit genau den editierbaren Feldern:
//!
//! ```json
//! {
//!   "enabled": true,
//!   "mode": "on_demand",
//!   "idle_timeout_seconds": 300,
//!   "path": "/opt/llamafile/server"
//! }
//! ```
//!
//! Nicht gesetzte Felder werden ausgelassen. Der Lader ist tolerant
//! gegenüber fehlenden Feldern; jedes übernommene Feld überschreibt den
//! Env-basierten Default aus [`crate::config::LlamafileConfig`].
//!
//! # Pfadauflösung
//!
//! Priorität absteigend:
//!
//!   1. `SMOLIT_SETTINGS_DIR` (Test-Override / explizite Konfiguration).
//!   2. `$XDG_CONFIG_HOME/smolit-assistant/`.
//!   3. `$HOME/.config/smolit-assistant/`.
//!
//! Ohne `$HOME` (z. B. in Containern) ist der Store lesefähig (liefert
//! dann schlicht `None`), aber nicht schreibfähig — der Aufrufer
//! bekommt in dem Fall einen ehrlichen `Err`.

use std::fs;
use std::io::Write;
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::config::{AudioConfig, LlamafileConfig, LocalHttpConfig};

/// Dateiname innerhalb des Settings-Verzeichnisses.
const LLAMAFILE_OVERRIDE_FILENAME: &str = "llamafile_local.json";
/// STT-Override-Datei (PR 7). Nur die vom Nutzer editierbaren Felder
/// werden persistiert — Timeout und Chain bleiben env-gesteuert.
const STT_OVERRIDE_FILENAME: &str = "stt.json";
/// TTS-Override-Datei (PR 7). Symmetrisch zum STT-Fall, zusätzlich
/// `auto_speak` als einzigem TTS-spezifischem Feld.
const TTS_OVERRIDE_FILENAME: &str = "tts.json";
/// Local-HTTP-Override-Datei (PR 8). Persistiert nur die in der
/// Settings-Shell editierbaren Felder (`enabled`, `endpoint`,
/// `request_timeout_seconds`). Prompt-/Response-Feldnamen bleiben
/// env-/Startup-gesteuert, damit ein späterer Provider-Wechsel nicht
/// an einem alten Override-File hängen bleibt.
const LOCAL_HTTP_OVERRIDE_FILENAME: &str = "local_http.json";
/// Env-Var für den Settings-Verzeichnis-Override (Tests, explizite
/// Konfiguration). Akzeptiert einen absoluten Pfad.
const ENV_SETTINGS_DIR: &str = "SMOLIT_SETTINGS_DIR";

/// Dateiform des Overrides. Alle Felder sind optional, damit eine
/// zukünftige Erweiterung (z. B. neuer Port) ältere Dateien nicht
/// bricht; der Loader übernimmt nur bekannte Felder.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LlamafileOverrideFile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub idle_timeout_seconds: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}

/// Liefert den Override-Dateipfad, wenn sich ein Settings-Verzeichnis
/// auflösen lässt. `None` bedeutet: weder `SMOLIT_SETTINGS_DIR` noch
/// `$XDG_CONFIG_HOME` noch `$HOME` sind gesetzt — der Store arbeitet
/// dann im „nur-Defaults"-Modus (Lesen liefert leer, Schreiben
/// schlägt ehrlich mit Fehler fehl).
pub fn resolve_llamafile_override_path() -> Option<PathBuf> {
    resolve_settings_dir().map(|dir| dir.join(LLAMAFILE_OVERRIDE_FILENAME))
}

fn resolve_settings_dir() -> Option<PathBuf> {
    if let Ok(value) = std::env::var(ENV_SETTINGS_DIR) {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            return Some(PathBuf::from(trimmed));
        }
    }
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        let trimmed = xdg.trim();
        if !trimmed.is_empty() {
            return Some(PathBuf::from(trimmed).join("smolit-assistant"));
        }
    }
    std::env::var("HOME")
        .ok()
        .filter(|h| !h.trim().is_empty())
        .map(|home| PathBuf::from(home).join(".config").join("smolit-assistant"))
}

/// Lädt den gespeicherten Llamafile-Override, falls vorhanden. Eine
/// fehlende Datei ist **kein** Fehler — der Core läuft dann mit den
/// Env-Defaults aus [`crate::config::LlamafileConfig`].
///
/// Lesefehler (I/O, JSON) werden als `Ok(None)` behandelt und im
/// Aufrufer sichtbar geloggt — ein kaputter Store soll den Core nicht
/// blockieren.
pub fn load_llamafile_override() -> LlamafileOverrideFile {
    let Some(path) = resolve_llamafile_override_path() else {
        return LlamafileOverrideFile::default();
    };
    let Ok(raw) = fs::read_to_string(&path) else {
        return LlamafileOverrideFile::default();
    };
    match serde_json::from_str::<LlamafileOverrideFile>(&raw) {
        Ok(file) => file,
        Err(err) => {
            tracing::warn!(
                error = %err,
                "settings_store: llamafile override file is not valid JSON; ignoring",
            );
            LlamafileOverrideFile::default()
        }
    }
}

/// Mischt den geladenen Override in eine bestehende
/// [`LlamafileConfig`]. Gesetzte Felder gewinnen; nicht gesetzte Felder
/// bleiben unverändert. Env-Defaults sind also nur ein Startpunkt —
/// sobald ein Nutzer über die Shell gespeichert hat, bestimmt der
/// Store.
pub fn apply_llamafile_override(
    base: LlamafileConfig,
    override_file: &LlamafileOverrideFile,
) -> LlamafileConfig {
    let mut merged = base;
    if let Some(enabled) = override_file.enabled {
        merged.enabled = enabled;
    }
    if let Some(mode) = override_file.mode.as_deref() {
        // Whitelist bleibt in der Config (single source of truth).
        if let Some(validated) = crate::config::validate_llamafile_mode(mode) {
            merged.mode = validated.to_string();
        } else {
            tracing::warn!(
                stored_mode = %mode,
                "settings_store: override mode is not in whitelist; ignoring",
            );
        }
    }
    if let Some(idle) = override_file.idle_timeout_seconds {
        if idle > 0 {
            merged.idle_timeout_seconds = idle;
        }
    }
    if let Some(path) = override_file.path.as_deref() {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            merged.path = None;
        } else {
            merged.path = Some(trimmed.to_string());
        }
    }
    merged
}

/// Persistiert den aktuellen Stand der editierbaren Llamafile-Felder.
/// Schreibt atomar (temp + rename), damit ein Crash zwischen `write`
/// und `rename` die bestehende Datei nicht beschädigt.
///
/// Der Aufrufer loggt das Ergebnis nicht verbose — insbesondere darf
/// weder der Pfad zum Binary noch das Store-Verzeichnis in `info!`-
/// oder `error!`-Zeilen landen. Wir loggen nur „settings saved"
/// bzw. eine kurze Fehlerklasse.
pub fn save_llamafile_override(cfg: &LlamafileConfig) -> Result<()> {
    let Some(path) = resolve_llamafile_override_path() else {
        bail!("no writable settings dir (neither SMOLIT_SETTINGS_DIR nor $XDG_CONFIG_HOME nor $HOME)")
    };
    // Nur die editierbaren Felder serialisieren. Port / Startup-/
    // Request-Timeout bleiben bewusst env-gesteuert und landen **nicht**
    // im Override — die UI hat dafür heute kein Editorfeld, und ein
    // unbeabsichtigtes Überschreiben aus einer älteren Datei würde mehr
    // schaden als nutzen.
    let body = LlamafileOverrideFile {
        enabled: Some(cfg.enabled),
        mode: Some(cfg.mode.clone()),
        idle_timeout_seconds: Some(cfg.idle_timeout_seconds),
        path: cfg.path.clone(),
    };
    // Shared atomic writer keeps the three override files (llamafile,
    // stt, tts) on byte-identical semantics (temp + rename, 0600 on
    // Unix) — see `write_override_atomic`.
    write_override_atomic(&path, &body, "llamafile")
}

// -----------------------------------------------------------------------
// PR 7 — STT/TTS-Overrides.
//
// Analog zum Llamafile-Override, bewusst kleiner: nur die Felder, die
// auch in der Settings-Shell editierbar sind. Timeouts und Provider-
// Chain bleiben env-/Startup-gesteuert — ein „versehentliches
// Abschalten einer zukünftigen Cloud-Kette über einen leeren Legacy-
// Override" wollen wir nicht haben.
// -----------------------------------------------------------------------

/// Dateiform des STT-Overrides (PR 7). Alle Felder sind optional, damit
/// Zukunfts-Erweiterungen ältere Dateien nicht brechen.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SttOverrideFile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    /// `None`                         → Command unverändert lassen.
    /// `Some("")` / nur Whitespace    → Command löschen.
    /// `Some("whisper --model base")` → Command setzen.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
}

/// Dateiform des TTS-Overrides (PR 7). Wie STT, zusätzlich
/// `auto_speak`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TtsOverrideFile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_speak: Option<bool>,
}

pub fn resolve_stt_override_path() -> Option<PathBuf> {
    resolve_settings_dir().map(|dir| dir.join(STT_OVERRIDE_FILENAME))
}

pub fn resolve_tts_override_path() -> Option<PathBuf> {
    resolve_settings_dir().map(|dir| dir.join(TTS_OVERRIDE_FILENAME))
}

pub fn load_stt_override() -> SttOverrideFile {
    let Some(path) = resolve_stt_override_path() else {
        return SttOverrideFile::default();
    };
    let Ok(raw) = fs::read_to_string(&path) else {
        return SttOverrideFile::default();
    };
    match serde_json::from_str::<SttOverrideFile>(&raw) {
        Ok(file) => file,
        Err(err) => {
            tracing::warn!(
                error = %err,
                "settings_store: stt override file is not valid JSON; ignoring",
            );
            SttOverrideFile::default()
        }
    }
}

pub fn load_tts_override() -> TtsOverrideFile {
    let Some(path) = resolve_tts_override_path() else {
        return TtsOverrideFile::default();
    };
    let Ok(raw) = fs::read_to_string(&path) else {
        return TtsOverrideFile::default();
    };
    match serde_json::from_str::<TtsOverrideFile>(&raw) {
        Ok(file) => file,
        Err(err) => {
            tracing::warn!(
                error = %err,
                "settings_store: tts override file is not valid JSON; ignoring",
            );
            TtsOverrideFile::default()
        }
    }
}

/// Mischt den STT-Override in eine bestehende [`AudioConfig`]. Nicht
/// überschrieben werden: Timeouts, Provider-Chains, TTS-Felder.
pub fn apply_stt_override(base: AudioConfig, override_file: &SttOverrideFile) -> AudioConfig {
    let mut merged = base;
    if let Some(enabled) = override_file.enabled {
        merged.stt_enabled = enabled;
    }
    if let Some(cmd) = override_file.command.as_deref() {
        let trimmed = cmd.trim();
        if trimmed.is_empty() {
            merged.stt_cmd = None;
        } else {
            merged.stt_cmd = Some(trimmed.to_string());
        }
    }
    merged
}

/// Mischt den TTS-Override in eine bestehende [`AudioConfig`].
pub fn apply_tts_override(base: AudioConfig, override_file: &TtsOverrideFile) -> AudioConfig {
    let mut merged = base;
    if let Some(enabled) = override_file.enabled {
        merged.tts_enabled = enabled;
    }
    if let Some(cmd) = override_file.command.as_deref() {
        let trimmed = cmd.trim();
        if trimmed.is_empty() {
            merged.tts_cmd = None;
        } else {
            merged.tts_cmd = Some(trimmed.to_string());
        }
    }
    if let Some(auto) = override_file.auto_speak {
        merged.auto_speak = auto;
    }
    merged
}

/// Persistiert den aktuellen Stand der editierbaren STT-Felder
/// (enabled, command). Atomar (temp + rename), 0600 auf Unix. Der
/// Command-String selbst ist kein Secret, wird aber — analog zum
/// Llamafile-Pfad — defensiv behandelt (keine Klartext-Logs).
pub fn save_stt_override(audio: &AudioConfig) -> Result<()> {
    let Some(path) = resolve_stt_override_path() else {
        bail!("no writable settings dir (neither SMOLIT_SETTINGS_DIR nor $XDG_CONFIG_HOME nor $HOME)")
    };
    let body = SttOverrideFile {
        enabled: Some(audio.stt_enabled),
        command: audio.stt_cmd.clone(),
    };
    write_override_atomic(&path, &body, "stt")
}

/// Persistiert den aktuellen Stand der editierbaren TTS-Felder
/// (enabled, command, auto_speak).
pub fn save_tts_override(audio: &AudioConfig) -> Result<()> {
    let Some(path) = resolve_tts_override_path() else {
        bail!("no writable settings dir (neither SMOLIT_SETTINGS_DIR nor $XDG_CONFIG_HOME nor $HOME)")
    };
    let body = TtsOverrideFile {
        enabled: Some(audio.tts_enabled),
        command: audio.tts_cmd.clone(),
        auto_speak: Some(audio.auto_speak),
    };
    write_override_atomic(&path, &body, "tts")
}

// -----------------------------------------------------------------------
// PR 8 — Local-HTTP-Override.
//
// Analog zum Llamafile-Override, aber mit deutlich kleinerer
// Feldmenge: enabled + endpoint + request_timeout. Prompt-/Response-
// Feldnamen bleiben env-gesteuert, damit ein versehentlich altes
// Override-File einen zukünftigen Feldnamenswechsel nicht überstimmt.
// -----------------------------------------------------------------------

/// Dateiform des Local-HTTP-Overrides (PR 8). Alle Felder optional.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LocalHttpOverrideFile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    /// `None`                       → Endpoint unverändert lassen.
    /// `Some("")` / nur Whitespace  → Endpoint löschen.
    /// `Some("http://host/path")`   → Endpoint setzen.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub endpoint: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub request_timeout_seconds: Option<u64>,
}

pub fn resolve_local_http_override_path() -> Option<PathBuf> {
    resolve_settings_dir().map(|dir| dir.join(LOCAL_HTTP_OVERRIDE_FILENAME))
}

pub fn load_local_http_override() -> LocalHttpOverrideFile {
    let Some(path) = resolve_local_http_override_path() else {
        return LocalHttpOverrideFile::default();
    };
    let Ok(raw) = fs::read_to_string(&path) else {
        return LocalHttpOverrideFile::default();
    };
    match serde_json::from_str::<LocalHttpOverrideFile>(&raw) {
        Ok(file) => file,
        Err(err) => {
            tracing::warn!(
                error = %err,
                "settings_store: local_http override file is not valid JSON; ignoring",
            );
            LocalHttpOverrideFile::default()
        }
    }
}

/// Mischt den Override in eine bestehende [`LocalHttpConfig`]. Nicht
/// überschrieben werden: `prompt_field` / `response_field`.
pub fn apply_local_http_override(
    base: LocalHttpConfig,
    override_file: &LocalHttpOverrideFile,
) -> LocalHttpConfig {
    let mut merged = base;
    if let Some(enabled) = override_file.enabled {
        merged.enabled = enabled;
    }
    if let Some(endpoint) = override_file.endpoint.as_deref() {
        let trimmed = endpoint.trim();
        if trimmed.is_empty() {
            merged.endpoint = None;
        } else {
            merged.endpoint = Some(trimmed.to_string());
        }
    }
    if let Some(timeout) = override_file.request_timeout_seconds {
        if timeout > 0 {
            merged.request_timeout_seconds = timeout;
        }
    }
    merged
}

pub fn save_local_http_override(cfg: &LocalHttpConfig) -> Result<()> {
    let Some(path) = resolve_local_http_override_path() else {
        bail!("no writable settings dir (neither SMOLIT_SETTINGS_DIR nor $XDG_CONFIG_HOME nor $HOME)")
    };
    let body = LocalHttpOverrideFile {
        enabled: Some(cfg.enabled),
        endpoint: cfg.endpoint.clone(),
        request_timeout_seconds: Some(cfg.request_timeout_seconds),
    };
    write_override_atomic(&path, &body, "local_http")
}

fn write_override_atomic<T: Serialize>(path: &std::path::Path, body: &T, label: &str) -> Result<()> {
    let dir = path
        .parent()
        .context("settings path has no parent directory")?;
    fs::create_dir_all(dir).context("failed to ensure settings directory exists")?;

    let json = serde_json::to_string_pretty(body)
        .with_context(|| format!("failed to serialize {label} override"))?;
    let tmp = path.with_extension("json.tmp");
    {
        let mut f = fs::File::create(&tmp)
            .context("failed to create temporary settings file")?;
        f.write_all(json.as_bytes())
            .context("failed to write settings body")?;
        f.sync_all().ok();
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    }
    fs::rename(&tmp, path).context("failed to atomically replace settings file")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_env_dir(marker: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!(
            "smolit-settings-store-test-{marker}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        base
    }

    #[test]
    fn resolve_uses_env_override_when_set() {
        let dir = fresh_env_dir("resolve-env");
        // SAFETY: single-threaded test; we restore the var afterwards.
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let resolved = resolve_llamafile_override_path().unwrap();
        assert!(resolved.starts_with(&dir));
        assert!(resolved.ends_with(LLAMAFILE_OVERRIDE_FILENAME));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn save_then_load_roundtrip_preserves_fields() {
        let dir = fresh_env_dir("save-load");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let cfg = LlamafileConfig {
            enabled: true,
            path: Some("/opt/llamafile/server".into()),
            mode: "standby".into(),
            idle_timeout_seconds: 900,
            port: 8788,
            startup_timeout_seconds: 30,
            request_timeout_seconds: 60,
        };
        save_llamafile_override(&cfg).unwrap();
        let loaded = load_llamafile_override();
        assert_eq!(loaded.enabled, Some(true));
        assert_eq!(loaded.mode.as_deref(), Some("standby"));
        assert_eq!(loaded.idle_timeout_seconds, Some(900));
        assert_eq!(loaded.path.as_deref(), Some("/opt/llamafile/server"));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn apply_override_merges_only_present_fields() {
        let base = LlamafileConfig {
            enabled: false,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 30,
            request_timeout_seconds: 60,
        };
        // Nur `enabled` und `mode` kommen aus dem Override — der Rest
        // der Config muss unverändert bleiben.
        let over = LlamafileOverrideFile {
            enabled: Some(true),
            mode: Some("standby".into()),
            idle_timeout_seconds: None,
            path: None,
        };
        let merged = apply_llamafile_override(base, &over);
        assert!(merged.enabled);
        assert_eq!(merged.mode, "standby");
        assert_eq!(merged.idle_timeout_seconds, 300);
        assert!(merged.path.is_none());
        assert_eq!(merged.port, 8788);
    }

    #[test]
    fn apply_override_rejects_unknown_mode_silently() {
        let base = LlamafileConfig {
            enabled: false,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 30,
            request_timeout_seconds: 60,
        };
        let over = LlamafileOverrideFile {
            enabled: None,
            mode: Some("cloud".into()),
            idle_timeout_seconds: None,
            path: None,
        };
        let merged = apply_llamafile_override(base, &over);
        // Mode bleibt auf dem alten Wert — kein Silent-Freiform.
        assert_eq!(merged.mode, "on_demand");
    }

    #[test]
    fn apply_override_clears_path_when_empty_string() {
        let base = LlamafileConfig {
            enabled: true,
            path: Some("/old/path".into()),
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 30,
            request_timeout_seconds: 60,
        };
        let over = LlamafileOverrideFile {
            enabled: None,
            mode: None,
            idle_timeout_seconds: None,
            path: Some("   ".into()),
        };
        let merged = apply_llamafile_override(base, &over);
        // Leerer String (nach trim) → Path explizit auf None.
        assert!(merged.path.is_none());
    }

    #[test]
    fn save_without_any_config_dir_errors_honestly() {
        // Temporär alle drei möglichen Quellen entziehen.
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
            std::env::remove_var("XDG_CONFIG_HOME");
            std::env::remove_var("HOME");
        }
        let cfg = LlamafileConfig {
            enabled: false,
            path: None,
            mode: "on_demand".into(),
            idle_timeout_seconds: 300,
            port: 8788,
            startup_timeout_seconds: 30,
            request_timeout_seconds: 60,
        };
        assert!(save_llamafile_override(&cfg).is_err());
        // Defensive Wiederherstellung für andere Tests.
        if let Some(home) = dirs_like_home_guess() {
            unsafe {
                std::env::set_var("HOME", home);
            }
        }
    }

    fn dirs_like_home_guess() -> Option<String> {
        // /root unter dev-Container, /home/<user> sonst — egal, die
        // anderen Tests prüfen nicht auf spezifische Pfade.
        std::env::var("USER")
            .ok()
            .map(|u| format!("/home/{u}"))
            .or(Some("/tmp".into()))
    }

    // PR 7 — STT/TTS-Override-Tests.

    fn audio_base() -> AudioConfig {
        AudioConfig {
            tts_enabled: true,
            tts_cmd: Some("/bin/old-tts".into()),
            tts_timeout_seconds: 5,
            stt_enabled: false,
            stt_cmd: None,
            stt_timeout_seconds: 5,
            auto_speak: false,
            stt_provider_chain: vec!["command".into()],
            tts_provider_chain: vec!["command".into()],
        }
    }

    #[test]
    fn stt_save_then_load_roundtrip() {
        let dir = fresh_env_dir("stt-save-load");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let audio = AudioConfig {
            stt_enabled: true,
            stt_cmd: Some("whisper --model base".into()),
            ..audio_base()
        };
        save_stt_override(&audio).unwrap();
        let loaded = load_stt_override();
        assert_eq!(loaded.enabled, Some(true));
        assert_eq!(loaded.command.as_deref(), Some("whisper --model base"));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn tts_save_then_load_roundtrip_includes_auto_speak() {
        let dir = fresh_env_dir("tts-save-load");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let audio = AudioConfig {
            tts_enabled: true,
            tts_cmd: Some("espeak -v de".into()),
            auto_speak: true,
            ..audio_base()
        };
        save_tts_override(&audio).unwrap();
        let loaded = load_tts_override();
        assert_eq!(loaded.enabled, Some(true));
        assert_eq!(loaded.command.as_deref(), Some("espeak -v de"));
        assert_eq!(loaded.auto_speak, Some(true));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn apply_stt_override_merges_only_present_fields() {
        let base = audio_base();
        let over = SttOverrideFile {
            enabled: Some(true),
            command: Some("whisper".into()),
        };
        let merged = apply_stt_override(base, &over);
        assert!(merged.stt_enabled);
        assert_eq!(merged.stt_cmd.as_deref(), Some("whisper"));
        // TTS bleibt unberührt.
        assert_eq!(merged.tts_cmd.as_deref(), Some("/bin/old-tts"));
    }

    #[test]
    fn apply_stt_override_clears_command_when_empty_string() {
        let base = AudioConfig {
            stt_cmd: Some("/old/stt".into()),
            ..audio_base()
        };
        let over = SttOverrideFile {
            enabled: None,
            command: Some("   ".into()),
        };
        let merged = apply_stt_override(base, &over);
        assert!(merged.stt_cmd.is_none());
    }

    // PR 8 — Local-HTTP-Override-Tests.

    fn local_http_base() -> LocalHttpConfig {
        LocalHttpConfig {
            enabled: false,
            endpoint: Some("http://127.0.0.1:8000/completion".into()),
            request_timeout_seconds: 30,
            prompt_field: "prompt".into(),
            response_field: "content".into(),
        }
    }

    #[test]
    fn local_http_save_then_load_roundtrip_preserves_fields() {
        let dir = fresh_env_dir("lh-save-load");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let cfg = LocalHttpConfig {
            enabled: true,
            endpoint: Some("http://127.0.0.1:8080/v1/completions".into()),
            request_timeout_seconds: 45,
            prompt_field: "prompt".into(),
            response_field: "content".into(),
        };
        save_local_http_override(&cfg).unwrap();
        let loaded = load_local_http_override();
        assert_eq!(loaded.enabled, Some(true));
        assert_eq!(
            loaded.endpoint.as_deref(),
            Some("http://127.0.0.1:8080/v1/completions"),
        );
        assert_eq!(loaded.request_timeout_seconds, Some(45));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn apply_local_http_override_merges_only_present_fields() {
        let base = local_http_base();
        let over = LocalHttpOverrideFile {
            enabled: Some(true),
            endpoint: None,
            request_timeout_seconds: None,
        };
        let merged = apply_local_http_override(base, &over);
        assert!(merged.enabled);
        // Endpoint und Timeout unverändert.
        assert_eq!(
            merged.endpoint.as_deref(),
            Some("http://127.0.0.1:8000/completion"),
        );
        assert_eq!(merged.request_timeout_seconds, 30);
        // Prompt-/Response-Felder dürfen vom Override nicht berührt werden.
        assert_eq!(merged.prompt_field, "prompt");
        assert_eq!(merged.response_field, "content");
    }

    #[test]
    fn apply_local_http_override_clears_endpoint_when_empty_string() {
        let base = local_http_base();
        let over = LocalHttpOverrideFile {
            enabled: None,
            endpoint: Some("   ".into()),
            request_timeout_seconds: None,
        };
        let merged = apply_local_http_override(base, &over);
        assert!(merged.endpoint.is_none());
    }

    #[test]
    fn apply_local_http_override_rejects_zero_timeout_silently() {
        let base = local_http_base();
        let over = LocalHttpOverrideFile {
            enabled: None,
            endpoint: None,
            request_timeout_seconds: Some(0),
        };
        let merged = apply_local_http_override(base, &over);
        // `0` ist im Override ungültig — Merge belässt den Basis-Wert.
        assert_eq!(merged.request_timeout_seconds, 30);
    }

    #[test]
    fn apply_tts_override_merges_auto_speak_and_command() {
        let base = audio_base();
        let over = TtsOverrideFile {
            enabled: Some(false),
            command: Some("".into()),
            auto_speak: Some(true),
        };
        let merged = apply_tts_override(base, &over);
        assert!(!merged.tts_enabled);
        assert!(merged.tts_cmd.is_none());
        assert!(merged.auto_speak);
        // STT bleibt unberührt.
        assert!(!merged.stt_enabled);
    }
}
