"""Run GCP auth input validation without cloud providers or credentials.

Usage: TERRAFORM=/path/to/tofu python3 -m unittest discover -s tests -v
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GCP = ROOT / "gcp/zipline-orchestration"
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("tofu") or shutil.which("terraform")
PROJECT = "test-project"
FULL_ID = "projects/other-project/secrets/zipline-acme-auth"


class GcpAuthInputsTest(unittest.TestCase):
    def plan(self, gcp=None, orchestration=None):
        source = (GCP / "main.tf").read_text().split('module "zipline_orchestration"')[0]
        locals_source = (GCP / "locals.tf").read_text()
        id_expression = locals_source.split("  auth_secret_id = ", 1)[1].split("\n\n", 1)[0]
        secrets_source = (GCP / "secrets.tf").read_text()
        grants_expression = secrets_source.split("  secret_ids_to_grant = ", 1)[1].split("\n}", 1)[0]
        source += ('\nlocals {\n'
                   '  cloud_args = merge({ auth_secret_id = "", extra_secret_ids = [] }, var.gcp)\n'
                   '  auth_enabled = try(var.orchestration.auth.enabled, false)\n'
                   '  auth_secret_id = ' + id_expression + '\n'
                   '  extra_external_secret_ids = []\n'
                   '  secret_ids_to_grant = ' + grants_expression + '\n}\n'
                   'output "secret_ids_to_grant" { value = local.secret_ids_to_grant }\n')
        with tempfile.TemporaryDirectory(prefix="gcp-auth-inputs-") as directory:
            path = Path(directory)
            (path / "main.tf").write_text(source)
            (path / "test.auto.tfvars.json").write_text(json.dumps({
                "gcp": {"project_id": PROJECT, "region": "us-central1", **(gcp or {})},
                "orchestration": orchestration or {},
            }))
            subprocess.run([TERRAFORM, "init", "-backend=false"], cwd=path,
                           check=True, capture_output=True)
            result = subprocess.run([TERRAFORM, "plan", "-input=false", "-no-color", "-out=plan"],
                                    cwd=path, capture_output=True, text=True)
            grants = None
            if result.returncode == 0:
                shown = subprocess.run([TERRAFORM, "show", "-json", "plan"], cwd=path,
                                       check=True, capture_output=True, text=True)
                grants = json.loads(shown.stdout)["planned_values"]["outputs"]["secret_ids_to_grant"]["value"]
            return result, grants

    def test_auth_secret_id_is_granted(self):
        for value, expected in (("zipline-acme-auth", f"projects/{PROJECT}/secrets/zipline-acme-auth"),
                                (FULL_ID, FULL_ID)):
            with self.subTest(value=value):
                result, grants = self.plan({"auth_secret_id": value}, {"auth": {"enabled": True}})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(grants, [expected])

    def test_shared_secrets_arn_fallback(self):
        result, grants = self.plan({}, {"auth": {"enabled": True, "secrets_arn": "zipline-acme-auth"}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(grants, [f"projects/{PROJECT}/secrets/zipline-acme-auth"])

    def test_auth_requires_secret_id(self):
        for value in ("", "has spaces", "projects/p/secrets/"):
            with self.subTest(value=value):
                result, _ = self.plan({"auth_secret_id": value}, {"auth": {"enabled": True}})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("set gcp.auth_secret_id", result.stderr)

    def test_disabled_auth_needs_no_id_and_grants_nothing(self):
        result, grants = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(grants, [])

    def test_stack_never_creates_auth_secret(self):
        sources = "\n".join(path.read_text() for path in GCP.glob("*.tf"))
        self.assertNotIn('resource "google_secret_manager_secret" "auth"', sources)
        self.assertNotIn("google_secret_manager_secret_version.auth", sources)
        removed = re.search(r"removed \{\s*from = google_secret_manager_secret\.auth\s*"
                            r"lifecycle \{\s*destroy = false\s*\}\s*\}", sources)
        self.assertIsNotNone(removed)

    def test_grants_cover_auth_and_wait_for_secret_manager_api(self):
        secrets_source = (GCP / "secrets.tf").read_text()
        for name in ("orchestration_extras", "eso_extras"):
            with self.subTest(resource=name):
                block = secrets_source.split(
                    f'resource "google_secret_manager_secret_iam_member" "{name}" {{', 1)[1].split("\n}", 1)[0]
                self.assertIn("for_each = toset(local.secret_ids_to_grant)", block)
                self.assertIn("depends_on = [google_project_service.required]", block)
        module_block = (GCP / "main.tf").read_text().split('module "zipline_orchestration"', 1)[1]
        self.assertIn("google_secret_manager_secret_iam_member.eso_extras", module_block)


if __name__ == "__main__":
    unittest.main()
