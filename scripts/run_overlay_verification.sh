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
#   full          — Overlay + Click-through + Probe + AOT + Report
#   report        — nur SMOLIT_WINDOW_REPORT=1 (Report für Baseline)
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
         SMOLIT_WINDOW_REPORT; do
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
