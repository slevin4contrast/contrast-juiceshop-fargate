# Container registry for the instrumented image.
# Build and push to this repo before running `terraform apply` (see TUTORIAL.md).

resource "aws_ecr_repository" "juice_shop" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

locals {
  # Use the explicit image override if given, otherwise the :latest tag in the ECR repo above.
  container_image = var.container_image != "" ? var.container_image : "${aws_ecr_repository.juice_shop.repository_url}:latest"
}
