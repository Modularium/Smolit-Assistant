use anyhow::{Context, Result, bail};
use tokio::process::Command;
use tokio::time::{Duration, timeout};

const DEFAULT_TIMEOUT_SECS: u64 = 30;

pub async fn run_task(input: &str) -> Result<String> {
    let command = std::env::var("ABRAIN_CMD").unwrap_or_else(|_| "abrain".to_string());
    run_task_with_cmd(&command, input).await
}

pub async fn run_task_with_cmd(command: &str, input: &str) -> Result<String> {
    let output = timeout(Duration::from_secs(DEFAULT_TIMEOUT_SECS), async {
        Command::new(command)
            .args(["task", "run", input])
            .output()
            .await
    })
    .await
    .context("ABrain task timed out")?
    .with_context(|| format!("failed to spawn ABrain command `{command}`"))?;

    let stdout = String::from_utf8(output.stdout).context("ABrain stdout was not valid UTF-8")?;
    let stderr = String::from_utf8(output.stderr).context("ABrain stderr was not valid UTF-8")?;

    if !output.status.success() {
        let detail = if stderr.trim().is_empty() {
            "process exited without error output".to_string()
        } else {
            stderr.trim().to_string()
        };

        bail!(
            "ABrain command `{command}` failed with status {}: {}",
            output.status,
            detail
        );
    }

    let response = stdout.trim().to_string();
    if response.is_empty() {
        bail!("ABrain command `{command}` returned no output");
    }

    Ok(response)
}
