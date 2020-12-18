data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  current_account_id = data.aws_caller_identity.current.account_id
  current_region     = data.aws_region.current.name
}


###################################################
#                                                 #
# Roles that can be assumed from trusted accounts #
# (typically a `service` account)                 #
#                                                 #
###################################################
resource "aws_iam_role" "deployment" {
  description        = "A role that can be assumed by a Fargate task during a deployment"
  name               = "${var.name_prefix}-trusted-deployment"
  assume_role_policy = data.aws_iam_policy_document.trusted_account_deployment_assume.json
  tags = merge(var.tags, {
    deployment-pipeline = true
  })
}

resource "aws_iam_role_policy_attachment" "admin_to_deployment" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.deployment.id
}

resource "aws_iam_role" "set_version" {
  description        = "A role that can be assumed by trusted accounts during a deployment in order to update SSM parameters."
  name               = "${var.name_prefix}-trusted-set-version"
  assume_role_policy = data.aws_iam_policy_document.trusted_account_assume.json
  tags = merge(var.tags, {
    deployment-pipeline = true
  })
}

resource "aws_iam_role_policy" "ssm_to_set_version" {
  policy = data.aws_iam_policy_document.ssm_for_set_version.json
  role   = aws_iam_role.set_version.id
}
