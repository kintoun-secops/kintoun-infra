'use strict';

const assert = require('assert');
const { extractPolicies, render } = require('./validate-iam-policies');

const fixture = {
  format_version: '1.2',
  planned_values: {
    root_module: {
      resources: [{
        address: 'aws_iam_policy.example',
        type: 'aws_iam_policy',
        identity_schema_version: 0,
        identity: null,
        values: { policy: '{"Version":"2012-10-17","Statement":[]}' },
      }],
    },
  },
};

const extracted = extractPolicies(fixture);
assert.strictEqual(extracted.policies.length, 1);
assert.strictEqual(extracted.policies[0].address, 'aws_iam_policy.example');
assert.deepStrictEqual(extracted.unchecked, []);

const nested = structuredClone(fixture);
nested.planned_values.root_module.child_modules = [{
  address: 'module.example',
  resources: [{
    address: 'module.example.aws_iam_role.example',
    type: 'aws_iam_role',
    values: { assume_role_policy: null },
  }],
}];
assert.deepStrictEqual(extractPolicies(nested).unchecked,
  ['module.example.aws_iam_role.example.assume_role_policy']);

assert.throws(() => extractPolicies({ format_version: '2.0' }), /지원하지 않는/);
// 미확정 정책이 있어도 검사한 정책 수와 지적 표를 함께 표시한다.
assert.strictEqual(render([{
  address: 'aws_iam_policy.example',
  findings: [{
    findingType: 'SECURITY_WARNING',
    issueCode: 'EXAMPLE',
    findingDetails: 'a | b\nsecond line',
  }],
}], ['aws_iam_policy.unknown.policy']), [
  '검사한 정책: 1개',
  '',
  '검사하지 못한 정책: `aws_iam_policy.unknown.policy`',
  '',
  '| 정책 | 구분 | 코드 | 내용 |',
  '|---|---|---|---|',
  '| `aws_iam_policy.example` | SECURITY_WARNING | EXAMPLE | a \\| b second line |',
].join('\n'));


// 잘못된 JSON 하나가 이후 정책의 검사를 중단시키지 않는다.
const malformed = structuredClone(fixture);
malformed.planned_values.root_module.resources.unshift({
  address: 'aws_iam_policy.invalid', type: 'aws_iam_policy', values: { policy: '{' },
});
const partial = extractPolicies(malformed);
assert.deepStrictEqual(partial.unchecked, ['aws_iam_policy.invalid.policy']);
assert.deepStrictEqual(partial.policies.map((p) => p.address), ['aws_iam_policy.example']);

const notChecked = render([], partial.unchecked);
assert.match(notChecked, /검사 완료된 정책이 없습니다/);
assert.doesNotMatch(notChecked, /지적 없음/);
const partlyChecked = render([{ address: 'aws_iam_policy.example', findings: [] }], partial.unchecked);
assert.match(partlyChecked, /검사하지 못한 정책: `aws_iam_policy.invalid.policy`/);
assert.match(partlyChecked, /검사한 정책에서 Access Analyzer 지적 없음/);
