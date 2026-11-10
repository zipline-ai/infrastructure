"""Provider-free evaluation of real HCL plus Helm rendering; never creates nodes."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
AWS = ROOT / 'aws/zipline-orchestration'
TOFU = os.environ.get('TERRAFORM', 'tofu')


def evaluate(settings=None):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        source = (AWS / 'gpu-training.tf').read_text().split('data "aws_subnet"', 1)[0]
        (p / 'gpu.tf').write_text(source)
        # Existing CPU locals are evaluated alongside the new profiles.
        shutil.copyfile(AWS / 'node-pools.tf', p / 'node-pools.tf')
        plugin = (AWS / 'gpu-training.tf').read_text().split('resource "helm_release" "nvidia_device_plugin"', 1)[1]
        plugin = re.split(r'values\s*= \[yamlencode\(', plugin)[1].split(')]', 1)[0]
        (p / 'main.tf').write_text('locals {\n karpenter = { enabled = true }\n plugin = ' + plugin + '\n}')
        (p / 'terraform.tfvars.json').write_text(json.dumps({'gpu_training': settings or {}}))
        result = subprocess.run([TOFU, 'console', '-no-color'], cwd=p, text=True, capture_output=True,
            input='jsonencode({enabled=var.gpu_training.enabled,pools=local.gpu_node_pools,quota=local.gpu_quota,cpu=local.karpenter_node_pools,hardware=local.gpu_hardware,plugin=local.plugin})\n')
        if result.returncode or 'Error:' in result.stderr:
            raise ValueError(result.stderr)
        return json.loads(json.loads(result.stdout))


def render(chart, values):
    result = subprocess.run(['helm', 'template', 'test', str(chart), '-f', '-'],
        input=yaml.safe_dump(values), text=True, capture_output=True, check=True)
    return [x for x in yaml.safe_load_all(result.stdout) if x]


class GPUTrainingTest(unittest.TestCase):
    def test_disabled_keeps_cpu_specs(self):
        x = evaluate()
        self.assertFalse(x['enabled'])
        self.assertEqual(set(x['cpu']), {'system','spark-driver','spark-executor','flink','ray-control','ray-worker'})
        for name in ('ray-control', 'ray-worker'):
            req = {r['key']:r.get('values') for r in x['cpu'][name]['requirements']}
            self.assertEqual(req['kubernetes.io/arch'], ['arm64'])
            self.assertEqual(req['karpenter.k8s.aws/instance-category'], ['c','m','r'])
        self.assertEqual(x['cpu']['ray-worker']['limits'], {'cpu':'200','memory':'800Gi'})
        source = (AWS / 'gpu-training.tf').read_text()
        self.assertEqual(source.count('count     = var.gpu_training.enabled ? 1 : 0') + source.count('count      = var.gpu_training.enabled ? 1 : 0'), 3)

    def test_profiles_and_two_node_accounting(self):
        for profile, instance, nodes, cpu, memory, gpus in [
            ('s6e11-l40s','g6e.xlarge',1,'4','32Gi','1'),
            ('s6e11-a100','p4d.24xlarge',1,'96','1152Gi','8'),
            ('s6e11-a100','p4d.24xlarge',2,'192','2304Gi','16')]:
            with self.subTest(profile=profile,nodes=nodes):
                x=evaluate({'profile':profile,'instance_type':instance,'worker_nodes':nodes,
                    'multi_node_validated': nodes == 2,'availability_zones':['us-west-2a']})
                docs=render(AWS/'charts/karpenter-nodepools',{'nodePools':x['pools'], 'ec2NodeClasses':[
                    {'name':f'{profile}-{role}','amiAlias':'al2023@v20261107'} for role in ['control','worker']]})
                self.assertEqual(sum(d['kind']=='EC2NodeClass' for d in docs),2)
                pools={d['metadata']['name']:d for d in docs if d['kind']=='NodePool'}
                for role in ('control','worker'):
                    pool=pools[f'{profile}-{role}']['spec']; spec=pool['template']['spec']
                    req={r['key']:r.get('values') for r in spec['requirements']}
                    self.assertEqual(req['kubernetes.io/arch'],['amd64'])
                    self.assertNotIn('karpenter.k8s.aws/instance-category',req)
                    self.assertEqual(req['node.kubernetes.io/instance-type'],[instance if role=='worker' else 'm6i.2xlarge'])
                    self.assertEqual(spec['expireAfter'],'Never')
                    self.assertNotIn('replicas',pool)
                    self.assertEqual(pool['disruption']['consolidationPolicy'],'WhenEmpty')
                    self.assertTrue(all('operator' not in t for t in spec['taints']))
                    self.assertIn({'key':'zipline.ai/workload','value':f'ray-{profile}','effect':'NoSchedule'},spec['taints'])
                self.assertEqual(pools[f'{profile}-worker']['spec']['limits'],{'cpu':cpu,'memory':memory,'nvidia.com/gpu':gpus})
                self.assertEqual(x['quota']['requests.nvidia.com/gpu'],gpus)
                self.assertEqual(x['quota']['count/rayjobs.ray.io'],'1')
                self.assertLess(x['hardware']['pod_memory'], x['hardware']['memory'])

    def test_invalid_selectors_and_unreviewed_multinode_fail(self):
        for settings in [{'profile':'s6e11-a100'}, {'capacity_type':'spot'}, {'worker_nodes':2},
                         {'profile':'s6e11-a100','instance_type':'p4d.24xlarge','worker_nodes':2},
                         {'max_deadline_seconds':30000},{'enabled':True},{'ami_release':'latest'},
                         {'data_prefix':'*'}]:
            with self.subTest(settings=settings), self.assertRaises(ValueError): evaluate(settings)

    def test_namespace_rbac_admission(self):
        x=evaluate()
        docs=render(AWS/'charts/gpu-training',{'roleArn':'arn:aws:iam::123456789012:role/test','quota':x['quota']})
        ns=next(d for d in docs if d['kind']=='Namespace')
        self.assertEqual(ns['metadata']['name'],'zipline-s6e11-dev')
        self.assertEqual(ns['metadata']['annotations']['helm.sh/resource-policy'],'keep')
        sa=next(d for d in docs if d['kind']=='ServiceAccount')
        self.assertEqual(sa['metadata']['name'],'spark-operator-spark')
        role=next(d for d in docs if d['kind']=='Role' and d['metadata']['name']=='training-submitter')
        for r in role['rules']:
            if r['resources'] != ['rayjobs']: self.assertFalse({'create','delete','patch','update'} & set(r['verbs']))
        cluster=next(d for d in docs if d['kind']=='ClusterRole')
        self.assertTrue(all(set(r['verbs']) <= {'get','list','watch'} for r in cluster['rules']))
        policy=next(d for d in docs if d['kind']=='ValidatingAdmissionPolicy')
        self.assertEqual(policy['spec']['failurePolicy'],'Fail')
        self.assertIn('1800',policy['spec']['validations'][1]['expression'])
        self.assertIn('nvidia.com/gpu',policy['spec']['validations'][-1]['expression'])

    def test_plugin_placement_does_not_need_nfd(self):
        plugin=evaluate()['plugin']
        self.assertIsNone(plugin['affinity'])
        self.assertEqual(plugin['nodeSelector']['zipline.ai/nvidia-device-plugin'], 'true')
        self.assertFalse(plugin['gfd']['enabled'])
        self.assertFalse(plugin['nfd']['enabled'])
        self.assertTrue(plugin['failOnInitError'])
        self.assertIn({'key':'zipline.ai/workload','operator':'Exists','effect':'NoSchedule'},plugin['tolerations'])

    def test_reset_guard_fails_closed_before_deletion(self):
        source=(AWS/'teardown.tf').read_text().split('command     = <<-EOT',1)[1]
        guard=source.split('      echo "Stopping Karpenter',1)[0]
        guard=guard.replace('${self.triggers_replace.cluster_name}', 'test-cluster').replace('${self.triggers_replace.region}', 'us-west-2')
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            (folder/'aws').write_text('#!/bin/bash\n[ "$CASE" != auth-failed ] || exit 1\n')
            (folder/'kubectl').write_text("""#!/bin/bash
[ "$CASE" != inspection-failed ] || exit 1
case "$2" in
  namespace) [ "$CASE" == no-namespace ] || echo namespace/zipline-s6e11-dev ;;
  rayjobs.ray.io) [ "$CASE" != active-job ] || echo rayjob/training ;;
  pods) [ "$CASE" != remaining-pod ] || echo pod/worker ;;
esac
exit 0
""")
            for name in ['aws','kubectl']: (folder/name).chmod(0o755)
            for case in ['no-namespace','empty','active-job','remaining-pod','inspection-failed','auth-failed']:
                with self.subTest(case=case):
                    result=subprocess.run(['bash','-c',guard+'\necho RESET_ALLOWED\n'], text=True,capture_output=True,
                        env={**os.environ,'PATH':str(folder)+':'+os.environ['PATH'],'CASE':case})
                    allowed=case in ['no-namespace','empty']
                    self.assertEqual(result.returncode==0,allowed)
                    self.assertEqual('RESET_ALLOWED' in result.stdout,allowed)

    def test_retention_and_identity_scope(self):
        storage=(ROOT/'aws/public-demo-datasources/training.tf').read_text()
        self.assertIn('prevent_destroy = true',storage)
        self.assertNotIn('expiration {',storage)
        self.assertIn('force_destroy = false',storage)
        iam=(AWS/'gpu-training-iam.tf').read_text()
        self.assertNotIn('s3:DeleteObject',iam)
        self.assertIn('controller_prefix}runs/*',iam)
        self.assertNotIn('AmazonEKSClusterAdminPolicy',iam)
        self.assertIn('StringNotEquals',(AWS/'irsa.tf').read_text())
        teardown=(AWS/'teardown.tf').read_text()
        self.assertLess(teardown.index('TRAINING_JOBS='),teardown.index('kubectl delete nodepools'))

if __name__=='__main__': unittest.main()
