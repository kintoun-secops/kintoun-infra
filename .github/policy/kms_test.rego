package terraform.kms

import rego.v1

plan(changes) := {"format_version": "1.2", "resource_changes": changes}
resource(kind, actions, before, after) := {
	"address": sprintf("module.logs.%s.test", [kind]), "type": kind,
	"change": {"actions": actions, "before": before, "after": after},
}

with_unknown(rc, unknown) := object.union(rc, {"change": object.union(rc.change, {"after_unknown": unknown})})
root_statement := {"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::123456789012:root"}, "Action": "kms:*", "Resource": "*"}
good := {
	"is_enabled": true, "enable_key_rotation": true,
	"customer_master_key_spec": "SYMMETRIC_DEFAULT", "key_usage": "ENCRYPT_DECRYPT",
	"policy": json.marshal({"Statement": [root_statement]}),
	"deletion_window_in_days": 30, "bypass_policy_lockout_safety_check": false,
}

policy(statement) := resource("aws_kms_key_policy", ["update"], {}, {"policy": json.marshal({"Statement": statement})})
hits(rules, needle) := count([f | some f in rules; contains(f.msg, needle)])

test_good_key_has_change_info_only if {
	p := plan([resource("aws_kms_key", ["create"], null, good)])
	count(deny) == 0 with input as p
	w := warn with input as p
	count(w) == 1
	every f in w { f.level == "info" }
}

test_key_delete_and_replace_are_high if {
	every kind in key_types {
		every actions in [["delete"], ["delete", "create"]] {
			r := deny with input as plan([resource(kind, actions, good, null)])
			hits(r, "키 삭제 또는 교체") == 1
		}
	}
}

test_alias_and_grant_are_tracked_without_key_deletion_warning if {
	every kind in ["aws_kms_alias", "aws_kms_grant"] {
		p := plan([resource(kind, ["delete"], {}, null)])
		count(deny) == 0 with input as p
		w := warn with input as p
		hits(w, "KMS 변경") == 1
	}
}

# 활성 여부 필드는 키 종류마다 이름이 다르다. 매핑에 없는 조합은 읽지 않는다.
test_disable_follows_enabled_field_mapping if {
	every kind, field in enabled_fields {
		r := deny with input as plan([resource(kind, ["update"], {field: true}, {field: false})])
		hits(r, "비활성화") == 1
	}
	stray := resource("aws_kms_key", ["update"], {"enabled": true}, {"enabled": false})
	hits(deny, "비활성화") == 0 with input as plan([stray])
}

test_lockout_bypass_is_high if {
	r := deny with input as plan([resource("aws_kms_key_policy", ["update"], {}, {"bypass_policy_lockout_safety_check": true})])
	hits(r, "잠금 방지") == 1
}

test_disabled_creation_is_a_review_note if {
	every kind, field in enabled_fields {
		p := plan([resource(kind, ["create"], null, {field: false})])
		count(deny) == 0 with input as p
		w := warn with input as p
		hits(w, "비활성 KMS 키 설정") == 1
	}
}

test_rotation_only_for_supported_primary_keys if {
	after := object.union(good, {"enable_key_rotation": false})
	w := warn with input as plan([resource("aws_kms_key", ["create"], null, after)])
	hits(w, "자동 회전") == 1
	every kind in ["aws_kms_external_key", "aws_kms_replica_key", "aws_kms_replica_external_key"] {
		r := warn with input as plan([resource(kind, ["create"], null, after)])
		hits(r, "자동 회전") == 0
	}
	every override in [{"customer_master_key_spec": "RSA_2048"}, {"key_usage": "GENERATE_VERIFY_MAC"}, {"custom_key_store_id": "store"}] {
		r := warn with input as plan([resource("aws_kms_key", ["create"], null, object.union(after, override))])
		hits(r, "자동 회전") == 0
	}
}

test_shorter_deletion_window_warned if {
	w := warn with input as plan([resource("aws_kms_key", ["update"], good, object.union(good, {"deletion_window_in_days": 7}))])
	hits(w, "대기 기간 단축") == 1
}

# null 과 미확정(after 에서 빠짐)은 둘 다 문자열이 아니다.
test_unknown_or_unreadable_policy_is_reported if {
	every after in [{"policy": null}, {"policy": "not json"}, {"policy": "{}"}, {}] {
		w := warn with input as plan([resource("aws_kms_key_policy", ["create"], null, after)])
		hits(w, "정책 미확정") == 1
	}
}

# 규칙이 읽는 관리 설정이 미확정이면 종류별 활성 필드를 포함해 모두 보고한다. 전체 미확정도 같다.
test_unknown_settings_are_reported_per_field if {
	every kind in policy_types {
		rc := resource(kind, ["create"], null, {})
		every field in managed_fields(rc) {
			w := warn with input as plan([with_unknown(rc, {field: true})])
			hits(w, "관리 설정 미확정") == 1
		}
		hits(warn, "관리 설정 미확정") == 1 with input as plan([with_unknown(rc, true)])
		hits(warn, "관리 설정 미확정") == 0 with input as plan([with_unknown(rc, {"arn": true})])
	}
}

test_wildcard_principals_string_array_and_condition if {
	every principal in ["*", {"AWS": "*"}, {"AWS": ["*"]}] {
		s := object.union(root_statement, {"Principal": principal})
		r := deny with input as plan([policy([s])])
		hits(r, "조건 없는 전체 주체") == 1
		limited := object.union(s, {"Condition": {"StringEquals": {"aws:PrincipalAccount": "123456789012"}}})
		count(deny) == 0 with input as plan([policy(limited)])
		w := warn with input as plan([policy(limited)])
		hits(w, "조건부 전체 주체") == 1
	}
}

test_service_principal_requires_both_positive_conditions if {
	s := object.union(root_statement, {"Principal": {"Service": "guardduty.amazonaws.com"}, "Action": "kms:GenerateDataKey"})
	arn := "arn:aws:guardduty:ap-northeast-2:123456789012:detector/abc"
	condition := {"StringEquals": {"aws:SourceAccount": "123456789012", "aws:SourceArn": arn}}
	count(deny) == 0 with input as plan([policy(object.union(s, {"Condition": condition}))])
	every missing in [
		{}, {"StringEquals": {"aws:SourceAccount": "123456789012"}}, {"StringEquals": {"aws:SourceArn": arn}},
		{"StringEquals": {"aws:SourceAccount": "*", "aws:SourceArn": arn}},
		{"StringEquals": {"aws:SourceAccount": "123456789012", "aws:SourceArn": "*"}},
		{"StringEquals": {"aws:SourceAccount": "123456789012", "aws:SourceArn": "arn:aws:guardduty:*:*:detector/abc"}},
		{"StringNotEquals": {"aws:SourceAccount": "123456789012", "aws:SourceArn": arn}},
	] {
		r := deny with input as plan([policy(object.union(s, {"Condition": missing}))])
		hits(r, "서비스 주체") == 1
	}
	logs := object.union(s, {"Principal": {"Service": ["logs.ap-northeast-2.amazonaws.com"]}})
	r := deny with input as plan([policy(logs)])
	hits(r, "서비스 주체") == 1
	logs_arn := "arn:aws:logs:ap-northeast-2:123456789012:log-group:*"
	scoped := object.union(logs, {"Condition": {"StringEquals": {"aws:SourceAccount": "123456789012"}, "ArnLike": {"aws:SourceArn": logs_arn}}})
	count(deny) == 0 with input as plan([policy(scoped)])
	count(deny) == 0 with input as plan([policy(root_statement)])
}

test_account_root_kms_star_is_not_a_service_permission if {
	w := warn with input as plan([policy(root_statement)])
	hits(w, "전체 작업") == 0
	s := object.union(root_statement, {"Principal": {"Service": "logs.ap-northeast-2.amazonaws.com"}})
	r := warn with input as plan([policy(s)])
	hits(r, "전체 작업") == 1
}

test_noop_import_is_tracked_but_noop_read_and_non_kms_are_not if {
	rc := resource("aws_kms_key", ["no-op"], good, good)
	imported := object.union(rc, {"change": object.union(rc.change, {"importing": {"id": "key"}})})
	w := warn with input as plan([imported])
	hits(w, "KMS 변경") == 1
	every r in [rc, resource("aws_kms_alias", ["read"], {}, {}), resource("aws_s3_bucket", ["create"], null, {})] {
		count(warn) == 0 with input as plan([r])
		count(deny) == 0 with input as plan([r])
	}
}

test_format_version_is_checked if {
	every doc in [{"resource_changes": []}, {"format_version": "2.0", "resource_changes": []}] {
		r := deny with input as doc
		count(r) == 1
		hits(r, "형식 버전") == 1
	}
	count(deny) == 0 with input as {"format_version": "1.9", "resource_changes": []}
}
