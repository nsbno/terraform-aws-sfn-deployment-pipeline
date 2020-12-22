locals {
  # The state machine definition that we will jsonencode and use
  state_machine_definition = {
    "Comment" = "A deployment pipeline implemented as a state machine"
    "StartAt" = "Get Latest Artifact Versions"
    # Define all states in the correct order
    "States" = {
      for i in range(length(local.states)) :
      keys(local.states[i])[0] => merge(
        local.states[i][keys(local.states[i])[0]],
        {
          # Determine if we have reached the final state or not
          (
            i < length(local.states) - 1
            ? "Next"
            : "End"
            ) = (
            i < length(local.states) - 1
            ? keys(local.states[i + 1])[0]
            : true
          )
        }
      )
    }
  }
}


locals {
  # Create an ordered list of all states to include, and filter out empty objects -- that is, states that were determined to be excluded.
  states = [for state in flatten([
    # Initial state -- we always include this
    {
      "Get Latest Artifact Versions" = {
        "Comment"  = "Get the latest versions of application artifacts in S3 and ECR"
        "Type"     = "Task"
        "Resource" = "arn:aws:states:::lambda:invoke",
        "Parameters" = {
          "FunctionName" = var.pipeline_lambda_configuration.set_version.function_name
          "Payload"      = local.input_to_get_latest_artifact_versions
        }
        "ResultSelector" = {
          "ecr.$"      = "$.Payload.ecr"
          "frontend.$" = "$.Payload.frontend"
          "lambda.$"   = "$.Payload.lambda"
        }
        "ResultPath" = "$.versions",
      }
    },
    # A parallel state will only be created if there are two or more parallel deployments
    length(local.parallel_deployment_accounts) == 0 ? {} :
    {
      "Parallel Deployment" = {
        "Comment"    = "Parallel deployment to ${join(", ", keys(local.parallel_deployment_accounts))} environments"
        "Type"       = "Parallel"
        "ResultPath" = "$.result"
        # Perform a reverse sort in order to get the branches in the order `test, service, stage` for visual purposes
        "Branches" = [for account_name in reverse(sort(keys(local.parallel_deployment_accounts))) : {
          "StartAt" = "Bump Versions in ${title(account_name)}"
          "States" = merge({
            "Bump Versions in ${title(account_name)}" = {
              "Comment"  = "Update SSM parameters in ${account_name} environment to latest versions of applications artifacts",
              "Type"     = "Task",
              "Resource" = "arn:aws:states:::lambda:invoke"
              "Parameters" = {
                "FunctionName" = var.pipeline_lambda_configuration.set_version.function_name
                "Payload"      = local.input_to_set_version[account_name]
              }
              "Catch" = [{
                "ErrorEquals" = ["States.ALL"]
                "Next"        = "Catch ${title(account_name)} Errors"
              }]
              "ResultPath" = null
              "Next"       = "Deploy ${title(account_name)}"
            }
            "Deploy ${title(account_name)}" = {
              "Type"     = "Task"
              "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
              "Parameters" = {
                "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
                "Payload"      = local.input_to_deploy_states[account_name]
              },
              "Catch" = [{
                "ErrorEquals" = ["States.ALL"]
                "Next"        = "Catch ${title(account_name)} Errors"
              }]
              "OutputPath"     = length(lookup(var.post_deployment_states, account_name, [])) > 0 ? "$" : null
              "ResultPath"     = null,
              "TimeoutSeconds" = local.default_deploy_state_timeout
              (
                length(lookup(var.post_deployment_states, account_name, []))
                > 0 ? "Next" : "End"
              ) = length(lookup(var.post_deployment_states, account_name, [])) > 0 ? var.post_deployment_states[account_name][0].name : true
            }
            "Catch ${title(account_name)} Errors" = {
              "Type" = "Pass"
              "End"  = true
            }
          }, local.additional_parallel_states[account_name])
          }
        ]
      }
    },
    # We only need the `Raise Errors` state if we have a parallel state.
    length(local.parallel_deployment_accounts) == 0 ? {} :
    {
      "Raise Errors" = {
        "Comment"  = "Raise previously caught errors, if any"
        "Type"     = "Task",
        "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        "Parameters" = {
          "FunctionName" = var.pipeline_lambda_configuration.error_catcher.function_name
          "Payload" = {
            "token.$" = "$$.Task.Token"
            "input.$" = "$.result"
          }
        }
        "ResultPath"     = "$.errors_found",
        "TimeoutSeconds" = local.default_deploy_state_timeout
      }
      # Reverse alphabetically to make sure deployment to prod is run last
    },
    [for account_name in reverse(sort(setsubtract(keys(local.accounts), keys(local.parallel_deployment_accounts)))) : [{
      "Bump Versions in ${title(account_name)}" = {
        "Comment"  = "Update SSM parameters in ${account_name} environment to latest versions of applications artifacts",
        "Type"     = "Task"
        "Resource" = "arn:aws:states:::lambda:invoke",
        "Parameters" = {
          "FunctionName" = var.pipeline_lambda_configuration.set_version.function_name
          "Payload"      = local.input_to_set_version[account_name]
        },
        "ResultPath" = null,
      }
      }, {
      "Deploy ${title(account_name)}" = {
        "Type"     = "Task",
        "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        "Parameters" = {
          "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
          "Payload"      = local.input_to_deploy_states[account_name]
        }
        "ResultPath"     = null
        "TimeoutSeconds" = local.default_deploy_state_timeout
      }
      },
      [for name, state in local.additional_states[account_name] : { "${name}" = state }]
      ]
    ]
  ]) : state if length(state) > 0]
}


locals {
  # Dynamically create post deployment states to inject into the AWS Step Functions state machine definition
  additional_states = { for key in setsubtract(keys(local.accounts), keys(local.parallel_deployment_accounts)) : key =>
    { for i in range(length(lookup(var.post_deployment_states, key, []))) : var.post_deployment_states[key][i].name => {
      "Type"     = "Task"
      "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
      "Parameters" = {
        "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
        "Payload" = merge(local.common_input_to_fargate_states, {
          cmd_to_run  = lookup(var.post_deployment_states[key][i], "cmd_to_run", "")
          mountpoints = lookup(var.post_deployment_states[key][i], "mountpoints", {})
          # Check if Amazon States Language notation has been used
          # This is required as the language does not allow both `content.$` and `content` to be passed in.
          (
            lookup(var.post_deployment_states[key][i], "content.$", "")
            != "" ?
            "content.$" : "content"
          )             = lookup(var.post_deployment_states[key][i], "content.$", lookup(var.post_deployment_states[key][i], "content", ""))
          task_role_arn = var.post_deployment_states[key][i].task_role
          image         = var.post_deployment_states[key][i].image
          # Conditionally include parameters
          lookup(var.post_deployment_states[key][i], "task_memory", "") = lookup(var.post_deployment_states[key][i], "task_memory", "")
          lookup(var.post_deployment_states[key][i], "task_cpu", "")    = lookup(var.post_deployment_states[key][i], "task_cpu", "")
        })
      },
      "ResultPath"     = null,
      "TimeoutSeconds" = local.default_additional_state_timeout
      }
    }
  }
  # Dynamically create post deployment states to inject into the AWS Step Functions state machine definition
  additional_parallel_states = { for key in keys(local.parallel_deployment_accounts) : key =>
    { for i in range(length(lookup(var.post_deployment_states, key, []))) : var.post_deployment_states[key][i].name => {
      "Type"     = "Task"
      "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
      "Parameters" = {
        "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
        "Payload" = merge(local.common_input_to_fargate_states, {
          # Add shell command for assuming role if the ARN of a role is passed in
          cmd_to_run = join(" && ", [for cmd in [
            lookup(var.post_deployment_states[key][i], "assume_role", "") != ""
            ? "${format(local.assume_role_cmd, var.post_deployment_states[key][i].assume_role)}"
            : null, lookup(var.post_deployment_states[key][i], "cmd_to_run", "")
            ] : cmd if cmd != null
          ])
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
      "OutputPath" = i < length(var.post_deployment_states[key]) - 1 ? "$" : null
      (
        i < length(var.post_deployment_states[key]) - 1 ? "Next" : "End"
      )                = i < length(var.post_deployment_states[key]) - 1 ? var.post_deployment_states[key][i + 1].name : true
      "ResultPath"     = null,
      "TimeoutSeconds" = local.default_additional_state_timeout
      "Catch" = [{
        "ErrorEquals" = ["States.ALL"]
        "Next"        = "Catch ${title(key)} Errors"
      }]
      }
    }
  }
}
