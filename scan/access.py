#!/usr/bin/env python3

import os
import re
import sys
import glob
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TYPE_RE = re.compile(r'\b(?:struct|class|enum|actor|extension)\s+([A-Z]\w*)')
MEMBER_RE = re.compile(
    r'\b(private|fileprivate)\s+(?:static\s+|final\s+|nonisolated\s+|@\w+\s+)*'
    r'(?:func|var|let|typealias)\s+(\w+)'
)

QUALIFIED_RE = re.compile(r'\b([A-Z]\w*)\s*\.\s*(\w+)\b')


def swift_files(root):
    out = []
    for p in glob.glob(os.path.join(root, 'CarKeeper', '**', '*.swift'), recursive=True):
        norm = p.replace('\\', '/')
        if '/scan/baseline/' in norm:
            continue
        out.append(p)
    return sorted(out)


def rel(p):
    return os.path.relpath(p, ROOT).replace('\\', '/')


def strip_noise(src):
    """把注释与字符串字面量换成空白，避免里面的 `foo.bar` 被当成引用。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join('\n' if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
        elif c == '"':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(''.join('\n' if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def type_bodies(src):
    """产出 (类型名, 类型体文本)。用花括号配平定界，支持嵌套。"""
    stack = []
    i, n = 0, len(src)
    while i < n:
        m = TYPE_RE.search(src, i)
        if not m:
            break
        brace = src.find('{', m.end())
        if brace < 0:
            break
        depth = 0
        j = brace
        while j < n:
            if src[j] == '{':
                depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        yield m.group(1), src[brace + 1:j]
        i = m.end()


def collect(files):
    """{类型名: {成员名: [文件]}} —— 只记 private / fileprivate 成员。"""
    table = {}
    for p in files:
        src = strip_noise(open(p, encoding='utf-8', errors='replace').read())
        for tname, body in type_bodies(src):
            for m in MEMBER_RE.finditer(body):
                table.setdefault(tname, {}).setdefault(m.group(2), []).append(rel(p))
    return table


def check(files, quiet=False):
    table = collect(files)
    problems = []

    for p in files:
        rp = rel(p)
        raw = open(p, encoding='utf-8', errors='replace').read()
        src = strip_noise(raw)

        here = set(t for t, _ in type_bodies(src))
        lines = raw.splitlines()

        for m in QUALIFIED_RE.finditer(src):
            tname, member = m.group(1), m.group(2)
            if tname in here:
                continue
            owners = table.get(tname, {}).get(member)
            if not owners or rp in owners:
                continue
            line = src[:m.start()].count('\n') + 1
            text = lines[line - 1].strip() if line - 1 < len(lines) else ''
            problems.append((rp, line, tname, member, owners, text))

    if not quiet:
        if problems:
            print(f"❌ {len(problems)} 处跨文件访问 private/fileprivate 成员：")
            for rp, line, tname, member, owners, text in problems:
                print(f"   {rp}:{line}")
                print(f"      {tname}.{member}  ← 声明在 {', '.join(sorted(set(owners)))}")
                print(f"      {text}")
        else:
            print(f"✅ 无跨文件 private 访问（扫 {len(files)} 个文件）")
    return problems


def selftest():
    """正向：干净树 0；反向：注入一条跨文件 private 调用必报。"""
    files = swift_files(ROOT)
    if check(files, quiet=True):
        print("❌ 自测失败：干净树本应 0 报错")
        return 1
    print("✅ 正向：干净树 0 报错")

    decl = os.path.join(ROOT, 'CarKeeper', '__AccessProbeDecl.swift')
    use = os.path.join(ROOT, 'CarKeeper', '__AccessProbeUse.swift')
    try:
        with open(decl, 'w', encoding='utf-8') as f:
            f.write("struct AccessProbeHolder {\n"
                    "    private static func secret() {}\n"
                    "}\n")
        with open(use, 'w', encoding='utf-8') as f:
            f.write("struct AccessProbeUser {\n"
                    "    func f() { AccessProbeHolder.secret() }\n"
                    "}\n")
        found = check([p for p in files if '__AccessProbe' not in p] + [decl, use], quiet=True)
        hit = [x for x in found if x[2] == 'AccessProbeHolder' and x[3] == 'secret']
        if not hit:
            print("❌ 反向自测失败：注入了探针却没报出来")
            return 1
        print("✅ 反向：注入探针已报出（探针在临时文件里，随即删除）")
    finally:
        for p in (decl, use):
            if os.path.exists(p):
                os.remove(p)
    return 0


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        sys.exit(selftest())
    fs = [p for p in swift_files(ROOT) if '__AccessProbe' not in p]
    sys.exit(1 if check(fs) else 0)
