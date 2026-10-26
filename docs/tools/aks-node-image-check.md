# aks-node-image-check

Compare the node image of every AKS node pool with the latest image AKS offers for it, and optionally start a node-image-only upgrade on the pools that are behind.

Node images carry the OS security patches. Keeping them current is routine hygiene that is easy to forget when the Kubernetes version itself is not changing.

## Prerequisites

- Azure CLI (`az`), signed in, and `jq`

## Permissions

- Check: `Reader` on the clusters
- `--upgrade`: `Microsoft.ContainerService/managedClusters/agentPools/write`, for example the built-in `Azure Kubernetes Service Contributor Role`, scoped to the cluster

## Usage

```text
aks-node-image-check [-s SUB] [-g RG -c CLUSTER] [-f table|json]
                     [--upgrade] [--dry-run] [--yes]
```

Without `-g`/`-c`, every cluster in the subscription is checked.

## Examples

```console
$ aks-node-image-check
2027-01-01T08:00:00Z [INFO ] aks-node-image-check: checking rg-aks-dev/aks-dev-weu
CLUSTER              POOL       MODE    K8S      CURRENT_IMAGE                              LATEST_IMAGE                               STATUS
aks-dev-weu          system     System  1.31.2   AKSUbuntu-2204gen2containerd-202610.01.0   AKSUbuntu-2204gen2containerd-202610.01.0   CURRENT
aks-dev-weu          user       User    1.31.2   AKSUbuntu-2204gen2containerd-202609.15.0   AKSUbuntu-2204gen2containerd-202610.01.0   OUTDATED
2027-01-01T08:00:00Z [INFO ] aks-node-image-check: 1 outdated node pool(s)
$ echo $?
1
```

```console
$ aks-node-image-check -g rg-aks-dev -c aks-dev-weu --dry-run
...
DRY-RUN: az aks nodepool upgrade --resource-group rg-aks-dev --cluster-name aks-dev-weu --name user --node-image-only --no-wait
```

## Safety notes

- Only `--node-image-only` upgrades are issued. The Kubernetes version never changes.
- Only pools marked `OUTDATED` are touched; a pool whose latest image cannot be determined is `UNKNOWN` and left alone.
- The upgrade cordons, drains and reimages nodes following the pool's surge settings. Check PodDisruptionBudgets and run it in a maintenance window for production pools.
- `--no-wait` returns once the operation is accepted; follow progress with `az aks nodepool show ... --query provisioningState`.

## Exit codes

`0` all pools current (or upgrades requested) · `1` at least one pool outdated · `2` an upgrade could not be started · `64` usage · `69` missing dependency · `77` confirmation declined.
