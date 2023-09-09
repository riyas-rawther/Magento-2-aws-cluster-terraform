



///////////////////////////////////////////////////[ TERRAFORM STATE LOCK ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 backend to keep terraform state lock
# # ---------------------------------------------------------------------------------------------------------------------#
terraform {
  backend "s3" {
    bucket         = "terraform-state-terraform-state"
    key            = "m2-magenx/us-west-2/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform_state"
    shared_credentials_file = "~/.aws/credentials"
    profile                 = "alignminds"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create DynamoDB table to check terraform lock state
# # ---------------------------------------------------------------------------------------------------------------------#
# resource "aws_dynamodb_table" "lock" {
#     name           = "m2-magenx-terraform-state-lock"
#     read_capacity  = 10
#     write_capacity = 10
#     hash_key       = "LockID"
#     attribute {
#         name = "LockID"
#         type = "S"
#     }
#     tags = {
#         Name = "${var.app["brand"]} ${data.aws_region.current.name} terraform state lock"
#     }
# }
