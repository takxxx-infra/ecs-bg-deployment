# ##################################################
# Locals
# ##################################################
locals {
  log_group = {
    frontend-app = {
      service           = "ecs"
      retention_in_days = 14
    }
  }
}

# ##################################################
# Log Group
# ##################################################
resource "aws_cloudwatch_log_group" "this" {
  for_each          = local.log_group
  name              = "/${local.project_name}/${local.log_group.frontend-app.service}/${each.key}"
  retention_in_days = each.value.retention_in_days
}

resource "aws_cloudwatch_log_group" "ecs_bg_approval" {
  name              = "/aws/lambda/${local.approval_lambda_name}"
  retention_in_days = 14
}
