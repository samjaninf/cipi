#!/bin/bash
#############################################
# Cipi Migration 4.7.16 — common.sh init chmod on read-only /etc
#
# Every `sudo cipi …` sources common.sh, which ran `chmod 700 /etc/cipi` without
# error suppression. On a read-only root (kernel remount-ro, dual-boot NTFS,
# etc.) that aborts even read-only API commands (db list, deploy status, …)
# with: chmod: Read-only file system (os error 30)
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
COMMON="${CIPI_LIB}/common.sh"

echo "Migration 4.7.16 — Harden common.sh chmod on /etc/cipi..."

[[ -f "$COMMON" ]] || { echo "  common.sh not found — skip"; exit 0; }

if grep -q 'chmod 700 "${CIPI_CONFIG}" 2>/dev/null || true' "$COMMON"; then
    echo "  common.sh already patched"
    exit 0
fi

cp -a "$COMMON" "${COMMON}.bak.$(date +%s)"

# /etc/cipi init chmod (runs on every cipi source)
sed -i 's|^chmod 700 "${CIPI_CONFIG}"$|chmod 700 "${CIPI_CONFIG}" 2>/dev/null || true|' "$COMMON"
sed -i 's|^mkdir -p "${CIPI_CONFIG}" "${CIPI_LOG}"$|mkdir -p "${CIPI_CONFIG}" "${CIPI_LOG}" 2>/dev/null || true|' "$COMMON"

# apps-public.json projection
sed -i 's|^    chmod 640 "${CIPI_CONFIG}/apps-public.json"$|    chmod 640 "${CIPI_CONFIG}/apps-public.json" 2>/dev/null || true|' "$COMMON"

echo "  Patched ${COMMON}"
echo "Migration 4.7.16 complete"
