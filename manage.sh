#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-up}"
SERVICES=(minecraft jenkins samba)
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

for service in "${SERVICES[@]}"; do
    echo "==> ${service}: docker compose ${ACTION} ..."
    if [[ "$ACTION" == "up" ]]; then
        docker compose -f "${BASE_DIR}/${service}/docker-compose.yml" up -d
    elif [[ "$ACTION" == "down" ]]; then
        docker compose -f "${BASE_DIR}/${service}/docker-compose.yml" down
    else
        docker compose -f "${BASE_DIR}/${service}/docker-compose.yml" "${ACTION}"
    fi
done

echo "==> Done."
