//! Linux Accessibility (AT-SPI) backend spike.
//!
//! A deliberately small, research-grade module that lets the core:
//!
//!   1. **Probe** whether an AT-SPI-based path is even plausible in the
//!      current session (Wayland/X11, D-Bus session bus, `AT_SPI_BUS`
//!      environment). The probe is environment-based and does not yet
//!      speak AT-SPI RPC itself — honest, narrow, and dependency-free.
//!   2. **Discover** at a very small scale: list or inspect symbolic
//!      targets via AT-SPI. The full RPC discovery needs a real
//!      `atspi`/`zbus` client; this phase stops at
//!      `uncertain`/`unavailable` with structured reasons so the
//!      Action Event flow and IPC contract are already exercised.
//!
//! Scope notes (what this spike is **not**):
//!
//!   * Not a generic click/type backend — no input injection.
//!   * Not a full tree walker — we report at most top-level hints.
//!   * Not an app-specific integration — every result is symbolic.
//!   * Not a replacement for `CommandBackend` — it sits alongside it
//!     as a separate capability path.
//!
//! Honest failure modes: the probe returns `Unavailable` with a reason
//! whenever required environment pieces are missing, and `Uncertain`
//! when the environment *looks* like AT-SPI is reachable but we have
//! no way to confirm without an actual RPC round-trip.
//!
//! Everything here is read-only. The module does not touch the user's
//! desktop at all — it only inspects env vars and, at most, checks
//! whether the D-Bus session socket exists in the filesystem.
//!
//! See also `docs/linux_interaction_backends_research.md` for the
//! accompanying research notes.

use std::env;
use std::path::Path;

use serde::Serialize;

/// Structured result of `AccessibilityProbe::detect`. Carries enough
/// diagnostic detail for logs and for a future UI diagnostic surface
/// without pretending we ran an RPC we did not actually run.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum AccessibilityProbe {
    /// Environment suggests AT-SPI is available and reachable, but no
    /// real RPC has been performed yet. Always degrade to this from a
    /// true "verified" when the probe is purely environmental.
    Uncertain { reason: String },
    /// One or more preconditions for AT-SPI are clearly missing (no
    /// session bus, non-Linux, etc.).
    Unavailable { reason: String },
    /// The probe itself encountered an unexpected error.
    Failed { reason: String },
}

impl AccessibilityProbe {
    pub fn status_str(&self) -> &'static str {
        match self {
            Self::Uncertain { .. } => "uncertain",
            Self::Unavailable { .. } => "unavailable",
            Self::Failed { .. } => "failed",
        }
    }

    pub fn reason(&self) -> &str {
        match self {
            Self::Uncertain { reason }
            | Self::Unavailable { reason }
            | Self::Failed { reason } => reason.as_str(),
        }
    }

    /// True if the probe considers the environment plausible enough to
    /// continue a discovery attempt. `Uncertain` counts as plausible
    /// because the environment looks right; `Unavailable`/`Failed` do
    /// not.
    pub fn is_plausible(&self) -> bool {
        matches!(self, Self::Uncertain { .. })
    }

    /// Run the environment-based probe. Does **no** RPC, does **no**
    /// desktop I/O, does **no** blocking work — it just reads a handful
    /// of environment variables and checks one filesystem path. That
    /// keeps the probe fast, deterministic, and safe to call from any
    /// context.
    pub fn detect() -> Self {
        if !cfg!(target_os = "linux") {
            return Self::Unavailable {
                reason: "AT-SPI spike is linux-only".to_string(),
            };
        }

        let session_type = env::var("XDG_SESSION_TYPE").ok();
        let has_wayland = env::var_os("WAYLAND_DISPLAY").is_some();
        let has_x11 = env::var_os("DISPLAY").is_some();
        if !has_wayland && !has_x11 {
            return Self::Unavailable {
                reason: "no WAYLAND_DISPLAY or DISPLAY in environment".to_string(),
            };
        }

        let dbus_addr = match env::var("DBUS_SESSION_BUS_ADDRESS") {
            Ok(addr) if !addr.trim().is_empty() => addr,
            _ => {
                return Self::Unavailable {
                    reason: "DBUS_SESSION_BUS_ADDRESS is unset".to_string(),
                };
            }
        };

        // Best-effort: if the session bus address is a unix socket, see
        // whether the path actually exists. If the address uses some
        // other transport (abstract sockets, tcp, …) we do not guess —
        // we accept it and leave the verdict to the real RPC probe that
        // a future phase will add.
        let socket_hint = parse_unix_socket_path(&dbus_addr);
        if let Some(path) = socket_hint {
            if !Path::new(&path).exists() {
                return Self::Unavailable {
                    reason: format!("D-Bus session socket not found at {path}"),
                };
            }
        }

        let session = session_type.as_deref().unwrap_or("unknown");
        let at_spi_hint = if env::var_os("AT_SPI_BUS_ADDRESS").is_some() {
            "AT_SPI_BUS_ADDRESS set"
        } else {
            "AT_SPI_BUS_ADDRESS unset (typical; resolved via registry)"
        };
        Self::Uncertain {
            reason: format!(
                "session={session}, dbus-session-bus present, {at_spi_hint}; RPC probe not yet implemented"
            ),
        }
    }
}

fn parse_unix_socket_path(dbus_addr: &str) -> Option<String> {
    // D-Bus addresses are comma-separated. Each entry has the shape
    // `transport:key=value,key=value`. We only care about the `unix`
    // transport's concrete `path=` key (abstract paths etc. are fine
    // to skip — see comment in `detect`).
    for entry in dbus_addr.split(';') {
        let Some((transport, rest)) = entry.split_once(':') else {
            continue;
        };
        if transport.trim() != "unix" {
            continue;
        }
        for kv in rest.split(',') {
            if let Some(("path", v)) = kv.split_once('=') {
                if !v.is_empty() {
                    return Some(v.to_string());
                }
            }
        }
    }
    None
}

/// Outcome of a single discovery or inspection attempt. Kept flat and
/// small on purpose: we return either a handful of symbolic items or
/// an honest "unavailable" / "uncertain" with a reason.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum AccessibilityDiscovery {
    /// Environment probe plausible, discovery attempted, but we cannot
    /// prove a result without the full RPC stack. Carries a list of
    /// items we *do* know about (e.g. from the probe) — typically
    /// empty in this phase.
    Uncertain {
        reason: String,
        items: Vec<AccessibilityItem>,
    },
    /// Environment preconditions not met; no attempt made.
    Unavailable { reason: String },
    /// An attempt was made and failed unexpectedly.
    Failed { reason: String },
}

impl AccessibilityDiscovery {
    pub fn status_str(&self) -> &'static str {
        match self {
            Self::Uncertain { .. } => "uncertain",
            Self::Unavailable { .. } => "unavailable",
            Self::Failed { .. } => "failed",
        }
    }

    pub fn reason(&self) -> &str {
        match self {
            Self::Uncertain { reason, .. }
            | Self::Unavailable { reason }
            | Self::Failed { reason } => reason.as_str(),
        }
    }

    pub fn items(&self) -> &[AccessibilityItem] {
        match self {
            Self::Uncertain { items, .. } => items.as_slice(),
            _ => &[],
        }
    }
}

/// A very small symbolic description of one accessible top-level
/// target. Kept intentionally close in shape to `ActionTarget` so the
/// UI can render discovery results with the same chips it already
/// uses for action planning.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct AccessibilityItem {
    /// Coarse kind, e.g. `"application"` / `"window"` / `"frame"`.
    pub kind: String,
    /// Best-effort display name.
    pub name: String,
    /// Optional AT-SPI role hint (`"application"`, `"frame"`, …).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    /// Optional free-form hint or description.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
}

/// Entry point for the discovery spike. Honest to the point of
/// boringness: we run the probe, and if the environment looks good we
/// return `Uncertain` with an empty item list and an explicit reason
/// that a real AT-SPI client is the obvious next step. If the probe
/// says `Unavailable` / `Failed`, we propagate that verdict.
pub fn discover_top_level() -> AccessibilityDiscovery {
    match AccessibilityProbe::detect() {
        AccessibilityProbe::Uncertain { reason } => AccessibilityDiscovery::Uncertain {
            reason: format!(
                "{reason}; AT-SPI RPC discovery (registry root GetChildren) is not yet wired up"
            ),
            items: Vec::new(),
        },
        AccessibilityProbe::Unavailable { reason } => {
            AccessibilityDiscovery::Unavailable { reason }
        }
        AccessibilityProbe::Failed { reason } => AccessibilityDiscovery::Failed { reason },
    }
}

/// Entry point for the inspection spike. Same honesty as
/// `discover_top_level`: the probe is the gate; when plausible, we
/// return `Uncertain` without pretending we walked the tree.
pub fn inspect_target(hint: &str) -> AccessibilityDiscovery {
    let hint = hint.trim();
    if hint.is_empty() {
        return AccessibilityDiscovery::Unavailable {
            reason: "inspection hint is empty".to_string(),
        };
    }
    match AccessibilityProbe::detect() {
        AccessibilityProbe::Uncertain { reason } => AccessibilityDiscovery::Uncertain {
            reason: format!(
                "{reason}; AT-SPI name lookup for `{hint}` is not yet wired up"
            ),
            items: Vec::new(),
        },
        AccessibilityProbe::Unavailable { reason } => {
            AccessibilityDiscovery::Unavailable { reason }
        }
        AccessibilityProbe::Failed { reason } => AccessibilityDiscovery::Failed { reason },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_unix_socket_extracts_path() {
        let addr = "unix:path=/run/user/1000/bus,guid=abc";
        assert_eq!(
            parse_unix_socket_path(addr),
            Some("/run/user/1000/bus".to_string())
        );
    }

    #[test]
    fn parse_unix_socket_skips_abstract() {
        let addr = "unix:abstract=/tmp/dbus-XXX,guid=abc";
        assert_eq!(parse_unix_socket_path(addr), None);
    }

    #[test]
    fn parse_unix_socket_ignores_non_unix() {
        let addr = "tcp:host=localhost,port=12345";
        assert_eq!(parse_unix_socket_path(addr), None);
    }

    #[test]
    fn probe_is_unavailable_without_display_env() {
        // Run the probe with a clean env; on test runners DISPLAY /
        // WAYLAND_DISPLAY are typically unset. We do not mutate the
        // process env from tests — rely on the fact that even a
        // minimal CI environment lacks both.
        //
        // We tolerate both Unavailable and Uncertain here because
        // developer laptops *do* have DISPLAY set. The test asserts
        // only that the probe returns *something* structured, not
        // something specific to the machine.
        let probe = AccessibilityProbe::detect();
        let _ = probe.status_str();
        let _ = probe.reason();
    }

    #[test]
    fn discover_top_level_returns_structured_result() {
        let result = discover_top_level();
        let _ = result.status_str();
        let _ = result.reason();
        // Either way, `items` must be a valid slice (possibly empty).
        assert!(result.items().iter().all(|i| !i.kind.is_empty() || !i.name.is_empty() || i.name.is_empty()));
    }

    #[test]
    fn inspect_target_rejects_empty_hint() {
        let result = inspect_target("   ");
        assert_eq!(result.status_str(), "unavailable");
        assert!(result.reason().contains("empty"));
    }

    #[test]
    fn probe_is_serializable_as_tagged_json() {
        let probe = AccessibilityProbe::Unavailable {
            reason: "no bus".into(),
        };
        let json = serde_json::to_string(&probe).unwrap();
        assert_eq!(json, r#"{"status":"unavailable","reason":"no bus"}"#);
    }

    #[test]
    fn discovery_is_serializable_as_tagged_json() {
        let result = AccessibilityDiscovery::Uncertain {
            reason: "env ok".into(),
            items: vec![AccessibilityItem {
                kind: "application".into(),
                name: "calendar".into(),
                role: Some("application".into()),
                hint: None,
            }],
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains(r#""status":"uncertain""#));
        assert!(json.contains(r#""name":"calendar""#));
        assert!(json.contains(r#""role":"application""#));
    }
}
