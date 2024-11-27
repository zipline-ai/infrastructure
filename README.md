# infrastructure
Configuration to Initialize Zipline Infrastructure

We are using OpenTofu to manage the infrastructure

## Requirements

Required applications are:
* [aws_cli](https://docs.aws.amazon.com/eks/latest/userguide/install-awscli.html)
* [opentofu](https://opentofu.org/docs/intro/install/)
* [kubectl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)

## Steps

### Initialize AWS Canary Clusters
```
aws configure
cd canary-aws/
tofu init
tofu apply
 ```

### Initialize Dev Clusters
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

