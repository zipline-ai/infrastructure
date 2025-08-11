# Zipline Orchestration Helm Chart

This Helm chart deploys the Zipline Orchestration Platform with Temporal workflow engine on Google Kubernetes Engine (GKE).

## Prerequisites

- GKE cluster with Autopilot enabled
- Static IP addresses created for ingresses
- Cloud SQL instances and databases configured
- Service accounts with appropriate IAM permissions
- Bigtable instance created

## Installation

1. **Create the static IP addresses first** (using Terraform or gcloud):
   ```bash
   gcloud compute addresses create orchestration-ui-ip --global
   gcloud compute addresses create temporal-ui-ip --global
   gcloud compute addresses create orchestration-hub-ip --global
   ```

2. **Get the IP addresses**:
   ```bash
   ORCHESTRATION_UI_IP=$(gcloud compute addresses describe orchestration-ui-ip --global --format="value(address)")
   TEMPORAL_UI_IP=$(gcloud compute addresses describe temporal-ui-ip --global --format="value(address)")
   ORCHESTRATION_HUB_IP=$(gcloud compute addresses describe orchestration-hub-ip --global --format="value(address)")
   ```

3. **Create a values file** with your configuration:
   ```yaml
   # values-production.yaml
   global:
     customer_name: "my-customer"
     region: "us-central1"
     project_id: "my-project-id"
     artifact_prefix: "my-artifacts"
     topic_id: "my-topic"
     
   database:
     temporal:
       host: "10.0.0.5"
       username: "temporal_user"
       password: "secure-password"
       database: "temporal"
     orchestration:
       host: "10.0.0.6"
       username: "orchestration_user"
       password: "secure-password"
       database: "orchestration"

   bigtable:
     instance_id: "zipline-bigtable"

   serviceAccount:
     temporal:
       googleServiceAccount: "temporal-sa@my-project.iam.gserviceaccount.com"
     orchestration:
       googleServiceAccount: "orchestration-sa@my-project.iam.gserviceaccount.com"

   staticIPs:
     orchestrationUI: "34.102.136.180"
     temporalUI: "34.102.136.181"
     orchestrationHub: "34.102.136.182"

   # Optional: Use custom domains instead of nip.io
   domains:
     ziplineUI: "ui.mydomain.com"
     temporal: "temporal.mydomain.com"
     hub: "hub.mydomain.com"
   ```

4. **Get cluster credentials for local kubectl/helm access**:
   ```bash
   # Replace with your actual cluster name, region, and project ID
   gcloud container clusters get-credentials <CLUSTER_NAME> --region <REGION> --project <PROJECT_ID>
   
   # Example:
   gcloud container clusters get-credentials my-customer-zipline-cluster --region us-central1 --project my-project-id
   ```

5. **Install the Helm chart**:
   ```bash
   helm install zipline-orchestration ./zipline-orchestration \
     -f values-production.yaml \
     --namespace zipline-system \
     --create-namespace
   ```

   > **Note**: The `--create-namespace` flag automatically creates the `zipline-system` namespace if it doesn't exist. Make sure you've configured kubectl to connect to the right cluster using the gcloud command above.

## Integration with Terraform

You can use this Helm chart in your Terraform configuration:

```hcl
# Create static IPs
resource "google_compute_global_address" "orchestration_ui_ip" {
  name = "orchestration-ui-ip"
}

resource "google_compute_global_address" "temporal_ui_ip" {
  name = "temporal-ui-ip"
}

resource "google_compute_global_address" "orchestration_hub_ip" {
  name = "orchestration-hub-ip"
}

# Deploy using Helm
resource "helm_release" "zipline_orchestration" {
  name       = "zipline-orchestration"
  chart      = "./zipline-orchestration"
  namespace  = "zipline-system"
  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values.yaml.tpl", {
      customer_name = var.customer_name
      region = var.region
      project_id = data.google_project.zipline.project_id
      artifact_prefix = var.artifact_prefix
      topic_id = var.topic_id
      
      temporal_db_host = google_sql_database_instance.temporal_instance.private_ip_address
      temporal_db_username = google_sql_user.temporal_user.name
      temporal_db_password = google_secret_manager_secret_version.db_password.secret_data
      temporal_db_database = google_sql_database.temporal_database.name
      
      orchestration_db_host = google_sql_database_instance.orchestration_instance.private_ip_address
      orchestration_db_username = google_sql_user.orchestration_user.name
      orchestration_db_password = google_secret_manager_secret_version.db_password.secret_data
      orchestration_db_database = google_sql_database.orchestration_database.name
      
      bigtable_instance_id = google_bigtable_instance.zipline_bigtable_instance.name
      
      temporal_service_account = google_service_account.temporal_gsa.email
      orchestration_service_account = google_service_account.orchestration_sa.email
      
      orchestration_ui_ip = google_compute_global_address.orchestration_ui_ip.address
      temporal_ui_ip = google_compute_global_address.temporal_ui_ip.address
      orchestration_hub_ip = google_compute_global_address.orchestration_hub_ip.address
      
      zipline_ui_domain = var.zipline_ui_domain
      temporal_domain = var.temporal_domain
      hub_domain = var.hub_domain
    })
  ]

  depends_on = [
    google_container_cluster.orchestration_cluster,
    null_resource.wait_for_cluster
  ]
}
```

## Upgrading

### Upgrading the Chart Version

To upgrade the chart itself:

```bash
helm upgrade zipline-orchestration ./zipline-orchestration \
  -f values-production.yaml \
  --namespace zipline-system
```

### Upgrading Container Images

1. Update your `modules.tf` with new image versions:
```yaml
zipline_version = "0.10.1"  # Update to desired version
```

2. Apply the upgrade:
```bash
terraform apply
```

### Checking Current Versions

To see current image versions:

```bash
# Check what's currently deployed
kubectl get deployments -n zipline-system -o wide

# Check Helm values
helm get values zipline-orchestration -n zipline-system
```

## Uninstalling

To uninstall the chart:

```bash
helm uninstall zipline-orchestration --namespace zipline-system
```

## Configuration

### Required Values

| Parameter | Description | Required |
|-----------|-------------|----------|
| `global.customer_name` | Customer identifier | Yes |
| `global.region` | GCP region | Yes |
| `global.project_id` | GCP project ID | Yes |
| `global.artifact_prefix` | GCS path prefix for artifacts | Yes |
| `global.topic_id` | Pub/Sub topic ID for orchestration | Yes |
| `global.version` | Zipline version to deploy | Yes |
| `database.temporal.host` | Temporal database host | Yes |
| `database.temporal.username` | Temporal database username | Yes |
| `database.temporal.password` | Temporal database password | Yes |
| `database.temporal.database` | Temporal database name | Yes |
| `database.orchestration.host` | Orchestration database host | Yes |
| `database.orchestration.username` | Orchestration database username | Yes |
| `database.orchestration.password` | Orchestration database password | Yes |
| `database.orchestration.database` | Orchestration database name | Yes |
| `bigtable.instance_id` | Bigtable instance ID | Yes |
| `serviceAccount.temporal.googleServiceAccount` | Google service account email for Temporal | Yes |
| `serviceAccount.orchestration.googleServiceAccount` | Google service account email for orchestration | Yes |
| `staticIPs.orchestrationUI` | Static IP for orchestration UI | Yes |
| `staticIPs.orchestrationUIName` | Name of the static IP for orchestration UI | Yes |
| `staticIPs.temporalUI` | Static IP for Temporal UI | Yes |
| `staticIPs.temporalUIName` | Name of the static IP for Temporal UI | Yes |
| `staticIPs.orchestrationHub` | Static IP for orchestration hub | Yes |
| `staticIPs.orchestrationHubName` | Name of the static IP for orchestration hub | Yes |

### Optional Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `domains.ziplineUI` | Custom domain for Zipline UI | `""` (uses nip.io) |
| `domains.temporal` | Custom domain for Temporal UI | `""` (uses nip.io) |
| `domains.hub` | Custom domain for Hub | `""` (uses nip.io) |

## SSL Certificates

The chart automatically creates Google-managed SSL certificates:

- For custom domains: Point your DNS A record to the static IP address
- For nip.io domains: Certificates are automatically provisioned

Certificate provisioning can take 15-60 minutes.

## Accessing Services

After deployment, services will be available at:

- **Zipline UI**: `https://{orchestration-ui-ip}.nip.io` or your custom domain
- **Temporal UI**: `https://{temporal-ui-ip}.nip.io` or your custom domain
- **Orchestration Hub**: `https://{orchestration-hub-ip}.nip.io` or your custom domain

## Troubleshooting

### Getting Cluster Access

If you need to access the cluster with `kubectl` or `helm` after Terraform deployment:

```bash
# Get cluster credentials (replace with your values)
gcloud container clusters get-credentials <CLUSTER_NAME> --region <REGION> --project <PROJECT_ID>

# Verify connection
kubectl get nodes
kubectl get namespaces

# Check current context
kubectl config current-context
```

### Common Issues

1. **Certificate not ready**: Wait 15-60 minutes for Google-managed certificates
2. **503 errors**: Check that all pods are running with `kubectl get pods -n zipline-system`
3. **Database connections**: Verify database credentials and network connectivity
4. **Service account permissions**: Ensure IAM roles are properly configured
5. **Helm release not found**: Make sure kubectl is connected to the right cluster using the gcloud credentials command above