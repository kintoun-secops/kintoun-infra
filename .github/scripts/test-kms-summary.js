'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const render = require('./kms-summary');

const finding = (level) => ({ msg: `${level} | key`, metadata: { level, why: '검토 사유' } });
const results = (warnings = [], failures = []) => [
  { namespace: 'terraform.iam', failures: [finding('high')] },
  { namespace: 'terraform.kms', warnings, failures },
];

async function runCase(contents, { expected = ['platform/wazuh'], skipped = ['identity'], failed = false } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kms-summary-test-'));
  const calls = { add: [], remove: [], create: [] };
  const outputs = {};
  const summary = [];
  try {
    const artifact = path.join(dir, 'iam-findings-platform__wazuh');
    fs.mkdirSync(artifact);
    if (contents !== undefined) fs.writeFileSync(path.join(artifact, 'iam-findings.json'), contents);
    if (failed) fs.writeFileSync(path.join(artifact, 'plan-failed'), '');
    await render({
      findingsDir: dir, outFile: path.join(dir, 'comment.md'), expectedDirs: expected, skippedDirs: skipped,
      context: { repo: { owner: 'example', repo: 'infra' }, serverUrl: 'https://github.com', runId: 1,
        payload: { pull_request: { number: 9, base: { ref: 'main' }, head: { sha: '1234567890' } } } },
      core: { setOutput: (key, value) => { outputs[key] = value; },
        summary: { addRaw: (value) => summary.push(value), async write() {} } },
      github: { rest: { issues: {
        async getLabel() { throw Object.assign(new Error('missing'), { status: 404 }); },
        async createLabel({ name }) { calls.create.push(name); },
        async addLabels({ labels }) { calls.add.push(...labels); },
        async removeLabel({ name }) { calls.remove.push(name); },
      } } },
    });
    return { calls, outputs, body: fs.readFileSync(path.join(dir, 'comment.md'), 'utf8'), summary };
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}

(async () => {
  const clean = await runCase(JSON.stringify(results()));
  assert.deepStrictEqual(clean.calls.remove, ['kms', 'kms:high-risk']);
  assert.strictEqual(clean.outputs.only_update, 'true');
  assert.match(clean.body, /KMS 리소스 변경이 확인되지 않았습니다/);
  assert.doesNotMatch(clean.body, /high \| key/);

  const changed = await runCase(JSON.stringify(results([finding('info')])));
  assert.deepStrictEqual(changed.calls.add, ['kms']);
  assert.deepStrictEqual(changed.calls.create, ['kms']);
  assert.deepStrictEqual(changed.calls.remove, ['kms:high-risk']);
  assert.strictEqual(changed.outputs.only_update, 'false');
  assert.match(changed.body, /변경 1, 위험 0, 확인 0/);
  assert.ok(changed.body.includes('info \\| key'));

  const high = await runCase(JSON.stringify(results([finding('info'), finding('warn')], [finding('high')])));
  assert.deepStrictEqual(high.calls.add, ['kms', 'kms:high-risk']);
  assert.deepStrictEqual(high.calls.remove, []);
  assert.match(high.body, /변경 1, 위험 1, 확인 1/);

  for (const contents of [undefined, '{', '[]', JSON.stringify([{ namespace: 'terraform.iam' }])]) {
    const missing = await runCase(contents);
    assert.deepStrictEqual(missing.calls.remove, []);
    assert.strictEqual(missing.outputs.only_update, 'false');
    assert.match(missing.body, /`platform\/wazuh`.*검사하지 못했습니다/);
  }
  const failed = await runCase(JSON.stringify(results()), { failed: true });
  assert.deepStrictEqual(failed.calls.remove, []);
  assert.match(failed.body, /검사하지 못했습니다/);

  const skipped = await runCase(undefined, { expected: [], skipped: ['identity', 'platform/wazuh'] });
  assert.strictEqual(skipped.outputs.only_update, 'true');
  assert.deepStrictEqual(skipped.calls.remove, ['kms', 'kms:high-risk']);
  assert.match(skipped.body, /plan 을 생략했습니다/);
  const discover = await runCase(undefined, { expected: [], skipped: [] });
  assert.strictEqual(discover.outputs.only_update, 'false');
  assert.deepStrictEqual(discover.calls.remove, []);
  assert.match(discover.body, /discover/);

  const many = await runCase(JSON.stringify(results(Array.from({ length: 45 }, () => finding('info')))));
  assert.match(many.body, /외 5건/);
  assert.strictEqual(many.summary.length, 1);
})().catch((error) => { process.stderr.write(`${error.stack}\n`); process.exitCode = 1; });
