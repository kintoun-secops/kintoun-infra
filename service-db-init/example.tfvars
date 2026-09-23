# 사용법: 다른 터미널에서 백엔드를 거치는 터널을 연 뒤
#   terraform plan  -var-file=example.tfvars
#   terraform apply -var-file=example.tfvars

db_host_override = "127.0.0.1"
db_port_override = 15432
