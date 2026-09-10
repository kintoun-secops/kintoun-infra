'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const render = require('./plan-summary');
const { toSlug } = require('./tf-roots');

const DIRS = ['identity', 'platform/network'];
const cleanResults = [
  { namespace: 'terraform.iam', successes: 1 },
  { namespace: 'terraform.guardrail', successes: 1 },
];
const CLEAN = JSON.stringify(cleanResults);
const iamResults = (failures) =>
  JSON.stringify([{ namespace: 'terraform.iam', failures }, cleanResults[1]]);

function writeArtifact(root, module, contents, status) {
  const dir = path.join(root, `iam-findings-${toSlug(module)}`);
  fs.mkdirSync(dir, { recursive: true });
  if (contents !== undefined) fs.writeFileSync(path.join(dir, 'iam-findings.json'), contents);
  if (status !== undefined)
    fs.writeFileSync(path.join(dir, 'plan-status.json'), JSON.stringify(status));
}

async function runCase(setup, expectedDirs = DIRS, skippedDirs = []) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'plan-summary-test-'));
  const outputs = {};
  const calls = { add: 0, remove: 0 };
  try {
    setup(root);
    await render({
      findingsDir: root,
      outFile: path.join(root, 'comment.md'),
      expectedDirs,
      skippedDirs,
      context: {
        payload: {
          pull_request: { number: 9, base: { ref: 'main' }, head: { sha: '1234567890' } },
        },
        repo: { owner: 'example', repo: 'infra' },
        serverUrl: 'https://github.com',
        runId: 1,
      },
      core: {
        setOutput: (key, value) => {
          if (key === 'only_update' || key === 'unchanged_delete')
            assert.match(value, /^(true|false)$/);
          outputs[key] = value;
        },
        summary: { addRaw() {}, async write() {} },
      },
      github: {
        rest: {
          issues: {
            async getLabel() {},
            async createLabel() {},
            async addLabels() {
              calls.add += 1;
            },
            async removeLabel() {
              calls.remove += 1;
            },
          },
        },
      },
    });
    return { outputs, calls, body: fs.readFileSync(path.join(root, 'comment.md'), 'utf8') };
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

(async () => {
  const missing = await runCase(() => {});
  const partial = await runCase((root) => writeArtifact(root, 'identity', CLEAN));
  const invalid = await runCase((root) => {
    writeArtifact(root, 'identity', '{');
    writeArtifact(root, 'platform/network', CLEAN);
  });
  // 일부라도 미검사면 해당 루트를 명시하고 새 경고를 허용하며 기존 위험 라벨을 유지한다.
  for (const [result, uncheckedRoots] of [
    [missing, '`identity`, `platform/network`'],
    [partial, '`platform/network`'],
    [invalid, '`identity`'],
  ]) {
    assert.strictEqual(result.outputs.only_update, 'false');
    assert.strictEqual(result.outputs.unchanged_delete, 'true');
    assert.deepStrictEqual(result.calls, { add: 0, remove: 0 });
    assert.strictEqual(
      result.body.split('\n')[2],
      `${uncheckedRoots}: plan 또는 IAM 검사 결과가 없어 이 커밋의 IAM 변경을 모두 검사하지 못했습니다.`,
    );
  }

  const clean = await runCase((root) => {
    writeArtifact(root, 'identity', CLEAN);
    writeArtifact(root, 'platform/network', CLEAN);
  });
  assert.strictEqual(clean.outputs.only_update, 'true');
  assert.strictEqual(clean.calls.remove, 1);

  const high = await runCase((root) => {
    writeArtifact(
      root,
      'platform/network',
      iamResults([
        {
          msg: 'change | address',
          metadata: { level: 'high', why: 'reason' },
        },
      ]),
    );
    writeArtifact(root, 'identity', CLEAN);
  });
  assert.strictEqual(high.calls.add, 1);
  assert.strictEqual(high.outputs.only_update, 'false');
  assert.ok(high.body.includes('| platform/network | **위험** | change \\| address | reason |'));

  // 기대 목록에 없는 아티팩트는 무시하고, 목록에 있는 것만 센다.
  const extra = await runCase((root) => {
    writeArtifact(root, 'identity', CLEAN);
    writeArtifact(root, 'platform/network', CLEAN);
    writeArtifact(root, 'lab/victim', iamResults([{ msg: 'x', metadata: { level: 'high' } }]));
  });
  assert.strictEqual(extra.outputs.only_update, 'true');
  assert.strictEqual(extra.calls.add, 0);

  // 루트 목록이 비면(discover 실패) 깨끗해 보여도 갱신하지 않고 경고를 남긴다.
  for (const dirs of [[], null]) {
    // undefined 는 기본값이 대신 들어간다
    const noList = await runCase((root) => writeArtifact(root, 'identity', CLEAN), dirs);
    assert.strictEqual(noList.outputs.only_update, 'false');
    assert.strictEqual(noList.calls.remove, 0);
    assert.match(noList.body, /루트 모듈 목록을 얻지 못해/);
    assert.strictEqual(noList.outputs.unchanged_delete, 'true');
  }

  const grouped = await runCase(
    (root) => {
      writeArtifact(root, 'identity', CLEAN, { no_changes: true });
      writeArtifact(root, 'platform', CLEAN, { no_changes: true });
      writeArtifact(root, 'platform/network', CLEAN, { no_changes: true });
      // import, 관리 해제나 출력 변경으로 종료 코드가 2이면 요약에 넣지 않는다.
      writeArtifact(root, 'platform/wazuh', CLEAN, { no_changes: false });
      writeArtifact(root, 'platform/removed-root', CLEAN, { no_changes: true });
    },
    ['identity', 'platform', 'platform/network', 'platform/wazuh'],
  );
  assert.strictEqual(grouped.outputs.unchanged_delete, 'false');
  assert.match(grouped.outputs.unchanged_body, /`platform` \| No changes/);
  assert.match(grouped.outputs.unchanged_body, /`platform\/network` \| No changes/);
  assert.doesNotMatch(
    grouped.outputs.unchanged_body,
    /`identity`|`platform\/wazuh`|`platform\/removed-root`/,
  );

  for (const status of [{ no_changes: 'true' }, {}]) {
    const changed = await runCase((root) => writeArtifact(root, 'platform/network', CLEAN, status));
    assert.strictEqual(changed.outputs.unchanged_delete, 'true');
  }

  // KMS 판정은 별도 코멘트로 가며 IAM 위험 라벨에 영향을 주지 않는다.
  const kmsOnly = await runCase(
    (root) => {
      writeArtifact(
        root,
        'identity',
        JSON.stringify([
          ...cleanResults,
          {
            namespace: 'terraform.kms',
            failures: [{ msg: 'KMS 위험', metadata: { level: 'high', why: '키 정책' } }],
          },
        ]),
      );
    },
    ['identity'],
  );
  assert.doesNotMatch(kmsOnly.body, /KMS 위험/);
  assert.deepStrictEqual(kmsOnly.calls, { add: 0, remove: 1 });

  // IAM 또는 가드레일 namespace가 빠지면 지적 0건이어도 검사 완료가 아니다.
  for (const results of [
    [],
    [cleanResults[0]],
    [cleanResults[1]],
    [{ namespace: 'terraform.kms' }],
  ]) {
    const unchecked = await runCase(
      (root) => {
        writeArtifact(root, 'identity', JSON.stringify(results));
      },
      ['identity'],
    );
    assert.deepStrictEqual(unchecked.calls, { add: 0, remove: 0 });
    assert.strictEqual(unchecked.outputs.only_update, 'false');
    assert.match(unchecked.body, /IAM 변경을 모두 검사하지 못했습니다/);
    assert.doesNotMatch(unchecked.body, /모두 해소되었습니다/);
  }

  // 한 패키지가 누락돼도 다른 패키지가 확인한 위험은 남긴다.
  const partialHigh = await runCase(
    (root) => {
      writeArtifact(
        root,
        'identity',
        JSON.stringify([
          {
            namespace: 'terraform.guardrail',
            failures: [{ msg: '[차단] 경계 없음', metadata: { level: 'high' } }],
          },
        ]),
      );
    },
    ['identity'],
  );
  assert.deepStrictEqual(partialHigh.calls, { add: 1, remove: 0 });
  assert.match(partialHigh.body, /IAM 변경을 모두 검사하지 못했습니다/);
  assert.match(partialHigh.body, /\[차단\] 경계 없음/);

  // 실패 표식이 있으면 같은 디렉터리에 판정 파일이 남아 있어도 검사 완료로 보지 않는다.
  const failedMarker = await runCase(
    (root) => {
      writeArtifact(root, 'identity', CLEAN);
      fs.writeFileSync(path.join(root, 'iam-findings-identity', 'plan-failed'), '');
    },
    ['identity'],
  );
  assert.strictEqual(failedMarker.outputs.only_update, 'false');
  assert.deepStrictEqual(failedMarker.calls, { add: 0, remove: 0 });

  // 변경 영향이 없어 생략한 루트는 실패로 세지 않는다. 대상 루트가 모두 깨끗하면 검사 완료다.
  const withSkipped = await runCase(
    (root) => writeArtifact(root, 'identity', CLEAN),
    ['identity'],
    ['platform/network'],
  );
  assert.strictEqual(withSkipped.outputs.only_update, 'true');
  assert.deepStrictEqual(withSkipped.calls, { add: 0, remove: 1 });
  assert.strictEqual(withSkipped.body.split('\n')[2], '이전에 지적된 항목이 모두 해소되었습니다.');
  assert.strictEqual(
    withSkipped.body.split('\n')[4],
    '`platform/network`: 변경 영향이 없어 plan 을 생략했습니다.',
  );
  assert.doesNotMatch(withSkipped.body, /검사하지 못했습니다/);

  // 대상 루트의 실패는 생략과 별개로 미검사다.
  const skippedAndFailed = await runCase(() => {}, ['identity'], ['platform/network']);
  assert.strictEqual(skippedAndFailed.outputs.only_update, 'false');
  assert.deepStrictEqual(skippedAndFailed.calls, { add: 0, remove: 0 });
  assert.strictEqual(
    skippedAndFailed.body.split('\n')[2],
    '`identity`: plan 또는 IAM 검사 결과가 없어 이 커밋의 IAM 변경을 모두 검사하지 못했습니다.',
  );
  assert.match(skippedAndFailed.body, /`platform\/network`: 변경 영향이 없어/);

  // 대상이 하나도 없으면 discover 실패와 구분한다. 검사 완료로 보고 기존 코멘트만 갱신한다.
  const none = await runCase(() => {}, [], DIRS);
  assert.strictEqual(none.outputs.only_update, 'true');
  assert.deepStrictEqual(none.calls, { add: 0, remove: 1 });
  assert.strictEqual(
    none.body.split('\n')[2],
    '변경 영향이 있는 루트가 없어 plan 을 생략했습니다. 이 커밋에는 검사할 IAM 변경이 없습니다.',
  );
  assert.doesNotMatch(
    none.body,
    /루트 모듈 목록을 얻지 못해|변경 영향이 없어 plan 을 생략했습니다\./,
  );
  assert.strictEqual(none.outputs.unchanged_delete, 'true');

  // 두 목록에 같은 루트가 있으면 대상으로 센다. 판정이 있으면 생략 안내와 표를 함께 만든다.
  const highSkipped = await runCase(
    (root) => {
      writeArtifact(
        root,
        'identity',
        iamResults([{ msg: 'x', metadata: { level: 'high', why: 'w' } }]),
      );
    },
    ['identity'],
    ['identity', 'platform/network'],
  );
  assert.deepStrictEqual(highSkipped.calls, { add: 1, remove: 0 });
  assert.strictEqual(
    highSkipped.body.split('\n')[2],
    '`platform/network`: 변경 영향이 없어 plan 을 생략했습니다.',
  );
  assert.ok(highSkipped.body.includes('| identity | **위험** | x | w |'));
})().catch((error) => {
  process.stderr.write(`${error.stack}\n`);
  process.exitCode = 1;
});
