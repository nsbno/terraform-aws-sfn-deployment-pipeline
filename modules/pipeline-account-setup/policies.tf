data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "fargate_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.fargate_task.arn]
    }
  }
}

data "aws_iam_policy_document" "role_assume_for_set_version" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = var.role_arns_for_set_version
  }
}

data "aws_iam_policy_document" "pass_role_for_single_use_fargate_task" {
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [aws_iam_role.fargate_task.arn]
  }
}

data "aws_iam_policy_document" "role_assume_for_fargate_task" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = var.role_arns_for_fargate_task
  }
}

data "aws_iam_policy_document" "s3_for_fargate_task" {
  statement {
    effect  = "Allow"
    actions = ["s3:Get*", "s3:List*"]
    resources = flatten([for arn in var.bucket_arns_for_fargate_task : [
      arn, "${arn}/*"
    ]])
  }
}

data "aws_iam_policy_document" "logs_for_fargate_task" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${local.current_region}:${local.current_account_id}:*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${local.current_region}:${local.current_account_id}:log-group:/aws/ecs/*"
    ]
  }
}

data "aws_iam_policy_document" "task_status_for_fargate_task" {
  statement {
    effect = "Allow"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure"
    ]
    resources = local.state_machine_arns
  }
}
