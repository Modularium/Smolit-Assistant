//! Provider abstraction layer.
//!
//! PR 2 der Provider-Fallback-Linie (siehe
//! `docs/provider_fallback_and_settings_architecture.md`).
//!
//! Zunächst **nur Text/Reasoning**. STT und TTS bleiben bewusst außerhalb
//! dieses Moduls — sie haben heute bereits eine eigene Command-Adapter-
//! Schicht (`core/src/audio/`) und werden in einem späteren PR in das
//! gleiche Provider-Vokabular gehoben, sobald der Resolver-Ansatz sich
//! am Text-Pfad bewährt hat.

pub mod text;
