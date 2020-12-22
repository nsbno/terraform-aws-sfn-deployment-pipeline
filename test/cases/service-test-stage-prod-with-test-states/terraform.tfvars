name_prefix = "example"
deployment_configuration = {
  image           = "vydev/terraform:0.12.29"
  task_role       = "task-role"
  deployment_role = "deployment-role"
  accounts = {
    service = {
      id = "123456789012"
    }
    test = {
      id = "234567890123"
    }
    stage = {
      id = "345678901234"
    }
    prod = {
      id = "456789012345"
    }
  }
}
post_deployment_states = {
  stage = [
    {
      name       = "Integration Tests"
      image      = "vydev/awscli"
      cmd_to_run = "echo Integration Tests"
      task_role  = "task-role"
    }
  ]
  prod = [
    {
      name       = "Smoke Tests"
      image      = "vydev/awscli"
      cmd_to_run = "echo Smoke Tests"
      task_role  = "task-role"
    }
  ]
}
pipeline_lambda_configuration = {
  error_catcher = {
    function_name = "error-catcher"
  }
  set_version = {
    function_name = "set-version"
    role          = "set-version-role"
    ssm_prefix    = "example"
    applications  = {}
  }
  single_use_fargate_task = {
    function_name  = "single-use-fargate-task"
    ecs_cluster    = "cluster"
    execution_role = "execution-role"
    subnets        = ["subnet-1", "subnet-2", "subnet-3"]
  }
}
