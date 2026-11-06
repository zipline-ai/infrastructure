"""Plan the actual database resources with mocked cloud providers.

Requires Terraform >= 1.9 on PATH (or TERRAFORM). No cloud credentials used.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM", shutil.which("terraform"))


@unittest.skipUnless(TERRAFORM, "Terraform >= 1.9 required for database replica plans")
class DatabaseReplicaTests(unittest.TestCase):
    def test_replica_plans(self):
        for cloud in ("aws", "azure"):
            with self.subTest(cloud=cloud), tempfile.TemporaryDirectory() as directory:
                fixture = Path(directory)
                source = ROOT / cloud / "zipline-orchestration"
                provider = "aws" if cloud == "aws" else "azurerm"
                version = "~> 5.0" if cloud == "aws" else "~> 3.117"
                defaults = (source / "locals.tf").read_text().split(f'}}, var.{cloud})', 1)[0]
                (fixture / "defaults.tf").write_text(defaults + f'}}, var.{cloud})\n}}\n')
                database = "rds.tf" if cloud == "aws" else "postgres.tf"
                shutil.copy(source / database, fixture / database)
                outputs = (source / "outputs.tf").read_text()
                name = "rds_read_replica_endpoint" if cloud == "aws" else "postgres_read_replica_fqdn"
                (fixture / "outputs.tf").write_text('output "' + name + '"' + outputs.split('output "' + name + '"', 1)[1])
                shared = '''
locals { name_prefix = "replica-test" }
variable "%s" {
  type = any
  default = {}
}
terraform {
  required_providers {
    %s = { source = "hashicorp/%s", version = "%s" }
    random = { source = "hashicorp/random", version = ">= 3.6.0" }
  }
}
''' % (cloud, provider, provider, version)
                if cloud == "aws":
                    shared += '''
locals {
  resolved_primary_subnet_id = "subnet-0123456789abcdef0"
  resolved_secondary_subnet_id = "subnet-0123456789abcdef1"
}
resource "aws_security_group" "zipline" { name = "replica-test" }
'''
                else:
                    shared += '''
locals {
  cluster_name = "replica-test"
  database_server_name = "replica-test"
  database_location = "eastus"
  database_name = "execution_info"
}
resource "random_password" "db_password" { length = 16 }
resource "azurerm_resource_group" "main" {
  name = "replica-test"
  location = "eastus"
}
resource "azurerm_virtual_network" "main" {
  name = "replica-test"
  resource_group_name = azurerm_resource_group.main.name
  location = "eastus"
  address_space = ["10.0.0.0/16"]
}
resource "azurerm_subnet" "private_endpoints" {
  name = "endpoints"
  resource_group_name = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes = ["10.0.1.0/24"]
}
'''
                (fixture / "main.tf").write_text(shared)
                resource = "aws_db_instance.read_replica" if cloud == "aws" else "azurerm_postgresql_flexible_server.read_replica"
                test = f'mock_provider "{provider}" {{}}\nmock_provider "random" {{}}\n'
                if cloud == "aws":
                    test += '''override_resource {
  target = aws_db_instance.zipline
  values = { arn = "arn:aws:rds:us-east-1:123456789012:db:replica-test" }
}
'''
                if cloud == "azure":
                    test += '''run "general_purpose_without_replica" {
  command = plan
  assert {
    condition = azurerm_postgresql_flexible_server.main.sku_name == "GP_Standard_D2ds_v5" && length(azurerm_private_endpoint.postgres_read_replica) == 0
    error_message = "General Purpose must be the default even without a replica."
  }
}
'''
                test += f'''
run "disabled_by_default" {{
  command = plan
  assert {{
    condition = length({resource}) == 0 && output.{name} == null
    error_message = "Replicas must be opt-in and their output null when disabled."
  }}
}}
run "enabled" {{
  command = plan
  variables {{ {cloud} = {{ database_read_replica_enabled = true }} }}
  assert {{
    condition = length({resource}) == 1
    error_message = "Enabling replicas must create one replica."
  }}
'''
                if cloud == "aws":
                    test += '''
  assert {
    condition = !aws_db_instance.read_replica[0].publicly_accessible && aws_db_instance.read_replica[0].instance_class == aws_db_instance.zipline.instance_class
    error_message = "Replica must remain private."
  }
}
run "backups_required" {
  command = plan
  variables { aws = { database_read_replica_enabled = true, database_backup_retention_days = 0 } }
  expect_failures = [aws_db_instance.read_replica[0]]
}
'''
                else:
                    test += '''
  assert {
    condition = azurerm_postgresql_flexible_server.main.sku_name == "GP_Standard_D2ds_v5" && azurerm_postgresql_flexible_server.read_replica[0].sku_name == azurerm_postgresql_flexible_server.main.sku_name
    error_message = "Both servers must use the General Purpose default."
  }
  assert {
    condition = azurerm_postgresql_flexible_server.read_replica[0].create_mode == "Replica" && !azurerm_postgresql_flexible_server.read_replica[0].public_network_access_enabled && length(azurerm_private_endpoint.postgres_read_replica) == 1
    error_message = "Replica must use replication with a private endpoint."
  }
}
run "burstable_rejected" {
  command = plan
  variables { azure = { database_read_replica_enabled = true, database_sku_name = "B_Standard_B1ms" } }
  expect_failures = [azurerm_postgresql_flexible_server.read_replica[0]]
}
run "external_host_rejected" {
  command = plan
  variables { azure = { database_read_replica_enabled = true, database_host = "external.example.com" } }
  expect_failures = [azurerm_postgresql_flexible_server.read_replica[0]]
}
'''
                (fixture / "replicas.tftest.hcl").write_text(test)
                init = [TERRAFORM, "init", "-backend=false", "-input=false", "-no-color"]
                plugins = source / ".terraform/providers"
                if plugins.exists():
                    init.append(f"-plugin-dir={plugins}")
                for command in (init, [TERRAFORM, "test", "-no-color"]):
                    result = subprocess.run(command, cwd=fixture, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
