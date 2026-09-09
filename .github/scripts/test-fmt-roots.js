'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'fmt-roots-test-'));
const file = path.join(repo, 'terraform-roots.json');
const script = path.join(__dirname, 'fmt-roots.js');
const run = (mode) => spawnSync(process.execPath, [script, mode], { cwd: repo, encoding: 'utf8' });
const data = { $comment: '루트와 순서', roots: { platform: { depends_on: ['platform/wazuh', 'platform/network'] } } };
const canonical = `${JSON.stringify(data, null, 2)}\n`;

try {
  fs.writeFileSync(file, canonical);
  assert.strictEqual(run('--check').status, 0);

  for (const input of [
    `${JSON.stringify(data, null, 3)}\n`,
    canonical.replace(/\n/g, '\r\n'),
    canonical.replace(/\n/g, '  \n'),
    `${canonical}\n`,
    canonical.trimEnd(),
  ]) {
    fs.writeFileSync(file, input);
    const check = run('--check');
    assert.strictEqual(check.status, 1);
    assert.match(check.stderr, /--write/);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), input, '검사는 파일을 수정하지 않는다');
    assert.strictEqual(run('--write').status, 0);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), canonical, '값과 키·배열 순서를 유지한다');
    assert.strictEqual(run('--write').stdout, '', '다시 정리하면 변경이 없다');
    assert.strictEqual(run('--check').status, 0);
  }

  fs.writeFileSync(file, '{');
  for (const mode of ['--check', '--write']) {
    assert.strictEqual(run(mode).status, 1);
    assert.strictEqual(fs.readFileSync(file, 'utf8'), '{', '구문 오류가 있는 파일을 덮어쓰지 않는다');
  }
  fs.unlinkSync(file);
  assert.strictEqual(run('--check').status, 1);
  assert.strictEqual(run('--unknown').status, 1);
} finally {
  fs.rmSync(repo, { recursive: true, force: true });
}
