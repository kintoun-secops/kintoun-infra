'use strict';
// IAM·KMS 가드의 위험 판정을 PR diff 의 리소스 블록 줄에 리뷰 코멘트로 단다.
// 전체 목록은 iam-guard·kms-guard 표가 맡고, 여기는 diff 에 블록이 있는 판정만 다룬다.
// 소스 위치는 plan JSON 에 없으므로 terraform-config-inspect 의 리소스 위치를 쓴다.
const path = require('path');
const { spawnSync } = require('child_process');
const { gather } = require('./plan-summary');

const MARKER = '<!-- guard-line-comment -->';
const GUARD = { 'terraform.kms': 'KMS 가드' };

function defaultInspect(repoRoot, dir) {
  const result = spawnSync('terraform-config-inspect', ['--json', dir], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  if (result.error || result.status !== 0) return null;
  try {
    return JSON.parse(result.stdout);
  } catch {
    return null;
  }
}

// diff hunk 에 들어 있는 새 파일 쪽 줄 번호. 리뷰 코멘트는 이 줄에만 달 수 있다.
function diffLines(patch) {
  const lines = new Set();
  if (typeof patch !== 'string') return lines;
  let current = 0;
  for (const line of patch.split('\n')) {
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(line);
    if (hunk) {
      current = Number(hunk[1]);
      continue;
    }
    if (line.startsWith('-') || line.startsWith('\\')) continue;
    lines.add(current);
    current += 1;
  }
  return lines;
}

// module.a["k"].aws_x.y[0] → { modules: ['a'], key: 'aws_x.y' }. 인덱스 키는 위치와 무관하다.
function parseAddress(address) {
  const parts = address.replace(/\[[^\]]*\]/g, '').split('.');
  const modules = [];
  while (parts.length >= 2 && parts[0] === 'module') {
    modules.push(parts[1]);
    parts.splice(0, 2);
  }
  if (parts[0] === 'data' && parts.length === 3) return { modules, key: parts.join('.') };
  if (parts.length === 2) return { modules, key: parts.join('.') };
  return null;
}

// 루트와 그 로컬 모듈의 리소스 위치. 모듈 경로는 module_calls 의 source 로 따라간다.
function resourceMap(config, repoRoot) {
  const out = new Map();
  for (const group of [config.managed_resources, config.data_resources]) {
    for (const [key, res] of Object.entries(group ?? {})) {
      const filename = res?.pos?.filename;
      const line = res?.pos?.line;
      if (typeof filename !== 'string' || !Number.isInteger(line)) continue;
      const file = path.isAbsolute(filename) ? path.relative(repoRoot, filename) : filename;
      out.set(key, { path: file.split(path.sep).join('/'), line });
    }
  }
  return out;
}

function locate(findings, inspect, repoRoot) {
  const configs = new Map();
  const inspectOnce = (dir) => {
    if (!configs.has(dir)) configs.set(dir, inspect(repoRoot, dir));
    return configs.get(dir);
  };
  const resolve = (dir, modules) => {
    const config = inspectOnce(dir);
    if (!config) return null;
    if (!modules.length) return resourceMap(config, repoRoot);
    const source = config.module_calls?.[modules[0]]?.source;
    if (typeof source !== 'string' || !/^\.\.?\//.test(source)) return null;
    const next = path.posix.normalize(path.posix.join(dir, source));
    if (next.startsWith('..')) return null;
    return resolve(next, modules.slice(1));
  };
  return findings.map((f) => {
    const parsed = f.address ? parseAddress(f.address) : null;
    const map = parsed ? resolve(f.dir, parsed.modules) : null;
    return { ...f, pos: map?.get(parsed.key) ?? null };
  });
}

function body(findings) {
  const blocks = findings.map((f) => `**${f.guard} · 위험** ${f.text}\n\n${f.why}`.trim());
  return [MARKER, ...blocks, '<sub>전체 목록은 IAM 가드와 KMS 가드 코멘트에 있습니다.</sub>'].join(
    '\n\n',
  );
}

module.exports = async ({
  github,
  context,
  core,
  findingsDir,
  repoRoot,
  expectedDirs,
  skippedDirs,
  inspect = defaultInspect,
}) => {
  const pr = context.payload.pull_request;
  if (!pr) return;
  const repo = context.repo;
  const pull_number = pr.number;

  const found = [];
  for (const namespace of [undefined, 'terraform.kms']) {
    const guard = GUARD[namespace] ?? 'IAM 가드';
    for (const f of gather(findingsDir, expectedDirs, skippedDirs, namespace).findings) {
      if (f.level === 'high') found.push({ ...f, guard });
    }
  }
  const located = locate(found, inspect, repoRoot);

  const files = await github.paginate(github.rest.pulls.listFiles, {
    ...repo,
    pull_number,
    per_page: 100,
  });
  const inDiff = new Map(files.map((file) => [file.filename, diffLines(file.patch)]));

  const grouped = new Map();
  let unplaced = 0;
  for (const f of located) {
    if (!f.pos || !inDiff.get(f.pos.path)?.has(f.pos.line)) {
      unplaced += 1;
      continue;
    }
    const key = `${f.pos.path}:${f.pos.line}`;
    if (!grouped.has(key)) grouped.set(key, { path: f.pos.path, line: f.pos.line, items: [] });
    grouped.get(key).items.push(f);
  }
  const comments = [...grouped.values()]
    .sort((a, b) => a.path.localeCompare(b.path) || a.line - b.line)
    .map(({ path: file, line, items }) => ({ path: file, line, side: 'RIGHT', body: body(items) }));

  // 이전 커밋의 코멘트는 모두 지우고 이번 판정으로 다시 단다. 사람의 리뷰 코멘트는 표식이 없어 남는다.
  const existing = await github.paginate(github.rest.pulls.listReviewComments, {
    ...repo,
    pull_number,
    per_page: 100,
  });
  for (const c of existing) {
    if (typeof c.body === 'string' && c.body.includes(MARKER))
      await github.rest.pulls.deleteReviewComment({ ...repo, comment_id: c.id });
  }
  if (comments.length) {
    await github.rest.pulls.createReview({
      ...repo,
      pull_number,
      commit_id: pr.head.sha,
      event: 'COMMENT',
      comments,
    });
  }
  core.info(
    `가드 라인 코멘트: 위험 ${found.length}건 중 ${comments.length}곳에 게시, diff 밖 ${unplaced}건은 표에만 표시`,
  );
  core.setOutput('line_comments', String(comments.length));
};

module.exports.diffLines = diffLines;
module.exports.parseAddress = parseAddress;
module.exports.locate = locate;
module.exports.MARKER = MARKER;
