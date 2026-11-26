"""Check that client-owned ingress keeps the public URLs and backend Services."""

from pathlib import Path
import subprocess
import unittest

import yaml

CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"


class ExternalIngressTest(unittest.TestCase):
    def test_renders_services_and_urls_without_managed_ingress(self):
        values = {
            "global": {"customer_name": "test", "deploy_fetcher": True},
            "database": {"host": "db.example.com"},
            "orchestration": {
                "hub": {"image": "ziplineai/hub", "verticleClass": "example.Hub"},
                "eval": {"image": "ziplineai/eval"},
            },
            "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "GCS"}}}}},
            "ingress-nginx-ui": {"enabled": False},
            "ingress": {
                "externalController": True,
                "ui": {"host": "zipline.example.com"},
                "hub": {"host": "zipline.example.com"},
            },
            "clusterIssuer": {"enabled": True},
        }
        result = subprocess.run(
            ["helm", "template", "test", str(CHART), "-f", "-"],
            input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
        )
        resources = {
            (doc["kind"], doc["metadata"]["name"]): doc
            for doc in yaml.safe_load_all(result.stdout) if doc
        }
        self.assertFalse(
            {"Ingress", "IngressClass", "ClusterIssuer"} & {kind for kind, _ in resources}
        )
        self.assertFalse(any("set-hub-base-url" in name for _, name in resources))
        self.assertNotIn(("Service", "test-ingress-nginx-ui-controller"), resources)
        for name, port in (
            ("orchestration-ui-service", 80),
            ("orchestration-hub-service", 80),
            ("eval-service", 80),
            ("fetcher-service", 80),
            ("spark-history-server", 18080),
            ("polaris-service", 8181),
        ):
            with self.subTest(service=name):
                service = resources["Service", name]
                self.assertIn(port, [entry["port"] for entry in service["spec"]["ports"]])

        hub = resources["Deployment", "zipline-orchestration-hub"]
        env = hub["spec"]["template"]["spec"]["containers"][0]["env"]
        self.assertIn(
            {"name": "HUB_BASE_URL", "value": "https://zipline.example.com/services/hub"},
            env,
        )
        self.assertIn(
            {"name": "CRUCIBLE_SPARK_HISTORY_PUBLIC_URL", "value": "https://zipline.example.com/spark-history"},
            env,
        )
