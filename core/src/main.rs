mod app;
pub mod adapters {
    pub mod abrain;
}
mod config;
mod event_loop;

use anyhow::Result;
use tracing::debug;
use tracing_subscriber::EnvFilter;

use crate::app::App;
use crate::config::Config;

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::load()?;
    init_tracing(&config.log_level);
    debug!(config = %config.as_json(), "configuration loaded");

    App::new(config).run().await
}

fn init_tracing(log_level: &str) {
    let filter = EnvFilter::try_new(log_level).unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .compact()
        .init();
}
