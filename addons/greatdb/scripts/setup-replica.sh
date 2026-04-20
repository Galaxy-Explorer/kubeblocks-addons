#!/bin/bash
# setup-replica.sh — KubeBlocks memberJoin for GreatDB
# Called after a pod becomes ready.
# - pod-0 (or when PRIMARY_POD_FQDN is empty / equals self): become primary (read_only=OFF)
# - other pods: CHANGE MASTER TO primary, START SLAVE

set -eo pipefail

MYSQL_CMD="greatdb -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PASSWORD} -h127.0.0.1 -P3306 --connect-timeout=10 -N -s"
POD_NAME="${KB_JOIN_MEMBER_POD_NAME:-${POD_NAME:-}}"
POD_FQDN="${KB_JOIN_MEMBER_POD_FQDN:-}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [setup-replica] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

wait_mysql() {
    local host="${1:-127.0.0.1}"
    local retries=30
    local i=0
    while ! greatdb -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" -h"${host}" -P3306 \
          --connect-timeout=3 -e "SELECT 1" &>/dev/null; do
        i=$((i+1))
        [ $i -ge $retries ] && die "MySQL at ${host} not ready after ${retries} attempts"
        log "Waiting for MySQL at ${host} (attempt ${i}/${retries})..."
        sleep 2
    done
}

# Determine ordinal from pod name (e.g. greatdb-0 → 0)
ordinal=0
if [[ "${POD_NAME}" =~ -([0-9]+)$ ]]; then
    ordinal="${BASH_REMATCH[1]}"
fi

# Check if this pod is the first one, or PRIMARY_POD_FQDN is not set / points to self
self_fqdn="${POD_FQDN}"
primary_fqdn="${PRIMARY_POD_FQDN:-}"
# PRIMARY_POD_FQDN may be comma-separated; take only the first entry
primary_fqdn=$(echo "${primary_fqdn}" | cut -d',' -f1 | tr -d '[:space:]')

log "Pod: ${POD_NAME} (ordinal=${ordinal}), PRIMARY_POD_FQDN='${primary_fqdn}'"

# Wait for local MySQL to be ready
wait_mysql "127.0.0.1"

# --- Bootstrap primary ---
if [ -z "${primary_fqdn}" ] || [ "${primary_fqdn}" = "${self_fqdn}" ] || [ "${ordinal}" -eq 0 -a -z "${primary_fqdn}" ]; then
    log "This pod is the primary. Setting read_only=OFF."
    $MYSQL_CMD -e "SET GLOBAL read_only = OFF; SET GLOBAL super_read_only = OFF;" || die "Failed to set read_only=OFF"

    log "Primary bootstrap complete."
    exit 0
fi

# --- Setup replica ---
log "Setting up replication from primary: ${primary_fqdn}"

# Wait for primary to be reachable
wait_mysql "${primary_fqdn}"

# Check if already replicating from the correct primary
current_master=$({ $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null || true; } | { grep "Master_Host:" || true; } | awk '{print $2}' | tr -d '[:space:]')
slave_running=$({ $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null || true; } | { grep "Slave_IO_Running:" || true; } | awk '{print $2}' | tr -d '[:space:]')

if [ "${current_master}" = "${primary_fqdn}" ] && [ "${slave_running}" = "Yes" ]; then
    log "Already replicating from ${primary_fqdn}. Skipping CHANGE MASTER TO."
    exit 0
fi

log "Configuring replication: STOP SLAVE → CHANGE MASTER TO → START SLAVE"

# Seed replica data from primary before configuring replication
log "Seeding replica data from primary via greatdbdump..."
greatdbdump -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" -h"${primary_fqdn}" -P3306 \
    --single-transaction --all-databases 2>/dev/null \
    | greatdb -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" -h127.0.0.1 -P3306 \
    || die "greatdbdump from ${primary_fqdn} failed"
log "Data seeding complete."

$MYSQL_CMD -e "STOP SLAVE;" 2>/dev/null || true
$MYSQL_CMD -e "
    CHANGE MASTER TO
        MASTER_HOST='${primary_fqdn}',
        MASTER_PORT=3306,
        MASTER_USER='${MYSQL_ROOT_USER}',
        MASTER_PASSWORD='${MYSQL_ROOT_PASSWORD}',
        MASTER_AUTO_POSITION=1;
" || die "CHANGE MASTER TO failed"

$MYSQL_CMD -e "START SLAVE;" || die "START SLAVE failed"

# Verify replication started
sleep 2
io_running=$({ $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null || true; } | { grep "Slave_IO_Running:" || true; } | awk '{print $2}' | tr -d '[:space:]')
sql_running=$({ $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null || true; } | { grep "Slave_SQL_Running:" || true; } | awk '{print $2}' | tr -d '[:space:]')

if [ "${io_running}" = "Yes" ] && [ "${sql_running}" = "Yes" ]; then
    log "Replication running successfully (IO: ${io_running}, SQL: ${sql_running})"
else
    last_err=$({ $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null || true; } | { grep "Last_Error:" || true; } | head -1)
    die "Replication not running after START SLAVE. IO=${io_running} SQL=${sql_running}. ${last_err}"
fi

# Set replica as read-only
$MYSQL_CMD -e "SET GLOBAL read_only = ON;" || die "Failed to set read_only=ON"
log "Replica setup complete."
