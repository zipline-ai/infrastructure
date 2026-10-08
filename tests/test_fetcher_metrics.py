"""Render the chart and check AWS discovery against its declared pod ports.

Run from the repo root: uv run --with PyYAML python -m unittest discover -s tests -v
"""

import re
import subprocess
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "charts/zipline-orchestration"


def render(fetcher=None, runtime_env=None, enabled=True):
    values = {
        "global": {"customer_name": "test", "version": "test", "deploy_fetcher": enabled},
        "database": {"host": "postgres.example.com"},
        "compute": {
            "objectStore": {"bucket": "test-bucket"},
            "sparkDefaults": {"eventLogDir": "test-bucket/spark-events"},
        },
        "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "S3"}}}}},
        "orchestration": {
            "hub": {"image": "ziplineai/hub", "verticleClass": "com.zipline.OrchestrationVerticle"},
            "eval": {"image": "ziplineai/eval"},
            "fetcher": fetcher or {},
        },
        "runtime": {"env": runtime_env or []},
    }
    result = subprocess.run(
        ["helm", "template", "test", str(CHART), "--namespace", "zipline-system", "-f", "-"],
        input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
    )
    return list(yaml.safe_load_all(result.stdout))


def pod(documents):
    return next(d for d in documents if d and d.get("kind") == "Deployment"
                and d["metadata"]["name"] == "zipline-fetcher")["spec"]["template"]


def scrape_config():
    source = (ROOT / "aws/zipline-orchestration/observability.tf").read_text()
    return yaml.safe_load(source.split("amp_scrape_config = <<-EOT\n", 1)[1].split("\nEOT", 1)[0])


def selected_addresses(job, template):
    """Evaluate discovery keep/drop rules on each declared container port."""
    addresses = []
    for container in template["spec"]["containers"]:
        for port in container.get("ports", []):
            labels = {
                "__meta_kubernetes_pod_container_name": container["name"],
                "__meta_kubernetes_pod_container_port_name": port.get("name", ""),
                "__meta_kubernetes_pod_phase": "Running",
            }
            labels.update({"__meta_kubernetes_pod_label_" + k: v
                           for k, v in template["metadata"]["labels"].items()})
            keep = True
            for rule in job["relabel_configs"]:
                action = rule.get("action", "replace")
                if action not in ("keep", "drop"):
                    continue
                value = rule.get("separator", ";").join(labels.get(k, "") for k in rule["source_labels"])
                matches = re.fullmatch(str(rule.get("regex", "(.*)")), value) is not None
                if (action == "keep" and not matches) or (action == "drop" and matches):
                    keep = False
            if keep:
                addresses.append(port["containerPort"])
    return addresses


class FetcherMetricsTest(unittest.TestCase):
    def test_metrics_enabled_by_default(self):
        container = pod(render())["spec"]["containers"][0]
        env = {item["name"]: item.get("value") for item in container["env"]}
        self.assertEqual(env.get("CHRONON_METRICS_READER"), "prometheus")
        ports = {p.get("name"): p["containerPort"] for p in container["ports"]}
        self.assertEqual(ports.get("chronon-metrics"), 8905)
        self.assertEqual(ports.get("vertx-metrics"), 8906)

    def test_aws_discovers_both_metrics_ports_without_application_port(self):
        jobs = scrape_config()["scrape_configs"]
        job = next((j for j in jobs if j["job_name"] == "fetcher"), None)
        self.assertIsNotNone(job, "AMP needs a fetcher scrape job")
        template = pod(render())
        self.assertEqual(selected_addresses(job, template), [8905, 8906])
        template["spec"]["containers"].append({
            "name": "sidecar", "ports": [{"name": "chronon-metrics", "containerPort": 9999}],
        })
        self.assertEqual(selected_addresses(job, template), [8905, 8906])
        template["metadata"]["labels"]["app"] = "hub"
        self.assertEqual(selected_addresses(job, template), [])

    def test_explicit_readers_are_preserved(self):
        for reader in ("http", "grpc", ""):
            for scope in ("runtime", "fetcher"):
                with self.subTest(reader=reader, scope=scope):
                    env = [{"name": "CHRONON_METRICS_READER", "value": reader}]
                    docs = render(runtime_env=env) if scope == "runtime" else render({"env": env})
                    container = pod(docs)["spec"]["containers"][0]
                    self.assertEqual([e for e in container["env"] if e["name"] == "CHRONON_METRICS_READER"], env)
                    self.assertEqual(len(container["ports"]), 1)

    def test_custom_ports_match_environment(self):
        env = [
            {"name": "CHRONON_PROMETHEUS_SERVER_PORT", "value": "9905"},
            {"name": "VERTX_PROMETHEUS_SERVER_PORT", "value": "9906"},
        ]
        job = next(j for j in scrape_config()["scrape_configs"] if j["job_name"] == "fetcher")
        for scope in ("runtime", "fetcher"):
            with self.subTest(scope=scope):
                template = pod(render(runtime_env=env) if scope == "runtime" else render({"env": env}))
                container = template["spec"]["containers"][0]
                for entry in env:
                    self.assertEqual([e for e in container["env"] if e["name"] == entry["name"]], [entry])
                self.assertEqual(selected_addresses(job, template), [9905, 9906])

    def test_chart_ports_configure_exporters(self):
        container = pod(render({"metricsPort": 9905, "vertxMetricsPort": 9906}))["spec"]["containers"][0]
        env = {e["name"]: e.get("value") for e in container["env"]}
        self.assertEqual(env["CHRONON_PROMETHEUS_SERVER_PORT"], "9905")
        self.assertEqual(env["VERTX_PROMETHEUS_SERVER_PORT"], "9906")
        self.assertEqual([p["containerPort"] for p in container["ports"]], [9000, 9905, 9906])

    def test_chart_can_disable_metrics(self):
        container = pod(render({"metricsReader": ""}))["spec"]["containers"][0]
        self.assertIn({"name": "CHRONON_METRICS_READER", "value": ""}, container["env"])
        self.assertEqual(len(container["ports"]), 1)

    def test_empty_port_environment_uses_application_defaults(self):
        container = pod(render({
            "metricsPort": 9905, "vertxMetricsPort": 9906,
            "env": [
                {"name": "CHRONON_PROMETHEUS_SERVER_PORT", "value": ""},
                {"name": "VERTX_PROMETHEUS_SERVER_PORT", "value": ""},
            ],
        }))["spec"]["containers"][0]
        self.assertEqual([p["containerPort"] for p in container["ports"]], [9000, 8905, 8906])

    def test_fetcher_reader_overrides_runtime_reader(self):
        template = pod(render(
            {"env": [{"name": "CHRONON_METRICS_READER", "value": "prometheus"}]},
            runtime_env=[{"name": "CHRONON_METRICS_READER", "value": "http"}],
        ))
        container = template["spec"]["containers"][0]
        readers = [e["value"] for e in container["env"] if e["name"] == "CHRONON_METRICS_READER"]
        self.assertEqual(readers, ["http", "prometheus"])
        self.assertEqual([p["containerPort"] for p in container["ports"]], [9000, 8905, 8906])

    def test_reader_from_secret_is_preserved(self):
        entry = {"name": "CHRONON_METRICS_READER", "valueFrom": {
            "secretKeyRef": {"name": "metrics", "key": "reader"},
        }}
        container = pod(render({"env": [entry]}))["spec"]["containers"][0]
        self.assertEqual([e for e in container["env"] if e["name"] == entry["name"]], [entry])
        self.assertEqual(len(container["ports"]), 1)

    def test_fetcher_remains_optional(self):
        self.assertFalse(any(d and d.get("kind") == "Deployment" and
                            d["metadata"]["name"] == "zipline-fetcher"
                            for d in render(enabled=False)))


if __name__ == "__main__":
    unittest.main()
