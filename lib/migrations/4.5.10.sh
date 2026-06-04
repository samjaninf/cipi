#!/bin/bash
#############################################
# Cipi Migration 4.5.10 — nginx.org sites-* layout fix
#
# nginx.org packages use conf.d/ only; Cipi expects sites-available/sites-enabled.
# Ensures those directories exist and drops the stock conf.d/default.conf.
# Idempotent — safe to re-run.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.5.10 — nginx sites-available/sites-enabled layout..."

if [[ -f "${CIPI_LIB}/nginx.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/nginx.sh"
else
    echo "  ERROR: ${CIPI_LIB}/nginx.sh not found — aborting"
    exit 0
fi

nginx_ensure_sites_layout
echo "  sites-available, sites-enabled, /var/www/html ready; conf.d/default.conf removed"

if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true
fi

echo "Migration 4.5.10 complete"
