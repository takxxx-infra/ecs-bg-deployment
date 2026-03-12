terraform {
  backend "s3" {
    bucket       = "ecs-bg-deployment-682120332115"
    key          = "tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
  }
}
