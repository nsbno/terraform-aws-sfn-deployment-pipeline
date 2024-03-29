output "state_machine_name" {
  value = aws_sfn_state_machine.this.name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.this.arn
}

output "state_machine_definition" {
  value = local.state_machine_definition
}
