"""Check AWS destroy ordering: python3 -m unittest discover -s tests."""

from pathlib import Path
import re
import unittest


TEARDOWN = Path(__file__).resolve().parents[1] / "aws/zipline-orchestration/teardown.tf"


def cleanup_depends_on():
    text = TEARDOWN.read_text()
    block = text[text.index('resource "terraform_data" "controller_resource_cleanup"'):]
    deps = block[block.index("depends_on = ["):]
    deps = deps[:deps.index("]")]
    return set(re.findall(r"^\s*([a-z0-9_.]+),", deps, re.MULTILINE))


class AwsTeardownOrderTest(unittest.TestCase):
    # Destroy removes these only after the hook drains Karpenter nodes and the NLB.
    # Without the edge they went in tofu's first wave, Karpenter nodes went
    # NotReady, and the hub-chart uninstall timed out with the cluster still up.
    def test_cleanup_outlives_node_and_controller_access(self):
        required = {
            "aws_eks_access_entry.karpenter_node",
            "aws_iam_instance_profile.karpenter_node",
            "aws_iam_role_policy_attachment.karpenter_node_worker",
            "aws_iam_role_policy_attachment.karpenter_node_cni",
            "aws_iam_role_policy_attachment.karpenter_node_registry",
            "aws_iam_role_policy_attachment.karpenter_node_ssm",
            "aws_iam_role_policy_attachment.aws_lb_controller",
            "aws_vpc_security_group_egress_rule.zipline_allow_all",
            "aws_security_group_rule.eks_cluster_ingress_https",
        }
        self.assertEqual(required - cleanup_depends_on(), set())


if __name__ == "__main__":
    unittest.main()
