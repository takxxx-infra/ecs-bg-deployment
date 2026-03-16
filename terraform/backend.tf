terraform {
  backend "s3" {
    bucket       = "ecs-bg-deployment-xxxxxxxxxxxx"
    key          = "tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
  }
}
