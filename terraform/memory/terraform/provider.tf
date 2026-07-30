terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      # aws_bedrockagentcore_memory / _memory_strategy are recent additions;
      # 6.56 is the earliest version verified to carry both resources.
      source  = "hashicorp/aws"
      version = "~> 6.56"
    }
  }

  backend "s3" {
    acl                  = "private"
    bucket               = "arcteryx-pf-sandbox"
    encrypt              = true
    use_lockfile         = true
    key                  = "agentcore/memory/terraform.tfstate"
    workspace_key_prefix = "agentcore"
    region               = "us-west-2"
  }
}

provider "aws" {
  region = var.region
}
