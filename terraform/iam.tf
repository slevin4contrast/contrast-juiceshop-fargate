# Two roles per ECS best practice:
#   - execution role: used by the ECS agent to pull the image, write logs, and
#     read the Contrast token from Secrets Manager at task launch.
#   - task role: assumed by the app itself (kept minimal here).

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to read just the Contrast token secret.
data "aws_iam_policy_document" "read_contrast_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.contrast_token.arn]
  }
}

resource "aws_iam_role_policy" "read_contrast_secret" {
  name   = "${var.project_name}-read-contrast-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.read_contrast_secret.json
}

resource "aws_iam_role" "task" {
  name               = "${var.project_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}
