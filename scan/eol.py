#!/usr/bin/env python3
"""行尾 / 字符串字面量 字节级检查（针对 CI 实际编译的 committed blob）。

三类问题，危害完全不同：
  1. 跨行字符串字面量 —— 单行 `"` 里出现裸换行 → 直接编译失败（最严重）
  2. 行中间出现裸 CR —— 多半是脚本把换行写进了字面量/表达式中间 → 编译失败
  3. 行尾 `\\r\\r\\n`（CR 写两遍）—— Swift 当空白，能编过，但会让行号在
     工具之间差一倍，并且下一次按文本处理时极易退化成 1/2 类问题
"""
import re
import subprocess
import sys
import pathlib

REPO = sys.argv[1] if len(sys.argv) > 1 else "."


def files():
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                         cwd=REPO, capture_output=True, text=True, check=True).stdout
    return [f for f in out.split("\n") if f.endswith(".swift")]


def get_blob(path):
    r = subprocess.run(["git", "show", f"HEAD:{path}"], cwd=REPO, capture_output=True)
    return r.stdout if r.returncode == 0 else None


def literals(b):
    """返回单行字符串字面量里出现裸换行的位置行号。"""
    text = b.decode("utf-8", "replace")
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            if text.startswith('"""', i):
                j = text.find('"""', i + 3)
                i = n if j < 0 else j + 3
                continue
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] in "\r\n":
                    out.append(text[:j].count("\n") + 1)
                    break
                j += 1
            i = j + 1
            continue
        i += 1
    return out


def classify(b):
    dbl = len(re.findall(rb"\r\r\n", b))
    lone = len(re.findall(rb"\r(?!(?:\r?\n))", b))
    crlf = len(re.findall(rb"\r\n", b))
    bad_lit = literals(b)
    return dbl, lone, crlf, bad_lit


def main():
    paths = files()
    print(f".swift 文件: {len(paths)}")
    fetched = 0
    crit, mid, dbl_files = [], [], []
    for p in paths:
        b = get_blob(p)
        if b is None:
            print(f"  !! 取不到 blob: {p}")
            continue
        fetched += 1
        dbl, lone, crlf, bad_lit = classify(b)
        if bad_lit:
            crit.append((p, bad_lit[:5]))
        stripped = b.replace(b"\r\r\n", b"\n").replace(b"\r\n", b"\n")
        lone_real = len(re.findall(rb"\r", stripped))
        if lone_real:
            mid.append((p, lone_real))
        if dbl:
            dbl_files.append((p, dbl, crlf))
    if fetched == 0:
        raise SystemExit("!! 一个 blob 都没取到，检查是不是在仓库根目录运行")

    print(f"\n已检查 {fetched} 个 committed blob\n")
    print("### 1) 单行字符串字面量里出现裸换行（编译失败）")
    for p, lines in crit:
        print(f"    ❌ {p}: 行 {lines}")
    if not crit:
        print("    ✅ 无")
    print("\n### 2) 行中间的裸 CR（编译失败）")
    for p, c in mid:
        print(f"    ❌ {p}: {c} 处")
    if not mid:
        print("    ✅ 无")
    print("\n### 3) 行尾 CR 写两遍（能编过，但会诱发 1/2 类问题）")
    for p, d, c in dbl_files:
        print(f"    ⚠️ {p}: \\r\\r\\n={d} 行")
    if not dbl_files:
        print("    ✅ 无")
    print(f"\n合计: 致命 {len(crit) + len(mid)} 个文件 / 行尾不规整 {len(dbl_files)} 个文件")


main()
