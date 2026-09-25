#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
文案检查器 —— 「界面上每一句都要有存在的理由」

为什么需要它（真实事故与真实抱怨）：
  · 用户原话：「每个界面的文案太繁琐，该精简精简，能看懂就行，无用的文字直接删」。
    上一轮按「删解释性括注 / 删复述 / 压缩空状态」手工过了一遍 —— 但那种通读
    **判断一次只生效一次**：下一个页面照样能写出「点下面那个按钮，这里就会显示结果」。
  · 更早的几类也同源：把已经显示在屏幕上的东西再讲一遍（复述）、给空状态配一句比喻、
    在页脚解释数字怎么算出来的（教学）、以及把实现细节写成界面词（「缓存」「报文」「字段」）。

它禁的不是「长」，是三件具体的事：
  ① **开发词**：`缓存 / 报文 / 字段 / 响应 / 接口` 这类词描述的是我们怎么取数据，
     不是这辆车怎么样。用户不需要知道我们内部怎么存 —— 出现在界面文案里就报红。
     （例外：`Features/Dev/DevView.swift` 是**排障页**：它正是「清掉缓存」那一个按钮
     所在的页面，也写着「只清空车况、充电、定位…缓存」这样的句子 ——
     在这一页里「缓存」是用户要做的动作，不是内部实现。）
  ② **复述/教学句式**：`点下面` `点上面` `就会出现` `就可以了` `请注意` ——
     屏幕已经把这件事说清楚了，再说一遍是噪音。
  ③ **长度**：一条界面文案超过 `MAX_LEN` 个字符（中文按字计）报红。
     长度不是品格，但它是「这句话在替用户想什么」的最好代理指标：
     一句话越长，越可能是在解释我们自己。

不算文案的东西（跳过）：
  · CSV 表头（含 `,`）与正则/匹配模式（含 `|`）
  · UserDefaults 键（`carkeeper_*`）、符号名、文件路径
  · 注释行（`//` 开头）—— 注释是给维护者的，不受此约束

退出码：0 = 全部通过；1 = 有需要精简的句子。
"""

import io
import os
import re
import sys

from _roots import assert_roots

APP = os.path.join("CarKeeper", "CarKeeper")
SERVICES = os.path.join("CarKeeper", "Services")
DESIGN = os.path.join("CarKeeper", "Design")
MODELS = os.path.join("CarKeeper", "Models")

# 这份清单曾包含 SHARED / WIDGETS / WATCH 三项 —— 那三个目录随小组件体系一起删了，
# 而它们在这里**不会报错**：不存在的目录只是被安静跳过。
# 于是「检查范围缩小」与「这一片没有界面文案」在输出上完全一样。
# `_roots.swift_files` 现在把这种沉默变成立即失败。
SCAN_DIRS = [APP, SERVICES, DESIGN, MODELS]

# 排障页：它的正文里「缓存」是**用户要做的动作**（那一页有「清除缓存」与它的确认句），
# 不是我们内部实现的名词 —— 不能按「开发词」判。⚠️ 这一条的理由在 2026-09-25 第九轮
# 变过一次：它原来叫「设计令牌页」（那一页曾挂着色板与字体样张，第 6 条已删），
# 而**豁免本身仍然需要** —— 变了的是它为什么需要。
EXEMPT_FILES = {
    os.path.join(APP, "Features", "Dev", "DevView.swift").replace("\\", "/"),
}

MAX_LEN = 30

# ①② 判据的词表。每一条都对应真实删过的一句话，不是凭感觉列的。
#
# 硬禁词只有四个，且它们有一个共同点：描述的是**我们怎么拿到数据**，
# 而不是**这辆车怎么样**。`响应`不在列：它在这里的正事是「等车辆响应」（车回话了），
# 是界面语言；滥用它的是 HTTP，而那不该出现在界面上。
IMPL_WORDS = ["缓存", "报文", "字段", "接口"]
TEACH_PATTERNS = ["点下面", "点上面", "就会出现", "就可以了", "请注意", "点一下那个"]

# 字面量里的插值表达式（`\(...)`）在屏幕上不是字符，量长度时先摘掉。
# 必须按括号配平：`\(powerKW.map { String(format: "%.1f", $0) }...)` 里
# 还有一层 `)`，按「到下一个右括号」摘会把后面的正文一起吃进去（上一版就是这样）。
def strip_interp(s):
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] == "(":
            depth = 0
            i += 2
            while i < len(s):
                if s[i] == "(":
                    depth += 1
                elif s[i] == ")":
                    if depth == 0:
                        i += 1
                        break
                    depth -= 1
                i += 1
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


# 日志/调试串不是界面文案：它们以 `tag:` 开头（如 `parseMessages:`），写在 NSLog 里。
LOG_LIKE = re.compile(r"^[a-z][A-Za-z0-9_]{2,}:")

CJK = re.compile(r"[\u4e00-\u9fff]")
STR = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def read(path):
    with io.open(path, encoding="utf-8", errors="ignore") as f:
        return f.read()


def swift_files():
    # 先确认清单里的目录真的在。这一步看着多余，其实正是它拦住了
    # 「删掉一个目录 → 检查范围悄悄变小 → 依旧输出 0 问题 ✅」。
    assert_roots(SCAN_DIRS)
    out = []
    for root in SCAN_DIRS:
        for dirpath, _, names in os.walk(root):
            if "baseline" in dirpath:
                continue
            for n in names:
                if n.endswith(".swift"):
                    out.append(os.path.join(dirpath, n).replace("\\", "/"))
    return sorted(set(out))


def is_copy(s):
    """这条字面量算不算「界面文案」。"""
    if not CJK.search(s):
        return False
    if "," in s or "|" in s:          # CSV 表头 / 正则
        return False
    if s.startswith("carkeeper") or "://" in s or s.startswith("widget_") or s.startswith("watch_"):
        return False
    if re.fullmatch(r"[A-Za-z0-9_./<> %-]+", s):   # 符号名 / 路径 / 格式串
        return False
    return True


def main():
    hits = []
    total = 0
    for f in swift_files():
        if f in EXEMPT_FILES:
            continue
        text = read(f)
        for i, line in enumerate(text.split("\n"), 1):
            st = line.strip()
            if st.startswith("//") or st.startswith("*"):
                continue
            for m in STR.finditer(line):
                s = m.group(1)
                if not is_copy(s):
                    continue
                if LOG_LIKE.match(strip_interp(s).strip()):
                    continue
                total += 1
                why = []
                for w in IMPL_WORDS:
                    if w in s:
                        why.append(f"实现词「{w}」")
                for p in TEACH_PATTERNS:
                    if p in s:
                        why.append(f"复述句式「{p}」")
                # 长度按**屏幕上的那一行**算：摘掉插值、按行拆开（多行块只看最长的一行）。
                # HTML 模板（导出报告）不算界面文案 —— 它不在这块屏幕上。
                visible = strip_interp(s)
                if LOG_LIKE.match(visible.strip()):
                    continue
                if "<" not in visible:
                    # 拆行：真实换行与转义的 `\n` 都算 —— 多行块只看最长的那一行
                    rows = visible.replace("\\n", "\n").split("\n")
                    for row in [r.strip() for r in rows if r.strip()]:
                        if len(row) > MAX_LEN:
                            why.append(f"过长（{len(row)} > {MAX_LEN}）：{row}")
                if why:
                    hits.append((f, i, s, why))

    print(f"界面文案 {total} 条；需要精简 {len(hits)} 条")
    if hits:
        print()
        for f, i, s, why in hits:
            print(f"  ❌ {f}:{i}")
            print(f"     {s}")
            print(f"     → {'；'.join(why)}")
        print()
        print("  规则见 scan/copy.py 顶部：开发词 / 复述句式 / 长度。")
        return 1
    print("✅ 每一条都有存在的理由（无实现词、无复述句式、无超长句）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
