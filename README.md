# terraform-aws-sfn-deployment-pipeline
This Terraform module creates a Continuous Deployment (CD) pipeline using AWS Step Functions.

The pipeline deploys to the `test`, `stage` and `service` accounts in parallel, and deploys to `prod` only if all previous states have passed. The module allows you to emit deployment to the `service` account, thus effectively removing the entire `service` branch from the pipeline. See the images below for examples.

The module variables allow you to add an arbitrary number of _post-deployment_ states to the pipeline -- that is, states that will be run after a successful deployment to test, stage or prod. These states will spin up containers with a user-defined image, command and S3 content. Examples of such states are:
- An `Integration Tests` state after a successful deployment to stage.
- A `Smoke Tests` state after a successful deployment to prod.
- ...


## Pipeline Examples
Standard |  Non-Service | Post-Deployment States
:-------------------------:|:------------------------:|:-------------------------:
![](docs/pipeline.png)  |  ![](docs/non_service_pipeline.png)  | ![](docs/pipeline_custom_states.png)
