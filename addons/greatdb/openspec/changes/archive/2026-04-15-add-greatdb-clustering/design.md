## Context

GreatDB 是一个基于 MySQL 8.0 的分布式数据库。当前 addon 仅支持单节点 standalone 模式。需要在现有 `cmpd.yaml` 上叠加主从复制（primary/replica）能力。

关键约束：
- **syncer 不开源**，不可用。所有 HA 管理逻辑必须用纯 shell 脚本实现，通过 KubeBlocks `lifecycleActions` 钩子调用
- GreatDB 主从基于标准 MySQL 异步/半同步复制，可用 `CHANGE MASTER TO` / `SHOW SLAVE STATUS` 等标准 MySQL 命令管理
- KubeBlocks 通过 `roleProbe` 定期探测角色，通过 `switchover` / `memberJoin` / `memberLeave` 管理拓扑变更
- 参考实现：openstack-helm mariadb `_start.py.tpl`（Python 启动脚本的 Bash 移植思路）+ etcd addon 的 shell 脚本结构

环境变量来源：
- **自动注入**（KubeBlocks）: `KB_SWITCHOVER_CURRENT_NAME`, `KB_SWITCHOVER_CANDIDATE_FQDN`, `KB_JOIN_MEMBER_POD_FQDN`, `KB_JOIN_MEMBER_POD_NAME`, `KB_LEAVE_MEMBER_POD_FQDN`, `KB_LEAVE_MEMBER_POD_NAME`
- **通过 `vars` 声明**（cmpd）: `PRIMARY_POD_FQDN`（podFQDNsForRole: primary）, `POD_FQDNS`（podFQDNs）, `MYSQL_ROOT_USER`, `MYSQL_ROOT_PASSWORD`, `MYSQL_REPL_USER`, `MYSQL_REPL_PASSWORD`

## Goals / Non-Goals

**Goals:**
- 主从拓扑：一主多从，primary 可写，secondary 只读
- roleProbe：通过 SQL 探测当前 pod 角色，输出 `primary` 或 `secondary`
- memberJoin：新 replica pod ready 后自动执行 `CHANGE MASTER TO` 完成主从搭建
- memberLeave：replica 离开前执行 `STOP SLAVE; RESET SLAVE ALL`
- switchover：primary 更新前把主权转移给一个 replica（`STOP SLAVE` + promote + 其他节点 re-point）
- ClusterDefinition：提供 `standalone` 和 `replication` 两个拓扑
- my.cnf 增加复制所需参数（server-id、binlog、gtid）
- 新增 `replication` 系统账户用于复制鉴权

**Non-Goals:**
- 半同步复制（semisync）—— 可后续迭代
- 自动故障转移（primary crash 后自动选主）—— 需要外部选举组件，本期不做
- ProxySQL 等读写分离代理
- 数据迁移（dataDump/dataLoad）—— 本期不实现，用 XtraBackup 走 rebuild 路径

## Decisions

### 1. 不新增 cmpd，直接扩展现有 cmpd.yaml
**决策**：在现有 `cmpd.yaml` 中添加 `roles`、`lifecycleActions`、新 vars、新系统账户。  
**理由**：用户明确要求；standalone 和 replication 共用同一个 ComponentDefinition，通过 ClusterDefinition topology 区分；减少维护重复。  
**替代方案**：新建 `cmpd-replication.yaml` —— 被否决，增加不必要复杂度。

### 2. 用 shell 脚本替代 syncer 实现 HA 逻辑
**决策**：所有 lifecycleAction 指向 `/scripts/greatdb/` 目录下的 shell 脚本，通过 `exec` 方式调用。  
**理由**：syncer 不开源；shell 脚本可读、可维护；etcd、mogdb 等 addon 已验证此模式可行。  
**风险**：脚本异常退出码会影响 KubeBlocks 控制器决策，需严格处理错误路径。

### 3. roleProbe 用 SQL 查询而非文件标记
**决策**：执行 `SELECT @@global.read_only` 判断角色：`0` = primary，`1` = secondary。  
**理由**：GreatDB 兼容 MySQL，`read_only` 变量是最可靠的角色标识；不依赖文件系统状态。  
**替代方案**：解析 `SHOW SLAVE STATUS` —— 更复杂，且 primary 节点执行会报错。

### 4. memberJoin 通过 PRIMARY_POD_FQDN var 找主节点
**决策**：在 `vars` 中声明 `PRIMARY_POD_FQDN`（`podFQDNsForRole: primary, option: Optional`），memberJoin 脚本用此变量执行 `CHANGE MASTER TO`。  
**理由**：KubeBlocks 会把当前 primary 角色 pod 的 FQDN 注入为环境变量，脚本无需自己发现 primary。  
**边界情况**：初次集群启动时无 primary（pod-0 是第一个 primary），此时 `PRIMARY_POD_FQDN` 为空，脚本需检测并跳过 `CHANGE MASTER TO`（pod-0 直接以 primary 启动）。

### 5. switchover 最小化实现
**决策**：switchover 脚本只做：①确认当前 pod 是 primary；②若有 candidate 则 `STOP SLAVE` on candidate + promote；③通知其他 replicas 重新 `CHANGE MASTER TO` 新主。  
**理由**：KubeBlocks 的 switchover 场景主要是滚动更新前转移主权，不需要完整 failover 逻辑。  
**局限**：primary 宕机后需人工干预或用 OpsRequest switchover，不自动选主。

### 6. GTID 模式
**决策**：my.cnf 启用 `gtid_mode=ON` + `enforce_gtid_consistency=ON`，`CHANGE MASTER TO` 使用 `MASTER_AUTO_POSITION=1`。  
**理由**：GTID 使 replica 重新指向新 primary 更简单可靠，不需要记录 binlog position。

## Risks / Trade-offs

- **[风险] primary 宕机不自动选主** → 本期接受；运维通过 OpsRequest/手动 switchover 恢复。未来可集成 Orchestrator 实现自动 failover。
- **[风险] memberJoin 竞争条件**：多个 replica 同时 join 时可能并发执行 `CHANGE MASTER TO` → `CHANGE MASTER TO` 是幂等的，并发执行无副作用。
- **[风险] switchover 期间短暂不可写**：primary 执行 `SET GLOBAL read_only=ON` 后到新主接管之间有短暂窗口 → 可接受（秒级）。
- **[Trade-off] shell 脚本 vs Go sidecar**：shell 更简单但调试困难；Go sidecar 功能强但需要单独构建和维护镜像 → 选 shell，够用且与 etcd/mogdb 模式一致。

## Migration Plan

1. 本次变更对现有 standalone 部署无影响（`cmpd.yaml` 中新增字段均为 optional）
2. 新建 `ClusterDefinition` 使 replication 拓扑可用
3. 用户迁移：standalone → replication 需要重新创建 Cluster（不支持原地迁移，属正常 day-2 操作）

## Open Questions

- GreatDB 容器镜像中是否已包含标准 `mysqladmin` / `mysql` 命令行工具？（假设：是，基于标准 MySQL 8.0 兼容镜像）
- KubeBlocks controller 触发 memberJoin 的确切时机：是 pod Ready 后立即触发，还是等所有 pod 都 Ready？（假设：pod Ready 后逐个触发）
