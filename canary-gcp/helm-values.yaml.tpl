global:
  customer_name: "${customer_name}"
  region: "${region}"
  project_id: "${project_id}"
  artifact_prefix: "${artifact_prefix}"
  version: "${version}"

database:
  temporal:
    host: "${temporal_db_host}"
    username: "${temporal_db_username}"
    password: "${temporal_db_password}"
    database: "${temporal_db_database}"
  orchestration:
    host: "${orchestration_db_host}"
    username: "${orchestration_db_username}"
    password: "${orchestration_db_password}"
    database: "${orchestration_db_database}"

bigtable:
  instance_id: "${bigtable_instance_id}"
  table_partitions_dataset: "${bigtable_table_partitions_dataset}"

serviceAccount:
  temporal:
    googleServiceAccount: "${temporal_service_account}"
  orchestration:
    googleServiceAccount: "${orchestration_service_account}"

domains:
  ziplineUI: "${zipline_ui_domain}"
  temporal: "${temporal_domain}"
  hub: "${hub_domain}"

staticIPs:
  orchestrationUI: "${orchestration_ui_ip}"
  orchestrationUIName: "${orchestration_ui_ip_name}"
  temporalUI: "${temporal_ui_ip}"
  temporalUIName: "${temporal_ui_ip_name}"
  orchestrationHub: "${orchestration_hub_ip}"
  orchestrationHubName: "${orchestration_hub_ip_name}"

ingress:
    sslPolicy: "${gke_ssl_policy_name}"