variable "orchestration" {
  description = "Shared Zipline orchestration install inputs consumed by modules/zipline-orchestration."
  type        = any
}

variable "azure" {
  description = "Azure-specific orchestration wrapper inputs."
  type        = any
}

module "zipline_orchestration" {
  source = "../../modules/zipline-orchestration"

  orchestration    = var.orchestration
  provider_context = local.provider_context
}
