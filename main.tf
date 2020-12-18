data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  current_account_id    = data.aws_caller_identity.current.account_id
  current_region        = data.aws_region.current.name
  default_state_timeout = 3600
}

resource "aws_sfn_state_machine" "this" {
  name       = local.state_machine_name
  definition = jsonencode(local.state_machine_definition)
  role_arn   = aws_iam_role.this.arn
  tags       = var.tags
}

resource "aws_iam_role" "this" {
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "lambda_to_sfn" {
  policy = data.aws_iam_policy_document.lambda_for_sfn.json
  role   = aws_iam_role.this.id
}
