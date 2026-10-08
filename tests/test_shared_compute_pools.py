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
SHARED_POOLS = {"spark", "flink"}


def evaluate(teams=("default",), karpenter=None):
    if not TERRAFORM:
        raise RuntimeError("Install Terraform/OpenTofu or set TERRAFORM to its executable")
    with tempfile.TemporaryDirectory(prefix="shared-compute-pools-") as directory:
        fixture = Path(directory)
        shutil.copyfile(AWS / "node-pools.tf", fixture / "node-pools.tf")
        declarations = (AWS / "main.tf").read_text().split('resource "terraform_data"', 1)[0]
        # Evaluate the provider's actual compute values, stubbing only its
        # provisioned storage class so this fixture stays provider-free.
        provider_compute = (AWS / "locals.tf").read_text().split("  provider_values = {", 1)[1]
        provider_compute = provider_compute.split("    compute = {", 1)[1].split("\n    orchestration = {", 1)[0]
        provider_compute = provider_compute.replace('kubernetes_storage_class_v1.gp3.metadata[0].name', '"test-gp3"')
        module_compute_defaults = (ROOT / "modules/zipline-orchestration/main.tf").read_text()
        module_compute_defaults = module_compute_defaults.split("  compute_defaults = {", 1)[1].split("\n  compute ", 1)[0]
        (fixture / "main.tf").write_text(declarations + '''
locals {
  karpenter = merge({ enabled = true }, try(var.aws.karpenter, {}))
  provider_compute = {
''' + provider_compute + '''
  compute_defaults = {
''' + module_compute_defaults + '''
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
            input='jsonencode({ pools = local.karpenter_node_pools, compute = merge({ workloadPriorityClasses = local.compute_defaults.workload_priority_classes }, local.provider_compute) })\n',
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

    def test_rendered_pools_share_capacity_between_roles(self):
        pools = render_pools(evaluate()["pools"])
        self.assertEqual(set(pools), SHARED_POOLS | {"system"})
        for name in SHARED_POOLS:
            pool = pools[name]["spec"]
            template = pool["template"]
            self.assertEqual(template["metadata"]["labels"], {
                "zipline.ai/engine": name, "zipline.ai/workload": name,
            })
            self.assertEqual(template["spec"]["taints"], [{
                "key": "zipline.ai/workload", "operator": "Equal", "value": name, "effect": "NoSchedule",
            }])
            requirements = {r["key"]: r for r in template["spec"]["requirements"]}
            self.assertEqual(requirements["karpenter.sh/capacity-type"]["values"],
                             ["on-demand", "spot"] if name == "spark" else ["on-demand"])
            self.assertEqual(requirements["kubernetes.io/arch"]["values"], ["arm64"])
            self.assertEqual(requirements["karpenter.k8s.aws/instance-category"]["values"], ["c", "m", "r"])
            self.assertEqual(requirements["karpenter.k8s.aws/instance-generation"]["values"], ["6"])
            self.assertNotIn("karpenter.k8s.aws/instance-local-nvme", requirements)
            self.assertEqual(pool["limits"], {"cpu": "1100", "memory": "4400Gi"})
        self.assertEqual(pools["system"]["spec"]["template"]["metadata"]["labels"]["zipline.ai/node-pool"], "system")

    def test_image_prepull_requires_nvme_within_shared_spark_pool(self):
        values = evaluate(("analytics",))
        documents = render({"imagePrepull": {"enabled": True, **values["compute"]["imagePrepull"]}})
        prepull = next(doc for doc in documents if doc["kind"] == "DaemonSet" and doc["metadata"]["name"].endswith("-image-prepull"))
        spec = prepull["spec"]["template"]["spec"]
        self.assertEqual(spec["nodeSelector"], {"zipline.ai/engine": "spark"})
        self.assertIn({"key": "zipline.ai/workload", "operator": "Equal", "value": "spark",
                       "effect": "NoSchedule"}, spec["tolerations"])
        self.assertEqual(spec.get("affinity"), {"nodeAffinity": {
            "requiredDuringSchedulingIgnoredDuringExecution": {"nodeSelectorTerms": [{
                "matchExpressions": [{"key": "karpenter.k8s.aws/instance-local-nvme", "operator": "Exists"}],
            }]},
        }})

    def test_warm_pool_requires_on_demand_without_requiring_nvme(self):
        values = evaluate(("analytics",))
        documents = render(values["compute"])
        warm = next(doc for doc in documents if doc["kind"] == "Deployment"
                    and doc["metadata"]["name"].endswith("-warm-pool"))
        spec = warm["spec"]["template"]["spec"]
        self.assertEqual(spec["nodeSelector"], {
            "zipline.ai/engine": "spark", "karpenter.sh/capacity-type": "on-demand",
        })
        self.assertEqual(spec["tolerations"], values["pools"]["spark"]["taints"])
        self.assertNotIn("affinity", spec)
        self.assertEqual(spec["terminationGracePeriodSeconds"], 0)
        self.assertEqual(spec["containers"][0]["resources"], {
            "requests": {"cpu": "2", "memory": "4Gi"},
            "limits": {"cpu": "2", "memory": "4Gi"},
        })
        classes = {doc["metadata"]["name"]: doc for doc in documents if doc["kind"] == "PriorityClass"}
        pause = classes[spec["priorityClassName"]]
        self.assertEqual(pause["value"], -1)
        for name in ("zipline-backfill", "zipline-deploy"):
            self.assertGreater(classes[name]["value"], pause["value"])
            self.assertEqual(classes[name]["preemptionPolicy"], "PreemptLowerPriority")

    def test_shared_limits_and_explicit_instance_types(self):
        pools = evaluate(karpenter={
            "compute_limits": {"cpu": "200"}, "spark_limits": {"memory": "8000Gi"},
            "flink_limits": {"cpu": "300"},
            "compute_instance_types": ["m8g.xlarge", "r8gd.8xlarge"],
        })["pools"]
        for name in SHARED_POOLS:
            self.assertEqual(pools[name]["limits"], {"cpu": "200", "memory": "8000Gi"} if name == "spark"
                             else {"cpu": "300", "memory": "4400Gi"})
            requirements = {r["key"]: r for r in pools[name]["requirements"]}
            self.assertEqual(requirements["node.kubernetes.io/instance-type"]["values"],
                             ["m8g.xlarge", "r8gd.8xlarge"])
            self.assertNotIn("karpenter.k8s.aws/instance-category", requirements)
            self.assertNotIn("karpenter.k8s.aws/instance-generation", requirements)
            self.assertNotIn("karpenter.k8s.aws/instance-local-nvme", requirements)
            self.assertEqual(requirements["karpenter.sh/capacity-type"]["values"],
                             ["on-demand", "spot"] if name == "spark" else ["on-demand"])
            self.assertEqual(requirements["kubernetes.io/os"]["values"], ["linux"])
            self.assertEqual(requirements["kubernetes.io/arch"]["values"], ["arm64"])
        self.assertEqual(pools["system"]["limits"], {"cpu": "1000", "memory": "4000Gi"})

    def test_compute_hardware_overrides_apply_to_both_engines(self):
        pools = evaluate(karpenter={
            "compute_arch": ["amd64"], "compute_categories": ["m", "r"], "min_instance_generation": "7",
        })["pools"]
        for name in SHARED_POOLS:
            requirements = {r["key"]: r for r in pools[name]["requirements"]}
            self.assertEqual(requirements["kubernetes.io/arch"]["values"], ["amd64"])
            self.assertEqual(requirements["karpenter.k8s.aws/instance-category"]["values"], ["m", "r"])
            self.assertEqual(requirements["karpenter.k8s.aws/instance-generation"]["values"], ["7"])

    def test_advanced_overrides_replace_fields_and_disable_pools(self):
        requirements = [{"key": "node.kubernetes.io/instance-type", "operator": "In", "values": ["m8g.xlarge"]}]
        pools = render_pools(evaluate(karpenter={"node_pools": {
            "spark": {"limits": {"cpu": "20"}, "requirements": requirements},
            "flink": {"enabled": False},
        }})["pools"])
        self.assertEqual(set(pools), {"system", "spark"})
        self.assertEqual(pools["spark"]["spec"]["limits"], {"cpu": "20"})
        self.assertEqual(pools["spark"]["spec"]["template"]["spec"]["requirements"], requirements)
        self.assertEqual(pools["spark"]["spec"]["template"]["metadata"]["labels"]["zipline.ai/engine"], "spark")

    def test_disabled_karpenter_does_not_enable_auxiliary_placement(self):
        values = evaluate(karpenter={"enabled": False})
        self.assertEqual(values["pools"], {})
        self.assertEqual(values["compute"]["imagePrepull"], {"nodeSelector": {}, "tolerations": [], "affinity": {}})
        self.assertFalse(values["compute"]["warmPool"]["enabled"])


if __name__ == "__main__":
    unittest.main()
