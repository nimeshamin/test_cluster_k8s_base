# AGENTS.md

## Repository Scope

This repository is for common Kubernetes platform services shared by clusters and environments.

## What Belongs Here

- Istio base and control plane configuration.
- Observability services such as Grafana, Prometheus, Alloy, Tempo, Loki, and Pyroscope.
- Common namespaces, service accounts, dashboards, datasources, and platform-level Kubernetes resources.
- Environment overlays for local, GCP, and AWS when they affect common platform services.

## What Does Not Belong Here

- Application-layer services.
- Product workloads.
- One-off app dependencies that are not common platform services.
- Pulumi infrastructure code.
- Argo CD installation code.

## Expected Use

Keep this repository focused on reusable base services that should be available before application workloads are deployed. Prefer Argo CD Applications, Kustomize overlays, and Helm values that can be shared across environments with minimal drift.

## Validation

Before handing off changes, render the affected overlays and validate YAML:

```bash
kubectl kustomize --load-restrictor LoadRestrictionsNone environments/local
kubectl kustomize --load-restrictor LoadRestrictionsNone environments/gcp
kubectl kustomize --load-restrictor LoadRestrictionsNone environments/aws
```
