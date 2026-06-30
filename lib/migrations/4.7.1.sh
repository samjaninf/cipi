#!/bin/bash
#############################################
# Cipi Migration 4.7.1 — GUI open_basedir + Composer path package
#
# Path-repo symlinks pointed outside /opt/cipi/gui/, so PHP-FPM open_basedir
# blocked CipiGuiServiceProvider (HTTP 500). Widen open_basedir, copy package
# into vendor (symlink=false), refresh FPM pool.
#
# Idempotent — safe to re-run.
#############################################

set -euo pipefail

export CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
export CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
export CIPI_LOG="${CIPI_LOG:-/var/log/cipi}"
[[ -z "${CIPI_GUI_ROOT:-}" ]] && export CIPI_GUI_ROOT="/opt/cipi/gui"

echo "Migration 4.7.1 — GUI open_basedir + cipi/gui vendor copy..."

if [[ ! -f /opt/cipi/lib/gui.sh ]]; then
    echo "  lib/gui.sh not found — skip"
    echo "Migration 4.7.1 complete."
    exit 0
fi

# shellcheck source=/dev/null
source /opt/cipi/lib/gui.sh

if [[ -f "${CIPI_GUI_ROOT}/artisan" && -d /opt/cipi/cipi-gui ]]; then
    _gui_composer_path_repo "${CIPI_GUI_ROOT}" /opt/cipi/cipi-gui
    (cd "${CIPI_GUI_ROOT}" && composer update cipi/gui --no-interaction 2>/dev/null) || true
    chown -R www-data:www-data "${CIPI_GUI_ROOT}" 2>/dev/null || true
    ensure_cipi_gui_permissions
    _gui_create_fpm_pool
    reload_php_fpm "8.5" 2>/dev/null || true
    echo "  FPM pool + cipi/gui vendor copy refreshed"
elif [[ -f /etc/php/8.5/fpm/pool.d/cipi-gui.conf ]]; then
    _gui_create_fpm_pool
    reload_php_fpm "8.5" 2>/dev/null || true
    echo "  FPM pool open_basedir refreshed"
else
    echo "  GUI not installed — skip"
fi

echo "Migration 4.7.1 complete."
