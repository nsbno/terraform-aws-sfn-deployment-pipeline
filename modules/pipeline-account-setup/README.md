# pipeline-account-setup
This module will create the Lambda functions that are used in the deployment pipeline, as well as a role that can be used as the task role in single-use Fargate tasks.

The module should be used in the AWS account that hosts the AWS Step Functions deployment pipeline. This account is typically the _service_ account.
