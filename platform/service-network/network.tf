# =======================================================
# VPC 생성
# =======================================================
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.project_name}-service-vpc"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Internet Gateway 생성
# =======================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-service-igw"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Public Subnet 생성 (앱 서버)
# =======================================================
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.project_name}-service-public-${each.key}"
    Tier      = "public"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Private Subnet 생성 (RDS)
# =======================================================
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.project_name}-service-private-${each.key}"
    Tier      = "private"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Public Route Table 생성 및 라우팅
# =======================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name      = "${var.project_name}-service-public-rt"
    ManagedBy = "Terraform"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# =======================================================
# Private Route Table 생성
# =======================================================
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-service-private-rt"
    ManagedBy = "Terraform"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# =======================================================
# S3 Gateway Endpoint 생성
# =======================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id,
  ]

  tags = {
    Name      = "${var.project_name}-service-s3-endpoint"
    ManagedBy = "Terraform"
  }
}
