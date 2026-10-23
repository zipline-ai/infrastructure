locals {
  wi_pool = "${local.cloud_args.project_id}.svc.id.goog"

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
# namespaces). Bind each namespace's KSA explicitly rather than using a
# principalSet — the GKE default WI pool only accepts "principal" (single KSA)
# references, not namespace-wide "principalSet" wildcards. The plan's §7.1
# principalSet note targets attribute mappings that aren't configurable on the
# default pool; parity (new team namespace = tfvars edit, no new resource type)
# comes from this for_each.
resource "google_service_account_iam_member" "spark_wi" {
  for_each = { for ns in local.compute_namespaces : ns.name => ns }

  service_account_id = google_service_account.spark.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${each.value.name}/${local.spark_service_account}]"
}

resource "google_service_account_iam_member" "flink_wi" {
  for_each = { for ns in local.compute_namespaces : ns.name => ns }

  service_account_id = google_service_account.flink.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${each.value.name}/${local.flink_service_account}]"
}

resource "google_service_account_iam_member" "eval_wi" {
  service_account_id = google_service_account.eval.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${local.orchestration_namespace}/eval]"
}

resource "google_service_account_iam_member" "polaris_wi" {
  service_account_id = google_service_account.polaris_storage.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${local.orchestration_namespace}/polaris]"
}

resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.wi_pool}[${local.orchestration_namespace}/external-secrets]"
}

# ---------------------------------------------------------------------------
# Project-level IAM
# ---------------------------------------------------------------------------

# Orchestration GSA roles (§7.1).
resource "google_project_iam_member" "orchestration" {
  for_each = toset([
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
    "roles/logging.logWriter",
  ])

  project = local.cloud_args.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.spark.email}"
}

# Flink GSA roles. Pub/Sub publisher is additive on top of what the plan lists
# — most streaming sources live outside this stack, but the fetcher may publish
# into Pub/Sub when offloaded. If unused, no cost.
resource "google_project_iam_member" "flink" {
  for_each = toset([
    "roles/bigtable.user",
    "roles/logging.logWriter",
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
