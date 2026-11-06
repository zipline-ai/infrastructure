"""Evaluate GCP pool defaults and autoscaling expressions without cloud access."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM", "terraform")


class GcpNodePoolAutoscalingTest(unittest.TestCase):
    def test_driver_can_use_capacity_in_any_zone(self):
        source = (ROOT / "gcp/zipline-orchestration/gke.tf").read_text()
        defaults = source.split('# Service account used by node VMs.')[0]
        scaling = source.split('  autoscaling {', 1)[1].split('\n  }', 1)[0]
        scaling = scaling.replace('each.value', 'pool')
        fixture = '''locals {
          name_prefix = "test"
          cloud_args = {
            cluster_name = "test"
            system_machine_type = "n2-standard-16"
            compute_machine_type = "c4a-standard-8"
            executor_machine_type = "c4a-standard-8-lssd"
          }
        }
        ''' + defaults + '''
        output "pools" { value = local.node_pools }
        output "scaling" {
          value = { for name, pool in local.node_pools : name => {
        ''' + scaling + '\n} }\n}\n'
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'main.tf').write_text(fixture)
            subprocess.run([TERRAFORM, 'init', '-backend=false'], cwd=directory,
                           check=True, capture_output=True)
            subprocess.run([TERRAFORM, 'plan', '-out=test.tfplan'], cwd=directory,
                           check=True, capture_output=True)
            result = subprocess.run([TERRAFORM, 'show', '-json', 'test.tfplan'],
                                    cwd=directory, check=True, capture_output=True, text=True)
        outputs = json.loads(result.stdout)['planned_values']['outputs']
        self.assertEqual(outputs['pools']['value']['spark-driver']['initial_count'], 0)
        driver = outputs['scaling']['value']['spark-driver']
        self.assertEqual(driver['location_policy'], 'ANY')
        self.assertEqual(driver['total_min_node_count'], 1)
        self.assertEqual(driver['total_max_node_count'], 30)
        self.assertIsNone(driver['min_node_count'])
        self.assertIsNone(driver['max_node_count'])
        for name, pool in outputs['scaling']['value'].items():
            if name != 'spark-driver':
                self.assertIsNotNone(pool['min_node_count'])
                self.assertIsNotNone(pool['max_node_count'])
                self.assertIsNone(pool['total_min_node_count'])
                self.assertIsNone(pool['total_max_node_count'])
                self.assertIsNone(pool['location_policy'])
