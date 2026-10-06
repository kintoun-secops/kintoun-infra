data "aws_subnet" "cert" {
  id = local.network.cert_subnet_id
}

resource "aws_ebs_volume" "uptime_kuma_data_ebs" {
  availability_zone = data.aws_subnet.cert.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true
  final_snapshot    = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-uptime-kuma-data-volume"
    ManagedBy = "Terraform"
  }
}

resource "aws_volume_attachment" "uptime_kuma_data_ebs" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.uptime_kuma_data_ebs.id
  instance_id                    = aws_instance.uptime_kuma_ec2.id
  stop_instance_before_detaching = true
}
