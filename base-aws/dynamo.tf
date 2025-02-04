resource "aws_dynamodb_table" "groupby_batch" {
  name = "GROUPBY_BATCH"
  read_capacity = 20
  write_capacity = 20
  attribute {
    name = "cf"
    type = "S"
  }
  hash_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "groupby_streaming" {
  name = "GROUPBY_STREAMING"
  read_capacity = 20
  write_capacity = 20
  attribute {
    name = "cf"
    type = "S"
  }
  hash_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "tile_summaries" {
  name = "TILE_SUMMARIES"
  read_capacity = 20
  write_capacity = 20
  attribute {
    name = "cf"
    type = "S"
  }
  hash_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "chronon_metadata" {
  name = "CHRONON_METADATA"
  read_capacity = 20
  write_capacity = 20
  attribute {
    name = "cf"
    type = "S"
  }
  hash_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "entity_keys_by_team" {
  name = "ENTITY_KEYS_BY_TEAM"
  read_capacity = 20
  write_capacity = 20
  attribute {
    name = "cf"
    type = "S"
  }
  hash_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "groupby_ingest" {
  name = "GROUPBY_INGEST"
  read_capacity = 20
  write_capacity = 20
  attribute {
    name = "cf"
    type = "S"
  }
  hash_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
