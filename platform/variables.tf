variable "aws_login_group_names" {
  description = "aws login 정책 연결용 그룹"
  type        = set(string)
  default = [
    "WHS4_Infra",
    "WHS4_Attack",
    "WHS4_SIEM_Detect"
  ]
}

variable "port_forwarding_group_names" {
  description = "포트 포워딩 정책 연결용 그룹"
  type        = set(string)
  default = [
    "WHS4_Infra",
    "WHS4_Attack",
    "WHS4_SIEM_Detect"
  ]
}

variable "project_name" {
  description = "tags 에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}
