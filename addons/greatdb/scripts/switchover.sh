#!/bin/bash
# switchover.sh — KubeBlocks switchover for GreatDB
# Transfers primary role to a candidate (or first available secondary).
#
# KB-injected env vars:
#   KB_SWITCHOVER_ROLE          — role of the pod triggering switchover ("primary" / "secondary")
#   KB_SWITCHOVER_CURRENT_NAME  — pod name of the current role holder
#   KB_SWITCHOVER_CURRENT_FQDN  — FQDN of the current role holder
#   KB_SWITCHOVER_CANDIDATE_FQDN — FQDN of the desired new primary (may be empty)
# Also available:
#   POD_FQDNS                   — comma-separated list of all pod FQDNs

set -eo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [switchover] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

mysql_cmd() {
    local host="$1"; shift
    greatdb -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" \
          -h"${host}" -P3306 --connect-timeout=10 -N -s "$@"
}

# Only act if this pod IS the primary
if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
    log "This pod is not the primary (role=${KB_SWITCHOVER_ROLE}). Nothing to do."
    exit 0
fi

current_fqdn="${KB_SWITCHOVER_CURRENT_FQDN}"
candidate_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"

log "Current primary: ${current_fqdn}"
log "Requested candidate: '${candidate_fqdn}'"

# If no candidate specified, pick the first secondary from POD_FQDNS
if [ -z "${candidate_fqdn}" ]; then
    IFS=',' read -ra all_fqdns <<< "${POD_FQDNS:-}"
    for fqdn in "${all_fqdns[@]}"; do
        fqdn=$(echo "$fqdn" | tr -d '[:space:]')
        [ -z "$fqdn" ] && continue
        [ "$fqdn" = "$current_fqdn" ] && continue
        # Check it's a live secondary
        role=$(mysql_cmd "${fqdn}" -e "SELECT IF(@@global.read_only=1,'secondary','primary');" 2>/dev/null | tr -d '[:space:]') || continue
        if [ "$role" = "secondary" ]; then
            candidate_fqdn="$fqdn"
            log "Auto-selected candidate: ${candidate_fqdn}"
            break
        fi
    done
    [ -z "${candidate_fqdn}" ] && die "No available secondary found for switchover"
fi

# Step 1: Make current primary read-only to stop new writes
log "Step 1: Setting current primary ${current_fqdn} to read_only=ON"
mysql_cmd "127.0.0.1" -e "SET GLOBAL super_read_only = ON; SET GLOBAL read_only = ON;" \
    || die "Failed to set read_only=ON on current primary"

# Step 2: Wait for candidate to catch up (up to 30s)
log "Step 2: Waiting for candidate ${candidate_fqdn} to catch up..."
primary_gtid=$(mysql_cmd "127.0.0.1" -e "SELECT @@global.gtid_executed;" 2>/dev/null | tr -d '[:space:]')
for i in $(seq 1 15); do
    cand_gtid=$(mysql_cmd "${candidate_fqdn}" -e "SELECT @@global.gtid_executed;" 2>/dev/null | tr -d '[:space:]') || true
    if [ "${cand_gtid}" = "${primary_gtid}" ]; then
        log "Candidate has caught up (GTID match)."
        break
    fi
    log "  Attempt ${i}/15: waiting 2s... primary_gtid=${primary_gtid:0:40}..."
    sleep 2
done

# Step 3: Promote candidate — stop replica, clear master, set writable
log "Step 3: Promoting candidate ${candidate_fqdn}"
mysql_cmd "${candidate_fqdn}" -e "
    STOP SLAVE;
    RESET SLAVE ALL;
    SET GLOBAL read_only = OFF;
    SET GLOBAL super_read_only = OFF;
" || die "Failed to promote candidate ${candidate_fqdn}"

# Step 4: Re-point all other replicas (including former primary) to the new primary
log "Step 4: Re-pointing other replicas to new primary ${candidate_fqdn}"
IFS=',' read -ra all_fqdns <<< "${POD_FQDNS:-}"
for fqdn in "${all_fqdns[@]}"; do
    fqdn=$(echo "$fqdn" | tr -d '[:space:]')
    [ -z "$fqdn" ] && continue
    [ "$fqdn" = "$candidate_fqdn" ] && continue  # skip new primary

    log "  Re-pointing ${fqdn} → ${candidate_fqdn}"
    mysql_cmd "${fqdn}" -e "
        STOP SLAVE;
        CHANGE MASTER TO
            MASTER_HOST='${candidate_fqdn}',
            MASTER_PORT=3306,
            MASTER_USER='${MYSQL_REPL_USER}',
            MASTER_PASSWORD='${MYSQL_REPL_PASSWORD}',
            MASTER_AUTO_POSITION=1;
        START SLAVE;
        SET GLOBAL read_only = ON;
    " 2>/dev/null || log "  WARNING: failed to re-point ${fqdn}, may need manual intervention"
done

log "Switchover complete. New primary: ${candidate_fqdn}"
