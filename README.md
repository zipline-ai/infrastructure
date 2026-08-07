# Infrastructure
Configuration to Initialize Zipline Infrastructure

We are using OpenTofu to manage the infrastructure

## Requirements
To work with this repo you'll need a few tools installed on your laptop. 

* Install [asdf](https://asdf-vm.com/guide/getting-started.html#_2-download-asdf)
* ```asdf plugin add asdf-plugin-manager```
* ```asdf install asdf-plugin-manager latest```
* ```asdf-plugin-manager add-all``` (see `.plugin-versions` for required plugins)
* ```asdf-plugin-manager update-all```
* ```asdf install``` (see `.tool-versions` for required applications)

## Zipline on GCP Steps

Authenticate with Google Cloud and select the existing project to use:

```shell
gcloud auth application-default login
gcloud config set project PROJECT_ID
```

Enter the GCP orchestration wrapper directory and initialize the infrastructure:

```shell
cd gcp/zipline-orchestration
../../pull_crucible_config.sh gcp
tofu init -reconfigure -backend-config=backend.hcl
tofu apply
```

See [gcp/zipline-orchestration/README.md](gcp/zipline-orchestration/README.md)
for the required project, network, GKE, storage, database, and workload identity
configuration. The wrapper does not create the GCP project or manage DNS records.


## Zipline on AWS Steps

Initialize to  and select the project you want to use
* ``` aws configure sso ```

Enter the AWS orchestration wrapper directory and initialize the infrastructure
* ``` cd aws/zipline-orchestration ```
* ``` ../../pull_crucible_config.sh aws ```
* ``` tofu init -reconfigure -backend-config=backend.hcl ```
* ``` tofu apply ```
Fill in your company name as the customer_name variable and select the region you want to deploy to.
