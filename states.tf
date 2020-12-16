locals {
  state_definition = {
    "Comment" = "A deployment pipeline implemented as a state machine"
    "StartAt" = "Get Latest Artifact Versions"
    "States" = merge({
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
        "Next"       = "Deploy to Test and Stage"
      }
      "Deploy to Test and Stage" = {
        "Comment"    = "Parallel deployment to test and stage environments"
        "Type"       = "Parallel"
        "Next"       = "Raise Errors"
        "ResultPath" = "$.result"
        "Branches" = concat([
          {
            "StartAt" = "Bump Versions in Test"
            "States" = merge({
              "Bump Versions in Test" = {
                "Comment"  = "Update SSM parameters in test environment to latest versions of applications artifacts",
                "Type"     = "Task",
                "Resource" = "arn:aws:states:::lambda:invoke"
                "Parameters" = {
                  "FunctionName" = var.pipeline_lambda_configuration.set_version.function_name
                  "Payload"      = local.input_to_bump_versions_in_test
                }
                "Catch" = [{
                  "ErrorEquals" = ["States.ALL"]
                  "Next"        = "Catch Test Errors"
                }]
                "ResultPath" = null
                "Next"       = "Deploy Test"
              }
              "Deploy Test" = {
                "Type"     = "Task"
                "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
                "Parameters" = {
                  "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
                  "Payload"      = local.input_to_deploy_test
                },
                "Catch" = [{
                  "ErrorEquals" = ["States.ALL"]
                  "Next"        = "Catch Test Errors"
                }]
                "OutputPath"     = length(lookup(var.post_deployment_states, "test", [])) > 0 ? "$" : null
                "ResultPath"     = null,
                "TimeoutSeconds" = 3600
                (
                  length(lookup(var.post_deployment_states, "test", []))
                  > 0 ? "Next" : "End"
                ) = length(lookup(var.post_deployment_states, "test", [])) > 0 ? var.post_deployment_states["test"][0].name : true
              }
              "Catch Test Errors" = {
                "Type" = "Pass"
                "End"  = true
              }
            }, local.additional_states.test)
          },
          {
            "StartAt" = "Bump Versions in Stage"
            "States" = merge({
              "Bump Versions in Stage" = {
                "Comment"  = "Update SSM parameters in stage environment to latest versions of applications artifacts",
                "Type"     = "Task",
                "Resource" = "arn:aws:states:::lambda:invoke"
                "Parameters" = {
                  "FunctionName" = var.pipeline_lambda_configuration.set_version.function_name
                  "Payload"      = local.input_to_bump_versions_in_stage
                }
                "Catch" = [{
                  "ErrorEquals" = ["States.ALL"]
                  "Next"        = "Catch Stage Errors"
                }]
                "ResultPath" = null,
                "Next"       = "Deploy Stage"
              }
              "Deploy Stage" = {
                "Type"     = "Task",
                "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken",
                "Parameters" = {
                  "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
                  "Payload"      = local.input_to_deploy_stage
                }
                "Catch" = [{
                  "ErrorEquals" = ["States.ALL"]
                  "Next"        = "Catch Stage Errors"
                }]
                "OutputPath"     = length(lookup(var.post_deployment_states, "stage", [])) > 0 ? "$" : null
                "ResultPath"     = null,
                "TimeoutSeconds" = 3600
                (
                  length(lookup(var.post_deployment_states, "stage", []))
                  > 0 ? "Next" : "End"
                ) = length(lookup(var.post_deployment_states, "stage", [])) > 0 ? var.post_deployment_states["stage"][0].name : true
              }
              "Catch Stage Errors" : {
                "Type" : "Pass",
                "End" : true
            } }, local.additional_states.stage)
          }
          ], contains(keys(var.deployment_configuration.accounts), "service") ? [
          {
            "StartAt" = "Deploy Service"
            "States" = {
              "Deploy Service" = {
                "Type"     = "Task",
                "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken",
                "Parameters" = {
                  "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
                  "Payload"      = local.input_to_deploy_service
                }
                "Catch" = [{
                  "ErrorEquals" = ["States.ALL"]
                  "Next"        = "Catch Service Errors"
                }]
                "ResultPath"     = null
                "OutputPath"     = null
                "TimeoutSeconds" = 3600
                "End"            = true
              }
              "Catch Service Errors" : {
                "Type" : "Pass",
                "End" : true
              }
            }
          }
        ] : [])
      },
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
        "TimeoutSeconds" = 3600
        "Next"           = "Bump Versions in Prod"
      }
      "Bump Versions in Prod" = {
        "Comment"  = "Update SSM parameters in prod environment to latest versions of applications artifacts",
        "Type"     = "Task"
        "Resource" = "arn:aws:states:::lambda:invoke",
        "Parameters" = {
          "FunctionName" = var.pipeline_lambda_configuration.set_version.function_name
          "Payload"      = local.input_to_bump_versions_in_prod
        },
        "ResultPath" = null,
        "Next"       = "Deploy Prod"
      }
      "Deploy Prod" = {
        "Type"     = "Task",
        "Resource" = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        "Parameters" = {
          "FunctionName" = var.pipeline_lambda_configuration.single_use_fargate_task.function_name
          "Payload"      = local.input_to_deploy_prod
        }
        "ResultPath"     = null
        "ResultPath"     = null,
        "TimeoutSeconds" = 3600
        (
          length(lookup(var.post_deployment_states, "prod", []))
          > 0 ? "Next" : "End"
        ) = length(lookup(var.post_deployment_states, "prod", [])) > 0 ? var.post_deployment_states["prod"][0].name : true
      }
    }, local.additional_states.prod)
  }
}

