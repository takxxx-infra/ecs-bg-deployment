# ##################################################
# ECS Blue/Green Deployment
# ##################################################
resource "aws_iam_role" "ecs_deployment" {
  name = "${local.project_name}-ecs-deployment"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_deployment" {
  for_each = {
    ecs         = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
    ecs_for_alb = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
  }
  role       = aws_iam_role.ecs_deployment.name
  policy_arn = each.value
}

# ##################################################
# ECS Blue/Green Approval
# ##################################################
resource "aws_iam_role" "ecs_bg_approval_lambda" {
  name = "${local.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# ##################################################
# ECS Lifecycle Hook Role
# ##################################################
resource "aws_iam_role" "ecs_lifecycle_hook" {
  name = "${local.project_name}-ecs-lifecycle-hook"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_lifecycle_hook" {
  for_each = {
    lambda = aws_iam_policy.ecs_lifecycle_hook.arn
  }
  role       = aws_iam_role.ecs_lifecycle_hook.name
  policy_arn = each.value
}

# ##################################################
# ECS Task Execution Role
# ##################################################
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.project_name}-ecs-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  for_each = {
    ecs_task = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  }
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = each.value
}

# ##################################################
# Amazon Q Developer chat Channel Role
# ##################################################
resource "aws_iam_role" "chatbot_channel" {
  name = "${local.project_name}-q-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "chatbot.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "q_developer_chat_chanel" {
  for_each = {
    parameter_store = aws_iam_policy.chatbot_custom_actions.arn
  }
  role       = aws_iam_role.chatbot_channel.name
  policy_arn = each.value
}
