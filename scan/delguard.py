#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
删声明守卫 —— 「声明被删掉/重写了，使用还在」

为什么需要它（两次真实事故，都占了一整轮 macOS runner）：

  ① `e78a344`（DSSwipeStrip）：撤掉 `pv` 状态时顺手把 `pvValue(_:gap:)` 函数本体也删了，
     5 处调用（透镜跟手、行跟手、吸附反算）还在 —— 3 条
     `error: cannot find 'pvValue' in scope`。
  ② `55794c4`（ArcStack）：重写 `shapeScroll` 的注释时把**声明本身**写没了，
     3 处使用（形变阈值、拖动跟手、落点）还在 —— 同样 3 条
     `error: cannot find 'shapeScroll' in scope`。

  两次都不是拼错名字，也不是缺类型：名字在**旧版本**里明明声明过，只是这一轮的编辑
  把它连同注释一起重写掉了。既有的检查器全都看不见这一类：
    · `scan.py` 查「用了但项目里没声明」——它看的是**当前**这一份代码，
      而这一份里确实没有这个名字，于是它把「没有声明」当成「SDK 提供」；
    · `scopeguard.py` 查跨作用域的静态成员调用，不管成员存不存在；
    · `orphans.py` 查「声明了但没人用」——正好是反方向。
  唯一能看见它的是编译器，而编译器住在按 10 倍计费的 macOS runner 上。

判据（只收窄到能给出确定结论的一条）：

  对每个源文件，取**旧版本**（默认 `HEAD~1`，拿不到就 `HEAD`）与**新版本**（工作区）：

  ① 旧版本里 **成员级**声明过这个名字（缩进 ≤ 4 空格的 `let` / `var` / `func` ——
     类型自己的属性、方法、`@State` 之类；函数体里的局部量缩进更深，不算）；
  ② 新版本里**没有**任何同名成员级声明；
  ③ 新版本里这个名字**还在代码里出现**（`//`、`///`、`/* */` 里的提及不算；
     把它当局部量声明的那些行也不算 —— 那种情况下它解析到局部量，编译得过）。

  三条同时成立 = 「这条声明被删了，但还有人调用它」。Swift 里这是编译错误，
  没有例外 —— 所以这里直接失败，而不是警告。

  另加一道**降噪**：如果这个名字在新版本的**其它文件**里被成员级声明了，就不报。
  它对应真实的一类编辑：把几个成员从骨架文件挪进内容文件（`2f088df` 把三个图层内容
  从 `MapSpineView` 挪进 `MapSpineLayers`）——同一个类型的 extension 在另一个文件里，
  调用照旧编译得过。代价是「同名成员真的落在别的类型上」这种错会漏（宁可漏，不可噪：
  一条误报就会让人开始绕过这个门禁）。

  为什么窗口是 `HEAD~1` 而不是「本次未提交的改动」：CI 上工作区**就是** HEAD，
  拿未提交改动去比永远为空（一个恒为 0 的绿灯不算绿灯）。比 `HEAD~1` 则两种场合都成立：
  CI 上它看的是**这次提交**改掉了什么，本地它同时覆盖「刚提交的那一笔」与「手上还在改的」。
  代价是 CI 的 checkout 要 `fetch-depth: 2`（见 `.github/workflows/ios-build.yml`）。

自测（拿上面两次真事故当探针，两条都必须报出来）：

  python3 scan/delguard.py --from e78a344~1 --to e78a344    # 应报 pvValue
  python3 scan/delguard.py --from 55794c4~1 --to 55794c4    # 应报 shapeScroll
"""

import argparse
import os
import re
import subprocess
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 报告范围：编进 App 主 target 的源码目录（与 scan/anorphans.py 同一套）
SCOPE_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Models",
    "CarKeeper/Design",
]

# 成员级声明：缩进 ≤ 4 空格，且行内有 let / var / func + 名字。
# 为什么卡缩进：函数体里的局部量缩进 ≥ 8，把它当成「声明」会让判定立刻失真
#（局部量被改名、成员还在，是最常见的一类假阳性）。
MEMBER_DECL = re.compile(
    r"^ {0,4}(?:@[A-Za-z_][\w.]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|internal|private|fileprivate|open|final|static|class|lazy|"
    r"nonisolated|weak|unowned|override|mutating)\s+)*"
    r"(?:let|var|func)\s+([A-Za-z_]\w*)\b",
    re.M,
)

# 「这个字出现在这一行」用词边界；短名字（< 5）不查 —— 它们太容易撞上局部量
#（`nav` / `row` 这类），收窄的代价是漏掉极短的成员，收益是零误报（scopeguard 同一条取舍）。
MIN_NAME_LEN = 5

# 把它当**局部量**声明的行：`let x =` / `if let x` / `for x in` / `guard var x` …
LOCAL_BINDING = r"(?:let|var|for)\s+%s\b"


def run_git(args):
    """跑一条 git 命令；失败返回 None（浅克隆里 HEAD~1 不存在就是这种情况）。"""
    try:
        p = subprocess.run(["git"] + args, cwd=PROJECT_ROOT,
                           capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
    except OSError:
        return None
    return p.stdout if p.returncode == 0 else None


def strip_comments(text):
    """去掉 `/* */`、`//`、`///` —— 注释里提到某个名字不是编译错误。

    ⚠️ 只做「文档与注释不算」这一件事，不碰字符串：字符串插值里用了一个被删的名字
    同样是编译错误，所以字符串**照查**。
    """
    text = re.sub(r"/\*(?:.|\n)*?\*/", "", text)
    text = re.sub(r"(?m)//.*$", "", text)
    return text


def member_names(text):
    """这个文件里成员级声明的名字（去注释后，只看缩进 ≤ 4 的 let/var/func）。"""
    return set(MEMBER_DECL.findall(strip_comments(text)))


def uses_of(name, text):
    """新版本里**仍在代码中**用到这个名字的行号（注释不算，局部量声明行也不算）。"""
    body = strip_comments(text)
    binding = re.compile(LOCAL_BINDING % re.escape(name))
    hit = re.compile(r"\b%s\b" % re.escape(name))
    out = []
    for i, line in enumerate(body.split("\n"), start=1):
        if not hit.search(line):
            continue
        if binding.search(line):      # 这一行是在**声明**同名局部量，不是使用
            continue
        out.append((i, line.strip()))
    return out


def scope_files():
    """范围内的 .swift 文件（相对仓库根，用 / 分隔）。"""
    out = []
    for d in SCOPE_DIRS:
        root = os.path.join(PROJECT_ROOT, d)
        for dirpath, _dirnames, filenames in os.walk(root):
            for f in filenames:
                if f.endswith(".swift"):
                    full = os.path.join(dirpath, f)
                    out.append(os.path.relpath(full, PROJECT_ROOT).replace("\\", "/"))
    return sorted(out)


def all_member_names(rev=None):
    """整个项目的成员级名字（新版本）。

    它的唯一用途是降噪：名字被挪到另一个文件（同类型的 extension）时，
    在这个文件里看不到声明，但项目里还有 —— 那种情况编译得过，不该报。
    给了 `rev` 就从那个提交读，否则读工作区。
    """
    names = set()
    if rev:
        listing = run_git(["ls-tree", "-r", "--name-only", rev, "--"] + SCOPE_DIRS) or ""
        for rel in listing.split("\n"):
            rel = rel.strip()
            if not rel.endswith(".swift"):
                continue
            text = run_git(["show", "%s:%s" % (rev, rel)])
            if text:
                names |= member_names(text)
        return names
    for rel in scope_files():
        try:
            with open(os.path.join(PROJECT_ROOT, rel), encoding="utf-8") as fh:
                names |= member_names(fh.read())
        except OSError:
            continue
    return names


def old_and_new(args):
    """→ [(相对路径, 旧文本, 新文本)]。只比**真的会变**的那些文件。"""
    pairs = []
    if args.rev_from and args.rev_to:
        changed = run_git(["diff", "--name-only", args.rev_from, args.rev_to]) or ""
        for rel in changed.split("\n"):
            rel = rel.strip()
            if not rel.endswith(".swift") or not os.path.exists(os.path.join(PROJECT_ROOT, rel)):
                continue
            old = run_git(["show", "%s:%s" % (args.rev_from, rel)])
            new = run_git(["show", "%s:%s" % (args.rev_to, rel)])
            if old is not None and new is not None:
                pairs.append((rel, old, new))
        return pairs

    # 默认：旧版本优先取 HEAD~1（那次提交改了什么），取不到退回 HEAD
    #（浅克隆 / 第一个提交；此时它退化成「工作区与 HEAD 比」，本地仍然有用）
    base = args.base or "HEAD~1"
    if run_git(["rev-parse", "--verify", base]) is None:
        base = "HEAD"
    for rel in scope_files():
        old = run_git(["show", "%s:%s" % (base, rel)])
        if old is None:
            continue
        try:
            with open(os.path.join(PROJECT_ROOT, rel), encoding="utf-8") as fh:
                new = fh.read()
        except OSError:
            continue
        if old != new:
            pairs.append((rel, old, new))
    return pairs


def main():
    ap = argparse.ArgumentParser(description="删声明守卫")
    ap.add_argument("--base", help="旧版本（默认 HEAD~1，取不到就退回 HEAD）")
    ap.add_argument("--from", dest="rev_from", help="自测用：旧提交")
    ap.add_argument("--to", dest="rev_to", help="自测用：新提交")
    args = ap.parse_args()

    pairs = old_and_new(args)
    if not pairs:
        print("本次没有变化的 Swift 文件 —— 没有「删了声明、使用还在」的名字")
        return 0

    # 新版本全项目的成员名（含被挪到别的文件的那些）—— 见文件头的「降噪」。
    global_new = all_member_names(args.rev_to if args.rev_to else None)

    bad = []
    for rel, old, new in pairs:
        old_names = member_names(old)
        for name in sorted(old_names):
            if len(name) < MIN_NAME_LEN or name in global_new:
                continue
            hits = uses_of(name, new)
            if hits:
                bad.append((rel, name, hits))

    print("比对了 %d 个文件" % len(pairs))
    if not bad:
        print("✅ 没有「删了声明、使用还在」的名字")
        return 0

    for rel, name, hits in bad:
        print("\n%s: `%s` 在旧版本里是成员级声明，新版本里没有声明了，但这些行还在用它：" % (rel, name))
        for lineno, text in hits[:8]:
            print("  %d: %s" % (lineno, text))
        if len(hits) > 8:
            print("  …还有 %d 行" % (len(hits) - 8))
    print("\n❌ %d 个名字「声明没了、使用还在」—— 这是编译错误，不用等 macOS runner"
          % len(bad))
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
