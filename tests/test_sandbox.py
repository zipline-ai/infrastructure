"""Render sandbox deployment and UI configuration without cloud credentials."""
import subprocess
import unittest

import yaml

from test_fetcher_metrics import CHART


def render(repo=None, auth=False, sandbox=None):
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
            "sandbox": sandbox or {},
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


class SandboxNetworkTest(unittest.TestCase):
    def test_no_network_resources_without_repo(self):
        docs = render()
        self.assertFalse(any(d["metadata"]["name"].startswith("sandbox-") for d in docs))

    def test_proxy_and_network_policy(self):
        docs = render({"url": "https://github.com/example/conf"})
        sandbox = container(docs, "zipline-sandbox")
        env = {e["name"]: e["value"] for e in sandbox["env"]}
        for key in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
            self.assertEqual(env[key], "http://sandbox-egress:3128")
        self.assertIn("orchestration-ui-service", env["no_proxy"].split(","))
        self.assertEqual(env["NO_PROXY"], env["no_proxy"])
        policies = {d["metadata"]["name"]: d["spec"] for d in docs if d["kind"] == "NetworkPolicy"}
        policy = policies["sandbox-isolation"]
        self.assertEqual(set(policy["policyTypes"]), {"Ingress", "Egress"})
        self.assertEqual(policy["ingress"], [{"from": [{"podSelector": {"matchLabels": {"app": "zipline-ui"}}}], "ports": [{"protocol": "TCP", "port": 8000}]}])
        self.assertEqual(len(policy["egress"]), 3)
        dns = policy["egress"][0]
        self.assertEqual(dns["to"], [{
            "namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}},
            "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}},
        }])
        self.assertEqual(dns["ports"], [{"protocol": "UDP", "port": 53}, {"protocol": "TCP", "port": 53}])
        self.assertEqual(policy["egress"][1]["ports"], [{"protocol": "TCP", "port": 3000}])
        self.assertEqual(policy["egress"][2]["ports"], [{"protocol": "TCP", "port": 3128}])
        destinations = [peer for rule in policy["egress"] for peer in rule["to"]]
        self.assertFalse(any("ipBlock" in peer for peer in destinations))
        self.assertIn({"podSelector": {"matchLabels": {"app": "sandbox-egress"}}}, destinations)
        self.assertIn({"podSelector": {"matchLabels": {"app": "zipline-ui"}}}, destinations)
        proxy_policy = policies["sandbox-egress-isolation"]
        self.assertEqual(proxy_policy["ingress"], [{
            "from": [{"podSelector": {"matchLabels": {"app": "zipline-sandbox"}}}],
            "ports": [{"protocol": "TCP", "port": 3128}],
        }])
        self.assertEqual(len(proxy_policy["egress"]), 2)
        self.assertEqual(proxy_policy["egress"][1]["ports"], [{"protocol": "TCP", "port": 443}])
        public = next(peer["ipBlock"] for rule in proxy_policy["egress"] for peer in rule["to"] if "ipBlock" in peer)
        self.assertIn("169.254.0.0/16", public["except"])
        self.assertIn("10.0.0.0/8", public["except"])
        config = next(d for d in docs if d["kind"] == "ConfigMap" and d["metadata"]["name"] == "sandbox-egress")
        self.assertEqual(config["data"]["allowed-hosts.txt"].splitlines(), ["github.com", "pypi.org", "files.pythonhosted.org"])
        self.assertIn("http_access deny all", config["data"]["squid.conf"])
        self.assertIn("http_access deny !CONNECT", config["data"]["squid.conf"])
        self.assertIn("http_access deny CONNECT !https", config["data"]["squid.conf"])

    def test_custom_hosts_and_ports(self):
        docs = render({"url": "https://git.example.com/conf"}, sandbox={
            "port": 9001, "egress": {"allowedHosts": ["git.example.com", "packages.example.com"]},
        })
        config = next(d for d in docs if d["kind"] == "ConfigMap" and d["metadata"]["name"] == "sandbox-egress")
        self.assertEqual(config["data"]["allowed-hosts.txt"].splitlines(), ["git.example.com", "packages.example.com"])
        policy = next(d for d in docs if d["kind"] == "NetworkPolicy" and d["metadata"]["name"] == "sandbox-isolation")
        self.assertEqual(policy["spec"]["ingress"][0]["ports"][0]["port"], 9001)
