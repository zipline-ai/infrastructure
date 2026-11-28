"""Check the bundled and client-managed Loki chart modes."""

from pathlib import Path
import subprocess
import unittest

import yaml

CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"


class ExternalLokiTest(unittest.TestCase):
    def test_external_backend_replaces_bundled_logging(self):
        for external in (False, True):
            with self.subTest(external=external):
                values = {
                    "global": {"customer_name": "test"},
                    "database": {"host": "db.example.com"},
                    "orchestration": {
                        "hub": {"image": "ziplineai/hub", "verticleClass": "example.Hub"},
                        "eval": {"image": "ziplineai/eval"},
                    },
                    "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "GCS"}}}}},
                    "compute": {"loki": {"storage": {"enabled": True}}},
                }
                if external:
                    values["compute"]["loki"]["queryUrl"] = "https://logs.example.com/"
                    values["promtail"] = {"enabled": False}
                result = subprocess.run(
                    ["helm", "template", "test", str(CHART), "-f", "-"],
                    input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
                )
                resources = {
                    (doc["kind"], doc["metadata"]["name"]): doc
                    for doc in yaml.safe_load_all(result.stdout) if doc
                }
                for kind in ("ConfigMap", "Deployment", "Service", "PersistentVolumeClaim"):
                    self.assertEqual(
                        (kind, "test-zipline-orchestration-loki") in resources,
                        not external,
                    )
                self.assertEqual(("DaemonSet", "test-promtail") in resources, not external)
                query_url = (
                    "https://logs.example.com" if external
                    else "http://test-zipline-orchestration-loki.default.svc.cluster.local:3100"
                )
                for name in ("zipline-orchestration-hub", "zipline-orchestration-ui"):
                    deployment = resources["Deployment", name]
                    env = deployment["spec"]["template"]["spec"]["containers"][0]["env"]
                    self.assertEqual(
                        [entry["value"] for entry in env if entry["name"] == "LOKI_URL"],
                        [query_url],
                    )
