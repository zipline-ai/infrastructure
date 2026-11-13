"""Evaluate Ray GPU execution profiles and render their Karpenter NodePools.

Checks the placement contract in platform contracts/training-v1 ("Profile
placement interface"): every pod selects zipline.ai/engine=ray,
zipline.ai/execution-profile=<profile>, kubernetes.io/arch=amd64; head and
submitter select role=control, workers role=worker; pods tolerate
zipline.ai/workload=ray-<profile>:NoSchedule.

Requires helm and Terraform or OpenTofu (override the binary with TERRAFORM).
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
AWS = ROOT / "aws/zipline-orchestration"
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("tofu") or shutil.which("terraform")


def evaluate(karpenter):
    if not TERRAFORM:
        raise RuntimeError("Install Terraform/OpenTofu or set TERRAFORM to its executable")
    with tempfile.TemporaryDirectory(prefix="ray-gpu-profiles-") as directory:
        fixture = Path(directory)
        shutil.copyfile(AWS / "node-pools.tf", fixture / "node-pools.tf")
        (fixture / "main.tf").write_text('''
variable "aws" { type = any }
locals { karpenter = merge({ enabled = true, release_name = "karpenter" }, try(var.aws.karpenter, {})) }
''')
        (fixture / "terraform.tfvars.json").write_text(json.dumps({"aws": {"karpenter": karpenter}}))
        result = subprocess.run(
            [TERRAFORM, "console", "-no-color"], cwd=fixture,
            input="jsonencode({ pools = local.ray_gpu_profile_pools, errors = local.ray_gpu_profile_errors, "
                  "quotas = local.ray_gpu_namespace_quotas, default_pools = keys(local.karpenter_node_pools) })\n",
            text=True, capture_output=True, check=True,
        )
        if "Error:" in result.stderr:
            raise subprocess.CalledProcessError(1, result.args, result.stdout, result.stderr)
        return json.loads(json.loads(result.stdout))


def render(profile_pools):
    pools = {**profile_pools["worker"], "nodeClassRef": {"name": "zipline"}}
    control = {**profile_pools["control"], "nodeClassRef": {"name": "zipline"}}
    result = subprocess.run(
        ["helm", "template", "test", str(AWS / "charts/karpenter-nodepools"), "-f", "-"],
        input=yaml.safe_dump({"nodePools": {"worker": pools, "control": control}}),
        text=True, capture_output=True, check=True,
    )
    docs = [doc for doc in yaml.safe_load_all(result.stdout) if doc]
    # The profile release must never render (and so never own) the shared EC2NodeClass.
    assert all(doc["kind"] == "NodePool" for doc in docs), [doc["kind"] for doc in docs]
    return {doc["metadata"]["name"]: doc["spec"] for doc in docs}


def requirement(spec, key):
    return next(r for r in spec["template"]["spec"]["requirements"] if r["key"] == key)


PROFILE = {"instance_types": ["g6e.xlarge", "g5.xlarge"], "max_gpus": 1}


class RayGpuProfileTest(unittest.TestCase):
    def test_no_profiles_by_default(self):
        result = evaluate({})
        self.assertEqual(result["pools"], {})
        self.assertEqual(result["quotas"], {})
        self.assertEqual(result["errors"], [])

    def test_profiles_do_not_change_shared_pools(self):
        self.assertEqual(evaluate({})["default_pools"],
                         evaluate({"ray_gpu_profiles": {"s6e11-l40s": PROFILE}})["default_pools"])

    def test_rendered_pools_satisfy_placement_contract(self):
        result = evaluate({"ray_gpu_profiles": {"s6e11-l40s": PROFILE}})
        self.assertEqual(result["errors"], [])
        pools = render(result["pools"]["s6e11-l40s"])
        self.assertEqual(set(pools), {"s6e11-l40s", "s6e11-l40s-control"})
        for name, role in (("s6e11-l40s", "worker"), ("s6e11-l40s-control", "control")):
            spec = pools[name]
            template = spec["template"]
            self.assertEqual(template["metadata"]["labels"], {
                "zipline.ai/engine": "ray",
                "zipline.ai/role": role,
                "zipline.ai/execution-profile": "s6e11-l40s",
            })
            self.assertEqual(template["spec"]["taints"], [
                {"key": "zipline.ai/workload", "value": "ray-s6e11-l40s", "effect": "NoSchedule"},
            ])
            self.assertEqual(requirement(spec, "kubernetes.io/arch")["values"], ["amd64"])
            self.assertEqual(requirement(spec, "karpenter.sh/capacity-type")["values"], ["on-demand"])
            self.assertEqual(spec["disruption"], {"consolidationPolicy": "WhenEmpty", "consolidateAfter": "1m"})
            self.assertEqual(template["spec"]["expireAfter"], "48h")

        worker = pools["s6e11-l40s"]
        self.assertEqual(requirement(worker, "node.kubernetes.io/instance-type")["values"],
                         ["g6e.xlarge", "g5.xlarge"])
        # Instance pins must not be ANDed with the CPU category selector.
        keys = {r["key"] for r in worker["template"]["spec"]["requirements"]}
        self.assertNotIn("karpenter.k8s.aws/instance-category", keys)
        self.assertEqual(worker["limits"], {"nvidia.com/gpu": "1"})

        control = pools["s6e11-l40s-control"]
        self.assertEqual(requirement(control, "karpenter.k8s.aws/instance-category")["values"], ["c", "m", "r"])
        self.assertNotIn("nvidia.com/gpu", control["limits"])

    def test_overrides(self):
        result = evaluate({
            "ray_gpu_profiles": {"big": {
                "instance_types": ["p5.48xlarge"], "max_gpus": 16, "capacity_type": "spot",
                "expire_after": "12h", "worker_limits": {"cpu": "384"}, "control_limits": {"cpu": "8"},
            }},
            "ray_gpu_namespace_quotas": {"zipline-default": 8},
        })
        self.assertEqual(result["errors"], [])
        pools = result["pools"]["big"]
        self.assertEqual(pools["worker"]["limits"], {"nvidia.com/gpu": "16", "cpu": "384"})
        self.assertEqual(pools["control"]["limits"], {"cpu": "8", "memory": "128Gi"})
        self.assertEqual(pools["worker"]["expireAfter"], "12h")
        self.assertIn({"key": "karpenter.sh/capacity-type", "operator": "In", "values": ["spot"]},
                      pools["worker"]["requirements"])
        # Control capacity stays on-demand: a reclaimed head fails the whole run.
        self.assertIn({"key": "karpenter.sh/capacity-type", "operator": "In", "values": ["on-demand"]},
                      pools["control"]["requirements"])
        self.assertEqual(result["quotas"], {"zipline-default": 8})

    def test_worker_limits_cannot_raise_gpu_cap(self):
        result = evaluate({"ray_gpu_profiles": {"capped": {
            **PROFILE, "worker_limits": {"nvidia.com/gpu": "8", "cpu": "16"}}}})
        self.assertEqual(result["pools"]["capped"]["worker"]["limits"], {"nvidia.com/gpu": "1", "cpu": "16"})

    def test_invalid_profiles_are_reported(self):
        errors = evaluate({"ray_gpu_profiles": {
            "Bad_Name": PROFILE,
            "no-types": {"instance_types": [], "max_gpus": 1},
            "zero": {"instance_types": ["g5.xlarge"], "max_gpus": 0},
            "fractional": {"instance_types": ["g5.xlarge"], "max_gpus": 1.5},
            "minutes": {**PROFILE, "expire_after": "90m"},
            "reserved": {**PROFILE, "capacity_type": "reserved"},
        }})["errors"]
        self.assertEqual(len(errors), 6, errors)
        for name in ("Bad_Name", "no-types", "zero", "fractional", "minutes", "reserved"):
            self.assertTrue(any(e.startswith(name + ":") for e in errors), (name, errors))

    def test_generated_names_must_not_collide(self):
        errors = evaluate({"ray_gpu_profiles": {
            "ray-worker": PROFILE,        # shared worker pool
            "ray": PROFILE,               # ray-control is a shared pool
            "training": PROFILE,          # training-control generated twice
            "training-control": PROFILE,
            "karpenter": PROFILE,         # Karpenter Helm release
            "fine": PROFILE,
        }})["errors"]
        for name in ("ray-worker:", "ray-control:", "training-control:", "karpenter:"):
            self.assertTrue(any(e.startswith(name) for e in errors), (name, errors))
        self.assertFalse(any(e.startswith("fine") for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
