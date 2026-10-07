terraform {
  backend "s3" {
    bucket       = "kintoun-tfstate"
    key          = "wazuh-logging/alb-log/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}