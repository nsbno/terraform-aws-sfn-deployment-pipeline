terraform {
  required_providers {
    local = "2.0.0"
  }
}

resource "local_file" "sfn_definition" {
  content  = jsonencode(local.state_machine_definition)
  filename = "${path.module}/generated.json"
}
