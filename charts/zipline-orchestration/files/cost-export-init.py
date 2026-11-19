"""Init container for the cost export job.

The Spark operator runs spark-submit in its own pod, which cannot read gs:// dependencies, and the
Polaris client Secret lives in the release namespace, which a pod in a compute namespace cannot
mount. So this step downloads the engine jar (the job's Iceberg runtime) and copies the Polaris
credential into a volume shared with the driver. Only the standard library is used because the
Spark image has no cloud client libraries.
"""

import base64
import json
import os
import ssl
import sys
import urllib.parse
import urllib.request

GCP_TOKEN_URL = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"


def download_gcs(source: str, destination: str):
    bucket, _, name = source[len("gs://"):].partition("/")
    token_request = urllib.request.Request(GCP_TOKEN_URL, headers={"Metadata-Flavor": "Google"})
    with urllib.request.urlopen(token_request, timeout=30) as response:
        token = json.load(response)["access_token"]
    url = (f"https://storage.googleapis.com/storage/v1/b/{bucket}/o/"
           f"{urllib.parse.quote(name, safe='')}?alt=media")
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=600) as response, open(destination, "wb") as out:
        while chunk := response.read(8 << 20):
            out.write(chunk)
    print(f"Downloaded {source} to {destination}")


def copy_secret_key(namespace: str, name: str, key: str, destination: str):
    host = os.environ["KUBERNETES_SERVICE_HOST"]
    port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
    with open(f"{SA_DIR}/token") as handle:
        token = handle.read().strip()
    request = urllib.request.Request(
        f"https://{host}:{port}/api/v1/namespaces/{namespace}/secrets/{name}",
        headers={"Authorization": f"Bearer {token}"})
    context = ssl.create_default_context(cafile=f"{SA_DIR}/ca.crt")
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        data = json.load(response)["data"]
    if key not in data:
        raise KeyError(f"secret {namespace}/{name} has no key {key!r}")
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(base64.b64decode(data[key]))
    print(f"Copied {namespace}/{name}[{key}] to {destination}")


def main():
    jar_source, jar_destination = os.environ["ENGINE_JAR"], os.environ["ENGINE_JAR_PATH"]
    if not jar_source.startswith("gs://"):
        raise ValueError(f"only gs:// engine jars are supported, got {jar_source!r}")
    download_gcs(jar_source, jar_destination)
    copy_secret_key(os.environ["POLARIS_SECRET_NAMESPACE"], os.environ["POLARIS_SECRET_NAME"],
                    os.environ["POLARIS_SECRET_KEY"], os.environ["POLARIS_CREDENTIAL_FILE"])


if __name__ == "__main__":
    sys.exit(main())
