#!/usr/bin/env python3
"""lexguard.py — 词法守卫：中文 / 全角字符出现在「代码位置」必然编译失败。

为什么需要它
------------
这个项目已经**三次**把 ASCII 双引号当成中文引号写进 Swift 字符串：

    Text("这一页是"去掉 Tab 栏"之后它们的家")   ← 真实发生过（MapSpineView.swift:568）
        .font(...)

Swift 在 `是"` 处提前结束字符串，接着把 `去掉` 当成标识符，于是报一条

    error: expected ',' separator

**报错位置和真正的错误原因没有明显关系**，而且每个来回都要等一整轮 macOS runner
（约 3 分钟）才发现。这个检查器把这一整类错误压缩到本地 0.2 秒。

判据（无假阳性）
----------------
**中文字符只可能出现在字符串字面量里**（注释里也允许）—— 合法的 Swift 代码位置
没有它。所以只要在「代码位置」遇到 CJK / 全角字符，那就是字符串边界错了。

> 唯一例外是「用中文当标识符」（`let 车速 = 1` 在 Swift 里合法）。本项目一处都没有；
> 真出现时会被列出来，一眼能判断，不会静默放过。

必须处理的语法（否则全是假阳性）
--------------------------------
`\\( )` **字符串插值**：插值里是一段真正的代码，而那段代码里往往还有字符串 ——

    "\\(store.caches["control"] != nil ? "已连接" : "未连接")"
        └────────── 插值内的代码 ──────────┘

本项目有 55 处这种写法。状态机若不跟踪 `\\(` 与配对的 `)`，就会把它们全报成错误
（这个检查器的第一版正是这样，55 处假阳性）。所以下面用**栈**来做：
进插值压栈并数括号，括号配平就弹回字符串。

顺带抓到的同族错误：字符串在行内未闭合、文件结束时字符串未闭合、全角标点写进代码、
「孤儿属性行」（真实发生过：批量删除声明块后留下光秃秃的 `@Model`，编译器只在文件尾报
`expected declaration`，与原因毫无关系 —— AppDataModel.swift，CI 才抓到）。
"""
import sys
from pathlib import Path

from _roots import swift_files

# 源码根目录，逐项必须存在（见 `_roots.py` 的说明）。
#  顶层 `CarKeeper/Models` 已删（2026-09-26）—— 本清单走 `swift_files`，对不存在的目录立即失败。
TK = ["CarKeeper/CarKeeper", "CarKeeper/Services",
      "CarKeeper/Design", "CarKeeper/Tests"]


def is_cjk(ch):
    o = ord(ch)
    return (
        0x3000 <= o <= 0x303F      # 、。「」〈〉《》
        or 0x4E00 <= o <= 0x9FFF   # 汉字
        or 0xFF00 <= o <= 0xFFEF   # 全角 ：（）？！，
        or 0x2010 <= o <= 0x2027   # – — ‘ ’ “ ” … † ‡
        or 0x2460 <= o <= 0x24FF   # ① ② ③
        or 0x2190 <= o <= 0x21FF   # ← → ↑ ↓
    )


def scan(path):
    """返回 [(行号, 说明)]。行号 1-based。

    状态：code / line_comment / block_comment / string / ml_string
    栈：  空 = 顶层代码；["string"] = 字符串里；["interp"] = 插值里的代码
          形如 [("string", None), ("interp", 括号深度), ...]
    """
    src = Path(path).read_text(encoding="utf-8")
    i, n, line = 0, len(src), 1
    state = "code"
    stack = []                       # 每项: ("string"|"ml_string"|"interp", 深度或 None)
    bad = []

    def close_frame():
        """关掉最内层（字符串闭合 / 插值括号配平），并回到**外层真正的状态**。

        注意：弹栈后如果新栈顶是插值，那意味着「现在处于插值里的代码」——
        状态必须是 code，而不是 interp。第一版写成 stack[-1][0] 直接赋值，
        于是插值未配平的那类错误在文件末尾检测不到。
        """
        nonlocal state
        if stack:
            stack.pop()
        top = stack[-1][0] if stack else None
        state = top if top in ("string", "ml_string") else "code"

    def snippet(pos):
        a = src.rfind("\n", 0, pos) + 1
        b = src.find("\n", pos)
        return src[a:(b if b != -1 else n)].strip()[:90]

    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""

        if ch == "\n":
            if state == "line_comment":
                state = "code"
            elif state == "string":
                bad.append((line, f"字符串在行内未闭合 → {snippet(i)}"))
                state = "code"
                # 行内未闭合：把这一层栈丢掉，避免后面全乱
                while stack and stack[-1][0] == "string":
                    stack.pop()
            line += 1
            i += 1
            continue

        # ---------- 字符串里 ----------
        if state in ("string", "ml_string"):
            if state == "string" and ch == "\\":
                if nxt == "(":                       # 进入插值
                    stack.append(("interp", 1))
                    state = "code"
                    i += 2
                    continue
                i += 2                                # 普通转义
                continue
            if state == "ml_string" and src[i:i + 2] == "\\(":
                stack.append(("interp", 1))
                state = "code"
                i += 2
                continue
            if state == "string" and ch == '"':
                close_frame()
                i += 1
                continue
            if state == "ml_string" and src[i:i + 3] == '"""':
                close_frame()
                i += 3
                continue
            i += 1
            continue

        # ---------- 注释里 ----------
        if state == "line_comment":
            i += 1
            continue
        if state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
                continue
            i += 1
            continue

        # ---------- 代码位置（顶层 or 插值内）----------
        inside_string = False                # 走到这里就说明不在字符串里
        if ch == "/" and nxt == "/":
            state = "line_comment"
            i += 2
            continue
        if ch == "/" and nxt == "*":
            state = "block_comment"
            i += 2
            continue
        if src[i:i + 3] == '"""':
            stack.append(("ml_string", None))
            state = "ml_string"
            i += 3
            continue
        if ch == '"':
            stack.append(("string", None))
            state = "string"
            i += 1
            continue

        if ch == "(" and stack and stack[-1][0] == "interp":
            stack[-1] = ("interp", stack[-1][1] + 1)
            i += 1
            continue
        if ch == ")" and stack and stack[-1][0] == "interp":
            depth = stack[-1][1] - 1
            if depth == 0:                   # 插值结束，弹回字符串
                close_frame()
            else:
                stack[-1] = ("interp", depth)
            i += 1
            continue

        if is_cjk(ch) and not inside_string:
            bad.append((line, f"代码位置出现中文「{ch}」→ {snippet(i)}"))
        i += 1

    if state == "string" or any(t == "string" for t, _ in stack):
        bad.append((line, "文件结束时字符串仍未闭合"))
    if any(t == "interp" for t, _ in stack):
        bad.append((line, "文件结束时字符串插值 \\( 未配平"))
    return bad


# ---------------------------------------------------------------------------
# 孤儿属性行：整行恰好是一个声明属性，而它后面再没有声明 —— 编译必报错。
# 判据刻意收窄到「整行 = 属性名」以避免假阳性：`@objc private func x()`
# 这种同行写法不算；只有批量删除声明块时才会留下这种光秃秃的行。
# 属性后面允许再跟一行属性（如 @Model 下一行是 @available），
# 但链条的末端必须见到真正的声明关键字。
# ---------------------------------------------------------------------------
ORPHAN_ATTRS = {"@Model", "@main", "@objc", "@objcMembers", "@discardableResult",
                "@IBAction", "@IBOutlet", "@NSManaged"}
DECL_KEYWORDS = ("class ", "struct ", "enum ", "actor ", "func ", "extension ",
                 "typealias ", "final ", "public ", "private ", "internal ",
                 "fileprivate ", "open ", "static ", "var ", "let ")


def orphan_attrs(path):
    """返回 [(行号, 说明)]。只看「整行恰好是声明属性」的行。"""
    lines = Path(path).read_text(encoding="utf-8").replace("\r\n", "\n").split("\n")
    bad = []
    for i, raw in enumerate(lines):
        t = raw.strip()
        if t not in ORPHAN_ATTRS:
            continue
        # 向后找第一个非空、非注释行
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or lines[j].strip().startswith(("//", "/*", "*"))):
            j += 1
        nxt = lines[j].strip() if j < len(lines) else ""
        if not nxt:
            bad.append((i + 1, f"{t} 之后直到文件尾都没有任何声明"))
        elif not (nxt.startswith("@") or nxt.startswith(DECL_KEYWORDS)):
            bad.append((i + 1, f"{t} 后面跟的是『{nxt[:40]}』而不是声明（属性后面只能再跟属性或声明）"))
    return bad


def main():
    files = swift_files(TK)
    hits = [(f, ln, why) for f in files for ln, why in scan(f)]
    orphans = [(f, ln, why) for f in files for ln, why in orphan_attrs(f)]

    print(f"扫描 {len(files)} 个 Swift 文件（状态机：代码 / 注释 / 字符串 / 多行字符串 / 插值）")
    print(f"字符串边界错误：{len(hits)} 处；孤儿属性行：{len(orphans)} 处")
    if not hits and not orphans:
        print("\n✅ 无『中文出现在代码位置』（嵌套双引号 / 未闭合字符串 / 全角标点）")
        print("✅ 无『孤儿属性行』（删除声明块后残留的 @Model / @main 等）")
        return 0
    for f, ln, why in hits:
        print(f"\n❌ 字符串边界错误（编译器会报一个与原因无关的错误）：")
        print(f"   {f}:{ln}")
        print(f"       {why}")
        break
    for f, ln, why in orphans:
        print(f"\n❌ 孤儿属性行（声明块被删后属性成了无主行，报 expected declaration）：")
        print(f"   {f}:{ln}")
        print(f"       {why}")
        break
    if hits:
        print("\n修法：把内层的 ASCII 双引号换成中文引号「」（或转义成 \\\"）。")
    if orphans:
        print("\n修法：把残留的属性行连同它原属的声明一起删掉（属性不是独立语句）。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
