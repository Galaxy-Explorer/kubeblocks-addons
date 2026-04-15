#!/bin/bash
# leave-member.sh — KubeBlocks memberLeave for GreatDB
# Called before a pod is removed from the cluster.
# - secondary: STOP SLAVE; RESET SLAVE ALL (clean detach)
# - primary: refuse with error (must switchover first)
#
# KB-injected env vars:
#   KB_LEAVE_MEMBER_POD_NAME — pod name of the leaving member
#   KB_LEAVE_MEMBER_POD_FQDN — FQDN of the leaving member

set -eo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [leave-member] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

LEAVER_FQDN="${KB_LEAVE_MEMBER_POD_FQDN:-}"
LEAVER_NAME="${KB_LEAVE_MEMBER_POD_NAME:-}"

[ -z "${LEAVER_FQDN}" ] && die "KB_LEAVE_MEMBER_POD_FQDN is not set"

log "Processing leave for pod: ${LEAVER_NAME} (${LEAVER_FQDN})"

mysql_leaver() {
    mysql -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" \
          -h"${LEAVER_FQDN}" -P3306 --connect-timeout=10 -N -s "$@"
}

# Check if the leaving pod is the primary
read_only=$(mysql_leaver -e "SELECT @@global.read_only;" 2>/dev/null | tr -d '[:space:]') || {
    # If MySQL is unreachable, allow removal (pod may already be down)
    log "WARNING: Cannot connect to ${LEAVER_FQDN}. Assuming pod is already stopped; allowing removal."
    exit 0
}

if [ "${read_only}" = "0" ]; then
    die "Pod ${LEAVER_NAME} is the primary (read_only=OFF). Run switchover before removing the primary."
fi

# Secondary: detach cleanly
log "Pod ${LEAVER_NAME} is a secondary. Stopping and resetting replication."
mysql_leaver -e "STOP SLAVE; RESET SLAVE ALL;" \
    || die "Failed to stop/reset replication on ${LEAVER_NAME}"

log "Pod ${LEAVER_NAME} has left the replication group cleanly."
