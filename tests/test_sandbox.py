"""Render sandbox deployment and UI configuration without cloud credentials."""
import subprocess
import unittest

import yaml

from test_fetcher_metrics import CHART


def render(repo=None, auth=False):
    values = {
        "global": {"customer_name": "test", "version": "test"},
        "database": {"host": "postgres"},
        "compute": {"objectStore": {"bucket": "test"}},
        "auth": {"enabled": auth},
        "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "S3"}}}}},
        "orchestration": {
            "hub": {"image": "hub", "verticleClass": "test"},
            "eval": {"image": "eval"},
            "confRepo": repo or {},
        },
    }
    result = subprocess.run(
        ["helm", "template", "test", str(CHART), "-f", "-"],
        input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
    )
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def container(docs, name):
    return next(d for d in docs if d["kind"] == "Deployment" and
                d["metadata"]["name"] == name)["spec"]["template"]["spec"]["containers"][0]


class SandboxTest(unittest.TestCase):
    def test_disabled_without_repo(self):
        docs = render()
        self.assertFalse(any(d["metadata"]["name"] in ("zipline-sandbox", "sandbox-service") for d in docs))
        self.assertNotIn("SANDBOX_URL", {e["name"] for e in container(docs, "zipline-orchestration-ui")["env"]})

    def test_enabled_service_auth_and_credentials(self):
        for auth in (False, True):
            with self.subTest(auth=auth):
                docs = render({"url": "https://github.com/example/conf", "path": "python/conf",
                               "branch": "deploy", "ziplineEnv": "canary", "githubClientId": "client",
                               "tokenKey": "github-token", "clientSecretKey": "github-client-secret"}, auth)
                sandbox = container(docs, "zipline-sandbox")
                self.assertEqual(sandbox["image"], "ziplineai/sandbox:test")
                env = {e["name"]: e["value"] for e in sandbox["env"]}
                self.assertEqual(env["AUTH_ENABLED"], str(auth).lower())
                self.assertEqual(env["AUTH_JWKS_URL"], "http://orchestration-ui-service/api/auth/jwks")
                self.assertEqual(env["SANDBOX_ZIPLINE_CLI"], "source")
                service = next(d for d in docs if d["metadata"]["name"] == "sandbox-service")
                self.assertEqual(service["spec"]["type"], "ClusterIP")
                self.assertEqual(service["spec"]["ports"][0]["port"], 8000)
                ui = {e["name"]: e for e in container(docs, "zipline-orchestration-ui")["env"]}
                self.assertEqual(ui["SANDBOX_URL"]["value"], "http://sandbox-service:8000")
                for name, value in {"CONF_REPO_URL": "https://github.com/example/conf", "CONF_REPO_PATH": "python/conf",
                                    "CONF_REPO_BRANCH": "deploy", "ZIPLINE_ENV": "canary",
                                    "CONF_REPO_GITHUB_CLIENT_ID": "client", "CONF_REPO_GITHUB_SCOPE": "repo"}.items():
                    self.assertEqual(ui[name]["value"], value)
                for name, key in {"CONF_REPO_GITHUB_TOKEN": "github-token",
                                  "CONF_REPO_GITHUB_CLIENT_SECRET": "github-client-secret"}.items():
                    self.assertEqual(ui[name]["valueFrom"]["secretKeyRef"],
                                     {"name": "conf-repo-credentials", "key": key})

    def test_optional_credentials(self):
        docs = render({"url": "https://github.com/example/public"})
        env = {e["name"] for e in container(docs, "zipline-orchestration-ui")["env"]}
        self.assertNotIn("CONF_REPO_GITHUB_TOKEN", env)
        self.assertNotIn("CONF_REPO_GITHUB_CLIENT_SECRET", env)
