"""Evaluate the AWS placement locals and render their Kubernetes manifests.

Requires helm and Terraform or OpenTofu (override the binary with TERRAFORM).
The fixture copies production HCL; it needs no providers or cloud credentials.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

from test_compute_quotas import render


ROOT = Path(__file__).resolve().parents[1]
AWS = ROOT / "aws/zipline-orchestration"
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("tofu") or shutil.which("terraform")
SHARED_POOLS = {"spark-driver", "spark-executor", "flink-jobmanager", "flink-taskmanager"}


def evaluate(teams=("default",), karpenter=None):
    if not TERRAFORM:
        raise RuntimeError("Install Terraform/OpenTofu or set TERRAFORM to its executable")
    with tempfile.TemporaryDirectory(prefix="shared-compute-pools-") as directory:
        fixture = Path(directory)
        shutil.copyfile(AWS / "node-pools.tf", fixture / "node-pools.tf")
        declarations = (AWS / "main.tf").read_text().split('resource "terraform_data"', 1)[0]
        (fixture / "main.tf").write_text(declarations + '''
locals {
  karpenter = merge({ enabled = true }, try(var.aws.karpenter, {}))
}
''')
        (fixture / "terraform.tfvars.json").write_text(json.dumps({
            "aws": {"warehouse_bucket": "test", "region": "us-west-2", "karpenter": karpenter or {}},
            "orchestration": {"compute": {"namespaces": [
                {"name": f"zipline-{team}", "team": team} for team in teams
            ]}},
        }))
        result = subprocess.run(
            [TERRAFORM, "console", "-no-color"], cwd=fixture,
            input='jsonencode({ pools = local.karpenter_node_pools, imagePrepull = { nodeSelector = local.image_prepull_node_selector, tolerations = local.image_prepull_node_tolerations }, warmPool = local.compute_warm_pool })\n',
            text=True, capture_output=True, check=True,
        )
        if "Error:" in result.stderr:
            raise subprocess.CalledProcessError(1, result.args, result.stdout, result.stderr)
        return json.loads(json.loads(result.stdout))


def render_pools(pools):
    result = subprocess.run(
        ["helm", "template", "test", str(AWS / "charts/karpenter-nodepools"), "-f", "-"],
        input=yaml.safe_dump({"ec2NodeClass": {"name": "test"}, "nodePools": pools}),
        text=True, capture_output=True, check=True,
    )
    return {doc["metadata"]["name"]: doc for doc in yaml.safe_load_all(result.stdout)
            if doc and doc["kind"] == "NodePool"}


class SharedComputePoolTest(unittest.TestCase):
    def test_adding_teams_does_not_change_pools(self):
        single = evaluate()
        multiple = evaluate(("default", "analytics", "data-science"))
        self.assertEqual(single, multiple)
        self.assertEqual(set(single["pools"]), SHARED_POOLS | {"system"})
        self.assertEqual(evaluate(("analytics",))["pools"], single["pools"])

    def test_rendered_pools_keep_role_hardware_and_shared_placement(self):
        pools = render_pools(evaluate()["pools"])
        self.assertEqual(set(pools), SHARED_POOLS | {"system"})
        for name in SHARED_POOLS:
            engine, role = name.split("-", 1)
            pool = pools[name]["spec"]
            template = pool["template"]
            self.assertEqual(template["metadata"]["labels"], {
                "zipline.ai/engine": engine, "zipline.ai/role": role, "zipline.ai/workload": name,
            })
            self.assertEqual(template["spec"]["taints"], [{
                "key": "zipline.ai/workload", "operator": "Equal", "value": name, "effect": "NoSchedule",
            }])
            requirements = {r["key"]: r for r in template["spec"]["requirements"]}
            driver = role in ("driver", "jobmanager")
            self.assertEqual(requirements["karpenter.sh/capacity-type"]["values"],
                             ["on-demand"] if driver else ["spot"])
            self.assertEqual(requirements["kubernetes.io/arch"]["values"], ["arm64"])
            self.assertEqual("karpenter.k8s.aws/instance-local-nvme" in requirements, name == "spark-executor")
            self.assertEqual(pool["limits"], {"cpu": "100", "memory": "400Gi"} if driver
                             else {"cpu": "1000", "memory": "4000Gi"})
        self.assertEqual(pools["system"]["spec"]["template"]["metadata"]["labels"]["zipline.ai/node-pool"], "system")

    def test_image_prepull_uses_shared_spark_executors(self):
        values = evaluate(("analytics",))
        documents = render({"imagePrepull": {"enabled": True, **values["imagePrepull"]}})
        prepull = next(doc for doc in documents if doc["kind"] == "DaemonSet" and doc["metadata"]["name"].endswith("-image-prepull"))
        spec = prepull["spec"]["template"]["spec"]
        self.assertEqual(spec["nodeSelector"], {
            "zipline.ai/engine": "spark", "zipline.ai/role": "executor",
        })
        self.assertIn({"key": "zipline.ai/workload", "operator": "Equal", "value": "spark-executor",
                       "effect": "NoSchedule"}, spec["tolerations"])

    def test_warm_pool_uses_shared_spark_drivers(self):
        values = evaluate(("analytics",))
        documents = render({"warmPool": values["warmPool"]})
        warm = next(doc for doc in documents if doc["kind"] == "Deployment"
                    and doc["metadata"]["name"].endswith("-warm-pool"))
        spec = warm["spec"]["template"]["spec"]
        driver = values["pools"]["spark-driver"]
        self.assertEqual(spec["nodeSelector"], driver["labels"])
        self.assertEqual(spec["tolerations"], driver["taints"])

    def test_shared_limits_and_explicit_instance_types(self):
        pools = evaluate(karpenter={
            "driver_limits": {"cpu": "200"}, "executor_limits": {"memory": "8000Gi"},
            "driver_instance_types": ["m8g.xlarge"], "executor_instance_types": ["r8gd.8xlarge"],
        })["pools"]
        for name in SHARED_POOLS:
            driver = name in ("spark-driver", "flink-jobmanager")
            self.assertEqual(pools[name]["limits"], {"cpu": "200", "memory": "400Gi"} if driver
                             else {"cpu": "1000", "memory": "8000Gi"})
            requirements = {r["key"]: r for r in pools[name]["requirements"]}
            self.assertEqual(requirements["node.kubernetes.io/instance-type"]["values"],
                             ["m8g.xlarge"] if driver else ["r8gd.8xlarge"])
            self.assertNotIn("karpenter.k8s.aws/instance-category", requirements)
            self.assertNotIn("karpenter.k8s.aws/instance-generation", requirements)
            self.assertEqual("karpenter.k8s.aws/instance-local-nvme" in requirements, name == "spark-executor")

    def test_disabled_karpenter_does_not_enable_auxiliary_placement(self):
        values = evaluate(karpenter={"enabled": False})
        self.assertEqual(values["pools"], {})
        self.assertEqual(values["imagePrepull"], {"nodeSelector": {}, "tolerations": []})
        self.assertFalse(values["warmPool"]["enabled"])


if __name__ == "__main__":
    unittest.main()
