use std::io::{self, Write};
use std::sync::Arc;

use anyhow::Result;
use tokio::io::{AsyncBufReadExt, BufReader};
use tracing::{debug, error, warn};

use crate::app::App;

pub struct EventLoop {
    app: Arc<App>,
}

impl EventLoop {
    pub fn new(app: Arc<App>) -> Self {
        Self { app }
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
                print_help();
                continue;
            }

            if input == "audio-status" {
                self.print_audio_status();
                continue;
            }

            if input == "voice" {
                self.handle_voice().await;
                continue;
            }

            if let Some(rest) = input.strip_prefix("speak") {
                let text = rest.trim();
                if text.is_empty() {
                    println!("Usage: speak <text>");
                    continue;
                }
                self.handle_speak(text).await;
                continue;
            }

            self.handle_abrain(input).await;
        }

        Ok(())
    }

    async fn handle_abrain(&self, input: &str) {
        debug!("forwarding user input to ABrain");

        match self.app.handle_text_query(input).await {
            Ok(response) => {
                println!("{response}");
                self.app.maybe_auto_speak(&response).await;
            }
            Err(err) => {
                error!(error = %err, "ABrain request failed");
                eprintln!("ABrain error: {err:#}");
            }
        }
    }

    async fn handle_voice(&self) {
        if !self.app.stt.is_available() {
            println!("STT is not available. Check SMOLIT_STT_ENABLED and SMOLIT_STT_CMD.");
            return;
        }

        println!("[listening...]");
        let recognized = match self.app.handle_voice_once().await {
            Ok(text) => text,
            Err(err) => {
                warn!(error = %err, "STT request failed");
                eprintln!("STT error: {err:#}");
                return;
            }
        };

        println!("[recognized] {recognized}");
        self.handle_abrain(&recognized).await;
    }

    async fn handle_speak(&self, text: &str) {
        if !self.app.tts.is_available() {
            println!("TTS is not available. Check SMOLIT_TTS_ENABLED and SMOLIT_TTS_CMD.");
            return;
        }

        if let Err(err) = self.app.handle_speak(text).await {
            warn!(error = %err, "TTS request failed");
            eprintln!("TTS error: {err:#}");
        }
    }

    fn print_audio_status(&self) {
        let status = self.app.build_status_payload();
        println!(
            "TTS: enabled={}, available={}",
            status.tts_enabled, status.tts_available
        );
        println!(
            "STT: enabled={}, available={}",
            status.stt_enabled, status.stt_available
        );
        println!("auto-speak: {}", status.auto_speak);
    }
}

fn print_help() {
    println!("Commands:");
    println!("  help              show this help");
    println!("  exit | quit       shut down the assistant");
    println!("  voice             capture a single STT utterance and send to ABrain");
    println!("  speak <text>      speak the given text via TTS");
    println!("  audio-status      show TTS/STT availability");
    println!("  <text>            send free text to ABrain");
}

fn print_prompt() -> Result<()> {
    print!("> ");
    io::stdout().flush()?;
    Ok(())
}
