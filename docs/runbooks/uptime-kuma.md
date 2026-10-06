# Uptime Kuma 접속 방법

## 권한 정책

`kintoun-secops-infra-ssm-port-forwarding` 정책이 연결된 그룹의 사용자가 접속할 수 있습니다.

## 접속 절차

1. `aws login`으로 임시 자격증명을 발급합니다.

    ```shell
    aws login --profile <본인 계정> --region ap-northeast-2
    ```

2. 포트포워딩 세션을 엽니다. 인스턴스 ID는 `platform/uptime-kuma`의 `uptime_kuma_instance_id` 출력에서 확인합니다.

    ```shell
    aws ssm start-session \
    --target <Uptime_Kuma_instance_id> \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["3001"],"localPortNumber":["3001"]}' \
    --region ap-northeast-2 \
    --profile <본인 계정>
    ```

3. 세션이 열린 상태에서 브라우저로 `http://localhost:3001`에 접속합니다.

!!! important "중요"
    최초 접속 시 관리자 계정 생성 화면이 표시됩니다. 배포 직후 팀이 정한 담당자가 먼저 관리자 계정을 생성해야 합니다.

## 설치 로그 확인

설치가 실패하면 관리자 자격증명으로 셸에 접속해 `/var/log/uptime-kuma-bootstrap.log`와 `systemctl status uptime-kuma`를 확인합니다.
