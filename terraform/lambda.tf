# ##################################################
# Locals
# ##################################################
locals {
  approval_lambda_name              = "${local.project_name}-ecs-bg-approval"
  approval_parameter_prefix_trimmed = trimsuffix("/ecs-bg-approval", "/")

  lambda_params = {
    runtime     = "python3.12"
    timeout     = 30
    memory_size = 256
    environment = {
      callback_delay_seconds = "0"
    }
  }
}

# ##################################################
# Lifecycle Hook Lambda
# ##################################################
data "archive_file" "ecs_bg_approval" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lifecycle_hook_handler.py"
  output_path = "${path.module}/.terraform/${local.approval_lambda_name}.zip"
}

resource "aws_lambda_function" "ecs_bg_approval" {
  function_name    = local.approval_lambda_name
  filename         = data.archive_file.ecs_bg_approval.output_path
  source_code_hash = data.archive_file.ecs_bg_approval.output_base64sha256
  role             = aws_iam_role.ecs_bg_approval_lambda.arn
  handler          = "lifecycle_hook_handler.lambda_handler"
  runtime          = local.lambda_params.runtime
  timeout          = local.lambda_params.timeout
  memory_size      = local.lambda_params.memory_size

  environment {
    variables = {
      ACTION_GROUP              = local.approval_action_group
      APPROVAL_PARAMETER_PREFIX = local.approval_parameter_prefix_trimmed
      APPROVAL_SNS_TOPIC_ARN    = aws_sns_topic.ecs_bg_deployment.arn
      APPROVAL_VALUE            = local.approval_action_value
      ROLLBACK_VALUE            = local.rollback_action_value
      CALLBACK_DELAY_SECONDS    = local.lambda_params.environment.callback_delay_seconds
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.ecs_bg_approval,
    aws_iam_role_policy.ecs_bg_approval_lambda,
  ]
}

resource "aws_lambda_permission" "ecs_lifecycle_hook" {
  statement_id   = "AllowExecutionFromECSLifecycleHooks"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ecs_bg_approval.function_name
  principal      = "ecs.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}
