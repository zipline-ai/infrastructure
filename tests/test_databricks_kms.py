"""Render the production Databricks IAM policy using mocked AWS metadata."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TF = os.environ.get("TERRAFORM", "terraform")
SECRET = "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-AbCdEf"
KEY = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-4234-8234-123456789012"


class DatabricksKmsTest(unittest.TestCase):
    def test_kms_permissions_follow_secret_metadata(self):
        wrapper = ROOT / "aws/zipline-orchestration"
        policy = (wrapper / "irsa.tf").read_text().split('resource "aws_iam_policy" "databricks_secrets_policy"', 1)[1].split('# Flink compute pods', 1)[0]
        source = (wrapper / "databricks.tf").read_text()
        source += 'resource "aws_iam_policy" "databricks_secrets_policy"' + policy
        source += '''
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
locals {
  name_prefix = "test"
  cloud_args = {
    databricks_client_id = "test-client"
    databricks_client_secret_arn = "SECRET"
    databricks_credential_arn = "CREDENTIAL"
  }
}
'''.replace("CREDENTIAL", SECRET.replace("client", "credential")).replace("SECRET", SECRET)
        test = '''
mock_provider "aws" {
  mock_data "aws_kms_key" {
    defaults = { arn = "KEY", key_manager = "CUSTOMER" }
  }
}
override_data {
  target = data.aws_secretsmanager_secret.databricks["client_secret"]
  values = { id = "SECRET", arn = "SECRET", kms_key_id = "" }
}
override_data {
  target = data.aws_secretsmanager_secret.databricks["credential"]
  values = { id = "CREDENTIAL", arn = "CREDENTIAL", kms_key_id = "" }
}
run "default_key_needs_no_extra_grant" {
  command = plan
  assert {
    condition = length(jsondecode(aws_iam_policy.databricks_secrets_policy[0].policy).Statement) == 1
    error_message = "Default encryption must not add KMS grants."
  }
}
run "customer_key_gets_scoped_decrypt" {
  command = plan
  override_data {
    target = data.aws_secretsmanager_secret.databricks["client_secret"]
    values = { id = "SECRET", arn = "SECRET", kms_key_id = "alias/databricks" }
  }
  assert {
    condition = length([for s in jsondecode(aws_iam_policy.databricks_secrets_policy[0].policy).Statement : s if contains(s.Action, "kms:Decrypt")]) == 1
    error_message = "A customer key requires a decrypt grant."
  }
  assert {
    condition = alltrue([for s in jsondecode(aws_iam_policy.databricks_secrets_policy[0].policy).Statement :
      s.Resource == ["KEY"] && s.Action == ["kms:Decrypt"] &&
      s.Condition.StringEquals["kms:ViaService"] == "secretsmanager.us-east-1.amazonaws.com" &&
      s.Condition.StringEquals["kms:EncryptionContext:SecretARN"] == "SECRET"
      if contains(s.Action, "kms:Decrypt")])
    error_message = "Decrypt must be scoped to the canonical key ARN, Secrets Manager, and the secret."
  }
}
run "explicit_aws_managed_key_gets_no_grant" {
  command = plan
  override_data {
    target = data.aws_secretsmanager_secret.databricks["client_secret"]
    values = { id = "SECRET", arn = "SECRET", kms_key_id = "alias/aws/secretsmanager" }
  }
  override_data {
    target = data.aws_kms_key.databricks["client_secret"]
    values = { arn = "KEY", key_manager = "AWS" }
  }
  assert {
    condition = length(jsondecode(aws_iam_policy.databricks_secrets_policy[0].policy).Statement) == 1
    error_message = "An explicitly configured AWS-managed key must not receive a grant."
  }
}
run "two_customer_keys_keep_separate_secret_scopes" {
  command = plan
  override_data {
    target = data.aws_secretsmanager_secret.databricks["client_secret"]
    values = { id = "SECRET", arn = "SECRET", kms_key_id = "alias/databricks-client" }
  }
  override_data {
    target = data.aws_secretsmanager_secret.databricks["credential"]
    values = { id = "CREDENTIAL", arn = "CREDENTIAL", kms_key_id = "KEY2" }
  }
  override_data {
    target = data.aws_kms_key.databricks["credential"]
    values = { arn = "KEY2", key_manager = "CUSTOMER" }
  }
  assert {
    condition = length([for s in jsondecode(aws_iam_policy.databricks_secrets_policy[0].policy).Statement : s if contains(s.Action, "kms:Decrypt")]) == 2
    error_message = "Both customer keys need decrypt grants."
  }
  assert {
    condition = alltrue([for s in jsondecode(aws_iam_policy.databricks_secrets_policy[0].policy).Statement :
      s.Resource == [s.Condition.StringEquals["kms:EncryptionContext:SecretARN"] == "SECRET" ? "KEY" : "KEY2"] &&
      contains(["SECRET", "CREDENTIAL"], s.Condition.StringEquals["kms:EncryptionContext:SecretARN"]) &&
      s.Condition.StringEquals["kms:ViaService"] == "secretsmanager.us-east-1.amazonaws.com"
      if contains(s.Action, "kms:Decrypt")])
    error_message = "Each key must be bound to its own secret."
  }
}
'''.replace("CREDENTIAL", SECRET.replace("client", "credential")).replace("SECRET", SECRET).replace("KEY2", KEY[:-1] + "3").replace("KEY", KEY)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "main.tf").write_text(source)
            (path / "kms.tftest.hcl").write_text(test)
            init = [TF, "init", "-backend=false", "-input=false", "-no-color"]
            cache = wrapper / ".terraform/providers"
            if cache.is_dir():
                init.append(f"-plugin-dir={cache}")
            result = subprocess.run(init, cwd=path, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([TF, "test", "-no-color"], cwd=path, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
