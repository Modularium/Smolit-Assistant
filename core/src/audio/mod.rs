//! Audio-Helfer (PR 6: schrumpft auf reine Hilfsstrukturen).
//!
//! Die ausführende Command-Logik für STT und TTS ist in die neue
//! Provider-Abstraktion gewandert:
//!
//!   * [`crate::providers::stt::SttCommandProvider`] /
//!     [`crate::providers::stt::SttProviderResolver`]
//!   * [`crate::providers::tts::TtsCommandProvider`] /
//!     [`crate::providers::tts::TtsProviderResolver`]
//!
//! Hier verbleiben nur noch geteilte Typen (insbesondere
//! `AudioFeatureState` und `split_command`), die auch andere Module
//! wie `interaction::backend` nutzen.

pub mod types;
