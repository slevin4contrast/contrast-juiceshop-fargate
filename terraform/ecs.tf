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

      # Non-secret, application-specific agent configuration as plain env vars.
      # The agent is preloaded by NODE_OPTIONS, which is baked into the image.
      environment = [
        { name = "CONTRAST__APPLICATION__NAME", value = var.contrast_application_name },
        { name = "CONTRAST__SERVER__NAME", value = var.contrast_server_name },
        { name = "CONTRAST__SERVER__ENVIRONMENT", value = var.contrast_server_environment },
        # Send agent logs to stdout so they land in CloudWatch.
        { name = "CONTRAST__AGENT__LOGGER__STDOUT", value = "true" }
      ]

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
