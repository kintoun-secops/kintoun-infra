'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const roots = require('./tf-roots');
const wave = require('./wave-comment');

const META = { sha: '1234567890abcdef', runUrl: 'https://github.com/example/infra/actions/runs/1' };

function withRepo(build, check) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'wave-comment-test-'));
  try {
    build(repo);
    check(wave.render(repo, META), repo);
  } finally {
    fs.rmSync(repo, { recursive: true, force: true });
  }
}

function addRoot(repo, dir) {
  fs.mkdirSync(path.join(repo, dir), { recursive: true });
  fs.writeFileSync(
    path.join(repo, dir, 'backend.tf'),
    `terraform {\n  backend "s3" {\n    bucket = "b"\n    key    = "${dir}/terraform.tfstate"\n  }\n}\n`,
  );
}

function manifest(repo, entries) {
  const out = {};
  for (const [dir, deps] of Object.entries(entries)) out[dir] = { depends_on: deps };
  fs.mkdirSync(path.join(repo, '.github'), { recursive: true });
  fs.writeFileSync(path.join(repo, roots.MANIFEST), JSON.stringify({ roots: out }));
}

// 코멘트에서 mermaid 블록만 뽑는다.
function mermaidBlock(body) {
  const m = body.match(/```mermaid\n([\s\S]*?)\n```/);
  return m ? m[1].split('\n') : null;
}

// 허용하는 줄 모양만 나와야 GitHub 가 그린다. 노드 id 는 r<번호>, 라벨은 큰따옴표 안의 루트 경로다.
const LINE_RE = [
  /^flowchart TB$/,
  /^  subgraph wave[0-3]$/,
  /^    r\d+\["[a-z0-9][a-z0-9-]*(\/[a-z0-9][a-z0-9-]*)?"\]$/,
  /^  end$/,
  /^  r\d+ --> r\d+$/,
];

// 정상: wave 별 subgraph, depends_on 화살표, 표, 새 코멘트 허용
withRepo((repo) => {
  ['identity', 'platform/network', 'platform/wazuh', 'platform/access', 'platform'].forEach((d) => addRoot(repo, d));
  manifest(repo, {
    identity: [],
    'platform/network': [],
    'platform/wazuh': ['platform/network'],
    'platform/access': ['platform/wazuh'],
    platform: ['platform/network', 'platform/wazuh', 'platform/access'],
  });
}, ({ body, onlyUpdate, result }) => {
  assert.strictEqual(onlyUpdate, '');
  assert.deepStrictEqual(result.errors, []);
  assert.match(body, /^### apply 순서: 루트 5개, wave 4개\n/);

  const lines = mermaidBlock(body);
  assert.ok(lines, 'mermaid 블록이 없다');
  for (const line of lines) assert.ok(LINE_RE.some((re) => re.test(line)), `허용되지 않는 줄: ${line}`);
  assert.strictEqual(lines.filter((l) => /subgraph/.test(l)).length, 4);

  // 노드는 한 번씩만 선언되고 화살표는 선언된 id 만 가리킨다.
  const declared = lines.filter((l) => /^    r\d+\[/.test(l)).map((l) => l.trim().split('[')[0]);
  assert.deepStrictEqual([...new Set(declared)].length, declared.length);
  assert.strictEqual(declared.length, 5);
  for (const l of lines.filter((l) => /-->/.test(l))) {
    for (const id of l.trim().split(' --> ')) assert.ok(declared.includes(id), `선언되지 않은 id: ${id}`);
  }
  // 정렬된 루트 순번이 id 다: identity=r0, platform=r1, platform/access=r2, platform/network=r3, platform/wazuh=r4
  assert.ok(lines.includes('    r0["identity"]'));
  assert.ok(lines.includes('    r3["platform/network"]'));
  assert.ok(lines.includes('  r3 --> r4')); // network -> wazuh
  assert.ok(lines.includes('  r2 --> r1')); // access -> platform
  assert.strictEqual(lines.filter((l) => /-->/.test(l)).length, 5);
  // wave0 subgraph 가 wave1 보다 먼저 온다.
  assert.ok(lines.indexOf('  subgraph wave0') < lines.indexOf('  subgraph wave1'));

  assert.match(body, /\| 0 \| `identity` \|  \|/);
  assert.match(body, /\| 1 \| `platform\/wazuh` \| `platform\/network` \|/);
  assert.match(body, /\| 3 \| `platform` \| `platform\/access`, `platform\/network`, `platform\/wazuh` \|/);
  // 성공 본문에는 커밋·로그가 없다. 매니페스트가 같으면 커밋이 달라도 본문이 같아야 한다.
  assert.match(body, /<sub>같은 wave 는 병렬로 apply 되고 .* 화살표는 먼저 apply 되는 루트에서 나중 루트로 향합니다\.<\/sub>$/);
  assert.doesNotMatch(body, /1234567|\]\(/);
});

// wave 가 하나뿐이면 화살표와 다음 wave 를 설명하지 않는다.
withRepo((repo) => {
  addRoot(repo, 'identity');
  addRoot(repo, 'platform');
  manifest(repo, { identity: [], platform: [] });
}, ({ body }) => {
  assert.match(body, /^### apply 순서: 루트 2개, wave 1개\n/);
  assert.match(body, /<sub>모든 루트가 wave0 이라 병렬로 apply 됩니다\.<\/sub>$/);
  assert.doesNotMatch(body, /화살표|-->/);
});

// depends_on 에 같은 루트를 두 번 적어도 화살표와 표 셀은 하나다.
withRepo((repo) => {
  addRoot(repo, 'a');
  addRoot(repo, 'b');
  manifest(repo, { a: [], b: ['a', 'a'] });
}, ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, '');
  assert.strictEqual(mermaidBlock(body).filter((l) => l === '  r0 --> r1').length, 1);
  assert.match(body, /\| 1 \| `b` \| `a` \|/);
});

// 하이픈 이름도 id 는 r<번호> 이고 라벨은 원래 이름이다.
withRepo((repo) => {
  addRoot(repo, 'platform/wazuh-logging');
  addRoot(repo, 'a--b');
  addRoot(repo, 'a/b');
  manifest(repo, { 'platform/wazuh-logging': [], 'a--b': [], 'a/b': ['a--b'] });
}, ({ body }) => {
  const lines = mermaidBlock(body);
  for (const line of lines) assert.ok(LINE_RE.some((re) => re.test(line)), `허용되지 않는 줄: ${line}`);
  assert.ok(lines.includes('    r2["platform/wazuh-logging"]'));
  assert.ok(lines.includes('    r0["a--b"]'));
  assert.ok(lines.includes('    r1["a/b"]'));
  assert.ok(lines.includes('  r0 --> r1'));
});

// 검증 실패: 그래프 없이 실패 사유만 적고 기존 코멘트만 갱신한다.
withRepo((repo) => {
  addRoot(repo, 'identity');
  addRoot(repo, 'platform/logging');
  manifest(repo, { identity: [] });
}, ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, 'true');
  assert.strictEqual(mermaidBlock(body), null);
  assert.match(body, /apply 순서를 계산하지 못했습니다/);
  assert.match(body, /- `platform\/logging: backend\.tf 는 있는데 \.github\/terraform-roots\.json 에 없다`/);
  assert.match(body, /<sub>.* · 1234567 · \[로그\]\(https:\/\/github\.com\/example\/infra\/actions\/runs\/1\)<\/sub>$/);
});

// 디렉터리 이름의 백틱은 코드 스팬을 닫아 HTML 이 살아나므로 바꿔 쓴다.
withRepo((repo) => {
  addRoot(repo, 'identity');
  addRoot(repo, 'x`</sub><b>y');
  manifest(repo, { identity: [] });
}, ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, 'true');
  assert.doesNotMatch(body, /x`/);
  assert.match(body, /- `x'<\/sub><b>y: backend\.tf 는 있는데/);
});

// constructor 같은 상속 속성 이름은 예외 없이 오류로 잡히거나(없는 의존) 정상 루트로 그려진다.
withRepo((repo) => {
  addRoot(repo, 'identity');
  manifest(repo, { identity: ['constructor'] });
}, ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, 'true');
  assert.match(body, /depends_on 의 constructor 이/);
});
withRepo((repo) => {
  addRoot(repo, 'constructor');
  addRoot(repo, 'identity');
  manifest(repo, { constructor: [], identity: ['constructor'] });
}, ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, '');
  assert.match(body, /^### apply 순서: 루트 2개, wave 2개\n/);
  assert.ok(mermaidBlock(body).includes('    r0["constructor"]'));
  assert.ok(mermaidBlock(body).includes('  r0 --> r1'));
});

// 매니페스트 형식 오류 메시지에 파일 경로가 두 번 붙지 않는다.
withRepo((repo) => {
  addRoot(repo, 'identity');
  fs.mkdirSync(path.join(repo, '.github'), { recursive: true });
  fs.writeFileSync(path.join(repo, roots.MANIFEST), JSON.stringify({ roots: [] }));
}, ({ body }) => {
  assert.match(body, /- `\.github\/terraform-roots\.json: "roots" 객체가 필요하다`/);
  assert.strictEqual((body.match(/terraform-roots\.json/g) || []).length, 2); // 오류 한 줄 + footer 문장
});

// 매니페스트가 없어도 본문은 나온다.
withRepo((repo) => addRoot(repo, 'identity'), ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, 'true');
  assert.match(body, /terraform-roots\.json/);
});

// 루트가 하나도 없으면 새 코멘트를 만들지 않는다.
withRepo((repo) => manifest(repo, {}), ({ body, onlyUpdate }) => {
  assert.strictEqual(onlyUpdate, 'true');
  assert.strictEqual(mermaidBlock(body), null);
  assert.match(body, /루트 모듈이 없어/);
});

// 매니페스트 키와 depends_on 순서가 달라도 본문은 같다 (skip_unchanged 가 의미를 가진다).
const bodies = [];
for (const entries of [
  { identity: [], platform: ['a', 'b'], b: [], a: [] },
  { a: [], b: [], platform: ['b', 'a'], identity: [] },
]) {
  withRepo((repo) => {
    Object.keys(entries).forEach((d) => addRoot(repo, d));
    manifest(repo, entries);
  }, ({ body }) => bodies.push(body));
}
assert.strictEqual(bodies[0], bodies[1]);

// 로컬 실행(환경 변수 없음)은 실패 본문에도 커밋·로그가 없다.
assert.deepStrictEqual(wave.metaFromEnv({}), { sha: '', runUrl: '' });
assert.deepStrictEqual(wave.metaFromEnv({
  GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: 'o/r', GITHUB_RUN_ID: '7', PR_HEAD_SHA: 'abc',
}), { sha: 'abc', runUrl: 'https://github.com/o/r/actions/runs/7' });
const localFail = wave.build({ roots: [], waves: [], deps: {}, errors: ['x: 문제'] }, {});
assert.doesNotMatch(localFail, /\]\(/);
assert.match(localFail, /<sub>\.github\/terraform-roots\.json 을 고치면 다음 커밋에서 다시 그립니다\.<\/sub>$/);

// analyze 가 예외를 던져도 실패 본문으로 바꾸고 기존 코멘트만 갱신한다.
const broken = wave.render('/nonexistent/repo/for/wave-comment-test', META);
assert.strictEqual(broken.onlyUpdate, 'true');
assert.match(broken.body, /계산하지 못했습니다/);
assert.match(broken.body, /- `tf-roots\.js: /);
