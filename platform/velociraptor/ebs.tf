data "aws_subnet" "cert" {
  id = local.network.cert_subnet_id
}

resource "aws_ebs_volume" "velociraptor_data_ebs" {
  availability_zone = data.aws_subnet.cert.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true
  final_snapshot    = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "velociraptor_data_ebs" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.velociraptor_data_ebs.id
  instance_id                    = aws_instance.velociraptor_ec2.id
  stop_instance_before_detaching = true # 인스턴스 교체 시 옛 인스턴스 정상 종료 뒤 EBS 분리
}