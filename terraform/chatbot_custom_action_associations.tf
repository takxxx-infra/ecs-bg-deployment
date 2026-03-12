# ##################################################
# Chatbot Slack Channel Configuration
# ##################################################
resource "awscc_chatbot_slack_channel_configuration" "main" {
  provider = awscc.awscc

  configuration_name = local.project_name
  customization_resource_arns = [
    awscc_chatbot_custom_action.approve.id,
    awscc_chatbot_custom_action.rollback.id,
  ]
  guardrail_policies = [
    aws_iam_policy.chatbot_custom_actions.arn,
  ]
  iam_role_arn       = aws_iam_role.chatbot_channel.arn
  slack_channel_id   = var.slack_channel_id
  slack_workspace_id = var.slack_workspace_id
  sns_topic_arns = [
    aws_sns_topic.ecs_bg_deployment.arn
  ]
  user_role_required = false

  depends_on = [
    aws_iam_role_policy_attachment.q_developer_chat_chanel,
  ]
}
