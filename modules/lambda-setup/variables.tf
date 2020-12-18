variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "artifact_bucket_arns" {
  description = "A list of S3 bucket ARNs that the Fargate task can read from."
  default     = []
  type        = list(string)
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}
