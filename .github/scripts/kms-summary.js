'use strict';
// 같은 plan 아티팩트에서 KMS 판정만 읽는다. 규칙은 Rego, 코멘트 게시는 워크플로가 맡는다.
const fs = require('fs');
const { gather } = require('./plan-summary');

const LABEL = { high: '위험', warn: '확인', info: '변경' };
const MAX_ROWS = 40;
const cell = (text) => text.replace(/\|/g, '\\|');
const rows = (findings) => findings.map((f) => `| ${f.dir} | **${LABEL[f.level]}** | ${cell(f.text)} | ${cell(f.why)} |`);

async function updateLabel(github, context, name, present, complete) {
  const repo = context.repo;
  const issue_number = context.payload.pull_request.number;
  if (present) {
    try { await github.rest.issues.getLabel({ ...repo, name }); }
    catch (error) {
      if (error.status !== 404) throw error;
      await github.rest.issues.createLabel({
        ...repo, name, color: name === 'kms' ? '5319e7' : 'd93f0b',
        description: name === 'kms' ? 'KMS 리소스 변경 포함' : '검토가 필요한 KMS 변경',
      });
    }
    await github.rest.issues.addLabels({ ...repo, issue_number, labels: [name] });
  } else if (complete) {
    try { await github.rest.issues.removeLabel({ ...repo, issue_number, name }); }
    catch (error) { if (error.status !== 404) throw error; }
  }
}

module.exports = async ({ github, context, core, findingsDir, outFile, expectedDirs, skippedDirs }) => {
  const pr = context.payload.pull_request;
  if (!pr) return;
  const result = gather(findingsDir, expectedDirs, skippedDirs, 'terraform.kms');
  const { findings, failed, expected, skipped, complete } = result;
  const high = findings.filter((f) => f.level === 'high').length;
  const warn = findings.filter((f) => f.level === 'warn').length;
  const changes = findings.filter((f) => f.level === 'info').length;
  await updateLabel(github, context, 'kms', changes > 0, complete);
  await updateLabel(github, context, 'kms:high-risk', high > 0, complete);

  const repoUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}`;
  const runUrl = `${repoUrl}/actions/runs/${context.runId}`;
  const lines = [`### KMS 가드: 변경 ${changes}, 위험 ${high}, 확인 ${warn}`, ''];
  if (!complete) {
    lines.push(failed.length
      ? `${failed.map((dir) => `\`${dir}\``).join(', ')}: plan 또는 KMS 검사 결과가 없어 이 커밋을 검사하지 못했습니다.`
      : '루트 목록을 얻지 못해 이 커밋의 KMS 변경을 검사하지 못했습니다 (discover 잡 로그 확인).', '');
  } else if (!findings.length) {
    lines.push(expected.length ? '이 커밋에서 KMS 리소스 변경이 확인되지 않았습니다.'
      : '변경 영향이 있는 루트가 없어 plan 을 생략했습니다. 검사할 KMS 변경이 없습니다.', '');
  }
  if (skipped.length && expected.length) {
    lines.push(`${skipped.map((dir) => `\`${dir}\``).join(', ')}: 변경 영향이 없어 plan 을 생략했습니다.`, '');
  }
  if (findings.length) {
    lines.push('| 루트 | 구분 | 변경 | 이유 |', '| --- | --- | --- | --- |', ...rows(findings.slice(0, MAX_ROWS)), '');
  }
  if (findings.length > MAX_ROWS) {
    lines.push(`외 ${findings.length - MAX_ROWS}건은 [실행 요약](${runUrl})에 있습니다.`, '');
    core.summary.addRaw(['## KMS 가드 전체 목록', '', '| 루트 | 구분 | 변경 | 이유 |', '| --- | --- | --- | --- |', ...rows(findings), ''].join('\n'));
    await core.summary.write();
  }
  lines.push(`<sub>자문 검사이며 병합을 차단하지 않습니다. [규칙](${repoUrl}/blob/${pr.base.ref}/.github/policy/kms.rego)`
    + ` · ${pr.head.sha.slice(0, 7)} · [로그](${runUrl})</sub>`);
  fs.writeFileSync(outFile, lines.join('\n'));
  core.setOutput('only_update', complete && findings.length === 0 ? 'true' : 'false');
};
