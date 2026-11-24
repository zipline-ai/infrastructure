"""Run AWS input validation without cloud providers or credentials.

Usage: TERRAFORM=/path/to/terraform python3 -m unittest discover -s tests -v
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM", "terraform")
ARN = "arn:aws:secretsmanager:us-east-1:123456789012:secret:auth-AbCdEf"


class AuthInputsTest(unittest.TestCase):
    def plan(self, aws, orchestration=None):
        source = (ROOT / "aws/zipline-orchestration/main.tf").read_text()
        source = source.split('module "zipline_orchestration"')[0]
        locals_source = (ROOT / "aws/zipline-orchestration/locals.tf").read_text()
        arn_expression = locals_source.split("  auth_secret_arn =", 1)[1].split("\n\n", 1)[0]
        source += ('\nlocals {\n'
                   '  cloud_args = merge({ auth_secret_arn = "" }, var.aws)\n'
                   # Shared configuration validation also reads Redis settings.
                   '  redis = { enabled = false, password_secret_arn = "", shards = 1, replicas_per_shard = 0 }\n'
                   '  redis_managed = false\n'
                   '  auth_enabled = try(var.orchestration.auth.enabled, false)\n'
                   '  auth_secret_arn =' + arn_expression + '\n}\n'
                   'output "auth_secret_arn" { value = local.auth_secret_arn }\n')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "main.tf").write_text(source)
            (path / "test.auto.tfvars.json").write_text(json.dumps({
                "aws": {"region": "us-east-1", "warehouse_bucket": "test", **aws},
                "orchestration": orchestration or {},
            }))
            subprocess.run([TERRAFORM, "init", "-backend=false"], cwd=path,
                           check=True, capture_output=True)
            return subprocess.run([TERRAFORM, "plan", "-input=false", "-no-color"],
                                  cwd=path, capture_output=True, text=True)

    def test_plaintext_input_rejected_even_when_empty_or_auth_disabled(self):
        for value in ({"auth_secret": "test-only"}, {}, None):
            with self.subTest(value=value):
                result = self.plan({"auth_secret_values": value})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("aws.auth_secret_values is no longer supported", result.stderr)

    def test_aws_arn_accepted(self):
        result = self.plan({"auth_secret_arn": ARN}, {"auth": {"enabled": True}})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_shared_arn_fallback(self):
        result = self.plan({}, {"auth": {"enabled": True, "secrets_arn": ARN}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(ARN, result.stdout)

    def test_aws_arn_takes_precedence(self):
        result = self.plan({"auth_secret_arn": ARN},
                           {"auth": {"enabled": True, "secrets_arn": "invalid"}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(ARN, result.stdout)

    def test_auth_requires_secrets_manager_arn(self):
        for value in ("", "plaintext", "arn:aws:ssm:us-east-1:123456789012:parameter/auth"):
            with self.subTest(value=value):
                result = self.plan({"auth_secret_arn": value}, {"auth": {"enabled": True}})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("valid AWS Secrets Manager secret ARN", result.stderr)

    def test_disabled_auth_needs_no_arn(self):
        result = self.plan({})
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
