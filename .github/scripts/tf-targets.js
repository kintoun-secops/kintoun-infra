'use strict';
// PR 의 변경 파일로 plan 할 루트를 고른다. 루트 목록과 의존 관계는 tf-roots.js 의 결과를 쓴다.
// 루트 디렉터리 안의 파일이 바뀌면 그 루트, 그 루트를 depends_on 으로 읽는 루트도 함께 대상이다.
// 루트가 source 로 참조하는 로컬 모듈이 바뀌면 그 모듈을 쓰는 루트가 대상이다.
// 매니페스트는 기준 브랜치와 비교한다. 공통 CI 구성처럼 영향 범위를 확정할 수 없는 변경은 전체가 대상이다.
// validate 대상은 plan 대상에 bootstrap 을 더한 것이다. bootstrap 은 plan 하지 않지만 그 파일이나
// 참조 모듈이 바뀌면 validate 한다. 전체 대상이면 bootstrap 도 포함한다.
// 워크플로의 discover 잡이 쓴다. 모듈 참조 조회에는 terraform-config-inspect 가 필요하다.

const fs = require('fs');
const path = require('path');

const { analyze, MANIFEST } = require('./tf-roots');
const { moduleSources } = require('./tf-module-sources');

// 바뀌면 전체 루트를 plan 한다. 끝이 / 인 항목은 그 아래 전체다.
const FULL_PLAN_PATHS = [
  '.github/workflows/terraform-plan.yml',
  '.github/workflows/_tf-root.yml',
  '.github/scripts/',
  '.github/actions/',
  '.github/policy/',
];
// 루트와 참조 모듈 밖에서만 제외한다. 루트 안의 문서도 file/templatefile 입력일 수 있다.
const IGNORED_PATHS = [
  'docs/',
  'bootstrap/',
  'README.md',
  'mkdocs.yml',
  'requirements-docs.txt',
  '.github/ISSUE_TEMPLATE/',
  '.github/pull_request_template.md',
  '.github/dependabot.yml',
  '.github/workflows/docs.yml',
  '.github/workflows/terraform-apply.yml',
];

const BOOTSTRAP = 'bootstrap';

const under = (file, dir) => file === dir || file.startsWith(`${dir}/`);

function matchesPath(file, paths) {
  return paths.find((p) => (p.endsWith('/') ? file.startsWith(p) : file === p)) ?? null;
}

function localModules(repoRoot, dir) {
  return moduleSources(repoRoot, dir).local;
}

// 루트가 직접 또는 간접으로 쓰는 모듈 디렉터리 전체. 모듈이 다른 모듈을 부르는 경우도 따라간다.
function moduleGraph(repoRoot, root) {
  const seen = new Set();
  const queue = [root];
  let uncertain = false;
  while (queue.length) {
    const dir = queue.shift();
    const sources = moduleSources(repoRoot, dir);
    uncertain ||= sources.uncertain;
    for (const m of sources.local) {
      if (!seen.has(m)) {
        seen.add(m);
        queue.push(m);
      }
    }
  }
  seen.delete(root);
  return { local: [...seen].sort(), uncertain };
}

function moduleClosure(repoRoot, root) {
  return moduleGraph(repoRoot, root).local;
}

// 파일을 담는 가장 깊은 루트. platform/network/main.tf 는 platform 이 아니라 platform/network 다.
function owningRoot(roots, file) {
  return [...roots].sort((a, b) => b.length - a.length).find((r) => under(file, r)) ?? null;
}

// depends_on 의 역방향. 영향 받은 루트를 읽는 루트를 끝까지 따라간다.
function dependents(deps, seeds, reasons) {
  const consumers = {};
  for (const [d, on] of Object.entries(deps)) {
    for (const dep of on) (consumers[dep] ??= []).push(d);
  }
  const queue = [...seeds];
  const out = new Set(seeds);
  while (queue.length) {
    const dep = queue.shift();
    for (const d of (consumers[dep] ?? []).sort()) {
      addReason(reasons, d, `의존: ${dep}`);
      if (!out.has(d)) {
        out.add(d);
        queue.push(d);
      }
    }
  }
  return out;
}

function addReason(reasons, root, reason) {
  const list = (reasons[root] ??= []);
  if (!list.includes(reason)) list.push(reason);
}

// changed 는 저장소 기준 상대 경로 목록이다. 이름이 바뀐 파일은 이전 경로도 함께 넣는다.
// all 이 true 면 목록과 무관하게 전체 루트를 대상으로 한다 (변경 파일 목록을 확정할 수 없을 때).
function select(repoRoot, changed, { all = false, baseManifest } = {}) {
  const result = analyze(repoRoot);
  if (result.errors.length)
    return { ...result, targets: [], skipped: [], validate: [], reasons: {} };
  const { roots, deps } = result;
  const reasons = {};
  const hasBootstrap = fs.existsSync(path.join(repoRoot, BOOTSTRAP, 'backend.tf'));
  const withValidate = (targets, bootstrap) => ({
    ...result,
    targets,
    skipped: roots.filter((r) => !targets.includes(r)),
    validate: [...(hasBootstrap && bootstrap ? [BOOTSTRAP] : []), ...targets],
    reasons,
  });
  const everything = (why) => {
    for (const r of roots) addReason(reasons, r, why);
    if (hasBootstrap) addReason(reasons, BOOTSTRAP, why);
    return withValidate([...roots], true);
  };
  if (all) return everything('전체 대상: 변경 파일 목록을 확정할 수 없다');

  const files = [...new Set(changed.map((f) => f.trim()).filter(Boolean))].sort();
  for (const f of files) {
    const hit = matchesPath(f, FULL_PLAN_PATHS);
    if (hit) return everything(`전체 대상: ${f}`);
  }

  // bootstrap 은 IGNORED_PATHS 라 plan 대상이 아니지만, 그 파일과 참조 모듈 변경은 validate 로 잡는다.
  let bootstrap = false;
  if (hasBootstrap) {
    const bootstrapModules = moduleGraph(repoRoot, BOOTSTRAP).local;
    for (const f of files) {
      if (under(f, BOOTSTRAP)) {
        bootstrap = true;
        addReason(reasons, BOOTSTRAP, `직접 변경: ${f}`);
      }
      const m = bootstrapModules.find((dir) => under(f, dir));
      if (m) {
        bootstrap = true;
        addReason(reasons, BOOTSTRAP, `모듈 변경: ${m}`);
      }
    }
  }

  const direct = new Set();
  if (files.includes(MANIFEST)) {
    const base = baseManifest?.roots;
    if (
      !base ||
      typeof base !== 'object' ||
      Array.isArray(base) ||
      Object.values(base).some(
        (entry) =>
          !Array.isArray(entry?.depends_on) ||
          entry.depends_on.some((dep) => typeof dep !== 'string'),
      )
    ) {
      return everything('전체 대상: 기준 매니페스트를 확인할 수 없다');
    }
    if (Object.keys(base).some((r) => !roots.includes(r)))
      return everything('전체 대상: 매니페스트에서 루트가 제거되었다');
    for (const r of roots) {
      const before = Object.hasOwn(base, r) ? [...new Set(base[r].depends_on)].sort() : null;
      if (JSON.stringify(before) !== JSON.stringify([...new Set(deps[r])].sort())) {
        direct.add(r);
        addReason(reasons, r, '매니페스트: 루트 추가 또는 의존 관계 변경');
      }
    }
  }

  const modules = {};
  for (const r of roots) modules[r] = moduleGraph(repoRoot, r);

  for (const f of files) {
    if (f === MANIFEST) continue;
    const owner = owningRoot(roots, f);
    if (owner) {
      direct.add(owner);
      addReason(reasons, owner, `직접 변경: ${f}`);
    }
    let moduleMatch = false;
    for (const r of roots) {
      const m = modules[r].local.find((dir) => under(f, dir));
      if (m) {
        moduleMatch = true;
        direct.add(r);
        addReason(reasons, r, `모듈 변경: ${m}`);
      }
    }
    if (!owner && !moduleMatch && matchesPath(f, IGNORED_PATHS)) continue;
    if (roots.some((r) => modules[r].uncertain))
      return everything('전체 대상: 모듈 source 를 정적 경로로 확정할 수 없다');
    if (!owner && !moduleMatch && !under(f, 'modules'))
      return everything(`전체 대상: 영향 범위를 알 수 없는 파일 ${f}`);
  }

  const affected = dependents(deps, [...direct].sort(), reasons);
  return withValidate(
    roots.filter((r) => affected.has(r)),
    bootstrap,
  );
}

function readChanged(argv) {
  const idx = argv.indexOf('--changed');
  const text = idx >= 0 ? fs.readFileSync(argv[idx + 1], 'utf8') : fs.readFileSync(0, 'utf8');
  return text.split(/\r?\n/);
}

function table({ targets, skipped, validate, reasons }) {
  const rows = ['| 루트 | plan | validate | 사유 |', '| --- | --- | --- | --- |'];
  for (const r of targets) rows.push(`| \`${r}\` | 실행 | 실행 | ${reasons[r].join(', ')} |`);
  for (const r of skipped) rows.push(`| \`${r}\` | 생략 | 생략 | 변경 영향 없음 |`);
  if (validate.includes(BOOTSTRAP))
    rows.push(`| \`${BOOTSTRAP}\` | 대상 아님 | 실행 | ${reasons[BOOTSTRAP].join(', ')} |`);
  return rows.join('\n');
}

function main(argv, env) {
  const rootIdx = argv.indexOf('--root');
  const repoRoot =
    rootIdx >= 0 ? path.resolve(argv[rootIdx + 1]) : path.resolve(__dirname, '..', '..');
  const all = argv.includes('--all');
  const baseIdx = argv.indexOf('--base-manifest');
  const baseManifest =
    baseIdx >= 0 ? JSON.parse(fs.readFileSync(argv[baseIdx + 1], 'utf8')) : undefined;
  const result = select(repoRoot, all ? [] : readChanged(argv), { all, baseManifest });
  if (result.errors.length) {
    for (const e of result.errors) process.stderr.write(`::error::${e}\n`);
    return 1;
  }

  const body = table(result);
  if (argv.includes('--github-output')) {
    const lines = [
      `targets=${JSON.stringify(result.targets)}`,
      `skipped=${JSON.stringify(result.skipped)}`,
      `validate=${JSON.stringify(result.validate)}`,
    ];
    fs.appendFileSync(env.GITHUB_OUTPUT, `${lines.join('\n')}\n`);
    process.stdout.write(`${lines.join('\n')}\n`);
    if (env.GITHUB_STEP_SUMMARY) {
      fs.appendFileSync(
        env.GITHUB_STEP_SUMMARY,
        `## plan 대상: ${result.targets.length}/${result.roots.length}, validate 대상: ${result.validate.length}\n\n${body}\n\n`,
      );
    }
  } else {
    process.stdout.write(`${body}\n`);
  }
  return 0;
}

module.exports = {
  BOOTSTRAP,
  FULL_PLAN_PATHS,
  IGNORED_PATHS,
  localModules,
  moduleClosure,
  owningRoot,
  select,
  table,
};

if (require.main === module) process.exitCode = main(process.argv.slice(2), process.env);
