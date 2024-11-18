// Establishes a
resource "aws_emrcontainers_virtual_cluster" "emr_cluster" {
  name          = "zipline-emr"

 container_provider {
     id   = data.aws_eks_cluster.zipline_canary_eks.name
     type = "EKS"

     info {
       eks_info {
         namespace = kubernetes_namespace.canary_emr.metadata.0.name
       }
     }
   }

 }

resource "kubernetes_namespace" "canary_emr" {
  metadata {
    name = "canary-emr"
  }
}

resource "kubernetes_deployment" "emr_deployment" {
  metadata {
    name      = "emr-server"
    namespace = kubernetes_namespace.canary_emr.metadata.0.name
    labels = {
      service = "emr-server"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        service = "emr-server"
      }
    }
    template {
      metadata {
        labels = {
          service = "emr-server"
        }
      }
      spec {
        container {
          name = "emr-server"
          image = "608033475327.dkr.ecr.us-west-1.amazonaws.com/notebook-python/emr-7.3.0:latest"
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [
      spec[0].template[0].metadata[0].annotations["kubectl.kubernetes.io/restartedAt"],
    ]
  }
}