use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ActionTarget {
    Application {
        name: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        hint: Option<String>,
    },
    Window {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        app: Option<String>,
    },
    UiElement {
        role: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        label: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        hint: Option<String>,
    },
    Region {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        hint: Option<String>,
    },
    Unknown,
}

impl ActionTarget {
    pub fn unknown() -> Self {
        Self::Unknown
    }

    pub fn application(name: impl Into<String>) -> Self {
        Self::Application {
            name: name.into(),
            hint: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_unknown_flat() {
        let json = serde_json::to_string(&ActionTarget::unknown()).unwrap();
        assert_eq!(json, r#"{"type":"unknown"}"#);
    }

    #[test]
    fn serializes_application() {
        let json = serde_json::to_string(&ActionTarget::application("calendar")).unwrap();
        assert_eq!(json, r#"{"type":"application","name":"calendar"}"#);
    }

    #[test]
    fn serializes_ui_element_with_label() {
        let target = ActionTarget::UiElement {
            role: "input_field".into(),
            label: Some("title".into()),
            hint: None,
        };
        let json = serde_json::to_string(&target).unwrap();
        assert_eq!(
            json,
            r#"{"type":"ui_element","role":"input_field","label":"title"}"#
        );
    }
}
