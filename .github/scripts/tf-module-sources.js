'use strict';
// HCL 과 Terraform JSON 해석은 HashiCorp 의 terraform-config-inspect 에 맡긴다.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function moduleSources(repoRoot, dir) {
  const abs = path.join(repoRoot, dir);
  if (!fs.existsSync(abs) || !fs.statSync(abs).isDirectory()) return { local: [], uncertain: false };
  const result = spawnSync('terraform-config-inspect', ['--json', abs], { encoding: 'utf8' });
  if (result.error) throw new Error(`terraform-config-inspect 실행 실패: ${result.error.message}`);
  if (result.status !== 0) return { local: [], uncertain: true };
  let config;
  try { config = JSON.parse(result.stdout); } catch { return { local: [], uncertain: true }; }
  const out = new Set();
  let uncertain = (config.diagnostics ?? []).some((d) => d.severity === 'error');
  for (const call of Object.values(config.module_calls ?? {})) {
    const source = call.source;
    // 도구는 변수·local 을 포함한 식을 평가하지 않고 원문으로 돌려준다.
    if (typeof source !== 'string' || !source || /\b(?:var|local)\.|\$\{|%\{/.test(source)) {
      uncertain = true;
      continue;
    }
    if (!/^\.\.?\//.test(source)) continue;
    const target = path.posix.normalize(path.posix.join(dir, source)).replace(/\/$/, '');
    if (target && target !== '.' && !target.startsWith('..')) out.add(target);
  }
  return { local: [...out].sort(), uncertain };
}

module.exports = { moduleSources };
