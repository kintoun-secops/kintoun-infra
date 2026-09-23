'use strict';
// 루트 모듈을 발견하고 검증하고 apply 순서(wave)를 계산한다.
// 표식은 backend.tf 다 — 1 디렉터리 = 1 state = 1 apply 단위.
// 발견 결과는 terraform-roots.json 과 일치해야 한다. 다르면 실패한다 (조용히 빠지는 루트가 없도록).
// 워크플로의 discover 잡, lint 잡, plan-summary.js, wave-comment.js 가 함께 쓴다. 의존 패키지 없음.

const fs = require('fs');
const path = require('path');

const MANIFEST = 'terraform-roots.json';
const SKIP_DIRS = new Set(['.terraform', 'node_modules', 'modules']);
const EXCLUDED_ROOTS = new Set(['bootstrap', 'service-db-init']); // 사람이 로컬에서 apply 한다
// 소문자·숫자·하이픈, 깊이 2 이하. bootstrap/oidc.tf 의 state 글롭(*/terraform.tfstate)과 한 쌍이다.
const NAME_RE = /^[a-z0-9][a-z0-9-]*(\/[a-z0-9][a-z0-9-]*)?$/;

// 아티팩트 이름에는 / 를 쓸 수 없다 (actions/upload-artifact). platform/network -> platform__network
const toSlug = (dir) => dir.replace(/\//g, '__');

function scan(repoRoot) {
  const found = [];
  const walk = (rel) => {
    const entries = fs.readdirSync(path.join(repoRoot, rel), { withFileTypes: true });
    if (rel && entries.some((e) => e.isFile() && e.name === 'backend.tf')) found.push(rel);
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith('.') || SKIP_DIRS.has(e.name)) continue;
      walk(rel ? `${rel}/${e.name}` : e.name);
    }
  };
  walk('');
  return found.filter((d) => !EXCLUDED_ROOTS.has(d)).sort();
}

function loadManifest(repoRoot) {
  const raw = JSON.parse(fs.readFileSync(path.join(repoRoot, MANIFEST), 'utf8'));
  if (!raw || typeof raw.roots !== 'object' || Array.isArray(raw.roots)) {
    throw new Error('"roots" 객체가 필요하다');
  }
  return raw.roots;
}

function backendKey(repoRoot, dir) {
  const text = fs.readFileSync(path.join(repoRoot, dir, 'backend.tf'), 'utf8');
  const m = text.match(/^\s*key\s*=\s*"([^"]*)"/m);
  return m ? m[1] : null;
}

// constructor 처럼 Object 의 상속 속성과 겹치는 이름이 있어도 매니페스트에 적힌 키만 인정한다 (in 연산자 금지).
const declaredIn = (manifest, d) => Object.hasOwn(manifest, d);

function validate(repoRoot, scanned, manifest) {
  const errors = [];
  const declared = Object.keys(manifest);
  for (const d of scanned) {
    if (!declaredIn(manifest, d)) errors.push(`${d}: backend.tf 는 있는데 ${MANIFEST} 에 없다`);
  }
  for (const d of declared) {
    if (!scanned.includes(d)) errors.push(`${d}: ${MANIFEST} 에는 있는데 backend.tf 가 없다`);
    if (!NAME_RE.test(d)) errors.push(`${d}: 이름 규칙 위반 (소문자·숫자·하이픈, 깊이 2 이하)`);
    const entry = manifest[d];
    if (!entry || typeof entry !== 'object') {
      errors.push(`${d}: 항목은 객체여야 한다`);
      continue;
    }
    const extra = Object.keys(entry).filter((k) => k !== 'depends_on');
    if (extra.length) errors.push(`${d}: 허용되지 않는 필드 ${extra.join(', ')}`);
    const deps = entry.depends_on;
    if (!Array.isArray(deps)) {
      errors.push(`${d}: depends_on 은 배열이어야 한다`);
      continue;
    }
    for (const dep of deps) {
      if (dep === d) errors.push(`${d}: 자기 자신에 의존한다`);
      else if (!declaredIn(manifest, dep))
        errors.push(`${d}: depends_on 의 ${dep} 이 ${MANIFEST} 에 없다`);
    }
  }
  for (const d of scanned) {
    const key = backendKey(repoRoot, d);
    const expected = `${d}/terraform.tfstate`;
    if (key === null) errors.push(`${d}/backend.tf: key 를 찾을 수 없다`);
    else if (key !== expected)
      errors.push(`${d}/backend.tf: key 가 "${key}" 인데 "${expected}" 이어야 한다`);
  }
  return errors;
}

// depends_on 그래프를 깊이별로 나눈다. wave0 은 의존이 없는 루트, wave1 은 wave0 에만 의존하는 루트 ...
function waves(manifest) {
  const errors = [];
  const level = Object.create(null);
  const visiting = new Set();
  const depth = (d, trail) => {
    if (d in level) return level[d];
    if (visiting.has(d)) {
      errors.push(`순환 의존: ${[...trail, d].join(' -> ')}`);
      return 0;
    }
    visiting.add(d);
    let l = 0;
    for (const dep of manifest[d] && Array.isArray(manifest[d].depends_on)
      ? manifest[d].depends_on
      : []) {
      if (declaredIn(manifest, dep) && dep !== d) l = Math.max(l, depth(dep, [...trail, d]) + 1);
    }
    visiting.delete(d);
    level[d] = l;
    return l;
  };
  for (const d of Object.keys(manifest)) depth(d, []);

  const maxLevel = Object.values(level).length ? Math.max(...Object.values(level)) : 0;
  const out = Array.from({ length: maxLevel + 1 }, () => []);
  for (const [d, l] of Object.entries(level)) {
    out[l].push(d);
  }
  for (const w of out) w.sort();
  return { waves: out, errors: [...new Set(errors)] };
}

function analyze(repoRoot) {
  const scanned = scan(repoRoot);
  let manifest;
  try {
    manifest = loadManifest(repoRoot);
  } catch (e) {
    return { roots: scanned, waves: [], deps: {}, errors: [`${MANIFEST}: ${e.message}`] };
  }
  const roots = Object.keys(manifest).sort();
  const w = waves(manifest);
  const errors = [...validate(repoRoot, scanned, manifest), ...w.errors];
  // 오류가 없는데 wave 에서 빠진 루트가 있으면 apply 에서 조용히 빠진다. 여기서 실패시킨다.
  if (!errors.length && w.waves.flat().length !== roots.length) {
    errors.push('wave 계산 결과가 루트 목록과 다르다 (tf-roots.js 결함)');
  }
  // deps 는 wave-comment.js 가 화살표를 그리는 데 쓴다. 중복을 걷고 정렬해 같은 매니페스트면 같은 본문이 나온다.
  const deps = {};
  for (const d of roots) {
    const entry = manifest[d];
    deps[d] = entry && Array.isArray(entry.depends_on) ? [...new Set(entry.depends_on)].sort() : [];
  }
  return { roots, waves: w.waves, deps, errors };
}

function main(argv) {
  const rootIdx = argv.indexOf('--root');
  const repoRoot =
    rootIdx >= 0 ? path.resolve(argv[rootIdx + 1]) : path.resolve(__dirname, '..', '..');
  const slugIdx = argv.indexOf('--slug');
  if (slugIdx >= 0) {
    process.stdout.write(`${toSlug(argv[slugIdx + 1] ?? '')}\n`);
    return 0;
  }

  const result = analyze(repoRoot);
  if (result.errors.length) {
    for (const e of result.errors) process.stderr.write(`::error::${e}\n`);
    return 1;
  }

  if (argv.includes('--list')) {
    process.stdout.write(result.roots.map((r) => `${r}\n`).join(''));
  } else if (argv.includes('--github-output')) {
    const lines = [`roots=${JSON.stringify(result.roots)}`];
    result.waves.forEach((w, i) => lines.push(`wave${i}=${JSON.stringify(w)}`));
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `${lines.join('\n')}\n`);
    process.stdout.write(`${lines.join('\n')}\n`);
  } else {
    process.stdout.write(
      `${JSON.stringify({ roots: result.roots, waves: result.waves }, null, 2)}\n`,
    );
  }
  return 0;
}

module.exports = { MANIFEST, NAME_RE, toSlug, scan, validate, waves, analyze };

if (require.main === module) process.exitCode = main(process.argv.slice(2));
