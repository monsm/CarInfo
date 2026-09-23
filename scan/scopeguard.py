#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
作用域检查器 —— 「名字在项目里，但在调用点不在作用域」

为什么需要它（真实事故，2026-09-23 的 CI）：

    Analysis.swift:424:19: error: cannot find 'extremeText' in scope
    Analysis.swift:424:31: error: cannot find 'numberList' in scope
    ... 同一个错误 8 条

  上一轮把四处 `arr.isEmpty ? "--" : arr.min()!` 收成助手时，调用写成了裸名字：

      vMin: extremeText(numberList(sub, "BatteryVoltage"), digits: 3, lowest: true)

  但这两个助手住在 `enum AN` 里，而调用点在**顶层函数** `batteryModel(_:)` 内 ——
  越了作用域，编译不过。它们既不是拼错（项目里确实有这两个名字），也不是缺类型
  （`scan.py` 见到项目内有声明就放行），所以 **18 项静态门禁全绿**，唯一能看见它的是
  CI 的 macOS runner —— 那是按 10 倍额度计费的一台机器。

判据（只收窄到能给出确定结论的两种）：

  ① 调用 `name(...)` 时没带类型前缀，而 `name` 是项目里**某个类型**的 `static`
     func / let / var —— 且调用点不在任何「声明了该名字的作用域」里。
     Swift 里跨类型调用静态成员必须写 `Type.name`，所以这不是风格问题，是编译错误。
  ② 报告里同时打印「它属于哪个类型」，因为修法就是补上那个前缀。

  **合法就该放行的四种情况**（都是实测出来的，不是猜的）：
    · 调用点在声明该名字的**类型体内**（含嵌套类型、含外层类型）—— 词法作用域允许；
    · 文件**顶层**声明了同名函数 / 变量 —— 名字解析到它，轮不到那个静态成员；
    · 同名还是个**全局函数**（另一个文件顶层声明）—— 同上；
    · 名字短于 6 个字符 —— 太容易撞上局部变量与参数（本项目里 `VM.n0` / `VM.s`
      这类短助手本来就是显式带前缀调用的），收窄的代价是漏掉极短的越界调用，
      收益是零误报。

  第一版还漏了「同文件内的静态成员」这一条 —— 而事故发生在**同一个文件**里
  （`extremeText` 与调用点都在 Analysis.swift），于是它会静默放行这起真实事故。
  这个假阴性是探针测出来的：探针注入 `enum ProbeOwner { static func probeHelper }`
  与两个跨作用域调用点，它必须两个都报；第一版两个都不报。

  刻意**不做**的：实例方法的裸调用（需要知道调用点有没有该类型的实例，误报会很多），
  以及字符串插值内部的调用（插值被当作字符串内容一起屏蔽）。

退出码：0 = 没有越作用域的调用；1 = 有（或扫描失败）。
"""

import io
import os
import re
import sys

# 编进 target 的 Swift 源码。测试目标不在内（测试里自成作用域）。
SCOPE_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Models",
    "CarKeeper/Design",
    "CarKeeper/Shared",
    "CarKeeper/Widgets",
    "CarKeeper/WatchApp",
]

# 白名单：{"相对路径:名字": "理由"}。留空是好事。
ALLOWED = {}

# re.M 是必须的：`^` 要能匹配每一行的行首。少了它，`^` 只在文件开头匹配 ——
# 收集到的类型数会是 0，而检查器会「全绿」地放行一切。
TYPE_DECL = re.compile(
    r"^[ \t]*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?[ \t]+)*"
    r"(?:public[ \t]+|internal[ \t]+|private[ \t]+|fileprivate[ \t]+|final[ \t]+|"
    r"open[ \t]+|indirect[ \t]+)*"
    r"(enum|struct|class|actor|extension)[ \t]+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)
STATIC_MEMBER = re.compile(
    r"^[ \t]+(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?[ \t]+)*"
    r"(?:public[ \t]+|internal[ \t]+|private[ \t]+|fileprivate[ \t]+|"
    r"nonisolated[ \t]+|mutating[ \t]+|@discardableResult[ \t]+)*"
    r"static[ \t]+(?:func|let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"
)
FUNC_DECL = re.compile(r"\bfunc[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(")
LET_VAR_DECL = re.compile(r"\b(?:let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?::[^=\n]+)?=")

MIN_NAME = 6


def mask(text):
    """把注释与字符串换成空格（保留换行），让正则只面对代码。

    偏移量不变，所以行号与括号配对都还能算。
    """
    out = list(text)
    i, n = 0, len(text)
    CODE, LINE, BLOCK, STR, ML = range(5)
    st = CODE
    depth = 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if st == CODE:
            if c == "/" and nxt == "/":
                st = LINE
                out[i] = " "
                i += 1
                continue
            if c == "/" and nxt == "*":
                st = BLOCK
                depth = 1
                out[i] = " "
                i += 1
                continue
            if text.startswith('"""', i):
                st = ML
                for k in range(i, min(i + 3, n)):
                    out[k] = " "
                i += 3
                continue
            if c == '"':
                st = STR
                out[i] = " "
                i += 1
                continue
            i += 1
        elif st == LINE:
            if c == "\n":
                st = CODE
            else:
                out[i] = " "
            i += 1
        elif st == BLOCK:
            if c == "/" and nxt == "*":
                depth += 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if c == "*" and nxt == "/":
                depth -= 1
                out[i] = out[i + 1] = " "
                i += 2
                if depth == 0:
                    st = CODE
                continue
            if c != "\n":
                out[i] = " "
            i += 1
        elif st == STR:
            if c == "\\":
                out[i] = " "
                if i + 1 < n and out[i + 1] != "\n":
                    out[i + 1] = " "
                i += 2
                continue
            if c == '"':
                st = CODE
            if c != "\n":
                out[i] = " "
            i += 1
        else:  # 多行字符串
            if text.startswith('"""', i):
                for k in range(i, min(i + 3, n)):
                    out[k] = " "
                i += 3
                st = CODE
                continue
            if c != "\n":
                out[i] = " "
            i += 1
    return "".join(out)


def swift_files():
    out = []
    for root in SCOPE_DIRS:
        if not os.path.isdir(root):
            continue
        for dirpath, _, names in os.walk(root):
            if "baseline" in dirpath:
                continue
            for name in sorted(names):
                if name.endswith(".swift"):
                    out.append(os.path.join(dirpath, name))
    return sorted(out)


def read(path):
    with io.open(path, encoding="utf-8", errors="ignore") as f:
        return f.read()


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def type_bodies(code):
    """[(类型名, 起始, 结束)] —— 用括号深度配对。"""
    opens = []
    starts = []
    for m in TYPE_DECL.finditer(code):
        brace = code.find("{", m.end())
        line_end = code.find("\n", m.end())
        if brace == -1 or (line_end != -1 and brace > line_end):
            continue
        starts.append((m.group(2), brace))

    bodies = []
    for m in re.finditer(r"[{}]", code):
        if m.group(0) == "{":
            opens.append(m.start())
        elif opens:
            start = opens.pop()
            for idx, (nm, brace) in enumerate(starts):
                if brace == start:
                    bodies.append((nm, start, m.start()))
                    del starts[idx]
                    break
    return bodies


def declared(code):
    """[(偏移, 名字)] —— 所有 `func name(` 与 `let/var name =` 的声明点。"""
    out = []
    for pattern in (FUNC_DECL, LET_VAR_DECL):
        for m in pattern.finditer(code):
            out.append((m.start(1), m.group(1)))
    return out


def split_by_scope(code, bodies, decls):
    """把声明分成「文件顶层」与「某个类型体内」两份。"""
    top = set()
    in_body = {}
    for off, name in decls:
        holder = None
        for idx, (_, s, e) in enumerate(bodies):
            if s < off < e:
                holder = idx
                break
        if holder is None:
            top.add(name)
        else:
            in_body.setdefault(holder, set()).add(name)
    return top, in_body


def static_members(code, bodies):
    """名字 → {类型名}（只统计确实落在类型体内的 static 声明）。"""
    owner = {}
    for m in re.finditer(r"^", code, re.M):
        line_start = m.start()
        line_end = code.find("\n", line_start)
        line = code[line_start:line_end if line_end != -1 else len(code)]
        sm = STATIC_MEMBER.match(line)
        if not sm:
            continue
        name = sm.group(1)
        if len(name) < MIN_NAME:
            continue
        off = line_start + sm.start(1)
        for type_name, start, end in bodies:
            if start < off < end:
                owner.setdefault(name, set()).add(type_name)
                break
    return owner


def main():
    files = swift_files()
    if not files:
        print("❌ 没扫到任何 Swift 文件（工作目录不对？）")
        return 1

    owner = {}          # 静态成员名 → 所属类型集合（全项目）
    globals_ = set()    # 顶层（任何文件）声明的名字
    parsed = {}
    for path in files:
        raw = read(path)
        code = mask(raw)
        bodies = type_bodies(code)
        decls = declared(code)
        top, in_body = split_by_scope(code, bodies, decls)
        parsed[path] = (raw, code, bodies, in_body)
        globals_.update(top)
        for name, types in static_members(code, bodies).items():
            owner.setdefault(name, set()).update(types)

    findings = []
    for path in files:
        raw, code, bodies, in_body = parsed[path]
        for name, types in owner.items():
            if name in globals_:
                continue
            pattern = re.compile(r"(?<![.\w])" + re.escape(name) + r"[ \t]*\(")
            for m in pattern.finditer(code):
                off = m.start()
                # 声明点本身不算调用（`private func sectionLabel(...)`）
                head = code.rfind("\n", 0, off)
                if re.search(r"\bfunc[ \t]+$", code[head + 1:off]):
                    continue
                # 调用点是否落在「声明了该名字的类型体」内（含嵌套类型与外层类型）——
                # 词法作用域允许裸写。BatteryView / ControlView 各自都有
                # `private func sectionLabel(...)`，而 `sectionLabel` 同时又是
                # 令牌类型的静态成员：这条判定就是为它们而写的（第一版会误报 9 处）。
                enclosed = [idx for idx, (_, s, e) in enumerate(bodies) if s < off < e]
                if any(name in in_body.get(idx, ()) for idx in enclosed):
                    continue
                key = "%s:%s" % (path.replace(os.sep, "/"), name)
                if key in ALLOWED:
                    continue
                findings.append((path, line_of(code, off), name,
                                 " / ".join(sorted(types)),
                                 raw.splitlines()[line_of(code, off) - 1].strip()))

    seen = set()
    unique = []
    for f in sorted(findings, key=lambda x: (x[0], x[1], x[2])):
        k = (f[0], f[1], f[2])
        if k in seen:
            continue
        seen.add(k)
        unique.append(f)

    print("作用域纪律（静态成员跨类型调用必须带类型前缀）")
    print()
    print("  扫描 %d 个 Swift 文件；项目内的静态成员名 %d 个（长度 ≥ %d 才纳入判据）"
          % (len(files), len(owner), MIN_NAME))
    print()
    if not unique:
        print("✅ 没有越作用域的调用（每个静态成员跨类型调用都带了 `类型.` 前缀）")
        return 0

    print("❌ 以下调用没带类型前缀，而名字属于别的类型 —— 编译会报 cannot find ... in scope：")
    for path, line, name, who, text in unique:
        print("   %s:%d  %s(...)   ← 属于 %s" % (path.replace(os.sep, "/"), line, name, who))
        print("      %s" % text[:100])
    print()
    print("   修法：补上类型前缀（`%s.%s(...)`），或把该名字挪到调用点所在的作用域。"
          % (sorted(unique[0][3].split(" / "))[0], unique[0][2]))
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:      # 扫描器自己坏了也必须报红，不能静默通过
        print("❌ 扫描失败：%r" % (e,))
        sys.exit(1)
