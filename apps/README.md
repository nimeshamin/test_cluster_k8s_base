# Base service applications

This directory owns the Argo CD `Application` resources for cluster base services:

- Istio base CRDs
- Istiod
- Loki
- Tempo
- Pyroscope
- Alloy
- Grafana

Environment roots under `../environments/<target>/` select these shared app definitions.
