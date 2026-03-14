# ##################################################
# Locals
# ##################################################
locals {
  image_tag = {
    frontend_app = "v1"
  }
}

# ##################################################
# ECS Task Definition
# ##################################################
resource "aws_ecs_task_definition" "frontend_app" {
  family                   = "${local.project_name}-frontend-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.this["frontend-app"].repository_url}:${local.image_tag.frontend_app}"
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]
    environment = [
      {
        name  = "APP_NAME"
        value = local.project_name
      },
      {
        name  = "APP_VERSION"
        value = local.image_tag.frontend_app
      }
    ]
    cpu               = 0
    memoryReservation = 512
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "${aws_cloudwatch_log_group.this["frontend-app"].name}"
        awslogs-region        = "${local.region}"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}
