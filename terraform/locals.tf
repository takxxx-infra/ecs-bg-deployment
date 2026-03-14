locals {
  project_name   = "ecs-bg-deployment"
  region         = "ap-northeast-1"
  chatbot_region = "us-east-2"

  az = {
    a = data.aws_availability_zones.available.names[0]
    c = data.aws_availability_zones.available.names[1]
  }
}
