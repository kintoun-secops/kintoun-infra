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
assert.match(render([], ['aws_iam_policy.unknown.policy']), /검사하지 못한 정책/);
assert.match(render([{
  address: 'aws_iam_policy.example',
  findings: [{
    findingType: 'SECURITY_WARNING',
    issueCode: 'EXAMPLE',
    findingDetails: 'a | b\nsecond line',
  }],
}], []), /a \\| b second line/);
