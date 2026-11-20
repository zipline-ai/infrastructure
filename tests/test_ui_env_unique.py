"""Render the chart with Helm: python3 -m unittest discover -s tests."""

from pathlib import Path
import subprocess
import unittest

import yaml


CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"


def ui_env(extra):
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
    for doc in yaml.safe_load_all(subprocess.check_output(command, text=True)):
        if doc and doc.get("kind") == "Deployment" and doc["metadata"]["name"].endswith("orchestration-ui"):
            return doc["spec"]["template"]["spec"]["containers"][0]["env"]
    raise AssertionError("UI Deployment not rendered")


class UiEnvUniqueTest(unittest.TestCase):
    # Duplicate env names make every later Deployment patch fail once the list changes shape.
    def test_configured_log_provider_replaces_default(self):
        env = ui_env(["--set", "orchestration.ui.env[0].name=LOG_PROVIDER",
                      "--set", "orchestration.ui.env[0].value=gcp"])
        names = [e["name"] for e in env]
        self.assertEqual(len(names), len(set(names)), names)
        self.assertEqual([e["value"] for e in env if e["name"] == "LOG_PROVIDER"], ["gcp"])

    def test_default_log_provider_is_loki(self):
        env = ui_env([])
        self.assertEqual([e["value"] for e in env if e["name"] == "LOG_PROVIDER"], ["loki"])


if __name__ == "__main__":
    unittest.main()
