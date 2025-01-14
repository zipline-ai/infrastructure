// Establishes the image repos for the app and the frontend

data "aws_ecr_repository" "app" {
  name = "zipline-ai/canary-app"
}

data "aws_ecr_repository" "frontend" {
  name = "zipline-ai/canary-frontend"
}

# resource "aws_ecr_repository" "app" {
#   name                 = "zipline-ai/canary-app"
#   image_tag_mutability = "MUTABLE"
#
#   image_scanning_configuration {
#     scan_on_push = true
#   }
# }
#
# resource "aws_ecr_repository" "frontend" {
#   name                 = "zipline-ai/canary-frontend"
#   image_tag_mutability = "MUTABLE"
#
#   image_scanning_configuration {
#     scan_on_push = true
#   }
# }
#
# output "app_repo" {
#   value = data.aws_ecr_repository.app.repository_url
# }
#
# output "frontend_repo" {
#   value = aws_ecr_repository.frontend.repository_url
# }