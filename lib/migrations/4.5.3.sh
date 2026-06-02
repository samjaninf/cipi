#!/bin/bash
#############################################
# Cipi Migration 4.5.3 — Panel API ownership repair
#
# Root cause of the recurring panel HTTP 500: lib/self-update.sh runs
# `chown -R root:root /opt/cipi` on every update (incl. the nightly cron),
# which also re-roots the Laravel panel app under /opt/cipi/api. With
# storage/, database/ and bootstrap/cache/ owned root:root, PHP-FPM (www-data)
# cannot open storage/logs/laravel.log or write the SQLite DB:
#
#   UnexpectedValueException: The stream or file
#   "/opt/cipi/api/storage/logs/laravel.log" could not be opened in append
#   mode: Failed to open stream: Permission denied
#
# Laravel then fatals while trying to log, so the browser only sees a bare 500.
# The www-data re-chown lived inside the cipi-api package block, which is
# skipped when /opt/cipi/cipi-api is absent (package installed from packagist),
# leaving the panel broken after each update.
#
# 4.5.3 makes self-update reclaim those paths unconditionally. This migration
# repairs servers that are already in the broken state and clears any
# root-owned cached config so www-data can rebuild it.
#
# Idempotent: chown/chmod + cache clear + service restart. Safe to re-run.
#############################################

set -e

CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
CIPI_API_ROOT="${CIPI_API_ROOT:-/opt/cipi/api}"

echo "Migration 4.5.3 — Panel API ownership repair..."

if [[ -f "${CIPI_LIB}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/common.sh"
fi

if [[ ! -f "${CIPI_API_ROOT}/artisan" ]]; then
    echo "  API not installed on this server — nothing to do"
    echo "Migration 4.5.3 complete"
    exit 0
fi

# 1. Reclaim writable paths for www-data (storage, database, bootstrap/cache, .env).
if declare -f ensure_cipi_api_permissions >/dev/null 2>&1; then
    ensure_cipi_api_permissions
else
    mkdir -p "${CIPI_API_ROOT}/storage/logs" "${CIPI_API_ROOT}/database" "${CIPI_API_ROOT}/bootstrap/cache" 2>/dev/null || true
    chown -R www-data:www-data "${CIPI_API_ROOT}/storage" "${CIPI_API_ROOT}/database" "${CIPI_API_ROOT}/bootstrap/cache" 2>/dev/null || true
    if [[ -f "${CIPI_API_ROOT}/.env" ]]; then
        chown www-data:www-data "${CIPI_API_ROOT}/.env" 2>/dev/null || true
        chmod 640 "${CIPI_API_ROOT}/.env" 2>/dev/null || true
    fi
fi
echo "  ownership: storage/, database/, bootstrap/cache/, .env → www-data"

# 2. Drop any root-owned cached config so the next request rebuilds it cleanly
#    (a stale/root-owned bootstrap/cache/config.php would otherwise persist).
(cd "${CIPI_API_ROOT}" && sudo -u www-data /usr/bin/php artisan config:clear 2>/dev/null) || true
(cd "${CIPI_API_ROOT}" && sudo -u www-data /usr/bin/php artisan cache:clear 2>/dev/null) || true
echo "  caches cleared"

# 3. Restart FPM + queue so the panel serves from the repaired state immediately.
systemctl restart php8.5-fpm 2>/dev/null || true
systemctl restart cipi-queue 2>/dev/null || true
echo "  php8.5-fpm + cipi-queue restarted"

echo "Migration 4.5.3 complete"
