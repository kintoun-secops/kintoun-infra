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
    main_igw_id = local.network_state_exists ? data.terraform_remote_state.network[0].outputs.main_igw_id : local.migration_network.main_igw_id
    main_vpc_id = local.network_state_exists ? data.terraform_remote_state.network[0].outputs.main_vpc_id : local.migration_network.main_vpc_id
  }
}
data "terraform_remote_state" "wazuh" {
  count   = local.wazuh_state_exists ? 1 : 0
  backend = "s3"

  config = {
    bucket = "kintoun-tfstate"
    key    = "platform/wazuh/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  wazuh = {
    ssm_policy_arn    = local.wazuh_state_exists ? data.terraform_remote_state.wazuh[0].outputs.ssm_policy_arn : local.migration_wazuh.ssm_policy_arn
    wazuh_ec2_arn     = local.wazuh_state_exists ? data.terraform_remote_state.wazuh[0].outputs.wazuh_ec2_arn : local.migration_wazuh.wazuh_ec2_arn
    wazuh_instance_id = local.wazuh_state_exists ? data.terraform_remote_state.wazuh[0].outputs.wazuh_instance_id : local.migration_wazuh.wazuh_instance_id
    wazuh_role_name   = local.wazuh_state_exists ? data.terraform_remote_state.wazuh[0].outputs.wazuh_role_name : local.migration_wazuh.wazuh_role_name
    wazuh_sg_agent_id = local.wazuh_state_exists ? data.terraform_remote_state.wazuh[0].outputs.wazuh_sg_agent_id : local.migration_wazuh.wazuh_sg_agent_id
  }
}
