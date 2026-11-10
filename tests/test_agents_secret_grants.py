"""Evaluate the production AWS/GCP grant lists without cloud credentials."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("terraform")


class AgentsSecretGrantsTest(unittest.TestCase):
    def grants(self, cloud, enabled):
        if cloud == "aws":
            path, name = "locals.tf", "extra_external_secret_arns"
            stubs = 'redis_password_enabled = false\nredis_password_secret_arn = ""\nextra_external_secrets = []'
            existing = "extra_secret_arns"
        else:
            path, name = "secrets.tf", "secret_ids_to_grant"
            stubs = 'auth_enabled = false\nauth_secret_id = ""\nextra_external_secret_ids = []'
            existing = "extra_secret_ids"
        source = (ROOT / cloud / "zipline-orchestration" / path).read_text()
        expression = source.split("  " + name + " = ", 1)[1].split("\n  )))", 1)[0] + "\n  )))"
        config = {
            "orchestration": {"agents": {
                "enable": enabled,
                "anthropic_api_key_remote_ref": {"key": "anthropic-secret"},
                "openai_api_key_remote_ref": {"key": "openai-secret", "property": "key"},
            }},
            "cloud_args": {existing: ["existing-secret"]},
        }
        with tempfile.TemporaryDirectory(prefix="agents-secret-grants-") as directory:
            fixture = Path(directory)
            (fixture / "main.tf").write_text('variable "orchestration" { type = any }\n'
                                             'variable "cloud_args" { type = any }\n'
                                             'locals {\ncloud_args = var.cloud_args\n' + stubs +
                                             '\ngrants = ' + expression + '\n}\n')
            (fixture / "test.auto.tfvars.json").write_text(json.dumps(config))
            result = subprocess.run([TERRAFORM, "console", "-no-color"], cwd=fixture,
                                    input="jsonencode(local.grants)\n", text=True,
                                    capture_output=True, check=True)
        return set(json.loads(json.loads(result.stdout)))

    def test_provider_grants_follow_agents_flag(self):
        for cloud in ("aws", "gcp"):
            for enabled in (False, True):
                with self.subTest(cloud=cloud, enabled=enabled):
                    expected = {"existing-secret"}
                    if enabled:
                        expected |= {"anthropic-secret", "openai-secret"}
                    self.assertEqual(self.grants(cloud, enabled), expected)
