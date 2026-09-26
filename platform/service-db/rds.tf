# =======================================================
# 최종 스냅샷 이름 충돌 방지용 접미사
# =======================================================
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =======================================================
# DB Subnet Group 생성
# =======================================================
resource "aws_db_subnet_group" "main" {
  name = "${var.project_name}-service-db-subnet-group"

  subnet_ids = values(local.private_subnet_ids)

  tags = {
    Name      = "${var.project_name}-service-db-subnet-group"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# DB Parameter Group 생성
# =======================================================
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-service-db-pg"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name      = "${var.project_name}-service-db-pg"
    ManagedBy = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =======================================================
# RDS 인스턴스 생성
# =======================================================
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-service-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_master_username

  manage_master_user_password = true

  iam_database_authentication_enabled = true

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [local.database_sg_id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period = var.db_backup_retention_days
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  deletion_protection        = var.db_deletion_protection

  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-service-db-final-${random_string.suffix.result}"

  tags = {
    Name      = "${var.project_name}-service-db"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# RDS 상태 유지
# =======================================================
resource "aws_rds_instance_state" "main" {
  identifier = aws_db_instance.main.identifier
  state      = var.db_state
}
