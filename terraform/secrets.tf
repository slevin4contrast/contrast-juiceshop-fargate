# Store the Contrast agent token in AWS Secrets Manager. The ECS task pulls it at
# launch and injects it as the CONTRAST__API__TOKEN environment variable, so the
# token never appears in the task definition, image, or logs.
#
# Contrast's recommended pattern for cloud providers: keep credentials in a
# secrets manager and link them to the agent's environment variables.
# https://docs.contrastsecurity.com/en/install-node-js-agent-in-a-container.html
# https://docs.contrastsecurity.com/en/find-the-agent-keys.html

resource "aws_secretsmanager_secret" "contrast_token" {
  name        = "${var.project_name}/contrast-api-token"
  description = "Contrast agent token (CONTRAST__API__TOKEN) for Juice Shop on Fargate."
}

resource "aws_secretsmanager_secret_version" "contrast_token" {
  secret_id     = aws_secretsmanager_secret.contrast_token.id
  secret_string = var.contrast_api_token
}
