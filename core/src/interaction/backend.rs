//! Interaction backends.
//!
//! A backend is the thing that actually touches the desktop. For MVP
//! there is exactly one concrete backend (`CommandBackend`) and only
//! `open_application` is implemented in a truthful, best-effort way —
//! everything else returns `BackendUnsupported` so the protocol can
//! already describe those operations while implementations land later.
//!
//! The trait intentionally keeps the surface small; new kinds can be
//! added alongside new backends without breaking existing callers.

use std::process::Stdio;

use tokio::process::Command;
use tracing::{debug, warn};

use crate::audio::types::split_command;

use super::action::InteractionAction;
use super::types::InteractionError;
use super::verifier::VerificationResult;

/// Interaction backend trait. Kept without `async_trait` because the
/// MVP only needs a single concrete backend — native async fns in
/// traits are enough and avoid pulling in a dependency. Adding a
/// second backend later is trivial; adding *dynamic dispatch* across
/// backends would be the trigger to reconsider.
pub trait InteractionBackend: Send + Sync {
    fn name(&self) -> &'static str;

    fn open_application(
        &self,
        action: &InteractionAction,
        name: &str,
    ) -> impl std::future::Future<Output = Result<VerificationResult, InteractionError>> + Send;

    fn type_text(
        &self,
        _action: &InteractionAction,
        _text: &str,
    ) -> impl std::future::Future<Output = Result<VerificationResult, InteractionError>> + Send
    {
        async { Err(InteractionError::BackendUnsupported("type_text")) }
    }

    fn send_shortcut(
        &self,
        _action: &InteractionAction,
        _combo: &str,
    ) -> impl std::future::Future<Output = Result<VerificationResult, InteractionError>> + Send
    {
        async { Err(InteractionError::BackendUnsupported("send_shortcut")) }
    }
}

/// Configuration for the command backend. Kept tiny on purpose: a
/// single optional command template. If the template is unset, the
/// backend honestly reports that `open_application` is unavailable
/// rather than silently doing nothing.
#[derive(Debug, Clone, Default)]
pub struct CommandBackendConfig {
    /// Template executed when opening an application. `{name}` is
    /// substituted with the symbolic application name. Example:
    /// `gtk-launch {name}` or `xdg-open {name}`.
    pub open_app_cmd_template: Option<String>,
}

pub struct CommandBackend {
    config: CommandBackendConfig,
}

impl CommandBackend {
    pub fn new(config: CommandBackendConfig) -> Self {
        Self { config }
    }
}

impl InteractionBackend for CommandBackend {
    fn name(&self) -> &'static str {
        "command"
    }

    async fn open_application(
        &self,
        _action: &InteractionAction,
        name: &str,
    ) -> Result<VerificationResult, InteractionError> {
        let template = self.config.open_app_cmd_template.as_deref().ok_or_else(|| {
            InteractionError::Preconditions(
                "open-application command template is not configured (SMOLIT_INTERACTION_OPEN_APP_CMD)"
                    .to_string(),
            )
        })?;

        if name.is_empty() {
            return Err(InteractionError::Preconditions(
                "application name is empty".to_string(),
            ));
        }

        let rendered = template.replace("{name}", name);
        let (program, args) = split_command(&rendered)
            .ok_or_else(|| InteractionError::Preconditions("rendered command is empty".into()))?;

        debug!(program = %program, args = ?args, "interaction: spawning open-application command");

        let spawn = Command::new(&program)
            .args(&args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn();

        match spawn {
            Ok(child) => {
                // Detach: we do not wait for the launched application
                // to exit. We cannot prove the app actually appeared
                // without a window probe, so verification is
                // intentionally "uncertain" for MVP.
                drop(child);
                Ok(VerificationResult::uncertain(
                    "Spawned open command",
                    format!("spawned `{program}` for `{name}` (no window probe yet)"),
                ))
            }
            Err(err) => {
                warn!(error = %err, program = %program, "failed to spawn open-application command");
                Err(InteractionError::BackendFailed(format!(
                    "failed to spawn `{program}`: {err}"
                )))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::interaction::action::InteractionAction;
    use crate::interaction::verifier::VerificationConfidence;

    fn action(name: &str) -> InteractionAction {
        InteractionAction::open_application("act_000001", name)
    }

    #[tokio::test]
    async fn open_application_without_template_reports_preconditions() {
        let backend = CommandBackend::new(CommandBackendConfig::default());
        let err = backend
            .open_application(&action("calendar"), "calendar")
            .await
            .expect_err("expected preconditions error");
        assert!(matches!(err, InteractionError::Preconditions(_)));
    }

    #[tokio::test]
    async fn open_application_with_true_command_is_uncertain() {
        let backend = CommandBackend::new(CommandBackendConfig {
            open_app_cmd_template: Some("/bin/true".into()),
        });
        let result = backend
            .open_application(&action("anything"), "anything")
            .await
            .expect("expected spawn success");
        assert_eq!(result.confidence, VerificationConfidence::Uncertain);
    }

    #[tokio::test]
    async fn type_text_is_unsupported_by_default() {
        let backend = CommandBackend::new(CommandBackendConfig::default());
        let err = backend
            .type_text(&action("n/a"), "hello")
            .await
            .expect_err("expected unsupported");
        assert!(matches!(err, InteractionError::BackendUnsupported(_)));
    }
}
