


//////////////////////////////////////////////////////////[ S3 BUCKET ]///////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket" "this" {
  for_each      = var.s3
  bucket        = "${local.project}-${random_string.s3[each.key].id}-${each.key}"
  force_destroy = true
  tags = {
    Name = "${local.project}-${random_string.s3[each.key].id}-${each.key}"
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = var.s3
  bucket = "${local.project}-${random_string.s3[each.key].id}-${each.key}"
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket ACL
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_acl" "this" {
  for_each = var.s3
  bucket   = "${local.project}-${random_string.s3[each.key].id}-${each.key}"
  acl      = "private"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket versioning
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this["state"].id
  versioning_configuration {
    status = "Enabled"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket encryption
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.s3
  bucket   = "${local.project}-${random_string.s3[each.key].id}-${each.key}"
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Block public access acl for internal S3 buckets
# # ---------------------------------------------------------------------------------------------------------------------#	  
resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = { for name in var.s3 : name => name if name != "media" }
  bucket                  = "${local.project}-${random_string.s3[each.key].id}-${each.key}"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create policy for CloudFront to limit S3 media bucket access
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.this["media"].id
  policy = jsonencode({
    Id = "PolicyForMediaStorageAccess"
    Statement = [
      {
        Action = "s3:GetObject"
        Effect = "Allow"
        Principal = {
          "Service": "cloudfront.amazonaws.com"
        }
        Resource = [
          "${aws_s3_bucket.this["media"].arn}/*.jpg",
          "${aws_s3_bucket.this["media"].arn}/*.jpeg",
          "${aws_s3_bucket.this["media"].arn}/*.png",
          "${aws_s3_bucket.this["media"].arn}/*.gif",
          "${aws_s3_bucket.this["media"].arn}/*.webp"
        ]
      },
      {
        Action = ["s3:PutObject"],
        Effect = "Allow"
        Principal = {
          "Service": "cloudfront.amazonaws.com"
        }
        Resource = [
          "${aws_s3_bucket.this["media"].arn}",
          "${aws_s3_bucket.this["media"].arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceVpc" = [aws_vpc.this.id]
          }
        }
      },
      {
        Action = ["s3:GetObject", "s3:GetObjectAcl"],
        Effect = "Allow"
        Principal = {
          "Service": "cloudfront.amazonaws.com"
        }
        Resource = [
          "${aws_s3_bucket.this["media"].arn}",
          "${aws_s3_bucket.this["media"].arn}/*"
        ]
      },
      {
        Action = ["s3:GetBucketLocation", "s3:ListBucket"],
        Effect = "Allow"
        Principal = {
          "Service": "cloudfront.amazonaws.com"
        }
        Resource = "${aws_s3_bucket.this["media"].arn}"
      },
    ]
    Version = "2012-10-17"
  })
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket policy for ALB to write access logs
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_policy" "system" {
  bucket = aws_s3_bucket.this["system"].id
  policy = jsonencode(
    {
      Id      = "PolicyALBWriteLogs"
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:PutObject"
          ],
          Effect   = "Allow"
          Resource = "${aws_s3_bucket.this["system"].arn}/ALB/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
          Principal = {
             type        = "AWS"
             identifiers = [data.aws_elb_service_account.current.arn]
          }
        },
        {
          Action = [
            "s3:PutObject",
            "s3:GetObject"
          ],
          Effect   = "Allow"
          Resource = "${aws_s3_bucket.this["system"].arn}/*"
          Principal = {
            AWS = [
              aws_iam_role.codebuild.arn,
              aws_iam_role.codepipeline.arn,
              aws_iam_role.config.arn
            ]
          }
        }
      ]
  })
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket policy for CodePipeline access
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.this["backup"].id
  policy = jsonencode({
    Id      = "PolicyForBackupBucket"
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject"
        ],
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.this["backup"].arn}/*"
        Principal = {
          AWS = [
            aws_iam_role.codebuild.arn,
            aws_iam_role.codepipeline.arn,
            aws_iam_role.codedeploy.arn
          ]
        }
      }
    ]
  })
}


