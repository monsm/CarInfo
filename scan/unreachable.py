#!/usr/bin/env python3
"""unreachable.py — 找 `return` 之后仍有同缩进语句的地方。

Swift 不会为 return 之后的不可达代码报警（BatteryView 的 `return EmptyView()`
残留就是这样静默存活了好几轮），所以这类脚本残留只能靠静态扫。
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(".")
TK = ["CarKeeper/", "Services/", "Shared/", "Widgets/", "WatchApp/", "HealthKit/", "Models/", "Design/"]

files = []
for tk in TK:
    files += [str(p) for p in (ROOT / tk).rglob("*.swift")]
files = sorted(set(files))

# 结尾标点：合法的“返回后续行”是链式调用/运算符续行
CONT = re.compile(r"^\s*[.).,]?\s*(\.|\)|\}|\?|:|&&|\|\||\+|,|->)")


def indent_of(line):
    return len(line) - len(line.lstrip())


hits = []
for f in files:
    lines = Path(f).read_text(encoding="utf-8").split("\n")
    for i, l in enumerate(lines):
        s = l.strip()
        if not s.startswith("return ") and s != "return":
            continue
        if s.startswith("return") and ("//" in s or "{" in s or "}" in s or '"""' in s):
            continue  # 注释 / 内联闭包 / 多行字符串起始
        j = i + 1
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        if j >= len(lines):
            continue
        nxt = lines[j]
        if nxt.strip().startswith("}"):
            continue
        if nxt.strip().startswith("case ") or nxt.strip().startswith("default:") or nxt.strip().startswith("@unknown default"):
            continue  # switch 分支
        if CONT.match(nxt) and indent_of(nxt) > indent_of(l):
            continue  # 链式续行
        if indent_of(nxt) <= indent_of(l) and indent_of(nxt) > 0 and not nxt.strip().startswith("//"):
            hits.append((f, i + 1, s[:70], j + 1, nxt.strip()[:60]))

print(f"扫描 {len(files)} 个 Swift 文件")
if not hits:
    print("✅ 无『return 之后仍有同缩进语句』")
else:
    print(f"⚠️ {len(hits)} 处（逐条人工确认）：")
    for f, i, s, j, n in hits:
        print(f"  {f}:{i}  {s}\n       ↓ 第 {j} 行: {n}")
