use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct AudioFeatureState {
    pub enabled: bool,
    pub available: bool,
}

impl AudioFeatureState {
    pub fn new(enabled: bool, available: bool) -> Self {
        Self { enabled, available }
    }
}

pub fn split_command(cmd: &str) -> Option<(String, Vec<String>)> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_single = false;
    let mut in_double = false;
    let mut escape = false;

    for ch in cmd.chars() {
        if escape {
            current.push(ch);
            escape = false;
            continue;
        }
        match ch {
            '\\' if !in_single => escape = true,
            '\'' if !in_double => in_single = !in_single,
            '"' if !in_single => in_double = !in_double,
            c if c.is_whitespace() && !in_single && !in_double => {
                if !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
            }
            c => current.push(c),
        }
    }

    if !current.is_empty() {
        tokens.push(current);
    }

    if tokens.is_empty() {
        return None;
    }

    let program = tokens.remove(0);
    Some((program, tokens))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_simple() {
        let (prog, args) = split_command("piper --model voice.onnx").unwrap();
        assert_eq!(prog, "piper");
        assert_eq!(args, vec!["--model", "voice.onnx"]);
    }

    #[test]
    fn handles_quoted() {
        let (prog, args) = split_command("say -v \"Daniel Premium\" --rate 180").unwrap();
        assert_eq!(prog, "say");
        assert_eq!(args, vec!["-v", "Daniel Premium", "--rate", "180"]);
    }

    #[test]
    fn empty_returns_none() {
        assert!(split_command("   ").is_none());
    }
}
