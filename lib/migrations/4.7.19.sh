#!/bin/bash
#############################################
# Cipi Migration 4.7.19 — Fix ~/.ssh mode + purge orphan app users
#
# 1) App create used mkdir without chmod 700 on ~/.ssh. With umask 002 the
#    directory becomes 775 (group-writable); OpenSSH StrictModes then refuses
#    pubkey auth ("Authentication refused: bad ownership or modes for directory
#    /home/<app>/.ssh") and deploy hangs on a password prompt.
#
# 2) app delete used `userdel -r … || true`, which often failed silently when
#    processes still held the UID — leaving orphan /home/<app> trees (and SSH
#    keys) that are no longer in apps.json. Purge those leftovers.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.7.19 — Harden ~/.ssh + purge orphan app users..."

# shellcheck source=/dev/null
source "${CIPI_LIB}/common.sh"

# ── 1. chmod 700 ~/.ssh for registered apps ───────────────────
fixed=0
registered=$(vault_read apps.json 2>/dev/null | jq -r 'keys[]' 2>/dev/null || true)

while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    ssh_dir="/home/${u}/.ssh"
    [[ -d "$ssh_dir" ]] || continue
    chown -R "${u}:${u}" "$ssh_dir" 2>/dev/null || true
    chmod 700 "$ssh_dir"
    [[ -f "${ssh_dir}/authorized_keys" ]] && chmod 600 "${ssh_dir}/authorized_keys"
    [[ -f "${ssh_dir}/id_ed25519" ]] && chmod 600 "${ssh_dir}/id_ed25519"
    [[ -f "${ssh_dir}/id_ed25519.pub" ]] && chmod 644 "${ssh_dir}/id_ed25519.pub"
    [[ -f "${ssh_dir}/known_hosts" ]] && chmod 600 "${ssh_dir}/known_hosts"
    ((fixed++)) || true
    echo "  fixed .ssh for ${u}"
done <<< "$registered"

echo "  hardened ${fixed} registered app ~/.ssh dir(s)"

# ── 2. Purge orphan users/homes (not in apps.json) ────────────
if declare -f purge_orphan_app_users >/dev/null; then
    purge_orphan_app_users
else
    echo "  WARN: purge_orphan_app_users missing — skip orphan sweep"
fi

echo "Migration 4.7.19 complete"
