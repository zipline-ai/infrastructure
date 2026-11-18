"""Render the automatic team namespace template, including external RBAC installs."""

from pathlib import Path
import subprocess
import unittest

import yaml


CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"
TEMPLATE_NAME = "test-zipline-orchestration-compute-namespace-template"
PROVISIONER_NAME = "test-zipline-orchestration-namespace-provisioner"


def render(compute=None):
    values = {
        "global": {"customer_name": "test"},
        "database": {"host": "postgres"},
        "polaris": {"bootstrap": {"rbac": {"catalog": {"storage": {"type": "S3"}}}}},
        "orchestration": {
            "hub": {"image": "test/hub", "verticleClass": "test.Hub"},
            "eval": {"image": "test/eval"},
        },
        "compute": compute or {},
    }
    result = subprocess.run(
        ["helm", "template", "test", str(CHART), "--namespace", "zipline-system", "-f", "-"],
        input=yaml.safe_dump(values), text=True, capture_output=True, check=True,
    )
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]


def resource(documents, kind, name):
    return next(doc for doc in documents if doc["kind"] == kind and doc["metadata"]["name"] == name)


class TeamNamespacesTest(unittest.TestCase):
    def assert_template_installed(self, documents):
        template = resource(documents, "ConfigMap", TEMPLATE_NAME)
        self.assertTrue(template["data"]["resources.yaml"].strip())
        hub = resource(documents, "Deployment", "zipline-orchestration-hub")["spec"]["template"]
        self.assertTrue(hub["metadata"]["annotations"]["checksum/compute-namespace-template"])
        pod = hub["spec"]
        container = pod["containers"][0]
        env = {entry["name"]: entry.get("value") for entry in container["env"]}
        self.assertEqual(env["IN_CLUSTER_COMPUTE_ENABLED"], "true")
        self.assertEqual(env["CRUCIBLE_COMPUTE_NAMESPACE_TEMPLATE_DIR"], "/etc/zipline/compute-namespace")
        self.assertNotIn("CRUCIBLE_TEAM_NAMESPACES_ENABLED", env)
        mount = next(mount for mount in container["volumeMounts"] if mount["name"] == "compute-namespace-template")
        self.assertEqual(mount["mountPath"], env["CRUCIBLE_COMPUTE_NAMESPACE_TEMPLATE_DIR"])
        self.assertTrue(mount["readOnly"])
        volume = next(volume for volume in pod["volumes"] if volume["name"] == mount["name"])
        self.assertEqual(volume["configMap"]["name"], TEMPLATE_NAME)

    def test_default_install_provisions_team_namespaces(self):
        documents = render()
        self.assert_template_installed(documents)
        provisioner = resource(documents, "ClusterRole", PROVISIONER_NAME)
        namespace_rule = next(rule for rule in provisioner["rules"] if rule["resources"] == ["namespaces"])
        self.assertEqual(set(namespace_rule["verbs"]), {"get", "list", "watch", "create"})
        binding = resource(documents, "ClusterRoleBinding", PROVISIONER_NAME)
        self.assertEqual(binding["roleRef"]["name"], PROVISIONER_NAME)
        self.assertEqual(binding["subjects"], [{
            "kind": "ServiceAccount", "name": "orchestration-sa", "namespace": "zipline-system",
        }])

    def test_external_rbac_still_installs_complete_template(self):
        documents = render({"rbac": {"create": False}})
        self.assert_template_installed(documents)
        provisioners = [doc for doc in documents if doc["kind"] in {"ClusterRole", "ClusterRoleBinding"}
                        and doc["metadata"]["name"] == PROVISIONER_NAME]
        self.assertEqual(provisioners, [])
        template = resource(documents, "ConfigMap", TEMPLATE_NAME)
        resources = [doc for doc in yaml.safe_load_all(template["data"]["resources.yaml"]) if doc]
        self.assertEqual({doc["kind"] for doc in resources}, {"ServiceAccount", "RoleBinding", "ResourceQuota", "LimitRange"})

    def test_template_preserves_namespace_policies_and_identity(self):
        for enabled in (True, False):
            with self.subTest(policies_enabled=enabled):
                documents = render({
                    "serviceAccount": {"annotations": {"iam.gke.io/gcp-service-account": "spark@example.iam.gserviceaccount.com"}},
                    "flinkDefaults": {"serviceAccountAnnotations": {"eks.amazonaws.com/role-arn": "arn:aws:iam::123456789012:role/flink"}},
                    "namespaceDefaults": {
                        "resourceQuota": {"enabled": enabled, "hard": {"requests.cpu": "45", "pods": "75"}},
                        "limitRange": {"enabled": enabled, "default": {"cpu": "3"}, "defaultRequest": {"cpu": "500m"}},
                    },
                })
                template = resource(documents, "ConfigMap", TEMPLATE_NAME)["data"]
                rendered_resources = [doc for doc in yaml.safe_load_all(template["resources.yaml"]) if doc]
                for doc in rendered_resources:
                    self.assertEqual(doc["metadata"]["namespace"], template["namespacePlaceholder"])
                    expected = next(item for item in documents if item["kind"] == doc["kind"]
                                    and item["metadata"]["name"] == doc["metadata"]["name"]
                                    and item["metadata"].get("namespace") == "zipline-default")
                    doc["metadata"]["namespace"] = "zipline-default"
                    for subject in doc.get("subjects", []):
                        if subject["namespace"] == template["namespacePlaceholder"]:
                            subject["namespace"] = "zipline-default"
                    self.assertEqual(doc, expected)
                for kind in ("ResourceQuota", "LimitRange"):
                    self.assertEqual(any(doc["kind"] == kind for doc in rendered_resources), enabled)


if __name__ == "__main__":
    unittest.main()
