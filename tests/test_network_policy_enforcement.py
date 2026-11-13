"""Evaluate the cloud wrappers' enforcement settings without cloud credentials."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("terraform")


def body(source, header):
    """Extract a production HCL block, including its nested blocks."""
    start = source.index(header) + len(header)
    depth = 1
    for end in range(start, len(source)):
        depth += (source[end] == "{") - (source[end] == "}")
        if depth == 0:
            return source[start:end]
    raise AssertionError("Unclosed HCL block: " + header)


def evaluate(definitions, expression):
    with tempfile.TemporaryDirectory(prefix="network-policy-") as directory:
        (Path(directory) / "main.tf").write_text("locals {\n" + definitions + "\n}\n")
        result = subprocess.run(
            [TERRAFORM, "console", "-no-color"], cwd=directory,
            input="jsonencode(" + expression + ")\n", text=True,
            capture_output=True, check=True,
        )
    return json.loads(json.loads(result.stdout))


class NetworkPolicyEnforcementTest(unittest.TestCase):
    def test_eks_requires_policy_agent_and_preserves_ipam_configuration(self):
        source = (ROOT / "aws/zipline-orchestration/aws-addons.tf").read_text()
        addon = body(source, 'resource "aws_eks_addon" "vpc_cni" {')
        expression = re.search(r'configuration_values\s*=\s*(jsonencode\(merge\(.*?\n  \)\))', addon, re.S).group(1)
        for custom in ({}, {"enableNetworkPolicy": "false", "env": {"WARM_IP_TARGET": "3"}}):
            with self.subTest(custom=custom):
                cloud_args = json.dumps(json.dumps({"vpc_cni_configuration_values": custom}))
                config = evaluate("cloud_args = jsondecode(" + cloud_args + ")\nconfig = " + expression,
                                  "jsondecode(local.config)")
                self.assertEqual(config["enableNetworkPolicy"], "true")
                if "env" in custom:
                    self.assertEqual(config["env"], custom["env"])

    def test_aks_uses_calico_with_existing_overlay(self):
        source = (ROOT / "azure/zipline-orchestration/aks.tf").read_text()
        profile = body(source, "  network_profile {")
        config = evaluate('''cloud_args = {
          aks_service_cidr = "10.0.0.0/16"
          aks_dns_service_ip = "10.0.0.10"
          aks_pod_cidr = "10.244.0.0/16"
        }
        profile = {''' + profile + "}", "local.profile")
        self.assertEqual(config["network_plugin"], "azure")
        self.assertEqual(config["network_plugin_mode"], "overlay")
        self.assertEqual(config["network_policy"], "calico")

    def test_gke_enables_control_plane_and_node_enforcement(self):
        source = (ROOT / "gcp/zipline-orchestration/gke.tf").read_text()
        policy = body(source, "  network_policy {")
        addon = body(source, "    network_policy_config {")
        config = evaluate("policy = {" + policy + "}\naddon = {" + addon + "}",
                          "{policy = local.policy, addon = local.addon}")
        self.assertTrue(config["policy"]["enabled"])
        self.assertEqual(config["policy"]["provider"], "CALICO")
        self.assertFalse(config["addon"]["disabled"])
