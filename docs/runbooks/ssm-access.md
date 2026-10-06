# SSM 접속 권한

팀원의 SSM 포트포워딩과 셸 접속은 인스턴스 태그로 대상을 정합니다.
정책은 [`identity/ssm_access.tf`](https://github.com/kintoun-secops/kintoun-infra/blob/main/identity/ssm_access.tf) 에 있습니다.

## 태그와 정책

| 태그 | 정책 | 연결 그룹 | 세션 문서 |
| --- | --- | --- | --- |
| `SSMPortForward = "true"` | `kintoun-secops-infra-ssm-port-forwarding` | `WHS4_Attack`, `WHS4_Infra`, `WHS4_SIEM_Detect` | `AWS-StartPortForwardingSession` |
| `SSMShell = "attack"` | `kintoun-secops-infra-ssm-shell-attack` | `WHS4_Attack` | `SSM-SessionManagerRunShell` |
| `SSMShell = "siem"` | `kintoun-secops-infra-ssm-shell-siem` | `WHS4_SIEM_Detect` | `SSM-SessionManagerRunShell` |

현재 태그가 붙은 인스턴스는 다음과 같습니다.

| 인스턴스 | 루트 | `SSMPortForward` | `SSMShell` |
| --- | --- | --- | --- |
| Wazuh | `platform/wazuh` | `true` | 없음 |
| Kali | `platform/attacker` | `true` | `attack` |
| Velociraptor | `platform/velociraptor` | `true` | `siem` |

## 접속 대상 조회

포트포워딩할 수 있는 인스턴스와 ID 를 조회합니다.

```shell
aws ec2 describe-instances \
--filters "Name=tag:SSMPortForward,Values=true" "Name=instance-state-name,Values=running" \
--query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value, InstanceId]" \
--output table \
--region ap-northeast-2 \
--profile <본인 계정>
```

셸 접속 대상은 필터를 `Name=tag:SSMShell,Values=<attack 또는 siem>` 으로 바꿔 조회합니다.

## 새 인스턴스에 접속 열기

1. 인스턴스의 `tags` 에 태그를 추가합니다. 전용 SSM 사용자 정책은 만들지 않습니다.

    ```hcl
    tags = {
      Name           = "${var.project_name}-example-ec2"
      SSMPortForward = "true"
      SSMShell       = "siem"
    }
    ```

2. 인스턴스 역할에 `platform/wazuh` 의 `ssm_policy_arn` 을 연결해 SSM 에 등록되게 합니다.
3. PR 을 올리고 main 에 머지합니다. `groups.yaml` 은 변경하지 않습니다.

!!! note "참고"
    새 팀 단위의 셸 권한이 필요하면 `identity/ssm_access.tf` 의 `ssm_shell_teams` 에 값을 추가하고,
    생성되는 `kintoun-secops-infra-ssm-shell-<값>` 정책을 `groups.yaml` 의 해당 그룹에 연결합니다.

## 태그 변경 제한

`kintoun-secops-infra-ssm-tag-guard` 는 `members.yaml` 의 모든 사용자에게 직접 연결됩니다.
`SSMPortForward` 와 `SSMShell` 태그 키에 대한 `ec2:CreateTags` 와 `ec2:DeleteTags` 를 거부하므로
팀원은 콘솔이나 CLI 에서 이 태그를 붙이거나 지울 수 없습니다. 태그는 Terraform 코드로만 변경합니다.

!!! warning "경고"
    태그가 접속 권한을 결정합니다. 태그 가드를 사용자에게서 분리하면 EC2 태그 권한이 있는 사용자가
    임의의 인스턴스에 셸 권한을 얻을 수 있습니다.

## 기존 인스턴스별 정책

`wazuh-ssm-port-forwarding`, `kali-ssm-port-forwarding`, `kali-shell-access`,
`velociraptor-ssm-port-forwarding`, `velociraptor-shell-access` 정책은 태그 기반 정책으로 접속을 확인할 때까지 유지합니다.
확인 후 `groups.yaml` 에서 연결을 먼저 해제하고, 다음 PR 에서 각 루트의 정책을 삭제합니다.
