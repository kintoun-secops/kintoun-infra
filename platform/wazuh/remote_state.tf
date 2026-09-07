data "terraform_remote_state" "network" {
  count   = local.network_state_exists ? 1 : 0
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  network = {
    main_vpc_id       = local.network_state_exists ? data.terraform_remote_state.network[0].outputs.main_vpc_id : local.migration_network.main_vpc_id
    public_subnet_ids = local.network_state_exists ? data.terraform_remote_state.network[0].outputs.public_subnet_ids : local.migration_network.public_subnet_ids
  }
}
