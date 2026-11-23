"""Evaluate Spark's production Secret Manager grants without cloud credentials."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("tofu") or shutil.which("terraform")


class GcpSparkSecretGrantsTest(unittest.TestCase):
    def grants(self, cloud_args):
        self.assertTrue(TERRAFORM, "Install Terraform/OpenTofu or set TERRAFORM")
        source = (ROOT / "gcp/zipline-orchestration/secrets.tf").read_text()
        resource = re.search(
            r'resource "google_secret_manager_secret_iam_member" "spark_extras" \{\n(.*?)\n\}',
            source, re.S,
        )
        self.assertIsNotNone(resource, "Spark jobs need their own Secret Manager accessor grants")
        attributes = dict(re.findall(r"^\s*(\w+)\s*=\s*(.+)$", resource.group(1), re.M))
        refs = source.split("  spark_secret_ids_to_grant = ", 1)[1].split("\n}", 1)[0]
        values = "\n".join(
            f"{key} = {attributes[key]}" for key in ("secret_id", "role", "member")
        ).replace("each.value", "ref").replace("google_service_account.spark.email", "local.spark_email")
        with tempfile.TemporaryDirectory(prefix="gcp-spark-secret-grants-") as directory:
            fixture = Path(directory)
            (fixture / "main.tf").write_text(
                'variable "cloud_args" { type = any }\n'
                'locals {\ncloud_args = var.cloud_args\n'
                'spark_email = "spark@test-project.iam.gserviceaccount.com"\n'
                'spark_secret_ids_to_grant = ' + refs + '\n'
                'grants = { for ref in ' + attributes["for_each"] + ' : ref => {\n' + values + '\n} }\n}\n'
            )
            (fixture / "test.auto.tfvars.json").write_text(json.dumps({"cloud_args": cloud_args}))
            result = subprocess.run(
                [TERRAFORM, "console", "-no-color"], cwd=fixture,
                input="jsonencode(local.grants)\n", text=True, capture_output=True, check=True,
            )
        return json.loads(json.loads(result.stdout))

    def test_only_requested_secrets_get_spark_access(self):
        shared = "projects/test-project/secrets/uc-client-secret"
        other = "projects/other-project/secrets/uc-client-secret"
        actual = self.grants({
            "project_id": "test-project",
            "extra_secret_ids": ["hub-only"],
            "spark_secret_ids": ["", "uc-client-secret", "test-project/uc-client-secret", shared,
                                 "other-project/uc-client-secret", other],
        })
        self.assertEqual(actual, {
            ref: {"secret_id": ref, "role": "roles/secretmanager.secretAccessor",
                  "member": "serviceAccount:spark@test-project.iam.gserviceaccount.com"}
            for ref in (shared, other)
        })

    def test_no_spark_access_without_explicit_secret_refs(self):
        for extras in ({}, {"spark_secret_ids": []}):
            with self.subTest(extras=extras):
                self.assertEqual(self.grants({"project_id": "test-project",
                                              "extra_secret_ids": ["hub-only"], **extras}), {})


if __name__ == "__main__":
    unittest.main()
