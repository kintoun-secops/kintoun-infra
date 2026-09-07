# 기존 platform state에서 확인한 리소스를 가져온다. 이전 기록과 재실행을 위해 import 블록을 유지한다.

import {
  to = aws_iam_instance_profile.wazuh_profile
  id = "kintoun-secops-infra-wazuh-profile"
}

import {
  to = aws_iam_policy.wazuh_ssm_role
  id = "arn:aws:iam::446413909569:policy/kintoun-secops-infra-wazuh-ec2-ssm-role"
}

import {
  to = aws_iam_role.wazuh_role
  id = "kintoun-secops-infra-wazuh-role"
}

import {
  to = aws_iam_role_policy_attachment.wazuh_ssm
  id = "kintoun-secops-infra-wazuh-role/arn:aws:iam::446413909569:policy/kintoun-secops-infra-wazuh-ec2-ssm-role"
}

import {
  to = aws_instance.wazuh_ec2
  id = "i-0d12ae915e1017223"
}

import {
  to = aws_security_group.wazuh_sg
  id = "sg-09f88859ecac9f19f"
}

import {
  to = aws_security_group.wazuh_sg_agent
  id = "sg-013ec6231905613e8"
}

import {
  to = aws_vpc_security_group_egress_rule.wazuh_sg_outbound
  id = "sgr-090a687017b179449"
}
