use anyhow::Result;

use crate::config::Config;
use crate::event_loop::EventLoop;

pub struct App {
    config: Config,
}

impl App {
    pub fn new(config: Config) -> Self {
        Self { config }
    }

    pub async fn run(self) -> Result<()> {
        EventLoop::new(self.config).run().await
    }
}
