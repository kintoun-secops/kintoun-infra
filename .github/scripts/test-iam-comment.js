'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const render = require('./iam-comment');
const { toSlug } = require('./tf-roots');

const DIRS = ['identity', 'platform/network'];

function writeArtifact(root, module, contents) {
  const dir = path.join(root, `iam-findings-${toSlug(module)}`);
  fs.mkdirSync(dir, { recursive: true });
  if (contents !== undefined) fs.writeFileSync(path.join(dir, 'iam-findings.json'), contents);
}

async function runCase(setup, expectedDirs = DIRS) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iam-comment-test-'));
  const outputs = {};
  const calls = { add: 0, remove: 0 };
  try {
    setup(root);
    await render({
      findingsDir: root,
      outFile: path.join(root, 'comment.md'),
      expectedDirs,
      context: {
        payload: { pull_request: { number: 9, base: { ref: 'main' }, head: { sha: '1234567890' } } },
        repo: { owner: 'example', repo: 'infra' },
        serverUrl: 'https://github.com',
        runId: 1,
      },
      core: {
        setOutput: (key, value) => {
          if (key === 'only_update') assert.match(value, /^(true|false)$/);
          outputs[key] = value;
        },
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
  assert.strictEqual(missing.outputs.only_update, 'false');
  assert.match(missing.body, /`identity`, `platform\/network`/);

  const clean = await runCase((root) => {
    writeArtifact(root, 'identity', '[]');
    writeArtifact(root, 'platform/network', '[]');
  });
  assert.strictEqual(clean.outputs.only_update, 'true');
  assert.strictEqual(clean.calls.remove, 1);

  const partial = await runCase((root) => writeArtifact(root, 'identity', '[]'));
  assert.strictEqual(partial.outputs.only_update, 'false');
  assert.match(partial.body, /`platform\/network`/);

  const invalid = await runCase((root) => {
    writeArtifact(root, 'identity', '{');
    writeArtifact(root, 'platform/network', '[]');
  });
  assert.match(invalid.body, /`identity`/);

  const high = await runCase((root) => {
    writeArtifact(root, 'platform/network', JSON.stringify([{ failures: [{
      msg: 'change | address', metadata: { level: 'high', why: 'reason' },
    }] }]));
    writeArtifact(root, 'identity', '[]');
  });
  assert.strictEqual(high.calls.add, 1);
  assert.strictEqual(high.outputs.only_update, 'false');
  assert.match(high.body, /change \\| address/);
  assert.match(high.body, /\| platform\/network \| \*\*위험\*\*/); // 중첩 dir 은 원래 경로로 표시

  // 기대 목록에 없는 아티팩트는 무시하고, 목록에 있는 것만 센다.
  const extra = await runCase((root) => {
    writeArtifact(root, 'identity', '[]');
    writeArtifact(root, 'platform/network', '[]');
    writeArtifact(root, 'lab/victim', JSON.stringify([{ failures: [{ msg: 'x', metadata: { level: 'high' } }] }]));
  });
  assert.strictEqual(extra.outputs.only_update, 'true');
  assert.strictEqual(extra.calls.add, 0);

  // 루트 목록이 비면(discover 실패) 깨끗해 보여도 갱신하지 않고 경고를 남긴다.
  for (const dirs of [[], null]) { // undefined 는 기본값이 대신 들어간다
    const noList = await runCase((root) => writeArtifact(root, 'identity', '[]'), dirs);
    assert.strictEqual(noList.outputs.only_update, 'false');
    assert.strictEqual(noList.calls.remove, 0);
    assert.match(noList.body, /루트 모듈 목록을 얻지 못해/);
  }
})().catch((error) => {
  process.stderr.write(`${error.stack}\n`);
  process.exitCode = 1;
});
