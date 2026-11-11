"""Actual admission regression checks on the disposable kind-gpu-review cluster.

Requires GPU_ADMISSION_KUBECONFIG, pinned KubeRay CRDs in /private/tmp, helm,
kubectl, and the regular tests' dependencies. Never runs against EKS.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import time
import unittest
import yaml
from test_gpu_training import AWS, evaluate

NS = 'zipline-s6e11-dev'
SA = f'system:serviceaccount:{NS}:spark-operator-spark'


def kubectl(*args, obj=None, check=True):
    env = {**os.environ, 'KUBECONFIG': os.environ['GPU_ADMISSION_KUBECONFIG']}
    result = subprocess.run(['kubectl', *args], input=None if obj is None else json.dumps(obj),
                            text=True, capture_output=True, env=env)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def pod(role):
    resources={'requests': {'cpu': '2', 'memory': '8Gi'}, 'limits': {'cpu':'2','memory':'8Gi'}}
    if role=='worker':
        resources={'requests':{'cpu':'2','memory':'24Gi','nvidia.com/gpu':'1'},
                   'limits':{'cpu':'2','memory':'24Gi','nvidia.com/gpu':'1'}}
    return {'serviceAccountName':'spark-operator-spark',
            'nodeSelector':{'zipline.ai/engine':'ray','zipline.ai/role':role,
                            'zipline.ai/execution-profile':'s6e11-l40s','kubernetes.io/arch':'amd64'},
            'containers':[{'name':'ray-'+role,'image':'example.invalid/test@sha256:'+'a'*64,
                           'resources':resources}]}


def cluster():
    return {'rayVersion':'2.55.1','headGroupSpec':{'rayStartParams':{},'template':{'spec':pod('control')}},
            'workerGroupSpecs':[{'groupName':'workers','replicas':1,'minReplicas':1,'maxReplicas':1,
                                 'rayStartParams':{},'template':{'spec':pod('worker')}}]}


def job():
    return {'apiVersion':'ray.io/v1','kind':'RayJob','metadata':{'name':'review-job','namespace':NS},
            'spec':{'entrypoint':'true','backoffLimit':0,'submissionMode':'K8sJobMode',
                    'activeDeadlineSeconds':1800,'preRunningDeadlineSeconds':900,
                    'rayClusterSpec':cluster(),'submitterPodTemplate':{'spec':pod('control')},
                    'deletionStrategy':{'deletionRules':[
                        {'policy':'DeleteCluster','condition':{'jobStatus':'SUCCEEDED','ttlSeconds':120}},
                        {'policy':'DeleteCluster','condition':{'jobDeploymentStatus':'Failed','ttlSeconds':120}}]}}}


class AdmissionSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.environ.get('GPU_ADMISSION_KUBECONFIG'):
            raise RuntimeError('Set GPU_ADMISSION_KUBECONFIG to the disposable kind kubeconfig')
        assert kubectl('config','current-context').stdout.strip()=='kind-gpu-review'
        for name in ['rayjobs','rayclusters']:
            kubectl('apply','--server-side','-f',f'/private/tmp/gpu-{name}-crd.yaml')
            for _ in range(30):
                result=kubectl('wait','--for=condition=Established',f'crd/{name}.ray.io','--timeout=2s',check=False)
                if result.returncode==0:break
                time.sleep(1)
            else:raise AssertionError(result.stderr)
        kubectl('delete','validatingadmissionpolicy,validatingadmissionpolicybinding','s6e11-training','--ignore-not-found')
        kubectl('delete','rayjobs,rayclusters','--all','-n',NS,'--ignore-not-found','--wait=true')
        values={'roleArn':'arn:aws:iam::123456789012:role/test','quota':evaluate()['quota']}
        rendered=subprocess.run(['helm','template','test',str(AWS/'charts/gpu-training'),'-f','-'],
                                input=yaml.safe_dump(values),text=True,capture_output=True,check=True).stdout
        for doc in yaml.safe_load_all(rendered):
            if doc: kubectl('apply','--server-side','-f','-',obj=doc)
        for name in ['s6e11-training-rayjobs','s6e11-training-rayclusters','s6e11-training-delete']:
            for _ in range(30):
                policy=json.loads(kubectl('get','validatingadmissionpolicy',name,'-o','json').stdout)
                status=policy.get('status',{})
                if status.get('observedGeneration') == policy['metadata']['generation'] and 'typeChecking' in status:
                    assert not status['typeChecking'].get('expressionWarnings'), status
                    break
                time.sleep(1)
            else: raise AssertionError('Admission policy did not complete type checking')
        cls.wait_quota_empty()
        time.sleep(1)

    @staticmethod
    def wait_quota_empty():
        for _ in range(40):
            q=json.loads(kubectl('get','resourcequota','training','-n',NS,'-o','json').stdout)
            used=q.get('status',{}).get('used',{})
            if all(used.get(k)=='0' for k in ['count/rayjobs.ray.io','count/rayclusters.ray.io']):return
            time.sleep(1)
        raise AssertionError('Quota did not observe empty Ray resources')

    def assertDenied(self, obj, as_user=None, verb='create'):
        args=[verb,'--dry-run=server','-f','-']
        if as_user:args+=['--as='+as_user]
        result=kubectl(*args,obj=obj,check=False)
        self.assertNotEqual(result.returncode,0,result.stdout)
        self.assertIn('denied',result.stderr.lower(),result.stderr)

    def test_valid_job_and_cluster(self):
        kubectl('create','--dry-run=server','-f','-',obj=job())
        c={'apiVersion':'ray.io/v1','kind':'RayCluster','metadata':{'name':'review-cluster','namespace':NS},'spec':cluster()}
        kubectl('create','--dry-run=server','-f','-',obj=c)

    def test_rayjob_unsafe_templates(self):
        for mutation in ['hostNetwork','privileged','hostPath','nodeName','schedulerName','terminationGracePeriodSeconds']:
            with self.subTest(mutation=mutation):
                obj=job();p=obj['spec']['rayClusterSpec']['workerGroupSpecs'][0]['template']['spec']
                if mutation=='privileged':p['containers'][0]['securityContext']={'privileged':True}
                elif mutation=='hostPath':p['volumes']=[{'name':'host','hostPath':{'path':'/'}}]
                elif mutation=='terminationGracePeriodSeconds':p[mutation]=86400
                else:p[mutation]=True if mutation=='hostNetwork' else 'bypass'
                self.assertDenied(obj)

    def test_raycluster_cannot_bypass_job_rules(self):
        for mutation in ['serviceAccountName','nodeSelector','replicas','memory']:
            with self.subTest(mutation=mutation):
                obj={'apiVersion':'ray.io/v1','kind':'RayCluster','metadata':{'name':'bad-cluster','namespace':NS},'spec':cluster()}
                w=obj['spec']['workerGroupSpecs'][0];p=w['template']['spec']
                if mutation=='serviceAccountName':p['serviceAccountName']='default'
                elif mutation=='nodeSelector':p['nodeSelector']['zipline.ai/execution-profile']='production'
                elif mutation=='replicas':w['replicas']=2
                else:p['containers'][0]['resources']['limits']['memory']='32Gi'
                self.assertDenied(obj)

    def test_autoscaler_cannot_orphan_or_pin_cluster(self):
        c={'apiVersion':'ray.io/v1','kind':'RayCluster','metadata':{'name':'review-cluster','namespace':NS,
            'ownerReferences':[{'apiVersion':'ray.io/v1','kind':'RayJob','name':'review-job','uid':'00000000-0000-0000-0000-000000000001','controller':True}]},'spec':cluster()}
        # A real owner prevents garbage collection racing this local test.
        kubectl('create','-f','-',obj=job())
        owner=json.loads(kubectl('get','rayjob','review-job','-n',NS,'-o','json').stdout)
        c['metadata']['ownerReferences'][0]['uid']=owner['metadata']['uid']
        try:
            kubectl('create','-f','-',obj=c)
            current=json.loads(kubectl('get','raycluster','review-cluster','-n',NS,'-o','json').stdout)
            kubectl('replace','--dry-run=server','--as='+SA,'-f','-',obj=current)
            autoscaler=copy.deepcopy(current)
            autoscaler['spec']['workerGroupSpecs'][0]['scaleStrategy']={'workersToDelete':['failed-worker']}
            kubectl('replace','--dry-run=server','--as='+SA,'-f','-',obj=autoscaler)
            for field, value in [('ownerReferences',[]),('finalizers',['example.com/hold'])]:
                obj=copy.deepcopy(current);obj['metadata'][field]=value
                self.assertDenied(obj,as_user=SA,verb='replace')
        finally:
            kubectl('delete','raycluster','review-cluster','-n',NS,'--ignore-not-found','--wait=true')
            kubectl('delete','rayjob','review-job','-n',NS,'--ignore-not-found','--wait=true')
            self.wait_quota_empty()

    def test_submitter_cannot_change_lifecycle_or_orphan_delete(self):
        user=['--as=review-submitter','--as-group=zipline:s6e11-dev']
        kubectl('create','-f','-',*user,obj=job())
        try:
            for patch in [{'spec':{'shutdownAfterJobFinishes':True}},
                          {'spec':{'managedBy':'kueue.x-k8s.io/multikueue'}},
                          {'metadata':{'finalizers':['example.com/hold']}}]:
                result=kubectl('patch','rayjob','review-job','-n',NS,'--dry-run=server',
                    '--type=merge','-p',json.dumps(patch),*user,check=False)
                self.assertNotEqual(result.returncode,0,result.stdout)
            result=kubectl('delete','rayjob','review-job','-n',NS,'--cascade=orphan','--dry-run=server',*user,check=False)
            self.assertNotEqual(result.returncode,0,result.stdout)
            self.assertIn('Orphan deletion is forbidden',result.stderr)
            kubectl('delete','rayjob','review-job','-n',NS,'--cascade=background','--dry-run=server',*user)
        finally:
            kubectl('delete','rayjob','review-job','-n',NS,'--ignore-not-found','--wait=true')
            self.wait_quota_empty()

    def test_submitter_diagnostic_permissions(self):
        user=['--as=review-submitter','--as-group=zipline:s6e11-dev']
        kubectl('get','resourcequota,limitrange,serviceaccount','-n',NS,*user)
        kubectl('get','namespace',NS,*user)
        result=kubectl('auth','can-i','create','pods','-n','default',*user,check=False)
        self.assertNotEqual(result.returncode,0)

    def test_workload_cannot_extend_pod_deletion_grace(self):
        # A nonexistent node keeps this Pod inert while exercising the bound-pod
        # deletion path. Kubernetes forces grace=0 for entirely unassigned Pods.
        obj={'apiVersion':'v1','kind':'Pod','metadata':{'name':'grace-test','namespace':NS},'spec':pod('worker')}
        obj['spec']['nodeName']='nonexistent-review-node'
        kubectl('create','-f','-',obj=obj)
        try:
            result=kubectl('delete','pod','grace-test','-n',NS,'--grace-period=86400','--dry-run=server','--as='+SA,check=False)
            self.assertNotEqual(result.returncode,0,result.stdout)
            self.assertIn('cannot extend training termination grace',result.stderr)
            kubectl('delete','pod','grace-test','-n',NS,'--grace-period=30','--dry-run=server','--as='+SA)
        finally:
            kubectl('delete','pod','grace-test','-n',NS,'--grace-period=0','--force','--wait=true')

    def test_baseline_rejects_operator_created_privileged_pod(self):
        p=pod('worker');p['containers'][0]['securityContext']={'privileged':True}
        obj={'apiVersion':'v1','kind':'Pod','metadata':{'name':'privileged','namespace':NS},'spec':p}
        result=kubectl('create','--dry-run=server','-f','-',obj=obj,check=False)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('violates PodSecurity',result.stderr)


if __name__=='__main__':unittest.main()
