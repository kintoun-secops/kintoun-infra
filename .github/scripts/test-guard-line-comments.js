'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const post = require('./guard-line-comments');
const { toSlug } = require('./tf-roots');

const { diffLines, parseAddress, locate, MARKER } = post;

// hunk 헤더 뒤의 문맥·추가 줄만 새 파일 쪽 번호를 받는다. 삭제 줄과 개행 안내는 건너뛴다.
const patch = [
  '@@ -1,3 +1,4 @@',
  ' resource "aws_iam_user" "a" {',
  '-  name = "old"',
  '+  name = "new"',
  '+  path = "/"',
  ' }',
  '@@ -20,2 +21,2 @@',
  ' resource "aws_kms_key" "k" {',
  '\\ No newline at end of file',
  ' }',
].join('\n');
assert.deepStrictEqual([...diffLines(patch)], [1, 2, 3, 4, 21, 22]);
assert.strictEqual(diffLines(undefined).size, 0);

assert.deepStrictEqual(parseAddress('aws_iam_user.a'), { modules: [], key: 'aws_iam_user.a' });
assert.deepStrictEqual(parseAddress('module.m["k"].module.n[0].aws_kms_key.k[1]'), {
  modules: ['m', 'n'],
  key: 'aws_kms_key.k',
});
assert.deepStrictEqual(parseAddress('data.aws_iam_policy_document.d'), {
  modules: [],
  key: 'data.aws_iam_policy_document.d',
});
assert.strictEqual(parseAddress('aws_iam_user'), null);

const configs = {
  identity: {
    managed_resources: { 'aws_iam_user.a': { pos: { filename: 'identity/users.tf', line: 1 } } },
    module_calls: { m: { source: '../modules/kms' } },
  },
  'modules/kms': {
    managed_resources: {
      'aws_kms_key.k': { pos: { filename: '/repo/modules/kms/main.tf', line: 21 } },
    },
  },
  'platform/wazuh': null,
};
const inspectCalls = [];
const inspect = (repoRoot, dir) => {
  inspectCalls.push(dir);
  assert.strictEqual(repoRoot, '/repo');
  return configs[dir] ?? null;
};

const located = locate(
  [
    { dir: 'identity', address: 'aws_iam_user.a' },
    { dir: 'identity', address: 'module.m.aws_kms_key.k' },
    { dir: 'identity', address: 'module.x.aws_kms_key.k' },
    { dir: 'identity', address: 'aws_iam_user.missing' },
    { dir: 'platform/wazuh', address: 'aws_iam_role.r' },
    { dir: 'identity', address: '' },
  ],
  inspect,
  '/repo',
);
assert.deepStrictEqual(
  located.map((f) => f.pos),
  [
    { path: 'identity/users.tf', line: 1 },
    { path: 'modules/kms/main.tf', line: 21 },
    null,
    null,
    null,
    null,
  ],
);
// 같은 루트·모듈 경로는 한 번만 조사한다.
assert.deepStrictEqual(inspectCalls, ['identity', 'modules/kms', 'platform/wazuh']);

const finding = (level, msg, address, why = '검토 사유') => ({
  msg,
  metadata: { level, why, address },
});
function writeArtifact(root, dir, results) {
  const artifact = path.join(root, `iam-findings-${toSlug(dir)}`);
  fs.mkdirSync(artifact, { recursive: true });
  fs.writeFileSync(path.join(artifact, 'iam-findings.json'), JSON.stringify(results));
}

async function runCase({ results, files, existing = [], expected = ['identity'] }) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-line-test-'));
  const calls = { deleted: [], reviews: [], outputs: {}, info: [] };
  try {
    if (results) writeArtifact(root, 'identity', results);
    await post({
      findingsDir: root,
      repoRoot: '/repo',
      expectedDirs: expected,
      skippedDirs: [],
      inspect,
      context: {
        repo: { owner: 'example', repo: 'infra' },
        payload: { pull_request: { number: 9, head: { sha: 'abcdef0123' } } },
      },
      core: {
        info: (m) => calls.info.push(m),
        setOutput: (k, v) => {
          calls.outputs[k] = v;
        },
      },
      github: {
        paginate: async (fn, params) => (await fn(params)).data,
        rest: {
          pulls: {
            async listFiles() {
              return { data: files };
            },
            async listReviewComments() {
              return { data: existing };
            },
            async deleteReviewComment({ comment_id }) {
              calls.deleted.push(comment_id);
            },
            async createReview(review) {
              calls.reviews.push(review);
            },
          },
        },
      },
    });
    return calls;
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

(async () => {
  const results = [
    {
      namespace: 'terraform.iam',
      failures: [
        finding('high', '사용자 삭제: `aws_iam_user.a`', 'aws_iam_user.a'),
        finding('high', '경계 없음: `aws_iam_user.a`', 'aws_iam_user.a', '두 번째 사유'),
        finding('high', '경계 없음: `aws_iam_user.missing`', 'aws_iam_user.missing'),
      ],
      warnings: [finding('warn', '사용자 생성: `aws_iam_user.a`', 'aws_iam_user.a')],
    },
    { namespace: 'terraform.guardrail', successes: 1 },
    {
      namespace: 'terraform.kms',
      failures: [finding('high', '키 삭제: `module.m.aws_kms_key.k`', 'module.m.aws_kms_key.k')],
      warnings: [finding('info', 'KMS 변경', 'module.m.aws_kms_key.k')],
    },
  ];
  const files = [
    { filename: 'identity/users.tf', patch },
    { filename: 'modules/kms/main.tf', patch: '@@ -1,2 +1,2 @@\n locals {\n+  x = 1\n }' },
  ];
  const stale = [
    { id: 1, body: `${MARKER}\n이전 판정` },
    { id: 2, body: '사람이 쓴 리뷰 코멘트' },
  ];

  const posted = await runCase({ results, files, existing: stale });
  assert.deepStrictEqual(posted.deleted, [1]);
  assert.strictEqual(posted.reviews.length, 1);
  const review = posted.reviews[0];
  assert.strictEqual(review.commit_id, 'abcdef0123');
  assert.strictEqual(review.event, 'COMMENT');
  assert.strictEqual(review.pull_number, 9);
  // 같은 줄의 위험 두 건은 코멘트 하나로 묶고, 확인·변경 판정과 diff 밖의 키 삭제는 달지 않는다.
  assert.strictEqual(review.comments.length, 1);
  const [comment] = review.comments;
  assert.deepStrictEqual(
    [comment.path, comment.line, comment.side],
    ['identity/users.tf', 1, 'RIGHT'],
  );
  assert.ok(comment.body.startsWith(MARKER));
  assert.match(comment.body, /IAM 가드 · 위험\*\* 사용자 삭제/);
  assert.match(comment.body, /두 번째 사유/);
  assert.doesNotMatch(comment.body, /사용자 생성|KMS 변경|키 삭제/);
  assert.strictEqual(posted.outputs.line_comments, '1');
  assert.match(posted.info[0], /위험 4건 중 1곳에 게시, diff 밖 2건/);

  // diff 에 블록이 들어오면 KMS 위험도 모듈 파일의 줄에 단다.
  const moduleInDiff = await runCase({
    results,
    files: [
      files[0],
      {
        filename: 'modules/kms/main.tf',
        patch: '@@ -20,2 +20,3 @@\n locals {}\n resource "aws_kms_key" "k" {\n+  x = 1',
      },
    ],
  });
  assert.deepStrictEqual(
    moduleInDiff.reviews[0].comments.map((c) => `${c.path}:${c.line}`),
    ['identity/users.tf:1', 'modules/kms/main.tf:21'],
  );
  assert.match(moduleInDiff.reviews[0].comments[1].body, /KMS 가드 · 위험\*\* 키 삭제/);

  // 판정이 없으면 이전 코멘트만 지우고 리뷰를 만들지 않는다. plan 이 없어도 같다.
  const clean = await runCase({
    results: [
      { namespace: 'terraform.iam', successes: 1 },
      results[1],
      { namespace: 'terraform.kms', successes: 1 },
    ],
    files,
    existing: stale,
  });
  assert.deepStrictEqual(
    [clean.deleted, clean.reviews.length, clean.outputs.line_comments],
    [[1], 0, '0'],
  );
  const missing = await runCase({ results: null, files, existing: stale });
  assert.deepStrictEqual([missing.deleted, missing.reviews.length], [[1], 0]);

  // patch 가 없는 큰 파일과 조사 실패 루트는 표에만 남긴다.
  const noPatch = await runCase({ results, files: [{ filename: 'identity/users.tf' }] });
  assert.strictEqual(noPatch.reviews.length, 0);
  console.log('guard-line-comments: ok');
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
