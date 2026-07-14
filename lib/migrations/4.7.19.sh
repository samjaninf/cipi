#!/bin/bash
#############################################
# Cipi Migration 4.7.19 — Fix `cipi db list` missing empty databases
#
# For servers already on 4.7.18 (read-only /etc/cipi + panel API).
# self-update copies lib/*.sh before this runs; migration verifies lib/db.sh
# uses information_schema.schemata and applies 4.7.19 lib polish when needed.
#
# Do not retro-edit migrations 4.7.16, 4.7.17, or 4.7.18.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
CIPI_REPO="${CIPI_REPO:-cipi-sh/cipi}"
CIPI_BRANCH="${CIPI_BRANCH:-latest}"
CIPI_UPDATE_TMP="${CIPI_UPDATE_TMP:-}"
DB_SH="${CIPI_LIB}/db.sh"
COMMON="${CIPI_LIB}/common.sh"
VAULT="${CIPI_LIB}/vault.sh"

echo "Migration 4.7.19 — Fix cipi db list (empty databases)..."

_419_db_ok() {
    [[ -f "$DB_SH" ]] && grep -q 'information_schema.schemata' "$DB_SH"
}

_419_lib_polish_ok() {
    [[ -f "$VAULT" ]] && grep -q '_cipi_safe_chmod' "$VAULT" \
        && [[ -f "$COMMON" ]] && ! grep -qE '^chmod 700 "\$\{CIPI_CONFIG\}"' "$COMMON"
}

_419_install_lib_from_bundle() {
    local src="$1"
    [[ -d "$src" ]] || return 1
    if [[ -f "${src}/db.sh" ]]; then
        cp -a "$DB_SH" "${DB_SH}.bak.419-$(date +%s)" 2>/dev/null || true
        cp "${src}/db.sh" "$DB_SH"
    fi
    if [[ -f "${src}/common.sh" ]]; then
        cp -a "$COMMON" "${COMMON}.bak.419-$(date +%s)" 2>/dev/null || true
        cp "${src}/common.sh" "$COMMON"
    fi
    if [[ -f "${src}/vault.sh" ]]; then
        cp -a "$VAULT" "${VAULT}.bak.419-$(date +%s)" 2>/dev/null || true
        cp "${src}/vault.sh" "$VAULT"
    fi
    chmod 700 "$DB_SH" "$COMMON" "$VAULT" 2>/dev/null || true
    return 0
}

if ! _419_db_ok || ! _419_lib_polish_ok; then
    echo "  lib/*.sh outdated — installing 4.7.19 lib..."
    if [[ -n "$CIPI_UPDATE_TMP" && -d "${CIPI_UPDATE_TMP}/lib" ]] \
        && _419_install_lib_from_bundle "${CIPI_UPDATE_TMP}/lib"; then
        echo "  Installed from self-update bundle (${CIPI_UPDATE_TMP}/lib)"
    elif command -v curl &>/dev/null; then
        tmp_lib="/tmp/cipi-419-lib.$$"
        mkdir -p "$tmp_lib"
        if curl -fsSL "https://raw.githubusercontent.com/${CIPI_REPO}/refs/heads/${CIPI_BRANCH}/lib/db.sh" -o "${tmp_lib}/db.sh" \
            && curl -fsSL "https://raw.githubusercontent.com/${CIPI_REPO}/refs/heads/${CIPI_BRANCH}/lib/common.sh" -o "${tmp_lib}/common.sh" \
            && curl -fsSL "https://raw.githubusercontent.com/${CIPI_REPO}/refs/heads/${CIPI_BRANCH}/lib/vault.sh" -o "${tmp_lib}/vault.sh" \
            && _419_install_lib_from_bundle "$tmp_lib"; then
            echo "  Installed from GitHub (${CIPI_BRANCH})"
        fi
        rm -rf "$tmp_lib"
    fi
fi

if ! _419_db_ok; then
    echo "  ERROR: lib/db.sh missing schemata query — run: sudo cipi self-update"
    exit 1
fi
echo "  lib/db.sh: lists empty databases (schemata query)"

if _419_lib_polish_ok; then
    echo "  lib/common.sh + lib/vault.sh: 4.7.19 polish OK (_cipi_safe_chmod, no init chmod)"
else
    echo "  WARN: common.sh/vault.sh missing 4.7.19 polish — re-run: sudo cipi self-update"
fi

echo "Migration 4.7.19 complete"
