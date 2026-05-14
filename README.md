# test_cluster_k8s_base

GitOps base-service repository consumed by Argo CD.

Current enabled base services:

- Istio base CRDs
- Istiod control plane
- Prometheus
- Grafana
- Alloy
- Tempo
- Loki
- Pyroscope

Prometheus installs kube-state-metrics and node-exporter, keeps a local 20Gi persistent store, and scrapes Istio control-plane and sidecar Envoy metrics. Grafana provisions the recommended Kubernetes and Istio dashboard sets into `Kubernetes` and `Istio` folders with `Prometheus` as the default datasource at `prometheus-server.observability.svc.cluster.local`.

The `apps/` directory owns the Argo CD app-of-apps chart definitions. Each environment directory is a root Kustomize target that selects those shared apps.

Environment roots reference shared app definitions outside their own directory, so Argo CD is configured by Pulumi with `--load-restrictor LoadRestrictionsNone` for this trusted repository.
