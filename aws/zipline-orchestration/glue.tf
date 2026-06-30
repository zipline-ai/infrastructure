resource "aws_glue_registry" "zipline" {
  count         = local.cloud_args.glue_schema_registry_name == "" ? 1 : 0
  registry_name = local.glue_registry_name
}
