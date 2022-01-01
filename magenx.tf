


/////////////////////////////////////////////////[ AWS BUDGET NOTIFICATION ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create alert when your budget thresholds are forecasted to exceed
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_budgets_budget" "all" {
  name              = "${var.app["brand"]}-budget-monthly-forecasted"
  budget_type       = "COST"
  limit_amount      = "2000"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.app["admin_email"]]
  }
}



///////////////////////////////////////////////////[ RANDOM STRING GENERATOR ]////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random uuid string that is intended to be used as unique identifier
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_uuid" "this" {
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "this" {
  for_each         = toset(["rds", "rabbitmq", "app", "blowfish"])
  length           = (each.key == "blowfish" ? 32 : 16)
  lower            = true
  upper            = true
  number           = true
  special          = true
  override_special = "%*?"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random string
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_string" "this" {
  for_each       = toset(["admin_path", "mysql_path", "profiler", "persistent", "id_prefix", "health_check"])
  length         = (each.key == "id_prefix" ? 3 : 7)
  lower          = true
  number         = true
  special        = false
  upper          = false
}



////////////////////////////////////////////////////////[ VPC NETWORKING ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_vpc" "this" {
  cidr_block           = var.app["cidr_block"]
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.app["brand"]}-vpc"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create subnets for each AZ in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_subnet" "this" {
  for_each                = data.aws_availability_zone.all
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 4, var.az_number[each.value.name_suffix])
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.app["brand"]}-subnet"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create RDS subnet group in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_db_subnet_group" "this" {
  name       = "${var.app["brand"]}-db-subnet"
  description = "${var.app["brand"]} RDS Subnet"
  subnet_ids = values(aws_subnet.this).*.id
  tags = {
    Name = "${var.app["brand"]}-db-subnet"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create ElastiCache subnet group in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_elasticache_subnet_group" "this" {
  description = "${var.app["brand"]} ElastiCache Subnet"
  name       = "${var.app["brand"]}-elasticache-subnet"
  subnet_ids = values(aws_subnet.this).*.id 
  tags = {
    Name = "${var.app["brand"]}-elasticache-subnet"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create internet gateway in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "${var.app["brand"]}-igw"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create route table in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_route" "this" {
  route_table_id         = aws_vpc.this.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Assign AZ subnets to route table in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_route_table_association" "this" {
  for_each       = aws_subnet.this
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_vpc.this.main_route_table_id
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create DHCP options in our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_vpc_dhcp_options" "this" {
  domain_name          = "${data.aws_region.current.name}.compute.internal"
  domain_name_servers  = ["AmazonProvidedDNS"]
  tags = {
    Name = "${var.app["brand"]}-dhcp"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Assign DHCP options to our dedicated VPC
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_vpc_dhcp_options_association" "this" {
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this.id
}



////////////////////////////////////////////////////[ SNS SUBSCRIPTION TOPIC ]////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SNS topic and email subscription (confirm email right after resource creation)
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_sns_topic" "default" {
  name = "${var.app["brand"]}-email-alerts"
}
resource "aws_sns_topic_subscription" "default" {
  topic_arn = aws_sns_topic.default.arn
  protocol  = "email"
  endpoint  = var.app["admin_email"]
}



///////////////////////////////////////////////////[ AWS CERTIFICATE MANAGER ]////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create and validate ssl certificate for domain and subdomains
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_acm_certificate" "default" {
  domain_name               = "${var.app["domain"]}"
  subject_alternative_names = ["*.${var.app["domain"]}"]
  validation_method         = "EMAIL"

lifecycle {
    create_before_destroy   = true
  }
}

resource "aws_acm_certificate_validation" "default" {
  certificate_arn = aws_acm_certificate.default.arn
}



///////////////////////////////////////////////////[ ELASTIC FILE SYSTEM ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create EFS file system
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_efs_file_system" "this" {
  creation_token = "${var.app["brand"]}-efs-storage"
  tags = {
    Name = "${var.app["brand"]}-efs-storage"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create EFS mount target for each subnet
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_efs_mount_target" "this" {
  for_each        = aws_subnet.this
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = aws_subnet.this[each.key].id
  security_groups = [aws_security_group.efs.id]
}



////////////////////////////////////////////////////////[ CODECOMMIT ]////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create CodeCommit repository for application code
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_codecommit_repository" "app" {
  repository_name = var.app["domain"]
  description     = "Magento 2.x code for ${var.app["domain"]}"
    tags = {
    Name = "${var.app["brand"]}-${var.app["domain"]}"
  }
  provisioner "local-exec" {
  interpreter = ["/bin/bash", "-c"]
  command = <<EOF
          git clone ${var.app["source"]} /tmp/magento
          cd /tmp/magento
          git remote add origin codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.app.repository_name}
          git branch -m main
          git push codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.app.repository_name} main
          rm -rf /tmp/magento
EOF
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CodeCommit repository for services configuration
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_codecommit_repository" "services" {
  repository_name = "${var.app["brand"]}-services-config"
  description     = "EC2 linux and services configurations"
    tags = {
    Name = "${var.app["brand"]}-services-config"
  }
  provisioner "local-exec" {
  interpreter = ["/bin/bash", "-c"]
  command = <<EOF
          cd ${abspath(path.root)}/services/nginx
          git init
          git commit --allow-empty -m "main branch"
          git branch -m main
          git push codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.services.repository_name} main

          git branch -m nginx_admin
          git add .
          git commit -m "nginx_ec2_config"
          git push codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.services.repository_name} nginx_admin

          git branch -m nginx_frontend
          git push codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.services.repository_name} nginx_frontend
		  
          git branch -m nginx_staging
          git push codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.services.repository_name} nginx_staging
          rm -rf .git
EOF
  }
}



/////////////////////////////////////////////////////[ EC2 INSTANCE PROFILE ]/////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create EC2 service role
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role" "ec2" {
  for_each = var.ec2
  name = "${var.app["brand"]}-EC2InstanceRole-${each.key}-${data.aws_region.current.name}"
  description = "Allows EC2 instances to call AWS services on your behalf"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Attach policies to EC2 service role
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy_attachment" "ec2" {
  for_each = { for policy in [ for role,policy in setproduct(keys(var.ec2),var.ec2_instance_profile_policy): { role = policy[0] , policy = policy[1]} ] : "${policy.role}-${policy.policy}" => policy }
  role       = aws_iam_role.ec2[each.value.role].name
  policy_arn = each.value.policy
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create inline policy for EC2 service role to publish sns message
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "sns_publish" {
  for_each = var.ec2
  name = "EC2ProfileSNSPublishPolicy${title(each.key)}"
  role = aws_iam_role.ec2[each.key].id

  policy = jsonencode({
  Version = "2012-10-17",
  Statement = [
    {
      Sid    = "EC2ProfileSNSPublishPolicy${each.key}",
      Effect = "Allow",
      Action = [
            "sns:Publish"
      ],
      Resource = aws_sns_topic.default.arn
 }]
})
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create inline policy for EC2 service role to limit CodeCommit access
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "codecommit_access" {
  for_each = var.ec2
  name = "PolicyForCodeCommitAccess${title(each.key)}"
  role = aws_iam_role.ec2[each.key].id

  policy = jsonencode({
  Version = "2012-10-17",
  Statement = [
    {
      Sid    = "codecommitaccessapp${each.key}",
      Effect = "Allow",
      Action = [
            "codecommit:Get*",
            "codecommit:List*",
            "codecommit:Merge*",
            "codecommit:GitPull",
            "codecommit:GitPush"
      ],
      Resource = aws_codecommit_repository.app.arn
      Condition = {
                StringEqualsIfExists = {
                    "codecommit:References" = [(each.key == "admin" || each.key == "frontend" ? "refs/heads/main" : (each.key == "staging" ? "refs/heads/staging" : "refs/heads/build"))]
    }
   }
},
     {
      Sid    = "codecommitaccessservices${each.key}", 
      Effect = "Allow",
      Action = [
            "codecommit:Get*",
            "codecommit:List*",
            "codecommit:Describe*",
            "codecommit:GitPull"
      ],
      Resource = aws_codecommit_repository.services.arn
    }]
})
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create EC2 Instance Profile
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_instance_profile" "ec2" {
  for_each = var.ec2
  name     = "${var.app["brand"]}-EC2InstanceProfile-${each.key}"
  role     = aws_iam_role.ec2[each.key].name
}


/////////////////////////////////////////////////////[ AMAZON RABBITMQ BROKER ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create RabbitMQ - queue message broker
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_mq_broker" "this" {
  broker_name = "${var.app["brand"]}-${var.rabbitmq["broker_name"]}"
  engine_type        = "RabbitMQ"
  engine_version     = var.rabbitmq["engine_version"]
  host_instance_type = var.rabbitmq["host_instance_type"]
  security_groups    = [aws_security_group.rabbitmq.id]
  subnet_ids         = [values(aws_subnet.this).0.id]
  user {
    username = var.app["brand"]
    password = random_password.this["rabbitmq"].result
  }
  tags = {
    Name   = "${var.app["brand"]}-${var.rabbitmq["broker_name"]}"
  }
}



//////////////////////////////////////////////////////////[ ELASTICACHE ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ElastiCache parameter groups
# # ---------------------------------------------------------------------------------------------------------------------#		  
resource "aws_elasticache_parameter_group" "this" {
  for_each      = toset(var.redis["name"])
  name          = "${var.app["brand"]}-${each.key}-parameter"
  family        = "redis6.x"
  description   = "Parameter group for ${var.app["domain"]} ${each.key} backend"
  parameter {
    name  = "cluster-enabled"
    value = "no"
  }
  tags = {
    Name = "${var.app["brand"]}-${each.key}-parameter"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create ElastiCache - Redis Replication group - session + cache
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_elasticache_replication_group" "this" {
  for_each                      = toset(var.redis["name"])
  number_cache_clusters         = length(values(aws_subnet.this).*.id)
  engine                        = "redis"
  engine_version                = var.redis["engine_version"]
  replication_group_id          = "${var.app["brand"]}-${each.key}-backend"
  replication_group_description = "Replication group for ${var.app["domain"]} ${each.key} backend"
  node_type                     = var.redis["node_type"]
  port                          = var.redis["port"]
  parameter_group_name          = aws_elasticache_parameter_group.this[each.key].id
  security_group_ids            = [aws_security_group.redis.id]
  subnet_group_name             = aws_elasticache_subnet_group.this.name
  automatic_failover_enabled    = var.redis["automatic_failover_enabled"]
  multi_az_enabled              = var.redis["multi_az_enabled"]
  notification_topic_arn        = aws_sns_topic.default.arn
  tags = {
    Name = "${var.app["brand"]}-${each.key}-backend"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch CPU Utilization metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "elasticache_cpu" {
  for_each            = aws_elasticache_replication_group.this
  alarm_name          = "${var.app["brand"]}-elasticache-${each.key}-cpu-utilization"
  alarm_description   = "Redis cluster CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]
  
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this[each.key].id
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch Freeable Memory metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "elasticache_memory" {
  for_each            = aws_elasticache_replication_group.this
  alarm_name          = "${var.app["brand"]}-elasticache-${each.key}-freeable-memory"
  alarm_description   = "Redis cluster freeable memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/ElastiCache"
  period              = "60"
  statistic           = "Average"
  threshold           = 10000000
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]
  
  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this[each.key].id
  }
}



//////////////////////////////////////////////////////////[ S3 BUCKET ]///////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket" "this" {
  for_each      = var.s3
  bucket        = "${var.app["brand"]}-${each.key}-storage"
  force_destroy = true
  acl           = "private"
  versioning {
        enabled = (each.value == "state" ? true : false)
   }
  tags = {
    Name        = "${var.app["brand"]}-${each.key}-storage"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create IAM user for S3 bucket
# # ---------------------------------------------------------------------------------------------------------------------#	  
resource "aws_iam_user" "s3" {
  name = "${var.app["brand"]}-s3-media-production"
  tags = {
    Name = "${var.app["brand"]}-s3-media-production"
  }
}
	  
resource "aws_iam_access_key" "s3" {
  user = aws_iam_user.s3.name
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create policy for S3 user to limit S3 media bucket access
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_s3_bucket_policy" "media" {
   bucket = aws_s3_bucket.this["media"].id
   policy = jsonencode({
   Id = "PolicyForMediaStorageAccess"
   Statement = [
      {
         Action = "s3:GetObject"
         Effect = "Deny"
         Principal = {
            AWS = "*"
         }
         Resource = [
            "${aws_s3_bucket.this["media"].arn}/*"
         ]
         Condition = {
            StringNotLike = {
		"aws:Referer" = [ var.app["domain"] ]
         }
       }
      }, 
      {
         Action = ["s3:PutObject"],
         Effect = "Allow"
         Principal = {
            AWS = [ aws_iam_user.s3.arn ]
         }
         Resource = [
            "${aws_s3_bucket.this["media"].arn}",
            "${aws_s3_bucket.this["media"].arn}/*"
         ]
         Condition = {
            StringEquals = {
                "aws:SourceVpc" = [ aws_vpc.this.id ]
         }
       }
      }, 
      {
         Action = ["s3:GetObject", "s3:GetObjectAcl"],
         Effect = "Allow"
         Principal = {
            AWS = [ aws_iam_user.s3.arn ]
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
            AWS = [ aws_iam_user.s3.arn ]
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
  Id = "PolicyALBWriteLogs"
  Version = "2012-10-17"
  Statement = [
    {
      Action = [
        "s3:PutObject"
      ],
      Effect = "Allow"
      Resource = "${aws_s3_bucket.this["system"].arn}/${var.app["brand"]}-alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      Principal = {
        AWS = [
          data.aws_elb_service_account.current.arn
        ]
      }
    },
    {
      Action = [
        "s3:PutObject",
        "s3:GetObject"
      ],
      Effect = "Allow"
      Resource = "${aws_s3_bucket.this["system"].arn}/${var.app["brand"]}-${data.aws_region.current.name}*"
      Principal = {
        AWS = [
          aws_iam_role.codebuild.arn,
          aws_iam_role.codepipeline.arn
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
  Id = "PolicyForBackupBucket"
  Version = "2012-10-17"
  Statement = [
    {
      Action = [
        "s3:PutObject"
      ],
      Effect = "Allow"
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



//////////////////////////////////////////////////////////[ ELASTICSEARCH ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ElasticSearch service linked role if not exists
# # ---------------------------------------------------------------------------------------------------------------------#
resource "null_resource" "es" {
  provisioner "local-exec" {
  interpreter = ["/bin/bash", "-c"]
  command = <<EOF
          exit_code=$(aws iam get-role --role-name AWSServiceRoleForAmazonElasticsearchService > /dev/null 2>&1 ; echo $?)
          if [[ $exit_code -ne 0 ]]; then
          aws iam create-service-linked-role --aws-service-name es.amazonaws.com
          fi
EOF
 }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create ElasticSearch domain
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_elasticsearch_domain" "this" {
  depends_on = [null_resource.es]
  domain_name           = "${var.app["brand"]}-${var.elk["domain_name"]}"
  elasticsearch_version = var.elk["elasticsearch_version"]
  cluster_config {
    instance_type  = var.elk["instance_type"]
    instance_count = var.elk["instance_count"]
    
    zone_awareness_enabled = true
    zone_awareness_config {
        availability_zone_count = var.elk["instance_count"]
      }
  }
  ebs_options {
    ebs_enabled = var.elk["ebs_enabled"]
    volume_type = var.elk["volume_type"]
    volume_size = var.elk["volume_size"]
  }
  vpc_options {
    subnet_ids = slice(values(aws_subnet.this).*.id, 0, var.elk["instance_count"])
    security_group_ids = [aws_security_group.elk.id]
  }
  tags = {
    Name = "${var.app["brand"]}-${var.elk["domain_name"]}"
  }
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.elk.arn
    log_type                 = var.elk["log_type"]
  }
  access_policies = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "*"
        ]
      },
      "Action": [
        "es:*"
      ],
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.app["brand"]}-${var.elk["domain_name"]}/*"
    }
  ]
}
EOF
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch log group for ElasticSearch log stream
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_log_group" "elk" {
  name = "${var.app["brand"]}-${var.elk["domain_name"]}"
}

resource "aws_cloudwatch_log_resource_policy" "elk" {
  policy_name = "${var.app["brand"]}-${var.elk["domain_name"]}"

  policy_document = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "es.amazonaws.com"
      },
      "Action": [
        "logs:PutLogEvents",
        "logs:PutLogEventsBatch",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:*"
    }
  ]
}
EOF
}



//////////////////////////////////////////////////////////////[ RDS ]/////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create RDS parameter groups
# # ---------------------------------------------------------------------------------------------------------------------#		
resource "aws_db_parameter_group" "this" {
  for_each          = toset(var.rds["name"])
  name              = "${var.app["brand"]}-${each.key}-parameters"
  family            = "mariadb10.5"
  description       = "Parameter group for ${var.app["brand"]} ${each.key} database"
  tags = {
    Name = "${var.app["brand"]}-${each.key}-parameters"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create RDS instance
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_db_instance" "this" {
  for_each               = toset(var.rds["name"])
  identifier             = "${var.app["brand"]}-${each.key}"
  allocated_storage      = var.rds["allocated_storage"]
  max_allocated_storage  = var.rds["max_allocated_storage"]
  storage_type           = var.rds["storage_type"] 
  engine                 = var.rds["engine"]
  engine_version         = var.rds["engine_version"]
  instance_class         = (each.key == "staging" ? var.rds["instance_class_staging"] : var.rds["instance_class"])
  multi_az               = (each.key == "staging" ? "false" : var.rds["multi_az"])
  name                   = "${var.app["brand"]}_${each.key}"
  username               = var.app["brand"]
  password               = random_password.this["rds"].result
  parameter_group_name   = aws_db_parameter_group.this[each.key].id
  skip_final_snapshot    = var.rds["skip_final_snapshot"]
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name
  enabled_cloudwatch_logs_exports = [var.rds["enabled_cloudwatch_logs_exports"]]
  performance_insights_enabled    = var.rds["performance_insights_enabled"]
  copy_tags_to_snapshot           = var.rds["copy_tags_to_snapshot"]
  backup_retention_period         = var.rds["backup_retention_period"]
  delete_automated_backups        = var.rds["delete_automated_backups"]
  deletion_protection             = var.rds["deletion_protection"]
  tags = {
    Name = "${var.app["brand"]}-${each.key}"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create RDS instance event subscription
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_db_event_subscription" "db_event_subscription" {
  name      = "${var.app["brand"]}-rds-event-subscription"
  sns_topic = aws_sns_topic.default.arn
  source_type = "db-instance"
  source_ids = [aws_db_instance.this["production"].id]
  event_categories = [
    "availability",
    "deletion",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "notification",
    "read replica",
    "recovery",
    "restoration",
    "configuration change"
  ]
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch CPU Utilization metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.app["brand"]} rds cpu utilization too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Average database CPU utilization over last 10 minutes too high"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this["production"].id
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch Freeable Memory metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "rds_memory" {
  alarm_name          = "${var.app["brand"]} rds freeable memory too low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Average"
  threshold           = "1.0e+09"
  alarm_description   = "Average database freeable memory over last 10 minutes too low, performance may suffer"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this["production"].id
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch Connections Anomaly metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "rds_connections_anomaly" {
  alarm_name          = "${var.app["brand"]} rds connections anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = "5"
  threshold_metric_id = "e1"
  alarm_description   = "Database connection count anomaly detected"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]
  
  insufficient_data_actions = []

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "DatabaseConnections (Expected)"
    return_data = "true"
  }

  metric_query {
    id          = "m1"
    return_data = "true"
    metric {
      metric_name = "DatabaseConnections"
      namespace   = "AWS/RDS"
      period      = "600"
      stat        = "Average"
      unit        = "Count"

      dimensions = {
        DBInstanceIdentifier = aws_db_instance.this["production"].id
      }
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch Max Connections metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "rds_max_connections" {
  alarm_name          = "${var.app["brand"]} rds connections over last 10 minutes is too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Average"
  threshold           = ceil((80 / 100) * var.max_connection_count[var.rds["instance_class"]])
  alarm_description   = "Average connections over last 10 minutes is too high"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this["production"].id
  }
}


/////////////////////////////////////////////////[ APPLICATION LOAD BALANCER ]////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Application Load Balancers
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb" "this" {
  name               = "${var.app["brand"]}-alb"
  internal           = false
  load_balancer_type = "application"
  drop_invalid_header_fields = true
  security_groups    = [aws_security_group.alb.id]
  subnets            = values(aws_subnet.this).*.id
  access_logs {
    bucket  = aws_s3_bucket.this["system"].bucket
    prefix  = "${var.app["brand"]}-alb"
    enabled = true
  }
  tags = {
    Name = "${var.app["brand"]}-alb"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Target Groups for Load Balancers
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb_target_group" "this" {
  for_each    = var.ec2
  name        = "${var.app["brand"]}-${each.key}-target"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  health_check {
    path = "/${random_string.this["health_check"].result}"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create default listener for Load Balancer - default response
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb_listener" "default" {
													   
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"
															
													 
  default_action {
    type             = "fixed-response"
    fixed_response {
        content_type = "text/plain"
        message_body = "No targets are responding to this request"
        status_code  = "502"
        }
    }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create conditional listener rule for Load Balancer - forward to frontend
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb_listener_rule" "frontend" {
  listener_arn = aws_lb_listener.default.arn
  priority     = 30
							
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["frontend"].arn
  }
  condition {
    host_header {
      values = [var.app["domain"]]
    }
  }
  condition {
    http_header {
      http_header_name = "X-Magenx-Header"
      values           = [random_uuid.this.result]
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create conditional listener rule for Load Balancer - forward to admin
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb_listener_rule" "admin" {
  listener_arn = aws_lb_listener.default.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["admin"].arn
  }
  condition {
    http_header {
      http_header_name = "X-Magenx-Header"
      values           = [random_uuid.this.result]
    }
  }
  condition {
    path_pattern {
      values = ["/admin_${random_string.this["admin_path"].result}/*"]
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create conditional listener rule for Load Balancer - forward to phpmyadmin
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb_listener_rule" "mysql" {
  listener_arn = aws_lb_listener.default.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["admin"].arn
  }
  condition {
    http_header {
      http_header_name = "X-Magenx-Header"
      values           = [random_uuid.this.result]
    }
  }
  condition {
    path_pattern {
      values = ["/mysql_${random_string.this["mysql_path"].result}/*"]
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create conditional listener rule for Load Balancer - forward to staging
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_lb_listener_rule" "staging" {
  listener_arn = aws_lb_listener.default.arn
  priority     = 40
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["staging"].arn
  }
  condition {
    host_header {
	values = [var.app["staging_domain"]]
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch HTTP 5XX metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "httpcode_target_5xx_count" {
  alarm_name          = "${var.app["brand"]}-http-5xx-errors-from-target"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = "25"
  alarm_description   = "HTTPCode 5XX count for frontend instances over 25"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]
  
  dimensions = {
    TargetGroup  = aws_lb_target_group.this["frontend"].arn
    LoadBalancer = aws_lb.this.arn
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch HTTP 5XX metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "httpcode_elb_5xx_count" {
  alarm_name          = "${var.app["brand"]}-http-5xx-errors-from-loadbalancer"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = "25"
  alarm_description   = "HTTPCode 5XX count for loadbalancer over 25"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]
  
  dimensions = {
    LoadBalancer = aws_lb.this.arn
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch RequestCount metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "alb_rps" {
  alarm_name          = "${var.app["brand"]}-loadbalancer-rps"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "120"
  statistic           = "Sum"
  threshold           = "5000"
  alarm_description   = "The number of requests processed over 2 minutes greater than 5000"
  alarm_actions       = ["${aws_sns_topic.default.arn}"]
  ok_actions          = ["${aws_sns_topic.default.arn}"]

  dimensions = {
    LoadBalancer = aws_lb.this.arn
  }
}



/////////////////////////////////////////////////////[ AUTOSCALING CONFIGURATION ]////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Launch Template for Autoscaling Groups - user_data converted
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_launch_template" "this" {
  for_each = var.ec2
  name = "${var.app["brand"]}-${each.key}-ltpl"
  iam_instance_profile { name = aws_iam_instance_profile.ec2[each.key].name }
  image_id = element(values(data.external.packer[each.key].result), 0)
  instance_type = each.value
  monitoring { enabled = false }
  network_interfaces { 
    associate_public_ip_address = true
    security_groups = [aws_security_group.ec2.id]
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.app["brand"]}-${each.key}-ec2" }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.app["brand"]}-${each.key}-ec2" }
  }
  user_data = base64encode(data.template_file.user_data[each.key].rendered)
  update_default_version = true
  lifecycle {
    create_before_destroy = true
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling Groups
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_autoscaling_group" "this" {
  for_each = var.ec2
  name = "${var.app["brand"]}-${each.key}-asg"
  vpc_zone_identifier = values(aws_subnet.this).*.id
  desired_capacity    = var.asg["desired_capacity"]
  min_size            = var.asg["min_size"]
  max_size            = var.asg["max_size"]
  health_check_grace_period = var.asg["health_check_grace_period"]
  health_check_type         = var.asg["health_check_type"]
  target_group_arns  = [aws_lb_target_group.this[each.key].arn]
  launch_template {
    name    = aws_launch_template.this[each.key].name
    version = "$Latest"
  }
  instance_refresh {
     strategy = "Rolling"
  }
  lifecycle {
    create_before_destroy = true
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling groups actions for SNS topic email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_autoscaling_notification" "this" {
for_each = aws_autoscaling_group.this 
group_names = [
    aws_autoscaling_group.this[each.key].name
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.default.arn
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling policy for scale-out
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_autoscaling_policy" "scaleout" {
  for_each               = var.ec2
  name                   = "${var.app["brand"]}-${each.key}-asp-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.this[each.key].name
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch alarm metric to execute Autoscaling policy for scale-out
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "scaleout" {
  for_each            = var.ec2
  alarm_name          = "${var.app["brand"]}-${each.key} scale-out alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.asp["evaluation_periods"]
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.asp["period"]
  statistic           = "Average"
  threshold           = var.asp["out_threshold"]
  dimensions = {
    AutoScalingGroupName  = aws_autoscaling_group.this[each.key].name
  }
  alarm_description = "${each.key} scale-out alarm - CPU exceeds ${var.asp["out_threshold"]} percent"
  alarm_actions     = [aws_autoscaling_policy.scaleout[each.key].arn]
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling policy for scale-in
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_autoscaling_policy" "scalein" {
  for_each               = var.ec2
  name                   = "${var.app["brand"]}-${each.key}-asp-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.this[each.key].name
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch alarm metric to execute Autoscaling policy for scale-in
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_metric_alarm" "scalein" {
  for_each            = var.ec2
  alarm_name          = "${var.app["brand"]}-${each.key} scale-in alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.asp["evaluation_periods"]
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.asp["period"]
  statistic           = "Average"
  threshold           = var.asp["in_threshold"]
  dimensions = {
    AutoScalingGroupName  = aws_autoscaling_group.this[each.key].name
  }
  alarm_description = "${each.key} scale-in alarm - CPU less than ${var.asp["in_threshold"]} percent"
  alarm_actions     = [aws_autoscaling_policy.scalein[each.key].arn]
}



////////////////////////////////////////////////////////[ EVENTBRIDGE RULES ]/////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create EventBridge service role
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role" "eventbridge_service_role" {
  name = "${var.app["brand"]}-EventBridgeServiceRole"
  description = "Provides EventBridge manage events on your behalf."
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "events.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create policy for EventBridge role to start CodePipeline
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_policy" "eventbridge_service_role" {
  name = "${var.app["brand"]}-${data.aws_region.current.name}-start-codepipeline"
  path = "/service-role/"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codepipeline:StartPipelineExecution"
            ],
            "Resource": [
                "${aws_codepipeline.this.arn}"
            ]
        }
    ]
}
EOF
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Attach policies to EventBridge role
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy_attachment" "eventbridge" {
  policy_arn = aws_iam_policy.eventbridge_service_role.arn
  role       = aws_iam_role.eventbridge_service_role.name
}
resource "aws_iam_role_policy_attachment" "eventbridge_service_role" {
  for_each   = var.eventbridge_policy
  role       = aws_iam_role.eventbridge_service_role.name
  policy_arn = each.value
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create EventBridge rule to run Magento cronjob
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_event_rule" "cronjob" {
  name        = "${var.app["brand"]}-EventBridge-Rule-Run-Magento-Cronjob"
  description = "EventBridge rule to run Magento cronjob every minute"
  schedule_expression = "rate(1 minute)"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create EventBridge target to execute SSM command
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudwatch_event_target" "cronjob" {
  rule      = aws_cloudwatch_event_rule.cronjob.name
  target_id = "${var.app["brand"]}-EventBridge-Target-Admin-Instance-Cron"
  arn       = "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript"
  role_arn  = aws_iam_role.eventbridge_service_role.arn
  input     = "{\"commands\":[\"su ${var.app["brand"]} -s /bin/bash -c '/home/${var.app["brand"]}/public_html/bin/magento cron:run 2>&1'\"],\"executionTimeout\":[\"180\"]}"
 
run_command_targets {
    key    = "tag:Name"
    values = [aws_launch_template.this["admin"].tag_specifications[0].tags.Name]
  }
}



////////////////////////////////////////////////////[ AMAZON SIMPLE EMAIL SERVICE ]///////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SES user credentials, Configuration Set to stream SES metrics to CloudWatch
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_user" "ses_smtp_user" {
  name = "${var.app["brand"]}-ses-smtp-user"
}
	
resource "aws_ses_email_identity" "ses_email_identity" {
  email = "${var.app["admin_email"]}"
}

resource "aws_iam_user_policy" "ses_smtp_user_policy" {
  name = "${var.app["brand"]}-ses-smtp-user-policy"
  user = aws_iam_user.ses_smtp_user.name
  
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource : "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "ses_smtp_user_access_key" {
  user = aws_iam_user.ses_smtp_user.name
}

resource "aws_ses_configuration_set" "this" {
  name = "${var.app["brand"]}-ses-events"
  reputation_metrics_enabled = true
  delivery_options {
    tls_policy = "Require"
  }
}

resource "aws_ses_event_destination" "cloudwatch" {
  name                   = "${var.app["brand"]}-ses-event-destination-cloudwatch"
  configuration_set_name = aws_ses_configuration_set.this.name
  enabled                = true
  matching_types         = ["bounce", "send", "complaint", "delivery"]

  cloudwatch_destination {
    default_value  = "default"
    dimension_name = "dimension"
    value_source   = "emailHeader"
  }
}



/////////////////////////////////////////////////////////[ SYSTEMS MANAGER ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameter store for aws params
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ssm_parameter" "env" {
  name        = "${var.app["brand"]}-${data.aws_region.current.name}-env"
  description = "Environment variables for ${var.app["brand"]} in ${data.aws_region.current.name}"
  type        = "String"
  value       = <<EOF

AWS_DEFAULT_REGION=${data.aws_region.current.name}
VPC_ID=${aws_vpc.this.id}
CIDR=${aws_vpc.this.cidr_block}
SUBNET_ID=${values(aws_subnet.this).0.id}
SECURITY_GROUP=${aws_security_group.ec2.id}

SOURCE_AMI=${data.aws_ami.distro.id}
VOLUME_SIZE=${var.app["volume_size"]}

RESOLVER=${cidrhost(aws_vpc.this.cidr_block, 2)}
								   											
ALB_DNS_NAME=${aws_lb.this.dns_name}
EFS_DNS_TARGET=${values(aws_efs_mount_target.this).0.dns_name}
SNS_TOPIC_ARN=${aws_sns_topic.default.arn}
CODECOMMIT_APP_REPO=codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.app.repository_name}
CODECOMMIT_SERVICES_REPO=codecommit::${data.aws_region.current.name}://${aws_codecommit_repository.services.repository_name}
RABBITMQ_ENDPOINT=${regex("amqps://(.*):5671",aws_mq_broker.this.instances.0.endpoints.0)}
RABBITMQ_USER=${var.app["brand"]}
RABBITMQ_PASSWORD=${random_password.this["rabbitmq"].result}
ELASTICSEARCH_ENDPOINT=https://${aws_elasticsearch_domain.this.endpoint}:443
REDIS_CACHE_BACKEND=${aws_elasticache_replication_group.this.primary_endpoint_address}

SES_KEY=${aws_iam_access_key.ses_smtp_user_access_key.id}
SES_SECRET=${aws_iam_access_key.ses_smtp_user_access_key.secret}
SES_PASSWORD=${aws_iam_access_key.ses_smtp_user_access_key.ses_smtp_password_v4}

DATABASE_ENDPOINT=${aws_db_instance.this.endpoint}
DATABASE_INSTANCE_NAME=${aws_db_instance.this.name}
DATABASE_USER_NAME=${aws_db_instance.this.username}
DATABASE_PASSWORD=${random_password.this["rds"].result}

ADMIN_PATH=admin_${random_string.this["admin_path"].result}
ADMIN_PASSWORD=${random_password.this["app"].result}

VERSION=2
DOMAIN=${var.app["domain"]}
STAGING_DOMAIN=${var.app["staging_domain"]}

BRAND=${var.app["brand"]}
PHP_USER=php-${var.app["brand"]}

ADMIN_EMAIL=${var.app["admin_email"]}
WEB_ROOT_PATH="/home/${var.app["brand"]}/public_html"
TIMEZONE=${var.app["timezone"]}
MAGENX_HEADER=${random_uuid.this.result}
HEALTH_CHECK_LOCATION=${random_string.this["health_check"].result}
MYSQL_PATH=mysql_${random_string.this["mysql_path"].result}
PROFILER=${random_string.this["profiler"].result}
BLOWFISH=${random_password.this["blowfish"].result}
RESOLVER=${cidrhost(aws_vpc.this.cidr_block, 2)}

PHP_VERSION=${var.app["php_version"]}
PHP_INI="/etc/php/${var.app["php_version"]}/fpm/php.ini"
PHP_FPM_POOL="/etc/php/${var.app["php_version"]}/fpm/pool.d/www.conf"
PHP_OPCACHE_INI="/etc/php/${var.app["php_version"]}/fpm/conf.d/10-opcache.ini"
HTTP_X_HEADER=${random_uuid.this.result}

EXTRA_PACKAGES_DEB="nfs-common unzip git patch python3-pip acl attr imagemagick snmp"
PHP_PACKAGES_DEB="cli fpm json common mysql zip gd mbstring curl xml bcmath intl soap oauth lz4 apcu"
EXCLUDE_PACKAGES_DEB="apache2* *apcu-bc"

EOF

  tags = {
    Name = "${var.app["brand"]}-${data.aws_region.current.name}-env"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameter configuration file for CloudWatch Agent
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  for_each    = var.ec2
  name        = "amazon-cloudwatch-agent-${each.key}.json"
  description = "Configuration file for CloudWatch agent at ${each.key}"
  type        = "String"
  value       = <<EOF
{
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
            {
                "file_path": "/var/log/nginx/error.log",
                "log_group_name": "${var.app["brand"]}_nginx_error_logs",
                "log_stream_name": "${each.key}-{instance_id}-{ip_address}"
            },
            %{ if each.key == "admin" || each.key == "staging" ~}
            {
                "file_path": "/home/${var.app["brand"]}/public_html/var/log/php-fpm-error.log",
                "log_group_name": "${var.app["brand"]}_php_app_error_logs",
                "log_stream_name": "${each.key}-{instance_id}-{ip_address}"
            },
            {
                "file_path": "/home/${var.app["brand"]}/public_html/var/log/exception.log",
                "log_group_name": "${var.app["brand"]}_app_error_logs",
                "log_stream_name": "${each.key}-{instance_id}-{ip_address}"
            },
            %{ endif ~}
            {
                "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
                "log_group_name": "${var.app["brand"]}_cloudwatch_agent_log",
                "log_stream_name": "${each.key}-{instance_id}-{ip_address}"
            },
            {
                "file_path": "/var/log/apt/history.log",
                "log_group_name": "${var.app["brand"]}_system_apt_history",
                "log_stream_name": "${each.key}-{instance_id}-{ip_address}"
            },
            {
                "file_path": "/var/log/syslog",
                "log_group_name": "${var.app["brand"]}_system_syslog",
                "log_stream_name": "${each.key}-{instance_id}-{ip_address}"
            }
            ]
          }
        },
        "log_stream_name": "${var.app["domain"]}",
        "force_flush_interval" : 60
      }
}
EOF

  tags = {
    Name = "amazon-cloudwatch-agent-${each.key}.json"
  }
}



///////////////////////////////////////////////////////[ AWS WAFv2 RULES ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create a WAFv2 Web ACL Association with Load Balancer
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create AWS WAFv2 rules
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_wafv2_web_acl" "this" {
  name        = "${var.app["brand"]}-WAF-Protections"
  scope       = "REGIONAL"
  description = "${var.app["brand"]}-WAF-Protections"

  default_action {
    allow {
    }
  }
	
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name = "${var.app["brand"]}-WAF-Protections"
    sampled_requests_enabled = true
  }

  rule {
    name = "AWSManagedRulesCommonRule"
    priority = 2
    override_action {
      none {
      }
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "${var.app["brand"]}-AWSManagedRulesCommonRule"
      sampled_requests_enabled = true
    }
  }
  rule {
    name = "AWSManagedRulesAmazonIpReputation"
    priority = 3
    override_action {
      none {
      }
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "${var.app["brand"]}-AWSManagedRulesAmazonIpReputation"
      sampled_requests_enabled = true
    }
  }
  rule {
    name = "AWSManagedRulesBotControlRule"
    priority = 4
    override_action {
      none {
      }
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "${var.app["brand"]}-AWSManagedRulesBotControlRule"
      sampled_requests_enabled = true
    }
  }
}
