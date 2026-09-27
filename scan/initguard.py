#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
initguard.py —— 调用点的实参标签，必须能被某个**声明的 init** 接下

为什么需要它（2026-09-25 的 CI，一次报 4 处；这类错没有一条判据在管）：

    ArtTheme.swift:340:32: error: extra arguments at positions #3, #4, #5, #7, #8,
                                    #10, #11, #12, #13, #14, #15, #16, #17, #18, #19 in call
        return ArtThemeSpec(canvas: …, surface: …, raised: …, …)
    ArtTheme.swift:141:5: note: 'init(canvas:surface:label:accent:decor:allowsGlow:
                                   usesSerifTitles:displayWeight:displayTracking:
                                   preferredScheme:pageAccents:)' declared here

  根因不是拼错，是**Swift 的一条语言规则**：结构体一旦自己声明了任何 `init`，
  编译器就不再合成隐式的 memberwise init。`75c80ce` 给 `ArtThemeSpec` 加了一个
  「二十套主题」的便捷 init，四处照旧按全字段成员列表写的调用点于是当场全红 ——
  而它们每一个标签、每一个值都没错。

  这一类的共同形状是「**调用点的实参表**与「声明的参数表」对不上」，
  完全可以静态判，且不依赖类型推导。既有的判据全都看不见它：
    · `scan.py` 查「未声明的类型 / 构造」——`ArtThemeSpec` 声明得好好的；
    · `logic.py` / `trailing` 那些查的是名字与结构，不看实参表；
    · `delguard.py` 要求「旧版本里声明过这个名字」——这里删掉的是**参数**，不是名字。

判据（只收窄到能给出确定结论的那一条）：

  对一个**项目里声明、且在自己类型体内声明过 `init`** 的类型 T，取每个调用点 `T(...)`：

  ① 调用点至少有 **2 个带标签**的实参（`Foo(x)` 这种无标签写法与 `init(_:)` 从文本上
     分不开，不判 —— 宁可漏，不可噪）；
  ② 逐个比 T 的每一个 `init`：有一套参数能接下它就放行
     （每个实参标签都在参数表里、顺序一致、实参个数不超参数个数、
      最后一个实参之前的**无默认值**参数一个不缺）；
  ③ 每一个 `init` 都接不下 → 报红。这正是编译器那句 “extra arguments at positions #…”。

  为什么只判「init 写在类型体内」的：`init` 写在 **extension** 里**不会**抑制隐式
  memberwise init，那时按参数表判会**误报**（成员列表调用其实合法）。误报比漏报糟 ——
  一条误报就会让人开始绕过这个门禁。

  另一处收窄：类型名后面紧跟 `.` 的不算（那是别人身上的东西）；泛型实参只吃
  不含括号的那一层（`Foo<Bar>(…)` 认得，`Foo<Bar<Baz>>(…)` 不认）。

为什么它要和 `extguard.py` 共用那个 mask：两者都需要「注释与字符串换成等长空格」——
再抄一份就是第四个副本了（见 `extguard.py` 的 `mask`）。共用只为了这一段。

退出码：0 = 没有接不下的调用点；1 = 有（附文件:行号、标签差在哪、候选 init 长什么样）。
"""

import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _roots import assert_roots  # noqa: E402
from extguard import mask, body_span  # noqa: E402

#  顶层的 `CarKeeper/Models` 已删（2026-09-26，`AppDataModel.swift` 整份走掉）——
#  本清单走 `assert_roots`，对不存在的目录立即失败。
#  它与此文件 205 行那条“同名类型”的教训直接相关：那次误报的一半就是
#  `Models/AppDataModel.swift` 里那个 `TripRecord`，而它现在已经不在了。
ROOTS = [
    os.path.join("CarKeeper", "CarKeeper"),
    os.path.join("CarKeeper", "Services"),
    os.path.join("CarKeeper", "Design"),
]

# 类型声明：**允许缩进**（嵌套类型也要能认出来）。
# 缩进必须认：`DSSwipeStrip` 里那个 `struct Item { init(id:title:) }` 是**嵌套类型**，
# 它的 init 不属于外层。不认缩进时，那个 `init(id:title:)` 会被算成 `DSSwipeStrip` 的
# 候选 init —— 而 `DSSwipeStrip(items:selectedID:follow:)` 用的是隐式 memberwise init
# （本类型自己没有 init，合成照旧）—— 那就是一条**误报**（本门禁的第一条）。
TYPE_DECL = re.compile(
    r"^[ \t]*(?:(?:@\w+(?:\([^)]*\))?)[ \t]+)*"
    r"(?:(?:public|internal|private|fileprivate|final|indirect)[ \t]+)*"
    r"(?P<kind>struct|class|enum|actor)[ \t]+(?P<name>[A-Za-z_]\w*)",
    re.M,
)
INIT_DECL = re.compile(r"(?<![\w.])init[?!]?\s*\(")
# 调用点：项目类型名 +（可选的简单泛型实参）+ `(`
CALL = re.compile(r"(?<![\w.])(?P<name>[A-Z][A-Za-z0-9_]*)\s*(?:<[^<>()]*>\s*)?\(")


def swift_files():
    out = []
    for base in ROOTS:
        if not os.path.isdir(base):
            continue
        for dp, _dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".swift"):
                    out.append(os.path.join(dp, f).replace("\\", "/"))
    return out


def split_top(text, seps=","):
    """按顶层分隔符切分（忽略括号 / 中括号 / 花括号里的分隔符与泛型尖括号）。"""
    parts, depth, cur = [], 0, []
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if depth == 0 and ch in seps:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    parts.append("".join(cur))
    return parts


def param_label(param):
    """一个形参的实参标签；`_ x: T` 与 `_ : T` 记作 None（调用点不写标签）。"""
    p = param.strip()
    if not p:
        return None, True
    has_default = "=" in split_top(p, "=")[-1] if False else bool(re.search(r"=\s*\S", p))
    head = p.split(":", 1)[0] if ":" in p else None
    if head is None:
        # 没有冒号：可能是 `_` 或裸类型（罕见），当作无标签
        return None, has_default
    tokens = head.split()
    if not tokens:
        return None, has_default
    if tokens[0] == "_":
        return None, has_default
    return tokens[-1], has_default


def init_params(body, start):
    """body[start] 处的 `(` 起，取这个 init 的参数表 → [(label, has_default), …]"""
    depth, i = 0, start
    while i < len(body):
        if body[i] == "(":
            depth += 1
        elif body[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    inner = body[start + 1:i]
    if not inner.strip():
        return []
    return [param_label(p) for p in split_top(inner)]


def call_labels(text, open_paren):
    """调用点实参表的标签序列；只要有一个实参没有标签就返回 None（不判）。"""
    depth, i = 0, open_paren
    while i < len(text):
        if text[i] in "([{":
            depth += 1
        elif text[i] in ")]}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    inner = text[open_paren + 1:i]
    if not inner.strip():
        return []
    labels = []
    for arg in split_top(inner):
        if not arg.strip():
            continue
        m = re.match(r"\s*(?:try\s+|await\s+|&\s*)?([a-z_]\w*)\s*:(?!:)", arg)
        if not m:
            return None
        labels.append(m.group(1))
    return labels


def accepts(params, labels):
    """这个 init 的参数表能接下这串标签吗。"""
    if any(lbl is None for lbl, _ in params):
        return None  # 参数表里有不写标签的形参 —— 文本层面分不清，放弃判断
    names = [lbl for lbl, _ in params]
    if len(labels) > len(names):
        return False
    pos = -1
    used = []
    for lbl in labels:
        if lbl not in names:
            return False
        idx = names.index(lbl, pos + 1)
        pos = idx
        used.append(idx)
    # 实参最大位置之前的**无默认值**参数一个不能缺
    last = max(used) if used else -1
    for i, (lbl, has_default) in enumerate(params):
        if i < last and not has_default and lbl not in labels:
            return False
    return True


def main():
    assert_roots(ROOTS)
    files = swift_files()

    # ① 收集：类型体内声明过 init 的类型 → 它的 init 参数表
    #
    # 两条必须的收窄（都是被**误报**逼出来的，只报真错才算有用的门禁）：
    #   · 嵌套类型体内的 init **不算**外层的（`DSSwipeStrip.Items` 的 init 曾把
    #     `DSSwipeStrip(items:selectedID:follow:)` 判成“接不下”，而那个调用是合法的）；
    #   · **同名类型多于一处的，整条跳过** —— 嵌套类型与顶层类型可以同名
    #     （`AppStore.TripRecord` 与 `Models/AppDataModel.swift` 的 `TripRecord` 就是），
    #     而“裸名字对应哪一个”要看调用点的上下文，文本层面无法确定 → 不判。
    inits = {}
    seen = {}
    for p in files:
        src = io.open(p, encoding="utf-8", errors="ignore").read()
        masked = mask(src)
        spans = []
        for m in TYPE_DECL.finditer(masked):
            brace = masked.find("{", m.end() - 1)
            if brace < 0:
                continue
            end = body_span(masked, brace)
            spans.append((m.group("name"), brace, end))
            seen.setdefault(m.group("name"), []).append(f"{p}:{masked.count(chr(10), 0, m.start()) + 1}")
        for name, brace, end in spans:
            nested = [(s, e) for n, s, e in spans if brace < s < end]
            for im in INIT_DECL.finditer(masked[brace:end]):
                at = brace + im.start()
                if any(s < at < e for s, e in nested):
                    continue
                body = masked[brace:end]
                paren = body.index("(", im.end() - 1)
                inits.setdefault(name, []).append(init_params(body, paren))
    dupes = {n: v for n, v in seen.items() if len(v) > 1}
    for n in dupes:
        inits.pop(n, None)

    bad = []
    for p in files:
        src = io.open(p, encoding="utf-8", errors="ignore").read()
        masked = mask(src)
        lines = masked.split("\n")
        for m in CALL.finditer(masked):
            name = m.group("name")
            params_list = inits.get(name)
            if not params_list:
                continue
            labels = call_labels(masked, m.end() - 1)
            if labels is None or len(labels) < 2:
                continue
            verdicts = [accepts(pp, labels) for pp in params_list]
            if True in verdicts or None in verdicts:
                continue
            line = masked.count("\n", 0, m.start()) + 1
            extra = [l for l in labels if all(l not in [x for x, _ in pp] for pp in params_list)]
            bad.append((p, line, name, labels, params_list, extra))

    if not bad:
        print(f"扫了 {len(files)} 个源文件：{len(inits)} 个自带 init 的类型，调用点全部接得下")
        print("   （每种类型体内声明的 init 都逐套比过实参标签）")
        print(f"   跳过 {len(dupes)} 个同名类型（裸名字对应哪一个要看调用点上下文，不猜）")
        return 0

    print(f"❌ {len(bad)} 处调用点没有任何一个 init 接得下：\n")
    for p, line, name, labels, params_list, extra in bad:
        print(f"  {p}:{line}")
        print(f"     调用点标签：{'、'.join(labels)}")
        for pp in params_list:
            print(f"     候选 init：{'、'.join(x for x, _ in pp) or '（无参）'}")
        if extra:
            print(f"     ⚠️ 这些标签没有任何 init 收：{'、'.join(extra)}")
        print()
    print("  改法：给这个调用点补一套能接下的 init 参数表，或者按声明的那一套改调用。")
    print("  注意：结构体一旦自己声明了任何 init，Swift 就不再合成 memberwise init ——")
    print("  「参数都没错却全红」通常就是这条规则（ArtThemeSpec 就是这么红的）。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
