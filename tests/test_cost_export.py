"""Render the cost export chart resources and evaluate GCP's values without cloud credentials.

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
                         "gs://test-artifacts/release/1.2.3/jars/cloud_gcp_lib_spark4_deploy.jar")
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


if __name__ == "__main__":
    unittest.main()
