locals {
  fetcher_ooc = local.deploy_fetcher ? try(var.aws.fetcher_ooc, null) : null
  fetcher_ooc_topic_info = local.fetcher_ooc == null ? null : join("/", [
    "kafka://${local.fetcher_ooc.topic}",
    "bootstrap=${data.aws_msk_cluster.fetcher_ooc[0].bootstrap_brokers_sasl_iam}",
    "security.protocol=SASL_SSL",
    "sasl.mechanism=AWS_MSK_IAM",
    "sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;",
    "sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler",
  ])
}

data "aws_msk_cluster" "fetcher_ooc" {
  count        = local.fetcher_ooc == null ? 0 : 1
  cluster_name = local.fetcher_ooc.cluster_name
}

data "aws_iam_policy_document" "fetcher_ooc" {
  count = local.fetcher_ooc == null ? 0 : 1

  statement {
    actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently"]
    resources = [data.aws_msk_cluster.fetcher_ooc[0].arn]
  }

  statement {
    actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
    resources = ["${replace(data.aws_msk_cluster.fetcher_ooc[0].arn, ":cluster/", ":topic/")}/${local.fetcher_ooc.topic}"]
  }
}

resource "aws_iam_role_policy" "fetcher_ooc" {
  count  = local.fetcher_ooc == null ? 0 : 1
  name   = "${local.name_prefix}-fetcher-ooc-producer"
  role   = aws_iam_role.orchestration_irsa.id
  policy = data.aws_iam_policy_document.fetcher_ooc[0].json
}
