"""Polaris signs tokens with a key that must survive restarts, or running Spark jobs fail with 401s."""
import base64
import subprocess
import unittest

import yaml

from test_fetcher_metrics import CHART


def render(polaris_extra=None):
    polaris = {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "S3"}}}}}
    polaris.update(polaris_extra or {})
    values = {
        "global": {"customer_name": "test", "version": "test"},
        "database": {"host": "postgres"},
        "compute": {"objectStore": {"bucket": "test"}},
        "polaris": polaris,
        "orchestration": {"hub": {"image": "hub", "verticleClass": "test"}, "eval": {"image": "eval"}},
    }
    result = subprocess.run(
        ["helm", "template", "test", str(CHART), "-f", "-"],
        input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
    )
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def find(docs, kind, name):
    return next(d for d in docs if d["kind"] == kind and d["metadata"]["name"] == name)


def polaris_server_env(docs):
    deployments = [d for d in docs if d["kind"] == "Deployment" and
                   any(c["name"] == "polaris" for c in d["spec"]["template"]["spec"]["containers"])]
    assert len(deployments) == 1, [d["metadata"]["name"] for d in deployments]
    container = next(c for c in deployments[0]["spec"]["template"]["spec"]["containers"] if c["name"] == "polaris")
    return {e["name"]: e for e in container["env"]}


class PolarisTokenBrokerTest(unittest.TestCase):
    def test_signing_key_is_a_kept_secret_used_by_the_server(self):
        docs = render()
        secret = find(docs, "Secret", "polaris-token-broker")
        self.assertEqual(secret["metadata"]["annotations"]["helm.sh/resource-policy"], "keep")
        self.assertGreaterEqual(len(base64.b64decode(secret["data"]["symmetric-key"])), 64)

        config = find(docs, "ConfigMap", "polaris-config")["data"]["application.properties"]
        self.assertIn("polaris.authentication.token-broker.type=symmetric-key", config.splitlines())

        ref = polaris_server_env(docs)["POLARIS_AUTHENTICATION_TOKEN_BROKER_SYMMETRIC_KEY_SECRET"]
        self.assertEqual(ref["valueFrom"]["secretKeyRef"], {"name": "polaris-token-broker", "key": "symmetric-key"})

    def test_secret_name_and_key_are_configurable(self):
        docs = render({"tokenBroker": {"secret": {"name": "custom-broker", "key": "k"}}})
        self.assertIn("k", find(docs, "Secret", "custom-broker")["data"])
        ref = polaris_server_env(docs)["POLARIS_AUTHENTICATION_TOKEN_BROKER_SYMMETRIC_KEY_SECRET"]
        self.assertEqual(ref["valueFrom"]["secretKeyRef"], {"name": "custom-broker", "key": "k"})


if __name__ == "__main__":
    unittest.main()
