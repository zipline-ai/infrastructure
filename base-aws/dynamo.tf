resource "aws_dynamodb_table" "chronon_metadata" {
  name           = "CHRONON_METADATA"
  read_capacity  = 10
  write_capacity = 10
  attribute {
    name = "keyBytes"
    type = "S"
  }
  hash_key = "keyBytes"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "entity_keys_by_team" {
  name           = "ENTITY_KEYS_BY_TEAM"
  read_capacity  = 10
  write_capacity = 10
  attribute {
    name = "keyBytes"
    type = "S"
  }
  hash_key = "keyBytes"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}