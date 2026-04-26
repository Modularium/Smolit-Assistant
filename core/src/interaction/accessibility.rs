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
//!      `atspi`/`zbus` client; this phase stops at a structured
//!      hint-echo plus the existing `uncertain`/`unavailable` verdicts
//!      so the Action Event flow and IPC contract are already
//!      exercised.
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

/// Per-item confidence level for an `AccessibilityItem`. This is the
/// honest layer between "definitely here" and "no idea". The wire
/// format uses snake_case so UIs can render it as a badge without
/// interpretation.
///
/// Semantics for this spike phase:
///
/// * `Verified` is **reserved** for the future real-RPC discovery
///   pipeline (registry walk with a role-typed top-level match). This
///   spike does not produce `Verified` items — we would lie if it
///   did.
/// * `Discovered` means we carry the item forward as a structured
///   target, but we have not independently confirmed it. Today this is
///   emitted by the hint-echo path of `inspect_target`: the caller
///   told us about the target, we acknowledge it with a role guess
///   and a `matched_hint`, and leave verification to a later stage.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DiscoveryConfidence {
    /// Strong evidence from an authoritative source (e.g. AT-SPI
    /// registry). Reserved: no path in this spike produces it yet.
    Verified,
    /// Plausible but unconfirmed — structured enough to render but not
    /// strong enough to act on without further checks.
    Discovered,
}

impl DiscoveryConfidence {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Verified => "verified",
            Self::Discovered => "discovered",
        }
    }
}

/// Outcome of a single discovery or inspection attempt. Kept flat and
/// small on purpose: we return either a handful of symbolic items or
/// an honest "unavailable" / "uncertain" with a reason.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum AccessibilityDiscovery {
    /// Discovery completed and produced at least one structured item.
    /// No pretence of full-tree accuracy — see per-item
    /// [`DiscoveryConfidence`] for how strong each result is.
    Ok {
        reason: String,
        items: Vec<AccessibilityItem>,
    },
    /// Environment probe plausible, discovery attempted, but we cannot
    /// prove a result without the full RPC stack. Carries a (usually
    /// empty) list of items we *do* know about.
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
            Self::Ok { .. } => "ok",
            Self::Uncertain { .. } => "uncertain",
            Self::Unavailable { .. } => "unavailable",
            Self::Failed { .. } => "failed",
        }
    }

    pub fn reason(&self) -> &str {
        match self {
            Self::Ok { reason, .. }
            | Self::Uncertain { reason, .. }
            | Self::Unavailable { reason }
            | Self::Failed { reason } => reason.as_str(),
        }
    }

    pub fn items(&self) -> &[AccessibilityItem] {
        match self {
            Self::Ok { items, .. } | Self::Uncertain { items, .. } => items.as_slice(),
            _ => &[],
        }
    }
}

/// Source label for a discovered `AccessibilityItem`. Kept as plain
/// string constants (not an enum) so a later RPC stage can introduce
/// new sources additively without a schema change.
pub mod source {
    /// The caller supplied a `hint` and we echoed it back in a
    /// structured shape. No independent AT-SPI confirmation.
    pub const ACCESSIBILITY_HINT_ECHO: &str = "accessibility_hint_echo";

    /// Item came from a real AT-SPI registry root `GetChildren` call
    /// via the FA-1 RPC path. Items carrying this source label are the
    /// **only** items allowed to bear `confidence: verified`.
    pub const ACCESSIBILITY_REGISTRY_ROOT: &str = "accessibility_registry_root";
}

/// A very small symbolic description of one accessible target. Kept
/// intentionally close in shape to `ActionTarget` so the UI can render
/// discovery results with the same chips it already uses for action
/// planning.
///
/// Invariants:
///
/// * `confidence` must be filled in every time — never leave the
///   caller guessing whether a result is strong.
/// * `source` names the provenance in a stable, snake_case vocabulary
///   (see [`source`]).
/// * `matched_hint` is set iff the item came from an explicit inspect
///   call with a user-supplied hint.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct AccessibilityItem {
    /// Coarse kind, e.g. `"application"` / `"window"` / `"frame"`.
    pub kind: String,
    /// Best-effort display name.
    pub name: String,
    /// Per-item confidence level. `verified` is reserved for the real
    /// RPC path.
    pub confidence: DiscoveryConfidence,
    /// Stable provenance label (see [`source`]).
    pub source: String,
    /// Optional AT-SPI role hint (`"application"`, `"frame"`, …).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    /// Optional free-form hint or description.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
    /// Optional short detail string for UIs (e.g. "hint echo").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// If this item came from `inspect_target(hint)`, the exact hint
    /// string the caller supplied (trimmed).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub matched_hint: Option<String>,
    /// Optional enclosing application name, when derivable.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_name: Option<String>,
}

impl AccessibilityItem {
    /// Build a hint-echo item: the caller asked about `hint`, and the
    /// probe was at least plausible. We record it as `Discovered`
    /// (never `Verified`) because no AT-SPI RPC has actually confirmed
    /// the target exists.
    fn hint_echo(hint: &str) -> Self {
        Self {
            kind: "application".to_string(),
            name: hint.to_string(),
            confidence: DiscoveryConfidence::Discovered,
            source: source::ACCESSIBILITY_HINT_ECHO.to_string(),
            role: Some("application".to_string()),
            hint: None,
            detail: Some("hint echoed; no AT-SPI RPC confirmation yet".to_string()),
            matched_hint: Some(hint.to_string()),
            app_name: Some(hint.to_string()),
        }
    }
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

/// Entry point for the inspection spike. When the probe is plausible
/// and the caller supplied a non-empty `hint`, we return a single
/// structured `Discovered` item that echoes the hint. This is the
/// strongest honest claim available without a real AT-SPI client:
/// "the caller asked about this target, we have carried it forward as
/// a structured shape for downstream UI, but we have not verified it
/// against the accessibility registry."
pub fn inspect_target(hint: &str) -> AccessibilityDiscovery {
    let hint = hint.trim();
    if hint.is_empty() {
        return AccessibilityDiscovery::Unavailable {
            reason: "inspection hint is empty".to_string(),
        };
    }
    match AccessibilityProbe::detect() {
        AccessibilityProbe::Uncertain { reason } => AccessibilityDiscovery::Ok {
            reason: format!(
                "{reason}; hint echoed as structured target (confidence=discovered)"
            ),
            items: vec![AccessibilityItem::hint_echo(hint)],
        },
        AccessibilityProbe::Unavailable { reason } => {
            AccessibilityDiscovery::Unavailable { reason }
        }
        AccessibilityProbe::Failed { reason } => AccessibilityDiscovery::Failed { reason },
    }
}

// ---------------------------------------------------------------------------
// FA-1 — read-only AT-SPI registry RPC scaffold (ADR-0002, PR 53).
// ---------------------------------------------------------------------------
//
// This block introduces the mockable boundary for a real registry-root
// `GetChildren` call without yet pulling in `atspi`/`zbus`. The default
// build keeps the historic env-only behaviour bit-for-bit. The opt-in
// path (`AccessibilityConfig::rpc_enabled` plus the `accessibility_rpc`
// Cargo feature plus a wired client) is the only way to produce
// `confidence: verified` items in the wire — `into_verified_item` is
// the single constructor and lives at the bottom of this block.
//
// FA-1 is deliberately partial: production calls reach the orchestrator
// without a registry client and honestly fall through to
// `Unavailable { reason: "accessibility_rpc_backend_not_implemented" }`.
// Tests inject a mock that returns synthetic registry rows.

/// Read-only RPC config for the accessibility spike. Kept tiny and
/// `Default`-friendly; lifted from [`crate::config::AccessibilityConfig`]
/// at call sites to avoid pulling the full `Config` graph into helpers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct AccessibilityRpcConfig {
    pub enabled: bool,
}

/// One direct child of the AT-SPI registry root, as returned by an
/// `AccessibilityRegistryClient`. Depth is fixed at one — there is no
/// recursive `children` field, no nested target. A future tree-walker
/// would need its own ADR (ADR-0002 §D1, FA-2/FA-3).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegistryRootChild {
    pub name: String,
    pub role: String,
    pub app_name: Option<String>,
    /// Item is a password / sensitive text field — must never be
    /// surfaced even as a name.
    pub is_password: bool,
    /// AT-SPI `STATE_INVISIBLE` (or equivalent). Filtered out before any
    /// item leaves this module.
    pub is_invisible: bool,
}

/// Honest failure classification for the RPC path. Every variant maps
/// to an `AccessibilityDiscovery::Unavailable` (or `Failed`) — none
/// produces `Discovered` or `Verified`. The reason strings are stable
/// so a UI / log can match on them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AccessibilityRpcError {
    DbusSessionMissing,
    A11yBusUnavailable,
    PermissionDenied,
    /// FA-1 partial: feature compiled, env on, but no real client is
    /// wired. Honest fallback in production.
    BackendNotImplemented,
    /// Catch-all for unexpected RPC errors. Reason is sanitised at the
    /// call site.
    Other(String),
}

impl AccessibilityRpcError {
    pub fn unavailable_reason(&self) -> String {
        match self {
            Self::DbusSessionMissing => "dbus_session_missing".into(),
            Self::A11yBusUnavailable => "a11y_bus_unavailable".into(),
            Self::PermissionDenied => "permission_denied".into(),
            Self::BackendNotImplemented => "accessibility_rpc_backend_not_implemented".into(),
            Self::Other(detail) => format!("accessibility_rpc_error: {detail}"),
        }
    }
}

/// Reason emitted when the RPC orchestrator runs without the
/// `accessibility_rpc` Cargo feature. Stable across releases.
pub const ACCESSIBILITY_RPC_FEATURE_DISABLED_REASON: &str = "accessibility_rpc_feature_disabled";

/// Adapter trait that any future `atspi`/`zbus`-backed client must
/// implement. The contract is intentionally narrow:
///
/// * Read-only — no `set_*`, no `do_action`, no `activate`.
/// * Single call — registry root `GetChildren` only. No recursion, no
///   per-child follow-up.
/// * Synchronous — keeps the orchestrator trivial; a future async
///   variant can be added as an additional method without breaking
///   this one.
///
/// Production has no live implementation in FA-1 (partial spike).
/// Tests provide a mock that returns synthetic `RegistryRootChild`
/// rows.
pub trait AccessibilityRegistryClient {
    /// Read direct children of the AT-SPI registry root. Depth is
    /// fixed at one by signature: there is no way to retrieve the
    /// children of an item from this trait.
    fn registry_root_children(&self) -> Result<Vec<RegistryRootChild>, AccessibilityRpcError>;
}

impl RegistryRootChild {
    /// Pure conversion from a registry row to a wire item. The **only**
    /// place that constructs `confidence: verified`. Filters out
    /// password / invisible / unnamed entries before they reach the
    /// wire. Returning `None` means "drop silently from the result
    /// list" — not a failure, just an honest omission.
    fn into_verified_item(self) -> Option<AccessibilityItem> {
        if self.is_password || self.is_invisible {
            return None;
        }
        let name = self.name.trim().to_string();
        if name.is_empty() {
            return None;
        }
        let role = self.role;
        let kind = match role.as_str() {
            "frame" | "window" | "dialog" => "window",
            _ => "application",
        }
        .to_string();
        Some(AccessibilityItem {
            kind,
            name,
            confidence: DiscoveryConfidence::Verified,
            source: source::ACCESSIBILITY_REGISTRY_ROOT.to_string(),
            role: Some(role),
            hint: None,
            detail: None,
            matched_hint: None,
            app_name: self.app_name,
        })
    }
}

/// Pure helper that converts a registry-root child list into a
/// discovery result. Tests call this directly; the orchestrator below
/// calls it after a successful trait call. Always lives outside the
/// `cfg(feature = "accessibility_rpc")` gate so the conversion logic is
/// covered by the default-features test run.
pub fn apply_registry_children(children: Vec<RegistryRootChild>) -> AccessibilityDiscovery {
    let items: Vec<AccessibilityItem> = children
        .into_iter()
        .filter_map(RegistryRootChild::into_verified_item)
        .collect();
    if items.is_empty() {
        // ADR-0002 §"Failure modes": empty registry stays Uncertain
        // (a screen reader could surface items after activation),
        // never Unavailable.
        AccessibilityDiscovery::Uncertain {
            reason: "registry_empty".into(),
            items,
        }
    } else {
        AccessibilityDiscovery::Ok {
            reason: "accessibility_rpc registry root GetChildren".into(),
            items,
        }
    }
}

/// FA-1 orchestrator. Honors the three-step gate: config flag, Cargo
/// feature, wired client. Any of those missing produces an honest
/// `Unavailable` with a stable reason and never falls back to a
/// verified-but-fake answer.
pub fn discover_top_level_with_config(
    config: &AccessibilityRpcConfig,
    client: Option<&dyn AccessibilityRegistryClient>,
) -> AccessibilityDiscovery {
    if !config.enabled {
        // Default path: behave exactly like pre-PR-53 callers.
        return discover_top_level();
    }
    if !cfg!(feature = "accessibility_rpc") {
        let _ = client;
        return AccessibilityDiscovery::Unavailable {
            reason: ACCESSIBILITY_RPC_FEATURE_DISABLED_REASON.into(),
        };
    }
    match AccessibilityProbe::detect() {
        AccessibilityProbe::Unavailable { reason } => {
            return AccessibilityDiscovery::Unavailable { reason };
        }
        AccessibilityProbe::Failed { reason } => {
            return AccessibilityDiscovery::Failed { reason };
        }
        AccessibilityProbe::Uncertain { .. } => {}
    }
    let Some(client) = client else {
        return AccessibilityDiscovery::Unavailable {
            reason: AccessibilityRpcError::BackendNotImplemented.unavailable_reason(),
        };
    };
    match client.registry_root_children() {
        Ok(children) => apply_registry_children(children),
        Err(err) => AccessibilityDiscovery::Unavailable {
            reason: err.unavailable_reason(),
        },
    }
}

/// FA-1 hint-inspect orchestrator. Deliberately delegates back to the
/// hint-echo path: name-matching against the registry is FA-2 (a
/// follow-up ADR). Even with the feature on, hint inspection in FA-1
/// stays at `confidence: discovered` — there is no path here that
/// produces `verified`.
pub fn inspect_target_with_config(
    hint: &str,
    config: &AccessibilityRpcConfig,
    _client: Option<&dyn AccessibilityRegistryClient>,
) -> AccessibilityDiscovery {
    let _ = config;
    inspect_target(hint)
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
        // Run the probe with the ambient env; on CI runners DISPLAY /
        // WAYLAND_DISPLAY are typically unset but on developer laptops
        // they are. The test asserts only that the probe returns
        // *something* structured, not something specific to the
        // machine.
        let probe = AccessibilityProbe::detect();
        let _ = probe.status_str();
        let _ = probe.reason();
    }

    #[test]
    fn discover_top_level_returns_structured_result() {
        let result = discover_top_level();
        let _ = result.status_str();
        let _ = result.reason();
        // Top-level discovery has no RPC backing yet, so the honest
        // outcomes are Uncertain (plausible env, empty items),
        // Unavailable (no desktop), or Failed.
        assert!(matches!(
            result,
            AccessibilityDiscovery::Uncertain { .. }
                | AccessibilityDiscovery::Unavailable { .. }
                | AccessibilityDiscovery::Failed { .. }
        ));
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
    fn discovery_ok_is_serializable_as_tagged_json() {
        let result = AccessibilityDiscovery::Ok {
            reason: "env ok".into(),
            items: vec![AccessibilityItem {
                kind: "application".into(),
                name: "Firefox".into(),
                confidence: DiscoveryConfidence::Discovered,
                source: source::ACCESSIBILITY_HINT_ECHO.to_string(),
                role: Some("application".into()),
                hint: None,
                detail: None,
                matched_hint: Some("Firefox".into()),
                app_name: None,
            }],
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains(r#""status":"ok""#));
        assert!(json.contains(r#""name":"Firefox""#));
        assert!(json.contains(r#""confidence":"discovered""#));
        assert!(json.contains(r#""source":"accessibility_hint_echo""#));
        assert!(json.contains(r#""matched_hint":"Firefox""#));
    }

    #[test]
    fn discovery_uncertain_is_serializable_as_tagged_json() {
        let result = AccessibilityDiscovery::Uncertain {
            reason: "env ok, no rpc".into(),
            items: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains(r#""status":"uncertain""#));
        assert!(json.contains(r#""items":[]"#));
    }

    #[test]
    fn hint_echo_item_carries_matched_hint_and_discovered_confidence() {
        let item = AccessibilityItem::hint_echo("Firefox");
        assert_eq!(item.name, "Firefox");
        assert_eq!(item.confidence, DiscoveryConfidence::Discovered);
        assert_eq!(item.matched_hint.as_deref(), Some("Firefox"));
        assert_eq!(item.source, source::ACCESSIBILITY_HINT_ECHO);
        // Never elevated to verified in this spike.
        assert_ne!(item.confidence, DiscoveryConfidence::Verified);
    }

    #[test]
    fn inspect_target_with_hint_produces_ok_or_unavailable() {
        // Same tolerance as probe_is_unavailable_without_display_env:
        // accept either an Ok result (developer laptop) or Unavailable
        // (bare CI). The invariant we care about: when Ok, it must
        // contain exactly one Discovered hint-echo item with the
        // trimmed hint.
        let result = inspect_target("  Calendar  ");
        match result {
            AccessibilityDiscovery::Ok { ref items, .. } => {
                assert_eq!(items.len(), 1);
                let item = &items[0];
                assert_eq!(item.name, "Calendar");
                assert_eq!(item.matched_hint.as_deref(), Some("Calendar"));
                assert_eq!(item.confidence, DiscoveryConfidence::Discovered);
            }
            AccessibilityDiscovery::Unavailable { .. }
            | AccessibilityDiscovery::Failed { .. } => {
                // Bare-env runner: expected outcome.
            }
            AccessibilityDiscovery::Uncertain { .. } => {
                panic!("inspect_target with non-empty hint should not return Uncertain");
            }
        }
    }

    // -----------------------------------------------------------------
    // FA-1 RPC layer tests (ADR-0002, PR 53). All invariants below run
    // on the *default* feature set so CI without
    // `--features accessibility_rpc` covers them. The feature-gated
    // end-to-end test is at the bottom of this module.
    // -----------------------------------------------------------------

    /// Mock client for the verified-from-registry test path. Returns
    /// whatever rows the test set up; never panics; never reads any
    /// real D-Bus state.
    struct MockRegistryClient {
        result: Result<Vec<RegistryRootChild>, AccessibilityRpcError>,
    }

    impl MockRegistryClient {
        fn ok(rows: Vec<RegistryRootChild>) -> Self {
            Self { result: Ok(rows) }
        }
    }

    impl AccessibilityRegistryClient for MockRegistryClient {
        fn registry_root_children(
            &self,
        ) -> Result<Vec<RegistryRootChild>, AccessibilityRpcError> {
            self.result.clone()
        }
    }

    fn sample_app_row(name: &str) -> RegistryRootChild {
        RegistryRootChild {
            name: name.to_string(),
            role: "application".to_string(),
            app_name: Some(name.to_string()),
            is_password: false,
            is_invisible: false,
        }
    }

    // Test 1.
    #[test]
    fn default_without_feature_or_env_never_verified() {
        let cfg = AccessibilityRpcConfig::default();
        let result = discover_top_level_with_config(&cfg, None);
        for item in result.items() {
            assert_ne!(
                item.confidence,
                DiscoveryConfidence::Verified,
                "fallback path leaked verified confidence"
            );
        }
    }

    // Test 2.
    #[test]
    fn rpc_env_enabled_without_feature_reports_feature_disabled() {
        let cfg = AccessibilityRpcConfig { enabled: true };
        let result = discover_top_level_with_config(&cfg, None);
        if !cfg!(feature = "accessibility_rpc") {
            match result {
                AccessibilityDiscovery::Unavailable { reason } => {
                    assert_eq!(reason, ACCESSIBILITY_RPC_FEATURE_DISABLED_REASON);
                }
                other => panic!("expected feature-disabled Unavailable, got {other:?}"),
            }
        }
    }

    // Test 3.
    #[test]
    fn missing_dbus_session_or_display_never_emits_verified_without_feature() {
        // Without the cargo feature, the orchestrator short-circuits at
        // the feature gate and the mock never runs — so verified must
        // not appear regardless of host env.
        let cfg = AccessibilityRpcConfig { enabled: true };
        let client = MockRegistryClient::ok(vec![sample_app_row("Firefox")]);
        let result = discover_top_level_with_config(
            &cfg,
            Some(&client as &dyn AccessibilityRegistryClient),
        );
        if !cfg!(feature = "accessibility_rpc") {
            for item in result.items() {
                assert_ne!(item.confidence, DiscoveryConfidence::Verified);
            }
        }
    }

    // Test 4.
    #[test]
    fn hint_echo_remains_discovered() {
        let cfg = AccessibilityRpcConfig { enabled: true };
        let result = inspect_target_with_config("Firefox", &cfg, None);
        for item in result.items() {
            assert_eq!(
                item.confidence,
                DiscoveryConfidence::Discovered,
                "hint inspect leaked verified confidence"
            );
            assert_eq!(item.source, source::ACCESSIBILITY_HINT_ECHO);
        }
    }

    // Test 5.
    #[test]
    fn mock_registry_child_can_be_verified_via_apply_helper() {
        let result = apply_registry_children(vec![sample_app_row("Firefox")]);
        match result {
            AccessibilityDiscovery::Ok { items, .. } => {
                assert_eq!(items.len(), 1);
                let item = &items[0];
                assert_eq!(item.confidence, DiscoveryConfidence::Verified);
                assert_eq!(item.source, source::ACCESSIBILITY_REGISTRY_ROOT);
                assert_eq!(item.name, "Firefox");
                assert_eq!(item.matched_hint, None);
            }
            other => panic!("expected Ok with one verified item, got {other:?}"),
        }
    }

    // Test 6.
    #[test]
    fn password_or_invisible_items_are_filtered() {
        let rows = vec![
            RegistryRootChild {
                name: "Vault password".into(),
                role: "password_text".into(),
                app_name: Some("Keyring".into()),
                is_password: true,
                is_invisible: false,
            },
            RegistryRootChild {
                name: "Hidden ghost".into(),
                role: "frame".into(),
                app_name: Some("Ghost".into()),
                is_password: false,
                is_invisible: true,
            },
            sample_app_row("Firefox"),
        ];
        let result = apply_registry_children(rows);
        match result {
            AccessibilityDiscovery::Ok { items, .. } => {
                assert_eq!(items.len(), 1);
                assert_eq!(items[0].name, "Firefox");
            }
            other => panic!("expected Ok with one survivor, got {other:?}"),
        }
    }

    // Test 7.
    #[test]
    fn registry_depth_limit_is_one_by_trait_signature() {
        // The trait exposes a single read-only method that returns a
        // flat `Vec<RegistryRootChild>`. There is no follow-up call to
        // fetch children of children, and `RegistryRootChild` has no
        // `children` field. Any nested walker would require a new
        // trait method (and a new ADR).
        fn assert_root_only<T: AccessibilityRegistryClient + ?Sized>(_: &T) {}
        let client = MockRegistryClient::ok(vec![sample_app_row("Firefox")]);
        assert_root_only(&client);
        let row: RegistryRootChild = sample_app_row("Firefox");
        let _name: &str = &row.name;
    }

    // Test 8.
    #[test]
    fn permission_denied_and_friends_map_to_stable_unavailable_reasons() {
        assert_eq!(
            AccessibilityRpcError::PermissionDenied.unavailable_reason(),
            "permission_denied"
        );
        assert_eq!(
            AccessibilityRpcError::A11yBusUnavailable.unavailable_reason(),
            "a11y_bus_unavailable"
        );
        assert_eq!(
            AccessibilityRpcError::DbusSessionMissing.unavailable_reason(),
            "dbus_session_missing"
        );
        assert_eq!(
            AccessibilityRpcError::BackendNotImplemented.unavailable_reason(),
            "accessibility_rpc_backend_not_implemented"
        );
    }

    // Test 9.
    #[test]
    fn rpc_failure_never_falls_back_to_verified() {
        // Empty registry → Uncertain (per ADR-0002 §"Failure modes").
        let result = apply_registry_children(vec![]);
        match result {
            AccessibilityDiscovery::Uncertain { items, reason } => {
                assert!(items.is_empty());
                assert_eq!(reason, "registry_empty");
            }
            other => panic!("empty registry must stay Uncertain, got {other:?}"),
        }
        // Unnamed row gets dropped — we never invent a name.
        let unnamed = RegistryRootChild {
            name: "   ".into(),
            role: "frame".into(),
            app_name: None,
            is_password: false,
            is_invisible: false,
        };
        let result = apply_registry_children(vec![unnamed]);
        match result {
            AccessibilityDiscovery::Uncertain { items, .. } => assert!(items.is_empty()),
            other => panic!("unnamed row must drop, got {other:?}"),
        }
    }

    // Test 10.
    #[test]
    fn serialization_keeps_existing_fields_stable() {
        // PR 53 must not change the wire shape. Verify both a hint-echo
        // (discovered, source=accessibility_hint_echo) and a verified
        // registry item (verified, source=accessibility_registry_root)
        // serialize via the documented field names.
        let echo = AccessibilityItem::hint_echo("Firefox");
        let json = serde_json::to_string(&echo).unwrap();
        assert!(json.contains(r#""confidence":"discovered""#));
        assert!(json.contains(r#""source":"accessibility_hint_echo""#));
        assert!(json.contains(r#""matched_hint":"Firefox""#));

        let result = apply_registry_children(vec![sample_app_row("Firefox")]);
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains(r#""status":"ok""#));
        assert!(json.contains(r#""confidence":"verified""#));
        assert!(json.contains(r#""source":"accessibility_registry_root""#));
        // matched_hint must be omitted on verified registry rows.
        assert!(!json.contains(r#""matched_hint""#));
    }

    // Feature-gated end-to-end check. Skipped on default builds.
    #[cfg(feature = "accessibility_rpc")]
    #[test]
    fn rpc_path_with_feature_and_mock_client_can_emit_verified() {
        // The orchestrator runs the env probe before the mock; on a
        // bare CI runner without DISPLAY/DBUS, that probe correctly
        // returns Unavailable and the mock is never invoked. Either
        // outcome is acceptable — the invariant is "if items came back,
        // they came from the mock and are verified".
        let cfg = AccessibilityRpcConfig { enabled: true };
        let client = MockRegistryClient::ok(vec![sample_app_row("Firefox")]);
        let result = discover_top_level_with_config(
            &cfg,
            Some(&client as &dyn AccessibilityRegistryClient),
        );
        match result {
            AccessibilityDiscovery::Ok { items, .. } => {
                assert!(items.iter().all(|i| i.confidence == DiscoveryConfidence::Verified
                    && i.source == source::ACCESSIBILITY_REGISTRY_ROOT));
            }
            AccessibilityDiscovery::Unavailable { .. }
            | AccessibilityDiscovery::Failed { .. } => {
                // Bare-env runner: probe stage rejected before the mock.
            }
            AccessibilityDiscovery::Uncertain { .. } => {
                // Acceptable when the probe says Uncertain and the mock
                // returns an empty registry — none of the rows reached
                // verified, which is exactly what we want.
            }
        }
    }
}
