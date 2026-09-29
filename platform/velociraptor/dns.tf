# =======================================================
# DNS Private 호스팅 존 생성
# =======================================================
resource "aws_route53_zone" "velociraptor_dns" {
  name    = "internal.kintoun.work"
  comment = "Private DNS for Velociraptor"

  vpc {
    vpc_id     = local.network.main_vpc_id
    vpc_region = "ap-northeast-2"
  }

  vpc {
    vpc_id     = local.network.service_vpc_id
    vpc_region = "ap-northeast-2"
  }

  tags = {
    Name      = "${var.project_name}-velociraptor-dns"
    ManagedBy = "Terraform"
  }
}

resource "aws_route53_record" "velociraptor" {
  zone_id = aws_route53_zone.velociraptor_dns.zone_id
  name    = "velo.internal.kintoun.work"
  type    = "A"

  ttl = 60

  records = [aws_instance.velociraptor_ec2.private_ip] # EC2 교체되도 새 IP 반영
}