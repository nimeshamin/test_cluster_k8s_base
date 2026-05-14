# test_cluster_k8s_base

GitOps base-service repository consumed by Argo CD.

Current enabled base services:

- Istio base CRDs
- Istiod control plane
- Grafana
- Alloy
- Tempo
- Loki
- Pyroscope

The `apps/` directory owns the Argo CD app-of-apps chart definitions. Each environment directory is a root Kustomize target that selects those shared apps.

Environment roots reference shared app definitions outside their own directory, so Argo CD is configured by Pulumi with `--load-restrictor LoadRestrictionsNone` for this trusted repository.
