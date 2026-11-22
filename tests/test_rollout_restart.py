"""Check restart opt-in, deployment targeting, and scoped permissions."""

import subprocess
import unittest
from pathlib import Path

import yaml

CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"


def render(enabled=False, fetcher=False, repo=False):
    result = subprocess.run(
        [
            "helm", "template", "test", str(CHART),
            "--namespace", "demo", "--kube-version", "1.36.4",
            "--set", "global.version=nightly",
            "--set", "global.customer_name=test",
            "--set", f"global.deploy_fetcher={str(fetcher).lower()}",
            "--set", f"orchestration.rolloutRestart.enabled={str(enabled).lower()}",
            "--set", "orchestration.confRepo.url=" + ("https://github.com/example/conf" if repo else ""),
            "--set", "orchestration.hub.image=ziplineai/hub-aws",
            "--set", "orchestration.hub.verticleClass=test.Hub",
            "--set", "orchestration.eval.image=ziplineai/eval-aws",
            "--set", "database.host=postgres",
            "--set", "compute.objectStore.bucket=test",
            "--set", "compute.sparkDefaults.eventLogDir=test/events",
            "--set", "polaris.bootstrap.rbac.catalog.storage.type=S3",
        ],
        capture_output=True, text=True, check=True,
    )
    return [d for d in yaml.safe_load_all(result.stdout) if d]


class RolloutRestartTest(unittest.TestCase):
    def test_repository_sandbox_is_refreshed_when_enabled(self):
        docs = render(enabled=True, repo=True)
        role = next(d for d in docs if d["kind"] == "Role" and d["metadata"]["name"].endswith("-rollout-restart"))
        job = next(d for d in docs if d["kind"] == "CronJob")
        args = job["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]["args"]
        self.assertIn("zipline-sandbox", args)
        self.assertIn("zipline-sandbox", role["rules"][0]["resourceNames"])

    def test_disabled_by_default(self):
        self.assertFalse(any("rollout-restart" in d["metadata"]["name"] for d in render()))

    def test_targets_only_enabled_services_with_scoped_permissions(self):
        for fetcher in (False, True):
            with self.subTest(fetcher=fetcher):
                docs = render(enabled=True, fetcher=fetcher)
                resources = {d["kind"]: d for d in docs
                             if d["metadata"]["name"].endswith("-rollout-restart")}
                self.assertEqual(set(resources), {"CronJob", "ServiceAccount", "Role", "RoleBinding", "ConfigMap"})
                job = resources["CronJob"]["spec"]
                self.assertEqual(job["schedule"], "0 11 * * *")
                self.assertEqual(job["timeZone"], "Etc/UTC")
                self.assertEqual(job["concurrencyPolicy"], "Forbid")
                pod = job["jobTemplate"]["spec"]["template"]["spec"]
                container = pod["containers"][0]
                self.assertEqual(container["image"], "registry.k8s.io/kubectl:v1.36.0")
                args = container["args"]
                self.assertIn("--kubeconfig=/etc/kubeconfig/kubeconfig", args)
                kubeconfig = yaml.safe_load(resources["ConfigMap"]["data"]["kubeconfig"])
                self.assertEqual(kubeconfig["users"][0]["user"], {
                    "tokenFile": "/var/run/secrets/kubernetes.io/serviceaccount/token",
                })
                targets = set(args[args.index("deployment") + 1:])
                expected = {"zipline-orchestration-hub", "zipline-orchestration-ui", "zipline-eval"}
                if fetcher:
                    expected.add("zipline-fetcher")
                self.assertEqual(targets, expected)
                self.assertEqual(resources["Role"]["rules"], [{
                    "apiGroups": ["apps"], "resources": ["deployments"],
                    "resourceNames": list(args[args.index("deployment") + 1:]),
                    "verbs": ["get", "patch"],
                }])
                binding = resources["RoleBinding"]
                self.assertEqual(binding["subjects"], [{
                    "kind": "ServiceAccount", "name": pod["serviceAccountName"], "namespace": "demo",
                }])
                self.assertEqual(binding["roleRef"]["name"], resources["Role"]["metadata"]["name"])
                deployments = {d["metadata"]["name"]: d for d in docs if d["kind"] == "Deployment"}
                for target in targets:
                    for app in deployments[target]["spec"]["template"]["spec"]["containers"]:
                        self.assertEqual(app["imagePullPolicy"], "Always")
                        self.assertTrue(app["image"].endswith(":nightly"))


if __name__ == "__main__":
    unittest.main()
