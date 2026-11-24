"""Daily cost export: cloud billing export -> cloud-agnostic Iceberg table in Polaris.

Each cloud has a reader that returns the same intermediate columns (see INTERMEDIATE_COLUMNS).
normalize() then derives category, cost_kind and team the same way for every cloud, and the
result replaces the usage_date partitions it covers, so reruns and late billing rows never
double count.

Readers: GCP reads the BigQuery detailed usage cost export (GKE cost allocation splits node rows
by namespace). AWS reads CUR 2.0 Parquet with split cost allocation data, which adds per-pod rows
next to each EC2 node row; see read_aws for how that is folded into the same shape.
"""

import argparse
import datetime
import os
import re

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

INTERMEDIATE_COLUMNS = [
    "usage_date", "billing_account", "account", "cluster", "namespace",
    "service", "sku", "currency", "cost", "cost_after_credits", "source_refreshed_at",
    # Set when the reader knows the cost kind directly (AWS idle and node remainder rows);
    # otherwise normalize() derives it from cluster and namespace.
    "kind",
]

KV_STORE_SERVICES = ["Cloud Bigtable", "AmazonDynamoDB"]

# GKE cost allocation reports these as namespace values for capacity no pod requested.
IDLE_NAMESPACES = ["kube:unallocated"]
SYSTEM_OVERHEAD_NAMESPACES = ["kube:system-overhead"]
UNALLOCATED_NAMESPACES = ["goog-k8s-unsupported-sku", "goog-k8s-unknown"]

TEAM_NAMESPACE_PREFIX = "zipline-"
SHARED_ZIPLINE_NAMESPACES = ["zipline-system"]

GCP_EXPORT_TABLE_PREFIX = "gcp_billing_export_resource_v1_"
BIGQUERY_IDENTIFIER = re.compile(r"^[A-Za-z0-9_.:-]+$")
AWS_ACCOUNT_ID = re.compile(r"^[0-9]{12}$")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cloud", choices=["gcp", "aws"], required=True)
    gcp = parser.add_argument_group("gcp")
    gcp.add_argument("--billing-export-dataset", help="project.dataset holding the billing export")
    gcp.add_argument("--billing-export-table", default="", help="overrides table discovery in the dataset")
    gcp.add_argument("--projects", help="comma-separated projects whose costs to keep")
    gcp.add_argument("--job-project", help="project that runs and pays for BigQuery jobs")
    aws = parser.add_argument_group("aws")
    aws.add_argument("--cur-export-path", help="CUR 2.0 data prefix holding BILLING_PERIOD=YYYY-MM folders")
    aws.add_argument("--accounts", help="comma-separated account IDs whose costs to keep")
    parser.add_argument("--lookback-days", type=int, default=5)
    parser.add_argument("--output-table", default="zipline_catalog.cost.daily_cost")
    args = parser.parse_args()
    required = {"gcp": ["billing_export_dataset", "projects", "job_project"],
                "aws": ["cur_export_path", "accounts"]}[args.cloud]
    missing = [f"--{name.replace('_', '-')}" for name in required if not getattr(args, name)]
    if missing:
        parser.error(f"--cloud {args.cloud} requires {', '.join(missing)}")
    return args


def bigquery_identifier(value: str) -> str:
    if not BIGQUERY_IDENTIFIER.match(value):
        raise ValueError(f"unexpected characters in BigQuery identifier: {value!r}")
    return value


def bigquery_query(spark: SparkSession, job_project: str, sql: str) -> DataFrame:
    return (
        spark.read.format("bigquery")
        .option("parentProject", job_project)
        .option("viewsEnabled", "true")
        .option("query", sql)
        .load()
    )


def gcp_export_table(spark: SparkSession, args) -> str:
    dataset = bigquery_identifier(args.billing_export_dataset)
    if args.billing_export_table:
        return f"{dataset}.{bigquery_identifier(args.billing_export_table)}"
    tables = bigquery_query(
        spark, args.job_project,
        f"SELECT table_name FROM `{dataset}`.INFORMATION_SCHEMA.TABLES "
        f"WHERE STARTS_WITH(table_name, '{GCP_EXPORT_TABLE_PREFIX}') ORDER BY table_name",
    ).collect()
    if len(tables) != 1:
        found = [row.table_name for row in tables]
        raise RuntimeError(
            f"expected one {GCP_EXPORT_TABLE_PREFIX}* table in {dataset}, found {found}; "
            "turn on the detailed usage cost export or pass --billing-export-table")
    return f"{dataset}.{tables[0].table_name}"


def read_gcp(spark: SparkSession, args, start: datetime.date) -> DataFrame:
    table = gcp_export_table(spark, args)
    projects = ", ".join(f"'{bigquery_identifier(p.strip())}'" for p in args.projects.split(",") if p.strip())
    # The export is partitioned by load day, and a usage day only ever lands on or after itself,
    # so the partition filter prunes old data without dropping late rows.
    sql = f"""
        SELECT
          DATE(usage_start_time) AS usage_date,
          billing_account_id AS billing_account,
          project.id AS account,
          (SELECT value FROM UNNEST(labels) WHERE key = 'goog-k8s-cluster-name') AS cluster,
          COALESCE((SELECT value FROM UNNEST(labels) WHERE key = 'k8s-namespace'),
                   (SELECT value FROM UNNEST(labels) WHERE key = 'goog-k8s-namespace')) AS namespace,
          service.description AS service,
          sku.description AS sku,
          currency,
          SUM(cost) AS cost,
          SUM(cost + IFNULL((SELECT SUM(amount) FROM UNNEST(credits)), 0)) AS cost_after_credits,
          MAX(export_time) AS source_refreshed_at,
          CAST(NULL AS STRING) AS kind
        FROM `{table}`
        WHERE _PARTITIONTIME >= TIMESTAMP('{start.isoformat()}')
          AND DATE(usage_start_time) >= '{start.isoformat()}'
          AND project.id IN ({projects})
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
    """
    print(f"Reading {table} from {start} for projects {args.projects}")
    return bigquery_query(spark, args.job_project, sql)


def billing_periods(start: datetime.date, end: datetime.date) -> list:
    periods, month = [], start.replace(day=1)
    while month <= end:
        periods.append(month.strftime("%Y-%m"))
        month = (month + datetime.timedelta(days=32)).replace(day=1)
    return periods


def read_aws(spark: SparkSession, args, start: datetime.date) -> DataFrame:
    accounts = [a.strip() for a in args.accounts.split(",") if a.strip()]
    for account in accounts:
        if not AWS_ACCOUNT_ID.match(account):
            raise ValueError(f"not an AWS account ID: {account!r}")
    path = args.cur_export_path.rstrip("/")
    periods = billing_periods(start, datetime.date.today())
    print(f"Reading {path} billing periods {periods} from {start} for accounts {accounts}")
    try:
        cur = spark.read.parquet(path)
    except Exception as e:
        raise RuntimeError(
            f"no CUR 2.0 export at {path}; create a Data Export with split cost allocation data "
            "and point cost_tracking.cur_export_path at its data/ prefix") from e
    (cur.where(F.col("BILLING_PERIOD").isin(periods))
        .withColumn("refreshed", F.col("_metadata.file_modification_time"))
        .createOrReplaceTempView("cur"))
    account_list = ", ".join(f"'{a}'" for a in accounts)
    # Split cost allocation adds one row per pod (split_line_item_parent_resource_id = the EC2
    # node) next to the node's own EC2 row, and the pods' split + unused cost add up to most of the
    # node's cost. To count each dollar once: pod split cost is allocated, pod unused cost is idle,
    # the node's EC2 rows that day are dropped, and whatever the pods did not cover (node hours
    # without pods) becomes an unallocated remainder row.
    # Pod ARNs look like arn:aws:eks:<region>:<account>:pod/<cluster>/<namespace>/<pod>/<uid>.
    return spark.sql(f"""
        WITH base AS (
          SELECT
            CAST(line_item_usage_start_date AS DATE) AS usage_date,
            bill_payer_account_id AS billing_account,
            line_item_usage_account_id AS account,
            line_item_product_code AS service,
            line_item_usage_type AS sku,
            line_item_currency_code AS currency,
            line_item_resource_id AS resource_id,
            split_line_item_parent_resource_id AS node,
            line_item_unblended_cost AS cost,
            COALESCE(line_item_net_unblended_cost, line_item_unblended_cost) AS net_cost,
            split_line_item_split_cost AS split_cost,
            COALESCE(split_line_item_net_split_cost, split_line_item_split_cost) AS net_split_cost,
            split_line_item_unused_cost AS unused_cost,
            COALESCE(split_line_item_net_unused_cost, split_line_item_unused_cost) AS net_unused_cost,
            refreshed
          FROM cur
          WHERE CAST(line_item_usage_start_date AS DATE) >= DATE'{start.isoformat()}'
            AND line_item_usage_account_id IN ({account_list})
        ),
        pods AS (
          SELECT *, split(resource_id, '/')[1] AS cluster, split(resource_id, '/')[2] AS namespace
          FROM base WHERE node IS NOT NULL
        ),
        node_days AS (
          SELECT usage_date, account, node, max(cluster) AS cluster,
                 sum(split_cost + unused_cost) AS covered, sum(net_split_cost + net_unused_cost) AS net_covered
          FROM pods GROUP BY usage_date, account, node
        ),
        node_rows AS (
          SELECT b.*, n.cluster, n.covered, n.net_covered
          FROM base b JOIN node_days n
            ON b.usage_date = n.usage_date AND b.account = n.account AND b.resource_id = n.node
          WHERE b.node IS NULL AND b.service = 'AmazonEC2'
        ),
        rows AS (
          SELECT usage_date, billing_account, account, cluster, namespace, service, sku, currency,
                 split_cost AS cost, net_split_cost AS cost_after_credits, refreshed, 'allocated' AS kind
          FROM pods
          UNION ALL
          SELECT usage_date, billing_account, account, cluster, CAST(NULL AS STRING), service, sku, currency,
                 unused_cost, net_unused_cost, refreshed, 'idle'
          FROM pods
          UNION ALL
          SELECT usage_date, max(billing_account), account, max(cluster), CAST(NULL AS STRING), 'AmazonEC2',
                 max(sku), max(currency), sum(cost) - max(covered), sum(net_cost) - max(net_covered),
                 max(refreshed), 'unallocated'
          FROM node_rows GROUP BY usage_date, account, resource_id
          UNION ALL
          SELECT b.usage_date, b.billing_account, b.account,
                 CASE WHEN b.resource_id LIKE 'arn:aws:eks:%:cluster/%' THEN split(b.resource_id, '/')[1] END,
                 CAST(NULL AS STRING), b.service, b.sku, b.currency, b.cost, b.net_cost, b.refreshed,
                 CAST(NULL AS STRING)
          FROM base b LEFT ANTI JOIN node_rows n
            ON b.usage_date = n.usage_date AND b.account = n.account AND b.resource_id = n.resource_id
          WHERE b.node IS NULL
        )
        SELECT usage_date, billing_account, account, cluster, namespace, service, sku, currency,
               sum(cost) AS cost, sum(cost_after_credits) AS cost_after_credits,
               max(refreshed) AS source_refreshed_at, kind
        FROM rows
        GROUP BY usage_date, billing_account, account, cluster, namespace, service, sku, currency, kind
    """)


def normalize(df: DataFrame, cloud: str) -> DataFrame:
    ns = F.col("namespace")
    is_k8s = F.col("cluster").isNotNull()
    is_team_ns = ns.startswith(TEAM_NAMESPACE_PREFIX) & ~ns.isin(SHARED_ZIPLINE_NAMESPACES)

    category = (
        F.when(is_k8s, "k8s_compute")
        .when(F.col("service").isin(KV_STORE_SERVICES), "kv_store")
        .otherwise("other")
    )
    cost_kind = (
        F.when(F.col("kind").isNotNull(), F.col("kind"))
        .when(~is_k8s, "direct")
        .when(ns.isin(IDLE_NAMESPACES), "idle")
        .when(ns.isin(SYSTEM_OVERHEAD_NAMESPACES), "system_overhead")
        .when(ns.isNull() | ns.isin(UNALLOCATED_NAMESPACES), "unallocated")
        .otherwise("allocated")
    )
    team = (
        F.when(is_k8s & is_team_ns, F.expr(f"substr(namespace, {len(TEAM_NAMESPACE_PREFIX) + 1})"))
        .otherwise(F.lit("shared"))
    )
    return df.select(
        F.col("usage_date").cast("date"),
        F.lit(cloud).alias("cloud"),
        "billing_account", "account", "cluster", "namespace",
        team.alias("team"), category.alias("category"), cost_kind.alias("cost_kind"),
        "service", "sku", "currency",
        F.col("cost").cast("double"),
        F.col("cost_after_credits").cast("double"),
        F.col("source_refreshed_at").cast("timestamp"),
    )


def write(spark: SparkSession, df: DataFrame, output_table: str):
    catalog, namespace, _ = output_table.split(".")
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {catalog}.{namespace}")
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS {output_table} (
          usage_date DATE, cloud STRING, billing_account STRING, account STRING,
          cluster STRING, namespace STRING, team STRING, category STRING, cost_kind STRING,
          service STRING, sku STRING, currency STRING,
          cost DOUBLE, cost_after_credits DOUBLE, source_refreshed_at TIMESTAMP)
        USING iceberg
        PARTITIONED BY (usage_date)
    """)
    df.writeTo(output_table).overwritePartitions()


def main():
    args = parse_args()
    # Local mode: the job handles one or two months of billing rows, which fit in the driver, and
    # no executor needs the Iceberg jar that only the driver's init container downloads.
    builder = SparkSession.builder.master("local[2]").appName("cost-export")
    # The init container copies the Polaris credential to a file so it never appears in the
    # SparkApplication spec.
    credential_file = os.environ.get("POLARIS_CREDENTIAL_FILE", "")
    if credential_file:
        with open(credential_file) as handle:
            catalog = args.output_table.split(".")[0]
            builder = builder.config(f"spark.sql.catalog.{catalog}.credential", handle.read().strip())
    spark = builder.getOrCreate()
    start = datetime.date.today() - datetime.timedelta(days=args.lookback_days)
    readers = {"gcp": read_gcp, "aws": read_aws}
    raw = readers[args.cloud](spark, args, start).select(*INTERMEDIATE_COLUMNS)
    out = normalize(raw, args.cloud).cache()
    summary = out.agg(F.count("*").alias("rows"), F.round(F.sum("cost"), 2).alias("cost")).collect()[0]
    print(f"Writing {summary.rows} rows, cost {summary.cost}, usage_date >= {start} to {args.output_table}")
    write(spark, out, args.output_table)
    spark.stop()


if __name__ == "__main__":
    main()
