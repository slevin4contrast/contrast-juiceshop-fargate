resource "aws_ecs_cluster" "this" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "juice_shop" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14
}

locals {
  # Base, non-secret agent configuration. The agent token is injected separately
  # via Secrets Manager (see the `secrets` block below), never as a plain env var.
  contrast_base_env = {
    CONTRAST__APPLICATION__NAME   = var.contrast_application_name
    CONTRAST__SERVER__NAME        = var.contrast_server_name
    CONTRAST__SERVER__ENVIRONMENT = var.contrast_server_environment
    # Protect + observe are the two ADR needs (plus a set server environment, above).
    CONTRAST__PROTECT__ENABLE = tostring(var.contrast_protect_enabled)
    CONTRAST__OBSERVE__ENABLE = tostring(var.contrast_observe_enabled)
    CONTRAST__ASSESS__ENABLE  = tostring(var.contrast_assess_enabled)
    # Send agent logs to stdout so they land in CloudWatch.
    CONTRAST__AGENT__LOGGER__STDOUT = "true"
  }

  # Merge base settings with any user-supplied overrides/additions, then shape
  # into the [{name, value}] form ECS expects. extra_contrast_env wins on conflict.
  contrast_env_map = merge(local.contrast_base_env, var.extra_contrast_env)
  contrast_env     = [for k, v in local.contrast_env_map : { name = k, value = v }]
}

resource "aws_ecs_task_definition" "juice_shop" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "juice-shop"
      image     = local.container_image
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      # Non-secret agent configuration as plain env vars (built in locals above).
      # The agent is preloaded by NODE_OPTIONS, which is baked into the image.
      environment = local.contrast_env

      # The agent token is injected from Secrets Manager, never stored in the task def.
      secrets = [
        {
          name      = "CONTRAST__API__TOKEN"
          valueFrom = aws_secretsmanager_secret.contrast_token.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.juice_shop.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "juice-shop"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "juice_shop" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.juice_shop.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # The Contrast agent rewrites application code at startup, which slows the
  # first boot. Give the task time to become healthy before the ALB health
  # check can mark it failed and trigger a restart loop. Increase this (or use
  # the agent rewriter CLI in the build) if you see tasks cycling.
  # https://support.contrastsecurity.com/hc/en-us/articles/9877427810068-Node-js-Startup-Troubleshooting
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "juice-shop"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]
}
