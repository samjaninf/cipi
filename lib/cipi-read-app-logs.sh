#!/bin/bash
# Paginated app log read for the Cipi panel API (replaces sudo bash for log tailing).
# Usage: cipi-read-app-logs <glob-pattern> <page> <per_page>
set -euo pipefail

pattern="${1:?pattern required}"
page="${2:-1}"
per_page="${3:-50}"

if [[ ! "$pattern" =~ ^/home/[a-z][a-z0-9]*/(logs/|shared/storage/logs/) ]]; then
    exit 1
fi

if ! [[ "$page" =~ ^[0-9]+$ && "$per_page" =~ ^[0-9]+$ ]]; then
    exit 1
fi

shopt -s nullglob
for f in $pattern; do
    [[ -f "$f" ]] || continue
    total=$(wc -l < "$f" | tr -d ' \n')
    from_end=$(( page * per_page ))
    echo "===CIPI_LOG_FILE:${f}:${total}==="
    /usr/bin/tail -n "$from_end" "$f" | /usr/bin/head -n "$per_page"
    echo "===CIPI_LOG_END==="
done
