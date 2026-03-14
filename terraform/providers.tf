terraform {
  required_version = "~> 1.14.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.30"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.74"
    }
  }
}

provider "aws" {
  region = local.region
}

provider "awscc" {
  alias  = "awscc"
  region = local.chatbot_region
}
