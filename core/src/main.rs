mod actions;
mod app;
mod approvals;
mod audio;
mod audit;
mod capabilities;
mod capability_guard;
mod config;
mod event_loop;
mod interaction;
mod ipc;
mod providers;
mod secrets_store;
mod settings_store;

/// Test-scope: prozess-weiter Mutex, der serialisiert, wer gerade
/// `SMOLIT_SETTINGS_DIR` setzt. Der Env-Var ist prozess-global; ohne
/// diesen Lock racen die Tests in `settings_store::tests`,
/// `secrets_store::tests` und `ipc::server::tests` gegeneinander und
/// schreiben in fremde Dirs. `Mutex<()>` in `std::sync` ist stabil und
/// braucht keinen Async-Runtime-Kontext.
///
/// Tests sollen **immer** `lock().unwrap_or_else(|e| e.into_inner())`
/// verwenden — damit auch ein früher panickender Test nachfolgende
/// Tests nicht mit `PoisonError` blockiert.
#[cfg(test)]
pub(crate) static SETTINGS_DIR_ENV_LOCK: std::sync::Mutex<()> =
    std::sync::Mutex::new(());

use std::sync::Arc;

use anyhow::Result;
use tracing::{debug, error, info};
use tracing_subscriber::EnvFilter;

use crate::app::App;
use crate::config::Config;
use crate::event_loop::EventLoop;

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::load()?;
    init_tracing(&config.log_level);
    debug!(config = %config.as_json(), "configuration loaded");

    let app = Arc::new(App::new(config));

    if app.config.ipc.enabled {
        let bind = app.config.ipc.bind.clone();
        let ipc_app = Arc::clone(&app);
        tokio::spawn(async move {
            if let Err(err) = ipc::serve(ipc_app, &bind).await {
                error!(error = %err, "IPC server stopped");
            }
        });
    } else {
        info!("IPC disabled via SMOLIT_IPC_ENABLED");
    }

    EventLoop::new(app).run().await
}

fn init_tracing(log_level: &str) {
    let filter = EnvFilter::try_new(log_level).unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .compact()
        .init();
}
