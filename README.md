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

Enter the zipline-gcp directory and initialize the infrastructure
* ``` cd zipline-aws ```
* ``` tofu init ```
* ``` tofu apply ```
Fill in your company name as the customer_name variable and select the region you want to deploy to.


## Canary Steps

### Initialize AWS Canary Clusters
```
aws configure
cd canary-aws/
tofu init
tofu apply
 ```

### Initialize AWS Dev Clusters
```
aws configure
cd dev-aws/
tofu init -var user=$USER
tofu apply -var user=$USER
 ```

### Images
The images are automatically pushed from the chronon repository for the kubernetes deployments.

### Restart Canary Servers

If the servers are already running, the following commands should restart them with the new version without changing 
the address they are accessible at:

```
aws eks update-kubeconfig --region us-west-1 --name Zipline-Canary-EKS

kubectl rollout restart deployment/app
kubectl rollout restart deployment/frontend
```

