variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "role_arns_for_set_version" {
  description = "A list of ARNs of roles that the set-version Lambda can assume (e.g., cross-account roles with write access to AWS Parameter Store)."
  default     = []
  type        = list(string)
}

variable "bucket_arns_for_fargate_task" {
  description = "A list of S3 bucket ARNs that single-use Fargate tasks can read from (e.g., artifact buckets)."
  default     = []
  type        = list(string)
}

variable "role_arns_for_fargate_task" {
  description = "A list of ARNs of roles that single-use Fargate tasks can assume (e.g., cross-account deployment roles)."
  default     = []
  type        = list(string)
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}
