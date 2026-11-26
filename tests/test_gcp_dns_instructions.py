"""Check DNS guidance using the controller's effective IP without cloud access."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = os.environ.get("TERRAFORM", "terraform")


class GcpDnsInstructionsTest(unittest.TestCase):
    def test_controller_ip_and_reserved_fallback(self):
        source = (ROOT / "gcp/zipline-orchestration/outputs.tf").read_text()
        source = source[source.index('output "ingress_dns_instructions"'):]
        source = source.replace('module.zipline_orchestration.ingress_load_balancer_ip', 'var.controller_ip')
        fixture = '''variable "controller_ip" { type = string }
variable "orchestration" { type = any }
locals {
  ingress_lb_ip = "203.0.113.10"
  external_ingress_controller = try(var.orchestration.ingress.external_controller, false)
}
''' + source
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'main.tf').write_text(fixture)
            subprocess.run([TERRAFORM, 'init', '-backend=false'], cwd=directory,
                           check=True, capture_output=True)
            for domain in ('zipline.example.com', ''):
                for controller_ip, expected_ip in (('203.0.113.20', '203.0.113.20'),
                                                   ('', '203.0.113.10'),
                                                   (None, '203.0.113.10')):
                    with self.subTest(domain=domain, controller_ip=controller_ip):
                        Path(directory, 'test.auto.tfvars.json').write_text(json.dumps({
                            'controller_ip': controller_ip,
                            'orchestration': {'ingress': {'domain': domain}},
                        }))
                        subprocess.run([TERRAFORM, 'plan', '-out=test.tfplan'], cwd=directory,
                                       check=True, capture_output=True)
                        result = subprocess.run([TERRAFORM, 'show', '-json', 'test.tfplan'],
                                                cwd=directory, check=True, capture_output=True, text=True)
                        value = json.loads(result.stdout)['planned_values']['outputs']['ingress_dns_instructions']['value']
                        self.assertIn(expected_ip, value)
                        if domain:
                            self.assertIn('DNS A record for ' + domain, value)
                        else:
                            self.assertIn('No ingress domain is configured.', value)

            Path(directory, 'test.auto.tfvars.json').write_text(json.dumps({
                'controller_ip': None,
                'orchestration': {
                    'ingress': {'domain': 'zipline.example.com', 'external_controller': True},
                },
            }))
            subprocess.run([TERRAFORM, 'plan', '-out=test.tfplan'], cwd=directory,
                           check=True, capture_output=True)
            result = subprocess.run([TERRAFORM, 'show', '-json', 'test.tfplan'],
                                    cwd=directory, check=True, capture_output=True, text=True)
            value = json.loads(result.stdout)['planned_values']['outputs']['ingress_dns_instructions']['value']
            self.assertEqual(value, 'Point DNS for zipline.example.com to your ingress controller.')
