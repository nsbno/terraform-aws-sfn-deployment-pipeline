# CloudFormation
This folder contains a CloudFormation template that can be used to create an encrypted S3 bucket and a DynamoDB table for storing Terraform state remotely.

A CloudFormation stack can be created by using the AWS CLI in the following manner:
```sh
aws cloudformation create-stack \
  --stack-name "TerraformBootstrap" \
  --template-body file://cfn_bootstrap.yml \
  && aws cloudformation wait \
    stack-create-complete \
    --stack-name "TerraformBootstrap"
```
