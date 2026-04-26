//! Audit Ring Buffer (PR 19).
//!
//! Thread-safe, in-memory, bounded. Kein Persistenz-Pfad, kein
//! Datei-Export, kein Cloud-Upload. Ein Core-Restart leert den
//! Store vollständig — das ist bewusst: der Store ist ein Dev-/
//! Debug-Hilfsmittel, kein Produkt-Feature.
//!
//! Die Kapazität wird aus `SMOLIT_AUDIT_MAX_EVENTS` gelesen und auf
//! [`HARD_MAX_EVENTS`] hart gedeckelt. Ohne Env bleibt die
//! Kapazität bei [`DEFAULT_MAX_EVENTS`].

use std::collections::VecDeque;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use super::event::{AuditEvent, AuditFields, AuditKind};

pub const DEFAULT_MAX_EVENTS: usize = 100;
pub const HARD_MAX_EVENTS: usize = 1000;
pub const ENV_MAX_EVENTS: &str = "SMOLIT_AUDIT_MAX_EVENTS";

/// Liest die gewünschte Kapazität aus der Umgebung. Ungültige oder
/// fehlende Werte fallen auf [`DEFAULT_MAX_EVENTS`], negative/zero
/// Werte genauso. Werte ≥ [`HARD_MAX_EVENTS`] werden hart geklemmt.
pub fn resolve_capacity_from_env() -> usize {
    let raw = std::env::var(ENV_MAX_EVENTS).unwrap_or_default();
    let parsed: Option<usize> = raw.trim().parse().ok();
    clamp_capacity(parsed.unwrap_or(DEFAULT_MAX_EVENTS))
}

/// Klemmt eine gewünschte Kapazität in den zulässigen Bereich.
pub fn clamp_capacity(requested: usize) -> usize {
    if requested == 0 {
        DEFAULT_MAX_EVENTS
    } else if requested > HARD_MAX_EVENTS {
        HARD_MAX_EVENTS
    } else {
        requested
    }
}

/// Thread-safe Ring-Buffer über eine [`VecDeque`]. Wir halten den
/// Mutex bewusst fein: Record und List laufen unter derselben Lock-
/// Disziplin; die Lock-Dauer ist in allen Pfaden O(1) bis O(limit).
pub struct AuditStore {
    inner: Mutex<AuditInner>,
    counter: AtomicU64,
}

#[derive(Debug)]
struct AuditInner {
    events: VecDeque<AuditEvent>,
    capacity: usize,
}

impl AuditStore {
    pub fn new() -> Self {
        Self::with_capacity(DEFAULT_MAX_EVENTS)
    }

    pub fn with_capacity(cap: usize) -> Self {
        let capacity = clamp_capacity(cap);
        Self {
            inner: Mutex::new(AuditInner {
                events: VecDeque::with_capacity(capacity),
                capacity,
            }),
            counter: AtomicU64::new(0),
        }
    }

    /// Liest die Kapazität aus der Umgebung. Bequeme Factory für die
    /// App-Initialisierung.
    pub fn from_env() -> Self {
        Self::with_capacity(resolve_capacity_from_env())
    }

    /// Aktuelle Kapazität (nach Env-/Clamping-Pass).
    pub fn capacity(&self) -> usize {
        self.inner.lock().expect("audit store mutex poisoned").capacity
    }

    pub fn len(&self) -> usize {
        self.inner.lock().expect("audit store mutex poisoned").events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Legt ein neues Event an und pusht es in den Ring. Liefert eine
    /// Kopie des gespeicherten Events zurück (mit vergebener `audit_id`
    /// und Timestamp), damit Caller es direkt weiterverwenden können
    /// (z. B. für Logs).
    pub fn record(&self, kind: AuditKind, fields: AuditFields) -> AuditEvent {
        let event = self.build_event(kind, fields);
        let mut guard = self.inner.lock().expect("audit store mutex poisoned");
        while guard.events.len() >= guard.capacity {
            guard.events.pop_front();
        }
        guard.events.push_back(event.clone());
        event
    }

    /// Liefert die `limit` jüngsten Events (Kopien, neueste zuletzt).
    /// `limit=None` oder `limit > len` liefert den gesamten Store.
    pub fn list_recent(&self, limit: Option<usize>) -> Vec<AuditEvent> {
        let guard = self.inner.lock().expect("audit store mutex poisoned");
        let total = guard.events.len();
        let take = match limit {
            Some(n) => n.min(total),
            None => total,
        };
        let start = total - take;
        guard.events.iter().skip(start).cloned().collect()
    }

    /// Leert den Store. Primär für Tests gedacht; die Produktions-UX
    /// kennt keinen Clear-Command in PR 19.
    pub fn clear_for_tests(&self) {
        let mut guard = self.inner.lock().expect("audit store mutex poisoned");
        guard.events.clear();
    }

    fn build_event(&self, kind: AuditKind, fields: AuditFields) -> AuditEvent {
        let n = self.counter.fetch_add(1, Ordering::Relaxed) + 1;
        let audit_id = format!("aud_{n:06}");
        let timestamp_ms = current_millis();
        let f = fields.sanitized();
        AuditEvent {
            audit_id,
            timestamp_ms,
            kind,
            action_id: f.action_id,
            approval_id: f.approval_id,
            risk: f.risk,
            result: f.result,
            source: f.source,
            summary: f.summary,
            correlation_id: f.correlation_id,
            capability_id: f.capability_id,
        }
    }
}

impl Default for AuditStore {
    fn default() -> Self {
        Self::new()
    }
}

fn current_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_capacity_replaces_zero_with_default() {
        assert_eq!(clamp_capacity(0), DEFAULT_MAX_EVENTS);
    }

    #[test]
    fn clamp_capacity_enforces_hard_maximum() {
        assert_eq!(clamp_capacity(1_000_000), HARD_MAX_EVENTS);
    }

    #[test]
    fn clamp_capacity_passes_reasonable_values() {
        assert_eq!(clamp_capacity(42), 42);
        assert_eq!(clamp_capacity(HARD_MAX_EVENTS), HARD_MAX_EVENTS);
    }

    #[test]
    fn record_assigns_id_and_stores_event() {
        let store = AuditStore::with_capacity(10);
        let event = store.record(
            AuditKind::ActionPlanned,
            AuditFields::new()
                .with_action_id("act_1")
                .with_summary("plan"),
        );
        assert_eq!(event.audit_id, "aud_000001");
        assert_eq!(event.action_id.as_deref(), Some("act_1"));
        assert_eq!(store.len(), 1);
    }

    #[test]
    fn ring_buffer_evicts_oldest_when_full() {
        let store = AuditStore::with_capacity(3);
        for _ in 0..5 {
            store.record(AuditKind::ActionPlanned, AuditFields::new());
        }
        let events = store.list_recent(None);
        assert_eq!(events.len(), 3);
        // The oldest two have been evicted; the remaining IDs are 3,4,5.
        assert_eq!(events[0].audit_id, "aud_000003");
        assert_eq!(events[2].audit_id, "aud_000005");
    }

    #[test]
    fn list_recent_respects_limit() {
        let store = AuditStore::with_capacity(10);
        for _ in 0..5 {
            store.record(AuditKind::ActionStarted, AuditFields::new());
        }
        let events = store.list_recent(Some(2));
        assert_eq!(events.len(), 2);
        // Newest-last ordering: the two most recent are the last two.
        assert_eq!(events[0].audit_id, "aud_000004");
        assert_eq!(events[1].audit_id, "aud_000005");
    }

    #[test]
    fn list_recent_with_limit_greater_than_len_returns_all() {
        let store = AuditStore::with_capacity(10);
        store.record(AuditKind::ActionPlanned, AuditFields::new());
        let events = store.list_recent(Some(50));
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn clear_for_tests_empties_the_store_but_keeps_capacity() {
        let store = AuditStore::with_capacity(5);
        store.record(AuditKind::ActionPlanned, AuditFields::new());
        store.record(AuditKind::ActionCompleted, AuditFields::new());
        assert_eq!(store.len(), 2);
        store.clear_for_tests();
        assert_eq!(store.len(), 0);
        assert_eq!(store.capacity(), 5);
    }

    #[test]
    fn record_sanitizes_unknown_source_to_none() {
        let store = AuditStore::with_capacity(5);
        let event = store.record(
            AuditKind::IpcCommandReceived,
            AuditFields::new().with_source("attacker"),
        );
        assert!(event.source.is_none(), "unknown source must be dropped");
    }

    #[test]
    fn record_truncates_long_summary() {
        let store = AuditStore::with_capacity(5);
        let long = "x".repeat(400);
        let event = store.record(
            AuditKind::ActionPlanned,
            AuditFields::new().with_summary(long),
        );
        let summary = event.summary.expect("summary present");
        assert!(summary.chars().count() <= super::super::event::MAX_SUMMARY_CHARS);
    }
}
