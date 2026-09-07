# Wazuh 접속 및 복구

## Dashboard 접속

AWS CLI와 Session Manager plugin, 대상 인스턴스의 포트 포워딩 정책이 필요하다.
사용자 프로필은 MFA를 포함한 프로젝트 인증 절차에 따라 준비한다.
CLI 인증 방법은 [AWS login 안내](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)를 참고한다.

```bash
aws login --profile <본인-프로필>
aws ssm start-session \
  --target <wazuh-instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["443"],"localPortNumber":["56789"]}' \
  --region ap-northeast-2 \
  --profile <본인-프로필>
```

대상 ID는 권한이 있는 운영자가 `AWS_PROFILE=kintoun-admin terraform -chdir=platform/wazuh output -raw wazuh_instance_id`로
확인하거나 EC2 콘솔에서 확인한다. state 조회 권한이 없는 사용자는 운영자에게 ID를 받는다.

`Waiting for connections...`가 표시되면 브라우저에서 `https://localhost:56789`에 접속한다.
사용하는 동안 터널 세션을 유지하고 종료 후 `aws logout --profile <본인-프로필>`을 실행한다.

포트 포워딩 정책은 기본 팀 그룹에 연결된다. Shell 정책은 생성만 하므로
Shell 운영자는 별도의 정책 연결이 필요하다.

## 접속과 설치 장애

| 증상 | 확인할 항목 |
| --- | --- |
| `StartSession` 권한 거부 | 사용자 그룹, 권한 경계, MFA 세션, 대상 인스턴스·SSM 문서 권한 |
| SSM 대상 오프라인 | EC2 실행 상태, SSM Agent, 인스턴스 역할, outbound 443과 인터넷 경로 |
| 터널은 열리지만 Dashboard 접속 실패 | Wazuh 서비스 상태와 설치 완료 표식 |
| 최초 설치 실패 | `/var/log/wazuh-bootstrap.log`, 디스크 여유와 패키지 다운로드 경로 |

Shell 권한이 있는 운영자는 다음 항목을 확인한다.

```bash
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat --no-pager
sudo test -f /var/lib/wazuh-bootstrap/complete
sudo less /var/log/wazuh-bootstrap.log
```

설치 로그와 `/opt/wazuh-install`의 설치 산출물에는 초기 비밀번호가 포함될 수 있다.
문서·PR·CI 아티팩트에 복사하지 않는다. 스크립트는 완료 표식이 있으면 재설치를 건너뛰므로
재실행 전 현재 서비스와 데이터를 확인한다.

## EC2 교체와 EBS 복구

현재 코드는 중지 시 공인 IP 차이로 인한 교체를 방지하고 루트 EBS를 종료 후 보존한다.
EC2를 실제로 교체하면 새 루트 EBS가 만들어지며 이전 볼륨은 자동 재연결되지 않는다.

1. plan에서 교체 원인을 확인하고 대상 EC2·볼륨 ID와 보존할 데이터를 기록한다.
2. 기존 루트 볼륨의 스냅샷을 확보하고 복구 지점을 확인한다.
3. 스냅샷 기반 AMI로 복구하거나, 기존 볼륨을 복구용 인스턴스에 연결하여
   Wazuh 데이터와 설정을 복구한다.
4. Manager·Indexer·Dashboard·Filebeat, agent 연결과 SSM 접속을 검증한다.
5. 코드와 실제 자원이 일치하도록 검토한 뒤 plan을 확인한다.
6. 보존된 볼륨과 스냅샷의 유지 여부를 결정한다. 연결되지 않은 볼륨도 비용이 발생한다.

별도 데이터 EBS와 자동 재연결은 후속 구현 대상이다.
