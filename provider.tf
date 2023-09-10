terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.13.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  alias = "east"
  region = "us-east-1"
 # profile = "foa"
  }

provider "aws" {
  alias  = "west"
# alias is used becuase WAF rule with CloudFront should be created at N. Virginia
  region = "us-west-2"
  # access_key = ""
  # secret_key = ""
 # profile = "foa"
  default_tags {
    tags = {
      Managed     = "terraform"
      Config      = "magenx"
      Environment = "development"
    }
  }
}
provider "null" {}
provider "random" {}
provider "template" {}
provider "external" {}

