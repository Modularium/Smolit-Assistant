//! Local Audit Trail v1 (PR 19).
//!
//! Kleiner, in-memory Audit-Store + ein streng sanitisiertes Event-
//! Modell. Der Store erfasst Lifecycle-Schritte aus dem
//! Approval-Gated Demo-Action-Planner (PR 18) und ein paar IPC-
//! Grenzfälle; er **persistiert nichts**, enthält keinen Export-Pfad
//! und keine kryptografische Signatur.
//!
//! Leitprinzip: *accountability without surveillance.* Jeder
//! Audit-Eintrag ist klein und trägt keine sensiblen Full-Payloads.
//! Siehe [`docs/security/AUDIT_TRAIL.md`](../../docs/security/AUDIT_TRAIL.md).
#![allow(dead_code)]

pub mod correlation;
pub mod event;
pub mod store;

pub use correlation::generate_correlation_id;
#[allow(unused_imports)]
pub use correlation::{
    CORRELATION_ID_PREFIX, MAX_CORRELATION_ID_LEN, MIN_CORRELATION_ID_LEN, sanitize_correlation_id,
};
pub use event::{
    AuditEvent, AuditFields, AuditKind, RESULT_CANCELLED, RESULT_COMPLETED, RESULT_DENIED,
    RESULT_EXPIRED, RESULT_REJECTED, SOURCE_CORE, SOURCE_UI,
};
#[allow(unused_imports)]
pub use event::{
    MAX_SUMMARY_CHARS, RESULT_APPROVED, RESULT_FAILED, SOURCE_SYSTEM, SOURCE_TIMEOUT, SOURCE_USER,
};
#[allow(unused_imports)]
pub use event::{
    KNOWN_RESULTS, KNOWN_SOURCES, sanitize_result, sanitize_risk, sanitize_source,
    sanitize_summary,
};
pub use store::AuditStore;
#[allow(unused_imports)]
pub use store::{
    DEFAULT_MAX_EVENTS, ENV_MAX_EVENTS, HARD_MAX_EVENTS, clamp_capacity, resolve_capacity_from_env,
};
