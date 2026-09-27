#!/usr/bin/env python3
"""跨 target 符号可见性检查。

project.yml 里各 target 的源文件是分开的：
  · 测试 target 不能使用 App target 里没有的类型
  · 同一个文件被两个 target 同时编译时，其引用必须两个 target 都能满足
每个 target 只声明了自己那批文件里的类型 —— 这里找出「引用了别处才有的项目内符号」。

⚠️ 2026-09-23：WidgetBundle / WatchApp / WatchKitApp 三个 target 已随小组件体系整体删除
（免费账号拿不到 App Group，那套东西没有一条可用路径）。这里曾列着它们与 Shared/ ——
留着只会让门禁去追一批不存在的目录。
"""
import re
import sys
from scan import (read, target_files, DECL, EXT, TYPE_REF, CALL_REF, MEMBER_REF,
                  FUNC, KEYWORDS, lex, BASELINE)

# target -> project.yml 里的 sources
TARGETS = {
    #  顶层的 `Models` 于 2026-09-26 随 `AppDataModel.swift` 一起删（project.yml 里那条
    #  `- path: Models` 也删了）—— 两边必须同时改，否则这里报「声明的源码路径不存在」。
    "CarKeeper": ["CarKeeper", "Design", "Services"],
    # CarPlay / AppClip / WidgetBundle / WatchApp / WatchKitApp 四个 target 与
    # HealthKit 目录都已删（免费账号无法配置所需能力，或代码早已不存在）——
    # 这里不保留“幽灵 target”，否则门禁会去追一批不存在的目录。
}
EXTS = {"swiftui", "uikit", "foundation", "combine", "widgetkit", "watchkit",
        "activitykit", "mapkit", "corelocation", "healthkit_", "vision", "os"}


def visible(p):
    return not any(part.startswith(".") for part in p.parts)


def build_whitelist():
    sdk = set()
    for p in sorted(BASELINE.rglob("*.swift")):
        t = read(p)
        sdk |= {m.group(2) for m in DECL.finditer(t)}
        _, _, cleaned = lex(t, clean=True)
        sdk |= {m.group(1) for m in TYPE_REF.finditer(cleaned)}
        sdk |= {m.group(1) for m in CALL_REF.finditer(cleaned)}
    sdk -= KEYWORDS
    sdk |= {"Swift", "Any", "AnyObject", "Some", "Never", "Self"}
    return sdk


def names_for(paths):
    """返回 (声明的类型名集合, extension 的目标名集合, 引用的类型名计数, 引用的名字->文件)"""
    declared, extended, refs, where = set(), set(), {}, {}
    for p in paths:
        text = read(p)
        _, _, cleaned = lex(text, clean=True)
        declared |= {m.group(2) for m in DECL.finditer(text) if m.group(2) not in KEYWORDS}
        declared |= set(FUNC.findall(text))
        for m in EXT.finditer(text):
            nm = m.group(1)
            extended.add(nm)
            declared.add(nm.split(".")[0])
        found = set()
        for rx in (TYPE_REF, CALL_REF, MEMBER_REF):
            for m in rx.finditer(cleaned):
                found.add(m.group(1))
        for m in re.finditer(r"(?<=[:(,])\s*([A-Z][A-Za-z0-9_]*)\s*(?=[;,{:])", cleaned):
            found.add(m.group(1))
        for nm in found:
            refs[nm] = refs.get(nm, 0) + 1
            where.setdefault(nm, p.name)
    return declared, extended, refs, where


def main():
    global_declared = set()
    sets = {}
    for tname, roots in TARGETS.items():
        paths = [p for p in target_files(roots) if visible(p)]
        if not paths:
            print(f"!! target {tname} 没有源文件（检查 project.yml 的 sources 是否变了）")
            continue
        sets[tname] = (paths, names_for(paths))
        global_declared |= sets[tname][1][0]

    sdk = build_whitelist()
    print(f"项目内声明的类型/函数共 {len(global_declared)} 个\n")
    for tname, (paths, (declared, extended, refs, where)) in sets.items():
        print(f"===== {tname}  ({len(paths)} 文件) =====")
        bad_ext = sorted(n for n in extended
                         if n.split(".")[0] not in declared and n.split(".")[0] not in sdk
                         and n.split(".")[-1] not in declared)
        missing = sorted(n for n in refs
                         if n in global_declared and n not in declared and n not in sdk)
        if bad_ext:
            print("  ⚠️ extension 了本 target 未声明的类型：")
            for n in bad_ext:
                print(f"      {n}  ({where.get(n, '?')})")
        if missing:
            print("  ⚠️ 引用了本项目其他 target 才有的符号：")
            for n in missing:
                print(f"      {n}  ← {where.get(n, '?')}")
        if not bad_ext and not missing:
            print("  ✅ 自洽")
        print()


main()
