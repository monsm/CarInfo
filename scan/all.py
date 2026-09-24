#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
本地一键跑齐全部门禁 —— 「清单只有一个来源，就是 CI 工作流本身」

为什么需要它（2026-09-24 的真实事故）：
  HANDOFF §1.1 一直写着本地该跑的那个 `for s in ...` 循环，而它的清单**与 CI 逐字同序**。
  那一轮改了 8 个文件，本地却只挑了 8 条里的一半跑（`scan.py` / `check_style` / `delguard`
  / `enumguard` …），于是三条红一条都没被本地看见 —— 全部由 CI 的静态门报出来：

    · `copy.py`     新写的空态里含实现词「接口」（同一个问题报两次：同一句话写了两遍）
    · `lintcfg.py`  `MapSpineView.swift` 涨到 1206 行，越过 1200 阈值
    · `oneentry.py` 判据 ③ 盯的是「档位在卡头里出现两次」，而那一轮的设计恰好把它改成一次

  三条里前两条是**真 bug**，本地全清单跑一遍就会当场红 —— 代价只是几十秒。
  靠「记得跑那个循环」显然不成立（它已经被写在文档里、还是漏了），所以这里把它变成一条命令。

判据（它自己不判任何东西，只做两件事）：
  ① 从 `.github/workflows/ios-build.yml` **解析**出 CI 真正跑的清单 —— 不复制一份。
     复制一份就会漂移：CI 加了门禁而这里没加，本地照样是一片绿。
  ② 逐条跑，**跑完所有条**（CI 用 `bash -e`，红在第一条就停；本地要的是一次看到全部红），
     最后给一张汇总表；有任何一条红则以 1 退出。

  解析失败（工作流改写法、清单读不出来）**立即失败并说明** —— 「没跑」与「跑了没问题」
  在输出上长得一模一样，正是这个仓库反复踩的那一类坑（见 `paths.py` 头注）。

注：子进程用 `sys.executable`（不写死 `python3`）—— 本地是哪个解释器，门禁就是哪个；
    CI 由工作流自己指定 python3，两边都不靠 PATH 猜。

退出码：0 = 全绿；1 = 有红（或清单解析失败）。
"""

import io
import os
import re
import subprocess
import sys

WORKFLOW = os.path.join(".github", "workflows", "ios-build.yml")
STYLE = os.path.join("CarKeeper", "check_style.js")


def read(path):
    with io.open(path, encoding="utf-8", errors="ignore") as f:
        return f.read()


def gates_from_workflow(text):
    """CI 的清单是唯一的来源。找不到就返回 None（调用方报错退出）。"""
    m = re.search(r"for\s+s\s+in\s+([^;]+);\s*do", text)
    if not m:
        return None
    names = m.group(1).split()
    if not names:
        return None
    if "node " + STYLE.replace(os.sep, "/") not in text.replace("\\", "/"):
        return None
    return names


def run(cmd):
    """跑一条，返回 (rc, 合并输出)。"""
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    return p.returncode, out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    if not os.path.exists(WORKFLOW):
        print(f"❌ 找不到 {WORKFLOW} —— 清单只能从这里读")
        return 1
    names = gates_from_workflow(read(WORKFLOW))
    if names is None:
        print(f"❌ 没能从 {WORKFLOW} 里解析出检查器清单。")
        print("   它应当是 `for s in <名字列表>; do python3 scan/$s.py; done` 这一段。")
        print("   工作流改了写法就要同步改这里 —— 绝不能在这份脚本里另抄一份清单：")
        print("   抄一份的后果是 CI 加了门禁、本地却不知道，于是本地永远绿。")
        return 1

    print(f"清单来源：{WORKFLOW}（不在此处复制，避免两边漂移）")
    print(f"共 {len(names)} 项门禁 + check_style.js\n")

    failed = []

    rc, out = run(["node", STYLE])
    if rc != 0:
        failed.append("check_style.js")
        print("=" * 72)
        print("✗ check_style.js")
        print("=" * 72)
        print(out.rstrip())
    else:
        print(f"  ✅ {'check_style.js':<16} {out.strip().splitlines()[-1][:60] if out.strip() else ''}")

    for name in names:
        rc, out = run([sys.executable, os.path.join("scan", name + ".py")])
        if rc != 0:
            failed.append(name + ".py")
            print("=" * 72)
            print(f"✗ scan/{name}.py")
            print("=" * 72)
            print(out.rstrip())
        else:
            tail = out.strip().splitlines()[-1] if out.strip() else ""
            print(f"  ✅ {name + '.py':<16} {tail[:60]}")

    print()
    if failed:
        print(f"❌ {len(failed)} / {len(names) + 1} 条红：" + "、".join(failed))
        print("   逐条修掉再提交 —— CI 的静态门用的是同一份清单，本地红它一定红。")
        return 1

    print(f"✅ 全部 {len(names) + 1} 条通过（本地能验的就是这些）。")
    print("   编译仍然只有 CI 能验：Swift 工具链不在这台机器上。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
