data "aws_iam_policy_document" "trusted_account_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = formatlist("arn:aws:iam::%s:root", var.trusted_accounts)
    }
  }
}

data "aws_iam_policy_document" "ssm_for_set_version" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:aws:ssm:${local.current_region}:${local.current_account_id}:parameter/${var.name_prefix}/versions/*"]
  }
}

data "aws_iam_policy_document" "trusted_account_deployment_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = formatlist("arn:aws:iam::%s:root", var.trusted_accounts)
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = formatlist("arn:aws:iam::%s:role/${var.name_prefix}-single-use-tasks", var.trusted_accounts)
    }
  }
}

