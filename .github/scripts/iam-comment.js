// conftest 결과로 PR 코멘트 본문을 조립한다. 판정 규칙은 .github/policy/iam.rego,
// 게시는 sticky-pull-request-comment 액션 몫이다. 여기는 본문·라벨·요약뿐이다.
// 규칙 메시지에 plan 의 값을 넣지 말 것 — artifact 와 코멘트로 그대로 나간다.

const fs = require('fs');
const path = require('path');

const RANK = { high: 0, warn: 1 };
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

// 모듈마다 iam-findings-<모듈>/ 에 iam-findings.json(검사됨) 또는 plan-failed(검사 못 함)가 온다.
// 일부 모듈만 실패해도 "지적 없음" 으로 읽히면 안 되므로 실패 모듈을 따로 센다.
function gather(findingsDir) {
  const findings = [];
  const failed = [];
  let legs = 0;
  if (!fs.existsSync(findingsDir)) return { findings, failed, legs };
  for (const entry of fs.readdirSync(findingsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    legs += 1;
    const dir = entry.name.replace(/^iam-findings-/, '');
    const file = path.join(findingsDir, entry.name, 'iam-findings.json');
    try {
      if (!fs.existsSync(file)) throw new Error('plan-failed');
      for (const f of collect(JSON.parse(fs.readFileSync(file, 'utf8')))) {
        findings.push({ dir, ...f });
      }
    } catch {
      failed.push(dir);
    }
  }
  findings.sort((a, b) => (RANK[a.level] - RANK[b.level]) || a.dir.localeCompare(b.dir));
  return { findings, failed: failed.sort(), legs };
}

// 리소스 주소에 | 가 들어갈 수 있다 (groups.tf 가 "name|arn" 을 키로 쓴다).
const cell = (s) => s.replace(/\|/g, '\\|');

function build({ findings, failed, legs }, { repoUrl, baseRef, sha, runUrl }) {
  const footer = `<sub>[차단] 항목 외에는 병합을 막지 않습니다. `
    + `[규칙](${repoUrl}/blob/${baseRef}/.github/policy/iam.rego)`
    + ` · ${sha.slice(0, 7)} · [로그](${runUrl})</sub>`;
  const complete = legs > 0 && failed.length === 0;
  const unchecked = failed.length
    ? `${failed.map((d) => `\`${d}\``).join(', ')}: plan 이 실패해 이 커밋의 IAM 변경을 검사하지 못했습니다.`
    : 'plan 결과가 없어 이 커밋의 IAM 변경을 검사하지 못했습니다.';

  if (!findings.length) {
    const status = complete ? '이전에 지적된 항목이 모두 해소되었습니다.' : unchecked;
    return ['### IAM 가드', '', status, '', footer].join('\n');
  }

  const highs = findings.filter((f) => f.level === 'high').length;
  const lines = [
    `### IAM 가드: 위험 ${highs}, 확인 ${findings.length - highs}`,
    ...(complete ? [] : ['', unchecked]),
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

module.exports = async ({ github, context, core, findingsDir, outFile }) => {
  const pr = context.payload.pull_request;
  if (!pr) return;

  const result = gather(findingsDir);
  const { findings, failed, legs } = result;
  const hasHigh = findings.some((f) => f.level === 'high');
  const complete = legs > 0 && failed.length === 0;

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
      `## IAM 가드 전체 목록 — ${findings.length}건`, '',
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

  // 지적이 없으면 기존 코멘트가 있을 때만 갱신한다 ("해소" 또는 "검사 못 함"). 없으면 침묵.
  core.setOutput('only_update', findings.length ? '' : 'true');
};

module.exports.collect = collect;
module.exports.gather = gather;
module.exports.build = build;
