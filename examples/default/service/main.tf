terraform {
  required_version = "0.12.29"
  backend "s3" {
    key            = "<name-prefix>/main.tfstate"           # TODO
    bucket         = "<service-account-id>-terraform-state" # TODO
    dynamodb_table = "<service-account-id>-terraform-lock"  # TODO
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
  test_account_id    = "<test-account-id>"    # TODO
  stage_account_id   = "<stage-account-id>"   # TODO
  prod_account_id    = "<prod-account-id>"    # TODO
  trusted_accounts = [
    local.service_account_id,
    local.test_account_id,
    local.stage_account_id,
    local.prod_account_id
  ]
  vpc_cidr_block = "192.168.50.0/24"
  public_cidr_blocks = [for k, v in data.aws_availability_zones.this.names :
  cidrsubnet(local.vpc_cidr_block, 4, k)]
}


#########################################
#                                       #
# Artifact Bucket                       #
# ---                                   #
# Bucket for storing artifacts          #
#                                       #
#########################################
resource "aws_s3_bucket" "artifact" {
  bucket = "${local.current_account_id}-${local.name_prefix}-pipeline-artifact"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = local.tags
}


#########################################
#                                       #
# VPC                                   #
# ---                                   #
# Mainly used for ad-hoc Fargate tasks  #
#                                       #
#########################################
module "vpc" {
  source               = "github.com/nsbno/terraform-aws-vpc?ref=ec7f57f"
  name_prefix          = local.name_prefix
  cidr_block           = local.vpc_cidr_block
  availability_zones   = data.aws_availability_zones.this.names
  public_subnet_cidrs  = local.public_cidr_blocks
  create_nat_gateways  = false
  enable_dns_hostnames = true
  tags                 = local.tags
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
  trusted_accounts = [local.current_account_id]
  tags             = local.tags
}


##########################################
#                                        #
# Setup for Pipeline-Account             #
# ---                                    #
# set-version, single-use-fargate-task & #
# pre-configured task role for Fargate   #
#                                        #
##########################################
module "pipeline-lambdas" {
  source                       = "../../../modules/pipeline-account-setup"
  name_prefix                  = local.name_prefix
  bucket_arns_for_fargate_task = [aws_s3_bucket.project_bucket.arn]
  role_arns_for_fargate_task   = formatlist("arn:aws:iam::%s:role/${module.pipeline-roles.deployment_role_name}", local.trusted_accounts)
  role_arns_for_set_version    = formatlist("arn:aws:iam::%s:role/${module.pipeline-roles.set_version_role_name}", local.trusted_accounts)
  tags                         = local.tags
}

#################################################
#                                               #
# AWS Step Functions Deployment Pipelines       #
#                                               #
#################################################
module "sfn" {
  source      = "../../../terraform-aws-sfn-deployment-pipeline"
  name_prefix = local.name_prefix
  # Configuration for the deployment states
  deployment_configuration = {
    image           = "vydev/terraform:0.12.29"
    deployment_role = module.pipeline-roles.deployment_role_name
    task_role       = module.pipeline-lambdas.single_use_fargate_task.task_role_name
    # The accounts to set up deployment states for
    accounts = {
      service = {
        id = local.service_account_id
      }
      test = {
        id = local.test_account_id
      }
      stage = {
        id = local.stage_account_id
      }
      prod = {
        id = local.prod_account_id
      }
    }
  }
  # Configuration for the various Lambdas used in the pipeline
  pipeline_lambda_configuration = {
    error_catcher = {
      function_name = module.pipeline-lambdas.error_catcher.function_name
    }
    set_version = {
      function_name = module.pipeline-lambdas.set_version.function_name
      role          = module.pipeline-roles.set_version_role_name
      ssm_prefix    = module.pipeline-roles.set_version_ssm_prefix
      /*
      # Add names and locations of application artifacts here:
      lambda_s3_bucket = aws_s3_bucket.artifact.id
      lambda_s3_prefix = "lambdas"
      frontend_s3_bucket = aws_s3_bucket.artifact.id
      frontend_s3_prefix = "frontends"
      applications = {
        ecr = ["${local.name_prefix}-docker-app"]
        frontend = ["${local.name_prefix}-frontend-app"]
        lambda = ["${local.name_prefix}-lambda-app"]
      }
      */
    }
    single_use_fargate_task = {
      function_name  = module.pipeline-lambdas.single_use_fargate_task.function_name
      ecs_cluster    = module.pipeline-lambdas.single_use_fargate_task.ecs_cluster_arn
      execution_role = module.pipeline-lambdas.single_use_fargate_task.task_execution_role_arn
      subnets        = module.vpc.public_subnet_ids
    }
  }
}
