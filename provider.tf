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
#  alias  = "useast2"
  region = "us-west-2"
  # access_key = ""
  # secret_key = ""
  profile = "alignminds"
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

