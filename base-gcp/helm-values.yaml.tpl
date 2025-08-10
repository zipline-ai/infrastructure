global:
  customer_name: "${customer_name}"
  region: "${region}"
  project_id: "${project_id}"
  artifact_prefix: "${artifact_prefix}"
  topic_id: "${topic_id}"

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
  temporalUI: "${temporal_ui_ip}"
  orchestrationHub: "${orchestration_hub_ip}"