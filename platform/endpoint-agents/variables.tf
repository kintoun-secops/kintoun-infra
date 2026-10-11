variable "association_schedule" {
  description = "State Manager 연결의 실행 주기"
  type        = string
  default     = "rate(30 minutes)"
}

variable "project_name" {
  description = "tags에 명시할 프로젝트 이름"
  type        = string
  default     = "kintoun-secops-infra"
}

variable "target_tag_key" {
  description = "설치 대상을 고르는 인스턴스 태그 키"
  type        = string
  default     = "EndpointAgents"
}

variable "target_tag_value" {
  description = "설치 대상을 고르는 인스턴스 태그 값"
  type        = string
  default     = "true"
}

variable "velociraptor_base_url" {
  description = "Velociraptor 릴리스 내려받기 주소"
  type        = string
  default     = "https://github.com/Velocidex/velociraptor/releases/download"
}

variable "velociraptor_version" {
  description = "설치할 Velociraptor 버전. 체크섬이 있는 버전만 쓸 수 있다"
  type        = string
  default     = "0.77.2"
}

variable "wazuh_agent_group" {
  description = "에이전트를 넣을 Wazuh 그룹"
  type        = string
  default     = "default"
}

variable "wazuh_agent_version" {
  description = "설치할 Wazuh 에이전트 버전. 체크섬이 있는 버전만 쓸 수 있다"
  type        = string
  default     = "4.14.8-1"
}

variable "wazuh_base_url" {
  description = "Wazuh 패키지 내려받기 주소"
  type        = string
  default     = "https://packages.wazuh.com/4.x"
}

variable "wazuh_manager" {
  description = "에이전트가 등록하고 로그를 보낼 Wazuh 매니저 주소"
  type        = string
  default     = "wazuh.internal.kintoun.work"
}
