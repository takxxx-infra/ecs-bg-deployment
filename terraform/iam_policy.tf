# ##################################################
# ECS Blue/Green Approval Policies
# ##################################################
resource "aws_iam_role_policy" "ecs_bg_approval_lambda" {
  name = "${local.approval_lambda_name}-policy"
  role = aws_iam_role.ecs_bg_approval_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.approval_lambda_name}:*",
          "arn:${data.aws_partition.current.partition}:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.approval_lambda_name}:*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/ecs-bg-approval/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "${aws_sns_topic.ecs_bg_deployment.arn}"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:ListServiceDeployments",
          "ecs:DescribeServiceDeployments"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_lifecycle_hook" {
  name = "${local.project_name}-ecs-lifecycle-hook"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "lambda:InvokeFunction"
      ]
      Resource = aws_lambda_function.ecs_bg_approval.arn
    }]
  })
}

resource "aws_iam_policy" "chatbot_custom_actions" {
  name = "${local.project_name}-chatbot-custom-actions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/ecs-bg-approval/*"
      }
    ]
  })
}
