# Preserve previously provisioned auth secrets while transferring ownership out
# of Terraform. Existing installs must supply the retained secret's ARN.
removed {
  from = aws_secretsmanager_secret.zipline_auth
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_secretsmanager_secret_version.zipline_auth
  lifecycle {
    destroy = false
  }
}

removed {
  from = random_password.zipline_auth
  lifecycle {
    destroy = false
  }
}

# Retain existing Databricks secrets and versions when switching to ARN inputs.
removed {
  from = aws_secretsmanager_secret.databricks_client_secret
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_secretsmanager_secret_version.databricks_client_secret
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_secretsmanager_secret.databricks_credential
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_secretsmanager_secret_version.databricks_credential
  lifecycle {
    destroy = false
  }
}
