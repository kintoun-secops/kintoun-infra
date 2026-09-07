# 최초 PR plan에는 network state가 아직 없다. 기존 state에서 확인한 ID로 import를 검증하고,
# network의 apply가 끝나 state가 생기면 remote_state.tf가 그 출력을 사용한다.
# 조회 오류나 기존 state의 출력 누락은 실패로 처리하며 대체 값으로 숨기지 않는다.
data "aws_s3_objects" "network_state" {
  bucket = "kintoun-tfstate"
  prefix = "platform/network/terraform.tfstate"
}

locals {
  network_state_exists = contains(data.aws_s3_objects.network_state.keys, "platform/network/terraform.tfstate")
  migration_network = {
    main_vpc_id       = "vpc-088a414494f775322"
    public_subnet_ids = ["subnet-0cac6e6e76e3bf8fb"]
  }
}
