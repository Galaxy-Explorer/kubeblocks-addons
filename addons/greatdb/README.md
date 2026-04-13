# GreatDB Addon for KubeBlocks

GreatDB is a distributed database based on MySQL, developed by Beijing Wanli Open Source Company. It is suitable for high-performance online transaction processing (OLTP) applications.

## Overview

This addon provides GreatDB database support for KubeBlocks, enabling you to deploy and manage GreatDB instances in Kubernetes environments.

## Prerequisites

- Kubernetes 1.19+
- KubeBlocks 0.5+
- PV provisioner support in the underlying infrastructure

## Installing the Addon

To install the GreatDB addon, use the following command:

```bash
kbcli addon enable greatdb
```

## Uninstalling the Addon

To uninstall the GreatDB addon, use the following command:

```bash
kbcli addon disable greatdb
```

## Configuration

The following table lists the configurable parameters of the GreatDB addon and their default values.

| Parameter                     | Description                                            | Default           |
|-------------------------------|--------------------------------------------------------|-------------------|
| `image.registry`              | GreatDB image registry                                 | `docker.io`       |
| `image.repository`            | GreatDB image name                                     | `greatdb/greatdb` |
| `image.tag`                   | GreatDB image tag                                      | `8.0.26`          |
| `image.pullPolicy`            | GreatDB image pull policy                              | `IfNotPresent`    |
| `auth.rootHost`               | Host for root user                                     | `%`               |
| `auth.createDatabase`         | Whether to create a custom database                    | `true`            |
| `auth.database`               | Name of the custom database                            | `greatdb`         |
| `service.type`                | Service type                                           | `ClusterIP`       |
| `service.port`                | Service port                                           | `3306`            |
| `persistence.enabled`         | Enable persistence using PVC                           | `true`            |
| `persistence.storageClass`    | Storage class for PVC                                  | ``                |
| `persistence.size`            | Size of persistent volume claim                        | `8Gi`             |
| `persistence.accessModes`     | Persistent volume access modes                         | `ReadWriteOnce`   |

## Example Usage

To create a GreatDB instance, you can use the following example:

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: greatdb-cluster
  namespace: default
spec:
  clusterDefRef: "greatdb"
  version: "8.0.26"
  componentSpecs:
    - name: greatdb
      componentDefRef: "greatdb"
      replicas: 1
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 100m
          memory: 256Mi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 8Gi
```

## Features

- High-performance OLTP database based on MySQL
- Distributed architecture
- Support for backup and recovery operations
- Prometheus monitoring integration
- Automated initialization

## Support

For support, please contact the KubeBlocks community through:

- GitHub Issues: [KubeBlocks Issues](https://github.com/apecloud/kubeblocks/issues)
- Slack: [KubeBlocks Slack](https://kubeblocks.slack.com)

## License

Apache License Version 2.0, see [LICENSE](https://github.com/apecloud/kubeblocks/blob/main/LICENSE).
