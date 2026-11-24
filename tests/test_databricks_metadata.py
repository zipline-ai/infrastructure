"""Exercise production metadata lookup postconditions with Terraform mock data."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TF = os.environ.get("TERRAFORM", "terraform")
ARN = "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-AbCdEf"


class DatabricksMetadataTest(unittest.TestCase):
    def test_resolved_arn_must_match_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            source = (ROOT / "aws/zipline-orchestration/databricks.tf").read_text()
            source += '''
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
variable "client_id" { default = "test-client" }
variable "secret_arn" { type = string }
locals {
  cloud_args = {
    databricks_client_id = var.client_id
    databricks_client_secret_arn = var.secret_arn
    databricks_credential_arn = var.secret_arn
  }
}
'''
            (path / "main.tf").write_text(source)
            (path / "metadata.tftest.hcl").write_text('''
mock_provider "aws" {}
override_data {
  target = data.aws_secretsmanager_secret.databricks["client_secret"]
  values = { id = "''' + ARN + '''", kms_key_id = "" }
}
override_data {
  target = data.aws_secretsmanager_secret.databricks["credential"]
  values = { id = "''' + ARN + '''", kms_key_id = "" }
}
variables { secret_arn = "''' + ARN + '''" }
run "matching_metadata" { command = plan }
run "partial_arn_rejected" {
  command = plan
  variables { secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:client" }
  expect_failures = [data.aws_secretsmanager_secret.databricks]
}
run "disabled_has_no_lookups" {
  command = plan
  variables { client_id = "" }
  assert {
    condition = length(data.aws_secretsmanager_secret.databricks) == 0
    error_message = "Disabled Databricks must not look up secrets."
  }
}
''')
            init = [TF, "init", "-backend=false", "-input=false", "-no-color"]
            cache = ROOT / "aws/zipline-orchestration/.terraform/providers"
            if cache.is_dir():
                init.append(f"-plugin-dir={cache}")
            result = subprocess.run(init, cwd=path, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([TF, "test", "-no-color"], cwd=path,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
