#!/bin/bash
#############################################
# Cipi Migration 4.7.15 — sudo-rs compatible cipi-api sudoers
#
# sudo-rs (default on Ubuntu 25.10+) rejects wildcards except as the final
# argument. "cipi db restore * *" breaks parsing of /etc/sudoers.d/cipi-api,
# so www-data cannot run any API sudo commands ("I'm afraid I can't do that").
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.7.15 — Fix /etc/sudoers.d/cipi-api for sudo-rs..."

# shellcheck source=/dev/null
source "${CIPI_LIB}/cipi-api-sudoers.sh"
write_cipi_api_sudoers

echo "Migration 4.7.15 complete"
