# terraform plan JSON 에 대한 IAM 정책. `conftest test plan.json -p .github/policy`
# 규칙은 AWS 리소스 타입과 plan 액션에만 건다 — 변수명·파일 구조를 파싱하지 않는다.
# 차단하지 않는다. deny 는 리뷰어에게 보이는 신호이고 판단은 사람이 한다.
package terraform.iam

import rego.v1

critical_policy := `:policy/(.*Administrator|.*PowerUser|IAMFullAccess)`

broad_policy := `:policy/.*FullAccess`

attachment_types := {
	"aws_iam_user_policy_attachment",
	"aws_iam_group_policy_attachment",
	"aws_iam_role_policy_attachment",
	"aws_iam_policy_attachment",
}

# ---- 공통 ---------------------------------------------------------------

finding(level, text, why) := {"level": level, "msg": text, "why": why}

# import 는 no-op 으로도 나타나므로 걸러내지 않는다.
changes contains rc if {
	some rc in input.resource_changes
	startswith(rc.type, "aws_iam_")
	not only_noise(rc)
}

only_noise(rc) if {
	not rc.change.importing
	every a in rc.change.actions {
		a in {"no-op", "read"}
	}
}

acted(rc, a) if a in rc.change.actions

is_replace(rc) if {
	acted(rc, "delete")
	acted(rc, "create")
}

# null 은 정의된 값이라 `not` 에 안 걸린다 — 문자열일 때만 정의되게 눕힌다.
boundary(rc, which) := b if {
	b := rc.change[which].permissions_boundary
	is_string(b)
}

# 모르는 메이저 버전이면 규칙이 조용히 빗나가는 대신 여기서 멈춘다 (공식 문서 지시).
deny contains finding("high", "plan JSON 형식 버전을 해석할 수 없습니다", sprintf("format_version=%v — 이 정책은 1.x 만 해석합니다. 갱신 전까지 검사 결과를 신뢰하지 마십시오.", [object.get(input, "format_version", "(없음)")])) if {
	not startswith(object.get(input, "format_version", ""), "1.")
}

# ---- 파괴적 변경 --------------------------------------------------------

deny contains finding("high", sprintf("사용자 삭제 — `%s`", [rc.address]), "되돌려도 비밀번호·액세스 키·MFA 디바이스는 복원되지 않습니다.") if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "delete")
	not is_replace(rc)
}

deny contains finding("high", sprintf("IAM 개체 삭제 — `%s`", [rc.address]), "이 개체로 부여하던 권한이나 제약이 사라집니다. MFA·경계 관련이면 보안 완화입니다.") if {
	some rc in changes
	rc.type != "aws_iam_user"
	acted(rc, "delete")
	not is_replace(rc)
}

deny contains finding("high", sprintf("IAM 개체 재생성%s — `%s`", [import_tag(rc), rc.address]), "제자리 수정이 아니라 삭제 후 재생성입니다. import 중이라면 코드가 실제 자원과 달라 운영 중인 자원을 지우는 계획입니다.") if {
	some rc in changes
	is_replace(rc)
}

import_tag(rc) := " [import]" if rc.change.importing

import_tag(rc) := "" if not rc.change.importing

# ---- 권한 경계 ----------------------------------------------------------

deny contains finding("high", sprintf("권한 경계 없는 사용자 생성 — `%s`", [rc.address]), "경계가 없으면 그룹 정책이 그대로 유효 권한이 됩니다.") if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not boundary(rc, "after")
}

# 경계는 제자리 갱신 대상이라 create 만 보면 변수를 비우는 조용한 update 를 놓친다.
deny contains finding("high", boundary_text(rc), "경계가 사라지거나 넓어지면 그룹 정책이 그대로 유효 권한이 됩니다.") if {
	some rc in changes
	rc.type == "aws_iam_user"
	not acted(rc, "delete")
	boundary_changed(rc)
}

boundary_changed(rc) if {
	boundary(rc, "before")
	not boundary(rc, "after")
}

boundary_changed(rc) if boundary(rc, "before") != boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 교체 (`%s` → `%s`) — `%s`", [boundary(rc, "before"), boundary(rc, "after"), rc.address]) if boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 제거 — `%s`", [rc.address]) if not boundary(rc, "after")

# ---- 권한 부여 ----------------------------------------------------------

deny contains finding("high", sprintf("특권 정책 연결 — `%s` → `%s`", [rc.change.after.policy_arn, rc.address]), "관리자·IAM 전체 권한입니다. 이 연결이 의도된 것인지 본문에 사유를 남기십시오.") if {
	some rc in changes
	rc.type in attachment_types
	acted(rc, "create")
	regex.match(critical_policy, rc.change.after.policy_arn)
}

warn contains finding("warn", sprintf("광범위한 정책 연결 — `%s` → `%s`", [rc.change.after.policy_arn, rc.address]), "해당 서비스 전체 권한입니다. 더 좁은 정책으로 대체할 수 있는지 확인하십시오.") if {
	some rc in changes
	rc.type in attachment_types
	acted(rc, "create")
	not regex.match(critical_policy, rc.change.after.policy_arn)
	regex.match(broad_policy, rc.change.after.policy_arn)
}

deny contains finding("high", sprintf("모든 작업을 허용하는 정책 — `%s`", [rc.address]), "`Action: \"*\"` 와 `Resource: \"*\"` 를 동시에 허용합니다.") if {
	some rc in changes
	not acted(rc, "delete")
	star_policy(rc.change.after.policy)
}

star_policy(doc) if {
	parsed := json.unmarshal(doc)
	some s in as_array(parsed.Statement)
	s.Effect == "Allow"
	"*" in as_array(s.Action)
	"*" in as_array(s.Resource)
}

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

# ---- 정보 ---------------------------------------------------------------

warn contains finding("warn", sprintf("그룹 소속 변경 — `%s` → %s", [rc.address, concat(", ", as_array(rc.change.after.groups))]), "그룹을 통해 부여되는 권한이 바뀝니다.") if {
	some rc in changes
	rc.type == "aws_iam_user_group_membership"
	not acted(rc, "delete")
}

warn contains finding("warn", sprintf("사용자 생성 — `%s`", [rc.address]), "적용 후 콘솔 액세스 활성화와 MFA 등록이 필요합니다.") if {
	some rc in changes
	rc.type == "aws_iam_user"
	acted(rc, "create")
	not is_replace(rc)
}

warn contains finding("warn", sprintf("그룹 생성 — `%s`", [rc.address]), "새 권한 부여 지점입니다. 연결되는 정책과 소속 인원을 함께 확인하십시오.") if {
	some rc in changes
	rc.type == "aws_iam_group"
	acted(rc, "create")
}

warn contains finding("warn", sprintf("코드로 들여옴 (import) — `%s`", [rc.address]), "id 가 의도한 실제 자원인지 확인하십시오. 잘못된 id 는 다른 자원을 이 주소에 묶습니다.") if {
	some rc in changes
	rc.change.importing
	not is_replace(rc)
}
