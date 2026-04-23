//! Dedizierter Secret-/Sensitive-Store (PR 10 der Provider-Fallback-/
//! Settings-Linie).
//!
//! **Bewusst getrennt** vom operationalen
//! [`crate::settings_store`], damit die Trennlinie aus
//! `docs/provider_fallback_and_settings_architecture.md` §11
//! („Secrets- und Sensitive-Config-Kategorien") auch auf Code-Ebene
//! sichtbar ist: sensitive Werte leben in einer eigenen Datei, haben
//! einen eigenen Serde-Typ und werden nie versehentlich gemeinsam mit
//! operationalen Overrides serialisiert oder geloggt.
//!
//! # Dateiformat
//!
//! Eine kleine JSON-Datei mit genau den zu speichernden Secrets:
//!
//! ```json
//! {
//!   "cloud_http_api_key": "sk-xxxxx"
//! }
//! ```
//!
//! Nicht gesetzte Felder werden beim Serialisieren **weggelassen**
//! (`skip_serializing_if = "Option::is_none"`), damit das
//! Override-File nicht größer wird als der tatsächlich gespeicherte
//! Geheim-Inhalt. Ein leerer Store = Datei nicht vorhanden.
//!
//! # Pfadauflösung
//!
//! Priorität absteigend, identisch zum operationalen Store:
//!
//!   1. `SMOLIT_SETTINGS_DIR` (Test-Override).
//!   2. `$XDG_CONFIG_HOME/smolit-assistant/`.
//!   3. `$HOME/.config/smolit-assistant/`.
//!
//! Dateiname: `secrets.json`.
//!
//! # Disziplin-Regeln
//!
//! Das Modul ist **das einzige**, das Secret-Klartext sieht. Alles
//! darüber hinaus arbeitet mit:
//!
//!   * einer `Option<String>` im In-Memory-Stand (App-Mutex), oder
//!   * einem boolschen „is present"-Flag in [`crate::app::StatusPayload`].
//!
//! Secret-Klartext darf **nie**:
//!
//!   * im StatusPayload auftauchen,
//!   * im EventBus auftauchen,
//!   * in `error`-Envelopes auftauchen,
//!   * in `tracing::info!` / `warn!` / `error!`-Zeilen auftauchen
//!     (auch nicht gekürzt oder gehasht — wir haben schlicht
//!     nichts davon zu loggen),
//!   * in Probe-Response-Messages auftauchen.
//!
//! Der Schreibpfad speichert atomar (temp + rename) und setzt auf
//! Unix Permissions `0600`, damit das File selbst nur vom laufenden
//! Nutzer gelesen werden kann.

use std::fs;
use std::io::Write;
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

/// Dateiname innerhalb des Settings-Verzeichnisses.
const SECRETS_FILENAME: &str = "secrets.json";
const ENV_SETTINGS_DIR: &str = "SMOLIT_SETTINGS_DIR";

/// In-Memory-Repräsentation der Secret-Datei. Alle Felder optional,
/// damit eine zukünftige Erweiterung (zweiter Cloud-Provider,
/// Refresh-Token, …) ältere Dateien nicht bricht. `PartialEq` für
/// Tests; `Debug` bewusst **ohne** Feld-Inhalte (siehe
/// [`ManualDebug`] unten).
#[derive(Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct SecretsFile {
    /// API-Key für den `cloud_http`-Text-Provider (PR 10). Wird als
    /// `Authorization: Bearer <value>` an den konfigurierten Endpoint
    /// geschickt. Nicht editierbar von außen ohne expliziten
    /// Settings-Schreibpfad.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cloud_http_api_key: Option<String>,
}

/// Custom `Debug`-Implementierung, damit `tracing::debug!` oder
/// `?secrets`-Ausdrücke **niemals** den Klartext eines Secrets zeigen.
/// Stattdessen wird pro Feld nur „set"/„unset" ausgegeben.
impl std::fmt::Debug for SecretsFile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SecretsFile")
            .field(
                "cloud_http_api_key",
                &if self.cloud_http_api_key.is_some() {
                    "<set>"
                } else {
                    "<unset>"
                },
            )
            .finish()
    }
}

pub fn resolve_secrets_path() -> Option<PathBuf> {
    resolve_settings_dir().map(|dir| dir.join(SECRETS_FILENAME))
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

/// Lädt den Secret-Store. Eine fehlende Datei ist **kein Fehler** —
/// der Core läuft dann ohne persistierte Secrets. Lesefehler (I/O,
/// JSON) werden auf einen leeren Store gemappt und im Aufrufer
/// sichtbar geloggt; ein kaputter Store soll den Core nicht blockieren.
///
/// **Kein Secret-Leak im Log-Pfad.** Bei Parse-Fehlern wird bewusst
/// nur ein String ohne Datei-Inhalt geloggt.
pub fn load_secrets() -> SecretsFile {
    let Some(path) = resolve_secrets_path() else {
        return SecretsFile::default();
    };
    let Ok(raw) = fs::read_to_string(&path) else {
        return SecretsFile::default();
    };
    match serde_json::from_str::<SecretsFile>(&raw) {
        Ok(file) => file,
        Err(err) => {
            // Error-Kind wird **nicht** gelogged, weil serde den Roh-
            // Inhalt in seiner Fehlermeldung zitieren könnte und das
            // im Secret-Kontext katastrophal wäre. Nur ein generischer
            // Hinweis.
            let _ = err;
            tracing::warn!(
                "secrets_store: secrets file is not valid JSON; ignoring (secrets will be treated as unset)",
            );
            SecretsFile::default()
        }
    }
}

/// Schreibt den Secret-Store atomar (temp + rename). Auf Unix wird
/// die temporäre Datei vor dem Rename auf `0600` gesetzt, damit der
/// finale Pfad nie mit offenen Permissions existiert.
///
/// **Keine Log-Zeile mit dem Inhalt.** Der Schreibpfad loggt nur
/// „saved".
pub fn save_secrets(secrets: &SecretsFile) -> Result<()> {
    let Some(path) = resolve_secrets_path() else {
        bail!(
            "no writable settings dir for secrets (neither SMOLIT_SETTINGS_DIR nor $XDG_CONFIG_HOME nor $HOME)"
        )
    };
    let dir = path
        .parent()
        .context("secrets path has no parent directory")?;
    fs::create_dir_all(dir).context("failed to ensure settings directory exists")?;

    let json = serde_json::to_string_pretty(secrets)
        .context("failed to serialize secrets (should not leak content — serialization error only)")?;

    let tmp = path.with_extension("json.tmp");
    {
        let mut f = fs::File::create(&tmp)
            .context("failed to create temporary secrets file")?;
        f.write_all(json.as_bytes())
            .context("failed to write secrets body")?;
        f.sync_all().ok();
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // 0600: nur Besitzer liest/schreibt. Schon auf der tmp-Datei
        // gesetzt, bevor das Rename sie sichtbar macht.
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    }
    fs::rename(&tmp, &path).context("failed to atomically replace secrets file")?;
    Ok(())
}

/// Komfort-Update: setzt genau den `cloud_http_api_key`, lädt und
/// speichert die Datei. `value=None` lässt den Rest des Store
/// unberührt und entfernt den Key (wird mit `skip_serializing_if`
/// weggelassen). Ein leerer / nur-Whitespace-String wird wie `None`
/// behandelt, damit die UI einen Clear-Pfad hat ohne eine eigene
/// Message.
pub fn set_cloud_http_api_key(value: Option<String>) -> Result<()> {
    let mut current = load_secrets();
    let normalized = value
        .map(|v| v.trim().to_string())
        .filter(|s| !s.is_empty());
    current.cloud_http_api_key = normalized;
    save_secrets(&current)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Serialisiert alle Tests, die `SMOLIT_SETTINGS_DIR` setzen. Der
    /// Env-Var ist Prozess-global; cargo-test läuft standardmäßig
    /// parallel — ohne dieses Lock würde Test A's Schreibpfad in
    /// Test B's Dir landen.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn fresh_env_dir(marker: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!(
            "smolit-secrets-test-{marker}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        base
    }

    #[test]
    fn load_without_file_returns_empty() {
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("no-file");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let s = load_secrets();
        assert!(s.cloud_http_api_key.is_none());
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn save_then_load_roundtrip_preserves_key() {
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("roundtrip");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let s = SecretsFile {
            cloud_http_api_key: Some("sk-test-abc123".into()),
        };
        save_secrets(&s).unwrap();
        let loaded = load_secrets();
        assert_eq!(loaded.cloud_http_api_key.as_deref(), Some("sk-test-abc123"));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn set_cloud_http_api_key_with_some_persists_value() {
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("set-some");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        set_cloud_http_api_key(Some("sk-test-xyz".into())).unwrap();
        let loaded = load_secrets();
        assert_eq!(loaded.cloud_http_api_key.as_deref(), Some("sk-test-xyz"));
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn set_cloud_http_api_key_with_none_clears_value() {
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("set-none");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        set_cloud_http_api_key(Some("sk-remove-me".into())).unwrap();
        assert!(load_secrets().cloud_http_api_key.is_some());
        set_cloud_http_api_key(None).unwrap();
        assert!(load_secrets().cloud_http_api_key.is_none());
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn set_cloud_http_api_key_empty_string_is_treated_as_clear() {
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("set-empty");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        set_cloud_http_api_key(Some("sk-to-be-removed".into())).unwrap();
        set_cloud_http_api_key(Some("   ".into())).unwrap();
        assert!(load_secrets().cloud_http_api_key.is_none());
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn debug_impl_never_prints_secret_plaintext() {
        let s = SecretsFile {
            cloud_http_api_key: Some("sk-this-must-not-leak".into()),
        };
        let rendered = format!("{s:?}");
        assert!(
            !rendered.contains("sk-this-must-not-leak"),
            "Debug impl leaked secret plaintext: {rendered}",
        );
        assert!(rendered.contains("<set>"));
    }

    #[cfg(unix)]
    #[test]
    fn saved_file_has_0600_permissions() {
        use std::os::unix::fs::PermissionsExt;
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("perms");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        save_secrets(&SecretsFile {
            cloud_http_api_key: Some("sk-perm".into()),
        })
        .unwrap();
        let path = resolve_secrets_path().unwrap();
        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "secrets file must be 0600 on unix, got {mode:o}");
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }

    #[test]
    fn parse_error_does_not_panic_and_yields_empty() {
        let _g = ENV_LOCK.lock().unwrap();
        let dir = fresh_env_dir("bad-json");
        unsafe {
            std::env::set_var(ENV_SETTINGS_DIR, dir.as_os_str());
        }
        let path = resolve_secrets_path().unwrap();
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "not json at all").unwrap();
        let loaded = load_secrets();
        assert!(loaded.cloud_http_api_key.is_none());
        unsafe {
            std::env::remove_var(ENV_SETTINGS_DIR);
        }
    }
}
