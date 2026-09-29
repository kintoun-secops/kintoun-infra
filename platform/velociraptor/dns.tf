/*resource "aws_route53_record" "velociraptor" {
  zone_id = local.dns.route53_private_zone_id
  name    = "velo.internal.kintoun.work"
  type    = "A"

  ttl = 60

  records = [aws_instance.velociraptor_ec2.private_ip]
}*/
# 후속 PR에서 처리, network 모듈 apply 후 주석 해제 예정