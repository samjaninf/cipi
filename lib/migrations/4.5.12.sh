#!/bin/bash
#############################################
# Cipi Migration 4.5.12 — PHP APT sources (ondrej / sury / sanitize)
#
# Ubuntu 26.04 (resolute): Launchpad ppa:ondrej/php has no suite yet; packages.sury.org
# does (same maintainer, co-installable php8.3/8.4/8.5). A partial setup may leave a
# broken PPA source that breaks every apt-get update.
#
# Idempotent — safe to re-run.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.5.12 — PHP APT sources (sanitize + packages.sury.org)..."

if [[ ! -f "${CIPI_LIB}/php-apt.sh" ]]; then
    echo "  WARN: ${CIPI_LIB}/php-apt.sh not found — skipping"
    echo "Migration 4.5.12 complete"
    exit 0
fi

# shellcheck source=/dev/null
source "${CIPI_LIB}/php-apt.sh"

cipi_sanitize_broken_apt_sources
echo "  APT third-party sources sanitized"

codename="$(ubuntu_codename)"

if php_ondrej_ppa_available "$codename"; then
    echo "  ondrej/php PPA available for '${codename}' — nothing else to configure"
elif [[ -f /etc/apt/sources.list.d/php-sury.list ]] \
     || [[ -f /etc/apt/sources.list.d/php.list ]]; then
    echo "  packages.sury.org already configured — nothing else to configure"
elif php_setup_apt_sources; then
    apt-get update -qq 2>/dev/null || true
    echo "  Configured PHP packages via $(php_apt_source_label)"
else
    echo "  No multi-PHP repo for '${codename}' — Ubuntu archive only"
fi

echo "Migration 4.5.12 complete"
