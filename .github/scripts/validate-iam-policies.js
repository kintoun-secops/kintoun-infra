'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const POLICY_FIELDS = {
  aws_iam_policy: [{ field: 'policy', policyType: 'IDENTITY_POLICY' }],
  aws_iam_user_policy: [{ field: 'policy', policyType: 'IDENTITY_POLICY' }],
  aws_iam_group_policy: [{ field: 'policy', policyType: 'IDENTITY_POLICY' }],
  aws_iam_role_policy: [{ field: 'policy', policyType: 'IDENTITY_POLICY' }],
  aws_iam_role: [{
    field: 'assume_role_policy',
    policyType: 'RESOURCE_POLICY',
    resourceType: 'AWS::IAM::AssumeRolePolicyDocument',
  }],
};

function modules(root) {
  if (!root) return [];
  return [root, ...(root.child_modules || []).flatMap(modules)];
}

function extractPolicies(plan) {
  if (!/^1\./.test(String(plan.format_version || ''))) {
    throw new Error(`지원하지 않는 Terraform plan JSON 형식: ${plan.format_version || '(없음)'}`);
  }

  const policies = [];
  const unchecked = [];
  for (const module of modules(plan.planned_values && plan.planned_values.root_module)) {
    for (const resource of module.resources || []) {
      for (const spec of POLICY_FIELDS[resource.type] || []) {
        const document = resource.values && resource.values[spec.field];
        if (typeof document !== 'string') {
          unchecked.push(`${resource.address}.${spec.field}`);
          continue;
        }
        JSON.parse(document);
        policies.push({ address: resource.address, document, ...spec });
      }
    }
  }
  return { policies, unchecked };
}

function awsValidate(policy, region, policyFile) {
  fs.writeFileSync(policyFile, policy.document, { mode: 0o600 });
  const args = [
    'accessanalyzer', 'validate-policy',
    '--policy-document', `file://${policyFile}`,
    '--policy-type', policy.policyType,
    '--region', region,
    '--output', 'json',
    '--no-cli-pager',
  ];
  if (policy.resourceType) {
    args.push('--validate-policy-resource-type', policy.resourceType);
  }

  const result = spawnSync('aws', args, { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `AWS CLI 종료 코드 ${result.status}`);
  }
  const parsed = JSON.parse(result.stdout);
  if (!Array.isArray(parsed.findings)) throw new Error('AWS 응답에 findings 배열이 없습니다.');
  return parsed.findings;
}

function escapeCell(value) {
  return String(value).replace(/\|/g, '\\|').replace(/[\r\n]+/g, ' ');
}

function render(results, unchecked) {
  const findings = results.flatMap(({ address, findings: items }) =>
    items.map((finding) => ({ address, ...finding })));
  const lines = [`검사한 정책: ${results.length}개`];

  if (unchecked.length) {
    lines.push('', `검사하지 못한 정책: ${unchecked.map((item) => `\`${item}\``).join(', ')}`);
  }
  if (!findings.length) {
    lines.push('', 'Access Analyzer 지적 없음');
    return lines.join('\n');
  }

  lines.push('', '| 정책 | 구분 | 코드 | 내용 |', '|---|---|---|---|');
  for (const finding of findings) {
    lines.push(`| \`${escapeCell(finding.address)}\` | ${escapeCell(finding.findingType)} | `
      + `${escapeCell(finding.issueCode)} | ${escapeCell(finding.findingDetails)} |`);
  }
  return lines.join('\n');
}

function main(argv) {
  const [planFile, region] = argv;
  if (!planFile || !region) throw new Error('사용법: validate-iam-policies.js <plan.json> <region>');
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  const { policies, unchecked } = extractPolicies(plan);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'iam-policy-validation-'));
  try {
    const results = policies.map((policy, index) => ({
      address: policy.address,
      findings: awsValidate(policy, region, path.join(tempDir, `${index}.json`)),
    }));
    process.stdout.write(`${render(results, unchecked)}\n`);
    const blocking = results.some(({ findings }) => findings.some(({ findingType }) =>
      findingType === 'ERROR' || findingType === 'SECURITY_WARNING'));
    if (unchecked.length || blocking) process.exitCode = 1;
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { extractPolicies, render };
