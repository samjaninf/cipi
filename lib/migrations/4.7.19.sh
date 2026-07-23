#!/bin/bash
#############################################
# Cipi Migration 4.7.19 — Fix ~/.ssh mode for Deployer localhost SSH
#
# App create used mkdir without chmod 700 on ~/.ssh. With umask 002 the
# directory becomes 775 (group-writable); OpenSSH StrictModes then refuses
# pubkey auth ("Authentication refused: bad ownership or modes for directory
# /home/<app>/.ssh") and deploy hangs on a password prompt.
#############################################

set -e

echo "Migration 4.7.19 — Harden app ~/.ssh permissions (700)..."

fixed=0
for home in /home/*/; do
    u=$(basename "$home")
    [[ "$u" =~ ^[a-z][a-z0-9]{2,31}$ ]] || continue
    [[ "$u" == "cipi" ]] && continue
    ssh_dir="${home}.ssh"
    [[ -d "$ssh_dir" ]] || continue

    chown "${u}:${u}" "$ssh_dir" 2>/dev/null || true
    chmod 700 "$ssh_dir"
    [[ -f "${ssh_dir}/authorized_keys" ]] && chmod 600 "${ssh_dir}/authorized_keys"
    [[ -f "${ssh_dir}/id_ed25519" ]] && chmod 600 "${ssh_dir}/id_ed25519"
    [[ -f "${ssh_dir}/id_ed25519.pub" ]] && chmod 644 "${ssh_dir}/id_ed25519.pub"
    [[ -f "${ssh_dir}/known_hosts" ]] && chmod 600 "${ssh_dir}/known_hosts"
    # Ensure ownership on key files (root-owned keys also break client/server auth)
    chown -R "${u}:${u}" "$ssh_dir" 2>/dev/null || true
    ((fixed++)) || true
    echo "  fixed ${u}"
done

echo "Migration 4.7.19 complete (${fixed} app(s))"
