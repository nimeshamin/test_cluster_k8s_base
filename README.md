# test_cluster_k8s_base

GitOps platform-services repository consumed by Argo CD (bootstrapped from [`test_cluster_infra`](https://github.com/nimeshamin/test_cluster_infra)).

The `apps/` directory holds Argo CD `Application` definitions for everything in the shared platform layer. Each environment directory (`environments/<target>/`) is a root Kustomize target that selects which of those apps deploy for that target.

> **`firecracker` branch.** A slim variant for Firecracker experiments on GCP. Every environment deploys only Istio + the observability stack; `environments/gcp` also deploys the Firecracker host below. MLflow, Kubeflow Pipelines, the Kubeflow CRDs, KubeRay and rl-bridge stay defined under `apps/` but are not referenced by any environment on this branch.

## Firecracker host (`firecracker` branch)

| App | Source | Version | Notes |
|---|---|---|---|
| firecracker | in-repo kustomize (`apps/firecracker/manifests/`) | Firecracker `v1.17.0`; guest kernel `vmlinux-6.1.186` + `ubuntu-24.04` rootfs from CI build `firecracker-ci/20260923-6f82ac4cf331-0` | `firecracker-host` DaemonSet in namespace `firecracker`, scheduled only on nodes labelled and tainted `firecracker=true` (the GKE nested-virtualization pool). Init containers first mount a reflink-capable XFS store at `/var/lib/firecracker` (`prepare-store.sh`: a sparse `FC_STORE_SIZE` file at `/var/lib/firecracker-store.xfs`, loop-mounted and propagated to the host so `fc-agent` sees it), then stage the binary (SHA256-verified), kernel (`kernels/`) and the read-only `ubuntu-24.04` base image (`images/ubuntu-24.04/rootfs.ext4`) on it. VM disks are reflink clones of base images. The readiness probe runs `check.sh`. Versions are pinned in `kustomization.yaml`. |

Once the pod is Ready:

```bash
scripts/firecracker-check.sh   # node has usable /dev/kvm, vmx flag, binary, kernel, rootfs
scripts/firecracker-smoke.sh   # boots a throwaway microVM and waits for the guest login prompt
```

A pod stuck in `ContainerCreating` with a `FailedMount` event for `/dev/kvm` means the node has no KVM device, i.e. nested virtualization is not enabled on its pool.

## Apps shipped here

| App | Chart / source | Version | Notes |
|---|---|---|---|
| Istio base CRDs | `base` (istio.io) | `1.29.2` | |
| Istiod control plane | `istiod` (istio.io) | `1.29.2` | |
| Prometheus | `prometheus` (prometheus-community) | `29.6.0` | Bundles kube-state-metrics + node-exporter, 20Gi persistent store, scrapes Istio control-plane and sidecar Envoy metrics. |
| Grafana | `grafana` (grafana) | `10.5.15` | Provisions recommended Kubernetes + Istio dashboards into `Kubernetes` and `Istio` folders, with `Prometheus` as the default datasource at `prometheus-server.observability.svc.cluster.local`. |
| Alloy | `alloy` (grafana) | `1.8.1` | |
| Tempo | `tempo` (grafana) | `1.24.4` | |
| Loki | `loki` (grafana) | `7.0.0` | |
| Pyroscope | `pyroscope` (grafana) | `2.0.1` | |
| MLflow | `mlflow` (community-charts) | `1.8.1` | File-backed sqlite at `/tmp/mlflow.db`; `MLFLOW_SERVER_ALLOWED_HOSTS=*`. |
| Kubeflow Pipelines | upstream `kubeflow/pipelines` kustomize (`manifests/kustomize/env/platform-agnostic`) | `2.16.1` | Patched via Argo CD `kustomize.patches`: (a) drop `--namespaced` from the workflow-controller so it reconciles Workflows in both `kubeflow` and `experiments` namespaces; (b) strip the default `artifactRepository` block so workflows don't need a per-namespace MinIO secret. |
| Kubeflow CRDs + workflow-controller RBAC | in-repo kustomize (`apps/kubeflow-crds/manifests/`) | — | Argo Workflows minimal CRDs (pinned to v3.7.3, the version KFP 2.16.1 bundles), KFP's own CRDs, plus the cluster-install workflow-controller ClusterRole/ClusterRoleBinding required when the controller runs cluster-wide. |
| KubeRay operator | `kuberay-operator` (ray-project) | `1.6.1` | Cluster-wide install (`singleNamespaceInstall: false`) so RayClusters can live in `experiments` and any future namespace. Ships the `RayCluster` / `RayJob` / `RayService` CRDs the PPO runtime depends on. |
| rl-bridge | in-repo manifests (`apps/rl-bridge/manifests/`) | — | Long-lived head-only `RayCluster` (`rl-head` in `experiments`) plus a `DaemonSet` that joins it from every `rl-worker=true` node as a Ray worker. Each DaemonSet pod will host the per-node policy cache + a UDS for UE worker pods to register their shmem IDs against (Phase B replaces the placeholder image with `bridge_daemon.py`). |
| Namespaces | in-repo manifests (`apps/namespaces/`) | — | `observability`, `kubeflow`, `experiments`, `mlflow`, `firecracker`. |

## Layout

- `apps/<service>/` — Argo CD `Application` definition (plus in-repo manifests/kustomize where applicable).
- `environments/<target>/kustomization.yaml` — root Kustomize target listing which `Application`s deploy to that environment.
- `scripts/` — helper scripts for cluster operators.

Environment roots reference shared app definitions outside their own directory, so Argo CD is configured by Pulumi with `--load-restrictor LoadRestrictionsNone` for this trusted repository.

## Helper scripts

| Script | Purpose |
|---|---|
| `scripts/get-trigger-token.sh` | Mint a short-lived bearer token for the `ppo-trigger` ServiceAccount (used by webhook callers of the PPO pipeline). Defaults to namespace `experiments`. Honors `KUBE_CONTEXT`, `NAMESPACE`, `SA`, `DURATION` env overrides. |
| `scripts/get-grafana-credentials.sh` | Print the chart-generated Grafana admin user + password. `eval`-friendly. |
| `scripts/firecracker-check.sh` | Show the Firecracker nodes and pods and run `check.sh` in each pod. Honors `KUBE_CONTEXT`, `NAMESPACE`. |
| `scripts/firecracker-smoke.sh` | Boot a throwaway microVM in each (or `POD`) firecracker-host pod and wait up to `TIMEOUT` seconds (default 60) for a login prompt. |
| `scripts/get-argocd-credentials.sh` | Print the initial Argo CD admin password. Only useful before the first password rotation — Argo CD deletes `argocd-initial-admin-secret` once you rotate. |
