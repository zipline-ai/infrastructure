"""Evaluate GCP's actual StarRocks values without providers or cloud credentials.

Requires Terraform/OpenTofu, or TERRAFORM pointing to its executable.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM") or shutil.which("tofu") or shutil.which("terraform")


class GcpDataExplorerTest(unittest.TestCase):
    def test_native_storage_and_pod_identity(self):
        self.assertTrue(TERRAFORM, "Install Terraform/OpenTofu or set TERRAFORM")
        source = (ROOT / "gcp/zipline-orchestration/locals.tf").read_text()
        starrocks = source.split("  provider_values = {", 1)[1].split("\n    polaris = {", 1)[0]
        with tempfile.TemporaryDirectory(prefix="gcp-data-explorer-") as directory:
            fixture = Path(directory)
            # Evaluate production HCL with stand-ins for the wrapper's inputs.
            (fixture / "main.tf").write_text('''
locals {
  cloud_args = {
    warehouse_bucket = "test-warehouse"
    region = "us-central1"
    storage_class = "premium-rwo"
  }
  orchestration_service_account = "test-orchestration"
  system_node_selector = { "zipline.ai/node-pool" = "system" }
  system_node_tolerations = []
  provider_values = {
''' + starrocks + "\n  }\n}\n")
            result = subprocess.run(
                [TERRAFORM, "console", "-no-color"], cwd=fixture,
                input="jsonencode(local.provider_values.starrocks)\n",
                text=True, capture_output=True, check=True,
            )
        values = json.loads(json.loads(result.stdout))
        config = values["feConfig"]
        self.assertEqual(config["cloud_native_storage_type"], "GS")
        self.assertEqual(config["gcp_gcs_path"], "test-warehouse/dataexplorer")
        self.assertTrue(config["gcp_gcs_use_compute_engine_service_account"])
        self.assertTrue(config["enable_load_volume_from_conf"])
        self.assertEqual(config["run_mode"], "shared_data")
        self.assertFalse(any(key.startswith("aws_s3_") for key in config))
        self.assertFalse(any("private_key" in key or "secret" in key for key in config))
        self.assertEqual(values["serviceAccount"], "test-orchestration")
        self.assertEqual(values["persistence"]["storageClass"], "premium-rwo")
        self.assertFalse(values["awsGlueCatalog"]["enabled"])


if __name__ == "__main__":
    unittest.main()
