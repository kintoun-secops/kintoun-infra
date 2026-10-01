terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "platform/attacker/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}