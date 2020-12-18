locals {
  non_empty_states = [for state in local.states : state if length(state) > 0]
  state_machine_definition = {
    "Comment" = "A deployment pipeline implemented as a state machine"
    "StartAt" = "Get Latest Artifact Versions"
    # Define all states, and filter out states that are set to `null`
    "States" = { for i in range(length(local.non_empty_states)) : keys(local.non_empty_states[i])[0] => merge(local.non_empty_states[i][keys(local.non_empty_states[i])[0]], {
      i < length(local.non_empty_states) - 1 ? "Next" : "End" = i < length(local.non_empty_states) - 1 ? keys(local.non_empty_states[i + 1])[0] : true
    }) }
  }
}


locals {
  # Create an ordered list of all states to include
  states = flatten([
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
  ])
}
