#!/bin/bash
#############################################
# Cipi Migration 4.4.16 — Panel API SQLite/logs/cache owned by www-data
#
# Composer and other root operations under /opt/cipi/api could leave
# database.sqlite or storage/logs owned by root, breaking artisan (sudo -u www-data)
# and PHP-FPM. ensure_cipi_api_permissions fixes storage, database, bootstrap/cache.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.4.16 — Panel API permissions (www-data)..."

if [[ -f "${CIPI_LIB}/common.sh" ]]; then
    source "${CIPI_LIB}/common.sh"
fi

if type ensure_cipi_api_permissions &>/dev/null; then
    ensure_cipi_api_permissions
fi

echo "Migration 4.4.16 complete"
