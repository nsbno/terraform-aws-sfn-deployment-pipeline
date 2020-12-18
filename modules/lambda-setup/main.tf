data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  current_account_id = data.aws_caller_identity.current.account_id
  current_region     = data.aws_region.current.name
  state_machine_arns = ["arn:aws:states:${local.current_region}:${local.current_account_id}:stateMachine:${var.name_prefix}-*"]
}

module "set_version" {
  source      = "github.com/nsbno/terraform-aws-pipeline-set-version?ref=ee68497"
  name_prefix = var.name_prefix
}

resource "aws_iam_role_policy" "role_assume_to_set_version" {
  role   = module.set_version.lambda_exec_role_id
  policy = data.aws_iam_policy_document.role_assume_for_set_version.json
}

module "single_use_fargate_task" {
  source      = "github.com/nsbno/terraform-aws-single-use-fargate-task?ref=78e9578"
  name_prefix = var.name_prefix
  tags        = var.tags
}

resource "aws_iam_role_policy" "pass_role_to_single_use_fargate_task" {
  policy = data.aws_iam_policy_document.pass_role_for_single_use_fargate_task.json
  role   = module.single_use_fargate_task.lambda_exec_role_id
}


# Default task role
resource "aws_iam_role" "fargate_task" {
  name               = "${var.name_prefix}-single-use-tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags = merge(var.tags, {
    deployment-pipeline = true
  })
}

resource "aws_iam_role_policy" "s3_to_fargate_task" {
  policy = data.aws_iam_policy_document.s3_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role_policy" "task_status_to_fargate_task" {
  policy = data.aws_iam_policy_document.task_status_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

resource "aws_iam_role_policy" "logs_to_fargate_task" {
  policy = data.aws_iam_policy_document.logs_for_fargate_task.json
  role   = aws_iam_role.fargate_task.id
}

module "roles" {
  source           = "../deployment-roles"
  name_prefix      = var.name_prefix
  trusted_accounts = [local.current_account_id]
  tags             = var.tags
}


##################################
#                                #
# Pipeline error catcher         #
#                                #
##################################
module "error_catcher" {
  source             = "github.com/nsbno/terraform-aws-pipeline-error-catcher?ref=3f74981"
  state_machine_arns = local.state_machine_arns
  name_prefix        = var.name_prefix
}
