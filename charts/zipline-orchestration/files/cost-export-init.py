"""Init container for the cost export job.

The Spark operator runs spark-submit in its own pod, which cannot read gs:// or s3:// dependencies,
and the Polaris client Secret lives in the release namespace, which a pod in a compute namespace
cannot mount. So this step downloads the engine jar (the job's Iceberg runtime) and copies the
Polaris credential into a volume shared with the driver.

The jar is copied with Hadoop's FsShell from the Spark image's own jars, so the image's GCS and S3
connectors and the pod's cloud identity (Workload Identity or IRSA) do the work on either cloud.
"""

import base64
import json
import os
import ssl
import subprocess
import sys
import tempfile
import urllib.request

SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
SPARK_JARS = "/opt/spark/jars/*"
SCHEME_SETTINGS = {
    "gs": ["fs.gs.impl=com.google.cloud.hadoop.fs.gcs.GoogleHadoopFileSystem"],
    "s3": ["fs.s3.impl=org.apache.hadoop.fs.s3a.S3AFileSystem",
           "fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider"],
    "s3a": ["fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider"],
}


def download(source: str, destination: str):
    scheme = source.split("://", 1)[0]
    if scheme not in SCHEME_SETTINGS:
        raise ValueError(f"unsupported engine jar location {source!r}")
    # Spark images ship no Hadoop config, and FsShell refuses to start without core-site.xml.
    with tempfile.TemporaryDirectory() as conf_dir:
        with open(os.path.join(conf_dir, "core-site.xml"), "w") as handle:
            handle.write("<configuration/>\n")
        settings = [arg for setting in SCHEME_SETTINGS[scheme] for arg in ("-D", setting)]
        subprocess.run(
            ["java", "-cp", f"{conf_dir}:{SPARK_JARS}", "org.apache.hadoop.fs.FsShell",
             *settings, "-copyToLocal", "-f", source, destination],
            check=True,
        )
    print(f"Downloaded {source} to {destination} ({os.path.getsize(destination)} bytes)")


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
    download(os.environ["ENGINE_JAR"], os.environ["ENGINE_JAR_PATH"])
    copy_secret_key(os.environ["POLARIS_SECRET_NAMESPACE"], os.environ["POLARIS_SECRET_NAME"],
                    os.environ["POLARIS_SECRET_KEY"], os.environ["POLARIS_CREDENTIAL_FILE"])


if __name__ == "__main__":
    sys.exit(main())
