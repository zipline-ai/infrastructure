"""Validate Databricks secret references using provider-free Terraform plans."""
import unittest

import test_auth_inputs


class DatabricksInputsTest(unittest.TestCase):
    plan = test_auth_inputs.AuthInputsTest.plan
    references = {
        "databricks_client_id": "test-client",
        "databricks_client_secret_arn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:client-AbCdEf",
        "databricks_credential_arn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:credential-AbCdEf",
    }

    def test_reject_plaintext_field_even_when_disabled(self):
        for value in ("test-only", "", None):
            with self.subTest(value=value):
                result = self.plan({"databricks_client_secret": value})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("aws.databricks_client_secret is no longer supported", result.stderr)

    def test_accept_both_references(self):
        result = self.plan(self.references)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_require_both_valid_references_when_enabled(self):
        for key in ("databricks_client_secret_arn", "databricks_credential_arn"):
            for value in (None, "", "plaintext", "arn:aws:ssm:us-east-1:123456789012:parameter/client"):
                with self.subTest(key=key, value=value):
                    result = self.plan({**self.references, key: value})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Databricks requires", result.stderr)

    def test_disabled_databricks_needs_no_references(self):
        result = self.plan({})
        self.assertEqual(result.returncode, 0, result.stderr)
