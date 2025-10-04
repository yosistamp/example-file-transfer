variable "project_name" {
  description = "The name of the project."
  type        = string
  default     = "s3-dynamo-pipe-app"
}

variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "ap-northeast-1"
}