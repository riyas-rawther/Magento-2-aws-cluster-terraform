
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
  }
}


provider "aws" {
region = "us-west-2"
default_tags {
   tags = {
   Managed      = "terraform"
   Config       = "magenx"
   Environment  = "development"
  }
 }
}

provider "null" {}
provider "random" {}

