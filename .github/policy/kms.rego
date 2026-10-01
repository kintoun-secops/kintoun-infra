package terraform.kms

import data.terraform.iam
import rego.v1

key_types := {"aws_kms_key", "aws_kms_external_key", "aws_kms_replica_key", "aws_kms_replica_external_key"}

policy_types := key_types | {"aws_kms_key_policy"}

enabled_fields := {
	"aws_kms_key": "is_enabled",
	"aws_kms_external_key": "enabled",
	"aws_kms_replica_key": "enabled",
	"aws_kms_replica_external_key": "enabled",
}

changes contains rc if {
	some rc in input.resource_changes
	startswith(rc.type, "aws_kms_")
	not iam.only_noise(rc)
}

live contains rc if {
	some rc in changes
	is_object(rc.change.after)
}

warn contains iam.finding_at("info", sprintf("KMS 변경: `%s` (%s)", [rc.address, concat(", ", rc.change.actions)]), "키를 사용하는 서비스와 기존 암호문에 영향을 줄 수 있습니다.", rc) if {
	some rc in changes
}

deny contains iam.format_finding if not iam.format_supported

deny contains iam.finding_at("high", sprintf("KMS 키 삭제 또는 교체: `%s`", [rc.address]), "삭제 예약 중에는 키를 사용할 수 없고, 삭제가 끝나면 키와 그 키로 만든 암호문을 복구할 수 없습니다.", rc) if {
	some rc in changes
	rc.type in key_types
	iam.acted(rc, "delete")
}

deny contains iam.finding_at("high", sprintf("KMS 키 비활성화: `%s`", [rc.address]), "이 키를 쓰는 암호화와 복호화가 중단됩니다.", rc) if {
	some rc in live
	field := enabled_fields[rc.type]
	rc.change.before[field] == true
	rc.change.after[field] == false
}

previously_enabled(rc, field) if rc.change.before[field] == true

warn contains iam.finding_at("warn", sprintf("비활성 KMS 키 설정: `%s`", [rc.address]), "이 상태에서는 키를 사용할 수 없습니다. 외부 키 재료를 import 하기 전에는 이 설정이 정상입니다.", rc) if {
	some rc in live
	field := enabled_fields[rc.type]
	rc.change.after[field] == false
	not previously_enabled(rc, field)
}

deny contains iam.finding_at("high", sprintf("KMS 정책 잠금 방지 검사 우회: `%s`", [rc.address]), "정책을 다시 변경할 권한을 잃게 되는 정책도 적용됩니다.", rc) if {
	some rc in live
	rc.type in policy_types
	rc.change.after.bypass_policy_lockout_safety_check == true
}

warn contains iam.finding_at("warn", sprintf("KMS 자동 회전 비활성: `%s`", [rc.address]), "자동 회전을 지원하는 키인데 회전이 꺼져 있습니다.", rc) if {
	some rc in live
	rc.type == "aws_kms_key"
	rc.change.after.customer_master_key_spec == "SYMMETRIC_DEFAULT"
	rc.change.after.key_usage == "ENCRYPT_DECRYPT"
	object.get(rc.change.after, "custom_key_store_id", null) in {null, ""}
	rc.change.after.enable_key_rotation == false
}

warn contains iam.finding_at("warn", sprintf("KMS 삭제 대기 기간 단축: `%s`", [rc.address]), "삭제를 취소할 수 있는 기간이 줄어듭니다.", rc) if {
	some rc in live
	rc.type in key_types
	rc.change.after.deletion_window_in_days < rc.change.before.deletion_window_in_days
}

managed_fields(rc) := {"enable_key_rotation", "bypass_policy_lockout_safety_check", "deletion_window_in_days"} | {f | f := enabled_fields[rc.type]}

warn contains iam.finding_at("warn", sprintf("KMS 관리 설정 미확정: `%s`", [rc.address]), "활성 여부, 자동 회전, 잠금 방지 우회, 삭제 대기 기간 중 plan 시점에 확정되지 않은 값이 있습니다.", rc) if {
	some rc in live
	rc.type in policy_types
	some field in managed_fields(rc)
	iam.unknown_after_field(rc, field)
}

valid_statements(value) if is_object(value)

valid_statements(value) if is_array(value)

policy_doc(rc) := doc if {
	raw := rc.change.after.policy
	is_string(raw)
	doc := json.unmarshal(raw)
	is_object(doc)
	valid_statements(doc.Statement)
}

warn contains iam.finding_at("warn", sprintf("KMS 키 정책 미확정 또는 해석 불가: `%s`", [rc.address]), "plan 에서 정책 본문을 읽을 수 없습니다. 기본 정책이나 별도의 aws_kms_key_policy 가 적용될 수 있습니다.", rc) if {
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

deny contains iam.finding_at("high", sprintf("조건 없는 전체 주체의 KMS 사용 허용: `%s`", [entry.rc.address]), "Principal 의 와일드카드가 모든 계정의 주체를 허용합니다. 키 정책의 Resource 와일드카드는 이 검사 대상이 아닙니다.", entry.rc) if {
	some entry in statements
	wildcard_principal(entry.statement)
	not has_conditions(entry.statement)
}

warn contains iam.finding_at("warn", sprintf("조건부 전체 주체의 KMS 사용 허용: `%s`", [entry.rc.address]), "조건이 허용 범위를 어디까지 제한하는지는 이 검사가 판정하지 않습니다.", entry.rc) if {
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

deny contains iam.finding_at("high", sprintf("AWS 서비스 주체의 KMS 사용 범위 제한 누락: `%s`", [entry.rc.address]), "aws:SourceAccount 와 aws:SourceArn 조건이 함께 없으면 다른 계정의 같은 서비스가 이 키를 사용할 수 있습니다. aws:SourceArn 을 지원하지 않는 서비스에는 해당하지 않습니다.", entry.rc) if {
	some entry in statements
	service_principal(entry.statement)
	not source_scoped(entry.statement)
}

warn contains iam.finding_at("warn", sprintf("AWS 서비스에 KMS 전체 작업 허용: `%s`", [entry.rc.address]), "서비스 주체에 KMS 의 모든 작업을 허용합니다. 계정 루트에 대한 관리 권한 위임은 이 검사 대상이 아닙니다.", entry.rc) if {
	some entry in statements
	entry.statement.Principal.Service
	some action in iam.as_array(entry.statement.Action)
	lower(action) in {"*", "kms:*"}
}
