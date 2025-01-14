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


## Zipline on AWS Steps

Initialize to  and select the project you want to use
* ``` gcloud auth application-default login ```
* ``` gcloud init ```

Enter the zipline-gcp directory and initialize the infrastructure
* ``` cd zipline-gcp ```
* ``` tofu init ```
* ``` tofu apply ```


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
The images are automatically pushed from the chronon repository for AWS ECR and GCP Artifact Registry.

### Push Kubernetes Services
Use the Kustomization files to push the services to the Kubernetes clusters.

To push the gcp services:
```
gcloud container clusters get-credentials [CLUSTER_NAME] --region [REGION]
kubectl apply -k k8s/gcp
```

To push the aws services:
```
aws eks update-kubeconfig --region [REGION] --name [CLUSTER_NAME]
kubectl apply -k k8s/aws
```

### Restart Canary Servers

If the servers are already running, the following commands should restart them with the new version without changing 
the address they are accessible at:

AWS:
```
aws eks update-kubeconfig --region us-west-1 --name Zipline-Canary-EKS

kubectl rollout restart deployment/app
kubectl rollout restart deployment/frontend
```

GCP:
```
gcloud container clusters get-credentials dataplane-cluster --region us-west1

kubectl rollout restart deployment/app
kubectl rollout restart deployment/frontend
```