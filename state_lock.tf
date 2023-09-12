



///////////////////////////////////////////////////[ TERRAFORM STATE LOCK ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 backend to keep terraform state lock
# # ---------------------------------------------------------------------------------------------------------------------#
terraform {
  backend "s3" {
    bucket         = "terraform-state-terraform-state"
    key            = "m2-dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform_state"
  }
}