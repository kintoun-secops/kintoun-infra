'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const render = require('./iam-comment');

function writeArtifact(root, module, contents) {
  const dir = path.join(root, `iam-findings-${module}`);
  fs.mkdirSync(dir, { recursive: true });
  if (contents !== undefined) fs.writeFileSync(path.join(dir, 'iam-findings.json'), contents);
}

async function runCase(setup) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iam-comment-test-'));
  const outputs = {};
  const calls = { add: 0, remove: 0 };
  try {
    setup(root);
    await render({
      findingsDir: root,
      outFile: path.join(root, 'comment.md'),
      context: {
        payload: { pull_request: { number: 9, base: { ref: 'main' }, head: { sha: '1234567890' } } },
        repo: { owner: 'example', repo: 'infra' },
        serverUrl: 'https://github.com',
        runId: 1,
      },
      core: {
        setOutput: (key, value) => { outputs[key] = value; },
        summary: { addRaw() {}, async write() {} },
      },
      github: { rest: { issues: {
        async getLabel() {},
        async createLabel() {},
        async addLabels() { calls.add += 1; },
        async removeLabel() { calls.remove += 1; },
      } } },
    });
    return { outputs, calls, body: fs.readFileSync(path.join(root, 'comment.md'), 'utf8') };
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

(async () => {
  const missing = await runCase(() => {});
  assert.strictEqual(missing.outputs.only_update, '');
  assert.match(missing.body, /`identity`, `platform`/);

  const clean = await runCase((root) => {
    writeArtifact(root, 'identity', '[]');
    writeArtifact(root, 'platform', '[]');
  });
  assert.strictEqual(clean.outputs.only_update, 'true');
  assert.strictEqual(clean.calls.remove, 1);

  const partial = await runCase((root) => writeArtifact(root, 'identity', '[]'));
  assert.strictEqual(partial.outputs.only_update, '');
  assert.match(partial.body, /`platform`/);

  const invalid = await runCase((root) => {
    writeArtifact(root, 'identity', '{');
    writeArtifact(root, 'platform', '[]');
  });
  assert.match(invalid.body, /`identity`/);

  const high = await runCase((root) => {
    writeArtifact(root, 'identity', JSON.stringify([{ failures: [{
      msg: 'change | address', metadata: { level: 'high', why: 'reason' },
    }] }]));
    writeArtifact(root, 'platform', '[]');
  });
  assert.strictEqual(high.calls.add, 1);
  assert.strictEqual(high.outputs.only_update, '');
  assert.match(high.body, /change \\| address/);
})().catch((error) => {
  process.stderr.write(`${error.stack}\n`);
  process.exitCode = 1;
});
