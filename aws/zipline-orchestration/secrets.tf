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
