variable "region" {
  description = "리소스를 만들 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "db_host_override" {
  description = "SSM 포트 포워딩으로 붙을 때 쓸 주소. 생략하면 RDS 엔드포인트"
  type        = string
  default     = null
}

variable "db_port_override" {
  description = "SSM 포트 포워딩으로 붙을 때 쓸 포트. 생략하면 RDS 포트"
  type        = number
  default     = null
}
