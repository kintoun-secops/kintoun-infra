# =======================================================
# platform/attacker 모듈 tfstate 활용
# =======================================================
data "terraform_remote_state" "attacker" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/attacker/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/network 모듈 tfstate 활용
# =======================================================
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/service-network 모듈 tfstate 활용
# =======================================================
data "terraform_remote_state" "service_network" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/service-network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/wazuh 모듈 tfstate 활용
# =======================================================
data "terraform_remote_state" "wazuh" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# =======================================================
# platform/velociraptor 모듈 tfstate 활용
# =======================================================
data "terraform_remote_state" "velociraptor" {
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/velociraptor/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  network = {
    attacker_vpc_id            = data.terraform_remote_state.attacker.outputs.attacker_vpc_id
    attacker_subnet_cidr_block = data.terraform_remote_state.attacker.outputs.attacker_subnet_cidr_block
    cert_vpc_id                = data.terraform_remote_state.network.outputs.main_vpc_id
    cert_subnet_cidr_block     = data.terraform_remote_state.network.outputs.cert_subnet_cidr_block
    service_vpc_id             = data.terraform_remote_state.service_network.outputs.vpc_id
    service_subnet_cidr_block  = data.terraform_remote_state.service_network.outputs.public_subnet_cidr_blocks["a"]
  }
  route_table = {
    attacker_rt_id = data.terraform_remote_state.attacker.outputs.attacker_subnet_rt_id
    cert_rt_id     = data.terraform_remote_state.network.outputs.cert_route_table_id
    service_rt_id  = data.terraform_remote_state.service_network.outputs.public_subnet_rt_id

  }
  security_group = {
    attacker_agent_sg_id     = data.terraform_remote_state.attacker.outputs.attacker_agent_sg_id
    wazuh_agent_sg_id        = data.terraform_remote_state.wazuh.outputs.wazuh_sg_agent_id
    velociraptor_agent_sg_id = data.terraform_remote_state.velociraptor.outputs.velociraptor_agent_sg_id
    frontend_sg_id           = data.terraform_remote_state.service_network.outputs.frontend_sg_id
    backend_sg_id            = data.terraform_remote_state.service_network.outputs.backend_sg_id
  }
}