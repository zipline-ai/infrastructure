"""Render the chart with Helm: python3 -m unittest discover -s tests."""

from pathlib import Path
import re
import subprocess
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "charts/zipline-orchestration"


def render(extra=()):
    command = [
        "helm", "template", "test", str(CHART),
        "--set", "global.customer_name=test",
        "--set", "database.host=postgres",
        "--set", "polaris.bootstrap.rbac.catalog.storage.type=S3",
        "--set", "orchestration.hub.image=test/hub",
        "--set", "orchestration.hub.verticleClass=test.Hub",
        "--set", "orchestration.eval.image=test/eval",
        *extra,
    ]
    return [doc for doc in yaml.safe_load_all(subprocess.check_output(command, text=True)) if doc]


def spark_operator_deployments(extra=()):
    deployments = {}
    for doc in render(extra):
        if doc.get("kind") != "Deployment":
            continue
        labels = doc.get("metadata", {}).get("labels", {})
        if labels.get("app.kubernetes.io/name") == "spark-operator":
            deployments[labels["app.kubernetes.io/component"]] = doc
    return deployments


class SparkOperatorTest(unittest.TestCase):
    def test_controller_has_ha_workers_and_resources(self):
        controller = spark_operator_deployments()["controller"]
        self.assertEqual(controller["spec"]["replicas"], 2)
        container = controller["spec"]["template"]["spec"]["containers"][0]
        self.assertIn("--controller-threads=20", container["args"])
        resources = container.get("resources", {})
        self.assertIn("cpu", resources.get("requests", {}))
        self.assertIn("memory", resources.get("requests", {}))
        self.assertIn("cpu", resources.get("limits", {}))
        self.assertIn("memory", resources.get("limits", {}))

    def test_webhook_has_ha_and_resources(self):
        webhook = spark_operator_deployments()["webhook"]
        self.assertEqual(webhook["spec"]["replicas"], 2)
        container = webhook["spec"]["template"]["spec"]["containers"][0]
        resources = container.get("resources", {})
        self.assertIn("cpu", resources.get("requests", {}))
        self.assertIn("memory", resources.get("requests", {}))
        self.assertIn("cpu", resources.get("limits", {}))
        self.assertIn("memory", resources.get("limits", {}))

    def test_values_omit_dead_kube_api_keys(self):
        values = yaml.safe_load((CHART / "values.yaml").read_text())
        controller_values = values["spark-operator"]["controller"]
        self.assertNotIn("kubeAPIQPS", controller_values)
        self.assertNotIn("kubeAPIBurst", controller_values)

    def test_aws_and_gcp_pin_webhook_to_system_pool(self):
        for cloud in ("aws", "gcp"):
            locals_text = (ROOT / f"{cloud}/zipline-orchestration/locals.tf").read_text()
            match = re.search(r'"spark-operator"\s*=\s*\{(.*?)\n    \}', locals_text, re.DOTALL)
            self.assertIsNotNone(match, f"{cloud} locals.tf missing spark-operator block")
            block = match.group(1)
            for component in ("hook", "controller", "webhook"):
                comp_match = re.search(rf'\b{component}\s*=\s*\{{(.*?)\}}', block, re.DOTALL)
                self.assertIsNotNone(comp_match, f"{cloud} spark-operator block missing {component}")
                comp_body = comp_match.group(1)
                self.assertIn("nodeSelector = local.system_node_selector", comp_body, f"{cloud} {component}")
                self.assertIn("tolerations  = local.system_node_tolerations", comp_body, f"{cloud} {component}")

        webhook = spark_operator_deployments([
            "--set", "spark-operator.webhook.nodeSelector.zipline\\.ai/node-pool=system",
            "--set", "spark-operator.webhook.tolerations[0].key=zipline.ai/node-pool",
            "--set", "spark-operator.webhook.tolerations[0].operator=Equal",
            "--set", "spark-operator.webhook.tolerations[0].value=system",
            "--set", "spark-operator.webhook.tolerations[0].effect=NoSchedule",
        ])["webhook"]
        pod_spec = webhook["spec"]["template"]["spec"]
        self.assertEqual(pod_spec["nodeSelector"], {"zipline.ai/node-pool": "system"})
        self.assertEqual(pod_spec["tolerations"], [{
            "key": "zipline.ai/node-pool",
            "operator": "Equal",
            "value": "system",
            "effect": "NoSchedule",
        }])


if __name__ == "__main__":
    unittest.main()
