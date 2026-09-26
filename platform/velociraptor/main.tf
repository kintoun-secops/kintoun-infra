data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# =======================================================
# EC2 생성 for Velociraptor Server
# =======================================================
resource "aws_instance" "velociraptor_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = var.instance_type
  subnet_id     = local.network.cert_subnet_id

  vpc_security_group_ids = [
    aws_security_group.velociraptor_sg.id
  ]
  iam_instance_profile        = aws_iam_instance_profile.velociraptor_ec2_profile.name
  associate_public_ip_address = false
  user_data                   = file("${path.module}/files/velociraptor-install.sh")
  user_data_replace_on_change = false

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = false

    tags = {
      Name      = "${var.project_name}-velociraptor-root-volume"
      ManagedBy = "Terraform"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  lifecycle {
    ignore_changes = [
      ami
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm
  ]

  tags = {
    Name      = "${var.project_name}-velociraptor-ec2"
    ManagedBy = "Terraform"
  }
}