import datetime as dt
import hashlib
import json
import os
import re
import time
import uuid

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import awswrangler as wr


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

USER_IDENTITY_COLUMNS = [
    {"Name": "user_id", "Type": "string"},
    {"Name": "email_hash", "Type": "string"},
    {"Name": "first_seen_ts", "Type": "bigint"},
    {"Name": "last_seen_ts", "Type": "bigint"},
    {"Name": "last_seen_time_iso", "Type": "string"},
    {"Name": "last_event", "Type": "string"},
    {"Name": "source_event_id", "Type": "string"},
    {"Name": "ingestion_id", "Type": "string"},
    {"Name": "ingested_at", "Type": "string"},
]


PARQUET_TYPES = {
    "string": pa.string(),
    "bigint": pa.int64(),
    "int": pa.int32(),
    "double": pa.float64(),
}


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


def _extract_user_identity(decoded, message):
    candidates = []
    if decoded:
        candidates.append(decoded)
    inner = _json_message(message)
    if inner:
        candidates.append(inner)

    for candidate in candidates:
        event_name = candidate.get("event")
        user_id = candidate.get("userid") or candidate.get("userId") or candidate.get("user_id")
        email = candidate.get("email")
        if not event_name or not user_id or not email:
            continue
        if event_name not in {"user_created", "authn_login_success", "authn_token_created"}:
            continue
        normalized_email = str(email).strip().lower()
        if not normalized_email:
            continue
        return {
            "user_id": str(user_id),
            "email_hash": hashlib.sha256(normalized_email.encode("utf-8")).hexdigest()[:8],
            "last_event": str(event_name),
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


def _ensure_partition(database_name, table_name, snapshot_date, location, columns):
    partition_input = {
        "Values": [snapshot_date],
        "StorageDescriptor": {
            "Columns": columns,
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


def _parse_snapshot_date(value):
    return dt.datetime.strptime(value, "%Y-%m-%d").date()


def _identity_snapshot_dates(event, now):
    explicit_dates = event.get("identity_snapshot_dates")
    if explicit_dates:
        return sorted({str(value) for value in explicit_dates})

    end_date = _parse_snapshot_date(event.get("identity_snapshot_end_date", f"{now:%Y-%m-%d}"))
    snapshot_days = int(
        event.get(
            "identity_snapshot_days",
            os.environ.get("USER_IDENTITY_SNAPSHOT_DAYS", "7"),
        )
    )
    snapshot_days = max(1, snapshot_days)
    dates = [
        end_date - dt.timedelta(days=days_ago)
        for days_ago in range(snapshot_days - 1, -1, -1)
    ]
    return [date.isoformat() for date in dates]


def _merge_identity_rows(*row_sets):
    merged = {}
    for rows in row_sets:
        for row in rows:
            user_id = row.get("user_id")
            if not user_id:
                continue
            existing = merged.get(user_id)
            if not existing:
                merged[user_id] = dict(row)
                continue

            existing["first_seen_ts"] = min(
                int(existing.get("first_seen_ts") or row.get("first_seen_ts") or 0),
                int(row.get("first_seen_ts") or existing.get("first_seen_ts") or 0),
            )
            if int(row.get("last_seen_ts") or 0) >= int(existing.get("last_seen_ts") or 0):
                merged[user_id] = {
                    **existing,
                    **row,
                    "first_seen_ts": existing["first_seen_ts"],
                }
    return list(merged.values())


def _load_latest_identity_rows(bucket, prefix):
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=f"{prefix}/snapshot_date="):
        keys.extend(
            item["Key"]
            for item in page.get("Contents", [])
            if item.get("Key", "").endswith(".jsonl")
        )
    if not keys:
        return []

    rows = []
    for key in sorted(keys, reverse=True):
        response = s3.get_object(Bucket=bucket, Key=key)
        body = response["Body"].read().decode("utf-8")
        for line in body.splitlines():
            if line.strip():
                rows.append(json.loads(line))
        if rows:
            return _merge_identity_rows(rows)
    return []


def _write_identity_snapshot(
    database_name,
    table_name,
    bucket,
    prefix,
    snapshot_date,
    ingestion_id,
    ingested_at,
    user_rows,
):
    partition_rows = []
    for row in user_rows:
        partition_rows.append(
            {
                **row,
                "ingestion_id": ingestion_id,
                "ingested_at": ingested_at,
            }
        )

    key = f"{prefix}/snapshot_date={snapshot_date}/{ingestion_id}.jsonl"
    body = "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in partition_rows)
    s3.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"), ContentType="application/jsonl")
    _ensure_partition(
        database_name,
        table_name,
        snapshot_date,
        f"s3://{bucket}/{prefix}/snapshot_date={snapshot_date}/",
        USER_IDENTITY_COLUMNS,
    )
    return key


def _write_parquet_rows(bucket, prefix, snapshot_date, key_name, rows, columns):
    schema = pa.schema(
        [pa.field(column["Name"], PARQUET_TYPES[column["Type"]]) for column in columns]
    )
    table = pa.Table.from_pylist(rows, schema=schema)
    output = pa.BufferOutputStream()
    pq.write_table(table, output, compression="snappy")
    key = f"{prefix}/snapshot_date={snapshot_date}/{key_name}.parquet"
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=output.getvalue().to_pybytes(),
        ContentType="application/vnd.apache.parquet",
    )
    return key


def _write_identity_iceberg(database_name, table_name, bucket, prefix, rows, snapshot_dates):
    iceberg_rows = []
    for snapshot_date in snapshot_dates:
        iceberg_rows.extend({**row, "snapshot_date": snapshot_date} for row in rows)

    wr.athena.to_iceberg(
        df=pd.DataFrame(iceberg_rows),
        database=database_name,
        table=table_name,
        temp_path=f"s3://{bucket}/tmp/user_identity_snapshots_iceberg/",
        table_location=f"s3://{bucket}/{prefix}/",
        partition_cols=["snapshot_date"],
        mode="overwrite_partitions",
        keep_files=False,
        workgroup=os.environ["ATHENA_WORKGROUP"],
        dtype={
            "user_id": "string",
            "email_hash": "string",
            "first_seen_ts": "bigint",
            "last_seen_ts": "bigint",
            "last_seen_time_iso": "string",
            "last_event": "string",
            "source_event_id": "string",
            "ingestion_id": "string",
            "ingested_at": "string",
            "snapshot_date": "string",
        },
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
    user_identity_table_name = os.environ.get("USER_IDENTITY_GLUE_TABLE", "user_identity_snapshots")
    database_name = os.environ["GLUE_DATABASE"]
    bucket = os.environ["CURATED_BUCKET"]
    prefix = os.environ.get("OUTPUT_PREFIX", "app/ui_access_logs").strip("/")
    user_identity_prefix = os.environ.get("USER_IDENTITY_OUTPUT_PREFIX", "app/user_identity_snapshots").strip("/")
    user_identity_parquet_prefix = os.environ.get(
        "USER_IDENTITY_PARQUET_PREFIX", "app/user_identity_snapshots_parquet"
    ).strip("/")
    user_identity_iceberg_table = os.environ.get(
        "USER_IDENTITY_ICEBERG_TABLE", "user_identity_snapshots_iceberg"
    )
    user_identity_iceberg_prefix = os.environ.get(
        "USER_IDENTITY_ICEBERG_PREFIX", "app/user_identity_snapshots_iceberg"
    ).strip("/")
    identity_snapshot_dates = _identity_snapshot_dates(event, now)
    log_stream_prefixes = [
        value.strip()
        for value in os.environ.get("LOG_STREAM_PREFIXES", "").split(",")
        if value.strip()
    ]

    rows = []
    users_by_id = {}
    for log_event in _iter_events(os.environ["LOG_GROUP_NAME"], start_ms, end_ms, log_stream_prefixes):
        log_message, decoded = _extract_log_message(log_event.get("message", ""))
        identity = _extract_user_identity(decoded, log_message)
        if identity:
            event_ts = int(log_event["timestamp"])
            existing = users_by_id.get(identity["user_id"])
            first_seen_ts = min(existing["first_seen_ts"], event_ts) if existing else event_ts
            if not existing or event_ts >= existing["last_seen_ts"]:
                last_seen_time = dt.datetime.fromtimestamp(event_ts / 1000, tz=dt.timezone.utc)
                users_by_id[identity["user_id"]] = {
                    **identity,
                    "first_seen_ts": first_seen_ts,
                    "last_seen_ts": event_ts,
                    "last_seen_time_iso": last_seen_time.isoformat(),
                    "source_event_id": log_event.get("eventId", ""),
                    "ingestion_id": ingestion_id,
                    "ingested_at": now.isoformat(),
                }
            else:
                existing["first_seen_ts"] = first_seen_ts

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
            UI_LOG_COLUMNS,
        )
    else:
        key = ""

    existing_user_rows = _load_latest_identity_rows(bucket, user_identity_prefix)
    user_rows = _merge_identity_rows(existing_user_rows, users_by_id.values())
    if user_rows:
        user_identity_keys = [
            _write_identity_snapshot(
                database_name,
                user_identity_table_name,
                bucket,
                user_identity_prefix,
                identity_snapshot_date,
                ingestion_id,
                now.isoformat(),
                user_rows,
            )
            for identity_snapshot_date in identity_snapshot_dates
        ]
    else:
        user_identity_keys = []

    if user_rows:
        parquet_rows = [
            {
                **row,
                "ingestion_id": ingestion_id,
                "ingested_at": now.isoformat(),
            }
            for row in user_rows
        ]
        user_identity_parquet_keys = [
            _write_parquet_rows(
                bucket,
                user_identity_parquet_prefix,
                identity_snapshot_date,
                "snapshot",
                parquet_rows,
                USER_IDENTITY_COLUMNS,
            )
            for identity_snapshot_date in identity_snapshot_dates
        ]
    else:
        user_identity_parquet_keys = []

    if user_rows:
        _write_identity_iceberg(
            database_name,
            user_identity_iceberg_table,
            bucket,
            user_identity_iceberg_prefix,
            parquet_rows,
            identity_snapshot_dates,
        )

    return {
        "rows": len(rows),
        "user_identity_rows": len(user_rows),
        "bucket": bucket,
        "key": key,
        "user_identity_keys": user_identity_keys,
        "user_identity_parquet_keys": user_identity_parquet_keys,
        "user_identity_iceberg_table": (
            f"{database_name}.{user_identity_iceberg_table}" if user_rows else ""
        ),
        "identity_snapshot_dates": identity_snapshot_dates,
        "lookback_minutes": lookback_minutes,
        "log_group_name": os.environ["LOG_GROUP_NAME"],
    }
