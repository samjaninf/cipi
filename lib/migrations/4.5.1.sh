#!/bin/bash
#############################################
# Cipi Migration 4.5.1 — Panel API scheduled maintenance & log pruning
#
# 4.5.0 fixed the *acute* symptom (silent 500s under load) by enlarging the
# FPM pool and surfacing worker SIGKILLs in the FPM log. But the *chronic*
# cause of the periodic 500s remained: the cipi-api Laravel package
# (v1.7.0+) registers scheduled commands — `cipi:prune-job-logs` daily,
# `cipi:record-server-metrics` every minute — and the cipi installer never
# wired up the `* * * * * php artisan schedule:run` cron for /opt/cipi/api.
# User apps had one in /var/spool/cron/crontabs/<app>; the panel API did not.
#
# Net effect over weeks of operation:
#   - storage/app/cipi-job-logs/{uuid}.log grew unbounded (one per deploy /
#     artisan / MCP / sudo cipi call), eventually filling the disk →
#     fopen() failures on the panel surfaced as opaque 500s on '/' and
#     /api/*, while user-app vhosts (separate pool, separate writes) kept
#     serving.
#   - cipi_jobs and failed_jobs accumulated forever in the panel SQLite.
#   - database.sqlite-wal grew without ever getting a TRUNCATE checkpoint
#     (PASSIVE checkpoints don't reclaim space under concurrent writers).
#   - Laravel session files piled up under the default 'file' driver — every
#     anonymous hit on '/' (bots, uptime monitors) wrote one; GC is
#     probabilistic (2/100) so low-traffic panels effectively never GC.
#
# This migration retrofits installed servers to match what `cipi api` writes
# on fresh installs in 4.5.1:
#  - installs /etc/cron.d/cipi-api (schedule:run + daily maintenance)
#  - installs /usr/local/bin/cipi-api-maintain (queue:prune-failed,
#    cipi_jobs purge, WAL checkpoint(TRUNCATE))
#  - sets SESSION_DRIVER=array in /opt/cipi/api/.env
#  - one-time prune of accumulated cipi-job-logs (>14 days)
#  - one-time WAL checkpoint and cipi_jobs/failed_jobs prune
#
# Idempotent: all file writes are full rewrites; .env edits are
# grep-then-sed-or-append; SQL DELETEs filter by age. Safe to re-run.
#############################################

set -e

CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
CIPI_API_ROOT="${CIPI_API_ROOT:-/opt/cipi/api}"
CIPI_API_CONFIG="${CIPI_CONFIG}/api.json"

echo "Migration 4.5.1 — Panel API scheduled maintenance & log pruning..."

if [[ -f "${CIPI_LIB}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/common.sh"
fi

# Skip cleanly if API was never installed on this server.
if [[ ! -f "$CIPI_API_CONFIG" ]] || [[ ! -f "${CIPI_API_ROOT}/artisan" ]]; then
    echo "  API not installed on this server — nothing to do"
    echo "Migration 4.5.1 complete"
    exit 0
fi

# 1. Install /etc/cron.d/cipi-api (schedule:run + daily maintenance).
#    Kept inline (not sourced from lib/api.sh) so this migration is a
#    self-contained snapshot, surviving lib/api.sh edits in future versions.
cat > /etc/cron.d/cipi-api <<CRON
# === CIPI API CRON ===
# Managed by 'cipi api'. Do not edit by hand — rewritten on each setup/update/upgrade.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

* * * * * www-data /usr/bin/php ${CIPI_API_ROOT}/artisan schedule:run >> /dev/null 2>&1
15 4 * * * www-data /usr/local/bin/cipi-api-maintain >> /var/log/cipi-api-maintain.log 2>&1
CRON
chmod 644 /etc/cron.d/cipi-api
echo "  /etc/cron.d/cipi-api installed (schedule:run every minute, maintenance daily @ 04:15)"

# 2. Install the maintenance helper.
cat > /usr/local/bin/cipi-api-maintain <<'MAINTAIN'
#!/bin/bash
# Cipi API daily maintenance — see /etc/cron.d/cipi-api.
set -u
API_ROOT="/opt/cipi/api"
DB_FILE=""
if [[ -f "${API_ROOT}/.env" ]] && grep -q '^DB_CONNECTION=sqlite' "${API_ROOT}/.env" 2>/dev/null; then
    raw=$(grep '^DB_DATABASE=' "${API_ROOT}/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]"\r')
    [[ -z "$raw" || "$raw" == "null" ]] && raw="database/database.sqlite"
    if [[ "$raw" =~ ^/ ]]; then
        DB_FILE="$raw"
    else
        DB_FILE="${API_ROOT}/${raw}"
    fi
fi

echo "[$(date '+%F %T')] cipi-api-maintain start"

if [[ -f "${API_ROOT}/artisan" ]]; then
    (cd "${API_ROOT}" && /usr/bin/php artisan queue:prune-failed --hours=336 2>&1) || true
fi

if [[ -n "$DB_FILE" && -f "$DB_FILE" ]] && command -v sqlite3 >/dev/null 2>&1; then
    deleted=$(/usr/bin/sqlite3 "$DB_FILE" \
        "DELETE FROM cipi_jobs WHERE status IN ('completed','failed') AND created_at < datetime('now','-14 days'); SELECT changes();" 2>/dev/null)
    echo "  cipi_jobs pruned: ${deleted:-0}"
    /usr/bin/sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    echo "  WAL checkpoint: ok"
fi

echo "[$(date '+%F %T')] cipi-api-maintain done"
MAINTAIN
chmod 755 /usr/local/bin/cipi-api-maintain
chown root:root /usr/local/bin/cipi-api-maintain
echo "  /usr/local/bin/cipi-api-maintain installed"

# 3. logrotate for the maintenance log.
if [[ -d /etc/logrotate.d ]]; then
    cat > /etc/logrotate.d/cipi-api-maintain <<'LR'
/var/log/cipi-api-maintain.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    copytruncate
}
LR
    echo "  /etc/logrotate.d/cipi-api-maintain installed"
fi

# 4. Force SESSION_DRIVER=array in .env. The panel is token-only (Sanctum);
#    the welcome route's 'web' middleware was writing a session file per
#    anonymous hit (bots, uptime checks) under the default 'file' driver,
#    accumulating thousands over weeks until scandir() on the sessions dir
#    started stalling FPM workers.
if [[ -f "${CIPI_API_ROOT}/.env" ]]; then
    if grep -q '^SESSION_DRIVER=' "${CIPI_API_ROOT}/.env" 2>/dev/null; then
        sed -i 's|^SESSION_DRIVER=.*|SESSION_DRIVER=array|' "${CIPI_API_ROOT}/.env"
    else
        echo 'SESSION_DRIVER=array' >> "${CIPI_API_ROOT}/.env"
    fi
    chown www-data:www-data "${CIPI_API_ROOT}/.env" 2>/dev/null || true
    chmod 640 "${CIPI_API_ROOT}/.env" 2>/dev/null || true
    echo "  ${CIPI_API_ROOT}/.env: SESSION_DRIVER=array"
fi

# 5. One-time cleanup of accumulated cipi-job-logs (the safety net for
#    servers that have been running 1.7.0+ for weeks). The scheduler will
#    keep this clean going forward.
JOB_LOGS_DIR="${CIPI_API_ROOT}/storage/app/cipi-job-logs"
if [[ -d "$JOB_LOGS_DIR" ]]; then
    deleted=$(find "$JOB_LOGS_DIR" -type f -name '*.log' -mtime +14 -print -delete 2>/dev/null | wc -l)
    echo "  ${JOB_LOGS_DIR}: pruned ${deleted} old log file(s)"
fi

# 6. One-time SQLite cleanup (mirror of the daily maintenance run, so
#    operators see the benefit immediately without waiting until 04:15).
DB_FILE=""
if [[ -f "${CIPI_API_ROOT}/.env" ]] && grep -q '^DB_CONNECTION=sqlite' "${CIPI_API_ROOT}/.env" 2>/dev/null; then
    raw=$(grep '^DB_DATABASE=' "${CIPI_API_ROOT}/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]"\r')
    [[ -z "$raw" || "$raw" == "null" ]] && raw="database/database.sqlite"
    if [[ "$raw" =~ ^/ ]]; then
        DB_FILE="$raw"
    else
        DB_FILE="${CIPI_API_ROOT}/${raw}"
    fi
fi
if [[ -n "$DB_FILE" && -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
    deleted=$(sudo -u www-data sqlite3 "$DB_FILE" \
        "DELETE FROM cipi_jobs WHERE status IN ('completed','failed') AND created_at < datetime('now','-14 days'); SELECT changes();" 2>/dev/null)
    echo "  cipi_jobs: pruned ${deleted:-0} row(s) older than 14 days"
    if [[ -f "${CIPI_API_ROOT}/artisan" ]]; then
        (cd "${CIPI_API_ROOT}" && sudo -u www-data /usr/bin/php artisan queue:prune-failed --hours=336 2>/dev/null) || true
    fi
    sudo -u www-data sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    echo "  ${DB_FILE}: WAL checkpoint(TRUNCATE)"
fi

# 7. Reload cron so /etc/cron.d/cipi-api is picked up immediately.
#    (cron re-reads /etc/cron.d on next minute boundary, but a reload is
#    faster feedback for the operator and is harmless.)
if systemctl list-unit-files 2>/dev/null | grep -q '^cron\.service'; then
    systemctl reload cron 2>/dev/null || systemctl restart cron 2>/dev/null || true
elif systemctl list-unit-files 2>/dev/null | grep -q '^crond\.service'; then
    systemctl reload crond 2>/dev/null || systemctl restart crond 2>/dev/null || true
fi
echo "  cron reloaded"

echo "Migration 4.5.1 complete"
