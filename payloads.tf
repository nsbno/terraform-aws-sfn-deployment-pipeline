##################################
#                                #
# Convenience variables          #
#                                #
##################################
locals {
  state_machine_name               = "${var.name_prefix}-state-machine"
  default_deploy_state_timeout     = 3600
  default_additional_state_timeout = 3600
  accounts = {
    for name in setintersection(["dev", "test", "stage", "prod", "service"], keys(var.deployment_configuration.accounts)) :
    name => var.deployment_configuration.accounts[name]
  }
  parallel_deployment_accounts = (
    length(setsubtract(keys(local.accounts), ["prod"])) > 1
    ? { for name, account in local.accounts : name => account if contains(["dev", "test", "stage", "service"], name) }
    : {}
  )
}


##################################
#                                #
# Payload for set-version        #
#                                #
##################################
locals {
  input_to_get_latest_artifact_versions = merge(
    {
      get_versions       = true
      set_versions       = false
      lambda_s3_bucket   = lookup(var.pipeline_lambda_configuration.set_version, "lambda_s3_bucket", "")
      lambda_s3_prefix   = lookup(var.pipeline_lambda_configuration.set_version, "lambda_s3_prefix", "")
      frontend_s3_bucket = lookup(var.pipeline_lambda_configuration.set_version, "frontend_s3_bucket", "")
      frontend_s3_prefix = lookup(var.pipeline_lambda_configuration.set_version, "frontend_s3_prefix", "")
      ssm_prefix         = var.pipeline_lambda_configuration.set_version.ssm_prefix
      role_to_assume     = var.pipeline_lambda_configuration.set_version.role
    },
    [
      for key in ["ecr", "frontend", "lambda"] :
      {
        "${key}_applications" = [
          for app in lookup(lookup(var.pipeline_lambda_configuration.set_version, "applications", {}), key, []) : try({
            name        = app.name
            tag_filters = lookup(app, "tag_filters", ["${lookup(var.pipeline_lambda_configuration.set_version, "default_branch", "master")}-branch"])
            }, {
            name        = app
            tag_filters = ["${lookup(var.pipeline_lambda_configuration.set_version, "default_branch", "master")}-branch"]
          })
        ]
      }
  ]...)
  input_to_set_version = {
    for name, account in local.accounts : name => merge(
      local.input_to_get_latest_artifact_versions,
      {
        account_id   = account.id
        get_versions = false
        set_versions = ! lookup(account, "dry_run", false)
        "versions.$" = "$.versions"
      }
    )
  }
}


##############################################
#                                            #
# Payload for single-use-fargate-task        #
#                                            #
##############################################
locals {
  assume_role_cmd          = "temp_role=$(aws sts assume-role --role-arn %s --role-session-name deployment-from-service-account) && aws configure set profile.deployment.aws_access_key_id \"$(echo $temp_role | jq -r .Credentials.AccessKeyId)\" && aws configure set profile.deployment.aws_secret_access_key \"$(echo $temp_role | jq -r .Credentials.SecretAccessKey)\" && aws configure set profile.deployment.aws_session_token \"$(echo $temp_role | jq -r .Credentials.SessionToken)\" && export AWS_PROFILE=deployment"
  terraform_deployment_cmd = "cd %s && terraform init -lock-timeout=120s -no-color && %s -lock-timeout=120s -no-color"
  common_input_to_fargate_states = {
    task_execution_role_arn = var.pipeline_lambda_configuration.single_use_fargate_task.execution_role
    credentials_secret_arn  = lookup(var.pipeline_lambda_configuration.single_use_fargate_task, "dockerhub_credentials", "")
    ecs_cluster             = var.pipeline_lambda_configuration.single_use_fargate_task.ecs_cluster
    subnets                 = var.pipeline_lambda_configuration.single_use_fargate_task.subnets
    state_machine_id        = local.state_machine_name
    "token.$"               = "$$.Task.Token",
    "state.$"               = "$$.State.Name"
  }
  common_input_to_deploy_states = merge(
    local.common_input_to_fargate_states,
    {
      image         = var.deployment_configuration.image
      task_role_arn = var.deployment_configuration.task_role
      "content.$"   = "$.deployment_package"
    }
  )
  # Set up shell commands for the deployment states
  input_to_deploy_states = {
    for name, account in local.accounts : name => merge(
      local.common_input_to_deploy_states,
      {
        cmd_to_run = "${format(local.assume_role_cmd, "arn:aws:iam::${account.id}:role/${var.deployment_configuration.deployment_role}")} && ${format(local.terraform_deployment_cmd, lookup(account, "path", "terraform/${name}"), lookup(account, "dry_run", false) ? "terraform plan" : "terraform apply -auto-approve")}"
      }
    )
  }
}
