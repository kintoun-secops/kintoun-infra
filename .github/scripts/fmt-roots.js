'use strict';
// terraform fmt 가 다루지 않는 루트 매니페스트를 검사한다. 키와 배열 순서는 유지한다.
const fs = require('fs');
const path = require('path');
const { MANIFEST } = require('./tf-roots');

function main(argv) {
  if (argv.length !== 1 || !['--check', '--write'].includes(argv[0])) {
    process.stderr.write('사용법: node .github/scripts/fmt-roots.js --check|--write\n');
    return 1;
  }
  const file = path.resolve(MANIFEST);
  let original;
  let formatted;
  try {
    original = fs.readFileSync(file, 'utf8');
    formatted = `${JSON.stringify(JSON.parse(original), null, 2)}\n`;
  } catch (error) {
    process.stderr.write(`::error file=${MANIFEST}::JSON 을 읽을 수 없습니다: ${error.message}\n`);
    return 1;
  }
  if (original === formatted) return 0;
  if (argv[0] === '--write') {
    fs.writeFileSync(file, formatted);
    process.stdout.write(`${MANIFEST}\n`);
    return 0;
  }
  process.stderr.write(`::error file=${MANIFEST}::JSON 포맷이 다릅니다. node .github/scripts/fmt-roots.js --write 로 정리하세요.\n`);
  return 1;
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));
