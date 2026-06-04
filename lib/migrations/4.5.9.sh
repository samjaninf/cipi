#!/bin/bash
#############################################
# Cipi Migration 4.5.9 — Nginx mainline upgrade (HTTP/2 bomb mitigation)
#
# The HTTP/2 bomb DoS chains HPACK header amplification with a zero-byte
# flow-control hold so memory is never freed. nginx fixed this in 1.29.8 with
# the max_headers directive (default 1000). Ubuntu 24.04 ships nginx 1.24.x,
# so existing Cipi servers must switch to the nginx.org mainline APT repository.
#
# This migration:
#   - pins nginx.org mainline (>= 1.29.8)
#   - drops libnginx-mod-http-headers-more-filter (Ubuntu-only; incompatible)
#   - rewrites nginx.conf with max_headers 1000
#
# Idempotent — safe to re-run.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.5.9 — Nginx mainline upgrade (HTTP/2 bomb mitigation)..."

if [[ -f "${CIPI_LIB}/nginx.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/nginx.sh"
else
    echo "  ERROR: ${CIPI_LIB}/nginx.sh not found — aborting"
    exit 0
fi

if nginx_upgrade_mainline_for_http2_bomb; then
    echo "Migration 4.5.9 complete"
else
    echo "Migration 4.5.9 finished with errors — review nginx manually"
    exit 0
fi
