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

use crate::config::LlamafileConfig;

/// Dateiname innerhalb des Settings-Verzeichnisses.
const LLAMAFILE_OVERRIDE_FILENAME: &str = "llamafile_local.json";
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
    let dir = path
        .parent()
        .context("settings path has no parent directory")?;
    fs::create_dir_all(dir).context("failed to ensure settings directory exists")?;

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
    let json = serde_json::to_string_pretty(&body)
        .context("failed to serialize llamafile override")?;

    let tmp = path.with_extension("json.tmp");
    {
        let mut f = fs::File::create(&tmp)
            .context("failed to create temporary settings file")?;
        f.write_all(json.as_bytes())
            .context("failed to write settings body")?;
        f.sync_all().ok();
    }
    // On Unix set conservative permissions. Path is not a secret, but
    // 0600 matches the posture of the future sensitive-store without
    // requiring a second file-layout decision later.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    }
    fs::rename(&tmp, &path).context("failed to atomically replace settings file")?;
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
}
