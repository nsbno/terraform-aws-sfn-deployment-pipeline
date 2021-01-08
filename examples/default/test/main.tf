terraform {
  required_version = "0.12.29"
  backend "s3" {
    key            = "<name-prefix>/main.tfstate"        # TODO
    bucket         = "<test-account-id>-terraform-state" # TODO
    dynamodb_table = "<test-account-id>-terraform-lock"  # TODO
    region         = "eu-west-1"
  }
}

data "aws_caller_identity" "this" {}
data "aws_availability_zones" "this" {}

locals {
  name_prefix = "<name-prefix>" # TODO
  tags = {
    project   = local.name_prefix
    terraform = true
  }
  current_account_id = data.aws_caller_identity.this.account_id
  service_account_id = "<service-account-id>" # TODO
}


#########################################
#                                       #
# Common Pipeline Setup                 #
# ---                                   #
# Roles that are used during deployment #
#                                       #
#########################################
module "pipeline-roles" {
  source           = "../../../modules/common-account-setup"
  name_prefix      = local.name_prefix
  trusted_accounts = [local.service_account_id]
  tags             = local.tags
}
