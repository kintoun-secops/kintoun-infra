# ==================================================================
# =====================Victim EC2를 위한 Network 설계==================
# ==================================================================

# =======================================================
# Public Subnet 생성 for ALB(서로 다른 AZ에 배치)
# =======================================================
resource "aws_subnet" "alb_public_subnets" {
  for_each = var.alb_public_subnets

  vpc_id            = local.main_vpc_id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  map_public_ip_on_launch = false

  tags = {
    Name     = "${var.project_name}-alb-public-subnet-${each.key}"
    Role     = "ALB"
    ManageBy = "Terraform"
  }
}

# =======================================================
# Public Subnet 생성 for Victim EC2
# =======================================================
resource "aws_subnet" "victim_public_subnet" {
  vpc_id            = local.main_vpc_id
  cidr_block        = var.victim_public_subnet_cidr
  availability_zone = "ap-northeast-2a"

  map_public_ip_on_launch = false

  tags = {
    Name     = "${var.project_name}-victim-public-subnet"
    Role     = "Victim"
    ManageBy = "Terraform"
  }
}

# =======================================================
# Victim Subnet and ALB Subnets 용 라우트 테이블 생성 및 라우팅
# =======================================================
resource "aws_route_table" "victim_route_table" {
  vpc_id = local.main_vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.main_igw_id
  }

  tags = {
    Name     = "${var.project_name}-victim-public-route-table"
    Role     = "Victim"
    ManageBy = "Terraform"
  }
}

resource "aws_route_table_association" "victim_public" {
  subnet_id      = aws_subnet.victim_public_subnet.id
  route_table_id = aws_route_table.victim_route_table.id
}

resource "aws_route_table_association" "alb_public_subnets" {
  for_each       = aws_subnet.alb_public_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.victim_route_table.id
}


# ==================================================================
# ====================Victim EC2 생성================================
# ==================================================================

# =======================================================
# Victim EC2 생성
# =======================================================
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "victim_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.victim_public_subnet.id
  vpc_security_group_ids = [
    aws_security_group.victim_sg.id,
    aws_security_group.victim_sg_agent.id
  ]
  iam_instance_profile        = aws_iam_instance_profile.victim_ec2_profile.name
  associate_public_ip_address = true

  user_data                   = file("${path.module}/files/victim-install.sh")
  user_data_replace_on_change = false

  root_block_device {
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional" # IMDSv1과 IMDSv2 모두 허용
    http_put_response_hop_limit = 2          # docker 환경에서도 IMDS 사용
    instance_metadata_tags      = "disabled" # 태그정보는 노출되지 않도록하여 공격 표면 최소화"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name     = "${var.project_name}-victim-ec2"
    ManageBy = "Terraform"
  }
}

# ==================================================================
# =================== 공격 대상 S3 Bucket 생성 ========================
# ==================================================================

# ======================================================
# 공격용 S3 Bucket 생성
# ======================================================
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "victim" {
  bucket        = "${var.victim_bucket_name}-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name     = "${var.project_name}-victim-bucket"
    ManageBy = "Terraform"
  }
}

# ======================================================
# 공격용 S3 Bucket BPA
# ======================================================
resource "aws_s3_bucket_public_access_block" "victim" {
  bucket = aws_s3_bucket.victim.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ======================================================
# 공격용 S3 Bucket SSE
# ======================================================
resource "aws_s3_bucket_server_side_encryption_configuration" "victim" {
  bucket = aws_s3_bucket.victim.id

  rule {
    apply_server_side_encryption_by_default {
      # S3 관리형 키이기 때문에,
      # s3:GetObject에 대한 권한만 있으면 S3가 객체를 자동으로 복호화하여 반환
      sse_algorithm = "AES256"
    }
  }
}

# ======================================================
# 공격용 S3 Bucket에 가짜 Secrets 업로드
# ======================================================
/*locals {
  upload_dir   = "${path.module}/files/secrets-file"
  upload_files = fileset(local.upload_dir, "**") # 하위 폴더 포함 모든 파일 찾기
}

resource "aws_s3_object" "secrets_upload" {
  for_each = local.upload_files

  bucket = aws_s3_bucket.victim.id
  key    = each.value
  source = "${local.upload_dir}/${each.value}"

  # 암호화 방식이나 S3 ETag 형식에 영향받지 않고 파일변경 감지 - 파일 내용 변경 시 객체 다시 업로드
  source_hash = filemd5("${local.upload_dir}/${each.value}")
}*/

# ======================================================
# 기존 실습 파일을 S3에 보존하고 Terraform 관리만 해제
# ======================================================
removed {
  from = aws_s3_object.secrets_upload

  lifecycle {
    destroy = false
  }
}