# Infrastructure
Configuration to Initialize Zipline Infrastructure

We are using OpenTofu to manage the infrastructure

## Zipline on GCP Steps

Initialize to gcloud and select the project you want to use
* ``` gcloud auth application-default login ```
* ``` gcloud init ```

Enter the zipline-gcp directory and initialize the infrastructure
* ``` cd zipline-gcp ```
* ``` tofu init ```
* ``` tofu apply ```
Fill in your company name as the customer_name variable and select the region you want to deploy to.


## Zipline on AWS Steps

Initialize to  and select the project you want to use
* ``` aws configure sso ```

Enter the AWS orchestration wrapper directory and initialize the infrastructure
* ``` cd aws/zipline-orchestration ```
* ``` ../../pull_crucible_config.sh aws ```
* ``` tofu init -reconfigure -backend-config=backend.hcl ```
* ``` tofu apply ```
Fill in your company name as the customer_name variable and select the region you want to deploy to.
