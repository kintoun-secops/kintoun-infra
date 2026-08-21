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

// findings/iam-findings-<모듈>/conftest.json 을 모아 심각도순 한 목록으로 만든다.
function gather(findingsDir) {
  const out = [];
  if (!fs.existsSync(findingsDir)) return out; // plan 전멸이면 결과가 없다
  for (const entry of fs.readdirSync(findingsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const file = path.join(findingsDir, entry.name, 'conftest.json');
    if (!fs.existsSync(file)) continue;
    const dir = entry.name.replace(/^iam-findings-/, '');
    for (const f of collect(JSON.parse(fs.readFileSync(file, 'utf8')))) {
      out.push({ dir, ...f });
    }
  }
  return out.sort((a, b) => (RANK[a.level] - RANK[b.level]) || a.dir.localeCompare(b.dir));
}

// 리소스 주소에 | 가 들어갈 수 있다 (groups.tf 가 "name|arn" 을 키로 쓴다).
const cell = (s) => s.replace(/\|/g, '\\|');

function build(findings, { repoUrl, baseRef, sha, runUrl }) {
  const footer = `<sub>[차단] 항목 외에는 병합을 막지 않습니다. `
    + `[규칙](${repoUrl}/blob/${baseRef}/.github/policy/iam.rego)`
    + ` · ${sha.slice(0, 7)} · [로그](${runUrl})</sub>`;

  if (!findings.length) {
    return ['### IAM 가드', '', '이전에 지적된 항목이 모두 해소되었습니다.', '', footer].join('\n');
  }

  const highs = findings.filter((f) => f.level === 'high').length;
  const lines = [
    `### IAM 가드: 위험 ${highs}, 확인 ${findings.length - highs}`,
    '',
    findings[0].text, // 타임라인 미리보기에 가장 심각한 항목이 보이게 한다
    '',
    '| 모듈 | 구분 | 변경 |',
    '| --- | --- | --- |',
    ...findings.slice(0, MAX_ROWS).map(
      (f) => `| ${f.dir} | **${LABEL[f.level]}** | ${cell(f.text)} |`,
    ),
  ];
  if (findings.length > MAX_ROWS) {
    lines.push('', `외 ${findings.length - MAX_ROWS}건은 [실행 요약](${runUrl})에 있습니다.`);
  }

  const seen = new Set();
  const reasons = [];
  for (const f of findings) {
    if (!f.why || seen.has(f.why)) continue;
    seen.add(f.why);
    reasons.push(`**${f.text.split(' — ')[0]}** — ${f.why}`);
  }
  if (reasons.length) {
    lines.push('', '<details><summary>설명</summary>', '', ...reasons, '', '</details>');
  }

  lines.push('', footer);
  return lines.join('\n');
}

module.exports = async ({ github, context, core, findingsDir, outFile }) => {
  const pr = context.payload.pull_request;
  if (!pr) return;

  const findings = gather(findingsDir);
  const hasHigh = findings.some((f) => f.level === 'high');

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
  } else {
    try { // 후속 푸시로 위험이 사라지면 걷는다
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
      '| 모듈 | 구분 | 변경 | 설명 |', '| --- | --- | --- | --- |',
      ...findings.map((f) => `| ${f.dir} | ${LABEL[f.level]} | ${cell(f.text)} | ${cell(f.why)} |`),
      '',
    ].join('\n'));
    await core.summary.write();
  }

  const repoUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}`;
  fs.writeFileSync(outFile, build(findings, {
    repoUrl,
    baseRef: pr.base.ref,
    sha: pr.head.sha,
    runUrl: `${repoUrl}/actions/runs/${context.runId}`,
  }));

  // 지적이 없으면 기존 코멘트가 있을 때만 "해소됨" 으로 갱신한다 (없으면 침묵).
  core.setOutput('only_update', findings.length ? '' : 'true');
};

module.exports.collect = collect;
module.exports.gather = gather;
module.exports.build = build;
