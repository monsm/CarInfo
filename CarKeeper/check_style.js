// check_style.js — 检查 Swift 文件格式
const fs = require('fs');
const path = require('path');

function checkFile(fp) {
  const content = fs.readFileSync(fp, 'utf8');
  const lines = content.split('\n');
  const issues = [];
  lines.forEach((line, i) => {
    if (line.length > 120 && !line.trim().startsWith('//') && !line.trim().startsWith('*')) {
      issues.push({ line: i + 1, len: line.length, text: line.substring(0, 130) });
    }
  });
  return issues;
}

const dirs = ['CarKeeper/CarKeeper/Design', 'CarKeeper/CarKeeper/Features'];
let totalIssues = 0;
for (const dir of dirs) {
  if (!fs.existsSync(dir)) continue;
  const entries = fs.readdirSync(dir);
  for (const entry of entries) {
    const full = path.join(dir, entry);
    if (fs.statSync(full).isDirectory()) {
      for (const f of fs.readdirSync(full)) {
        if (f.endsWith('.swift') && checkFile(path.join(full, f)).length > 0) {
          const issues = checkFile(path.join(full, f));
          console.log(`  ⚠️ ${path.join(full, f)}`);
          console.log(`       ${issues.length} 个问题`);
          issues.slice(0, 5).forEach(i => console.log(`       • L${i.line}: line too long (${i.len} chars)`));
          if (issues.length > 5) console.log(`       ... 还有 ${issues.length - 5} 个`);
          totalIssues += issues.length;
        } else if (entry.endsWith('.swift')) {
          const lines = fs.readFileSync(full, 'utf8').split('\n').length;
          const size = fs.statSync(full).size;
          console.log(`  ✅ ${full}`);
          console.log(`       ${lines} 行, ${size} bytes ✓ 通过`);
        }
      }
    } else if (entry.endsWith('.swift')) {
      const issues = checkFile(full);
      if (issues.length > 0) {
        console.log(`  ⚠️ ${full}`);
        console.log(`       ${issues.length} 个问题`);
        issues.slice(0, 5).forEach(i => console.log(`       • L${i.line}: line too long (${i.len} chars)`));
        if (issues.length > 5) console.log(`       ... 还有 ${issues.length - 5} 个`);
        totalIssues += issues.length;
      } else {
        const lines = fs.readFileSync(full, 'utf8').split('\n').length;
        const size = fs.statSync(full).size;
        console.log(`  ✅ ${full}`);
        console.log(`       ${lines} 行, ${size} bytes ✓ 通过`);
      }
    }
  }
}
console.log(`\n📊 总计: ${totalIssues} 个问题`);
if (totalIssues === 0) console.log('\n🎉 所有文件通过风格检查！');
