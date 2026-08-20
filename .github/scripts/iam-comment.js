// conftest 결과를 PR 코멘트 하나로 옮긴다. 판정 규칙은 여기 없다 —
// 규칙은 .github/policy/iam.rego 에 있고 conftest verify 로 단위 테스트한다.
// 이 파일은 표시만 책임진다.
//
// 루트 모듈마다 코멘트를 달면 PR 이 봇 코멘트로 뒤덮이므로, plan 잡이 올린
// 결과를 모아 한 번만 게시한다.
//
// 업로드되는 conftest 결과에는 우리가 만든 메시지만 담긴다 (plan JSON 자체가
// 아니다). 규칙 메시지에 plan 의 값을 그대로 넣지 말 것 — 민감값이 섞이면
// 그대로 artifact 와 코멘트로 나간다.

const fs = require('fs');
const path = require('path');

const RANK = { high: 0, warn: 1 };
const LABEL = { high: '위험', warn: '확인' };
const MARKER = '<!-- iam-guard -->';
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

// findingsDir 안의 iam-findings-<dir>/conftest.json 들을 모은다.
function gather(findingsDir) {
  const byDir = [];
  // plan 이 전부 실패하면 올라온 결과가 하나도 없다.
  if (!fs.existsSync(findingsDir)) return byDir;
  for (const entry of fs.readdirSync(findingsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const dir = entry.name.replace(/^iam-findings-/, '');
    const file = path.join(findingsDir, entry.name, 'conftest.json');
    if (!fs.existsSync(file)) continue;
    const findings = collect(JSON.parse(fs.readFileSync(file, 'utf8')))
      .sort((a, b) => RANK[a.level] - RANK[b.level]);
    byDir.push({ dir, findings });
  }
  return byDir.sort((a, b) => a.dir.localeCompare(b.dir));
}

module.exports = async ({ github, context, core, findingsDir }) => {
  const pr = context.payload.pull_request;
  if (!pr) return;

  const modules = gather(findingsDir);
  const all = modules.flatMap((m) => m.findings);
  const highs = all.filter((f) => f.level === 'high');
  const hasHigh = highs.length > 0;

  // --- 라벨 ---------------------------------------------------------------
  const ensureLabel = async (name, color, description) => {
    try {
      await github.rest.issues.getLabel({ ...context.repo, name });
    } catch (e) {
      if (e.status !== 404) throw e;
      await github.rest.issues.createLabel({ ...context.repo, name, color, description });
    }
  };
  const dropLabel = async (name) => {
    try {
      await github.rest.issues.removeLabel({ ...context.repo, issue_number: pr.number, name });
    } catch (e) {
      if (e.status !== 404) throw e; // 애초에 없었으면 그만이다
    }
  };

  if (hasHigh) {
    await ensureLabel('iam:high-risk', 'd93f0b', '검토가 필요한 IAM 변경');
    await github.rest.issues.addLabels({
      ...context.repo, issue_number: pr.number, labels: ['iam:high-risk'],
    });
  } else {
    await dropLabel('iam:high-risk'); // 후속 푸시로 위험이 사라지면 걷는다
  }

  // --- 잡 요약: 잘리지 않은 전체 목록 ---------------------------------------
  // addTable 은 raw HTML 을 내보내므로 마크다운이 해석되지 않는다 (백틱이 그대로
  // 보인다). 마크다운 표를 직접 써서 addRaw 로 넘긴다.
  if (all.length) {
    const rows = modules.flatMap((m) => m.findings.map(
      (f) => `| ${m.dir} | ${LABEL[f.level]} | ${cell(f.text)} | ${cell(f.why)} |`,
    ));
    core.summary.addRaw([
      `## IAM 가드 — ${all.length}건`, '',
      '| 모듈 | 등급 | 변경 | 확인할 점 |',
      '| --- | --- | --- | --- |',
      ...rows, '',
    ].join('\n'));
    await core.summary.write();
  }

  // --- 코멘트 -------------------------------------------------------------
  const { data: comments } = await github.rest.issues.listComments({
    ...context.repo, issue_number: pr.number, per_page: 100,
  });
  const existing = comments.find((c) => c.body.startsWith(MARKER));

  // 볼 것이 없으면 침묵한다. 변경 사실 자체는 plan 코멘트가 이미 말한다.
  if (!all.length && !existing) {
    core.info('IAM 지적 없음');
    return;
  }

  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}`
    + `/actions/runs/${context.runId}`;
  const lines = [MARKER];

  if (!all.length) {
    lines.push('### IAM 가드 — 지적 없음', '', '이전에 지적된 항목이 모두 해소되었습니다.');
  } else {
    lines.push(
      `### IAM 가드 — 위험 ${highs.length} · 확인 ${all.length - highs.length}`,
      '',
      // 타임라인 미리보기에 가장 심각한 항목이 보이도록 맨 앞에 한 줄 세운다.
      (hasHigh ? highs : all)[0].text,
      '',
    );

    let budget = MAX_ROWS;
    for (const m of modules) {
      if (!m.findings.length) continue;
      const shown = m.findings.slice(0, budget);
      budget -= shown.length;
      lines.push(
        `**${m.dir}**`, '',
        '| 등급 | 변경 |', '| --- | --- |',
        ...shown.map((f) => `| **${LABEL[f.level]}** | ${cell(f.text)} |`),
        '',
      );
    }

    const hidden = all.length - Math.min(all.length, MAX_ROWS);
    if (hidden) lines.push(`*… 외 ${hidden}건 — 전체는 [잡 요약](${runUrl})에 있습니다*`, '');

    // 사유는 표 밖으로 뺀다. 표는 훑는 용도, 산문은 펼쳐 보는 용도다.
    const seen = new Set();
    const reasons = all.filter((f) => {
      const key = f.why;
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    if (reasons.length) {
      lines.push(
        '<details><summary>확인할 점</summary>', '',
        // 표의 어느 줄에 대한 설명인지 알 수 있게 변경 종류를 앞에 세운다.
        ...reasons.map((f) => `**${f.text.split(' — ')[0]}** · ${f.why}`),
        '', '</details>', '',
      );
    }
  }

  lines.push(
    `<sub>규칙: <a href="${context.serverUrl}/${context.repo.owner}/${context.repo.repo}`
      + `/blob/${pr.base.ref}/.github/policy/iam.rego"><code>.github/policy/iam.rego</code></a>`
      + ` · 차단하지 않습니다 · <code>${pr.head.sha.slice(0, 7)}</code>`
      + ` · <a href="${runUrl}">실행 로그</a></sub>`,
  );

  const body = lines.join('\n');
  if (existing) {
    await github.rest.issues.updateComment({ ...context.repo, comment_id: existing.id, body });
  } else {
    await github.rest.issues.createComment({
      ...context.repo, issue_number: pr.number, body,
    });
  }
};

// 리소스 주소에 | 가 들어갈 수 있다 (groups.tf 가 "name|arn" 을 키로 쓴다).
function cell(s) {
  return s.replace(/\|/g, '\\|');
}

module.exports.collect = collect;
module.exports.gather = gather;
