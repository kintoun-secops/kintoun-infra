'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const roots = require('./tf-roots');

function withRepo(build, check) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'tf-roots-test-'));
  try {
    build(repo);
    check(roots.analyze(repo));
  } finally {
    fs.rmSync(repo, { recursive: true, force: true });
  }
}

function addRoot(repo, dir, key = `${dir}/terraform.tfstate`) {
  fs.mkdirSync(path.join(repo, dir), { recursive: true });
  fs.writeFileSync(
    path.join(repo, dir, 'backend.tf'),
    `terraform {\n  backend "s3" {\n    bucket = "b"\n    key    = "${key}"\n  }\n}\n`,
  );
}

function manifest(repo, entries) {
  const out = {};
  for (const [dir, deps] of Object.entries(entries)) out[dir] = { depends_on: deps };
  fs.mkdirSync(path.join(repo, '.github'), { recursive: true });
  fs.writeFileSync(path.join(repo, roots.MANIFEST), JSON.stringify({ roots: out }));
}

const errorsMatching = (result, re) => result.errors.filter((e) => re.test(e));

// 정상: 의존 깊이에 따라 wave 가 나뉘고, bootstrap·modules·.terraform 은 무시된다.
withRepo(
  (repo) => {
    addRoot(repo, 'identity');
    addRoot(repo, 'platform/network');
    addRoot(repo, 'platform/wazuh');
    addRoot(repo, 'platform/access');
    addRoot(repo, 'platform');
    addRoot(repo, 'bootstrap');
    addRoot(repo, 'modules/vpc');
    addRoot(repo, 'platform/.terraform/modules/x');
    manifest(repo, {
      identity: [],
      'platform/network': [],
      'platform/wazuh': ['platform/network'],
      'platform/access': ['platform/wazuh'],
      platform: ['platform/network', 'platform/wazuh', 'platform/access'],
    });
  },
  (r) => {
    assert.deepStrictEqual(r.errors, []);
    assert.deepStrictEqual(r.roots, [
      'identity',
      'platform',
      'platform/access',
      'platform/network',
      'platform/wazuh',
    ]);
    assert.deepStrictEqual(r.waves, [
      ['identity', 'platform/network'],
      ['platform/wazuh'],
      ['platform/access'],
      ['platform'],
    ]);
    assert.deepStrictEqual(r.deps.platform, [
      'platform/access',
      'platform/network',
      'platform/wazuh',
    ]);
  },
);

// 디스크에만 있는 루트 (upstream guardduty 브랜치가 빠뜨린 경우)
withRepo(
  (repo) => {
    addRoot(repo, 'identity');
    addRoot(repo, 'platform/logging');
    manifest(repo, { identity: [] });
  },
  (r) => {
    assert.strictEqual(errorsMatching(r, /^platform\/logging: backend\.tf 는 있는데/).length, 1);
  },
);

// 매니페스트에만 있는 루트
withRepo(
  (repo) => {
    addRoot(repo, 'identity');
    manifest(repo, { identity: [], 'lab/victim': [] });
  },
  (r) => {
    assert.strictEqual(errorsMatching(r, /^lab\/victim: .* backend\.tf 가 없다/).length, 1);
  },
);

// state key 가 디렉터리 경로와 다르면 실패
withRepo(
  (repo) => {
    addRoot(repo, 'platform/logging', 'platform/logging/guardduty/terraform.tfstate');
    manifest(repo, { 'platform/logging': [] });
  },
  (r) => {
    assert.strictEqual(
      errorsMatching(r, /key 가 "platform\/logging\/guardduty\/terraform\.tfstate" 인데/).length,
      1,
    );
  },
);

// 깊이 3 이름과 대문자는 거부
withRepo(
  (repo) => {
    addRoot(repo, 'platform/wazuh-logging/guardduty');
    addRoot(repo, 'Lab');
    manifest(repo, { 'platform/wazuh-logging/guardduty': [], Lab: [] });
  },
  (r) => {
    assert.strictEqual(errorsMatching(r, /이름 규칙 위반/).length, 2);
  },
);

// 순환 의존과 없는 의존 대상
withRepo(
  (repo) => {
    addRoot(repo, 'a');
    addRoot(repo, 'b');
    manifest(repo, { a: ['b'], b: ['a', 'zzz'] });
  },
  (r) => {
    assert.strictEqual(errorsMatching(r, /순환 의존/).length, 1);
    assert.strictEqual(errorsMatching(r, /b: depends_on 의 zzz/).length, 1);
  },
);

// 매니페스트가 없거나 깨졌을 때
withRepo(
  (repo) => {
    addRoot(repo, 'identity');
  },
  (r) => {
    assert.strictEqual(errorsMatching(r, /terraform-roots\.json/).length, 1);
  },
);
