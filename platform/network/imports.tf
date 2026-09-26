# 기존 platform state에서 확인한 리소스를 가져온다. 이전 기록과 재실행을 위해 import 블록을 유지한다.

import {
  to = aws_internet_gateway.main_igw
  id = "igw-02d59842e31086360"
}

import {
  to = aws_route_table.cert_route_table
  id = "rtb-023221cbe7d73d1bf"
}

import {
  to = aws_route_table_association.cert_rt_association[0]
  id = "subnet-0cac6e6e76e3bf8fb/rtb-023221cbe7d73d1bf"
}

import {
  to = aws_subnet.cert_subnet[0]
  id = "subnet-0cac6e6e76e3bf8fb"
}

import {
  to = aws_vpc.main_vpc
  id = "vpc-088a414494f775322"
}
