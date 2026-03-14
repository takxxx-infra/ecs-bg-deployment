# ##################################################
# Topic
# ##################################################
resource "aws_sns_topic" "ecs_bg_deployment" {
  name = "${local.project_name}-sns"
}
