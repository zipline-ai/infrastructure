# infrastructure
Configuration to Initialize Zipline Infrastructure

We are using OpenTofu to manage the infrastructure

## Requirements

Required applications are:
* [aws_cli](https://docs.aws.amazon.com/eks/latest/userguide/install-awscli.html)
* [opentofu](https://opentofu.org/docs/intro/install/)
* [kubectl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)

## Steps

### Initialize Clusters
```
aws configure
cd canary-tf/
tofu apply
 ```
This will output the established App and Frontend Repo URIs for use in the next step.

### Build and Push Images
For initial setup, the Chronon images need to be built (for the established canary instance, this is pushed
automatically by a Github workflow).
The OpenTofu script outputs the addresses where the images should be uploaded.
Within the Chronon repository (not available in this repo) run the following to build the images and upload them.

Replace the addresses of the repos, as well as the aws region and account_id in the script and run:
```
export APP_REPO=[URI of App Repo]:latest
export FRONTEND_REPO=[URI of Frontend Repo]:latest

# Log Docker into aws
aws ecr get-login-password --region [region] | docker login --username AWS --password-stdin [aws_account_id].dkr.ecr.[REGION].amazonaws.com

cd [Path to Chronon]

docker build -t base_image -f ./.github/image/Dockerfile .
docker build -t zipline-ai/demo_app -f ./docker-init/Dockerfile .
docker build -t zipline-ai/demo_frontend -f ./docker-init/frontend/Dockerfile .


docker tag zipline-ai/demo_app $APP_REPO
docker push $APP_REPO

docker tag zipline-ai/demo_frontend $FRONTEND_REPO
docker push $FRONTEND_REPO

```

### Restart Canary Servers

If the servers are already running, the following commands should restart them with the new version without changing 
the address they are accessible at:

```
aws eks update-kubeconfig --region us-west-1 --name Zipline-Canary-EKS

kubectl rollout restart deployment/app
kubectl rollout restart deployment/frontend
```

### Start Servers

Once the images have been uploaded to the repositories, use the following commands to start the servers in Kubernetes:

``` 
cd canary-tf/k8s/
tofu apply
```

