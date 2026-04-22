#!/usr/bin/env bash
# run_overlay_verification.sh
#
# Kleiner Wrapper, um die Overlay-/Click-through-Verifikationsmatrix
# (docs/linux_overlay_verification_matrix.md) mit konsistenten Env-
# Kombinationen zu starten. Bewusst klein gehalten: keine Test-Suite,
# keine Assertion-Logik — das hier startet nur den Godot-UI-Build mit
# den richtigen SMOLIT_*-Variablen, damit die geloggten Blocks
# vergleichbar bleiben.
#
# Usage:
#   scripts/run_overlay_verification.sh <case>
#
# Cases:
#   baseline      — keine Opt-ins (Referenz-Lauf)
#   overlay       — SMOLIT_UI_OVERLAY=1
#   click-through — SMOLIT_UI_OVERLAY=1 + SMOLIT_UI_CLICK_THROUGH=1
#   probe         — SMOLIT_WINDOW_PROBE=1
#   aot-x11       — SMOLIT_UI_ALWAYS_ON_TOP=1 + SMOLIT_WINDOW_REPORT=1
#                   (X11-only Sonderpfad — no-op auf Wayland/GNOME)
#   aot-wayland-refusal
#                 — AOT-Env + SMOLIT_WINDOW_REPORT=1 mit Wayland-Env-
#                   Overrides. Diagnostik-Fall: zeigt, dass der
#                   Controller bei session_type=wayland sauber
#                   verweigert. KEIN echter Wayland-Compositor-Test —
#                   siehe docs/wayland_always_on_top_refusal_results.md.
#   full          — Overlay + Click-through + Probe + AOT + Report
#   report        — nur SMOLIT_WINDOW_REPORT=1 (Report für Baseline)
#
# Backend-Familie (Resolver-Verifikation, siehe
# docs/window_behavior_backend_verification.md):
#   resolver-smoke
#                 — Führt scripts/resolver_classification_smoke.gd aus.
#                   Prüft neun synthetische Session/Driver/Desktop-
#                   Kombinationen gegen die erwartete backend_id.
#                   Exit 0 = alle PASS.
#   resolver-wayland-mutter
#                 — Env-Override (Wayland + GNOME) + Report. Zeigt, dass
#                   der Resolver backend_wayland_mutter wählt und der
#                   Controller-Refusal-Pfad wie gewohnt greift.
#   resolver-wayland-wlroots
#                 — Env-Override (Wayland + sway). Zeigt backend_wayland_wlroots.
#   resolver-wayland-generic
#                 — Env-Override (Wayland + KDE). Zeigt backend_wayland_generic
#                   als ehrlichen Fallback.
#   resolver-noop — Env-Override (session_type=unknown). Zeigt backend_noop.
#
# WICHTIG: Die resolver-* Fälle sind Simulationen. Sie beweisen NICHT,
# dass die jeweiligen Compositoren wirklich vorhanden sind; sie
# beweisen nur, dass der Resolver bei diesen Env-Signalen das
# dokumentierte Backend wählt.
#
# Flags (vor dem Case-Argument):
#   --headless    — Godot headless starten (godot --headless --path ui/)
#   --report      — zusätzlich SMOLIT_WINDOW_REPORT=1 setzen
#   --scene       — Main-Szene als Standalone-Runtime starten statt
#                   Editor. Nötig für reale X11-AOT-Verifikation:
#                   die aot-x11-Fälle brauchen ein echtes Game-Fenster
#                   mit X11-Driver, kein Editor-Fenster.
#
# Beispiel (real-host Messung für docs/x11_always_on_top_verification.md):
#   scripts/run_overlay_verification.sh --scene --report aot-x11
#
# Für UX-Läufe (Fokus / Stacking / Workspace / Fullscreen-Peer) ist der
# `--scene`-Modus Pflicht: der Godot-Editor wäre kein verlässlicher
# Peer. Ein zweites Toplevel (z. B. `xterm`) und ein paar
# `xdotool` / `wmctrl` / `xprop`-Aufrufe neben diesem Wrapper liefern
# die Beobachtungen; siehe docs/x11_always_on_top_results.md für die
# konkreten Messkommandos.
#
# Beispiel (headless smoke, jeder Case):
#   scripts/run_overlay_verification.sh --headless --report click-through

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
UI_DIR="${REPO_ROOT}/ui"

HEADLESS=0
EXTRA_REPORT=0
SCENE_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless)
      HEADLESS=1
      shift
      ;;
    --report)
      EXTRA_REPORT=1
      shift
      ;;
    --scene)
      SCENE_RUN=1
      shift
      ;;
    -h|--help)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ "${HEADLESS}" -eq 1 && "${SCENE_RUN}" -eq 1 ]]; then
  echo "--scene and --headless together are nonsensical: scene-run requires a real X11 window" >&2
  exit 64
fi

if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") [--headless] [--report] <case>" >&2
  echo "see --help for available cases" >&2
  exit 64
fi

CASE="$1"
shift

# Env per case. Alles andere bleibt bewusst unangefasst.
case "${CASE}" in
  baseline)
    ;;
  overlay)
    export SMOLIT_UI_OVERLAY=1
    ;;
  click-through)
    export SMOLIT_UI_OVERLAY=1
    export SMOLIT_UI_CLICK_THROUGH=1
    ;;
  probe)
    export SMOLIT_WINDOW_PROBE=1
    ;;
  aot-x11)
    # X11-only special path — opt-in Always-on-top. Bewusst mit Report,
    # weil das der einzige Weg ist, das Ergebnis ehrlich einzuordnen.
    export SMOLIT_UI_ALWAYS_ON_TOP=1
    export SMOLIT_WINDOW_REPORT=1
    ;;
  aot-wayland-refusal)
    # Diagnostik: Env-Override erzwingt die Wayland-Branch der
    # Capability-Detection. Reproduziert den Refusal-Pfad des
    # X11-only Sonderpfads. Kein echter Wayland-Compositor-Test —
    # Details in docs/wayland_always_on_top_refusal_results.md.
    export SMOLIT_UI_ALWAYS_ON_TOP=1
    export SMOLIT_WINDOW_REPORT=1
    export XDG_SESSION_TYPE=wayland
    export WAYLAND_DISPLAY=wayland-0-fake
    export XDG_CURRENT_DESKTOP=ubuntu:GNOME
    # DISPLAY explizit leeren, damit die Detection sich nicht doch
    # noch an X11 festhält.
    export DISPLAY=
    ;;
  full)
    export SMOLIT_UI_OVERLAY=1
    export SMOLIT_UI_CLICK_THROUGH=1
    export SMOLIT_WINDOW_PROBE=1
    export SMOLIT_UI_ALWAYS_ON_TOP=1
    export SMOLIT_WINDOW_REPORT=1
    ;;
  report)
    export SMOLIT_WINDOW_REPORT=1
    ;;
  resolver-smoke)
    # Spezialfall: statt die UI-Scene zu starten, läuft hier der
    # Classification-Smoketest gegen den Resolver.
    exec godot --headless --path "${UI_DIR}" \
      --script "${REPO_ROOT}/scripts/resolver_classification_smoke.gd"
    ;;
  resolver-wayland-mutter)
    export SMOLIT_WINDOW_REPORT=1
    export XDG_SESSION_TYPE=wayland
    export WAYLAND_DISPLAY=wayland-0-fake
    export XDG_CURRENT_DESKTOP=ubuntu:GNOME
    export DISPLAY=
    ;;
  resolver-wayland-wlroots)
    export SMOLIT_WINDOW_REPORT=1
    export XDG_SESSION_TYPE=wayland
    export WAYLAND_DISPLAY=wayland-0-fake
    export XDG_CURRENT_DESKTOP=sway
    export DISPLAY=
    ;;
  resolver-wayland-generic)
    export SMOLIT_WINDOW_REPORT=1
    export XDG_SESSION_TYPE=wayland
    export WAYLAND_DISPLAY=wayland-0-fake
    export XDG_CURRENT_DESKTOP=KDE
    export DISPLAY=
    ;;
  resolver-noop)
    export SMOLIT_WINDOW_REPORT=1
    export XDG_SESSION_TYPE=
    export WAYLAND_DISPLAY=
    export XDG_CURRENT_DESKTOP=
    export DISPLAY=
    ;;
  *)
    echo "unknown case: ${CASE}" >&2
    echo "see --help" >&2
    exit 64
    ;;
esac

if [[ "${EXTRA_REPORT}" -eq 1 ]]; then
  export SMOLIT_WINDOW_REPORT=1
fi

echo "──────────────────────────────────────────────────────────"
echo "overlay verification run: case=${CASE} headless=${HEADLESS}"
echo "env:"
for v in SMOLIT_UI_OVERLAY SMOLIT_UI_CLICK_THROUGH \
         SMOLIT_UI_ALWAYS_ON_TOP \
         SMOLIT_WINDOW_PROBE SMOLIT_WINDOW_PROBE_REVERT \
         SMOLIT_WINDOW_REPORT \
         XDG_SESSION_TYPE WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP; do
  printf "  %-28s = %s\n" "$v" "${!v-(unset)}"
done
echo "──────────────────────────────────────────────────────────"

if ! command -v godot >/dev/null 2>&1; then
  echo "godot binary not found in PATH" >&2
  exit 127
fi

if [[ "${HEADLESS}" -eq 1 ]]; then
  exec godot --headless --path "${UI_DIR}" "$@"
elif [[ "${SCENE_RUN}" -eq 1 ]]; then
  # Main scene als Standalone-Runtime — kein Editor, damit ein bereits
  # geöffneter Editor nicht kollidiert und der echte X11-Driver wirksam
  # ist. Pfad ist die im Projekt als main konfigurierte Scene.
  exec godot --path "${UI_DIR}" scenes/main.tscn "$@"
else
  exec godot --path "${UI_DIR}" "$@"
fi
