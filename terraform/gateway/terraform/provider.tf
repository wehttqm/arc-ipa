terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    acl                  = "private"
    bucket               = "arcteryx-pf-sandbox"
    encrypt              = true
    use_lockfile         = true
    key                  = "agentcore/gateway/terraform.tfstate"
    workspace_key_prefix = "agentcore"
    region               = "us-west-2"
  }
}

provider "aws" {
  region = var.region
}
