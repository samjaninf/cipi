#!/bin/bash
#############################################
# Cipi Migration 4.7.3 — GUI runtime repair
#
# Servers still on pre-4.7.1 open_basedir or composer path symlinks get a full
# repair: vendor copy of cipi/gui + FPM pool + optimize:clear.
#
# Idempotent — safe to re-run.
#############################################

set -euo pipefail

export CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
export CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
export CIPI_LOG="${CIPI_LOG:-/var/log/cipi}"
[[ -z "${CIPI_GUI_ROOT:-}" ]] && export CIPI_GUI_ROOT="/opt/cipi/gui"

echo "Migration 4.7.3 — GUI runtime repair..."

if [[ ! -f /opt/cipi/lib/gui.sh ]]; then
    echo "  lib/gui.sh not found — skip"
    echo "Migration 4.7.3 complete."
    exit 0
fi

# shellcheck source=/dev/null
source /opt/cipi/lib/gui.sh

if [[ -f "${CIPI_GUI_ROOT}/artisan" ]]; then
    _gui_repair_runtime || true
    echo "  GUI runtime repaired"
else
    echo "  GUI not installed — skip"
fi

echo "Migration 4.7.3 complete."
