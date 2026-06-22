output "ecr_repository_url" {
  description = "Push the instrumented image here before applying."
  value       = aws_ecr_repository.juice_shop.repository_url
}

output "juice_shop_url" {
  description = "Open this in a browser once the service is healthy."
  value       = "http://${aws_lb.this.dns_name}"
}

output "log_group" {
  description = "CloudWatch log group with Juice Shop + Contrast agent logs."
  value       = aws_cloudwatch_log_group.juice_shop.name
}
