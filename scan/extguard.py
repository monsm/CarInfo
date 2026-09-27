#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extguard.py —— extension 的三条铁律（这一课是 **CI 红的**）

为什么需要它（真实事故，2026-09-25 的 CI，红在 macOS runner 上）：

    MapSpineBottomBar.swift:71:13: error: declaration is only valid at file scope
        private extension Double {

  上一轮的某个 agent 为了让 `MapSpineView.swift` 回到 `lintcfg.py` 的 1200 行阈值以内，
  把「底条整行横拖」那块搬进了一个新文件，而那个文件里犯了同一类的三个错：

    ① 嵌套 extension —— `private extension Double` 写在 `extension MapSpineView { … }` **体内**。
       Swift 不允许；声明必须在文件层。
    ② extension 里的**实例存储属性** —— `@State private var barDragBase: Double?`。
       extension 只能加计算属性与方法；存储属性必须住在类型本体的声明里。
    ③ 跨文件碰了别处的 `private` —— 它读写 `modePosition` / `barOpen` / `modeIndex` /
       `barRowWidth`，而这四个在 `MapSpineView.swift` 里都是 `private`（`private` 的作用域是
       **文件**）。同一个错还独立出现在 `ControlFit.swift`（用 `ControlView.filteredRuns`）。

  三个错各自都编译不过，而 29 条门禁全绿、CI 连编两次都红 —— 因为当时没有任何一条判据
  知道「extension 该长什么样」。这三条就是那一课。

判据（三条，按上面的编号）：

  ① **extension 必须在文件层**：行首除修饰符外没有缩进。嵌套一律报红。
  ② **extension 的直接成员层不许有实例存储属性**：
     · `var x: T` / `let x: T` 后面没有 `{`（不是计算属性）→ 报；
     · `var x = 值` / `let x = 值` → 报（extension 里带初值的成员也是存储属性）；
     · 带属性包装器的成员（`@State` / `@ObservedObject` / `@Environment` 等）→ 报；
     · **`static` / `class` 放行**（extension 里放静态存储属性是合法的），
       `@ViewBuilder` 这类结果构建器也放行（它们修饰的是计算属性）。
  ③ **跨文件 extension 不许碰别处的 `private` / `fileprivate` 成员**：
     在 A 文件里对 B 文件声明的类型写 `extension` 时，用到 B 里的私有成员就是
     「名字在项目里、但在调用点不在作用域」。

  **收窄（宁可漏报，不要误报）**：
    · 判据 ③ 只认**裸名字**（`filteredRuns`），不认 `self.name` 形式；名字短于 6 个字符
      也不认（`store` / `body` 这类太容易与局部变量撞名）；
    · 判据 ③ 跳过「本文件自己也声明过同名东西」的情况（那就是另一个名字解析）；
    · 判据 ② 只认属性包装器名单里的那几个 —— 认不出的一律放行。
  这三条收窄都写在明处：它们会让某些真错误漏掉，而误报会让整条门禁被无视。

退出码：0 = 三条都干净；1 = 有违规。
"""

import io
import os
import re
import sys

from _roots import assert_roots

APP = os.path.join("CarKeeper", "CarKeeper")
SCOPE_DIRS = [
    APP,
    os.path.join("CarKeeper", "Services"),
    #  顶层 `CarKeeper/Models` 已删（2026-09-26）—— 本清单走 `assert_roots`。
    os.path.join("CarKeeper", "Design"),
]

# 属性包装器：名单里的这些是**存储**属性的标志（extension 里放它们＝编译错）。
# 刻意不写 `@ViewBuilder` / `@MainActor` / `@discardableResult`：它们修饰的可能是计算属性。
WRAPPERS = (
    "State", "StateObject", "ObservedObject", "EnvironmentObject", "Environment",
    "Binding", "AppStorage", "SceneStorage", "FocusState", "GestureState",
    "Published", "NSFetchRequest", "Query", "Relationship", "Namespace",
)
WRAP_RE = re.compile(r"@(?:" + "|".join(WRAPPERS) + r")\b")

MODS = r"(?:private|fileprivate|public|internal|open|final|nonisolated|override|mutating|lazy|weak|unowned|indirect)"
DECL_MODS = r"(?:static|class)"

NESTED_EXT = re.compile(r"^[ \t]+(?:@\w+(?:\([^)]*\))?[ \t]+)?(?:" + MODS + r"[ \t]+)*extension[ \t]+\w")
MEMBER = re.compile(
    r"^(?P<indent>[ \t]+)"
    r"(?:@\w+(?:\([^)]*\))?[ \t]+)*"
    r"(?:" + MODS + r"[ \t]+)*"
    r"(?P<static>" + DECL_MODS + r"[ \t]+)?"
    r"(?P<kind>var|let)[ \t]+(?P<name>[A-Za-z_]\w*)"
)
# ⚠️ `re.M` 必须有：少了它 `^` 只在文件开头匹配，收集到的类型数是 0 ——
# 那样这个检查器会「全绿」地放行一切（下一行的私有成员收集同样是空的）。
# `scopeguard.py` 的头注里记过同一个坑，我这里又踩了一次（探针当场捉到：
# 注入的跨文件私有成员一个字都没报）。
TYPE_BODY = re.compile(
    r"^(?:" + MODS + r"[ \t]+)*(?:struct|class|enum|actor)[ \t]+([A-Za-z_]\w*)[^{]*\{",
    re.M,
)

MIN_NAME = 6


def swift_files():
    out = []
    for base in SCOPE_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".swift"):
                    out.append(os.path.join(dp, f).replace("\\", "/"))
    return out


def mask(text):
    """注释与字符串换成空格（保留换行）—— 判据只看代码，注释里的名字不算使用。"""
    out = list(text)
    i, n = 0, len(text)
    CODE, LINE, BLOCK, STR = range(4)
    st = CODE
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if st == CODE:
            if c == "/" and nxt == "/":
                # ⚠️ 第一根斜杠也要清掉。原来只清后续字符，于是每一行注释开头都留下一个
                # `/`：它不干扰本文件那几条判据（它们不匹配 `/`），但它会把**任何按
                # 实参/表达式切分的下游判据**弄脏 —— `initguard.py` 就是因为一个注释行
                # 开头的 `/` 而认不出紧跟其后的 `labelTertiary:`（那是它的第一次误判）。
                out[i] = " "
                st = LINE
            elif c == "/" and nxt == "*":
                st = BLOCK
                out[i] = out[i + 1] = " "
                i += 2
                continue
            elif c == '"':
                st = STR
            i += 1
        elif st == LINE:
            if c == "\n":
                st = CODE
            else:
                out[i] = " "
            i += 1
        elif st == BLOCK:
            if c == "*" and nxt == "/":
                out[i] = out[i + 1] = " "
                i += 2
                st = CODE
                continue
            if c != "\n":
                out[i] = " "
            i += 1
        else:  # STR
            if c == "\\":
                out[i] = " "
                if i + 1 < n:
                    out[i + 1] = " "
                i += 2
                continue
            if c == '"':
                st = CODE
                i += 1
                continue
            if c != "\n":
                out[i] = " "
            i += 1
    return "".join(out)


def body_span(masked, open_brace):
    """从 `{` 起，返回（结束下标, 结束行）。按花括号配对。"""
    depth = 0
    i = open_brace
    while i < len(masked):
        if masked[i] == "{":
            depth += 1
        elif masked[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(masked)


def scan_file(path, masked, priv_map):
    """返回 [(行号, 为什么)]。"""
    out = []
    lines = masked.split("\n")
    raw = io.open(path, encoding="utf-8", errors="ignore").read().split("\n")

    # ---- ① 嵌套 extension ----
    for i, ln in enumerate(raw, 1):
        if NESTED_EXT.match(ln):
            out.append((i, "extension 嵌在别的声明里（Swift 只允许文件层）"))

    # ---- ② extension 里的实例存储属性 ----
    i = 0
    while i < len(lines):
        if re.match(r"^(?:" + MODS + r"[ \t]+)*extension[ \t]+\w", lines[i]):
            brace = lines[i].find("{")
            if brace >= 0:
                offset = sum(len(l) + 1 for l in lines[:i]) + brace
                end = body_span(masked, offset)
                end_line = masked.count("\n", 0, end)
                # ⚠️ 初始深度就是 extension 自己那个 `{` —— 少了它，成员层会被算成 0，
                # 而函数体里的局部变量会被算成「成员层」（第一版就是这么误报 17 处的）。
                # 成员层 = 1；函数体 / 闭包体 = ≥2。
                depth = lines[i].count("{") - lines[i].count("}")
                for j in range(i, end_line + 1):
                    ln = lines[j]
                    if j > i:
                        depth += ln.count("{") - ln.count("}")
                    if j > i and depth == 1:
                        m = MEMBER.match(ln)
                        if m and not m.group("static"):
                            rest = ln[m.end():]
                            has_body = "{" in rest
                            wrapped = bool(WRAP_RE.search(ln))
                            if wrapped:
                                out.append((j + 1, "extension 里的存储属性（带属性包装器 %s）"
                                            % WRAP_RE.search(ln).group(0)))
                            elif not has_body:
                                out.append((j + 1, "extension 里的存储属性（`%s` 没有计算体）"
                                            % m.group("name")))
                    if j == end_line:
                        break
                i = end_line
        i += 1

    # ---- ③ 跨文件碰别处的 private ----
    i = 0
    while i < len(lines):
        m = re.match(r"^(?:" + MODS + r"[ \t]+)*extension[ \t]+([A-Za-z_]\w*)", lines[i])
        if m:
            tname = m.group(1)
            owner, priv = priv_map.get(tname, (None, set()))
            brace = lines[i].find("{")
            if priv and owner and owner != path and brace >= 0:
                offset = sum(len(l) + 1 for l in lines[:i]) + brace
                end = body_span(masked, offset)
                end_line = masked.count("\n", 0, end)
                for j in range(i + 1, end_line + 1):
                    code = lines[j]
                    for nm in sorted(priv):
                        if re.search(r"(?<![\w.])" + re.escape(nm) + r"\b", code):
                            # 本文件自己也声明过同名东西 → 那是另一个名字，放行
                            if re.search(r"\b(?:var|let|func)[ \t]+" + re.escape(nm) + r"\b", masked):
                                continue
                            out.append((j + 1, "用了 `%s.%s` —— 它在 %s 里是私有的（`private` 的作用域是文件）"
                                        % (tname, nm, os.path.basename(owner))))
                            break
        i += 1
    return out


def main():
    assert_roots(SCOPE_DIRS)
    paths = swift_files()
    print(f"扫了 {len(paths)} 个源文件（extension 三条铁律）")

    # 每个顶层类型 → （声明它的文件, 它的私有成员名）
    priv_map = {}
    for p in paths:
        masked = mask(io.open(p, encoding="utf-8", errors="ignore").read())
        for m in TYPE_BODY.finditer(masked):
            name = m.group(1)
            brace = masked.find("{", m.start())
            end = body_span(masked, brace)
            body = masked[brace:end]
            got = set()
            for ln in body.split("\n"):
                mm = re.match(r"^[ \t]+(?:@\w+(?:\([^)]*\))?[ \t]+)*(?:"
                              + MODS + r"[ \t]+)*(?:"
                              + DECL_MODS + r"[ \t]+)?(?:private|fileprivate)[ \t]+"
                              r"(?:var|let|func)[ \t]+([A-Za-z_]\w*)", ln)
                if mm and len(mm.group(1)) >= MIN_NAME:
                    got.add(mm.group(1))
            if got:
                # 同一个名字只可能有一个顶层类型（同名＝重复声明），所以这里是并集：
                # owner 保留**最先**收集到的那一个文件（扩展体里再声明同名类型属病态，不管）。
                owner, priv = priv_map.get(name, (p, set()))
                priv_map[name] = (owner, priv | got)

    bad = []
    for p in paths:
        masked = mask(io.open(p, encoding="utf-8", errors="ignore").read())
        for ln, why in scan_file(p, masked, priv_map):
            bad.append((p, ln, why))

    if bad:
        print(f"\n❌ {len(bad)} 处 extension 写得编译不过（或碰不到）：")
        for p, ln, why in bad:
            print(f"  {p}:{ln}  {why}")
        print("\n改法：")
        print("  · extension 放到文件层（不嵌套）；")
        print("  · 存储属性搬回类型本体的声明里（extension 只加计算属性与方法，static 可以）；")
        print("  · 跨文件要用的成员去掉 `private`（并在声明处写清为什么 —— 这是本仓的惯例）。")
        return 1
    print("\n✅ extension 都在文件层、都不含存储属性、也没碰别处的私有成员")
    return 0


if __name__ == "__main__":
    sys.exit(main())
