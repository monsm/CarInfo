#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
paths.py —— project.yml 与 CI 工作流里声明的路径必须真的存在。

为什么需要它（不是理论风险，是已经发生过的一次失败）：

  2026-09-22 的 CI 在 `xcodegen generate` 这一步就挂了：

      Spec validation error: Target "CarKeeper" has a missing source directory
        ".../CarKeeper/HealthKit"

  `project.yml` 里声明了 `- path: HealthKit`，而那个目录的唯一文件在「删死代码」
  那一批里被删掉了。git 不跟踪空目录 —— 所以**开发机上目录还在**（被删文件留下的
  空壳），本地跑 `xcodegen generate` 一切正常，只有干净检出会失败。

  也就是说：这类问题本地怎么试都试不出来，代价是一整轮 macOS runner
  （约 3 分钟，而 macOS 额度按 10 倍计费），以及「连编译都没开始」的误导性日志。

  这个检查器在 Linux 上跑，秒级拦下同一类问题：
    ① `project.yml` 里声明的每个 source / resource / info 路径都要存在
    ② `.github/workflows/*.yml` 里点名的检查器（scan/xxx.py、check_style.js）都要存在
       （检查器改名而忘了改工作流时，CI 会以「文件不存在」失败）

  它**只看存在性**，不判断路径该不该在那儿 —— 删目录时漏删声明，正是它要抓的。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "CarKeeper", "project.yml")
SPEC_DIR = os.path.join(ROOT, "CarKeeper")   # xcodegen 以 spec 所在目录为基准
WORKFLOW_DIR = os.path.join(ROOT, ".github", "workflows")

# `- path: X` / `  path: X` —— 只此两种写法，且必须独占一行
PATH_LINE = re.compile(r"^\s*(?:-\s+)?path:\s*(\S+)\s*$", re.M)
# 工作流里点名的检查器
CHECKER_CALL = re.compile(r"(?:python3?|node)\s+([A-Za-z0-9_./-]+\.(?:py|js))")
# 工作流里的 `for s in a b c; do ... python3 scan/$s.py ... done`
LOOP_HEAD = re.compile(r"for\s+(\w+)\s+in\s+([^;\n]+);\s*do", re.M)
LOOP_BODY = re.compile(r"scan/\$(\w+)\.py")


def declared_paths(spec_path):
    """project.yml 里声明过的所有路径（保持出现顺序，去掉重复）"""
    with open(spec_path, encoding="utf-8") as f:
        text = f.read()
    seen, out = set(), []
    for raw in PATH_LINE.findall(text):
        p = raw.strip().strip('"').strip("'")
        if p and p not in seen:
            seen.add(p)
            out.append(p)
    return out


def workflow_checkers(workflow_dir):
    """工作流里点名的检查器脚本（相对仓库根）

    两种写法都要看得见：
      ① 直接写文件名：`python3 scan/scan.py`、`node CarKeeper/check_style.js`
      ② 循环：`for s in scan logic ...; do python3 scan/$s.py; done`
        （静态门禁用的就是第二种 —— 漏掉它，检查器改名而忘了改列表就查不出来）
    """
    out = []
    if not os.path.isdir(workflow_dir):
        return out
    for name in sorted(os.listdir(workflow_dir)):
        if not name.endswith((".yml", ".yaml")):
            continue
        with open(os.path.join(workflow_dir, name), encoding="utf-8") as f:
            text = f.read()
        for call in CHECKER_CALL.findall(text):
            if call not in out:
                out.append(call)
        # ② 循环写法：只有真的出现了 `scan/$var.py` 才认这组循环变量
        for var, items in LOOP_HEAD.findall(text):
            if var not in LOOP_BODY.findall(text):
                continue
            for token in items.split():
                token = token.strip().strip('"').strip("'")
                if not token or token.startswith("#"):
                    continue
                rel = f"scan/{token}.py"
                if rel not in out:
                    out.append(rel)
    return out


def main(argv):
    spec = argv[1] if len(argv) > 1 else SPEC
    if not os.path.isfile(spec):
        print(f"❌ 找不到 spec：{spec}")
        return 1

    problems = []

    paths = declared_paths(spec)
    print(f"project.yml 声明路径 {len(paths)} 条")
    for p in paths:
        # xcodegen 以 spec 所在目录解析相对路径
        target = p if os.path.isabs(p) else os.path.join(SPEC_DIR, p)
        ok = os.path.exists(target)
        print(("  ✅ " if ok else "  ❌ ") + p)
        if not ok:
            problems.append(f"project.yml 声明的路径不存在：{p}"
                            "（干净检出里没有它 → XcodeGen 会在 generate 阶段直接失败）")

    checkers = workflow_checkers(WORKFLOW_DIR) if spec == SPEC else []
    if checkers:
        print(f"\n工作流点名的检查器 {len(checkers)} 个")
        for c in checkers:
            ok = os.path.exists(os.path.join(ROOT, c))
            print(("  ✅ " if ok else "  ❌ ") + c)
            if not ok:
                problems.append(f"CI 工作流调用了不存在的脚本：{c}")

    print()
    if problems:
        print("❌ 高嫌疑：")
        for p in problems:
            print("   " + p)
        return 1
    print("✅ 声明的路径全部存在（project.yml / 工作流一致）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
