# =======================================================
# Amazon Linux 2023 arm64 AMI 조회
# =======================================================
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# =======================================================
# 프론트 EC2 생성
# =======================================================
resource "aws_instance" "frontend" {
  ami           = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.frontend_instance_type
  subnet_id     = local.public_subnet_ids["a"]

  vpc_security_group_ids      = [local.frontend_sg_id]
  iam_instance_profile        = aws_iam_instance_profile.frontend.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/files/frontend-install.sh", {
    region            = var.region
    artifact_bucket   = aws_s3_bucket.artifacts.id
    listen_port       = local.frontend_app_port
    health_path       = var.frontend_health_path
    keep_releases     = var.keep_releases
    release_parameter = local.release_parameters["frontend"]
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  lifecycle {
    ignore_changes = [
      ami,
      associate_public_ip_address,
    ]
  }

  depends_on = [aws_ssm_parameter.current_release]

  tags = {
    Name      = "${var.project_name}-service-frontend"
    Service   = local.service_tag
    Role      = "frontend"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# 백엔드 EC2 생성
# =======================================================
resource "aws_instance" "backend" {
  ami           = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.backend_instance_type
  subnet_id     = local.public_subnet_ids["a"]

  vpc_security_group_ids      = [local.backend_sg_id]
  iam_instance_profile        = aws_iam_instance_profile.backend.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/files/backend-install.sh", {
    region            = var.region
    artifact_bucket   = aws_s3_bucket.artifacts.id
    app_port          = local.backend_app_port
    db_host           = local.db_endpoint
    db_port           = local.db_port
    db_name           = local.db_name
    db_iam_user       = local.db_iam_user
    keep_releases     = var.keep_releases
    release_parameter = local.release_parameters["backend"]
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  lifecycle {
    ignore_changes = [
      ami,
      associate_public_ip_address,
    ]
  }

  depends_on = [aws_ssm_parameter.current_release]

  tags = {
    Name      = "${var.project_name}-service-backend"
    Service   = local.service_tag
    Role      = "backend"
    ManagedBy = "Terraform"
  }
}
