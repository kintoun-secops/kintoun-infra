'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const roots = require('./tf-roots');
const targets = require('./tf-targets');

function addRoot(repo, dir) {
  fs.mkdirSync(path.join(repo, dir), { recursive: true });
  fs.writeFileSync(
    path.join(repo, dir, 'backend.tf'),
    `terraform {\n  backend "s3" {\n    bucket = "b"\n    key    = "${dir}/terraform.tfstate"\n  }\n}\n`,
  );
}

function addFile(repo, file, text = '') {
  fs.mkdirSync(path.dirname(path.join(repo, file)), { recursive: true });
  fs.writeFileSync(path.join(repo, file), text);
}

function manifest(repo, entries) {
  const out = {};
  for (const [dir, deps] of Object.entries(entries)) out[dir] = { depends_on: deps };
  fs.writeFileSync(path.join(repo, roots.MANIFEST), JSON.stringify({ roots: out }));
}

// 실제 매니페스트와 같은 모양. victim 은 자식 모듈을 쓰고 그 모듈은 다른 모듈을 부른다.
function buildRepo(repo) {
  for (const d of [
    'identity',
    'platform',
    'platform/network',
    'platform/wazuh',
    'platform/victim',
    'bootstrap',
  ])
    addRoot(repo, d);
  manifest(repo, {
    identity: [],
    platform: ['platform/network', 'platform/wazuh'],
    'platform/network': [],
    'platform/wazuh': ['platform/network'],
    'platform/victim': ['platform/network', 'platform/wazuh'],
  });
  addFile(
    repo,
    'platform/victim/main.tf',
    [
      'module "logs" {',
      '  source = "../../modules/log-bucket/"',
      '}',
      'module "aws_only" {',
      '  source  = "terraform-aws-modules/vpc/aws"',
      '  version = "5.0.0"',
      '}',
    ].join('\n'),
  );
  addFile(repo, 'modules/log-bucket/main.tf', 'module "key" {\n  source = "../kms"\n}\n');
  addFile(repo, 'modules/kms/main.tf', '');
  addFile(repo, 'modules/unused/main.tf', '');
}

function withRepo(build, check) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'tf-targets-test-'));
  try {
    build(repo);
    check(repo);
  } finally {
    fs.rmSync(repo, { recursive: true, force: true });
  }
}

const ALL = ['identity', 'platform', 'platform/network', 'platform/victim', 'platform/wazuh'];

withRepo(buildRepo, (repo) => {
  const run = (changed, opts) => targets.select(repo, changed, opts);

  // 모듈 참조는 로컬 경로만 따라가고 모듈이 부르는 모듈도 포함한다.
  assert.deepStrictEqual(targets.localModules(repo, 'platform/victim'), ['modules/log-bucket']);
  assert.deepStrictEqual(targets.moduleClosure(repo, 'platform/victim'), [
    'modules/kms',
    'modules/log-bucket',
  ]);
  assert.deepStrictEqual(targets.moduleClosure(repo, 'identity'), []);

  // 중첩 루트의 파일은 가장 깊은 루트의 것이다.
  assert.strictEqual(targets.owningRoot(ALL, 'platform/network/main.tf'), 'platform/network');
  assert.strictEqual(targets.owningRoot(ALL, 'platform/main.tf'), 'platform');
  assert.strictEqual(targets.owningRoot(ALL, 'platform/wazuh/files/install.sh'), 'platform/wazuh');
  assert.strictEqual(targets.owningRoot(ALL, 'docs/index.md'), null);
  assert.strictEqual(targets.owningRoot(ALL, 'platformer/main.tf'), null);

  // 직접 변경 + depends_on 을 끝까지 따라간 소비 루트
  let r = run(['platform/network/main.tf']);
  assert.deepStrictEqual(r.errors, []);
  assert.deepStrictEqual(r.targets, [
    'platform',
    'platform/network',
    'platform/victim',
    'platform/wazuh',
  ]);
  assert.deepStrictEqual(r.skipped, ['identity']);
  assert.deepStrictEqual(r.reasons['platform/network'], ['직접 변경: platform/network/main.tf']);
  assert.deepStrictEqual(r.reasons['platform/wazuh'], ['의존: platform/network']);
  assert.deepStrictEqual(r.reasons.platform, ['의존: platform/network', '의존: platform/wazuh']);

  // 소비 루트가 없는 루트는 자기만 대상이다. 부모 디렉터리 루트의 변경은 자식 루트에 번지지 않는다.
  r = run(['platform/main.tf', 'identity/users.tf']);
  assert.deepStrictEqual(r.targets, ['identity', 'platform']);
  assert.deepStrictEqual(r.skipped, ['platform/network', 'platform/victim', 'platform/wazuh']);

  // 루트 아래 정적 파일도 그 루트의 변경이다.
  r = run(['platform/wazuh/files/install.sh']);
  assert.deepStrictEqual(r.targets, ['platform', 'platform/victim', 'platform/wazuh']);
  r = run(['platform/wazuh/files/template.md']);
  assert.deepStrictEqual(r.targets, ['platform', 'platform/victim', 'platform/wazuh']);
  r = run(['modules/kms/README.md']);
  assert.deepStrictEqual(r.targets, ['platform/victim']);

  // 자식 모듈이 바뀌면 그 모듈을 쓰는 루트가 대상이다. 모듈이 부르는 모듈도 같다.
  r = run(['modules/kms/main.tf']);
  assert.deepStrictEqual(r.targets, ['platform/victim']);
  assert.deepStrictEqual(r.reasons['platform/victim'], ['모듈 변경: modules/kms']);
  r = run(['modules/log-bucket/variables.tf']);
  assert.deepStrictEqual(r.targets, ['platform/victim']);
  assert.deepStrictEqual(r.reasons['platform/victim'], ['모듈 변경: modules/log-bucket']);

  // 아무 루트도 쓰지 않는 모듈, 문서와 별도 워크플로, bootstrap 은 대상이 없다.
  for (const files of [
    ['modules/unused/main.tf'],
    ['docs/ci/plan.md', 'mkdocs.yml', 'README.md'],
    ['bootstrap/oidc.tf'],
    [
      '.github/workflows/docs.yml',
      '.github/workflows/terraform-apply.yml',
      '.github/dependabot.yml',
    ],
    [],
    ['', '  '],
  ]) {
    r = run(files);
    assert.deepStrictEqual(r.targets, [], JSON.stringify(files));
    assert.deepStrictEqual(r.skipped, ALL);
  }

  // 영향 범위를 확정할 수 없는 파일은 전체가 대상이다.
  for (const file of [
    '.github/workflows/terraform-plan.yml',
    '.github/workflows/_tf-root.yml',
    '.github/scripts/tf-roots.js',
    '.github/policy/iam.rego',
  ]) {
    r = run(['docs/index.md', file]);
    assert.deepStrictEqual(r.targets, ALL, file);
    assert.deepStrictEqual(r.skipped, []);
    assert.deepStrictEqual(r.reasons.identity, [`전체 대상: ${file}`]);
  }
  r = run(['terraform-roots.json']);
  assert.deepStrictEqual(r.targets, ALL);
  assert.match(r.reasons.identity[0], /기준 매니페스트/);
  r = run(['identity/users.tf'], { all: true });
  assert.deepStrictEqual(r.targets, ALL);
  assert.match(r.reasons.identity[0], /^전체 대상: /);
  r = run(['shared/config.yaml']);
  assert.deepStrictEqual(r.targets, ALL);
  assert.match(r.reasons.identity[0], /영향 범위를 알 수 없는 파일/);

  // 이름이 바뀐 파일은 이전 경로와 새 경로가 모두 들어온다. 중복 경로는 한 번만 센다.
  r = run(['identity/x.tf', 'platform/wazuh/x.tf', 'identity/x.tf']);
  assert.deepStrictEqual(r.targets, ['identity', 'platform', 'platform/victim', 'platform/wazuh']);
  assert.deepStrictEqual(r.reasons.identity, ['직접 변경: identity/x.tf']);

  const body = targets.table(run(['identity/users.tf']));
  assert.match(body, /\| `identity` \| 실행 \| 직접 변경: identity\/users\.tf \|/);
  assert.match(body, /\| `platform\/network` \| 생략 \| 변경 영향 없음 \|/);
});

// 한 줄 HCL 과 JSON 구성도 Terraform 이 지원하는 모듈 선언이다.
for (const [file, content] of [
  ['main.tf', 'module "key" { source = "../modules/kms" }\n'],
  ['main.tf', 'module "key" { source /* 경로 */ = "../modules/kms" }\n'],
  ['main.tf.json', JSON.stringify({ module: { key: { source: '../modules/kms' } } })],
  ['main.tf.json', JSON.stringify({ module: [{ key: [{ source: '../modules/kms' }] }] })],
]) {
  withRepo(
    (repo) => {
      buildRepo(repo);
      addFile(repo, `identity/${file}`, content);
    },
    (repo) => {
      assert.deepStrictEqual(
        targets.select(repo, ['modules/kms/main.tf']).targets,
        ['identity', 'platform/victim'],
        file,
      );
    },
  );
}

// 식으로 된 source 는 경로를 추측하지 않는다. 문서만 바뀌면 여전히 plan 을 생략한다.
for (const [file, content] of [
  ['main.tf', 'module "key" { source = var.module_source }\n'],
  ['main.tf', 'module "key" { source = "${var.module_source}" }\n'],
  [
    'main.tf',
    'module "key" { source = "a" == var.choice ? "../modules/kms" : "../modules/unused" }\n',
  ],
  ['main.tf.json', JSON.stringify({ module: { key: { source: '${var.module_source}' } } })],
  ['main.tf.json', 'not json'],
]) {
  withRepo(
    (repo) => {
      buildRepo(repo);
      addFile(repo, `identity/${file}`, content);
    },
    (repo) => {
      assert.deepStrictEqual(targets.select(repo, ['modules/kms/main.tf']).targets, ALL, file);
      assert.deepStrictEqual(targets.select(repo, ['docs/ci/plan.md']).targets, [], file);
    },
  );
}

// 모듈 외 블록의 source 가 파일을 가리켜도 디렉터리로 읽다가 실패하지 않는다.
withRepo(
  (repo) => {
    buildRepo(repo);
    addFile(
      repo,
      'identity/main.tf',
      'resource "aws_s3_object" "x" { source = "./files/object.txt" }\n',
    );
    addFile(repo, 'identity/files/object.txt', 'payload');
  },
  (repo) => {
    assert.deepStrictEqual(targets.select(repo, ['identity/files/object.txt']).targets, [
      'identity',
    ]);
  },
);

// 매니페스트 검증에 실패하면 대상을 고르지 않는다. 워크플로는 tf-roots.js 단계에서 먼저 멈춘다.
withRepo(
  (repo) => {
    addRoot(repo, 'identity');
    addRoot(repo, 'platform/logging');
    manifest(repo, { identity: [] });
  },
  (repo) => {
    const r = targets.select(repo, ['identity/users.tf']);
    assert.ok(r.errors.length > 0);
    assert.deepStrictEqual(r.targets, []);
    assert.deepStrictEqual(r.skipped, []);
  },
);

// 저장소 밖을 가리키는 source 와 없는 디렉터리는 무시한다.
withRepo(
  (repo) => {
    addRoot(repo, 'identity');
    manifest(repo, { identity: [] });
    addFile(
      repo,
      'identity/main.tf',
      'module "x" {\n  source = "../../outside"\n}\nmodule "y" {\n  source = "./missing"\n}\n',
    );
  },
  (repo) => {
    assert.deepStrictEqual(targets.localModules(repo, 'identity'), ['identity/missing']);
    assert.deepStrictEqual(targets.moduleClosure(repo, 'identity'), ['identity/missing']);
    assert.deepStrictEqual(targets.select(repo, ['identity/missing/main.tf']).targets, [
      'identity',
    ]);
  },
);

// 매니페스트는 JSON 포맷·주석·순서가 아니라 루트와 의존 관계를 비교한다.
withRepo(buildRepo, (repo) => {
  const baseManifest = JSON.parse(fs.readFileSync(path.join(repo, roots.MANIFEST), 'utf8'));
  baseManifest.$comment = '이전 설명';
  for (const entry of Object.values(baseManifest.roots)) entry.depends_on.reverse();
  assert.deepStrictEqual(targets.select(repo, [roots.MANIFEST], { baseManifest }).targets, []);

  const added = structuredClone(baseManifest);
  delete added.roots['platform/victim'];
  assert.deepStrictEqual(targets.select(repo, [roots.MANIFEST], { baseManifest: added }).targets, [
    'platform/victim',
  ]);

  const changed = structuredClone(baseManifest);
  changed.roots['platform/wazuh'].depends_on = [];
  assert.deepStrictEqual(
    targets.select(repo, [roots.MANIFEST], { baseManifest: changed }).targets,
    ['platform', 'platform/victim', 'platform/wazuh'],
  );

  const removed = structuredClone(baseManifest);
  removed.roots['platform/old'] = { depends_on: [] };
  assert.deepStrictEqual(
    targets.select(repo, [roots.MANIFEST], { baseManifest: removed }).targets,
    ALL,
  );
  assert.deepStrictEqual(
    targets.select(repo, [roots.MANIFEST], { baseManifest: { roots: [] } }).targets,
    ALL,
  );
});

// PR #35: 로깅 루트 추가와 victim 파일 변경은 생산자인 Wazuh 의 plan 을 요구하지 않는다.
withRepo(
  (repo) => {
    buildRepo(repo);
    const base = JSON.parse(fs.readFileSync(path.join(repo, roots.MANIFEST), 'utf8'));
    addFile(repo, 'base-roots.json', JSON.stringify(base));
    for (const dir of ['wazuh-logging/guardduty', 'wazuh-logging/waf-log']) addRoot(repo, dir);
    base.roots['wazuh-logging/guardduty'] = { depends_on: ['platform/wazuh'] };
    base.roots['wazuh-logging/waf-log'] = { depends_on: ['platform/wazuh', 'platform/victim'] };
    addFile(repo, roots.MANIFEST, JSON.stringify(base));
  },
  (repo) => {
    const baseManifest = JSON.parse(fs.readFileSync(path.join(repo, 'base-roots.json'), 'utf8'));
    const r = targets.select(
      repo,
      [
        roots.MANIFEST,
        'platform/victim/waf.tf',
        'wazuh-logging/guardduty/main.tf',
        'wazuh-logging/waf-log/main.tf',
      ],
      { baseManifest },
    );
    assert.deepStrictEqual(r.targets, [
      'platform/victim',
      'wazuh-logging/guardduty',
      'wazuh-logging/waf-log',
    ]);
    assert.deepStrictEqual(r.skipped, [
      'identity',
      'platform',
      'platform/network',
      'platform/wazuh',
    ]);
  },
);
