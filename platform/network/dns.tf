# =======================================================
# DNS Private 호스팅 존 생성
# =======================================================
resource "aws_route53_zone" "private_dns" {
  name    = "internal.kintoun.work"
  comment = "Private DNS for Velociraptor and Wazuh"

  vpc {
    vpc_id     = aws_vpc.main_vpc.id
    vpc_region = "ap-northeast-2"
  }

  vpc {
    vpc_id     = local.network.service_vpc_id
    vpc_region = "ap-northeast-2"
  }

  vpc {
    vpc_id     = local.network.attacker_vpc_id
    vpc_region = "ap-northeast-2"
  }

  tags = {
    Name      = "${var.project_name}-private-dns"
    ManagedBy = "Terraform"
  }
}