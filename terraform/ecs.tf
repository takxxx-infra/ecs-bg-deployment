# ##################################################
# Locals
# ##################################################
locals {
  frontend_app = {
    desired_count = 0
  }
}

# ##################################################
# ECS Cluster
# ##################################################
resource "aws_ecs_cluster" "main" {
  name = "${local.project_name}-app"
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  capacity_providers = ["FARGATE"]
  cluster_name       = aws_ecs_cluster.main.name
}

# ##################################################
# ECS Service Frontend
# ##################################################
resource "aws_ecs_service" "frontend_app" {
  name                               = "${local.project_name}-frontend-app"
  cluster                            = aws_ecs_cluster.main.arn
  task_definition                    = aws_ecs_task_definition.frontend_app.arn
  desired_count                      = local.frontend_app.desired_count
  scheduling_strategy                = "REPLICA"
  availability_zone_rebalancing      = "ENABLED"
  platform_version                   = "LATEST"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  health_check_grace_period_seconds  = 60
  propagate_tags                     = "NONE"

  deployment_controller {
    type = "ECS"
  }
  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = "10"

    lifecycle_hook {
      hook_target_arn = aws_lambda_function.ecs_bg_approval.arn
      role_arn        = aws_iam_role.ecs_lifecycle_hook.arn
      lifecycle_stages = [
        "POST_TEST_TRAFFIC_SHIFT"
      ]
      hook_details = jsonencode({
        ActionGroup = local.approval_action_group
        ClusterArn  = aws_ecs_cluster.main.arn
        ServiceName = "${local.project_name}-frontend-app"
      })
    }
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 0
    weight            = 1
  }

  load_balancer {
    container_name   = "app"
    container_port   = 8080
    target_group_arn = aws_lb_target_group.this["frontapp-blue"].arn
    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.this["frontapp-green"].arn
      production_listener_rule   = aws_lb_listener_rule.production.arn
      test_listener_rule         = aws_lb_listener_rule.test.arn
      role_arn                   = aws_iam_role.ecs_deployment.arn
    }
  }
  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.frontend_app.id]
    subnets = [
      aws_subnet.this["private-a"].id,
      aws_subnet.this["private-c"].id
    ]
  }

  depends_on = [
    aws_iam_policy.ecs_lifecycle_hook,
    aws_lambda_permission.ecs_lifecycle_hook,
  ]
}
