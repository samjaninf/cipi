#!/bin/bash
#############################################
# Cipi Migration 4.7.5 — GUI package from GitHub
#
# - Switch cipi/gui from bundled path repo to GitHub VCS
# - Simplify PHP-FPM open_basedir (package lives under vendor/)
# - Remove legacy /opt/cipi/cipi-gui copy
#
# Idempotent — safe to re-run.
#############################################

set -euo pipefail

export CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
export CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
export CIPI_LOG="${CIPI_LOG:-/var/log/cipi}"
[[ -z "${CIPI_GUI_ROOT:-}" ]] && export CIPI_GUI_ROOT="/opt/cipi/gui"

echo "Migration 4.7.5 — GUI package from GitHub..."

if [[ ! -f /opt/cipi/lib/gui.sh ]]; then
    echo "  lib/gui.sh not found — skip"
    echo "Migration 4.7.5 complete."
    exit 0
fi

# shellcheck source=/dev/null
source /opt/cipi/lib/gui.sh

if [[ -f "${CIPI_GUI_ROOT}/artisan" ]]; then
    (cd "${CIPI_GUI_ROOT}" && composer config --unset repositories.cipi-gui 2>/dev/null) || true
    _gui_composer_vcs_repo "${CIPI_GUI_ROOT}"
    (cd "${CIPI_GUI_ROOT}" && composer update cipi/gui --no-interaction 2>/dev/null) || true
    chown -R www-data:www-data "${CIPI_GUI_ROOT}" 2>/dev/null || true
    ensure_cipi_gui_permissions
    _gui_create_fpm_pool
    reload_php_fpm "8.5" 2>/dev/null || true
    echo "  cipi/gui switched to GitHub VCS + FPM pool updated"
else
    echo "  GUI not installed — skip"
fi

if [[ -d /opt/cipi/cipi-gui ]]; then
    rm -rf /opt/cipi/cipi-gui
    echo "  removed legacy /opt/cipi/cipi-gui"
fi

echo "Migration 4.7.5 complete."
