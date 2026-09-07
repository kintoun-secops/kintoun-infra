# 최초 PR plan에서 생산자 state가 없을 때만 이전 state에서 확인한 출력값을 사용한다.
# 생산자 state가 존재하면 조회 오류나 출력 누락을 숨기지 않고 remote state를 사용한다.
data "aws_s3_objects" "network_state" {
  bucket = "kintoun-tfstate"
  prefix = "platform/network/terraform.tfstate"
}

locals {
  network_state_exists = contains(data.aws_s3_objects.network_state.keys, "platform/network/terraform.tfstate")
  migration_network = {
    main_igw_id = "igw-02d59842e31086360"
    main_vpc_id = "vpc-088a414494f775322"
  }
}
data "aws_s3_objects" "wazuh_state" {
  bucket = "kintoun-tfstate"
  prefix = "platform/wazuh/terraform.tfstate"
}

locals {
  wazuh_state_exists = contains(data.aws_s3_objects.wazuh_state.keys, "platform/wazuh/terraform.tfstate")
  migration_wazuh = {
    ssm_policy_arn    = "arn:aws:iam::446413909569:policy/kintoun-secops-infra-wazuh-ec2-ssm-role"
    wazuh_ec2_arn     = "arn:aws:ec2:ap-northeast-2:446413909569:instance/i-0d12ae915e1017223"
    wazuh_instance_id = "i-0d12ae915e1017223"
    wazuh_role_name   = "kintoun-secops-infra-wazuh-role"
    wazuh_sg_agent_id = "sg-013ec6231905613e8"
  }
}
