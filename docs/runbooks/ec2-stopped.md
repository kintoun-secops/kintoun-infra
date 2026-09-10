# 중지한 EC2와 plan 변경

비용 절감을 위해 EC2를 중지해 두면 코드를 바꾸지 않아도 plan이 인스턴스 교체를 요구한다.
새 EC2를 추가하거나 이 증상을 발견했을 때의 기준을 정리한다.

## 증상과 원인

중지한 인스턴스는 자동 할당된 공인 IP가 회수된다. 프로바이더는 `associate_public_ip_address`를
`false`로 읽고, 코드의 `true`와 달라진다. 이 속성은 값이 바뀌면 교체를 강제한다.

```
~ associate_public_ip_address = false -> true # forces replacement
~ instance_state              = "stopped" -> (known after apply)
```

인스턴스 ARN이나 ID를 참조하는 IAM 정책과 대상 그룹 연결도 함께 변경으로 잡힌다.
이는 교체에 딸려온 결과이므로 별도의 변경이 아니다.

main의 apply는 `-auto-approve`다. 이 상태로 머지하면 인스턴스가 교체되고 그 안의 데이터는 사라진다.

## 조치

EC2 리소스의 `lifecycle.ignore_changes`에 해당 속성을 넣는다. AMI를 이미 무시하고 있다면 함께 나열한다.
최초 생성에는 `associate_public_ip_address = true`가 그대로 적용되며, 이후의 차이만 무시한다.

```hcl
lifecycle {
  ignore_changes = [
    ami,
    associate_public_ip_address,
  ]
}
```

인스턴스를 다시 시작해도 plan은 조용해지지만 중지할 때마다 같은 상태가 되므로 코드로 처리한다.

## 루트 EBS를 보존할지 판단하는 기준

`root_block_device`의 `delete_on_termination`은 EC2가 교체·삭제될 때 루트 볼륨을 남길지 정한다.
보존한 볼륨은 새 인스턴스에 자동으로 붙지 않으며 비용은 계속 발생한다.
스냅샷이나 AMI로 복구하거나 다른 인스턴스에 연결해야 한다.

| 값 | 선택하는 경우 | 적용 |
| --- | --- | --- |
| `false` (보존) | 인스턴스 안의 데이터가 유일본이고 복구 가치가 있다. 로그·탐지 결과·설정처럼 다시 만들 수 없는 상태를 담는다 | `platform/wazuh` |
| `true` (함께 삭제) | 공격 실습으로 오염될 수 있어 재생성이 오히려 낫다. user_data와 코드로 상태를 다시 만들 수 있다 | `platform/victim` |

판단이 서지 않으면 보존을 선택하고, 복구를 마친 뒤 남은 볼륨을 정리한다.
데이터를 계속 보존해야 하는 인스턴스는 루트 볼륨 대신 별도의 데이터 EBS로 분리하는 편이 안전하다.

## 새 EC2 루트를 추가할 때

1. `associate_public_ip_address`를 쓰면 `ignore_changes`에 함께 넣는다.
2. 위 표로 `delete_on_termination`을 정하고 그 이유를 코드 주석에 남긴다.
3. 모듈 문서에 어느 쪽을 선택했는지 한 줄로 적고 이 문서를 참조한다.

## 이미 교체가 계획된 상태를 발견했을 때

1. plan에서 `forces replacement`의 원인 속성을 확인한다. 위 증상과 다르면 실제 코드 변경일 수 있다.
2. 해당 루트를 건드리는 PR을 머지하지 않는다. 자동 apply가 교체를 실행한다.
3. 조치 PR을 먼저 머지한 뒤 plan이 변경 없음으로 나오는지 확인한다.
4. 인스턴스 안의 데이터가 필요하면 조치 전에 스냅샷을 만든다.
