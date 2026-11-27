const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const dirs = [
  'CarKeeper/CarKeeper/Design',
  'CarKeeper/CarKeeper/Features',
  'CarKeeper/Design',
];

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.swift')) out.push(full);
  }
}

function checkFile(fp) {
  const lines = fs.readFileSync(fp, 'utf8').split('\n');
  const issues = [];
  lines.forEach((line, i) => {
    const t = line.trim();
    if (line.length > 120 && !t.startsWith('//') && !t.startsWith('*')) {
      issues.push({ line: i + 1, len: line.length });
    }
  });
  return issues;
}

let totalIssues = 0;
let missingDirs = 0;

for (const rel of dirs) {
  const dir = path.resolve(repoRoot, rel);
  if (!fs.existsSync(dir)) {
    console.error(`  ❌ 声明的目录不存在: ${rel}`);
    missingDirs += 1;
    continue;
  }
  const files = [];
  walk(dir, files);
  for (const f of files) {
    const issues = checkFile(f);
    if (issues.length === 0) continue;
    console.log(`  ⚠️ ${path.relative(repoRoot, f)}`);
    console.log(`       ${issues.length} 个问题`);
    issues.slice(0, 5).forEach(i => console.log(`       • L${i.line}: line too long (${i.len} chars)`));
    if (issues.length > 5) console.log(`       ... 还有 ${issues.length - 5} 个`);
    totalIssues += issues.length;
  }
}

console.log(`\n📊 总计: ${totalIssues} 个问题`);

if (missingDirs > 0) {
  console.log(`\n❌ ${missingDirs} 个声明目录不存在 —— 检查范围被悄悄缩小了`);
  process.exitCode = 1;
} else if (totalIssues === 0) {
  console.log('\n🎉 所有文件通过风格检查！');
} else {
  process.exitCode = 1;
}
