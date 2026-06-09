terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.21"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  backend "s3" {
    acl                  = "private"
    bucket               = "arcteryx-pf-sandbox"
    encrypt              = true
    use_lockfile         = true
    key                  = "agentcore/terraform.tfstate"
    workspace_key_prefix = "terraform-state-backend"
    region               = "us-west-2"
  }
}

provider "aws" {
  region = var.region
}
