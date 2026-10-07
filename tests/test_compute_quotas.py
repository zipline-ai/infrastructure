"""Render compute namespaces and verify mode-scoped quota placement."""

import subprocess
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "charts/zipline-orchestration"


def render(compute=None):
    values = {
        "global": {"customer_name": "test", "version": "test"},
        "database": {"host": "postgres.example.com"},
        "compute": {
            "objectStore": {"bucket": "test-bucket"},
            "sparkDefaults": {"eventLogDir": "test-bucket/spark-events"},
            **(compute or {}),
        },
        "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "S3"}}}}},
        "orchestration": {
            "hub": {"image": "ziplineai/hub", "verticleClass": "com.zipline.OrchestrationVerticle"},
            "eval": {"image": "ziplineai/eval"},
        },
    }
    result = subprocess.run(
        ["helm", "template", "test", str(CHART), "--namespace", "zipline-system", "-f", "-"],
        input=yaml.safe_dump(values),
        text=True,
        capture_output=True,
        check=True,
    )
    return [document for document in yaml.safe_load_all(result.stdout) if document]


class ComputeQuotaTest(unittest.TestCase):
    def test_default_namespace_has_aggregate_and_mode_quotas(self):
        documents = render()
        quotas = {
            document["metadata"]["name"]: document
            for document in documents
            if document["kind"] == "ResourceQuota"
            and document["metadata"]["namespace"] == "zipline-default"
        }

        self.assertEqual(set(quotas), {"zipline-compute", "zipline-backfill", "zipline-deploy"})
        aggregate_hard = quotas["zipline-compute"]["spec"]["hard"]
        for mode in ("backfill", "deploy"):
            quota = quotas[f"zipline-{mode}"]
            self.assertEqual(quota["spec"]["hard"], aggregate_hard)
            expression = quota["spec"]["scopeSelector"]["matchExpressions"]
            self.assertEqual(expression, [{
                "scopeName": "PriorityClass",
                "operator": "In",
                "values": [f"zipline-{mode}"],
            }])

    def test_workload_priority_classes_are_non_preempting(self):
        classes = {
            document["metadata"]["name"]: document
            for document in render()
            if document["kind"] == "PriorityClass"
        }

        self.assertEqual(classes["zipline-backfill"]["value"], 100)
        self.assertEqual(classes["zipline-deploy"]["value"], 200)
        self.assertEqual(classes["zipline-backfill"]["preemptionPolicy"], "Never")
        self.assertEqual(classes["zipline-deploy"]["preemptionPolicy"], "Never")

    def test_unlisted_team_namespace_does_not_get_mode_quotas(self):
        documents = render({
            "namespaces": [{"name": "zipline-other", "team": "other"}],
        })
        quotas = [
            document for document in documents
            if document["kind"] == "ResourceQuota"
            and document["metadata"]["namespace"] == "zipline-other"
        ]

        self.assertEqual([quota["metadata"]["name"] for quota in quotas], ["zipline-compute"])

    def test_another_namespace_can_opt_in_with_overrides(self):
        documents = render({
            "namespaces": [{"name": "zipline-other", "team": "other"}],
            "modeResourceQuotas": {
                "zipline-other": {
                    "backfill": {
                        "priorityClassName": "zipline-backfill",
                        "hard": {"requests.cpu": "25"},
                    },
                },
            },
        })
        quota = next(
            document for document in documents
            if document["kind"] == "ResourceQuota"
            and document["metadata"]["namespace"] == "zipline-other"
            and document["metadata"]["name"] == "zipline-backfill"
        )

        self.assertEqual(quota["spec"]["hard"], {"requests.cpu": "25"})


if __name__ == "__main__":
    unittest.main()
