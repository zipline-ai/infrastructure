data "google_project" "current" {
  project_id = local.cloud_args.project_id
}

locals {
  wi_pool = "${local.cloud_args.project_id}.svc.id.goog"

  # Keyed off the cluster resource, not the name variable, so the binding cannot
  # name a cluster this stack did not create.
  cluster_self_link = "https://container.googleapis.com/v1/projects/${local.cloud_args.project_id}/locations/${google_container_cluster.main.location}/clusters/${google_container_cluster.main.name}"

  # §7.2 bucket grant map:
  #   - orchestration/eval get objectAdmin on owned; objectViewer on shared +
  #     additional_data_buckets
  #   - spark gets objectAdmin on owned + additional_data_buckets; objectViewer
  #     on shared + spark-libs
  #   - flink gets objectAdmin on owned + additional_flink_buckets; objectViewer
  #     on spark-libs + additional_flink_readonly_buckets
  orchestration_rw_buckets = local.owned_buckets
  orchestration_ro_buckets = distinct(compact(concat(
    [local.cloud_args.shared_warehouse_bucket],
    local.cloud_args.additional_data_buckets,
  )))

  spark_rw_buckets = distinct(compact(concat(
    local.owned_buckets,
    local.cloud_args.additional_data_buckets,
  )))
  spark_ro_buckets = distinct(compact(concat(
    [local.cloud_args.shared_warehouse_bucket, local.spark_libs_bucket_name],
  )))

  flink_rw_buckets = distinct(compact(concat(
    local.owned_buckets,
    local.cloud_args.additional_flink_buckets,
  )))
  flink_ro_buckets = distinct(compact(concat(
    [local.spark_libs_bucket_name],
    local.cloud_args.additional_flink_readonly_buckets,
  )))

  eval_rw_buckets = local.owned_buckets
  eval_ro_buckets = distinct(compact(concat(
    [local.cloud_args.shared_warehouse_bucket],
    local.cloud_args.additional_data_buckets,
  )))

  polaris_rw_buckets = [local.cloud_args.warehouse_bucket]

  # Flatten (gsa, role, bucket) tuples so for_each can iterate them.
  bucket_bindings = concat(
    [for b in local.orchestration_rw_buckets : { key = "orch-rw-${b}", gsa = "orchestration", role = "roles/storage.objectAdmin", bucket = b }],
    [for b in local.orchestration_ro_buckets : { key = "orch-ro-${b}", gsa = "orchestration", role = "roles/storage.objectViewer", bucket = b }],
    [for b in local.spark_rw_buckets : { key = "spark-rw-${b}", gsa = "spark", role = "roles/storage.objectAdmin", bucket = b }],
    [for b in local.spark_ro_buckets : { key = "spark-ro-${b}", gsa = "spark", role = "roles/storage.objectViewer", bucket = b }],
    [for b in local.flink_rw_buckets : { key = "flink-rw-${b}", gsa = "flink", role = "roles/storage.objectAdmin", bucket = b }],
    [for b in local.flink_ro_buckets : { key = "flink-ro-${b}", gsa = "flink", role = "roles/storage.objectViewer", bucket = b }],
    [for b in local.eval_rw_buckets : { key = "eval-rw-${b}", gsa = "eval", role = "roles/storage.objectAdmin", bucket = b }],
    [for b in local.eval_ro_buckets : { key = "eval-ro-${b}", gsa = "eval", role = "roles/storage.objectViewer", bucket = b }],
    [for b in local.polaris_rw_buckets : { key = "polaris-rw-${b}", gsa = "polaris", role = "roles/storage.objectAdmin", bucket = b }],
  )
  bucket_bindings_map = { for b in local.bucket_bindings : b.key => b }

  gsa_emails = {
    orchestration    = google_service_account.orchestration.email
    spark            = google_service_account.spark.email
    flink            = google_service_account.flink.email
    eval             = google_service_account.eval.email
    polaris          = google_service_account.polaris_storage.email
    external_secrets = google_service_account.external_secrets.email
  }
}

# ---------------------------------------------------------------------------
# GSAs
# ---------------------------------------------------------------------------

resource "google_service_account" "orchestration" {
  account_id   = "${local.name_prefix}-orchestration"
  display_name = "Orchestration (hub, ui, eval, external-secrets reader)"
}

resource "google_service_account" "spark" {
  account_id   = "${local.name_prefix}-spark"
  display_name = "Spark compute execution"
}

resource "google_service_account" "flink" {
  account_id   = "${local.name_prefix}-flink"
  display_name = "Flink compute execution"
}

resource "google_service_account" "eval" {
  account_id   = "${local.name_prefix}-eval"
  display_name = "Eval service"
}

resource "google_service_account" "polaris_storage" {
  account_id   = "${local.name_prefix}-polaris"
  display_name = "Polaris GCS credential-vending identity"
}

resource "google_service_account" "external_secrets" {
  account_id   = "${local.name_prefix}-eso"
  display_name = "External Secrets Operator"
}

# ---------------------------------------------------------------------------
# Workload Identity bindings — KSA → GSA
# ---------------------------------------------------------------------------

resource "google_service_account_iam_member" "orchestration_wi" {
  service_account_id = google_service_account.orchestration.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${local.orchestration_namespace}/${local.orchestration_service_account}]"
}

# Spark/Flink KSAs live in per-team compute namespaces (orchestration.compute.
# namespaces), and the Hub creates a namespace per team on team sync — so the
# set is no longer known at apply time and a for_each over it cannot cover it.
#
# One cluster-scoped principalSet per GSA covers every namespace in the cluster
# instead. An earlier comment here held that the default WI pool rejects
# principalSet members; that is true of the *namespace*-scoped form, but the
# kubernetes.cluster form below is accepted — verified on crucible-gke, where a
# KSA in a namespace with no binding of its own minted a token for the bound
# GSA. This is the impersonation model (roles/iam.workloadIdentityUser), not
# direct resource access, so the Cloud Storage restrictions on that variant do
# not apply.
#
# The trade-off, taken deliberately: this covers every namespace in the cluster
# — kube-system included — not just the zipline- prefixed ones. The alternative,
# the Hub writing an IAM binding per namespace, needs read-modify-write with
# etag retries, tolerates propagation delay on a new namespace's first job, and
# breaks silently if this file ever moves to google_service_account_iam_binding.
resource "google_service_account_iam_member" "spark_wi" {
  service_account_id = google_service_account.spark.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.wi_pool}/kubernetes.cluster/${local.cluster_self_link}"
}

resource "google_service_account_iam_member" "flink_wi" {
  service_account_id = google_service_account.flink.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.wi_pool}/kubernetes.cluster/${local.cluster_self_link}"
}

resource "google_service_account_iam_member" "eval_wi" {
  service_account_id = google_service_account.eval.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${local.orchestration_namespace}/eval]"
}

# Polaris runs as the orchestration KSA and impersonates this GSA to mint
# downscoped GCS tokens. GCP parity with AWS's orchestration_polaris_storage_assume_role.
resource "google_service_account_iam_member" "orchestration_polaris_token_creator" {
  service_account_id = google_service_account.polaris_storage.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.orchestration.email}"
}

resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${local.orchestration_namespace}/external-secrets]"
}

# ---------------------------------------------------------------------------
# Project-level IAM
# ---------------------------------------------------------------------------

# Orchestration GSA roles (§7.1). Hub, UI and eval share this GSA, as they share
# the orchestration IRSA role on AWS. BigQuery is read-only, matching its Glue Get*.
resource "google_project_iam_member" "orchestration" {
  for_each = toset([
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/bigquery.readSessionUser",
    "roles/bigtable.user",
    "roles/cloudsql.client",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/logging.logWriter",
    "roles/logging.viewer",
  ])

  project = local.cloud_args.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.orchestration.email}"
}

# Spark GSA roles.
resource "google_project_iam_member" "spark" {
  for_each = toset([
    "roles/bigtable.user",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    # BigQuery Storage Read API (bigquery.readsessions.create) for BigQueryMetastoreCatalog reads.
    "roles/bigquery.readSessionUser",
    "roles/logging.logWriter",
  ])

  project = local.cloud_args.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.spark.email}"
}

# Flink GSA roles. Pub/Sub editor lets jobs consume, read topic schemas for
# pubsub_schema serde, and create their own subscriptions. Project-wide, like
# the AWS Flink role's Kinesis read.
resource "google_project_iam_member" "flink" {
  for_each = toset([
    "roles/bigtable.user",
    "roles/logging.logWriter",
    "roles/pubsub.editor",
  ])

  project = local.cloud_args.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.flink.email}"
}

# Eval GSA roles.
resource "google_project_iam_member" "eval" {
  for_each = toset([
    "roles/bigquery.jobUser",
    "roles/bigquery.dataViewer",
    "roles/bigquery.dataEditor",
    "roles/logging.logWriter",
  ])

  project = local.cloud_args.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.eval.email}"
}

# ---------------------------------------------------------------------------
# Bucket-level IAM
# ---------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "bucket_grants" {
  for_each = local.bucket_bindings_map

  bucket = each.value.bucket
  role   = each.value.role
  member = "serviceAccount:${local.gsa_emails[each.value.gsa]}"

  depends_on = [
    google_storage_bucket.warehouse,
    google_storage_bucket.artifact,
    google_storage_bucket.logs,
    google_storage_bucket.spark_libs,
  ]
}

# ---------------------------------------------------------------------------
# Human access (§7.5) — personnel_emails get roles/container.admin.
# Group-based: canary sets ["group:all@zipline.ai"]; customer stacks leave empty.
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "personnel" {
  for_each = toset(local.cloud_args.personnel_emails)

  project = local.cloud_args.project_id
  role    = "roles/container.admin"
  member  = each.value
}
