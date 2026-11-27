#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
enumguard.py —— SDK 枚举成员不许凭印象拼（只认已对着 Apple 文档核过的成员表）

为什么需要它（2026-09-23 真实事故，真实代价）：

    .accessibilityAction(.scrollUp) { step(-1) }
    .accessibilityAction(.scrollDown) { step(1) }

    → /CarKeeper/Design/ArcStack.swift:85:35:
      error: type 'AccessibilityActionKind' has no member 'scrollUp'

  这两个名字**不存在**：`AccessibilityActionKind` 的成员是
  default / delete / escape / magicTap / showMenu（Apple 文档 JSON 的
  topicSections 列得很清楚）。而当时 24 项门禁**全绿**：

    · scan.py 的名字白名单只检查「这个名字在不在表里」——
      `accessibilityAction` 在（它确实存在），于是整条调用放行；
    · 更糟的是，**白名单里的说明文字也把不存在的成员写成了事实**
      （「.scrollUp / .scrollDown 为 AccessibilityActionKind 的静态成员」），
      于是那份说明反过来成了「已经核实过」的证据。白名单里的一句话也是断言，
      而当时的机制没有任何东西去检查它；
    · 点号前缀的枚举简写（`.scrollUp`）不落在 scan.py 的「未知成员」判据里 ——
      那条判据只看**项目自己声明的类型**的成员（`Foo.bar`），SDK 类型的简写成员
      从头到尾没人看过；
    · 只有编译器看得见 —— 而编译器在 macOS runner 上，一轮 3 分钟（额度按 10 倍计）。

  同一类事故的另一个形态（同一天也在这一轮里）：把「子视图的状态」与「外层的
  卡表」拆到两个结构里，于是 `X.sectionCards` 这种「instance member 当类型成员用」
  的写法也只在 CI 上才报。那一类已经用结构本身解决（卡表与状态同住一个视图，
  且改成 `private`），不需要检查器 —— 检查器只负责剩下这一类：
  **枚举成员是名字，写错了没有任何静态信号。**

判据（窄到不会有假阳性，而不是宽到能猜意图）：

  只检查**登记在下面表里的调用**，而且只检查「`(` 后面紧跟 `.`」这一种写法 ——
  即枚举简写。允许 `(` 与 `.` 之间换行，因为长修饰符链经常换行。

    .accessibilityAction(.showMenu) { }      → 检查 showMenu 在不在表里
    .accessibilityAction(named: Text("x"))    → 不检查（第一个参数是标签，不是简写）
    .textCase(.uppercase)                     → 检查 uppercase 在不在表里
    .accessibilityElement(children: .contain) → 检查 contain（表里声明了标签 `children`）

  表里带 `arg` 的族才看带标签的实参，而且**只认那一个标签** ——
  否则 `.foo(title: .bar)` 这种到处都有的写法会被大量误判。

  合法的非简写形态（传变量、传 `nil`、传显式构造）一律放行 —— 那些不可能写错名字。

它**不看**什么：类型推断、参数个数、修饰符挂在什么视图上。这些是编译器的事，
本文件不去冒充编译器。

已知边界（读源码时看到的就这些，写在明处）：
  · 这是**表驱动**，不是类型推断：表里没有的调用族就完全不受检查。加一族时必须
    先取 Apple 文档 JSON（`https://developer.apple.com/tutorials/data/documentation/
    <模块>/<类型>.json`，看 `topicSections` 里的成员列表），把成员抄进表里，
    再把出处 URL 写在同一行 —— 这一条是硬要求，因为**凭印象写这张表，
    就正好复现了这个文件要防的那个错误**。
  · 注释与字符串字面量里的 `.scrollUp` 不会误报：`code_only()` 先把它们抹成空格
    （本文件自己的文档里就写着 `.scrollUp`）。

退出码：0 = 表里每个调用族用的都是已核成员；1 = 出现了表外的成员（或表本身空掉了）。
"""

import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _roots import EXISTING_ROOTS, swift_files


SDK_ENUM_ARGS = {
    "accessibilityAction": {
        "param": "AccessibilityActionKind",
        "doc": "https://developer.apple.com/documentation/swiftui/accessibilityactionkind",
        "members": {"default", "delete", "escape", "magicTap", "showMenu"},
    },
    "textCase": {
        "param": "Text.Case",
        "doc": "https://developer.apple.com/documentation/swiftui/text/case",
        "members": {"lowercase", "uppercase"},
    },
    "accessibilityElement": {
        "param": "AccessibilityChildBehavior",
        "arg": "children",
        "doc": "https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior",
        "members": {"combine", "contain", "ignore"},
    },
    "scrollBounceBehavior": {
        "param": "ScrollBounceBehavior",
        "doc": "https://developer.apple.com/documentation/swiftui/scrollbouncebehavior",
        "members": {"automatic", "always", "basedOnSize"},
    },
}
if not SDK_ENUM_ARGS:
    print("❌ enumguard 的成员表是空的 —— 检查范围为零，退出码按失败处理。")
    sys.exit(1)


def code_only(text):
    """把注释与字符串字面量的**内容**抹成空格，其余原样保留（行号与列号不变）。

    必须做这一步：ArcStack 的注释里就明明白白写着 `.scrollUp`——
    那是在解释这个错误，不是在犯这个错误。
    """
    out, i, n = [], 0, len(text)

    def blank(chunk):
        return "".join(ch if ch == "\n" else " " for ch in chunk)

    while i < n:
        c = text[i]
        if c == "/" and text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(blank(text[i:j]))
            i = j
            continue
        if c == "/" and text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append(blank(text[i:j]))
            i = j
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                if text[j] == "\n":
                    break
                j += 1
            out.append('"' + " " * (j - i - 1))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def read(path):
    with io.open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def scan_file(path):
    """返回 [(行号, 该行原文, 为什么)]

    判据与组都从表里生成，所以「加一族」只是往表里加一行。
    """
    raw = read(path)
    raw_lines = raw.split("\n")
    code = code_only(raw)

    hits = []
    for name, spec in sorted(SDK_ENUM_ARGS.items()):
        mid = (re.escape(spec["arg"]) + r"\s*:\s*") if spec.get("arg") else ""
        pat = re.compile(r"\b" + re.escape(name) + r"\s*\(\s*" + mid +
                         r"\.([A-Za-z_][A-Za-z0-9_]*)")
        for m in pat.finditer(code):
            member = m.group(1)
            if member in spec["members"]:
                continue
            line_no = code.count("\n", 0, m.start()) + 1
            shown = (f"{spec['arg']}: .{member}" if spec.get("arg") else f".{member}")
            hits.append((line_no, raw_lines[line_no - 1].strip(),
                         f"`{name}({shown})` —— `{spec['param']}` 没有这个成员。"
                         f"已核成员：{' / '.join(sorted(spec['members']))}"
                         f"（出处 {spec['doc']}）"))
    return hits


def main():
    files = swift_files(EXISTING_ROOTS)
    hits = []
    for f in files:
        for line_no, line, why in scan_file(f):
            hits.append((f, line_no, line, why))

    print(f"扫描 Swift 文件 {len(files)} 个，已核调用族 {len(SDK_ENUM_ARGS)} 个")
    for name, spec in sorted(SDK_ENUM_ARGS.items()):
        form = (f"{spec['arg']}: ." if spec.get("arg") else ".") + spec["param"]
        print(f"  · {name}({form}) —— {len(spec['members'])} 个成员")
    if hits:
        print()
        for f, i, line, why in hits:
            print(f"  ❌ {f}:{i}")
            print(f"     {line[:110]}")
            print(f"     → {why}")
        print()
        print("  规则见 scan/enumguard.py 顶部：SDK 枚举成员必须是表里已核过的名字。")
        print("  要加成员：先取 Apple 文档 JSON 的 topicSections，再连出处一起写进表。")
        return 1
    print("✅ 表内调用族用的都是已核成员（没有凭印象拼的枚举简写）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
