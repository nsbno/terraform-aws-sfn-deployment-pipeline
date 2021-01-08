variable "name_prefix" {
  description = "A prefix used for naming resources."
  type        = string
}

variable "deployment_configuration" {
  description = <<DOC
The configuration for the Terraform deployment states (e.g., `Deploy Test`) in the pipeline.
---
deployment_role: The name of a role to assume during a deployment (e.g., a cross-account role).
task_role: The name of a task role to use for the single-use deployment Fargate tasks.
image: The Docker image to use during a deployment (e.g., `vydev/terraform:0.12.29`).
accounts: An object that describes which accounts to deploy to. At least one of the keys `test`, `stage`, `prod` or `service` is required.
  service: An account object.
    id: The account id.
    path: Optional path to Terraform folder (e.g., `terraform/custom`).
    dry_run: Optional boolean that determines if the pipeline should do a dry-run of the deployment or not -- where a dry-run means running `terraform plan` instead of `terraform apply`, and not updating the SSM version parameters. (Defaults to false).
  test: Same account object as above.
  stage: Same account object as above.
  prod: Same account object as above.
---
DOC
  type = object({
    deployment_role = string
    task_role       = string
    image           = string
    accounts        = map(any)
  })
}

variable "pipeline_lambda_configuration" {
  description = <<DOC
The configuration for the various Lambda functions used in the pipeline.
---
error_catcher: A required object that contains configuration for the error-catcher Lambda.
  function_name: The name of the function.
set_version: A required object that contains configuration for the set-version Lambda.
  function_name: The name of the function.
  role: The name of the role to assume during `Bump Versions in <env>` states.
  ssm_prefix: The SSM prefix to use when setting parameters in AWS Parameter Store.
  default_branch: Optional name of the branch used when looking for artifact versions (defaults to `master`).
  applications: An optional object that describes which applications the pipeline should version.
    ecr: Optional list of names of Docker applications to fetch and set versions for.
    frontend: Optional list of names of static frontend applications to fetch and set versions for.
    lambda: Optional list of names of Lambda applications to fetch and set versions for.
  lambda_s3_bucket: Optional name of S3 bucket for storing Lambda artifacts.
  lambda_s3_prefix: Optional prefix to use when looking for Lambda artifacts.
  frontend_s3_bucket: Optional name of S3 buckt for storing frontend artifacts.
  frontend_s3_prefix: Optional prefix to use when looking for frontend artifacts.
single_use_fargate_task: A required object that contains configuration for the single-use-fargate-task Lambda.
  function_name: The name of the function.
  ecs_cluster: The name of the ECS cluster to use.
  execution_role: The name of the ECS execution role.
  subnets: A list of subnets to run the Fargate tasks in.
  dockerhub_credentials: Optional ARN of an AWS Secrets Manager secret containing Docker Hub credentials.
---
DOC
  type = object({
    error_catcher           = any
    single_use_fargate_task = any
    set_version             = any
  })
}

variable "post_deployment_states" {
  description = <<DOC
Optional Fargate states to run after successful deployments (e.g., `Integration Tests`).
---
service: An optional list of Fargate states to run after `Deploy Service`.
test: An optional list of Fargate states to run after `Deploy Test`.
stage: An optional list of Fargate states to run after `Deploy Stage`.
prod: An optional list of Fargate states to run after `Deploy Prod`.
---

A Fargate state is defined as an object:
---
name: The name of the state.
image: The image to use.
task_role: The name of a task role to use for the Fargate task.
assume_role: Optional ARN of role to assume before running shell command.
cmd_to_run: Optional shell command to run inside the container.
content: Optional S3 ZIP file to mount (Amazon States Language notation can be used, e.g., `content.$`).
task_memory: Optional string of amount of task memory to allocate.
task_cpu: Optional string of amount of task cpu to allocate.
mountpoints: Optional map of mountpoints and S3 ZIP files to mount. Conflicts with `content`.
---
DOC
  default     = {}
}

variable "tags" {
  description = "A map of tags (key-value pairs) passed to resources."
  type        = map(string)
  default     = {}
}
