## ADDED Requirements

### Requirement: Primary/replica topology declared in ClusterDefinition
A `ClusterDefinition` named `greatdb` SHALL define two topologies: `standalone` (single node, default) and `replication` (one primary + N replicas).

#### Scenario: Standalone topology is default
- **WHEN** a user creates a Cluster referencing the `greatdb` ClusterDefinition without specifying a topology
- **THEN** the cluster uses the `standalone` topology with a single greatdb pod

#### Scenario: Replication topology available
- **WHEN** a user creates a Cluster specifying topology `replication`
- **THEN** the cluster provisions pods using the `greatdb` ComponentDefinition with roles enabled

---

### Requirement: Roles defined on ComponentDefinition
The greatdb `ComponentDefinition` SHALL declare two roles: `primary` (exclusive, higher update priority) and `secondary`.

#### Scenario: Roles registered
- **WHEN** the ComponentDefinition is applied
- **THEN** it contains a `roles` list with entries for `primary` (isExclusive: true, updatePriority: 2) and `secondary` (updatePriority: 1)

---

### Requirement: Role detection via roleProbe
The ComponentDefinition SHALL define a `roleProbe` that executes a shell script (`role-probe.sh`) to determine the current pod's role.

#### Scenario: Primary role detected
- **WHEN** `role-probe.sh` runs on a pod where `@@global.read_only = 0`
- **THEN** the script outputs `primary` to stdout and exits 0

#### Scenario: Secondary role detected
- **WHEN** `role-probe.sh` runs on a pod where `@@global.read_only = 1`
- **THEN** the script outputs `secondary` to stdout and exits 0

#### Scenario: Detection failure
- **WHEN** the MySQL connection fails or the query errors
- **THEN** the script exits non-zero and outputs an error message to stderr

---

### Requirement: Automatic replica setup via memberJoin
The ComponentDefinition SHALL define a `memberJoin` lifecycleAction that runs `setup-replica.sh` after a new pod becomes ready.

#### Scenario: First pod (pod-0) skips replica setup
- **WHEN** `setup-replica.sh` runs on pod-0 and `PRIMARY_POD_FQDN` is empty or equals the current pod's FQDN
- **THEN** the script sets `read_only=OFF` (this node IS the primary) and exits 0 without executing `CHANGE MASTER TO`

#### Scenario: Subsequent pods join as replicas
- **WHEN** `setup-replica.sh` runs on a non-primary pod and `PRIMARY_POD_FQDN` is set to a reachable host
- **THEN** the script executes `STOP SLAVE; CHANGE MASTER TO MASTER_HOST=<PRIMARY_POD_FQDN>, MASTER_AUTO_POSITION=1, ...; START SLAVE` and exits 0

#### Scenario: Setup is idempotent
- **WHEN** `setup-replica.sh` is called on a pod that is already replicating from the correct primary
- **THEN** the script detects the existing `SHOW SLAVE STATUS` matches the target and exits 0 without re-running `CHANGE MASTER TO`

---

### Requirement: Graceful replica removal via memberLeave
The ComponentDefinition SHALL define a `memberLeave` lifecycleAction that runs `leave-member.sh` before a pod is removed.

#### Scenario: Secondary leaves cleanly
- **WHEN** `leave-member.sh` runs on a secondary pod (`KB_LEAVE_MEMBER_POD_NAME` is set)
- **THEN** the script connects to that pod and executes `STOP SLAVE; RESET SLAVE ALL` then exits 0

#### Scenario: Primary leave blocked
- **WHEN** `leave-member.sh` is called on the primary pod
- **THEN** the script exits non-zero with an error message indicating primary cannot leave without prior switchover

---

### Requirement: Controlled switchover via switchover action
The ComponentDefinition SHALL define a `switchover` lifecycleAction that runs `switchover.sh` to transfer primary role before an update.

#### Scenario: Switchover with candidate
- **WHEN** `switchover.sh` runs with `KB_SWITCHOVER_ROLE=primary` and `KB_SWITCHOVER_CANDIDATE_FQDN` is set
- **THEN** the script: sets `read_only=ON` on current primary, connects to candidate and runs `STOP SLAVE; RESET SLAVE ALL; SET GLOBAL read_only=OFF`, then tells remaining replicas to point to the new primary via `CHANGE MASTER TO`

#### Scenario: Switchover without candidate
- **WHEN** `switchover.sh` runs with `KB_SWITCHOVER_ROLE=primary` and `KB_SWITCHOVER_CANDIDATE_FQDN` is empty
- **THEN** the script picks the first available secondary from `POD_FQDNS` and promotes it as above

#### Scenario: Non-primary pod skips switchover
- **WHEN** `switchover.sh` runs on a secondary pod (`KB_SWITCHOVER_ROLE != primary`)
- **THEN** the script exits 0 immediately without any action

---

### Requirement: Replication system account
The ComponentDefinition SHALL include a `replication` system account (not initAccount) used exclusively for `CHANGE MASTER TO` authentication.

#### Scenario: Replication credentials available in scripts
- **WHEN** a lifecycle script needs to set up replication
- **THEN** `MYSQL_REPL_USER` and `MYSQL_REPL_PASSWORD` environment variables are available (declared via `vars` from the `replication` credential)

---

### Requirement: Replication-ready my.cnf defaults
The `my.cnf` config file SHALL include MySQL replication prerequisites: unique `server-id` (derived from pod ordinal), binary logging, relay log, and GTID mode.

#### Scenario: Each pod gets a unique server-id
- **WHEN** GreatDB starts on any pod
- **THEN** the `server-id` in `my.cnf` is unique per pod (e.g., set dynamically at startup based on ordinal)

#### Scenario: GTID mode enabled
- **WHEN** a replica executes `CHANGE MASTER TO MASTER_AUTO_POSITION=1`
- **THEN** replication succeeds because both primary and replica have `gtid_mode=ON` and `enforce_gtid_consistency=ON`

---

### Requirement: Vars for replication topology scripts
The ComponentDefinition SHALL declare vars sufficient for lifecycle scripts to locate the primary and all peers.

#### Scenario: Primary FQDN available
- **WHEN** any lifecycle action runs after role stabilization
- **THEN** `PRIMARY_POD_FQDN` env var contains the FQDN of the current primary pod (empty if no primary yet)

#### Scenario: All pod FQDNs available
- **WHEN** any lifecycle action runs
- **THEN** `POD_FQDNS` env var contains a comma-separated list of all pod FQDNs in the component
