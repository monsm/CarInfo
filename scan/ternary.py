#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ternary.py —— 三元运算符的 `?` 必须和前面的 token 分开（否则它变成可选链）

为什么需要它（2026-09-23 真实事故，真实代价）：

    message: searchText.isEmpty? "搜页面、车牌、行程、指令、充电记录。"
                                  ^ 少了空格

    Swift 把 `isEmpty?` 读成**可选链**，于是这一行成了
    「对 Bool 做可选链，后面再接一个裸字符串」→
        error: expected ',' separator

  这一行是「精简文案」那轮手工改三元时留下的，而当时 **21 项门禁全绿**。
  它们没漏跑，是这一类根本不在任何一项的判据里：

    · scan.py  查括号/引号/#if 配平 —— 这里三者**都是配平的**（少了空格，不是少了符号）
    · lexguard / copy.py 等查的是**词与句子**，不看运算符 —— `?` 有没有空格与文案无关
    · 只有编译器看得见 —— 而编译器在 macOS runner 上，一轮 3 分钟（额度按 10 倍计）

  也就是说：这是「静态上可见、但没人看」的一类。同一个事故在 2026-09-22
  也发生过一次（`TripsEventsView` 的 `id:` 参数），两次都是靠 CI 日志发现的。
  这条检查器把它搬到 Linux 上、秒级。

判据（只认「不可能合法」的形态，不猜意图）：

  `?` 紧贴在某个 token 后面，跟一段空白，然后接一个**不可能是可选链**的字符。
  合法的写法只有这几种，所以它们都被显式放行：

    · `foo?.bar` / `foo?[0]` / `foo?(x)` —— 可选链只能接 `.` `[` `(`
    · `foo ?? "兜底"` —— 空合运算符（两个 `?` 贴在一起，另一条判据管）
    · `Int?` / `String? {` / `-> String? in` —— **类型可选**：后面接的是
      `= , ) ] } > & | : {` 或行尾。这是本判据最大的假阳性来源，
      所以上一版拿截断行试的时候，85 条报错里 84 条是它 —— 全部显式放行。
    · `try?` / `as?` / `is?` —— 前面是关键字，不是标识符

  唯一的边界情况：`?` 写在行尾。类型可选在行尾很常见（`let x: Date?`），
  所以行尾**不报**；只有下一行的第一个非空字符是字符串字面量（`"`）时才报 ——
  那个形态（`cond?` 换行接 `"文案"`）同样不可能是合法 Swift。

它**不看**什么：一句代码写得好不好、三元该不该用。缩进、命名、可读性都不在这里。

已知边界（读源码时看到的就这些，写在明处）：
  · 原始字符串 `#"..."#` 与裸正则字面量 `/.../` 没有出现，所以没有为它们做状态跟踪。
    哪天用了，本文件的 `code_only` 需要同步加分支 —— 否则字面量里的 `?` 会被当成代码。
  · `case let x?:`（可选模式）里 `?` 紧接 `:`，属于合法写法，不在判据内。

退出码：0 = 全部通过；1 = 有 `?` 贴住了前一个 token。
"""

import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _roots import EXISTING_ROOTS, swift_files

SAFE_NEXT = set(".,([=,)]}&|:{>?")
SAFE_WORDS = {"in"}
SAFE_PREV_WORDS = {"try", "as", "is"}

GLOVE = re.compile(r"([A-Za-z0-9_\)\]\"'])\?([ \t]*)(\S?)")


def code_only(text):
    """把注释与字符串字面量的**内容**抹成空格，其余原样保留（行号与列号不变）。

    必须做这一步：字面量正文里出现 `? "` 完全正常 —— 例如一句中文提示里引用了
    另一句话（`他说"这样?""`），那不是代码。上一版对整行做正则，
    就报过一条注释里的例子。

    四种要抹掉的东西：行注释、块注释、多行字符串（`\"\"\"`）、单行字符串。
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
    """返回 [(行号, 该行原文, 为什么)]"""
    raw_lines = read(path).split("\n")
    code_lines = code_only("\n".join(raw_lines)).split("\n")
    hits = []
    for i, line in enumerate(code_lines):
        for m in GLOVE.finditer(line):
            prev, gap, nxt = m.group(1), m.group(2), m.group(3)
            head = line[:m.start(1) + 1]
            word = re.search(r"[A-Za-z_][A-Za-z0-9_]*$", head)
            if word and word.group(0) in SAFE_PREV_WORDS:
                continue
            if nxt in SAFE_NEXT:
                continue
            if nxt == "":
                nxt2 = ""
                for j in range(i + 1, min(i + 4, len(code_lines))):
                    s = code_lines[j].strip()
                    if s:
                        nxt2 = s[0]
                        break
                if nxt2 != '"':
                    continue
            nxt_word = re.match(r"[A-Za-z_][A-Za-z0-9_]*", line[m.start(3):] or "")
            if nxt_word and nxt_word.group(0) in SAFE_WORDS:
                continue
            hits.append((i + 1, raw_lines[i].strip(),
                         f"`{prev}?` 贴在一起 —— `?` 前面必须有空格，"
                         f"否则被读成可选链（`{prev}? {nxt}...`）"))
    return hits


def main():
    files = swift_files(EXISTING_ROOTS)
    hits = []
    for f in files:
        for line_no, line, why in scan_file(f):
            hits.append((f, line_no, line, why))

    print(f"扫描 Swift 文件 {len(files)} 个")
    if hits:
        print()
        for f, i, line, why in hits:
            print(f"  ❌ {f}:{i}")
            print(f"     {line[:110]}")
            print(f"     → {why}")
        print()
        print("  规则见 scan/ternary.py 顶部：三元 `?` 前必须有空格。")
        return 1
    print("✅ 没有任何 `?` 贴在前一个 token 上（三元运算符写法合法）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
