# Wazuh 에서 AWS Native 로그(CloudTrail, VPC Flow, WAF, GuardDuty) 수집
Wazuh Manager가 AWS Native 로그 수집을 위한 정책을 정리한 모듈

## CloudTrail Logging
팀 근두운 계정에 기존 생성되어 있는 CloudTrail 추적과 연동된 S3 Bucket 사용
</br>"whs4-kintoun-cloudtrail-logs" S3 Bucket에 대한 권한 정책 생성 및 Wazuh에 Profile된 IAM Role(`kintoun-secops-infra-wazuh-role`)에 Attach
```text
# 허용 Actions
- s3:ListBucket - CloudTrail 로그가 저장되는 S3 버킷 조회
- s3:GetObject - CloudTrail 로그가 저장되는 S3 버킷 내 객체를 가져옴
```
Wazuh EC2 Instance만 해당 Actions을 허용

## VPC Flow Logging
Victim EC2 Instance가 위치한 Subnet의 VPC Flow 로그만 생성하여, S3 Bucket에 원본 저장
</br>"whs4-kintoun-vpcflow-logs" S3 Bucket 생성
</br>위 버킷에 대한 권한 정책 생성 및 Wazuh Manager가 VPC Flow Logs를 가져오기 위한 권한 정책도 추가, Wazuh에 Profile된 IAM Role(`kintoun-secops-infra-wazuh-role`)에 Attach
```text
# 허용 Actions
- s3:ListBucket - VPC Flow 로그가 저장되는 S3 버킷 조회
- s3:GetObject - VPC Flow 로그가 저장되는 S3 버키 내 객체를 가져옴
- ec2:DescribeFlowLogs - VPC Flow Logs 설정 목록과 상태를 조회하는 권한
```
Wazuh EC2 Instance만 해당 Actions을 허용

## WAF Logging

## GuardDuty Logging
GuardDuty 활성화 하고 KMS 키를 생성 한 뒤 S3 bucket에 로그 저장
</br> KMS 키 생성
</br>"whs4-kintoun-guardduty-findings" S3 Bucket 생성
</br> 위 버킷에 대한 권한 정책 생성 및 Wazuh Manager가 GuardDuty가 로그를 저장한 S3 버킷에서 로그를 복호화하고 조회하고 가져오기위한 정책 설정
#허용 Actions 
- 계정(root) : KMS:* -> 키가 아무도 못 건드리는 상태로 잠기지 않게, 계정 차원의 관리 권한 위임
- GuardDuty : KMS:GenerateDataKey -> findings 파일을 암호화할 임시 데이터 키 발급받기
- GuardDuty : s3:PutObject -> findings 파일을 버킷에 새로 업로드하기
- GuardDuty : s3:GetBucketLocation -> 목적지 버킷이 어느 리전에 있는지 확인하기
- wazuh_role : KMS:Decrypt -> 암호화된 findings 파일 내용을 복호화해서 읽을 수 있게 한다.
- wazuh_role : s3:ListBucket -> 버킷 안에 어떤 findings 파일들이 쌓였는지 목록 조회하기
- wazuh_role : s3:GetObject -> 실제 findings 파일 내용을 다운로드
