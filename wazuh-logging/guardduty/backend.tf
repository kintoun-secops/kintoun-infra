# =======================================================
# platform/ 모듈이 apply된 이후에 apply 해야함
# =======================================================
terraform { # 테라폼이 지금 뭐가 만들어져 있는지를 기록해두는 파일 -> state 파일이다.
  backend "s3" {
    bucket       = "kintoun-tfstate"                           # 버킷 이름
    key          = "wazuh-logging/guardduty/terraform.tfstate" # 그 버킷 안에서 이 모듈만의 전용 경로
    region       = "ap-northeast-2"                            # 리전 이름
    use_lockfile = true                                        # 두 사람이 동시에 apply 못 하게 잠그는 기능
    encrypt      = true                                        # state 파일 자체를 암호화해서 저장
  }
}