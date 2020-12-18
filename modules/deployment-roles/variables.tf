variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "trusted_accounts" {
  description = "IDs of other accounts that are trusted to assume the roles."
  type        = list(string)
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}
