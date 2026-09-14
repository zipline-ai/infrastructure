# Public Demo Fetch Logging and Online/Offline Consistency

## Objective

Capture the `LoggableResponse` emitted by the Zipline fetcher for sampled Join fetches, archive those records in an AWS catalog table, and use Chronon's existing log-flattener and consistency jobs to compare the fetched online values with recomputed offline values.

This is feature-response logging. It is separate from the UI and Hub HTTP access-log datasets.

## Decisions

- Prefer the existing/shared Amazon MSK infrastructure when the public-demo VPC can reach it. Do not create a dedicated MSK cluster solely for this demo.
- Support Kinesis as the lower-complexity AWS transport by setting `FETCHER_OOC_TOPIC_INFO=kinesis://<stream-name>`; Kafka support remains available.
- Keep the existing Kafka wire format: Avro-encoded `LoggableResponse` records produced by `KafkaLoggableResponseConsumer`.
- Use one topic for all Join versions. The outer schema is stable; `schemaHash` identifies the schema for the encoded Join key and value.
- Preserve the GCP pipeline boundary. The archive creates a raw `data.loggable_response`-equivalent table; a Chronon staging query performs partitioning, base64 conversion, and column normalization.
- Keep the archive and its S3 data in the persistent datasource stack so weekly platform resets do not erase consistency history.
- Keep sampling controlled by Join configuration. The current demo Joins use `check_consistency=True` and `consistency_sample_percent=100.0`; lower this lever if traffic or cost grows.

## Record Contracts

Kafka receives the canonical Avro `LoggableResponse`:

```text
keyBytes: byte[]
valueBytes: byte[]
joinName: string
tsMillis: long
schemaHash: string
```

`SCHEMA_PUBLISH_EVENT` records use the same envelope and carry the inner logging schema. Normal records contain Avro-encoded Join keys and fetched values.

The staging query produces the table expected by `LogFlattenerJob`:

```text
ds: string
ts_millis: long
key_base64: string
value_base64: string
name: string
schema_hash: string
```

## Target Pipeline

```text
Zipline fetcher
  -> MSK topic: public-demo-fetcher-ooc
  -> managed archive into S3 and a raw Glue catalog table
  -> partitioned_logging StagingQuery
  -> logging_schema GroupBy
  -> log-flattener for each consistency-enabled Join
  -> <join output table>_logged
  -> consistency-metrics-compute
```

## Implementation Landmarks

Status as of 2026-09-14: landmark 1 supports both Kafka and Kinesis and its focused platform tests pass. Landmark 2 found that the shared `zipline-canary-kafka` cluster is active but not currently reachable from public-demo: it is private in VPC `vpc-0a77ba48fbfd24a1b`, public-demo is in `vpc-0182d5493e977ed6b`, there is no VPC peering, and MSK multi-VPC connectivity is disabled. No MSK Connect connectors or custom plugins are currently installed. Kinesis is now the ready transport fallback; provisioning, IAM, fetcher configuration, and archival remain.

### 1. Enable AWS Kafka response logging

- Update `chronon/cloud_aws/.../AwsApiImpl.scala` in the platform repository.
- Resolve `FETCHER_OOC_TOPIC_INFO` exactly as the GCP implementation does.
- Select the existing `KafkaLoggableResponseConsumer` for `kafka://` topic information.
- Support the optional existing `SCHEMA_REGISTRY_ID` setting without changing serialization.
- Retain a clearly logged no-op when the setting is absent.
- Add focused tests for configured and unconfigured behavior.
- Compile and run the cloud AWS tests.

### 2. Confirm shared MSK connectivity

- Identify the MSK cluster ARN, IAM bootstrap brokers, topic policy, VPC, and subnets.
- Confirm connectivity from the public-demo fetcher Pod/VPC.
- If the cluster is private and unreachable, choose private connectivity or fall back to Kinesis. Do not provision a new MSK cluster without revisiting cost.
- Create or select the `public-demo-fetcher-ooc` topic.

Current finding: reuse requires either VPC peering plus broker security-group/routing changes, or enabling IAM multi-VPC connectivity and creating an MSK VPC connection. The latter is also the path required for Firehose to consume the private MSK cluster. The alternative is to use a dedicated Kinesis stream without changing the shared canary cluster.

### 3. Configure the fetcher

- Add `FETCHER_OOC_TOPIC_INFO` to the public-demo fetcher environment, including MSK bootstrap and IAM SASL Kafka properties.
- Grant the fetcher/orchestration IRSA role least-privilege `kafka-cluster:Connect`, `DescribeTopic`, and `WriteData` access.
- Roll out a platform release containing landmark 1.
- Fetch a consistency-enabled Join and verify both a normal event and `SCHEMA_PUBLISH_EVENT` reach Kafka.

### 4. Archive the Kafka topic

- Prefer an existing managed MSK-to-S3/Glue pattern if one exists.
- First evaluate MSK Connect with an Avro-capable S3 sink. Use Firehose from MSK with a small outer-Avro transformation only if the connector path is unavailable or materially more operationally expensive.
- Preserve all five raw envelope fields in the catalog table.
- Make the raw table append-only and readable by the Spark catalog used by public-demo.
- Add retention, dead-letter/error handling, and basic delivery metrics.

### 5. Add Chronon log processing configs

- Port `python/test/canary/staging_queries/gcp/partitioned_logging.py` to the demo's AWS SQL/catalog dialect.
- Add the corresponding `logging_schema` GroupBy over `SCHEMA_PUBLISH_EVENT` records.
- Add explicit table dependencies and a start partition matching the first archived data.
- Evaluate and backfill both configs, then verify schema hashes are available.

### 6. Run online/offline consistency

- Run `log-flattener` for a fetched Join, passing the normalized log table and logging-schema table.
- Run `consistency-metrics-compute` for the same Join and date range.
- Verify the logged table, comparison table, and consistency metrics table in Data Explorer.
- Add the final commands and expected output to the quickstart tutorial.

## End-to-End Acceptance Test

1. Deploy a Join with consistency logging enabled.
2. Fetch a known key through the UI or fetch API.
3. Confirm a Kafka record exists for that Join and that publishing failures remain zero.
4. Confirm the record appears in the raw Glue table.
5. Run the staging query and logging-schema GroupBy.
6. Run log flattening and confirm the fetched feature columns appear in the Join's logged table.
7. Run consistency metrics and confirm online and offline values are compared for the fetched timestamp and key.
8. Change the demo freshness lever, repeat the fetch, and demonstrate a measurable consistency/freshness difference.

## Context-Restoration Prompt

Continue the public-demo fetch logging implementation described in `infrastructure/docs/plans/public-demo-fetch-logging.md`. We are implementing Chronon `LoggableResponse` logging for AWS, not HTTP access logging. Preserve the existing Avro Kafka envelope, prefer shared MSK if reachable from public-demo, archive it into a raw Glue table, then use the canary-style `partitioned_logging` staging query, `logging_schema` GroupBy, log flattener, and consistency metrics job. Check current git state before editing and continue from the first incomplete landmark.
