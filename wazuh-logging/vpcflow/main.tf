# =======================================================
# VPC Flow Logs 생성
# =======================================================
resource "aws_flow_log" "victim_subnet" {
  subnet_id    = local.victim_subnet_id
  traffic_type = "ALL" # REJECT / ACCEPT / ALL 선택

  log_destination_type = "s3" # CloudWatch / S3 선택
  log_destination      = module.vpc_flow_logs_bucket.bucket_arn

  destination_options {
    file_format                = "plain-text"
    hive_compatible_partitions = false
    per_hour_partition         = true # 시간 단위로 경로를 나눔
  }

  log_format = join(" ", [
    # 기본 필드
    "$${version}",      # 로그 형식 버전(기본 형식 v2)
    "$${account-id}",   # ENI 소유 AWS 게정 ID
    "$${interface-id}", # 트래픽이 캡처된 ENI ID
    "$${srcaddr}",      # 출발지 IP
    "$${dstaddr}",      # 목적지 IP
    "$${srcport}",      # 출발지 PORT
    "$${dstport}",      # 목적지 PORT
    "$${protocol}",     # IANA 프로코톨 번호(TCP:6, UDP:16, ICMP:1)
    "$${packets}",      # 집계 구간 동안 전송된 패킷 수 
    "$${bytes}",        # 집계 구간 동안 전송된 바이트 수
    "$${start}",        # 트래픽 흐름 시작 시간(Unix Epoch, 초)
    "$${end}",          # 트래픽 흐름 종료 시간(Unix Epoch, 초)
    "$${action}",       # 보안 그룹/NACL 허용 여부(ACCEPT / REJECT)
    "$${log-status}",   # 로그 기록 상태
    # 커스텀 필드
    "$${pkt-srcaddr}",   # NAT or LB를 거치기 전의 원래 출발지 IP
    "$${pkt-dstaddr}",   # NAT or LB를 거지기 전의 원래 목적지 IP
    "$${flow-direction}" # 로그 캡처한 ENI 기준 Ingress / Egress 방향
  ])

  tags = {
    Name     = "${var.project_name}-flow-logs"
    SubnetId = "Victim Subnet"
    ManagedBy = "Terraform"
  }
}