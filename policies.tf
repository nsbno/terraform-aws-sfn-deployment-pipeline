data "aws_iam_policy_document" "sfn_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["states.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "lambda_for_sfn" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:${var.pipeline_lambda_configuration.error_catcher.function_name}",
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:${var.pipeline_lambda_configuration.set_version.function_name}",
      "arn:aws:lambda:${local.current_region}:${local.current_account_id}:function:${var.pipeline_lambda_configuration.single_use_fargate_task.function_name}"
    ]
  }
}
