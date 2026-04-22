//! Target selection (UI → Core handoff).
//!
//! Minimal, deliberately flat reference to one "currently focused"
//! target. It sits between the Accessibility Discovery spike (which
//! produces structured items) and the Interaction Layer (which consumes
//! `ActionTarget`s to actually do something). The selection itself is
//! **never** a permission: approval is still required for every
//! concrete action.
//!
//! Design intent:
//!
//! * Stay a *pointer*, not a snapshot. We keep enough to render and
//!   shape a follow-up approval message, nothing more. No A11y tree,
//!   no permission cache.
//! * Honest mapping to `ActionTarget` only — a selected `window` does
//!   not magically become an application or UI element.
//! * Short-lived by construction. The selection is held in-memory on
//!   the `App` (see `app::App::selected_target`) and cleared on
//!   disconnect, error, or explicit clear.

use serde::{Deserialize, Serialize};

use crate::actions::ActionTarget;

/// A small, serializable reference to one target the user has selected
/// (usually from an accessibility discovery result). Flat by design.
///
/// Wire format mirrors the `interaction_select_target` message: the UI
/// sends the same shape, the core accepts it, and the `target_selected`
/// event echoes it back verbatim.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SelectedTarget {
    /// Stable id scoped to the current session. When the UI omits this
    /// the core assigns a `sel_NNNNNN` id — see
    /// [`SelectedTarget::normalize_with_fallback_id`].
    pub id: String,
    /// Best-effort display name (from the discovered item).
    pub name: String,
    /// Coarse role, one of `"application"` / `"window"` / `"ui_element"`
    /// / `"region"` / `"unknown"`. Stays a string so new roles can be
    /// added without a schema change.
    pub role: String,
    /// Provenance label: today always `"accessibility"` (hint-echo
    /// path). Future pipelines can introduce new sources additively.
    #[serde(default = "default_source")]
    pub source: String,
    /// Per-item confidence from the discovery stage: `"verified"` or
    /// `"discovered"`. Carried forward as-is — the selection layer must
    /// never upgrade `discovered` → `verified`.
    pub confidence: String,
    /// Optional matched hint that produced the discovery result (kept
    /// so approval messages can show *why* this was selected).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub matched_hint: Option<String>,
    /// Optional enclosing application name, when derivable.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_name: Option<String>,
}

fn default_source() -> String {
    "accessibility".to_string()
}

/// Validation outcome when a client submits `interaction_select_target`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SelectionError {
    /// `name` was missing or empty after trimming.
    EmptyName,
    /// `role` was missing or empty after trimming.
    EmptyRole,
    /// `confidence` was missing, empty, or not one of the known values
    /// (`verified` / `discovered`).
    InvalidConfidence,
}

impl SelectionError {
    pub fn message(&self) -> &'static str {
        match self {
            Self::EmptyName => "selected target requires a non-empty name",
            Self::EmptyRole => "selected target requires a non-empty role",
            Self::InvalidConfidence => {
                "selected target confidence must be 'verified' or 'discovered'"
            }
        }
    }
}

impl SelectedTarget {
    /// Trim trivial whitespace, clamp source to a default when empty,
    /// and replace an empty/whitespace id with `fallback_id`. Returns
    /// the cleaned-up target or a structured validation error.
    pub fn normalize_with_fallback_id(
        mut self,
        fallback_id: impl Into<String>,
    ) -> Result<Self, SelectionError> {
        self.id = self.id.trim().to_string();
        if self.id.is_empty() {
            self.id = fallback_id.into();
        }

        self.name = self.name.trim().to_string();
        if self.name.is_empty() {
            return Err(SelectionError::EmptyName);
        }

        self.role = self.role.trim().to_string();
        if self.role.is_empty() {
            return Err(SelectionError::EmptyRole);
        }

        self.source = self.source.trim().to_string();
        if self.source.is_empty() {
            self.source = default_source();
        }

        self.confidence = self.confidence.trim().to_string();
        if !matches!(self.confidence.as_str(), "verified" | "discovered") {
            return Err(SelectionError::InvalidConfidence);
        }

        self.matched_hint = self
            .matched_hint
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        self.app_name = self
            .app_name
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        Ok(self)
    }

    /// Best-effort mapping to the richer `ActionTarget` used by the
    /// Action Event Model. Stays conservative: unknown roles degrade to
    /// `ActionTarget::Unknown` rather than inventing structure.
    pub fn to_action_target(&self) -> ActionTarget {
        match self.role.as_str() {
            "application" => ActionTarget::Application {
                name: self.name.clone(),
                hint: self.matched_hint.clone(),
            },
            "window" => ActionTarget::Window {
                title: Some(self.name.clone()),
                app: self.app_name.clone().or_else(|| self.matched_hint.clone()),
            },
            "ui_element" => ActionTarget::UiElement {
                role: self.role.clone(),
                label: Some(self.name.clone()),
                hint: self.matched_hint.clone(),
            },
            "region" => ActionTarget::Region {
                name: Some(self.name.clone()),
                hint: self.matched_hint.clone(),
            },
            _ => ActionTarget::Unknown,
        }
    }

    /// Short human-readable label for approval banners and logs:
    /// `"calendar (window, discovered)"`.
    pub fn short_label(&self) -> String {
        format!("{} ({}, {})", self.name, self.role, self.confidence)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(role: &str, confidence: &str) -> SelectedTarget {
        SelectedTarget {
            id: "sel_test".into(),
            name: "calendar".into(),
            role: role.into(),
            source: "accessibility".into(),
            confidence: confidence.into(),
            matched_hint: Some("calendar".into()),
            app_name: None,
        }
    }

    #[test]
    fn normalize_rejects_empty_name() {
        let t = SelectedTarget {
            id: "x".into(),
            name: "   ".into(),
            role: "window".into(),
            source: "accessibility".into(),
            confidence: "discovered".into(),
            matched_hint: None,
            app_name: None,
        };
        assert_eq!(
            t.normalize_with_fallback_id("sel_fallback"),
            Err(SelectionError::EmptyName)
        );
    }

    #[test]
    fn normalize_rejects_unknown_confidence() {
        let t = SelectedTarget {
            id: "x".into(),
            name: "calendar".into(),
            role: "window".into(),
            source: "accessibility".into(),
            confidence: "totally_verified".into(),
            matched_hint: None,
            app_name: None,
        };
        assert_eq!(
            t.normalize_with_fallback_id("sel_fallback"),
            Err(SelectionError::InvalidConfidence)
        );
    }

    #[test]
    fn normalize_fills_fallback_id_when_empty() {
        let t = SelectedTarget {
            id: "".into(),
            name: "calendar".into(),
            role: "window".into(),
            source: "accessibility".into(),
            confidence: "discovered".into(),
            matched_hint: None,
            app_name: None,
        };
        let normalized = t.normalize_with_fallback_id("sel_000001").unwrap();
        assert_eq!(normalized.id, "sel_000001");
    }

    #[test]
    fn normalize_defaults_source_when_blank() {
        let mut t = sample("window", "discovered");
        t.source = "   ".into();
        let normalized = t.normalize_with_fallback_id("sel_000001").unwrap();
        assert_eq!(normalized.source, "accessibility");
    }

    #[test]
    fn to_action_target_window_uses_title_and_app() {
        let t = SelectedTarget {
            id: "sel_1".into(),
            name: "Calendar".into(),
            role: "window".into(),
            source: "accessibility".into(),
            confidence: "discovered".into(),
            matched_hint: Some("cal".into()),
            app_name: Some("gnome-calendar".into()),
        };
        match t.to_action_target() {
            ActionTarget::Window { title, app } => {
                assert_eq!(title.as_deref(), Some("Calendar"));
                assert_eq!(app.as_deref(), Some("gnome-calendar"));
            }
            other => panic!("unexpected target: {other:?}"),
        }
    }

    #[test]
    fn to_action_target_application_uses_name_and_hint() {
        let t = sample("application", "discovered");
        match t.to_action_target() {
            ActionTarget::Application { name, hint } => {
                assert_eq!(name, "calendar");
                assert_eq!(hint.as_deref(), Some("calendar"));
            }
            other => panic!("unexpected target: {other:?}"),
        }
    }

    #[test]
    fn to_action_target_unknown_role_degrades_to_unknown() {
        let t = sample("mystery", "discovered");
        assert_eq!(t.to_action_target(), ActionTarget::Unknown);
    }

    #[test]
    fn short_label_has_role_and_confidence() {
        let t = sample("window", "discovered");
        assert_eq!(t.short_label(), "calendar (window, discovered)");
    }

    #[test]
    fn round_trips_as_json() {
        let t = sample("window", "discovered");
        let json = serde_json::to_string(&t).unwrap();
        let back: SelectedTarget = serde_json::from_str(&json).unwrap();
        assert_eq!(back, t);
    }
}
