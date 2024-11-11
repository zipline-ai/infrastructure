// Establishes the image repos for the app and the frontend
resource "aws_ecr_repository" "app" {
  name                 = "zipline-ai/demo-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "zipline-ai/demo-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "app_repo" {
  value = aws_ecr_repository.app.repository_url
}

output "frontend_repo" {
  value = aws_ecr_repository.frontend.repository_url
}