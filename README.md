# test_cluster_k8s_base

GitOps platform-services repository consumed by Argo CD (bootstrapped from [`test_cluster_infra`](https://github.com/nimeshamin/test_cluster_infra)).

The `apps/` directory holds Argo CD `Application` definitions for everything in the shared platform layer. Each environment directory (`environments/<target>/`) is a root Kustomize target that selects which of those apps deploy for that target.

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
| Namespaces | in-repo manifests (`apps/namespaces/`) | — | `observability`, `kubeflow`, `experiments`, `mlflow`. |

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
| `scripts/get-argocd-credentials.sh` | Print the initial Argo CD admin password. Only useful before the first password rotation — Argo CD deletes `argocd-initial-admin-secret` once you rotate. |
