// 루트별 아티팩트로 IAM 가드와 변경 없는 platform plan 요약 본문을 조립한다.
// IAM 판정 규칙은 .github/policy/의 Rego, 게시는 sticky-pull-request-comment 액션 몫이다.
// 여기는 두 요약의 본문·라벨·출력을 맡는다.
// 규칙 메시지에 plan 의 값을 넣지 말 것 — artifact 와 코멘트로 그대로 나간다.

const fs = require('fs');
const path = require('path');

const { toSlug } = require('./tf-roots');

const RANK = { high: 0, warn: 1, info: 2 };
const LABEL = { high: '위험', warn: '확인' };
const MAX_ROWS = 40;

function collect(results) {
  const out = [];
  for (const r of results ?? []) {
    for (const [key, level] of [['failures', 'high'], ['warnings', 'warn']]) {
      for (const f of r[key] ?? []) {
        out.push({
          level: f.metadata?.level ?? level,
          text: f.msg ?? String(f),
          why: f.metadata?.why ?? '',
        });
      }
    }
  }
  return out;
}

// 모듈마다 iam-findings-<슬러그>/ 에 iam-findings.json(검사됨) 또는 plan-failed(검사 못 함)가 온다.
// 기대 목록(expectedDirs)과 생략 목록(skippedDirs)은 discover 잡이 준다. 일부 모듈만 실패해도 "지적 없음" 으로
// 읽히면 안 되므로 실패 모듈을 따로 세고, 두 목록이 모두 비면 아무것도 검사하지 못한 것으로 친다.
// 변경 영향이 없어 생략한 모듈은 실패가 아니다. 기대 목록이 비어도 생략 목록이 있으면 검사 완료다.
function gather(findingsDir, expectedDirs, skippedDirs, namespace) {
  const expected = Array.isArray(expectedDirs) ? [...expectedDirs].sort() : [];
  const skipped = Array.isArray(skippedDirs) ? skippedDirs.filter((d) => !expected.includes(d)).sort() : [];
  const findings = [];
  const failed = [];
  let legs = 0;
  for (const dir of expected) {
    const artifactDir = path.join(findingsDir, `iam-findings-${toSlug(dir)}`);
    if (!fs.existsSync(artifactDir)) {
      failed.push(dir);
      continue;
    }
    legs += 1;
    const file = path.join(artifactDir, 'iam-findings.json');
    try {
      if (!fs.existsSync(file) || fs.existsSync(path.join(artifactDir, 'plan-failed'))) throw new Error('plan-failed');
      const results = JSON.parse(fs.readFileSync(file, 'utf8'));
      const namespaces = namespace ? [namespace] : ['terraform.iam', 'terraform.guardrail'];
      if (!Array.isArray(results)) throw new Error('invalid-results');
      const selected = results.filter((r) => namespaces.includes(r?.namespace));
      for (const f of collect(selected)) {
        findings.push({ dir, ...f });
      }
      // 일부 패키지의 결과가 없더라도 이미 확인한 위험은 코멘트에 남긴다.
      if (!namespaces.every((name) => selected.some((r) => r.namespace === name))) failed.push(dir);
    } catch {
      failed.push(dir);
    }
  }
  findings.sort((a, b) => (RANK[a.level] - RANK[b.level]) || a.dir.localeCompare(b.dir));
  const known = expected.length + skipped.length > 0;
  const complete = known && legs === expected.length && failed.length === 0;
  return { findings, failed: failed.sort(), legs, expected, skipped, complete };
}

// 현재 실행에서 성공한 platform 루트만 묶는다. 표식 누락이나 읽기 실패는 변경 없음으로 추정하지 않는다.
function unchangedPlatform(findingsDir, expectedDirs) {
  return (Array.isArray(expectedDirs) ? expectedDirs : []).filter((dir) => {
    if (dir !== 'platform' && !dir.startsWith('platform/')) return false;
    const artifactDir = path.join(findingsDir, `iam-findings-${toSlug(dir)}`);
    if (fs.existsSync(path.join(artifactDir, 'plan-failed'))) return false;
    try {
      return JSON.parse(fs.readFileSync(path.join(artifactDir, 'plan-status.json'), 'utf8')).no_changes === true;
    } catch {
      return false;
    }
  }).sort();
}

// 리소스 주소에 | 가 들어갈 수 있다 (groups.tf 가 "name|arn" 을 키로 쓴다).
const cell = (s) => s.replace(/\|/g, '\\|');

function build({ findings, failed, expected, skipped, complete }, { repoUrl, baseRef, sha, runUrl }) {
  const footer = `<sub>[차단] 항목 외에는 병합을 막지 않습니다. `
    + `[규칙](${repoUrl}/blob/${baseRef}/.github/policy/iam.rego)`
    + ` · ${sha.slice(0, 7)} · [로그](${runUrl})</sub>`;
  let unchecked;
  if (!expected.length && !skipped.length) {
    unchecked = '루트 모듈 목록을 얻지 못해 이 커밋의 IAM 변경을 검사하지 못했습니다 (discover 잡 로그 확인).';
  } else if (failed.length) {
    unchecked = `${failed.map((d) => `\`${d}\``).join(', ')}: plan 또는 IAM 검사 결과가 없어 이 커밋의 IAM 변경을 모두 검사하지 못했습니다.`;
  } else {
    unchecked = 'plan 결과가 없어 이 커밋의 IAM 변경을 검사하지 못했습니다.';
  }

  // 생략한 루트는 목록으로만 남긴다. 실패 목록과 섞이지 않는다.
  const skippedLine = skipped.length
    ? `${skipped.map((d) => `\`${d}\``).join(', ')}: 변경 영향이 없어 plan 을 생략했습니다.`
    : '';

  if (!findings.length) {
    let status;
    if (!complete) status = unchecked;
    else if (!expected.length) status = '변경 영향이 있는 루트가 없어 plan 을 생략했습니다. 이 커밋에는 검사할 IAM 변경이 없습니다.';
    else status = '이전에 지적된 항목이 모두 해소되었습니다.';
    const notes = skippedLine && expected.length ? ['', skippedLine] : [];
    return ['### IAM 가드', '', status, ...notes, '', footer].join('\n');
  }

  const highs = findings.filter((f) => f.level === 'high').length;
  const lines = [
    `### IAM 가드: 위험 ${highs}, 확인 ${findings.length - highs}`,
    ...(complete ? [] : ['', unchecked]),
    ...(skippedLine ? ['', skippedLine] : []),
    '',
    '| 모듈 | 구분 | 변경 | 이유 |',
    '| --- | --- | --- | --- |',
    ...findings.slice(0, MAX_ROWS).map(
      (f) => `| ${f.dir} | **${LABEL[f.level]}** | ${cell(f.text)} | ${cell(f.why)} |`,
    ),
  ];
  if (findings.length > MAX_ROWS) {
    lines.push('', `외 ${findings.length - MAX_ROWS}건은 [실행 요약](${runUrl})에 있습니다.`);
  }
  lines.push('', footer);
  return lines.join('\n');
}

module.exports = async ({ github, context, core, findingsDir, outFile, expectedDirs, skippedDirs }) => {
  const pr = context.payload.pull_request;
  if (!pr) return;

  const result = gather(findingsDir, expectedDirs, skippedDirs);
  const { findings, complete } = result;
  const hasHigh = findings.some((f) => f.level === 'high');

  const unchanged = unchangedPlatform(findingsDir, expectedDirs);
  core.setOutput('unchanged_delete', unchanged.length === 0 ? 'true' : 'false');
  core.setOutput('unchanged_body', [
    '### Platform terraform plan: 변경 없음', '',
    '| 루트 | 결과 |', '| --- | --- |',
    ...unchanged.map((dir) => `| \`${dir}\` | No changes |`), '',
    'import, state 관리 해제와 출력 변경이 있는 루트는 별도 상세 plan을 확인해 주세요.',
  ].join('\n'));

  if (hasHigh) {
    try {
      await github.rest.issues.getLabel({ ...context.repo, name: 'iam:high-risk' });
    } catch (e) {
      if (e.status !== 404) throw e;
      await github.rest.issues.createLabel({
        ...context.repo, name: 'iam:high-risk', color: 'd93f0b', description: '검토가 필요한 IAM 변경',
      });
    }
    await github.rest.issues.addLabels({
      ...context.repo, issue_number: pr.number, labels: ['iam:high-risk'],
    });
  } else if (complete) { // 전부 검사했고 깨끗할 때만 걷는다 — 검사 못 한 커밋은 그대로 둔다
    try {
      await github.rest.issues.removeLabel({
        ...context.repo, issue_number: pr.number, name: 'iam:high-risk',
      });
    } catch (e) {
      if (e.status !== 404) throw e;
    }
  }

  // 코멘트 표가 잘릴 때만 전체 목록을 잡 요약에 남긴다.
  if (findings.length > MAX_ROWS) {
    core.summary.addRaw([
      `## IAM 가드 전체 목록: ${findings.length}건`, '',
      '| 모듈 | 구분 | 변경 | 이유 |', '| --- | --- | --- | --- |',
      ...findings.map((f) => `| ${f.dir} | ${LABEL[f.level]} | ${cell(f.text)} | ${cell(f.why)} |`),
      '',
    ].join('\n'));
    await core.summary.write();
  }

  const repoUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}`;
  fs.writeFileSync(outFile, build(result, {
    repoUrl,
    baseRef: pr.base.ref,
    sha: pr.head.sha,
    runUrl: `${repoUrl}/actions/runs/${context.runId}`,
  }));

  // 모든 모듈을 검사했고 지적이 없을 때만 기존 코멘트를 갱신한다.
  // 미검사 모듈이 있으면 지적이 0개여도 새 경고 코멘트를 만든다.
  // 액션의 boolean 입력은 빈 문자열을 허용하지 않으므로 false도 명시한다.
  core.setOutput('only_update', complete && findings.length === 0 ? 'true' : 'false');
};

module.exports.collect = collect;
module.exports.gather = gather;
module.exports.build = build;
