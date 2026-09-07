'use strict';
// apply 순서(wave)를 Mermaid 그래프와 표로 그려 PR 코멘트 본문을 만든다.
// wave 계산과 매니페스트 검증은 tf-roots.js, 게시는 sticky-pull-request-comment 액션 몫이다. 여기는 본문뿐이다.
// 루트 이름은 NAME_RE(소문자·숫자·하이픈, /)를 통과한 값만 오므로 라벨에 그대로 쓴다. 의존 패키지 없음.
// wave0 이 비어 있으면(루트 없음, 검증 실패) 새 코멘트를 만들지 않고 이전 커밋의 코멘트만 갱신한다.
// 성공 본문에는 커밋 정보를 넣지 않는다. 매니페스트가 같으면 본문이 같아 skip_unchanged 가 갱신을 건너뛴다.

const fs = require('fs');
const path = require('path');

const { MANIFEST, analyze } = require('./tf-roots');

const TITLE = '### apply 순서';
const MERMAID_FENCE = '```mermaid';
const FENCE = '```';

// Mermaid 노드 id 는 영문·숫자·밑줄만 쓴다. / 는 문법 문자, - 는 화살표(-->)와 섞이고 end 는 예약어다.
// 이름을 바꿔 쓰면 a--b 와 a/b 가 겹칠 수 있으니 정렬된 루트 목록의 순번을 id 로 쓴다. 라벨이 이름을 보여 준다.
function nodeIds(roots) {
  const ids = {};
  roots.forEach((d, i) => { ids[d] = `r${i}`; });
  return ids;
}

// wave 하나가 subgraph 하나다. 위에서 아래로 계산된 wave를 표시하고, 화살표는 먼저 apply 되는 루트에서 나중 루트로 간다.
function mermaid({ roots, waves, deps }) {
  const ids = nodeIds(roots);
  const lines = ['flowchart TB'];
  waves.forEach((dirs, i) => {
    if (!dirs.length) return;
    lines.push(`  subgraph wave${i}`);
    for (const d of dirs) lines.push(`    ${ids[d]}["${d}"]`);
    lines.push('  end');
  });
  for (const d of roots) {
    for (const dep of deps[d] ?? []) lines.push(`  ${ids[dep]} --> ${ids[d]}`);
  }
  return lines.join('\n');
}

function table({ waves, deps }) {
  const rows = ['| wave | 루트 | depends_on |', '| --- | --- | --- |'];
  waves.forEach((dirs, i) => {
    for (const d of dirs) {
      const on = (deps[d] ?? []).map((x) => `\`${x}\``).join(', ');
      rows.push(`| ${i} | \`${d}\` | ${on} |`);
    }
  });
  return rows.join('\n');
}

// 오류 메시지에는 디렉터리 이름이 그대로 들어온다. 백틱은 코드 스팬을 닫아 HTML 이 살아나므로 바꾼다.
const inline = (s) => s.replace(/[\r\n]+/g, ' ').replace(/`/g, "'");

// 실패 본문에만 커밋과 로그를 붙인다. sha·runUrl 이 없으면(로컬 실행) 문장만 남긴다.
function footer(note, { sha, runUrl } = {}) {
  const parts = note ? [note] : [];
  if (sha) parts.push(sha.slice(0, 7));
  if (runUrl) parts.push(`[로그](${runUrl})`);
  return parts.length ? `<sub>${parts.join(' · ')}</sub>` : '';
}

function build(result, meta = {}) {
  const { roots, waves, errors } = result;
  if (errors.length) {
    return [
      TITLE, '',
      '루트 모듈 목록을 얻지 못해 이 커밋의 apply 순서를 계산하지 못했습니다 (discover 잡 로그 확인).', '',
      ...errors.map((e) => `- \`${inline(e)}\``), '',
      footer(`${MANIFEST} 을 고치면 다음 커밋에서 다시 그립니다.`, meta),
    ].join('\n');
  }
  if (!roots.length) {
    return [TITLE, '', `${MANIFEST} 에 루트 모듈이 없어 apply 할 대상이 없습니다.`].join('\n');
  }
  const waveCount = waves.filter((w) => w.length).length;
  // 화살표와 다음 wave 는 wave 가 둘 이상일 때만 그림에 있다. 없는 요소를 설명하지 않는다.
  const note = waveCount > 1
    ? '같은 wave 는 한 실행 안에서 차례로 apply 되고 다음 wave 는 앞 wave 가 실패하지 않았을 때만 실행됩니다. '
      + '화살표는 먼저 apply 되는 루트에서 나중 루트로 향합니다.'
    : '모든 루트가 wave0 이라 차례로 apply 됩니다.';
  return [
    `${TITLE}: 루트 ${roots.length}개, wave ${waveCount}개`, '',
    MERMAID_FENCE, mermaid(result), FENCE, '',
    table(result), '',
    footer(note),
  ].join('\n');
}

// 검증 실패나 루트 없음이면 기존 코멘트만 갱신한다 (only_update). wave0 이 있을 때만 새로 만든다.
// analyze 가 예외를 던져도 낡은 그래프가 남지 않도록 실패 본문으로 바꾼다.
function render(repoRoot, meta) {
  let result;
  try {
    result = analyze(repoRoot);
  } catch (e) {
    result = { roots: [], waves: [], deps: {}, errors: [`tf-roots.js: ${e.message}`] };
  }
  const posted = !result.errors.length && result.roots.length > 0;
  // 액션의 boolean 입력은 빈 문자열을 필수 입력 누락으로 취급하므로 항상 true/false 를 쓴다.
  return { body: build(result, meta), onlyUpdate: posted ? 'false' : 'true', result };
}

function metaFromEnv(env) {
  const repoUrl = env.GITHUB_SERVER_URL && env.GITHUB_REPOSITORY
    ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}` : '';
  return {
    sha: env.PR_HEAD_SHA || '',
    runUrl: repoUrl && env.GITHUB_RUN_ID ? `${repoUrl}/actions/runs/${env.GITHUB_RUN_ID}` : '',
  };
}

function main(argv, env) {
  const rootIdx = argv.indexOf('--root');
  const repoRoot = rootIdx >= 0 ? path.resolve(argv[rootIdx + 1]) : path.resolve(__dirname, '..', '..');
  const outIdx = argv.indexOf('--out');
  const { body, onlyUpdate } = render(repoRoot, metaFromEnv(env));
  if (outIdx >= 0) fs.writeFileSync(argv[outIdx + 1], `${body}\n`);
  else process.stdout.write(`${body}\n`);
  if (env.GITHUB_OUTPUT) fs.appendFileSync(env.GITHUB_OUTPUT, `only_update=${onlyUpdate}\n`);
  return 0;
}

module.exports = { nodeIds, mermaid, table, build, render, metaFromEnv };

if (require.main === module) process.exitCode = main(process.argv.slice(2), process.env);
