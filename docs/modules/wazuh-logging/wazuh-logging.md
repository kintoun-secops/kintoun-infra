# Wazuh 에서 AWS 서비스 로그(CloudTrail, VPC Flow, ALB Access Log)수집
Wazuh Manager가 AWS Native 로그 수집을 위한 정책을 정리한 모듈
</br>Wazuh Manager가 S3 버킷에 저장되는 AWS Native로그를 읽기 위한 선행 과정
</br>실제로 Wazuh Manager가 S3 버킷에 있는 AWS 로그를 가져오는 것은 Wazuh Manger Shell에서 수동으로 진행

## Wazuh Manger에서 aws-s3 모듈 연동(S3 버킷에 있는 AWS Native Logs를 수집하는 방법)
✅ AWS Login 선행 필요(임시 자격증명으로 aws cli에서 진행)
- Wazuh SIEM EC2 관리자가 SSM 서비스를 통해 Shell에 접근
```shell
aws ssm start-session \
--target <Wazuh_Instance_ID>
```
- Wazuh Manager의 ossec.conf 원본 파일 백업
```shell
sudo cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.backup
```
- Wazuh Manager ossec.conf 파일에서 aws s3 모듈 활성화 (aws-s3 모듈 설정 항목별 의미 - [Wazuh 공식문서](https://documentation.wazuh.com/current/user-manual/reference/ossec-conf/wodle-s3.html))
```shell
sudo vi /var/ossec/etc/ossec.conf
```
```XML
<!-- aws-s3 모듈 활성화 -->
<ossec_config>
	<wodle name="aws-s3">
		<disabled>no</disabled>
		<interval>10m</interval>
		<run_on_start>yes</run_on_start>
		<bucket type=수집 대상 이벤트>
			<name>Bucket Name</name>
			<remove_from_bucket>no</remove_from_bucket>
		</bucket>
	</wodle>
</ossec_config>
```

- ossec.conf 파일 수정 완료 후, 데몬 재시작
```shell
sudo systemctl restart wazuh-manager
```


## CloudTrail Logging
팀 근두운 계정에 기존 생성되어 있는 CloudTrail 추적과 연동된 S3 Bucket 사용
</br>"whs4-kintoun-cloudtrail-logs" S3 Bucket에 대한 권한 정책 생성 및 Wazuh에 Profile된 IAM Role(`kintoun-secops-infra-wazuh-role`)에 Attach
```text
# 허용 Actions
- s3:ListBucket - CloudTrail 로그가 저장되는 S3 버킷 조회
- s3:GetObject - CloudTrail 로그가 저장되는 S3 버킷 내 객체를 가져옴
```
Wazuh EC2 Instance만 해당 Actions을 허용

🖥️ Wazuh Manager의 ossec.conf 파일 내 모듈 활성화
```XML
<!-- CloudTrail 로그 수집 모듈 활성화 -->
<ossec_config>
	<wodle name="aws-s3">
		<disabled>no</disabled>
		<interval>5m</interval>
		<run_on_start>yes</run_on_start>
		<skip_on_error>yes</skip_on_error>
		<bucket type="cloudtrail">
			<name>Bucket Name</name>
			<remove_from_bucket>no</remove_from_bucket>
		</bucket>
	</wodle>
</ossec_config>
```

## VPC Flow Logging
Service-APP, Service-DB가 위치한 Subnet의 VPC Flow 로그만 생성하여, S3 Bucket에 원본 저장
</br>"whs4-kintoun-vpcflow-logs" S3 Bucket 생성
</br>위 버킷에 대한 권한 정책 생성 및 Wazuh Manager가 VPC Flow Logs를 가져오기 위한 권한 정책도 추가, Wazuh에 Profile된 IAM Role(`kintoun-secops-infra-wazuh-role`)에 Attach
```text
# 허용 Actions
- s3:ListBucket - VPC Flow 로그가 저장되는 S3 버킷 조회
- s3:GetObject - VPC Flow 로그가 저장되는 S3 버킷 내 객체를 가져옴
- ec2:DescribeFlowLogs - VPC Flow Logs 설정 목록과 상태를 조회하는 권한
- kms:Decrypt - KMS 키로 암호화 된 S3 버킷내 데이터를 복호화하는 권한
```
Wazuh EC2 Instance만 해당 Actions을 허용

🖥️ Wazuh Manager의 ossec.conf 파일 내 모듈 활성화
```XML
<!-- VPC Flow 로그 수집 모듈 활성화 -->
<ossec_config>
	<wodle name="aws-s3">
		<disabled>no</disabled>
		<interval>5m</interval>
		<run_on_start>yes</run_on_start>
		<skip_on_error>yes</skip_on_error>
		<bucket type="vpcflow">
			<name>Bucket Name</name>
			<remove_from_bucket>no</remove_from_bucket>
		</bucket>
	</wodle>
</ossec_config>
```

#### CloudWatch로 전송
vpc-flow-logs가 Cloudwatch에 로그스트림을 생성하고 로그를 보관할 수 있도록 IAM Role 및 권한 정책 생성
```text
- logs:DescribeLogGroups - CloudWatch의 로그 그룹 목록과 설정을 조회
- logs:DescribeLogStreams - 특정 로그 그룹 안의 로그 스트림 목록을 조회
- logs:CreateLogGroup - CloudWatch에 새 로그 그룹을 만드는 권한
- logs:CreateLogStream - 로그 그룹 안에 새 로그 스트림을 만드는 권한
- logs:PutLogEvents - 로그 스트림에 실제 로그 기록을 보내는 권한
```

## ALB Access Logging
service-app 모듈에서 생성한 ALB에 대한 Access log를 S3 Bucket에 저장
<br/>"whs4-kintoun-alb-logs" S3 Bucket이 ALB 로그를 가져와 저장할 수 있도록 권한 정책 생성 및 버킷에 연결
<br/>Wazuh Manager가 위 버킷에서 ALB Access Logs를 가져오기 위한 권한 정책도 추가, Wazuh에 Profile된 IAM Role(`kintoun-secops-infra-wazuh-role`)에 Attach
```text
# 버킷 허용 Actions
- s3:PutObject - ALB 로그가 S3 버킷에 로그를 저장
# Wazuh EC2 허용 Actions
- s3:ListBucket - ALB 로그가 저장되는 S3 버킷 조회
- s3:GetObject - ALB 로그가 저장되는 S3 버킷 내 객체를 가져옴
```

🖥️ Wazuh Manager의 ossec.conf 파일 내 모듈 활성화
```XML
<!-- ALB Access 로그 수집 모듈 활성화 -->
<ossec_config>
	<wodle name="aws-s3">
		<disabled>no</disabled>
		<interval>5m</interval>
		<run_on_start>yes</run_on_start>
		<skip_on_error>yes</skip_on_error>
		<bucket type="alb">
			<name>Bucket Name</name>
			<remove_from_bucket>no</remove_from_bucket>
		</bucket>
	</wodle>
</ossec_config>
```

