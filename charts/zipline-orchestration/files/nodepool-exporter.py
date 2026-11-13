import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from ssl import create_default_context
from urllib.request import Request, urlopen

SA_DIR = '/var/run/secrets/kubernetes.io/serviceaccount'
API_HOST = os.environ.get('KUBERNETES_SERVICE_HOST', 'kubernetes.default.svc')
API_PORT = os.environ.get('KUBERNETES_SERVICE_PORT', '443')
LISTEN_PORT = int(os.environ.get('PORT', '9101'))
CLUSTER_NAME = os.environ.get('CLUSTER_NAME', '')
CM_NAMESPACE = 'kube-system'
CM_NAME = 'cluster-autoscaler-status'
REFRESH_SECONDS = int(os.environ.get('REFRESH_SECONDS', '30'))

# The autoscaler's YAML is regular: one nodeGroup block per managed instance group, each with
# a health map carrying minSize/maxSize and nodeCounts. Parsing those few fields keeps the
# exporter dependency-free (no PyYAML in the image).
POOL_FROM_MIG = re.compile(r'instanceGroups/(?P<mig>[^/]+?)-\w+-grp$')

state_lock = threading.Lock()
state = {'up': 0, 'healthy': 0, 'status': 'Unknown', 'pools': {}}


def read_status():
    with open(f'{SA_DIR}/token') as handle:
        token = handle.read().strip()
    url = f'https://{API_HOST}:{API_PORT}/api/v1/namespaces/{CM_NAMESPACE}/configmaps/{CM_NAME}'
    request = Request(url, headers={'Authorization': f'Bearer {token}'})
    context = create_default_context(cafile=f'{SA_DIR}/ca.crt')
    with urlopen(request, context=context, timeout=15) as response:
        return json.load(response)['data']['status']


def pool_from_mig(name):
    match = POOL_FROM_MIG.search(name)
    if not match:
        return None
    mig = match.group('mig')
    if CLUSTER_NAME and mig.startswith(f'gke-{CLUSTER_NAME}-'):
        return mig[len(f'gke-{CLUSTER_NAME}-'):]
    parts = mig.split('-')
    return '-'.join(parts[2:-1]) if len(parts) > 3 else mig


def parse(status):
    cluster_wide = status.split('nodeGroups:')[0]
    status_match = re.search(r'^\s{4}status: (\S+)', cluster_wide, re.M)
    status_label = status_match.group(1) if status_match else 'Unknown'
    healthy = 1 if status_label == 'Healthy' else 0

    pools = {}
    blocks = re.split(r'^- health:', status, flags=re.M)[1:]
    for block in blocks:
        name_match = re.search(r'^\s{2}name: (\S+)', block, re.M)
        max_match = re.search(r'^\s{4}maxSize: (\d+)', block, re.M)
        min_match = re.search(r'^\s{4}minSize: (\d+)', block, re.M)
        if not (name_match and max_match and min_match):
            continue
        pool = pool_from_mig(name_match.group(1))
        if not pool:
            continue
        nodes_match = re.search(r'registered:.*?^ +total: (\d+)', block, re.M | re.S)
        # The autoscaler reports one nodeGroup per managed instance group, and a regional pool has
        # one per zone, each carrying the pool's *per-zone* min/max. Summing them is what makes the
        # ceiling match GKE's (min/max nodes are per zone unless --total-* was used); collapsing a
        # three-zone pool onto one MIG understates its limit threefold.
        entry = pools.setdefault(pool, {'min': 0, 'max': 0, 'nodes': 0, 'zones': 0})
        entry['min'] += int(min_match.group(1))
        entry['max'] += int(max_match.group(1))
        entry['nodes'] += int(nodes_match.group(1)) if nodes_match else 0
        entry['zones'] += 1
    return healthy, status_label, pools


def refresh():
    while True:
        try:
            healthy, status_label, pools = parse(read_status())
            with state_lock:
                state.update(up=1, healthy=healthy, status=status_label, pools=pools)
        except Exception as exc:  # keep serving the last good scrape
            with state_lock:
                state['up'] = 0
            print(f'nodepool-exporter: {exc}', file=sys.stderr, flush=True)
        time.sleep(REFRESH_SECONDS)


def render():
    with state_lock:
        snapshot = json.loads(json.dumps(state))
    lines = [
        '# HELP gke_nodepool_exporter_up 1 when the last autoscaler ConfigMap read succeeded.',
        '# TYPE gke_nodepool_exporter_up gauge',
        f"gke_nodepool_exporter_up {snapshot['up']}",
        '# HELP gke_cluster_autoscaler_healthy 1 when the cluster autoscaler reports Healthy.',
        '# TYPE gke_cluster_autoscaler_healthy gauge',
        f"gke_cluster_autoscaler_healthy {snapshot['healthy']}",
        '# HELP gke_cluster_autoscaler_status Cluster autoscaler health status.',
        '# TYPE gke_cluster_autoscaler_status gauge',
        'gke_cluster_autoscaler_status{status="' + snapshot['status'] + '"} 1',
    ]
    for kind, help_text in (
            ('min_nodes', 'Autoscaler minimum node count summed over the pool zones.'),
            ('max_nodes', 'Autoscaler maximum node count summed over the pool zones.'),
            ('nodes', 'Nodes the autoscaler counts as registered in the pool.'),
            ('zones', 'Zones (managed instance groups) the pool spans.')):
        field = {'min_nodes': 'min', 'max_nodes': 'max', 'nodes': 'nodes', 'zones': 'zones'}[kind]
        lines.append(f'# HELP gke_nodepool_{kind} {help_text}')
        lines.append(f'# TYPE gke_nodepool_{kind} gauge')
        for pool, values in sorted(snapshot['pools'].items()):
            lines.append('gke_nodepool_' + kind + '{pool="' + pool + '"} ' + str(values[field]))
    return '\n'.join(lines) + '\n'


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ('/metrics', '/'):
            self.send_response(404)
            self.end_headers()
            return
        body = render().encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; version=0.0.4')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        return


if __name__ == '__main__':
    threading.Thread(target=refresh, daemon=True).start()
    print(f'nodepool-exporter: listening on :{LISTEN_PORT}', flush=True)
    ThreadingHTTPServer(('', LISTEN_PORT), Handler).serve_forever()
