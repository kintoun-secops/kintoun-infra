resource "aws_route53_record" "velociraptor" {
  zone_id = local.dns.route53_private_zone_id
  name    = "velo.internal.kintoun.work"
  type    = "A"

  ttl = 60

  records = [aws_instance.velociraptor_ec2.private_ip]
}