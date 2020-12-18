output "deployment_role_name" {
  value = aws_iam_role.deployment.name
}

output "deployment_role_arn" {
  value = aws_iam_role.deployment.arn
}

output "set_version_role_name" {
  value = aws_iam_role.set_version.name
}

output "set_version_role_arn" {
  value = aws_iam_role.set_version.arn
}
