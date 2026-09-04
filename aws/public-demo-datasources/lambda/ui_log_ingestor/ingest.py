import datetime as dt
import hashlib
import json
import os
import re
import time
import uuid

import boto3


cloudwatch_logs = boto3.client("logs")
glue = boto3.client("glue")
s3 = boto3.client("s3")


UI_LOG_COLUMNS = [
    {"Name": "event_id", "Type": "string"},
    {"Name": "ingestion_id", "Type": "string"},
    {"Name": "event_ts", "Type": "bigint"},
    {"Name": "event_time_iso", "Type": "string"},
    {"Name": "ingested_at", "Type": "string"},
    {"Name": "freshness_lag_seconds", "Type": "bigint"},
    {"Name": "log_stream", "Type": "string"},
    {"Name": "namespace", "Type": "string"},
    {"Name": "pod", "Type": "string"},
    {"Name": "container", "Type": "string"},
    {"Name": "client_ip", "Type": "string"},
    {"Name": "user_id", "Type": "string"},
    {"Name": "http_method", "Type": "string"},
    {"Name": "path", "Type": "string"},
    {"Name": "route_family", "Type": "string"},
    {"Name": "status_code", "Type": "int"},
    {"Name": "status_family", "Type": "string"},
    {"Name": "is_error", "Type": "int"},
    {"Name": "is_not_found", "Type": "int"},
    {"Name": "is_write", "Type": "int"},
    {"Name": "request_time_seconds", "Type": "double"},
    {"Name": "user_agent", "Type": "string"},
    {"Name": "raw_message", "Type": "string"},
]


NGINX_ACCESS_RE = re.compile(
    r'^(?P<client_ip>\S+)\s+\S+\s+\S+\s+\[[^\]]+\]\s+'
    r'"(?P<method>GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\s+'
    r'(?P<path>[^\s"]+)\s+[^"]*"\s+'
    r'(?P<status>\d{3})\s+\S+\s+'
    r'"[^"]*"\s+"(?P<user_agent>[^"]*)"\s+'
    r'\S+\s+(?P<request_time>[0-9.]+)',
    re.IGNORECASE,
)

REQUEST_RE = re.compile(
    r'"(?P<method>GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\s+'
    r'(?P<path>[^\s"]+)\s+[^"]*"\s+'
    r'(?P<status>\d{3})'
    r'(?:\s+\S+){0,5}'
    r'(?:\s+"[^"]*"\s+"(?P<user_agent>[^"]*)")?'
    r'(?:\s+\S+\s+(?P<request_time>[0-9.]+))?',
    re.IGNORECASE,
)


def _json_message(message):
    try:
        decoded = json.loads(message)
        if isinstance(decoded, dict):
            return decoded
    except json.JSONDecodeError:
        pass
    return {}


def _extract_log_message(message):
    decoded = _json_message(message)
    for key in ("log", "message", "msg"):
        value = decoded.get(key)
        if isinstance(value, str) and value:
            return value.strip(), decoded
    return message.strip(), decoded


def _parse_stream(log_stream):
    parts = log_stream.split("_")
    if len(parts) >= 3:
        return {
            "pod": parts[0],
            "namespace": parts[1],
            "container": parts[2].split("-")[0],
        }
    return {"pod": "", "namespace": "", "container": ""}


def _route_family(path):
    if not path:
        return "unknown"
    clean = path.split("?", 1)[0]
    parts = [part for part in clean.split("/") if part]
    if not parts:
        return "/"
    if parts[0] in {"services", "api", "joins", "group_bys", "workflows"}:
        return "/" + "/".join(parts[:2])
    return "/" + parts[0]


def _parse_audit_json(decoded, message):
    candidates = []
    if decoded:
        candidates.append(decoded)
    inner = _json_message(message)
    if inner:
        candidates.append(inner)

    for candidate in candidates:
        if candidate.get("eventType") != "api_request_complete":
            continue
        method = str(candidate.get("method", "")).upper()
        path = candidate.get("path") or candidate.get("route") or ""
        status_code = int(candidate.get("statusCode", 0))
        if not method or not path or not status_code:
            continue
        return {
            "client_ip": candidate.get("remoteIp", ""),
            "user_id": candidate.get("userId") or candidate.get("user_id") or candidate.get("email") or "",
            "http_method": method,
            "path": path,
            "route_family": candidate.get("route") or _route_family(path),
            "status_code": status_code,
            "status_family": f"{status_code // 100}xx",
            "is_error": 1 if status_code >= 500 else 0,
            "is_not_found": 1 if status_code == 404 else 0,
            "is_write": 1 if method in {"POST", "PUT", "PATCH", "DELETE"} else 0,
            "request_time_seconds": float(candidate.get("latencyMs", 0)) / 1000.0,
            "user_agent": candidate.get("userAgent", ""),
        }
    return None


def _parse_http_fields(message):
    match = NGINX_ACCESS_RE.search(message) or REQUEST_RE.search(message)
    if not match:
        return None
    status_code = int(match.group("status"))
    method = match.group("method").upper()
    return {
        "client_ip": match.groupdict().get("client_ip", ""),
        "user_id": "",
        "http_method": method,
        "path": match.group("path"),
        "route_family": _route_family(match.group("path")),
        "status_code": status_code,
        "status_family": f"{status_code // 100}xx",
        "is_error": 1 if status_code >= 500 else 0,
        "is_not_found": 1 if status_code == 404 else 0,
        "is_write": 1 if method in {"POST", "PUT", "PATCH", "DELETE"} else 0,
        "request_time_seconds": float(match.group("request_time") or 0.0),
        "user_agent": match.group("user_agent") or "",
    }


def _ensure_partition(database_name, table_name, snapshot_date, location):
    partition_input = {
        "Values": [snapshot_date],
        "StorageDescriptor": {
            "Columns": UI_LOG_COLUMNS,
            "Location": location,
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "Name": f"{table_name}-serde",
                "SerializationLibrary": "org.apache.hive.hcatalog.data.JsonSerDe",
            },
        },
    }
    try:
        glue.create_partition(
            DatabaseName=database_name,
            TableName=table_name,
            PartitionInput=partition_input,
        )
    except glue.exceptions.AlreadyExistsException:
        glue.update_partition(
            DatabaseName=database_name,
            TableName=table_name,
            PartitionValueList=[snapshot_date],
            PartitionInput=partition_input,
        )


def _iter_events(log_group_name, start_ms, end_ms, log_stream_prefixes):
    kwargs = {
        "logGroupName": log_group_name,
        "startTime": start_ms,
        "endTime": end_ms,
        "interleaved": True,
    }
    prefixes = [prefix for prefix in log_stream_prefixes if prefix]
    if len(prefixes) == 1:
        kwargs["logStreamNamePrefix"] = prefixes[0]

    while True:
        page = cloudwatch_logs.filter_log_events(**kwargs)
        for event in page.get("events", []):
            if not prefixes or any(event.get("logStreamName", "").startswith(prefix) for prefix in prefixes):
                yield event
        token = page.get("nextToken")
        if not token:
            break
        kwargs["nextToken"] = token


def handler(event, _context):
    now = dt.datetime.now(dt.timezone.utc)
    ingestion_id = str(uuid.uuid4())
    lookback_minutes = int(event.get("lookback_minutes", os.environ.get("LOOKBACK_MINUTES", "30")))
    end_ms = int(now.timestamp() * 1000)
    start_ms = int((now - dt.timedelta(minutes=lookback_minutes)).timestamp() * 1000)
    snapshot_date = f"{now:%Y-%m-%d}"
    table_name = os.environ.get("GLUE_TABLE", "ui_access_logs")
    database_name = os.environ["GLUE_DATABASE"]
    bucket = os.environ["CURATED_BUCKET"]
    prefix = os.environ.get("OUTPUT_PREFIX", "app/ui_access_logs").strip("/")
    log_stream_prefixes = [
        value.strip()
        for value in os.environ.get("LOG_STREAM_PREFIXES", "").split(",")
        if value.strip()
    ]

    rows = []
    for log_event in _iter_events(os.environ["LOG_GROUP_NAME"], start_ms, end_ms, log_stream_prefixes):
        log_message, decoded = _extract_log_message(log_event.get("message", ""))
        parsed = _parse_audit_json(decoded, log_message) or _parse_http_fields(log_message)
        if not parsed:
            continue

        event_ts = int(log_event["timestamp"])
        event_time = dt.datetime.fromtimestamp(event_ts / 1000, tz=dt.timezone.utc)
        stream_fields = _parse_stream(log_event.get("logStreamName", ""))
        row = {
            "event_id": hashlib.sha256(
                f"{log_event.get('eventId', '')}:{event_ts}:{log_message}".encode("utf-8")
            ).hexdigest(),
            "ingestion_id": ingestion_id,
            "event_ts": event_ts,
            "event_time_iso": event_time.isoformat(),
            "ingested_at": now.isoformat(),
            "freshness_lag_seconds": max(0, int(time.time() - event_ts / 1000)),
            "log_stream": log_event.get("logStreamName", ""),
            "namespace": decoded.get("kubernetes", {}).get("namespace_name", stream_fields["namespace"]),
            "pod": decoded.get("kubernetes", {}).get("pod_name", stream_fields["pod"]),
            "container": decoded.get("kubernetes", {}).get("container_name", stream_fields["container"]),
            "raw_message": log_message,
            **parsed,
        }
        rows.append(row)

    if rows:
        key = f"{prefix}/snapshot_date={snapshot_date}/{ingestion_id}.jsonl"
        body = "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows)
        s3.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"), ContentType="application/jsonl")
        _ensure_partition(
            database_name,
            table_name,
            snapshot_date,
            f"s3://{bucket}/{prefix}/snapshot_date={snapshot_date}/",
        )
    else:
        key = ""

    return {
        "rows": len(rows),
        "bucket": bucket,
        "key": key,
        "lookback_minutes": lookback_minutes,
        "log_group_name": os.environ["LOG_GROUP_NAME"],
    }
