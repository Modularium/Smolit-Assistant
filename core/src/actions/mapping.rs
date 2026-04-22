use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ActionSpace {
    LogicalSpace,
    WindowSpace,
    ScreenSpace,
}

/// Symbolic visual mapping for v1. No geometry — just the space,
/// a short human hint, and an optional window/app reference.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ActionMapping {
    pub space: ActionSpace,
    pub hint: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window: Option<String>,
}

impl ActionMapping {
    pub fn logical(hint: impl Into<String>) -> Self {
        Self {
            space: ActionSpace::LogicalSpace,
            hint: hint.into(),
            window: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_logical_mapping() {
        let json = serde_json::to_string(&ActionMapping::logical("towards calendar app")).unwrap();
        assert_eq!(
            json,
            r#"{"space":"logical_space","hint":"towards calendar app"}"#
        );
    }
}
