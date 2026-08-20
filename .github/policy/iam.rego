# terraform plan JSON 에 대한 IAM 정책. `conftest test plan.json -p .github/policy`
#
# 규칙은 AWS 리소스 타입과 plan 액션에만 걸린다. 우리 변수명이나 파일 구조를
# 파싱하지 않으므로 리팩터링에도, 새 IAM 리소스 타입에도 살아남는다.
# 차단하지 않는다 — deny 는 리뷰어에게 보이는 신호이고 판단은 사람이 한다.
package terraform.iam

import rego.v1

# 특정 ARN 열거가 아니라 패턴이라 새 관리형 정책이 나와도 걸린다.
critical_policy := `:policy/(.*Administrator|.*PowerUser|IAMFullAccess)`

broad_policy := `:policy/.*FullAccess`

attachment_types := {
	"aws_iam_user_policy_attachment",
	"aws_iam_group_policy_attachment",
	"aws_iam_role_policy_attachment",
	"aws_iam_policy_attachment",
}

# plan JSON 은 format_version 으로 호환성을 약속한다. 공식 문서가 "인식하지 못하는
# 메이저 버전은 거부하라"고 지시하므로, 규칙이 조용히 빗나가는 대신 여기서 멈춘다.
# (1.0 이후 마이너만 올랐고 메이저 변경은 없었다 — 현재 1.2)
supported_major := "1"

deny contains finding("high", "plan JSON 형식 버전을 해석할 수 없습니다", sprintf("format_version=%v 는 이 정책이 아는 형식(%v.x)이 아닙니다. 정책을 갱신하기 전까지 IAM 검사 결과를 신뢰하지 마십시오.", [object.get(input, "format_version", "(없음)"), supported_major])) if {
	not valid_format
}

valid_format if {
	v := input.format_version
	is_string(v)
	split(v, ".")[0] == supported_major
}

changes contains rc if {
	some rc in input.resource_changes
	startswith(rc.type, "aws_iam_")
	not only_noise(rc)
}

# no-op 은 볼 것이 없지만 import 는 no-op 으로도 나타나므로 남긴다.
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

after(rc) := object.union({}, x) if x := rc.change.after
after(rc) := {} if rc.change.after == null
after(rc) := {} if not rc.change.after

before(rc) := object.union({}, x) if x := rc.change.before
before(rc) := {} if rc.change.before == null
before(rc) := {} if not rc.change.before

arn_of(o) := o.policy_arn
arn_of(o) := o.managed_policy_arn if not o.policy_arn
arn_of(o) := "" if {
	not o.policy_arn
	not o.managed_policy_arn
}

finding(level, text, why) := {"level": level, "msg": text, "why": why}

# plan JSON 은 값이 없을 때 null 을 넣는다. Rego 에서 null 은 정의된 값이라
# `not x` 로 걸리지 않으므로 명시적으로 "쓸 만한 문자열인가"를 본다.
present(x) if {
	is_string(x)
	x != ""
}

boundary(rc, which) := b if {
	b := object.get(rc.change[which], "permissions_boundary", null)
	present(b)
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

# create 만 보면 안 된다. 경계는 제자리 갱신 대상이라 변수를 비우면
# 전 사용자에게 조용한 update 로 나타나고, import 도 이 경로로 벗겨진다.
deny contains finding("high", boundary_text(rc), "경계가 사라지거나 넓어지면 그룹 정책이 그대로 유효 권한이 됩니다.") if {
	some rc in changes
	rc.type == "aws_iam_user"
	not acted(rc, "delete")
	boundary(rc, "before")
	boundary(rc, "before") != object.get(rc.change.after, "permissions_boundary", null)
}

boundary_text(rc) := sprintf("권한 경계 교체 (`%s` → `%s`) — `%s`", [boundary(rc, "before"), boundary(rc, "after"), rc.address]) if boundary(rc, "after")

boundary_text(rc) := sprintf("권한 경계 제거 — `%s`", [rc.address]) if not boundary(rc, "after")

# ---- 권한 부여 ----------------------------------------------------------

deny contains finding("high", sprintf("특권 정책 연결 — `%s` → `%s`", [arn_of(after(rc)), rc.address]), "관리자·IAM 전체 권한입니다. 이 연결이 의도된 것인지 본문에 사유를 남기십시오.") if {
	some rc in changes
	rc.type in attachment_types
	acted(rc, "create")
	regex.match(critical_policy, arn_of(after(rc)))
}

warn contains finding("warn", sprintf("광범위한 정책 연결 — `%s` → `%s`", [arn_of(after(rc)), rc.address]), "해당 서비스 전체 권한입니다. 더 좁은 정책으로 대체할 수 있는지 확인하십시오.") if {
	some rc in changes
	rc.type in attachment_types
	acted(rc, "create")
	not regex.match(critical_policy, arn_of(after(rc)))
	regex.match(broad_policy, arn_of(after(rc)))
}

deny contains finding("high", sprintf("모든 작업을 허용하는 정책 — `%s`", [rc.address]), "`Action: \"*\"` 와 `Resource: \"*\"` 를 동시에 허용합니다.") if {
	some rc in changes
	not acted(rc, "delete")
	# 배열 리터럴에 undefined 원소가 하나라도 있으면 전체가 undefined 가 되므로
	# object.get 으로 기본값을 채워서 순회한다.
	some key in ["policy", "assume_role_policy"]
	star_policy(object.get(after(rc), key, null))
}

star_policy(doc) if {
	is_string(doc)
	parsed := json.unmarshal(doc)
	some s in cast_array(parsed.Statement)
	s.Effect == "Allow"
	"*" in cast_array(s.Action)
	"*" in cast_array(s.Resource)
}

cast_array(x) := x if is_array(x)

cast_array(x) := [x] if not is_array(x)

# ---- 정보 --------------------------------------------------------------

warn contains finding("warn", sprintf("그룹 소속 변경 — `%s` → %s", [rc.address, concat(", ", cast_array(after(rc).groups))]), "그룹을 통해 부여되는 권한이 바뀝니다.") if {
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
