locals {
  db_host = data.terraform_remote_state.infra.outputs.db_private_ip
  db_name = data.terraform_remote_state.infra.outputs.db_name
  db_user = data.terraform_remote_state.infra.outputs.db_user
} 