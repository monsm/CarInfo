#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lintcfg.py —— `.swiftlint.yml` 的排除清单必须与真实文件树、与它自己的阈值一致。

为什么需要它（这一条的两半都真的错着，而且错了不知道多久）：

  ① **基准目录错了一层。** `excluded` 里的路径是这样写的：

         - CarKeeper/CarKeeper/Design/DS.swift

     而配置文件住在 `CarKeeper/.swiftlint.yml`。SwiftLint 官方文档写明：

         included / excluded entries from each config are resolved relative to that
         config file's directory.
         —— https://realm.github.io/SwiftLint/ （Configuration / path merging）

     也就是说基准是 `CarKeeper/`，那条路径实际指向
     `CarKeeper/CarKeeper/CarKeeper/Design/DS.swift` —— 不存在。
     **排除清单整份是空转的**：swiftlint 照旧把 DS.swift（1077 行）报成超长。
     （`project.yml` 里同样是 `- path: Design` / `- path: CarKeeper/` 这种以
      `CarKeeper/` 为基准的写法 —— 两种配置文件住在同一个目录，基准是同一个。）

  ② **清单只减不增。** 删掉 App Clip / CarPlay / 小组件时留下了指向已删目录的条目
     （`CarKeeper/WatchApp`、`CarKeeper/Widgets`），而代码继续长大
     （`MapSpineView.swift` 1125 行、`ControlView.swift` 1103 行）却没有跟着进清单。
     两个方向都会让这份清单失去意义。

  这个检查器在 Linux 上跑，不需要 swiftlint、不需要 macOS：
    · 清单里的每一项都必须存在（按**配置文件所在目录**解析）        → 错了就失败
    · 超过 `file_length` 阈值（warning 与 error 都算）的 .swift 文件必须被排除
      —— 因为 build.sh 用的是 `swiftlint lint --strict`，warning 会被升级，
      所以「只排 error 以上的」是不够的                              → 漏了就失败
    · 超 `type_body_length` / `function_body_length` 的块，按 ⚠️ 提示（不判失败：
      按花括号粗量，量法本身有误差，不能拿它拦 CI）
"""

import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("需要 PyYAML：pip install pyyaml")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "CarKeeper", ".swiftlint.yml")
# SwiftLint 解析 included/excluded 的基准 = 配置文件所在目录
CONFIG_DIR = os.path.dirname(CONFIG)
SWIFT_ROOT = os.path.join("CarKeeper", "CarKeeper")
# 顶层还有一棵 CarKeeper/Design · Services（见 project.yml 的 sources）。
# （顶层的 `Models` 项在 2026-09-26 去掉了：`AppDataModel.swift` 整份删除之后那个
#  目录不存在，而这份清单是给 glob 用的 —— 不存在的目录只会静默返回空。）
SWIFT_EXTRA_ROOTS = ["Design", "Services", "Tests"]


def swift_files():
    """全部会被编译的 .swift（相对 ROOT）。"""
    out = []
    roots = [SWIFT_ROOT] + [os.path.join("CarKeeper", r) for r in SWIFT_EXTRA_ROOTS]
    for r in roots:
        base = os.path.join(ROOT, r)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != "DerivedData"]
            for fn in filenames:
                if fn.endswith(".swift"):
                    out.append(os.path.relpath(os.path.join(dirpath, fn), ROOT))
    return sorted(set(out))


def load_config():
    with open(CONFIG, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def file_length_lines(cfg):
    fl = cfg.get("file_length", {}) or {}
    return int(fl.get("warning", 400)), int(fl.get("error", 1000))


# ---- 花括号粗量：type_body_length / function_body_length 只做提示 ------------

TYPE_KW = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*"
                     r"(?:class|struct|enum|extension|protocol|actor)\s+(\w+)")
FUNC_KW = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|static\s+|"
                     r"class\s+|override\s+|mutating\s+|nonisolated\s+)*func\s+(\w+)")


def strip_code(src):
    """把字符串/注释挖空（保留换行），免得里面的括号干扰计数。"""
    out = []
    i, n = 0, len(src)
    in_line = False
    in_block = False
    quote = None
    while i < n:
        c = src[i]
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            else:
                out.append(" ")
            i += 1
            continue
        if in_block:
            if src.startswith("*/", i):
                in_block = False
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        if quote:
            if c == "\\":
                out.append("  ")
                i += 2
                continue
            if c == quote:
                quote = None
            out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        if src.startswith("//", i):
            in_line = True
            out.append("  ")
            i += 2
            continue
        if src.startswith("/*", i):
            in_block = True
            out.append("  ")
            i += 2
            continue
        if c in "\"'":
            quote = c
            out.append(" ")
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def oversized_bodies(path, type_warn, func_warn):
    """返回 [(kind, name, lines, threshold)]，按花括号跨度粗量。"""
    src = strip_code(open(path, encoding="utf-8").read())
    lines = src.split("\n")
    open_lines = []      # (decl_line_index, kind, name)
    hits = []
    pending = None       # 本行/上一行刚看到的声明
    for li, line in enumerate(lines):
        m = TYPE_KW.match(line)
        if m:
            pending = ("type", m.group(1))
        else:
            m = FUNC_KW.match(line)
            if m:
                pending = ("func", m.group(1))
        for ch in line:
            if ch == "{":
                if pending:
                    open_lines.append((li, pending[0], pending[1]))
                    pending = None
                else:
                    open_lines.append((li, None, None))
            elif ch == "}":
                if open_lines:
                    start, kind, name = open_lines.pop()
                    if kind == "type":
                        hits.append(("type_body_length", name, li - start, type_warn))
                    elif kind == "func":
                        hits.append(("function_body_length", name, li - start, func_warn))
    return [
        (k, n, got, thr)
        for (k, n, got, thr) in hits
        if thr is not None and got > thr
    ]


def main():
    problems = 0
    cfg = load_config()
    warn_thr, err_thr = file_length_lines(cfg)

    raw_excluded = cfg.get("excluded") or []
    excluded = [str(x).strip() for x in raw_excluded]

    print(f"配置: {os.path.relpath(CONFIG, ROOT)}")
    print(f"解析基准（SwiftLint 文档：相对配置文件所在目录）: "
          f"{os.path.relpath(CONFIG_DIR, ROOT)}/")
    print(f"file_length 阈值: warning {warn_thr} / error {err_thr}")
    print(f"排除清单 {len(excluded)} 条")
    print()

    # ---- ① 每一项都必须存在 ------------------------------------------------
    missing = []
    for entry in excluded:
        resolved = os.path.normpath(os.path.join(CONFIG_DIR, entry))
        if not os.path.exists(resolved):
            missing.append((entry, os.path.relpath(resolved, ROOT)))
    if missing:
        problems += len(missing)
        print(f"❌ 排除清单里有 {len(missing)} 条指向不存在的路径"
              f"（按配置文件所在目录解析）:")
        for entry, resolved in missing:
            print(f"   {entry}")
            print(f"     → 实际算出来是 {resolved}（不存在）")
        print("   指向不存在的东西，swiftlint 不会报，而后来的人会以为那里还有代码。")
        print()
    else:
        print("✅ 排除清单里的每一项都存在")

    # ---- ② 超过 file_length 阈值的文件必须被排除 ---------------------------
    def is_excluded(rel_path):
        abs_file = os.path.join(ROOT, rel_path)
        for entry in excluded:
            resolved = os.path.normpath(os.path.join(CONFIG_DIR, entry))
            if abs_file == resolved or abs_file.startswith(resolved + os.sep):
                return True
        return False

    over = []
    for rel in swift_files():
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            count = len(fh.read().split("\n"))
        if count > warn_thr and not is_excluded(rel):
            over.append((count, rel))
    over.sort(reverse=True)

    if over:
        problems += len(over)
        print()
        print(f"❌ 有 {len(over)} 个文件超过 file_length 阈值却没进排除清单"
              f"（build.sh 用 `--strict`，warning 会升级，所以两种阈值都算）:")
        for count, rel in over:
            print(f"   {count:5d} 行  {rel}")
        print("   清单只减不增，代码继续长大时它就悄悄失真了。")
        print()
        print("   两条路，选一条并写出理由（默认不建议排除，见 .swiftlint.yml 里的说明）：")
        print("     · 把文件改回到阈值以内；或")
        print("     · 调高 `.swiftlint.yml` 里对应的阈值（要能说出为什么这个尺寸是合理的）")
        print()
        print("   若确实要排除，写法是（基准 = 配置文件所在目录 CarKeeper/，用正斜杠）：")
        for count, rel in over:
            print(f"     - {os.path.relpath(rel, 'CarKeeper').replace(os.sep, '/')}   # {count} 行")
        print()
    else:
        print("✅ 超过 file_length 阈值的文件都已在排除清单里")

    # ---- ③ type / function body（粗量，只提示） ----------------------------
    tcfg = cfg.get("type_body_length", {}) or {}
    fcfg = cfg.get("function_body_length", {}) or {}
    tw = int(tcfg.get("warning", 300))
    fw = int(fcfg.get("warning", 100))
    notes = []
    for rel in swift_files():
        if is_excluded(rel):
            continue
        for kind, name, got, thr in oversized_bodies(os.path.join(ROOT, rel), tw, fw):
            notes.append((got, thr, kind, name, rel))
    if notes:
        notes.sort(reverse=True)
        print()
        print(f"⚠️ {len(notes)} 处块体超阈值（按花括号粗量，仅供参考，不判失败）:")
        for got, thr, kind, name, rel in notes[:15]:
            print(f"   {got:4d} > {thr:4d}  {kind}  {name}  ({rel})")
        if len(notes) > 15:
            print(f"   …另有 {len(notes) - 15} 处")
    else:
        print("✅ 没有粗量超阈值的块体")

    print()
    if problems:
        print(f"❌ 排除清单与实际不符 {problems} 处")
        print("   这不是洁癖：清单失真 = 该被排除的没排除（build.sh 会红），")
        print("   以及不该被排除的排除了（那片代码从此没人检查）。")
        return 1
    print("✅ 排除清单与文件树、与阈值三方一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
