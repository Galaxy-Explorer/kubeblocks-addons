#!/bin/bash
# role-probe.sh — KubeBlocks roleProbe for GreatDB
# Output: "primary" or "secondary" to stdout, exit 0
# On failure: error message to stderr, exit 1

set -eo pipefail

MYSQL_CMD="greatdb -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -h127.0.0.1 -P3306 --connect-timeout=5 -N -s"

# Query read_only: 0 = primary (writable), 1 = secondary (read-only)
read_only=$($MYSQL_CMD -e "SELECT @@global.read_only;" 2>/dev/null) || {
    echo "ERROR: failed to connect to MySQL" >&2
    exit 1
}

read_only=$(echo "$read_only" | tr -d '[:space:]')

if [ "$read_only" = "0" ]; then
    echo -n "primary"
elif [ "$read_only" = "1" ]; then
    echo -n "secondary"
else
    echo "ERROR: unexpected read_only value: '$read_only'" >&2
    exit 1
fi
