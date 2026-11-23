"""Render the cost export chart resources and evaluate GCP and AWS values without cloud credentials.

Requires Helm, PyYAML and Terraform/OpenTofu (or TERRAFORM pointing to its executable).
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "charts/zipline-orchestration"
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("tofu") or shutil.which("terraform")


def render(cost_export):
    values = {
        "global": {"customer_name": "test", "artifact_prefix": "gs://test-artifacts", "version": "1.2.3"},
        "database": {"host": "postgres"},
        "compute": {"objectStore": {"bucket": "test"}},
        "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "GCS"}}}}},
        "orchestration": {"hub": {"image": "hub", "verticleClass": "test"}, "eval": {"image": "eval"}},
        "costExport": cost_export,
    }
    result = subprocess.run(
        ["helm", "template", "test", str(CHART), "-n", "zipline-system", "-f", "-"],
        input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
    )
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def find(docs, kind, name):
    return next(d for d in docs if d["kind"] == kind and d["metadata"]["name"] == name)


ENABLED = {
    "enabled": True,
    "cloud": "gcp",
    "gcp": {"billingExportDataset": "billing-proj.billing_export", "projects": ["a", "b"], "jobProject": "a"},
}


class CostExportChartTest(unittest.TestCase):
    def test_disabled_by_default(self):
        docs = render({})
        self.assertFalse(any(d["kind"] == "ScheduledSparkApplication" for d in docs))

    def test_enabled(self):
        docs = render(ENABLED)
        job = find(docs, "ScheduledSparkApplication", "cost-export")
        self.assertEqual(job["metadata"]["namespace"], "zipline-default")
        self.assertEqual(job["spec"]["schedule"], "0 6 * * *")
        self.assertEqual(job["spec"]["concurrencyPolicy"], "Forbid")
        app = job["spec"]["template"]
        args = app["arguments"]
        self.assertEqual(args[args.index("--billing-export-dataset") + 1], "billing-proj.billing_export")
        self.assertEqual(args[args.index("--projects") + 1], "a,b")
        self.assertEqual(args[args.index("--lookback-days") + 1], "5")
        conf = app["sparkConf"]
        self.assertEqual(conf["spark.sql.catalog.zipline_catalog.warehouse"], "polaris_test")
        self.assertEqual(conf["spark.sql.catalog.zipline_catalog.uri"],
                         "http://polaris-service.zipline-system.svc.cluster.local:8181/api/catalog")
        self.assertFalse(any(key.endswith(".credential") for key in conf))
        init_env = {e["name"]: e["value"] for e in app["driver"]["initContainers"][0]["env"]}
        self.assertEqual(init_env["ENGINE_JAR"],
                         "gs://test-artifacts/release/latest/jars/cloud_gcp_lib_spark4_deploy.jar")
        self.assertEqual(init_env["POLARIS_SECRET_NAMESPACE"], "zipline-system")

        role = find(docs, "Role", "cost-export-polaris-credential")
        self.assertEqual(role["metadata"]["namespace"], "zipline-system")
        self.assertEqual(role["rules"], [{"apiGroups": [""], "resources": ["secrets"],
                                          "resourceNames": ["polaris-client-credentials"], "verbs": ["get"]}])
        binding = find(docs, "RoleBinding", "cost-export-polaris-credential")
        self.assertEqual(binding["subjects"], [{"kind": "ServiceAccount", "name": "spark-operator-spark",
                                                "namespace": "zipline-default"}])
        script = find(docs, "ConfigMap", "cost-export")
        self.assertEqual(script["metadata"]["namespace"], "zipline-default")
        self.assertEqual(set(script["data"]), {"cost-export.py", "cost-export-init.py"})

    def test_aws(self):
        docs = render({"enabled": True, "cloud": "aws",
                       "aws": {"curExportPath": "s3://payer-cur/cur2/export/data", "accounts": ["111111111111"]}})
        app = find(docs, "ScheduledSparkApplication", "cost-export")["spec"]["template"]
        args = app["arguments"]
        self.assertEqual(args[args.index("--cloud") + 1], "aws")
        self.assertEqual(args[args.index("--cur-export-path") + 1], "s3://payer-cur/cur2/export/data")
        self.assertEqual(args[args.index("--accounts") + 1], "111111111111")
        self.assertNotIn("--billing-export-dataset", args)
        conf = app["sparkConf"]
        self.assertEqual(conf["spark.hadoop.fs.s3.impl"], "org.apache.hadoop.fs.s3a.S3AFileSystem")
        self.assertEqual(conf["spark.sql.sources.partitionColumnTypeInference.enabled"], "false")
        init_env = {e["name"]: e["value"] for e in app["driver"]["initContainers"][0]["env"]}
        self.assertEqual(init_env["ENGINE_JAR"],
                         "gs://test-artifacts/release/latest/jars/cloud_aws_lib_spark4_deploy.jar")

    def test_engine_version_override(self):
        app = find(render({**ENABLED, "engineVersion": "1.30.1"}), "ScheduledSparkApplication",
                   "cost-export")["spec"]["template"]
        init_env = {e["name"]: e["value"] for e in app["driver"]["initContainers"][0]["env"]}
        self.assertEqual(init_env["ENGINE_JAR"],
                         "gs://test-artifacts/release/1.30.1/jars/cloud_gcp_lib_spark4_deploy.jar")

    def test_gcp_has_no_s3_settings(self):
        conf = find(render(ENABLED), "ScheduledSparkApplication", "cost-export")["spec"]["template"]["sparkConf"]
        self.assertFalse(any("s3" in key for key in conf))

    def test_requires_aws_settings(self):
        with self.assertRaises(subprocess.CalledProcessError) as error:
            render({"enabled": True, "cloud": "aws", "aws": {"curExportPath": "", "accounts": ["1"]}})
        self.assertIn("costExport.aws.curExportPath is required", error.exception.stderr)

    def test_rejects_unknown_cloud(self):
        with self.assertRaises(subprocess.CalledProcessError) as error:
            render({**ENABLED, "cloud": "azure"})
        self.assertIn("costExport.cloud must be gcp or aws", error.exception.stderr)

    def test_requires_gcp_settings(self):
        with self.assertRaises(subprocess.CalledProcessError) as error:
            render({**ENABLED, "gcp": {"billingExportDataset": "", "projects": ["a"], "jobProject": "a"}})
        self.assertIn("costExport.gcp.billingExportDataset is required", error.exception.stderr)


class GcpCostExportValuesTest(unittest.TestCase):
    def evaluate(self, cost_tracking):
        self.assertTrue(TERRAFORM, "Install Terraform/OpenTofu or set TERRAFORM")
        source = (ROOT / "gcp/zipline-orchestration/locals.tf").read_text()
        cost_locals = source.split("  cost_tracking         =", 1)[1].split("\n\n", 1)[0]
        cost_values = source.split("    costExport = {", 1)[1].split("\n    nodepoolExporter = {", 1)[0]
        with tempfile.TemporaryDirectory(prefix="gcp-cost-export-") as directory:
            fixture = Path(directory)
            # Evaluate production HCL with stand-ins for the wrapper's inputs.
            (fixture / "main.tf").write_text(f'''
variable "orchestration" {{
  type = any
}}
locals {{
  cloud_args = {{ project_id = "cluster-proj" }}
  cost_tracking         ={cost_locals}
  values = {{
    costExport = {{{cost_values}
  }}
}}
''')
            (fixture / "terraform.tfvars.json").write_text(json.dumps(
                {"orchestration": {"cost_tracking": cost_tracking}}))
            result = subprocess.run(
                [TERRAFORM, "console", "-no-color"], cwd=fixture,
                input="jsonencode(local.values.costExport)\n",
                text=True, capture_output=True, check=True,
            )
        return json.loads(json.loads(result.stdout))

    def test_defaults(self):
        values = self.evaluate({"enabled": True})
        self.assertTrue(values["enabled"])
        self.assertEqual(values["gcp"]["billingExportDataset"], "cluster-proj.billing_export")
        self.assertEqual(values["gcp"]["projects"], ["cluster-proj"])
        self.assertEqual(values["gcp"]["jobProject"], "cluster-proj")
        self.assertEqual(values["namespace"], "zipline-default")
        self.assertIn({"key": "kubernetes.io/arch", "operator": "Exists", "effect": "NoSchedule"},
                      values["tolerations"])

    def test_overrides(self):
        values = self.evaluate({"enabled": True, "billing_export_dataset": "billing-proj.cost",
                                "projects": ["p1", "p2"], "lookback_days": 3})
        self.assertEqual(values["gcp"]["billingExportDataset"], "billing-proj.cost")
        self.assertEqual(values["gcp"]["projects"], ["p1", "p2"])
        self.assertEqual(values["lookbackDays"], 3)

    def test_enabled_by_default(self):
        self.assertTrue(self.evaluate({})["enabled"])

    def test_opt_out(self):
        self.assertFalse(self.evaluate({"enabled": False})["enabled"])


class AwsCostExportValuesTest(unittest.TestCase):
    def evaluate(self, cost_tracking, expression="local.values.costExport"):
        self.assertTrue(TERRAFORM, "Install Terraform/OpenTofu or set TERRAFORM")
        source = (ROOT / "aws/zipline-orchestration/locals.tf").read_text()
        cost_locals = source.split("  cost_tracking        =", 1)[1].split("\n\n", 1)[0]
        cost_values = source.split("    costExport = {", 1)[1].split("\n    }\n", 1)[0] + "\n    }"
        # terraform console cannot read data sources without a provider; stand in for the account.
        cost_values = cost_values.replace("data.aws_caller_identity.current.account_id", "local.account_id")
        with tempfile.TemporaryDirectory(prefix="aws-cost-export-") as directory:
            fixture = Path(directory)
            (fixture / "main.tf").write_text(f'''
variable "orchestration" {{
  type = any
}}
locals {{
  account_id = "222222222222"
  cost_tracking        ={cost_locals}
  values = {{
    costExport = {{{cost_values}
  }}
}}
''')
            (fixture / "terraform.tfvars.json").write_text(json.dumps(
                {"orchestration": {"cost_tracking": cost_tracking}}))
            result = subprocess.run(
                [TERRAFORM, "console", "-no-color"], cwd=fixture,
                input=f"jsonencode({expression})\n",
                text=True, capture_output=True, check=True,
            )
        return json.loads(json.loads(result.stdout))

    def test_disabled_without_cur_path(self):
        self.assertFalse(self.evaluate({})["enabled"])

    def test_enabled_by_cur_path(self):
        values = self.evaluate({"cur_export_path": "s3://payer-cur/cur2/export/data/"})
        self.assertTrue(values["enabled"])
        self.assertEqual(values["cloud"], "aws")
        self.assertEqual(values["aws"]["curExportPath"], "s3://payer-cur/cur2/export/data")
        self.assertEqual(values["aws"]["accounts"], ["222222222222"])
        self.assertEqual(values["namespace"], "zipline-default")

    def test_opt_out_and_overrides(self):
        self.assertFalse(self.evaluate({"enabled": False, "cur_export_path": "s3://b/p"})["enabled"])
        values = self.evaluate({"cur_export_path": "s3://b/p", "accounts": ["333333333333"], "lookback_days": 2})
        self.assertEqual(values["aws"]["accounts"], ["333333333333"])
        self.assertEqual(values["lookbackDays"], 2)

    def test_bucket_and_prefix_for_iam(self):
        tracking = {"cur_export_path": "s3://payer-cur/cur2/export/data/"}
        self.assertEqual(self.evaluate(tracking, "local.cost_cur_bucket"), "payer-cur")
        self.assertEqual(self.evaluate(tracking, "local.cost_cur_prefix"), "cur2/export/data")


if __name__ == "__main__":
    unittest.main()
