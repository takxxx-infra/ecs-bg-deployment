# ##################################################
# Locals
# ##################################################
locals {
  approval_action_value = "approved"
  rollback_action_value = "rollback"
  chatbot_custom_action_command = {
    // 再ルーティング用パラメーターをセットするコマンド
    approve = "ssm put-parameter --name $ParameterName --value ${local.approval_action_value} --type String --region ${local.region}"
    // ロールバック用パラメーターをセットするコマンド
    rollback = "ssm put-parameter --name $RollbackParameterName --value ${local.rollback_action_value} --type String --region ${local.region}"
  }

  approval_action_group = "ecs-bg-approval"
  approve_action_name   = "${local.project_name}-ecs-bg-reroute"
  rollback_action_name  = "${local.project_name}-ecs-bg-rollback"
  approve_action_alias  = "${local.project_name}-reroute"
  rollback_action_alias = "${local.project_name}-rollback"
}

# ##################################################
# Chatbot Custom Action Definitions
# ##################################################
resource "awscc_chatbot_custom_action" "approve" {
  provider    = awscc.awscc
  action_name = local.approve_action_name
  alias_name  = local.approve_action_alias //alias_name は30文字制限

  definition = {
    command_text = local.chatbot_custom_action_command.approve
  }

  attachments = [
    {
      button_text       = "🔁 再ルーティング"
      notification_type = "Custom"
      criteria = [
        {
          operator      = "EQUALS"
          variable_name = "ActionGroup"
          value         = local.approval_action_group
        }
      ]
      variables = {
        ActionGroup   = "event.metadata.additionalContext.ActionGroup"
        ParameterName = "event.metadata.additionalContext.ParameterName"
      }
    }
  ]
}

resource "awscc_chatbot_custom_action" "rollback" {
  provider    = awscc.awscc
  action_name = local.rollback_action_name
  alias_name  = local.rollback_action_alias

  definition = {
    command_text = local.chatbot_custom_action_command.rollback
  }

  attachments = [
    {
      button_text       = "🔙 ロールバック"
      notification_type = "Custom"
      criteria = [
        {
          operator      = "EQUALS"
          variable_name = "ActionGroup"
          value         = local.approval_action_group
        }
      ]
      variables = {
        ActionGroup           = "event.metadata.additionalContext.ActionGroup"
        RollbackParameterName = "event.metadata.additionalContext.RollbackParameterName"
      }
    }
  ]
}
