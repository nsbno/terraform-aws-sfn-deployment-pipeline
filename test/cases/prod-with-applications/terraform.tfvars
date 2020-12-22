name_prefix = "example"
deployment_configuration = {
  image           = "vydev/terraform:0.12.29"
  task_role       = "task-role"
  deployment_role = "deployment-role"
  accounts = {
    prod = {
      id = "456789012345"
    }
  }
}
pipeline_lambda_configuration = {
  error_catcher = {
    function_name = "error-catcher"
  }
  set_version = {
    function_name = "set-version"
    role          = "set-version-role"
    ssm_prefix    = "example"
    applications = {
      ecr      = ["example-docker-app", "example-docker-app-2"]
      frontend = ["example-frontend-app"]
      lambda   = ["example-lambda-app"]
    }
  }
  single_use_fargate_task = {
    function_name  = "single-use-fargate-task"
    ecs_cluster    = "cluster"
    execution_role = "execution-role"
    subnets        = ["subnet-1", "subnet-2", "subnet-3"]
  }
}
