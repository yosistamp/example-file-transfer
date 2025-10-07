resource "aws_iam_role" "upload_app_role" {
  name = "${var.project_name}-upload-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "upload_app_policy" {
  name        = "${var.project_name}-upload-app-policy"
  description = "Policy for Lambda to access ECR, S3, DynamoDB"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # ECR access for Lambda container image
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ],
        Resource = "*"
      },
      # S3 access
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.file_storage.arn,
          "${aws_s3_bucket.file_storage.arn}/*"
        ]
      },
      # DynamoDB access
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Resource = aws_dynamodb_table.metadata.arn
      },
      # CloudWatch Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "upload_app_policy_attachment" {
  role       = aws_iam_role.upload_app_role.name
  policy_arn = aws_iam_policy.upload_app_policy.arn
}

resource "aws_iam_role" "process_event_role" {
  name = "${var.project_name}-process-event-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "process_event_policy" {
  name        = "${var.project_name}-process-event-policy"
  description = "Policy for Lambda to access ECR, S3, DynamoDB"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # ECR access for Lambda container image
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ],
        Resource = "*"
      },
      # CloudWatch Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "process_event_policy_attachment" {
  role       = aws_iam_role.process_event_role.name
  policy_arn = aws_iam_policy.process_event_policy.arn
}
