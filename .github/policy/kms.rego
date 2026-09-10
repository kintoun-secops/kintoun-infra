# KMS 변경 자문. PR 라벨과 코멘트로 보고하며 병합은 차단하지 않는다.
package terraform.kms

import data.terraform.iam
import rego.v1

key_types := {"aws_kms_key", "aws_kms_external_key", "aws_kms_replica_key", "aws_kms_replica_external_key"}
policy_types := key_types | {"aws_kms_key_policy"}

changes contains rc if {
	some rc in input.resource_changes
	startswith(rc.type, "aws_kms_")
	not iam.only_noise(rc)
}

live contains rc if {
	some rc in changes
	is_object(rc.change.after)
}

# 지적이 없는 변경도 KMS PR 임을 알린다. alias·grant 와 no-op import 도 포함한다.
warn contains iam.finding_at("info", sprintf("KMS 변경: `%s` (%s)", [rc.address, concat(", ", rc.change.actions)]), "키를 사용하는 서비스와 기존 암호문에 미치는 영향을 함께 확인해 주세요.", rc) if {
	some rc in changes
}

deny contains iam.finding("high", "plan JSON 형식 버전을 해석할 수 없습니다", "이 정책은 1.x 형식만 해석합니다. 검사 결과를 신뢰하기 전에 규칙을 갱신해 주세요.") if {
	not startswith(object.get(input, "format_version", ""), "1.")
}

deny contains iam.finding_at("high", sprintf("KMS 키 삭제 또는 교체: `%s`", [rc.address]), "삭제 예약 중에는 키를 사용할 수 없습니다. 삭제 완료 후에는 키와 해당 키가 필요한 암호문을 복구할 수 없으므로 데이터 보존 기간과 복구 계획을 확인해 주세요.", rc) if {
	some rc in changes
	rc.type in key_types
	iam.acted(rc, "delete")
}

deny contains iam.finding_at("high", sprintf("KMS 키 비활성화: `%s`", [rc.address]), "이 키에 의존하는 암호화·복호화가 중단됩니다. 연결된 로그 수집과 데이터 접근에 미치는 영향을 확인해 주세요.", rc) if {
	some rc in live
	rc.type in key_types
	some field in {"is_enabled", "enabled"}
	rc.change.before[field] == true
	rc.change.after[field] == false
}

previously_enabled(rc, field) if rc.change.before[field] == true

warn contains iam.finding_at("warn", sprintf("비활성 KMS 키 설정: `%s`", [rc.address]), "이 상태에서는 키를 사용할 수 없습니다. 외부 키 재료 import 대기 등 의도된 설정인지 확인해 주세요.", rc) if {
	some rc in live
	rc.type in key_types
	some field in {"is_enabled", "enabled"}
	rc.change.after[field] == false
	not previously_enabled(rc, field)
}

deny contains iam.finding_at("high", sprintf("KMS 정책 잠금 방지 검사 우회: `%s`", [rc.address]), "정책을 다시 변경할 권한을 잃을 수 있습니다. bypass_policy_lockout_safety_check 를 켜야 하는 사유와 복구 주체를 확인해 주세요.", rc) if {
	some rc in live
	rc.type in policy_types
	rc.change.after.bypass_policy_lockout_safety_check == true
}

# AWS 생성 대칭 암호화 키만 자동 회전을 지원한다. 복제 키는 주 키의 설정을 따른다.
warn contains iam.finding_at("warn", sprintf("KMS 자동 회전 비활성: `%s`", [rc.address]), "자동 회전을 지원하는 키입니다. 로그 보존과 키 관리 기준에 맞춰 회전을 켤지 확인해 주세요.", rc) if {
	some rc in live
	rc.type == "aws_kms_key"
	rc.change.after.customer_master_key_spec == "SYMMETRIC_DEFAULT"
	rc.change.after.key_usage == "ENCRYPT_DECRYPT"
	object.get(rc.change.after, "custom_key_store_id", null) in {null, ""}
	rc.change.after.enable_key_rotation == false
}

warn contains iam.finding_at("warn", sprintf("KMS 삭제 대기 기간 단축: `%s`", [rc.address]), "삭제를 취소할 수 있는 시간이 줄어듭니다. 복구 절차에 필요한 기간을 확보했는지 확인해 주세요.", rc) if {
	some rc in live
	rc.type in key_types
	rc.change.after.deletion_window_in_days < rc.change.before.deletion_window_in_days
}

warn contains iam.finding_at("warn", sprintf("KMS 관리 설정 미확정: `%s`", [rc.address]), "활성화·자동 회전·정책 잠금 방지 설정 중 plan 시점에 확정되지 않은 값이 있습니다. 적용 전 최종 값을 확인해 주세요.", rc) if {
	some rc in live
	rc.type in policy_types
	some field in {"is_enabled", "enabled", "enable_key_rotation", "bypass_policy_lockout_safety_check"}
	rc.change.after_unknown[field] == true
}

valid_statements(value) if is_object(value)

valid_statements(value) if is_array(value)

policy_doc(rc) := doc if {
	doc := json.unmarshal(rc.change.after.policy)
	is_object(doc)
	valid_statements(doc.Statement)
}

warn contains iam.finding_at("warn", sprintf("KMS 키 정책 미확정 또는 해석 불가: `%s`", [rc.address]), "plan 에서 정책 본문을 확인할 수 없습니다. 기본 정책이나 별도 aws_kms_key_policy 를 포함해 실제 적용할 정책을 확인해 주세요.", rc) if {
	some rc in live
	rc.type in policy_types
	not policy_doc(rc)
}

statements contains {"rc": rc, "statement": statement} if {
	some rc in live
	rc.type in policy_types
	some statement in iam.as_array(policy_doc(rc).Statement)
	statement.Effect == "Allow"
}

wildcard_principal(statement) if statement.Principal == "*"

wildcard_principal(statement) if "*" in iam.as_array(statement.Principal.AWS)

has_conditions(statement) if {
	is_object(statement.Condition)
	count(statement.Condition) > 0
}

deny contains iam.finding_at("high", sprintf("조건 없는 전체 주체의 KMS 사용 허용: `%s`", [entry.rc.address]), "Principal 의 와일드카드가 모든 계정의 주체를 허용합니다. 계정·역할 범위를 제한해 주세요. 키 정책의 Resource 와일드카드는 이 검사 대상이 아닙니다.", entry.rc) if {
	some entry in statements
	wildcard_principal(entry.statement)
	not has_conditions(entry.statement)
}

warn contains iam.finding_at("warn", sprintf("조건부 전체 주체의 KMS 사용 허용: `%s`", [entry.rc.address]), "조건이 허용 계정·역할을 실제로 제한하는지 확인해 주세요. 조건이 있다는 사실만으로 안전하다고 판정하지 않습니다.", entry.rc) if {
	some entry in statements
	wildcard_principal(entry.statement)
	has_conditions(entry.statement)
}

service_principal(statement) if {
	count(iam.as_array(statement.Principal.Service)) > 0
}

source_account(statement) if {
	values := iam.as_array(statement.Condition.StringEquals["aws:SourceAccount"])
	count(values) > 0
	every value in values { regex.match(`^[0-9]{12}$`, value) }
}

source_arn(statement) if {
	some operator in {"StringEquals", "ArnEquals", "StringLike", "ArnLike"}
	values := iam.as_array(statement.Condition[operator]["aws:SourceArn"])
	count(values) > 0
	every value in values { regex.match(`^arn:[a-z-]+:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$`, value) }
}

source_scoped(statement) if {
	source_account(statement)
	source_arn(statement)
}

deny contains iam.finding_at("high", sprintf("AWS 서비스 주체의 KMS 사용 범위 제한 누락: `%s`", [entry.rc.address]), "aws:SourceAccount 와 호출 리소스의 aws:SourceArn 을 함께 제한해 주세요. 두 조건 없이는 다른 계정의 같은 서비스가 이 키를 사용할 수 있습니다. aws:SourceArn 을 지원하지 않는 서비스의 경우는 해당하지 않습니다.", entry.rc) if {
	some entry in statements
	service_principal(entry.statement)
	not source_scoped(entry.statement)
}

warn contains iam.finding_at("warn", sprintf("AWS 서비스에 KMS 전체 작업 허용: `%s`", [entry.rc.address]), "서비스 연동에 필요한 KMS 작업만 허용했는지 확인해 주세요. 계정의 관리 권한 위임과 서비스 사용 권한은 별도로 검토합니다.", entry.rc) if {
	some entry in statements
	entry.statement.Principal.Service
	some action in iam.as_array(entry.statement.Action)
	lower(action) in {"*", "kms:*"}
}
