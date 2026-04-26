//! Interaction action model.
//!
//! An `InteractionAction` is the core-internal, strongly-typed shape of
//! a desktop-level operation the assistant wants to perform. It is
//! *not* the IPC event — that stays in `crate::actions` (Action Event
//! Model v1). Instead, an `InteractionAction` is what the executor
//! consumes; the executor then emits Action Events as it progresses.

use serde::{Deserialize, Serialize};

use crate::actions::ActionTarget;

/// The small, deliberately-limited taxonomy of MVP interaction kinds.
/// New backends may introduce additional kinds; the enum stays
/// `non_exhaustive` to signal that the list grows over time.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum InteractionKind {
    OpenApplication,
    FocusWindow,
    TypeText,
    SendShortcut,
    Noop,
    Unknown,
}

impl InteractionKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::OpenApplication => "open_application",
            Self::FocusWindow => "focus_window",
            Self::TypeText => "type_text",
            Self::SendShortcut => "send_shortcut",
            Self::Noop => "noop",
            Self::Unknown => "unknown",
        }
    }
}

/// Per-kind structured payload. Using an enum (rather than stuffing
/// fields onto `InteractionAction`) lets the compiler enforce which
/// fields belong with which kind — at the cost of a tiny amount of
/// boilerplate.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum InteractionPayload {
    OpenApplication {
        /// Symbolic application name, e.g. `"calendar"` / `"terminal"`.
        name: String,
    },
    FocusWindow {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        app: Option<String>,
    },
    TypeText {
        text: String,
    },
    SendShortcut {
        /// Symbolic shortcut like `"ctrl+shift+t"`.
        combo: String,
    },
    Noop,
}

impl InteractionPayload {
    pub fn kind(&self) -> InteractionKind {
        match self {
            Self::OpenApplication { .. } => InteractionKind::OpenApplication,
            Self::FocusWindow { .. } => InteractionKind::FocusWindow,
            Self::TypeText { .. } => InteractionKind::TypeText,
            Self::SendShortcut { .. } => InteractionKind::SendShortcut,
            Self::Noop => InteractionKind::Noop,
        }
    }
}

/// A concrete, dispatchable interaction. `target` reuses the Action
/// Event `ActionTarget` so the symbolic visual shape stays consistent
/// between planning, rendering and execution.
#[derive(Debug, Clone)]
pub struct InteractionAction {
    pub action_id: String,
    pub title: String,
    pub target: ActionTarget,
    pub payload: InteractionPayload,
    /// Whether this action should be confirmed by the user before the
    /// backend runs. For MVP, when `true` and the config also requires
    /// confirmation, the executor refuses with `ConfirmationRequired`
    /// (no confirmation channel is implemented yet — see Phase 8b).
    pub requires_confirmation: bool,
    /// Reserved for the future trust model (see
    /// `docs/presence_desktop_interaction.md`, §7). For MVP this flag
    /// is carried through but not yet gating anything.
    pub trusted_only: bool,
    /// PR 54 — additives, optionales Korrelations-Token. Wird vom
    /// `App`-Lifecycle früh am Aktionspfad gesetzt (siehe
    /// [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../../../docs/contracts/AUDIT_CORRELATION_ID_SPEC.md))
    /// und vom Executor in jeden ausgehenden Action-Event hinein
    /// gespiegelt. Default `None`, damit reine Unit-Tests des
    /// Executors weiterhin ohne Korrelation laufen.
    pub correlation_id: Option<String>,
}

impl InteractionAction {
    pub fn kind(&self) -> InteractionKind {
        self.payload.kind()
    }

    /// Convenience constructor for the only operation the command
    /// backend actually executes in this phase.
    pub fn open_application(action_id: impl Into<String>, name: impl Into<String>) -> Self {
        let name = name.into();
        let target = ActionTarget::application(name.clone());
        Self {
            action_id: action_id.into(),
            title: format!("Open {name}"),
            target,
            payload: InteractionPayload::OpenApplication { name },
            requires_confirmation: false,
            trusted_only: false,
            correlation_id: None,
        }
    }

    /// Convenience constructor for the focus_window spike. `title` and
    /// `app` are both optional, but the backend requires at least one
    /// of them — the caller is expected to supply a meaningful target.
    pub fn focus_window(
        action_id: impl Into<String>,
        title: Option<String>,
        app: Option<String>,
    ) -> Self {
        let display = title
            .clone()
            .or_else(|| app.clone())
            .unwrap_or_else(|| "window".to_string());
        let target = ActionTarget::window(title.clone(), app.clone());
        Self {
            action_id: action_id.into(),
            title: format!("Focus {display}"),
            target,
            payload: InteractionPayload::FocusWindow { title, app },
            requires_confirmation: false,
            trusted_only: false,
            correlation_id: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_application_has_application_target() {
        let action = InteractionAction::open_application("act_000001", "calendar");
        assert_eq!(action.kind(), InteractionKind::OpenApplication);
        match &action.target {
            ActionTarget::Application { name, .. } => assert_eq!(name, "calendar"),
            other => panic!("unexpected target: {other:?}"),
        }
    }

    #[test]
    fn payload_kind_matches_enum() {
        let payload = InteractionPayload::SendShortcut {
            combo: "ctrl+alt+t".into(),
        };
        assert_eq!(payload.kind(), InteractionKind::SendShortcut);
    }
}
