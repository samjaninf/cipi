#!/bin/bash
#############################################
# Cipi Migration 4.7.2 — GUI CSS/JS fixes
#
# - cipi/gui: missing Tailwind-like size utilities (giant SVG icons)
# - Remove duplicate Alpine.js (Livewire 3 bundles Alpine)
# - Nginx: X-Forwarded-Proto for HTTPS / Livewire (patch in place, keeps certbot SSL)
#
# Idempotent — safe to re-run.
#############################################

set -euo pipefail

export CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
export CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
export CIPI_LOG="${CIPI_LOG:-/var/log/cipi}"
[[ -z "${CIPI_GUI_ROOT:-}" ]] && export CIPI_GUI_ROOT="/opt/cipi/gui"

echo "Migration 4.7.2 — GUI CSS/JS + nginx forwarded proto..."

if [[ ! -f /opt/cipi/lib/gui.sh ]]; then
    echo "  lib/gui.sh not found — skip"
    echo "Migration 4.7.2 complete."
    exit 0
fi

# shellcheck source=/dev/null
source /opt/cipi/lib/gui.sh

if [[ -f "${CIPI_GUI_ROOT}/artisan" && -d /opt/cipi/cipi-gui ]]; then
    _gui_composer_path_repo "${CIPI_GUI_ROOT}" /opt/cipi/cipi-gui
    (cd "${CIPI_GUI_ROOT}" && composer update cipi/gui --no-interaction 2>/dev/null) || true
    chown -R www-data:www-data "${CIPI_GUI_ROOT}" 2>/dev/null || true
    ensure_cipi_gui_permissions
    echo "  cipi/gui package updated"
fi

nginx_site="/etc/nginx/sites-available/cipi-gui"
if [[ -f "$nginx_site" ]] && ! grep -q 'HTTP_X_FORWARDED_PROTO' "$nginx_site" 2>/dev/null; then
    sed -i '/fastcgi_param SCRIPT_FILENAME/a\        fastcgi_param HTTP_X_FORWARDED_PROTO $scheme;\n        fastcgi_param HTTPS $https if_not_empty;' "$nginx_site"
    if nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
        echo "  Nginx patched (forwarded proto)"
    else
        echo "  WARN: nginx -t failed after patch — revert manually if needed"
    fi
fi

if [[ -f /etc/php/8.5/fpm/pool.d/cipi-gui.conf ]]; then
    _gui_create_fpm_pool
    reload_php_fpm "8.5" 2>/dev/null || true
fi

echo "Migration 4.7.2 complete."
