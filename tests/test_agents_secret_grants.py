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
    def grants(self, cloud, enabled, extra_config=None):
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
        if cloud == "gcp":
            expression = source.split("  " + name + " = ", 1)[1].split("\n}", 1)[0]
        config = {
            "orchestration": {"agents": {
                "enable": enabled,
                "anthropic_api_key_remote_ref": {"key": "anthropic-secret"},
                "openai_api_key_remote_ref": {"key": "openai-secret", "property": "key"},
                "gemini_api_key_remote_ref": {"key": "gemini-secret"},
            }},
            "cloud_args": {existing: ["existing-secret"]},
        }
        if cloud == "gcp":
            config["cloud_args"]["project_id"] = "test-project"
        if extra_config:
            config["orchestration"]["agents"].update(extra_config["agents"])
            config["cloud_args"][existing] = extra_config["extras"]
            config["orchestration"].update(extra_config.get("orchestration", {}))
            if cloud == "gcp":
                stubs = ('auth_enabled = true\nauth_secret_id = "shared"\n'
                         'extra_external_secret_ids = ["shared"]')
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
                        expected |= {"anthropic-secret", "openai-secret", "gemini-secret"}
                    if cloud == "gcp":
                        expected = {"projects/test-project/secrets/" + key for key in expected}
                    self.assertEqual(self.grants(cloud, enabled), expected)

    def test_gcp_deduplicates_secret_identity_across_providers_and_extras(self):
        shared = "projects/test-project/secrets/shared"
        other = "projects/other-project/secrets/shared"
        actual = self.grants("gcp", True, {
            "agents": {
                "anthropic_api_key_remote_ref": {"key": "shared"},
                "openai_api_key_remote_ref": {"key": shared, "property": "openai"},
                "gemini_api_key_remote_ref": {"key": "shared", "property": "gemini"},
            },
            "extras": ["shared", shared, other],
            "orchestration": {"conf_repo": {
                "url": "https://example.com/repo",
                "github_token_remote_ref": {"key": shared},
            }},
        })
        self.assertEqual(actual, {shared, other})

    def test_gcp_normalizes_project_secret_reference(self):
        actual = self.grants("gcp", False, {
            "agents": {},
            "extras": ["other-project/my-secret",
                       "projects/other-project/secrets/my-secret",
                       "test-project/shared"],
        })
        self.assertEqual(actual, {
            "projects/test-project/secrets/shared",
            "projects/other-project/secrets/my-secret",
        })
