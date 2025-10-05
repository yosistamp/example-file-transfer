# -----------------------------------------------------------------------------
# AWS Provider Configuration
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# S3 Bucket for File Storage
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "file_storage" {
  bucket = "${var.project_name}-storage"

  tags = {
    Name = "${var.project_name}-storage"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "file_storage_encryption" {
  bucket = aws_s3_bucket.file_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "file_storage_versioning" {
  bucket = aws_s3_bucket.file_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "file_storage_public_access" {
  bucket = aws_s3_bucket.file_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudwatch_metric_alarm" "s3_monitoring" {
  alarm_name          = "${var.project_name}-s3-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "5xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Monitors S3 bucket for 5xx errors."
  dimensions = {
    BucketName = aws_s3_bucket.file_storage.bucket
    FilterId   = "EntireBucket"
  }
}

# -----------------------------------------------------------------------------
# DynamoDB Table for Metadata
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "metadata" {
  name             = "${var.project_name}-metadata"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "FilePath"

  attribute {
    name = "FilePath"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Name = "${var.project_name}-metadata"
  }
}

# -----------------------------------------------------------------------------
# ECR Repositories for Lambda Functions
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "upload_app_repo" {
  name                 = "${var.project_name}/upload-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "process_app_repo" {
  name                 = "${var.project_name}/process-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# -----------------------------------------------------------------------------
# Cognito User Pool for Authentication
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.project_name}-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret       = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.project_name}-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# -----------------------------------------------------------------------------
# IAM Roles and Policies
# -----------------------------------------------------------------------------

# IAM Role for EventBridge Pipe
resource "aws_iam_role" "pipe_role" {
  name = "${var.project_name}-pipe-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "pipes.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for the Pipe Role
resource "aws_iam_policy" "pipe_policy" {
  name   = "${var.project_name}-pipe-policy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ],
        Resource = aws_dynamodb_table.metadata.stream_arn
      },
      {
        Effect   = "Allow",
        Action   = "states:StartExecution",
        Resource = aws_sfn_state_machine.downstream_workflow.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pipe_policy_attachment" {
  role       = aws_iam_role.pipe_role.name
  policy_arn = aws_iam_policy.pipe_policy.arn
}

# -----------------------------------------------------------------------------
# Step Functions State Machine
# -----------------------------------------------------------------------------

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# IAM Role for Step Functions
resource "aws_iam_role" "sfn_role" {
  name = "${var.project_name}-sfn-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "sfn_policy" {
  name = "${var.project_name}-sfn-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "lambda:InvokeFunction",
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_policy_attachment" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_policy.arn
}

resource "aws_sfn_state_machine" "downstream_workflow" {
  name     = "${var.project_name}-downstream-workflow"
  role_arn = aws_iam_role.sfn_role.arn

  definition = jsonencode({
    Comment = "A simple workflow to process file uploads. The FunctionName will be updated by the CD pipeline.",
    StartAt = "ProcessEvent",
    States = {
      ProcessEvent = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          "FunctionName" = "PLEASE_UPDATE_VIA_CD_PIPELINE", # This ARN is dynamically updated by the CD workflow.
          "Payload.$"    = "$"
        },
        End = true
      }
    }
  })

  tags = {
    Name = "${var.project_name}-downstream-workflow"
  }
}

# -----------------------------------------------------------------------------
# EventBridge Pipe
# -----------------------------------------------------------------------------
resource "aws_pipes_pipe" "dynamodb_to_sfn" {
  name     = "${var.project_name}-dynamo-to-sfn-pipe"
  role_arn = aws_iam_role.pipe_role.arn

  source = aws_dynamodb_table.metadata.stream_arn

  source_parameters {
    dynamodb_stream_parameters {
      starting_position = "LATEST"
      batch_size        = 1
    }
  }

  target = aws_sfn_state_machine.downstream_workflow.arn
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "cognito_app_client_id" {
  description = "The ID of the Cognito App Client."
  value       = aws_cognito_user_pool_client.app_client.id
}

output "sfn_state_machine_arn" {
  description = "The ARN of the Step Functions state machine."
  value       = aws_sfn_state_machine.downstream_workflow.arn
}

# -----------------------------------------------------------------------------
# Consolidated Outputs for CD Pipeline and Documentation
# -----------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "The name of the S3 bucket for file storage."
  value       = aws_s3_bucket.file_storage.bucket
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table for metadata."
  value       = aws_dynamodb_table.metadata.name
}

output "upload_app_ecr_repo_url" {
  description = "The URL of the ECR repository for the upload application."
  value       = aws_ecr_repository.upload_app_repo.repository_url
}

output "process_app_ecr_repo_url" {
  description = "The URL of the ECR repository for the process application."
  value       = aws_ecr_repository.process_app_repo.repository_url
}