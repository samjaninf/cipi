#!/bin/bash
#############################################
# Cipi Migration 4.7.13 — Weekly PHP upgrade check + immediate run
#
# PHP is blacklisted from unattended-upgrades (managed by Cipi). This adds a
# weekly cron job that runs `cipi php upgrade` and applies security patches
# for all installed PHP versions.
#
# Runs the upgrade check immediately on self-update (2026-07 PHP 8.x security
# release). Idempotent — safe to re-run.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.7.13 — PHP upgrade cron + immediate security check..."

if [[ -f "${CIPI_LIB}/common.sh" && -f "${CIPI_LIB}/php.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/common.sh"
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/php.sh"

    _php_setup_upgrade_cron
    echo "  Root crontab: weekly PHP upgrade check @ Sunday 03:30"

    echo "  Running PHP upgrade check now (security release)..."
    _php_upgrade || echo "  WARN: PHP upgrade check failed — see /var/log/cipi/php-upgrade.log"
else
    echo "  common.sh or php.sh not found — skip"
fi

echo "Migration 4.7.13 complete"
