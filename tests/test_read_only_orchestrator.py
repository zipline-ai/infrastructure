"""Render the reader deployment and check separation from the workflow writer."""
import subprocess
import unittest
from pathlib import Path

import yaml

CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"


def render(reader=None):
    values = {
        "global": {"customer_name": "test", "version": "test"},
        "database": {"host": "writer-db", "jdbcUrl": "jdbc:postgresql://writer-db:5432/execution_info", "credentialsSecret": {"name": "db-credentials"}},
        "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "S3"}}}}},
        "orchestration": {
            "hub": {"image": "test/hub", "verticleClass": "test.Hub,test.Worker"},
            "eval": {"image": "test/eval"},
        },
        "serviceAccount": {"annotations": {"eks.amazonaws.com/role-arn": "writer-role"}},
        "podLabels": {"azure.workload.identity/use": "true"},
        "runtime": {"env": [{"name": "WRITER_CREDENTIAL", "value": "must-not-copy"}]},
    }
    if reader is not None:
        values["orchestration"]["readOnly"] = reader
    return subprocess.run(
        ["helm", "template", "test", str(CHART), "--namespace", "zipline-system", "-f", "-"],
        input=yaml.safe_dump(values), text=True, capture_output=True,
    )


def documents(result):
    if result.returncode:
        raise AssertionError(result.stderr)
    return [d for d in yaml.safe_load_all(result.stdout) if d]


class ReadOnlyOrchestratorTest(unittest.TestCase):
    def test_disabled_by_default(self):
        docs = documents(render())
        self.assertFalse(any(d["metadata"]["name"] == "orchestration-read-only-service" for d in docs))

    def test_reader_is_separate_and_has_no_execution_identity(self):
        docs = documents(render({"enabled": True, "databaseHost": "reader-db", "verticleClass": "test.Hub"}))
        deployments = {d["metadata"]["name"]: d for d in docs if d["kind"] == "Deployment"}
        reader = deployments["zipline-orchestration-read-only"]["spec"]["template"]
        writer = deployments["zipline-orchestration-hub"]["spec"]["template"]
        pod = reader["spec"]
        self.assertFalse(pod["automountServiceAccountToken"])
        self.assertNotEqual(pod["serviceAccountName"], writer["spec"]["serviceAccountName"])
        self.assertNotIn("azure.workload.identity/use", reader["metadata"]["labels"])
        container = pod["containers"][0]
        self.assertEqual(container["image"], writer["spec"]["containers"][0]["image"])
        env = {item["name"]: item for item in container["env"]}
        self.assertEqual(env["ORCHESTRATION_READ_ONLY"]["value"], "true")
        self.assertEqual(env["VERTICLE_CLASS"]["value"], "test.Hub")
        self.assertIn("reader-db", env["DB_URL"]["value"])
        self.assertNotIn("writer-db", env["DB_URL"]["value"])
        self.assertNotIn("WRITER_CREDENTIAL", env)
        self.assertEqual(env["DB_USERNAME"]["valueFrom"]["secretKeyRef"]["name"], "db-credentials")
        writer_env = {item["name"]: item for item in writer["spec"]["containers"][0]["env"]}
        self.assertNotIn("ORCHESTRATION_READ_ONLY", writer_env)
        self.assertEqual(writer_env["VERTICLE_CLASS"]["value"], "test.Hub,test.Worker")
        self.assertIn("writer-db", writer_env["DB_URL"]["value"])
        self.assertEqual(container["readinessProbe"]["httpGet"]["path"], "/readyz")
        self.assertEqual(container["livenessProbe"]["httpGet"]["path"], "/ping")
        sa = next(d for d in docs if d["kind"] == "ServiceAccount" and d["metadata"]["name"] == pod["serviceAccountName"])
        self.assertNotIn("annotations", sa["metadata"])
        self.assertFalse(any(d["kind"] == "Ingress" and d["metadata"]["name"] == "orchestration-read-only-ingress" for d in docs))

    def test_explicit_reader_ingress(self):
        docs = documents(render({"enabled": True, "databaseHost": "reader-db", "verticleClass": "test.Hub", "ingress": {"enabled": True, "host": "reader.example.com"}}))
        ingress = next(d for d in docs if d["kind"] == "Ingress" and d["metadata"]["name"] == "orchestration-read-only-ingress")
        self.assertEqual(ingress["spec"]["rules"][0]["host"], "reader.example.com")
        backend = ingress["spec"]["rules"][0]["http"]["paths"][0]["backend"]
        self.assertEqual(backend["service"]["name"], "orchestration-read-only-service")

    def test_missing_reader_configuration_is_rejected(self):
        for reader in (
            {"enabled": True},
            {"enabled": True, "databaseHost": "reader-db"},
            {"enabled": True, "databaseHost": "reader-db", "verticleClass": "test.Hub,test.Worker"},
            {"enabled": True, "databaseHost": "writer-db", "verticleClass": "test.Hub"},
            {"enabled": True, "databaseHost": "reader-db", "verticleClass": "test.Hub", "ingress": {"enabled": True}},
        ):
            with self.subTest(reader=reader):
                self.assertNotEqual(render(reader).returncode, 0)


if __name__ == "__main__":
    unittest.main()
