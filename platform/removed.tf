# network와 wazuh의 import 이후 기존 state의 관리만 해제한다. 사용자 권한은 이 루트에 남긴다.

removed {
  from = aws_iam_instance_profile.wazuh_profile

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_policy.wazuh_ssm_role

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role.wazuh_role

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role_policy_attachment.wazuh_ssm

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_instance.wazuh_ec2

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_internet_gateway.main_igw

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_route_table.public_route_table

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_route_table_association.public_rt_association

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group.wazuh_sg

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group.wazuh_sg_agent

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_subnet.public_subnet

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_vpc.main_vpc

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_vpc_security_group_egress_rule.wazuh_sg_outbound

  lifecycle {
    destroy = false
  }
}
