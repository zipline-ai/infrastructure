resource "aws_dynamodb_table" "groupby_batch" {
  name = "GROUPBY_BATCH"
  attribute {
    name = "cf"
    type = "S"
  }
  range_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "groupby_streaming" {
  name = "GROUPBY_STREAMING"
  attribute {
    name = "cf"
    type = "S"
  }
  range_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "tile_summaries" {
  name = "TILE_SUMMARIES"
  attribute {
    name = "cf"
    type = "S"
  }
  range_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "chronon_metadata" {
  name = "CHRONON_METADATA"
  attribute {
    name = "cf"
    type = "S"
  }
  range_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "entity_keys_by_team" {
  name = "ENTITY_KEYS_BY_TEAM"
  attribute {
    name = "cf"
    type = "S"
  }
  range_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "groupby_ingest" {
  name = "GROUPBY_INGEST"
  attribute {
    name = "cf"
    type = "S"
  }
  range_key = "cf"
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
