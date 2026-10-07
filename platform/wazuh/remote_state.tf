data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  network = {
    main_vpc_id     = data.terraform_remote_state.network.outputs.main_vpc_id
    cert_subnet_ids = data.terraform_remote_state.network.outputs.cert_subnet_ids
  }
  dns = {
    route53_private_zone_id = data.terraform_remote_state.network.outputs.route53_private_zone_id
  }
}
