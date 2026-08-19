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
# Public Subnet 생성 for Wazuh
# =======================================================
resource "aws_subnet" "public_subnet" {
  count      = length(var.public_subnet_cidrs)
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

# =======================================================
# Public Route Table 생성 및 라우팅
# =======================================================
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.project_name}-public-route-table"
  }
}

resource "aws_route_table_association" "public_rt_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}