data "aws_availability_zones" "available" {
  state = "available" # 사용 가능한 AZ 목록을 가져옴(2a, 2b, 2c, 2d)
}

# =======================================================
# VPC 생성
# =======================================================
resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr

  # 도메인 이름으로 통신하는 것을 허용해주는 설정
  enable_dns_support   = true # 도메인이름을 IP 주소로 바꿀 수 있게 해줌
  enable_dns_hostnames = true # Public IP가 할당된 EC2 인스턴스에 공인 DNS 호스트 이름이 부여

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# =======================================================
# Internet Gateway 생성
# =======================================================
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# =======================================================
# Subnet 생성 for CERT 인프라(Wazuh, Velociraptor)
# =======================================================
resource "aws_subnet" "cert_subnet" {
  count      = length(var.cert_subnet_cidrs)
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = var.cert_subnet_cidrs[count.index]

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.project_name}-cert-subnet-${count.index + 1}"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# Route Table 생성 및 라우팅
# =======================================================
resource "aws_route_table" "cert_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name      = "${var.project_name}-cert-route-table"
    ManagedBy = "Terraform"
  }
}

resource "aws_route" "cert_to_nat" {
  route_table_id         = aws_route_table.cert_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "cert_rt_association" {
  count          = length(var.cert_subnet_cidrs)
  subnet_id      = aws_subnet.cert_subnet[count.index].id
  route_table_id = aws_route_table.cert_route_table.id
}

# =======================================================
# NAT Gateway 구성 (Subnet 생성, 라우팅, NAT 생성)
# =======================================================
resource "aws_subnet" "nat_public_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.nat_subnet_cidr
  availability_zone = aws_subnet.cert_subnet[0].availability_zone

  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.project_name}-nat-public-subnet"
    Role      = "NAT-Public"
    ManagedBy = "Terraform"
  }
}

resource "aws_route_table" "nat_public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name      = "${var.project_name}-nat-public-route-table"
    Role      = "NAT-Public"
    ManagedBy = "Terraform"
  }
}

resource "aws_route" "nat_public_to_internet" {
  route_table_id         = aws_route_table.nat_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_igw.id
}

resource "aws_route_table_association" "nat_public" {
  subnet_id      = aws_subnet.nat_public_subnet.id
  route_table_id = aws_route_table.nat_public_rt.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name      = "${var.project_name}-nat-eip"
    ManagedBy = "Terraform"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id     = aws_eip.nat.allocation_id
  subnet_id         = aws_subnet.nat_public_subnet.id
  connectivity_type = "public"

  tags = {
    Name      = "${var.project_name}-nat-gateway"
    ManagedBy = "Terraform"
  }

  depends_on = [
    aws_route_table_association.nat_public
  ]
}