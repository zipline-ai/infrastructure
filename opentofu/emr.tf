// Establishes a
resource "aws_emrcontainers_virtual_cluster" "emr_cluster" {
  name          = "zipline-emr"

 container_provider {
     id   = aws_eks_cluster.zipline_demo_eks.name
     type = "EKS"

     info {
       eks_info {
         namespace = kubernetes_namespace.demo_emr.metadata.0.name
       }
     }
   }

 }

resource "kubernetes_namespace" "demo_emr" {
  metadata {
    name = "demo-emr"
  }
}