use std::io::{self, Write};

use anyhow::Result;
use tokio::io::{AsyncBufReadExt, BufReader};
use tracing::{debug, error};

use crate::adapters::abrain;
use crate::config::Config;

pub struct EventLoop {
    config: Config,
}

impl EventLoop {
    pub fn new(config: Config) -> Self {
        Self { config }
    }

    pub async fn run(self) -> Result<()> {
        let stdin = tokio::io::stdin();
        let mut lines = BufReader::new(stdin).lines();

        println!("Smolit ready.");
        debug!("event loop started");

        loop {
            print_prompt()?;

            let line = match lines.next_line().await? {
                Some(line) => line,
                None => {
                    println!();
                    debug!("stdin closed, stopping event loop");
                    break;
                }
            };

            let input = line.trim();
            if input.is_empty() {
                continue;
            }

            if matches!(input, "exit" | "quit") {
                debug!("shutdown requested by user");
                println!("Bye.");
                break;
            }

            if input == "help" {
                println!("Commands: help, exit, quit");
                continue;
            }

            debug!("forwarding user input to ABrain");

            match abrain::run_task_with_cmd(&self.config.abrain_cmd, input).await {
                Ok(response) => println!("{response}"),
                Err(err) => {
                    error!(error = %err, "ABrain request failed");
                    eprintln!("ABrain error: {err:#}");
                }
            }
        }

        Ok(())
    }
}

fn print_prompt() -> Result<()> {
    print!("> ");
    io::stdout().flush()?;
    Ok(())
}
