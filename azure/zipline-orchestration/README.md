# Azure Zipline Orchestration

Installs the shared `charts/zipline-orchestration` chart on AKS and wires Azure
infrastructure into cloud-neutral chart values.

Azure-specific work stays at this layer:

- Azure workload identity annotations and pod labels.
- Azure Key Vault objects projected through the generic chart `secrets` values.
- Static IP and resource-group settings for ingress-nginx controller Services.
- ABFS event log, warehouse, and Flink state paths supplied as runtime values.

Networking intentionally matches AWS at the chart boundary: cloud load balancers
pass traffic to ingress-nginx, and Kubernetes Ingress TLS secrets own TLS
termination. Azure Application Gateway or Front Door can still be layered in
front later without changing the Zipline chart.
