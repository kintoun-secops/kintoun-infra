resource "aws_route53_record" "wazuh" {
  zone_id = local.dns.route53_private_zone_id
  name    = "wazuh.internal.kintoun.work"
  type    = "A"

  ttl = 60

  records = [aws_instance.wazuh_ec2.private_ip]
}