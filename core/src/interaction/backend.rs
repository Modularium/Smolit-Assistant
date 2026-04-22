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

    fn focus_window(
        &self,
        _action: &InteractionAction,
        _title: Option<&str>,
        _app: Option<&str>,
    ) -> impl std::future::Future<Output = Result<VerificationResult, InteractionError>> + Send
    {
        async { Err(InteractionError::BackendUnsupported("focus_window")) }
    }

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
    /// Template executed when focusing a window. `{name}` is the
    /// preferred symbolic target (title or app), `{title}` / `{app}` are
    /// each substituted with the corresponding component or an empty
    /// string if absent. Example on X11: `wmctrl -a {name}`. On Wayland
    /// there is no generic equivalent — leaving this unset makes the
    /// backend honestly report `focus_window` as unsupported.
    pub focus_window_cmd_template: Option<String>,
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

    async fn focus_window(
        &self,
        _action: &InteractionAction,
        title: Option<&str>,
        app: Option<&str>,
    ) -> Result<VerificationResult, InteractionError> {
        let Some(template) = self.config.focus_window_cmd_template.as_deref() else {
            // No template configured — do not guess, do not fake
            // success. Honest unsupported is the correct answer.
            return Err(InteractionError::BackendUnsupported("focus_window"));
        };

        let title = title.map(str::trim).filter(|s| !s.is_empty());
        let app = app.map(str::trim).filter(|s| !s.is_empty());
        let Some(name) = title.or(app) else {
            return Err(InteractionError::Preconditions(
                "focus_window requires a title or app target".to_string(),
            ));
        };

        let rendered = template
            .replace("{name}", name)
            .replace("{title}", title.unwrap_or(""))
            .replace("{app}", app.unwrap_or(""));
        let (program, args) = split_command(&rendered)
            .ok_or_else(|| InteractionError::Preconditions("rendered command is empty".into()))?;

        debug!(program = %program, args = ?args, "interaction: spawning focus-window command");

        let output = Command::new(&program)
            .args(&args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await;

        match output {
            Ok(out) if out.status.success() => {
                // Exit 0 says the helper ran — it does not prove focus
                // actually moved. MVP stays honest: `uncertain`.
                Ok(VerificationResult::uncertain(
                    "Focus command completed",
                    format!(
                        "ran `{program}` for `{name}` (no focus probe yet)"
                    ),
                ))
            }
            Ok(out) => {
                let code = out.status.code().unwrap_or(-1);
                let stderr = String::from_utf8_lossy(&out.stderr);
                let snippet = stderr.trim();
                let detail = if snippet.is_empty() {
                    format!("exit code {code}")
                } else {
                    format!("exit code {code}: {snippet}")
                };
                Err(InteractionError::BackendFailed(format!(
                    "focus command `{program}` failed ({detail})"
                )))
            }
            Err(err) => {
                warn!(error = %err, program = %program, "failed to spawn focus-window command");
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
            ..CommandBackendConfig::default()
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

    #[tokio::test]
    async fn focus_window_without_template_is_unsupported() {
        let backend = CommandBackend::new(CommandBackendConfig::default());
        let err = backend
            .focus_window(&action("n/a"), Some("calendar"), None)
            .await
            .expect_err("expected unsupported");
        assert!(matches!(err, InteractionError::BackendUnsupported(_)));
    }

    #[tokio::test]
    async fn focus_window_without_target_reports_preconditions() {
        let backend = CommandBackend::new(CommandBackendConfig {
            focus_window_cmd_template: Some("/bin/true".into()),
            ..CommandBackendConfig::default()
        });
        let err = backend
            .focus_window(&action("n/a"), None, None)
            .await
            .expect_err("expected preconditions error");
        assert!(matches!(err, InteractionError::Preconditions(_)));
    }

    #[tokio::test]
    async fn focus_window_with_true_is_uncertain() {
        let backend = CommandBackend::new(CommandBackendConfig {
            focus_window_cmd_template: Some("/bin/true".into()),
            ..CommandBackendConfig::default()
        });
        let result = backend
            .focus_window(&action("n/a"), Some("calendar"), None)
            .await
            .expect("command ran");
        assert_eq!(result.confidence, VerificationConfidence::Uncertain);
    }

    #[tokio::test]
    async fn focus_window_failing_command_reports_backend_failed() {
        let backend = CommandBackend::new(CommandBackendConfig {
            focus_window_cmd_template: Some("/bin/false".into()),
            ..CommandBackendConfig::default()
        });
        let err = backend
            .focus_window(&action("n/a"), Some("calendar"), None)
            .await
            .expect_err("expected failure");
        assert!(matches!(err, InteractionError::BackendFailed(_)));
    }
}
