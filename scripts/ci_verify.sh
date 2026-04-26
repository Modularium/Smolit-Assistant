#!/usr/bin/env bash
# ci_verify.sh
#
# PR 38 — spiegelt die in .github/workflows/ci.yml laufenden Jobs
# lokal mit einem einzigen Aufruf. Kein Ersatz für den CI-Runner,
# nur ein Parity-Check für Contributor:innen.
#
# Was dieses Script tut:
#   1. Setzt `HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` auf eine
#      frische Temp-Location — damit lokale Dev-Artefakte unter
#      `~/.config/smolit-assistant/` die Tests nicht verfälschen
#      (das wiederkehrende Problem aus mehreren PRs).
#   2. Führt `cargo test --manifest-path core/Cargo.toml --locked` aus.
#   3. Führt die fünf in CI gespiegelten Smokes aus, wenn `godot`
#      im PATH ist. Ohne Godot bleibt das Script mit einem klaren
#      Hinweis ehrlich und meldet Exit 0 für den Core-Teil.
#
# Nicht-Ziele:
#   * Kein Packaging, kein Release, keine Artefakte.
#   * Kein Dependency-Install (Contributor:innen wissen selbst, wie sie
#     Rust + Godot auf ihrem Host besorgen — siehe docs/SETUP.md).
#   * Keine CI-Parallelisierung nachbauen — die Jobs laufen hier
#     sequentiell; der Zweck ist „lokal ein schneller Healthcheck",
#     nicht „CI-Replay".
#
# Usage:
#   scripts/ci_verify.sh            # voller Lauf (cargo + smokes)
#   scripts/ci_verify.sh core       # nur cargo
#   scripts/ci_verify.sh smokes     # nur smokes (benötigt Godot im PATH)

set -euo pipefail

SCOPE="${1:-all}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# --- XDG-Isolation -------------------------------------------------------
#
# Wir überschreiben NICHT `HOME`. Grund: rustup/cargo, Godot-User-Data
# und andere Tools finden ihre Toolchain-/Config-Pfade relativ zu
# `HOME`; ein isoliertes `HOME` würde `cargo` auf dem CI-Runner (wo
# `dtolnay/rust-toolchain@stable` in `$HOME/.cargo` installiert wird)
# die Toolchain verlieren lassen.
#
# Was wir wirklich isolieren müssen: die XDG-Config-, Cache- und
# Data-Pfade, weil Smolit-Core Konfiguration unter
# `$XDG_CONFIG_HOME/smolit-assistant/` (bzw.
# `$HOME/.config/smolit-assistant/`) liest. Das Setzen von
# `XDG_CONFIG_HOME` zwingt diesen Lookup auf einen leeren Ordner —
# lokale Dev-Artefakte (`text_chain.json`, `secrets.json`) können so
# nicht mehr hineinbluten. `XDG_DATA_HOME` wird mitisoliert, damit
# zukünftige Persistenz-Pfade (z. B. künftige Audit-/User-Daten
# unter `$XDG_DATA_HOME/smolit-assistant/`) automatisch in derselben
# Isolations-Domäne landen — der Gate-Check bleibt reproduzierbar,
# auch wenn neue Code-Pfade eine `XDG_DATA_HOME`-Location einführen.

ISOLATE_DIR="$(mktemp -d -t smolit-ci-XXXXXX)"
export XDG_CONFIG_HOME="${ISOLATE_DIR}/config"
export XDG_CACHE_HOME="${ISOLATE_DIR}/cache"
export XDG_DATA_HOME="${ISOLATE_DIR}/data"
mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}"

cleanup() {
    rm -rf "${ISOLATE_DIR}"
}
trap cleanup EXIT

echo "→ XDG isolation:"
echo "    XDG_CONFIG_HOME = ${XDG_CONFIG_HOME}"
echo "    XDG_CACHE_HOME  = ${XDG_CACHE_HOME}"
echo "    XDG_DATA_HOME   = ${XDG_DATA_HOME}"
echo "  (HOME stays ${HOME} — rustup/cargo need it; config lookups"
echo "   for smolit-assistant follow XDG_CONFIG_HOME first.)"
echo

# --- cargo test ----------------------------------------------------------

run_core() {
    echo "→ cargo test --manifest-path core/Cargo.toml --locked"
    cargo test --manifest-path core/Cargo.toml --locked
    echo
}

# --- ui smokes -----------------------------------------------------------

run_smokes() {
    if ! command -v godot >/dev/null 2>&1; then
        echo "→ godot not found in PATH — UI smokes skipped."
        echo "  Install Godot 4.6 (see docs/SETUP.md) to exercise this tier."
        return 0
    fi

    local smokes=(
        settings-shell-smoke
        avatar-render-polish-smoke
        workflow-visibility-smoke
        approval-card-smoke
        audit-panel-smoke
    )
    for case in "${smokes[@]}"; do
        echo "→ scripts/run_overlay_verification.sh ${case}"
        scripts/run_overlay_verification.sh "${case}"
        echo
    done
}

# --- dispatch ------------------------------------------------------------

case "${SCOPE}" in
    all)
        run_core
        run_smokes
        ;;
    core)
        run_core
        ;;
    smokes)
        run_smokes
        ;;
    *)
        echo "Usage: scripts/ci_verify.sh [all|core|smokes]" >&2
        exit 64
        ;;
esac

echo "ci_verify: PASS"
