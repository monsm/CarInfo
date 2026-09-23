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

import glob
import os
import re
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "CarKeeper", "project.yml")
SPEC_DIR = os.path.join(ROOT, "CarKeeper")   # xcodegen 以 spec 所在目录为基准
WORKFLOW_DIR = os.path.join(ROOT, ".github", "workflows")

# 明确「不参与 CI 编译」的 target。
#
# 默认值是「每个 target 都要被编到」—— 因为「写了但没人编」就是「改了等于没改，
# 而且没有报错」。豁免只能显式给，而且必须写出理由：靠沉默蒙过去是不行的。
CI_UNCOVERED_TARGETS = {
    "CarKeeperTests": "纯函数测试 target。它在 CI 上要占一整个 macOS runner"
                      "（额度按 10 倍计费），2026-09-22 按用户要求停跑。"
                      "target 与 scheme 都保留，开发机上用 Xcode 直接跑（Product > Test）。",
}

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


def covered_sources(paths):
    """把声明的 source 路径展开成「真的会参与编译的 Swift 文件」集合

    存在的意义（2026-09-22 差点出的事）：
    仓库里有两条 Services/ 与两条 Models/ —— `CarKeeper/Services/`（在 spec 里声明了）
    与 `CarKeeper/CarKeeper/Services/`（在 `- path: CarKeeper/` 里）。
    两边都在编译，没问题；但如果哪天改的那份不在任何声明之下，
    它就成了「磁盘上有、编译器永远不看」的文件 —— 改了等于没改，而且毫无报错。
    """
    covered = set()
    for rel in paths:
        base = os.path.join(SPEC_DIR, rel.rstrip('/'))
        if os.path.isfile(base):
            norm = os.path.normpath(base).replace(os.sep, '/')
            if norm.endswith('.swift'):
                covered.add(norm)
            continue
        for p in glob.glob(os.path.join(base, '**', '*.swift'), recursive=True):
            covered.add(os.path.normpath(p).replace(os.sep, '/'))
    return covered


def stray_swift(paths):
    """磁盘上的 Swift 文件里，不参与任何 target 编译的那些"""
    covered = covered_sources(paths)
    root = ROOT.replace(os.sep, '/')
    stray = []
    for p in glob.glob(os.path.join(ROOT, 'CarKeeper', '**', '*.swift'), recursive=True):
        norm = os.path.normpath(p).replace(os.sep, '/')
        if '/scan/' in norm:
            continue            # 检查器的基线副本（不是源码）
        if norm in covered:
            continue
        stray.append(norm[len(root) + 1:] if norm.startswith(root) else norm)
    return sorted(stray)


SPEC_SOURCES_ITEM = re.compile(r"^    - path:\s*(\S+)\s*$")


def target_source_files(spec_text):
    """把 spec 里每个 target 的 sources 展开成「真参与编译的 Swift 文件」列表

    为什么要展开到文件级（而不是只看路径存不存在）：
      · 同一个 basename 落在**同一个** target 里两次 = 重复符号，编译必挂；
      · 同一个 basename 落在**两个** target 里、但来自两条不同的路径 = 两份副本，
        改一份忘另一份就会漂移。`WatchApp/WatchApp.swift` 与
        `WatchApp/WatchApp/Sources/WatchApp.swift` 就是这种「故意的两份」——
        本检查器的职责不是拆掉它们，而是保证它们始终一致。

    只认 `    - path: X` 这一种写法（spec 里就是这种），子键用缩进判定。
    """
    lines = spec_text.split('\n')
    start = next((i for i, l in enumerate(lines) if l.rstrip() == 'targets:'), None)
    if start is None:
        return {}
    end = len(lines)
    for i in range(start + 1, len(lines)):
        l = lines[i]
        if l and not l.startswith(' ') and l.rstrip().endswith(':'):
            end = i
            break

    targets, cur, in_sources = {}, None, False
    for i in range(start + 1, end):
        l = lines[i]
        m = re.match(r'^  ([A-Za-z0-9_]+):\s*$', l)
        if m:
            cur, in_sources = m.group(1), False
            targets.setdefault(cur, [])
            continue
        if cur is None:
            continue
        if re.match(r'^    sources:\s*(\[\s*\])?\s*$', l):
            in_sources = True
            continue
        if not in_sources:
            continue
        # 回到 4 空格缩进的非列表键（如 settings: / dependencies:）就说明 sources 块结束
        if re.match(r'^    [A-Za-z]', l) and not l.startswith('    - '):
            in_sources = False
            continue
        mp = SPEC_SOURCES_ITEM.match(l)
        if mp:
            targets[cur].append([mp.group(1), []])
            continue
        if re.match(r'^      excludes:\s*$', l):
            continue
        me = re.match(r"^      - '?([^']+)'?\s*$", l)
        if me and targets[cur]:
            targets[cur][-1][1].append(me.group(1).strip())
    return targets


def _exclude_matcher(pat):
    """把 XcodeGen 的 excludes 通配（`**/.*`）翻成正则"""
    rx, i = '', 0
    while i < len(pat):
        if pat.startswith('**/', i):
            rx += '(?:.*/)?'
            i += 3
        elif pat.startswith('**', i):
            rx += '.*'
            i += 2
        elif pat[i] == '*':
            rx += '[^/]*'
            i += 1
        elif pat[i] == '?':
            rx += '[^/]'
            i += 1
        else:
            rx += re.escape(pat[i])
            i += 1
    return re.compile('^' + rx + '$')


def expand_sources(entries):
    """sources 条目 → 归一化后的 Swift 文件绝对路径集合"""
    out = set()
    for rel, excludes in entries:
        base = os.path.join(SPEC_DIR, rel.rstrip('/'))
        excl = [_exclude_matcher(e) for e in excludes]
        if os.path.isfile(base):
            cands, relbase = [base], os.path.dirname(base)
        else:
            cands, relbase = glob.glob(os.path.join(base, '**', '*.swift'), recursive=True), base
        for p in cands:
            if not p.endswith('.swift'):
                continue
            relp = os.path.relpath(p, relbase).replace(os.sep, '/')
            if any(e.match(relp) for e in excl):
                continue
            out.add(os.path.normpath(p).replace(os.sep, '/'))
    return out


def workflow_build_targets(workflow_dir):
    """CI 里 `for pair in Target:sdk ...; do` 这种编译体检清单点名的 target

    为什么必须读它：scheme 的 build action 只列了主 App，其余 target 是
    靠这段循环编的。清单漏了谁，谁就永远不被编译 —— 这正是 2026-09-22 之前的
    真实状态（WidgetBundle / WatchApp / WatchKitApp 从未编译过）。
    """
    out = []
    if not os.path.isdir(workflow_dir):
        return out
    for name in sorted(os.listdir(workflow_dir)):
        if not name.endswith(('.yml', '.yaml')):
            continue
        with open(os.path.join(workflow_dir, name), encoding='utf-8') as f:
            text = f.read()
        for var, items in LOOP_HEAD.findall(text):
            if var == 's':          # `for s in scan logic ...` 是检查器列表，不是 target
                continue
            for token in items.split():
                token = token.strip().strip('"').strip("'")
                if not token or token.startswith('#'):
                    continue
                t = token.split(':')[0]
                if t not in out:
                    out.append(t)
    return out


def workflow_test_schemes(workflow_dir):
    """工作流里跑过 `xcodebuild test` 的 scheme —— 只有它们才会真的去编 test target

    为什么不能只看「scheme 的 test action 里列了谁」：那样的声明不等于真被执行。
    2026-09-22 删掉单元测试 job 之后，`CarKeeper` scheme 的 test action 里依旧
    写着 `CarKeeperTests`，但 CI 已经不再跑 `xcodebuild test` 了 ——
    若只看声明，这个 target 会显成「已覆盖」，而它实际上一行都没被编过。
    """
    out = set()
    if not os.path.isdir(workflow_dir):
        return out
    for name in sorted(os.listdir(workflow_dir)):
        if not name.endswith(('.yml', '.yaml')):
            continue
        with open(os.path.join(workflow_dir, name), encoding='utf-8') as f:
            text = f.read()
        if not re.search(r'xcodebuild\s+test', text):
            continue
        out.update(re.findall(r'-scheme\s+([A-Za-z0-9_.-]+)', text))
    return out


def scheme_targets(data, only=None, phases=('build', 'test')):
    """schemes: 里 build / test 两个阶段点名的 target

    `only` 用来限定「只看被工作流引用的那些 scheme」：一个从没被 CI 跑过的 scheme
    （即使是 spec 里声明的）并不能让它的 target 真的被编到。
    """
    out = set()
    for _name, body in (data.get('schemes') or {}).items():
        if only is not None and _name not in only:
            continue
        for phase in phases:
            blk = (body or {}).get(phase) or {}
            v = blk.get('targets')
            if isinstance(v, list):
                out.update(x for x in v if isinstance(x, str))
            elif isinstance(v, dict):
                out.update(v.keys())
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


def workflow_schemes(workflow_dir):
    """工作流里 `-scheme X` 用到的 scheme 名"""
    out = []
    if not os.path.isdir(workflow_dir):
        return out
    for name in sorted(os.listdir(workflow_dir)):
        if not name.endswith((".yml", ".yaml")):
            continue
        with open(os.path.join(workflow_dir, name), encoding="utf-8") as f:
            for s in re.findall(r"-scheme\s+([A-Za-z0-9_.-]+)", f.read()):
                if s not in out:
                    out.append(s)
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

    # 工作流里 `-scheme X` 用到的名字必须在 spec 里有交代，而且规则比想象的严：
    #
    #   • `schemes:` **缺席**时：XcodeGen 会为每个 target 自动生成方案，
    #     所以 `-scheme <target 名>` 是可用的。
    #   • `schemes:` **一旦存在**：只生成其中列出的那些，其它 target 不再自动生成。
    #
    # 这条教训是 2026-09-22 真实踩到的：那时 `schemes:` 里只有 CarKeeperTests，
    # 而 CI 用 `-scheme CarKeeper` —— 干净检出里根本没有这个方案
    # （「does not contain a scheme named CarKeeper」），本地 Xcode 却会自动补一个，
    # 所以怎么试都试不出来。**只看「是不是 target 名」是不够的**，
    # 这正是本检查器第一版犯过的错（反向自测当场抳住了）。
    if spec == SPEC:
        import yaml  # 工作流与 spec 都是 YAML；runner 上装了 pyyaml
        with open(spec, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        declared = set(data.get("schemes") or {})
        targets = set(data.get("targets") or {})
        allowed = declared if declared else (targets | {data.get("name", "")})
        schemes = workflow_schemes(WORKFLOW_DIR)
        if schemes:
            mode = "只认显式声明的 schemes" if declared else "schemes 缺席 → 每个 target 都有自动方案"
            print(f"\n工作流用到的 scheme {len(schemes)} 个（{mode}）")
            for s in schemes:
                ok = s in allowed
                print(("  ✅ " if ok else "  ❌ ") + s)
                if not ok:
                    problems.append(f"CI 用 -scheme {s}，但 spec 既没有这个 scheme"
                                    "（schemes: 存在时 XcodeGen 不再为其它 target 自动生成方案）")

    if spec == SPEC:
        stray = stray_swift(paths)
        if stray:
            print(f"\n⚠️ 磁盘上 {len(stray)} 个 Swift 文件不在任何已声明的 source 之下")
            for s in stray:
                print("  ❌ " + s)
            problems.append(f"{len(stray)} 个 Swift 文件永远不会被编译（改了等于没改）")

    # ---- 文件级规则：每个 target 实际编译哪些 .swift ------------------------
    # 三条都属于「编译器会说、但要等一整轮 macOS runner」的那一类：
    #   ① 同一 target 内同名 → 重复符号（编译必挂）
    #   ② 跨 target 同名但来自不同路径 → 两份副本，内容必须一字不差（防漂移）
    #   ③ project.yml 里的每个 target 都必须被 CI 覆盖（scheme 或体检清单）
    if spec == SPEC:
        with open(spec, encoding='utf-8') as f:
            spec_text = f.read()
        files = {t: expand_sources(e) for t, e in target_source_files(spec_text).items()}
        if files:
            print(f"\ntarget 文件清单（{len(files)} 个 target，"
                  f"{sum(len(v) for v in files.values())} 个 .swift 参与编译）")
            for t in sorted(files):
                print(f"  · {t}: {len(files[t])} 个")

            # ① 同一 target 内同名
            for t, fs in files.items():
                byname = {}
                for f in fs:
                    byname.setdefault(os.path.basename(f), []).append(f)
                for n, ps in sorted(byname.items()):
                    if len(ps) > 1:
                        rel = [p[len(ROOT) + 1:] if p.startswith(ROOT) else p for p in sorted(ps)]
                        print(f"  ❌ {t} 内同名：{n} ← " + " / ".join(rel))
                        problems.append(f"target {t} 里有 {len(ps)} 个同名文件 {n}"
                                        "（同一个 target 编两份 → 重复符号）")

            # ② 跨 target 的两份副本必须一致
            groups = {}
            for t, fs in files.items():
                for f in fs:
                    groups.setdefault(os.path.basename(f), set()).add(f)
            for n, ps in sorted(groups.items()):
                if len(ps) < 2:
                    continue
                blobs = {}
                for p in sorted(ps):
                    with open(p, 'rb') as f:
                        blobs[p] = f.read()
                if len(set(blobs.values())) > 1:
                    rel = [p[len(ROOT) + 1:] if p.startswith(ROOT) else p for p in sorted(ps)]
                    print(f"  ❌ 两份副本已漂移：{n} ← " + " / ".join(rel))
                    problems.append(f"{n} 有两份不同内容的副本（" + " / ".join(rel) +
                                    "）—— 改了一份忘另一份，两个 target 会各跑各的")
                else:
                    rel = [p[len(ROOT) + 1:] if p.startswith(ROOT) else p for p in sorted(ps)]
                    print(f"  ✅ 跨 target 同名副本一致：{n} ← " + " / ".join(rel))

            # ③ 每个 target 都要被 CI 编到
            with open(spec, encoding='utf-8') as f:
                data = yaml.safe_load(f) or {}
            all_targets = set(data.get('targets') or {})
            declared_schemes = set(data.get('schemes') or {})
            used_schemes = set(workflow_schemes(WORKFLOW_DIR))
            if declared_schemes:
                # 只算**被工作流真的用到**的 scheme：spec 里声明了但 CI 从不跑它的，
                # 它的 target 实际上从未被编译过（2026-09-22 删掉单元测试 job 之后，
                # `CarKeeperTests` 正好就是这种情形）。
                # 只算 build action 的 target：test action 里写着谁，不等于谁会真的被编
                covered = (scheme_targets(data, only=used_schemes, phases=('build',))
                           | scheme_targets(data, only=workflow_test_schemes(WORKFLOW_DIR), phases=('test',))
                           | set(workflow_build_targets(WORKFLOW_DIR)))
                mode = (f"只看工作流引用的 scheme：{sorted(used_schemes) or '无'}"
                        f"；跑过 test 的 scheme：{sorted(workflow_test_schemes(WORKFLOW_DIR)) or '无'}")
            else:
                # schemes: 缺席时 XcodeGen 为每个 target 自动生成方案，视为都覆盖
                covered = set(all_targets) | set(workflow_build_targets(WORKFLOW_DIR))
                mode = "spec 没有 schemes: → 每个 target 都有自动方案"
            if all_targets:
                print(f"\ntarget 的 CI 覆盖（{mode}）")
                for t in sorted(all_targets):
                    ok = t in covered
                    if ok:
                        print("  ✅ " + t)
                    elif t in CI_UNCOVERED_TARGETS:
                        print(f"  ⚠️  {t}（已显式豁免）—— {CI_UNCOVERED_TARGETS[t]}")
                    else:
                        print("  ❌ " + t)
                        problems.append(f"target {t} 没有任何 CI 步骤会编译它"
                                        "（scheme 的 build action 里没有它，体检清单里也没有）。"
                                        "若是有意不跑，请写进 paths.py 的 CI_UNCOVERED_TARGETS 并说明理由。")
                for t in sorted(set(CI_UNCOVERED_TARGETS) - all_targets):
                    print(f"  ⚠️  豁免名单里的 {t} 在 spec 里已不存在 —— 这条豁免该删了")

            for t in sorted(covered - all_targets):
                print("  ❌ " + t + "（CI 点名了，但 project.yml 里没有这个 target）")
                problems.append(f"CI 点名编译 {t}，但 project.yml 里没有这个 target（名字写错了？）")

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
