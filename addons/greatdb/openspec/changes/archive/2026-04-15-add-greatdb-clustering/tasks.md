## 1. my.cnf 配置更新

- [x] 1.1 在 `config/my.cnf` 中添加二进制日志参数：`log_bin`, `binlog_format=ROW`, `relay-log`
- [x] 1.2 在 `config/my.cnf` 中添加 GTID 参数：`gtid_mode=ON`, `enforce_gtid_consistency=ON`
- [x] 1.3 在 `config/my.cnf` 中添加 `skip-slave-start=ON`（避免重启时自动启动复制）

## 2. 主从管理脚本

- [x] 2.1 创建 `scripts/role-probe.sh`：通过 `SELECT @@global.read_only` 探测角色，输出 `primary` 或 `secondary`
- [x] 2.2 创建 `scripts/setup-replica.sh`：新 pod ready 后执行；pod-0 或无 primary 时设置 `read_only=OFF` 直接成为 primary；其他 pod 执行 `STOP SLAVE; CHANGE MASTER TO ...; START SLAVE`
- [x] 2.3 创建 `scripts/switchover.sh`：将 primary 角色转移给 candidate（或自动选一个 secondary）；包含 `read_only=ON` → promote candidate → 其他副本重新 `CHANGE MASTER TO`
- [x] 2.4 创建 `scripts/leave-member.sh`：secondary 离开前执行 `STOP SLAVE; RESET SLAVE ALL`；primary 离开则报错退出非0

## 3. cmpd.yaml 扩展

- [x] 3.1 在 `cmpd.yaml` 中添加 `roles` 列表：`primary`（isExclusive: true, updatePriority: 2）和 `secondary`（updatePriority: 1）
- [x] 3.2 在 `cmpd.yaml` 中添加 `lifecycleActions.roleProbe`：exec 调用 `/scripts/greatdb/role-probe.sh`，periodSeconds: 10
- [x] 3.3 在 `cmpd.yaml` 中添加 `lifecycleActions.memberJoin`：exec 调用 `/scripts/greatdb/setup-replica.sh`
- [x] 3.4 在 `cmpd.yaml` 中添加 `lifecycleActions.memberLeave`：exec 调用 `/scripts/greatdb/leave-member.sh`
- [x] 3.5 在 `cmpd.yaml` 中添加 `lifecycleActions.switchover`：exec 调用 `/scripts/greatdb/switchover.sh`
- [x] 3.6 在 `cmpd.yaml` 的 `systemAccounts` 中添加 `replication` 账户（非 initAccount）
- [x] 3.7 在 `cmpd.yaml` 的 `vars` 中添加 `PRIMARY_POD_FQDN`（podFQDNsForRole: primary, Optional）
- [x] 3.8 在 `cmpd.yaml` 的 `vars` 中添加 `POD_FQDNS`（podFQDNs: Required）
- [x] 3.9 在 `cmpd.yaml` 的 `vars` 中添加 `MYSQL_REPL_USER` 和 `MYSQL_REPL_PASSWORD`（从 replication credential 引用）

## 4. ClusterDefinition

- [x] 4.1 新建 `templates/clusterdefinition.yaml`，定义 `greatdb` ClusterDefinition
- [x] 4.2 添加 `standalone` topology（default: true），引用 `greatdb` ComponentDefinition regexp
- [x] 4.3 添加 `replication` topology，同样引用 `greatdb` ComponentDefinition regexp

## 5. configmap.yaml 脚本注册

- [x] 5.1 在 `templates/configmap.yaml` 中将新脚本（role-probe.sh、setup-replica.sh、switchover.sh、leave-member.sh）加入 `greatdb-scripts` ConfigMap 的 data 字段

## 6. values.yaml 更新

- [x] 6.1 在 `values.yaml` 中添加 `roleProbe` 配置节（periodSeconds、timeoutSeconds）
- [x] 6.2 在 `values.yaml` 中添加 `replication` 配置节（replicationUser 默认值）
