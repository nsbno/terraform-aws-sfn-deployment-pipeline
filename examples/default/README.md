# Default
This folder contains four different Terraform root modules that configures a deployment pipeline based on AWS Step Functions.

Go through each folder and replace the placeholders (marked with `TODO`) with your own values.

Each root module requires an initial instantiation to create all the necessary resources in each account. This can be done by logging in to the respective AWS account on the command-line, changing the directory (e.g., `cd test`) and then running `terraform init` and `terraform apply`.

**NOTE**: All of the Terraform root modules expect an encrypted S3 bucket (`<account-id>-terraform-state`) and DynamoDB table (`<account-id>-terraform-lock`) to exist in each account.
