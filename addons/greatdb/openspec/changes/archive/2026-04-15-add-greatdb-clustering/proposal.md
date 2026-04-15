## Why

The current greatdb addon only supports single-node standalone deployment. Adding primary/replica replication (主从模式) to the existing ComponentDefinition enables high availability — allowing KubeBlocks to automatically manage failover, replica setup, and role-aware traffic routing. Since syncer is closed-source and unavailable, the HA management layer will be implemented using shell scripts (模仿 openstack-helm mariadb 的 _start.py.tpl 风格), leveraging KubeBlocks' native `lifecycleActions` (roleProbe, switchover, memberJoin, memberLeave) without any proprietary tooling.

## What Changes

- Extend the existing `cmpd.yaml` with:
  - `roles` definition (primary / secondary)
  - `lifecycleActions.roleProbe` — shell script that queries `SHOW SLAVE STATUS` / `SHOW MASTER STATUS` to detect role
  - `lifecycleActions.switchover` — promotes a replica to primary via `STOP SLAVE` + `RESET SLAVE ALL` + notify old primary
  - `lifecycleActions.memberJoin` — sets up `CHANGE MASTER TO` on the new replica pointing at the primary
  - `lifecycleActions.memberLeave` — executes `STOP SLAVE; RESET SLAVE ALL` to cleanly detach a replica
- Add a `replication-user` system account for replication authentication
- Add new vars for primary pod FQDN and pod FQDN list (used by scripts)
- Add replication lifecycle scripts: `role-probe.sh`, `switchover.sh`, `setup-replica.sh`, `leave-member.sh`
- Add a `ClusterDefinition` with two topologies: `standalone` and `replication`
- Extend `my.cnf` config with replication defaults: `server-id`, `log_bin`, `relay-log`, `gtid-mode`
- Update `configmap.yaml` to include the scripts ConfigMap
- Update `values.yaml` with replication section

## Capabilities

### New Capabilities

- `replication`: Primary/replica GreatDB topology — automatic replica bootstrapping via `CHANGE MASTER TO`, role detection via SQL probe, switchover, and graceful member leave

### Modified Capabilities

- (none — standalone behavior unchanged; `cmpd.yaml` additions are purely additive)

## Impact

- Modified templates: `cmpd.yaml`, `configmap.yaml`, `my.cnf` (config/), `values.yaml`
- New templates: `clusterdefinition.yaml`
- New scripts: `scripts/role-probe.sh`, `scripts/setup-replica.sh`, `scripts/switchover.sh`, `scripts/leave-member.sh`
- No breaking changes to existing standalone usage
