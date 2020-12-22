variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "ssm_prefix_for_set_version" {
  description = "The SSM prefix the role used by the set-version Lambda is allowed to write SSM parameters to (defaults to `<name-prefix>/versions`)."
  type        = string
  default     = ""
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
