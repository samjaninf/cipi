#!/bin/bash
#############################################
# Cipi Migration 4.7.8 — panel API app log reads
#
# GET /api/apps/{name}/logs uses paginated tail via sudo. www-data was not
# allowed to run /bin/bash (or read Laravel logs under shared/storage/logs),
# so the GUI showed nginx/php logs but not laravel-*.log.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.7.8 — Install cipi-read-app-logs and extend cipi-api sudoers..."

if [[ -f "${CIPI_LIB}/cipi-read-app-logs.sh" ]]; then
    cp "${CIPI_LIB}/cipi-read-app-logs.sh" /usr/local/bin/cipi-read-app-logs
    chmod 755 /usr/local/bin/cipi-read-app-logs
    chown root:root /usr/local/bin/cipi-read-app-logs
    echo "  Installed /usr/local/bin/cipi-read-app-logs"
fi

cat > /etc/sudoers.d/cipi-api <<'SUDOEOF'
www-data ALL=(root) NOPASSWD: /usr/local/bin/cipi app create *, \
                               /usr/local/bin/cipi app edit *, \
                               /usr/local/bin/cipi app delete *, \
                               /usr/local/bin/cipi app suspend *, \
                               /usr/local/bin/cipi app unsuspend *, \
                               /usr/local/bin/cipi basicauth enable *, \
                               /usr/local/bin/cipi basicauth disable *, \
                               /usr/local/bin/cipi basicauth status *, \
                               /usr/local/bin/cipi deploy *, \
                               /usr/local/bin/cipi alias add *, \
                               /usr/local/bin/cipi alias remove *, \
                               /usr/local/bin/cipi ssl install *, \
                               /usr/local/bin/cipi db list, \
                               /usr/local/bin/cipi db create *, \
                               /usr/local/bin/cipi db delete *, \
                               /usr/local/bin/cipi db backup *, \
                               /usr/local/bin/cipi db restore * *, \
                               /usr/local/bin/cipi db password *, \
                               /usr/local/bin/cipi-read-app-logs *, \
                               /bin/cat /etc/cipi/apps.json
SUDOEOF
chmod 440 /etc/sudoers.d/cipi-api

echo "Migration 4.7.8 complete"
