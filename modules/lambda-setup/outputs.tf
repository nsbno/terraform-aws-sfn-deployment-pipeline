output "single_use_fargate_task" {
  value = {
    task_execution_role_arn      = module.single_use_fargate_task.task_execution_role_arn
    ecs_cluster_arn              = module.single_use_fargate_task.ecs_cluster_arn
    function_name                = module.single_use_fargate_task.function_name
    default_deployment_role_name = module.roles.deployment_role_name
    default_deployment_role_arn  = module.roles.deployment_role_arn
    default_task_role_name       = aws_iam_role.fargate_task.id
    default_task_role_arn        = aws_iam_role.fargate_task.arn
  }
}

output "set_version" {
  value = {
    function_name     = module.set_version.function_name
    ssm_prefix        = "${var.name_prefix}/versions"
    default_role_name = module.roles.set_version_role_name
    default_role_arn  = module.roles.set_version_role_arn
  }
}

output "error_catcher" {
  value = {
    function_name = module.error_catcher.function_name
  }
}
