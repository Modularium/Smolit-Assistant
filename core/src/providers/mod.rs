//! Provider-Abstraktionsschicht.
//!
//! Die Provider-Linien teilen sich eine gemeinsame Leitplanken-Sammlung
//! (siehe `docs/provider_fallback_and_settings_architecture.md`):
//! enum-basiertes Dispatch, kuratierte Kinds, Resolver-Laufzeitstatus,
//! additive StatusPayload-Projektion, keine stillen Cloud-Fallbacks.
//!
//! Module:
//!
//!   * [`text`] — Text-/Reasoning-Provider (PR 2 + 2a + 2b): `abrain`
//!     (CLI) und `llamafile_local` (lokaler Runtime).
//!   * [`stt`] — STT-Provider (PR 6): `command` als einziges Kind
//!     heute; der bisherige `SMOLIT_STT_CMD`-Pfad wohnt ab jetzt
//!     hinter dieser Abstraktion.
//!   * [`tts`] — TTS-Provider (PR 6): `command` als einziges Kind
//!     heute; Spiegel zu `stt`.

pub mod stt;
pub mod text;
pub mod tts;
