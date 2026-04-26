//! Local Audit Correlation IDs (PR 54 — Runtime FA-1 spike).
//!
//! Implementiert das in
//! [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../../../docs/contracts/AUDIT_CORRELATION_ID_SPEC.md)
//! beschriebene `correlation_id`-Format als kleinen, lokalen
//! Generator. Scope: ein Smolit-Assistant-Lauf. Keine Cross-Repo-
//! Propagation, kein Netzwerk, keine Persistenz, kein Distributed
//! Tracing. Eine `correlation_id` lebt nur so lange wie der Action-
//! Lifecycle, an dem sie hängt.
//!
//! Das Format ist bewusst einfach: `corr_<timestamp_ms-hex><counter-hex>`.
//! Das ergibt einen kollisionsarmen, monotonen Identifier ohne
//! externe Dependency. ULID/UUID-v7 bleibt
//! [`docs/contracts/AUDIT_CORRELATION_ID_SPEC.md`](../../../docs/contracts/AUDIT_CORRELATION_ID_SPEC.md)
//! §5 als Future-Work; der Generator hier hält dieselben Constraints
//! ein (Prefix, lowercase, charset, max length).

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Pflichtprefix laut Spec §5. Verhindert Verwechslung mit
/// `audit_*` / `act_*` / `apr_*`.
pub const CORRELATION_ID_PREFIX: &str = "corr_";

/// Maximale Länge inklusive Prefix. Spec §5 erlaubt ≤ 80; der lokale
/// Generator bleibt deutlich darunter.
pub const MAX_CORRELATION_ID_LEN: usize = 80;

/// Mindestlänge inklusive Prefix. Spec §5 verlangt ≥ 24.
pub const MIN_CORRELATION_ID_LEN: usize = 24;

static CORRELATION_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Erzeugt eine neue `correlation_id` für den aktuellen Lauf. Format:
/// `corr_<timestamp_ms-hex><counter-hex>`. Der Counter ist
/// prozess-monoton und springt bei jedem Aufruf um eins; die
/// Kombination aus Timestamp und Counter macht Kollisionen über
/// einen einzelnen Lauf hinweg praktisch ausgeschlossen.
pub fn generate_correlation_id() -> String {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let n = CORRELATION_COUNTER.fetch_add(1, Ordering::Relaxed) + 1;
    format!("{CORRELATION_ID_PREFIX}{ts:012x}{n:016x}")
}

/// Validiert ein eingehendes `correlation_id`-Token gegen das in
/// Spec §5 fixierte Format. Liefert `None`, wenn das Token Prefix,
/// Charset oder Länge verletzt — der Audit-/Action-Pfad speichert
/// dann nichts statt eines kaputten Werts.
pub fn sanitize_correlation_id(raw: Option<String>) -> Option<String> {
    let s = raw?;
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.len() > MAX_CORRELATION_ID_LEN {
        return None;
    }
    if trimmed.len() < MIN_CORRELATION_ID_LEN {
        return None;
    }
    if !trimmed.starts_with(CORRELATION_ID_PREFIX) {
        return None;
    }
    let body = &trimmed[CORRELATION_ID_PREFIX.len()..];
    if body.is_empty() {
        return None;
    }
    if !body
        .chars()
        .all(|c| matches!(c, 'a'..='z' | '0'..='9' | '_'))
    {
        return None;
    }
    Some(trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_correlation_id_has_corr_prefix() {
        let id = generate_correlation_id();
        assert!(
            id.starts_with(CORRELATION_ID_PREFIX),
            "id must start with `corr_`, got {id}",
        );
    }

    #[test]
    fn generated_correlation_id_is_lowercase_safe_charset() {
        let id = generate_correlation_id();
        let body = id.strip_prefix(CORRELATION_ID_PREFIX).expect("prefix");
        assert!(!body.is_empty(), "body must be non-empty");
        for c in body.chars() {
            assert!(
                matches!(c, 'a'..='z' | '0'..='9' | '_'),
                "char `{c}` outside [a-z0-9_]",
            );
        }
    }

    #[test]
    fn generated_correlation_id_fits_max_length() {
        let id = generate_correlation_id();
        assert!(id.len() <= MAX_CORRELATION_ID_LEN);
        assert!(id.len() >= MIN_CORRELATION_ID_LEN);
    }

    #[test]
    fn generated_correlation_ids_are_not_constant() {
        let a = generate_correlation_id();
        let b = generate_correlation_id();
        let c = generate_correlation_id();
        assert_ne!(a, b);
        assert_ne!(b, c);
        assert_ne!(a, c);
    }

    #[test]
    fn invalid_correlation_id_is_rejected() {
        // Kein Prefix.
        assert!(sanitize_correlation_id(Some("act_000001".into())).is_none());
        // Falsches Charset.
        assert!(sanitize_correlation_id(Some("corr_AAAA-bbbb-ccccdddd".into())).is_none());
        // Zu kurz.
        assert!(sanitize_correlation_id(Some("corr_1".into())).is_none());
        // Zu lang.
        let long = format!("corr_{}", "a".repeat(MAX_CORRELATION_ID_LEN));
        assert!(sanitize_correlation_id(Some(long)).is_none());
        // Leer / None.
        assert!(sanitize_correlation_id(None).is_none());
        assert!(sanitize_correlation_id(Some(String::new())).is_none());
        assert!(sanitize_correlation_id(Some("   ".into())).is_none());
    }

    #[test]
    fn valid_correlation_id_passes_sanitization() {
        let id = generate_correlation_id();
        assert_eq!(sanitize_correlation_id(Some(id.clone())), Some(id));
    }

    #[test]
    fn generated_correlation_id_shape_is_stable() {
        let id = generate_correlation_id();
        // Prefix + 12 hex (timestamp_ms) + 16 hex (counter) = 5 + 28 = 33.
        assert_eq!(id.len(), CORRELATION_ID_PREFIX.len() + 12 + 16);
        let body = id.strip_prefix(CORRELATION_ID_PREFIX).expect("prefix");
        assert!(body.chars().all(|c| matches!(c, 'a'..='f' | '0'..='9')));
    }
}
