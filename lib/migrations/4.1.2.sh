#!/bin/bash
#############################################
# Cipi Migration 4.1.2
# - Auth notify: skip internal sudo events
#   (script already copied by self-update)
#############################################

set -e

echo "Updating PAM auth notification script..."

if [[ -x /usr/local/bin/cipi-auth-notify ]]; then
    chmod 700 /usr/local/bin/cipi-auth-notify
    echo "  cipi-auth-notify updated (internal sudo events now filtered)"
else
    echo "  cipi-auth-notify not found — will be installed on next self-update"
fi

echo "Migration 4.1.2 complete"
