##################################
#                                #
# Payload for set-version        #
#                                #
##################################
locals {
  input_to_get_latest_artifact_versions = merge({
    get_versions       = true
    set_versions       = false
    lambda_s3_bucket   = lookup(var.pipeline_lambda_configuration.set_version, "lambda_s3_bucket", "")
    lambda_s3_prefix   = lookup(var.pipeline_lambda_configuration.set_version, "lambda_s3_prefix", "")
    frontend_s3_bucket = lookup(var.pipeline_lambda_configuration.set_version, "frontend_s3_bucket", "")
    frontend_s3_prefix = lookup(var.pipeline_lambda_configuration.set_version, "frontend_s3_prefix", "")
    ssm_prefix         = var.pipeline_lambda_configuration.set_version.ssm_prefix
    role_to_assume     = var.pipeline_lambda_configuration.set_version.role
    }, [for key in ["ecr", "frontend", "lambda"] : {
      "${key}_applications" = [
        for app in lookup(var.pipeline_lambda_configuration.set_version.applications, key, []) : try({
          name        = app.name
          tag_filters = lookup(app, "tag_filters", ["${lookup(var.pipeline_lambda_configuration.set_version, "default_branch", "master")}-branch"])
          }, {
          name        = app
          tag_filters = ["${lookup(var.pipeline_lambda_configuration.set_version, "default_branch", "master")}-branch"]
        })
      ]
  }]...)
  # test account is optional
  input_to_bump_versions_in_test = contains(keys(var.deployment_configuration.accounts), "test") ? merge(local.input_to_get_latest_artifact_versions, {
    account_id   = var.deployment_configuration.accounts.test.id
    get_versions = false
    set_versions = ! lookup(var.deployment_configuration.accounts.test, "dry_run", false)
    "versions.$" = "$.versions"
  }) : null
  input_to_bump_versions_in_stage = merge(local.input_to_get_latest_artifact_versions, {
    account_id   = var.deployment_configuration.accounts.stage.id
    get_versions = false
    set_versions = ! lookup(var.deployment_configuration.accounts.stage, "dry_run", false)
    "versions.$" = "$.versions"
  })
  input_to_bump_versions_in_prod = merge(local.input_to_get_latest_artifact_versions, {
    account_id   = var.deployment_configuration.accounts.prod.id
    get_versions = false
    set_versions = ! lookup(var.deployment_configuration.accounts.prod, "dry_run", false)
    "versions.$" = "$.versions"
  })
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
    credentials_secret_arn  = var.pipeline_lambda_configuration.single_use_fargate_task.dockerhub_credentials
    ecs_cluster             = var.pipeline_lambda_configuration.single_use_fargate_task.ecs_cluster
    subnets                 = var.pipeline_lambda_configuration.single_use_fargate_task.subnets
    state_machine_id        = local.state_machine_name
    "token.$"               = "$$.Task.Token",
    "state.$"               = "$$.State.Name"
  }
  common_input_to_deploy_states = merge(local.common_input_to_fargate_states, {
    image         = var.deployment_configuration.image
    task_role_arn = var.deployment_configuration.task_role
    "content.$"   = "$.deployment_package"
  })
  # Set up shell commands for the deployment states
  # service is optional account
  input_to_deploy_service = contains(keys(var.deployment_configuration.accounts), "service") ? merge(local.common_input_to_deploy_states, {
    cmd_to_run = "${format(local.assume_role_cmd, "arn:aws:iam::${var.deployment_configuration.accounts.service.id}:role/${var.deployment_configuration.deployment_role}")} && ${format(local.terraform_deployment_cmd, lookup(var.deployment_configuration.accounts.service, "path", "terraform/service"), lookup(var.deployment_configuration.accounts.service, "dry_run", false) ? "terraform plan" : "terraform apply -auto-approve")}"
  }) : null
  # test is optional account
  input_to_deploy_test = contains(keys(var.deployment_configuration.accounts), "test") ? merge(local.common_input_to_deploy_states, {
    cmd_to_run = "${format(local.assume_role_cmd, "arn:aws:iam::${var.deployment_configuration.accounts.test.id}:role/${var.deployment_configuration.deployment_role}")} && ${format(local.terraform_deployment_cmd, lookup(var.deployment_configuration.accounts.test, "path", "terraform/test"), lookup(var.deployment_configuration.accounts.test, "dry_run", false) ? "terraform plan" : "terraform apply -auto-approve")}"
  }) : null

  input_to_deploy_stage = merge(local.common_input_to_deploy_states, {
    cmd_to_run = "${format(local.assume_role_cmd, "arn:aws:iam::${var.deployment_configuration.accounts.stage.id}:role/${var.deployment_configuration.deployment_role}")} && ${format(local.terraform_deployment_cmd, lookup(var.deployment_configuration.accounts.stage, "path", "terraform/stage"), lookup(var.deployment_configuration.accounts.stage, "dry_run", false) ? "terraform plan" : "terraform apply -auto-approve")}"
  })

  input_to_deploy_prod = merge(local.common_input_to_deploy_states, {
    cmd_to_run = "${format(local.assume_role_cmd, "arn:aws:iam::${var.deployment_configuration.accounts.prod.id}:role/${var.deployment_configuration.deployment_role}")} && ${format(local.terraform_deployment_cmd, lookup(var.deployment_configuration.accounts.prod, "path", "terraform/prod"), lookup(var.deployment_configuration.accounts.prod, "dry_run", false) ? "terraform plan" : "terraform apply -auto-approve")}"
  })
}

locals {
  # Dynamically create post deployment states to inject into the AWS Step Functions state machine definition
  additional_states = { for key in ["test", "stage", "prod"] : key =>
    { for i in range(length(lookup(var.post_deployment_states, key, []))) : var.post_deployment_states[key][i].name => merge({
      "Type"     = "Task"
      "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
      "Parameters" = {
        "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
        "Payload" = merge(local.common_input_to_fargate_states, {
          cmd_to_run  = lookup(var.post_deployment_states[key][i], "cmd_to_run", "")
          mountpoints = lookup(var.post_deployment_states[key][i], "mountpoints", {})
          # Check if Amazon States Language notation has been used
          # This is required as the language does not allow both `$.content` and `content` to be passed in.
          (
            lookup(var.post_deployment_states[key][i], "$.content", "")
            != "" ?
            "$.content" : "content"
          )             = lookup(var.post_deployment_states[key][i], "$.content", lookup(var.post_deployment_states[key][i], "content", ""))
          task_role_arn = var.post_deployment_states[key][i].task_role
          image         = var.post_deployment_states[key][i].image
          # Conditionally include parameters
          lookup(var.post_deployment_states[key][i], "task_memory", "") = lookup(var.post_deployment_states[key][i], "task_memory", "")
          lookup(var.post_deployment_states[key][i], "task_cpu", "")    = lookup(var.post_deployment_states[key][i], "task_cpu", "")
        })
      },
      # Suppress output from final states in parallel branches.
      # This avoids a lot of duplicated content in the output JSON during an execution.
      "OutputPath"     = key == "prod" || i < length(var.post_deployment_states[key]) - 1 ? "$" : null
      "ResultPath"     = null,
      "TimeoutSeconds" = 3600
      (
        i < length(var.post_deployment_states[key]) - 1 ? "Next" : "End"
      ) = i < length(var.post_deployment_states[key]) - 1 ? var.post_deployment_states[key][i + 1].name : true
      },
      # Error catching blocks are only used in parallel branches.
      key == "prod" ? {} : {
        "Catch" = [{
          "ErrorEquals" = ["States.ALL"]
          "Next"        = "Catch ${title(key)} Errors"
        }]
      })

    }
  }
}
