#!/bin/bash
#############################################
# Cipi Migration 4.7.9 — Laravel log read ACL for panel API
#
# The panel API (www-data / cipi user) needs read access to Laravel log files
# under shared/storage/logs. Directory traverse ACLs alone are not enough when
# log files are app:app 664 — grant u:cipi:r on each *.log file.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.7.9 — Grant cipi read ACL on Laravel app log files..."

if ! command -v setfacl &>/dev/null || ! id cipi &>/dev/null; then
    echo "  Skipped (setfacl or cipi user unavailable)"
    exit 0
fi

if type ensure_app_logs_permissions &>/dev/null; then
    if [[ -f /etc/cipi/apps.json ]] || [[ -f /etc/cipi/apps-public.json ]]; then
        while IFS= read -r app; do
            [[ -n "$app" ]] && ensure_app_logs_permissions "$app"
        done < <(python3 -c "
import json, pathlib
for p in ('/etc/cipi/apps.json', '/etc/cipi/apps-public.json'):
    f = pathlib.Path(p)
    if f.is_file():
        try:
            data = json.loads(f.read_text())
            for name in data:
                print(name)
            break
        except Exception:
            pass
" 2>/dev/null || true)
    fi

    for home in /home/*/; do
        u=$(basename "$home")
        [[ "$u" =~ ^[a-z][a-z0-9]{2,31}$ ]] || continue
        [[ -d "${home}shared/storage/logs" ]] && ensure_app_logs_permissions "$u"
    done
fi

echo "Migration 4.7.9 complete"
