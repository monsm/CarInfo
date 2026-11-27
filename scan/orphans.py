#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
孤儿页面检查器 —— 「写了，但没有任何地方能到达」

为什么需要它（真实事故）：
  全局搜索页 `Features/GlobalSearchHUD.swift`（159 行）**零外部引用** ——
  全 App 没有任何地方 present 它。它先被当成「零版面页面」重排过一遍（白做），
  直到手工审计才发现它根本打不开。
  同类的还有 `Services/BillingAndCalendar.swift`（442 行）与
  `Services/FamilyAndKeySharing.swift`（308 行）：里面每个类型都没有任何外部引用。

  既有的检查器都不管这件事：`unreachable.py` 查的是「return 之后的死语句」，
  `scan.py` 查的是「用了但没声明的名字」—— 而**声明了但没人用的名字**，
  在 Swift 里既不报错也不警告。

判据（刻意收窄，避免假阳性）：
  • 只看 `CarKeeper/CarKeeper/**`、`CarKeeper/{Services,Models,Design,Shared,HealthKit}/**`
    —— 这些是编进 App 主 target 的源码；扩展 target（Widgets / WatchApp）
    与测试不在报告范围（但它们的引用**算数**）。

  判据 ②（2026-09-25 补）：**系统类型扩展里没人读的成员**。
  起因是判据 ① 的盲区：它只认顶层类型，于是
  `private extension Double { func clamped(to:) }` 这类声明与漏洞整个看不见 ——
  那个 `clamped` 的唯一使用点删掉后，声明还在，31 条门禁一条都没说话。
  补上后当场报到两个真的：`URLSession.dataTaskRetryable`（+ `RetryConfig`，
  第二套重试实现，真正在用的是 `Retrier.global`）与 `UIColor.dsDynamic`
  （第二套动态色，真正在用的是 `TokensPalette.nativeDynamic` —— 它原名
  `ArtTheme.nativeDynamic`，2026-09-25 随艺术主题删除搬进 `Tokens.swift`）。
  探针：注入 `extension Double { func probeDeadMember() }` → 当场报出；
  还原后文件哈希与注入前一致、转绿。收窄三条写在判据 ② 的注释里。

  • 一个文件里的**顶层类型声明**（列 0 的 struct/class/enum/actor）如果在
    **其它任何文件**里一次都没被提到，就算孤儿。
  • 跳过入口类文件：含 `@main` / `PreviewProvider` / `#Preview` /
    `AppIntent` / `AppShortcutsProvider`（系统按注册发现，代码里不需要引用）/
    `UIApplicationDelegate` 的文件。
  • 白名单在下面，每条必须写清理由 —— 白名单是给「确实不需要外部引用」用的，
    不是给「暂时懒得接」用的。

  判据 ③（2026-09-27 补）：**顶层 View 从来没有被构造过**。
  起因是判据 ① 是**按文件**判的：它把文件里的顶层类型名当成一张名单，名单里只要有
  **一个**名字在别处出现过，整个文件就算「有人引用」。于是同一份文件里只要有一样东西
  是活的，零读者的类型就全搭它的便车：`Theme.swift` 里的月报
  （`MonthlyReportSection` / `MonthlyReportCard`：行驶统计 + 驾驶评分 + 生成 HTML 再分享，
  约 170 行）零入口、零读者，34 条门禁一条都没说话 —— 它被发现，靠的是一次性脚本。
  探针：临时文件 `_GateProbe.swift` 里注入一个没有构造点的 `: View` → 当场报出；
  删掉临时文件、改成没有构造点那一侧 → 转绿。
  判据与三条收窄写在下面对应的那一节。

退出码：0 = 无孤儿；1 = 有孤儿（或扫描失败）。
"""

import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCOPE_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Design",
    "CarKeeper/Shared",
    "CarKeeper/HealthKit",
]

ENTRY_MARKERS = [
    "@main",
    "PreviewProvider",
    "#Preview",
    "AppIntent",
    "AppShortcutsProvider",
    "UIApplicationDelegate",
    "UIWindowSceneDelegate",
]

WHITELIST = {
    "CarKeeper/CarKeeper/Features/SiriShortcuts.swift":
        "AppIntent 由系统按定义发现（Siri/快捷指令），代码里不需要引用 —— 见该文件头部说明",
}

TOP_TYPE_RE = re.compile(
    r"^(?:public |internal |private |final |open |@\w+\s+)*(struct|class|enum|actor)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)

EXT_MIN_NAME = 6

EXT_WHITELIST: dict[str, str] = {}

TYPE_DECL_RE = re.compile(
    r"^(?:public |internal |private |fileprivate |final |open |@\w+\s+)*"
    r"(?:struct|class|enum|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)
EXT_BLOCK_RE = re.compile(
    r"^(?:public |internal |private |fileprivate )?extension\s+([A-Za-z_][A-Za-z0-9_.]*)",
    re.M,
)
EXT_MEMBER_RE = re.compile(
    r"^[ \t]+(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public |internal |private |fileprivate |static |final |mutating )*"
    r"(?:func|var|let)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)


def extension_member_orphans(texts):
    """返回 [(键, 成员名, 类型名, 文件)]：系统类型扩展里没有人读的成员。"""
    readable = {q: t for q, t in texts.items() if "DerivedData" not in q}
    project_types = set()
    for text in readable.values():
        project_types |= {m.group(1) for m in TYPE_DECL_RE.finditer(text)}

    hits = []
    for path, text in readable.items():
        for m in EXT_BLOCK_RE.finditer(text):
            raw = m.group(1)
            typ = raw.split(".")[-1]
            if typ in project_types:
                continue
            brace = text.find("{", m.end())
            if brace < 0:
                continue
            depth, i = 1, brace + 1
            while i < len(text) and depth:
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                i += 1
            body = text[brace + 1:i]
            for member in EXT_MEMBER_RE.finditer(body):
                name = member.group(1)
                if len(name) < EXT_MIN_NAME:
                    continue
                key = f"{path}:{typ}.{name}"
                if key in EXT_WHITELIST:
                    continue
                word = r"\b" + re.escape(name) + r"\b"
                decl = r"\b(?:func|var|let)\s+" + re.escape(name) + r"\b"
                uses = sum(len(re.findall(word, t)) for t in readable.values())
                decls = sum(len(re.findall(decl, t)) for t in readable.values())
                if uses - decls <= 0:
                    hits.append((key, name, typ, path))
    return hits


VIEW_MIN_NAME = 6
VIEW_DECL_RE = re.compile(
    r"^(?:public |internal |private |fileprivate |final |open )*struct\s+([A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\s*<[^>\n]*>)?\s*:[^\n{]*\bView\b",
    re.M,
)
VIEW_WHITELIST: dict[str, str] = {}


def view_orphans(texts, in_scope):
    """返回 [(文件, 类型名)]：声明了 `: View` 却全仓没被构造过的顶层结构体。"""
    readable = {q: t for q, t in texts.items() if "DerivedData" not in q}
    hits = []
    for path in in_scope:
        text = readable.get(path)
        if text is None:
            continue
        if any(marker in text for marker in ENTRY_MARKERS):
            continue
        for m in VIEW_DECL_RE.finditer(text):
            name = m.group(1)
            if len(name) < VIEW_MIN_NAME or name.endswith("_Previews"):
                continue
            key = f"{path}:{name}"
            if key in VIEW_WHITELIST:
                continue
            pat = re.compile(
                r"\b" + re.escape(name) + r"\s*[\(<]"
                r"|<\s*" + re.escape(name) + r"\s*(?:,|>)"
                r"|\b" + re.escape(name) + r"\.self\b"
            )
            if not any(pat.search(t) for t in readable.values()):
                hits.append((path, name))
    return hits


def all_swift_files(root):
    out = []
    for dirpath, _, filenames in os.walk(os.path.join(PROJECT_ROOT, root)):
        for f in filenames:
            if f.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(dirpath, f), PROJECT_ROOT).replace(os.sep, "/"))
    return out


def main():
    in_scope = []
    for d in SCOPE_DIRS:
        if os.path.isdir(os.path.join(PROJECT_ROOT, d)):
            in_scope += all_swift_files(d)
    in_scope = sorted(set(in_scope))

    everything = sorted(set(all_swift_files("CarKeeper")))
    texts = {}
    for p in everything:
        try:
            with open(os.path.join(PROJECT_ROOT, p), encoding="utf-8", errors="ignore") as fh:
                texts[p] = fh.read()
        except OSError as exc:
            print(f"❌ 读不了 {p}: {exc}")
            return 1

    if not in_scope:
        print("❌ 扫描范围为空 —— 路径写错了？")
        return 1

    orphans = []
    checked = 0
    for p in in_scope:
        text = texts.get(p)
        if text is None:
            continue
        if any(marker in text for marker in ENTRY_MARKERS):
            continue
        names = {m.group(2) for m in TOP_TYPE_RE.finditer(text)}
        names = {n for n in names if len(n) >= 6}
        if not names:
            continue
        checked += 1
        hit = False
        for name in names:
            pattern = re.compile(r"\b" + re.escape(name) + r"\b")
            for q, other in texts.items():
                if q == p:
                    continue
                if pattern.search(other):
                    hit = True
                    break
            if hit:
                break
        if not hit:
            orphans.append((p, sorted(names)))

    print(f"扫描 {len(in_scope)} 个 App 源码文件（跨 {len(everything)} 个文件统计引用）")
    print(f"其中 {checked} 个文件含可检类型；白名单 {len(WHITELIST)} 条")

    hard = [(p, n) for p, n in orphans if p not in WHITELIST]
    if hard:
        print("\n❌ 孤儿页面/类型（没有任何文件引用它，也打不开）：")
        for p, names in hard:
            print(f"   {p}")
            print(f"      顶层类型: {', '.join(names)}")
        print("\n   两种修法（都要选一种，不能留着）：")
        print("     ① 接上入口 —— 让用户真的能到达它；")
        print("     ② 删掉 —— 写了却到不了的功能，等于没写，但会一直占着维护成本。")
        print("   如果它确实不需要被代码引用（系统按注册发现等），写进 WHITELIST 并说明理由。")
        return 1

    print("\n✅ 无『孤儿页面』（每个写了页面的文件都有地方能到达它）")

    ext_hits = extension_member_orphans(texts)
    hard_ext = [h for h in ext_hits if h[0] not in EXT_WHITELIST]
    if hard_ext:
        print("\n❌ 系统类型扩展里没人读的成员（声明在、没有读者）：")
        for key, name, typ, path in hard_ext:
            print(f"   {path} → extension {typ} → {name}")
        print("\n   两种修法（都要选一种，不能留着）：")
        print("     ① 接上读者 —— 它本来就该被某处调用；")
        print("     ② 删掉 —— 留着它的代价是下一个人以为「它可以被调用」。")
        print("   确实不需要被代码引用的，写进 EXT_WHITELIST 并说明理由。")
        return 1
    print(f"\n✅ 系统类型扩展里的成员都有读者（例外表 {len(EXT_WHITELIST)} 条）")

    view_hits = view_orphans(texts, in_scope)
    hard_view = [h for h in view_hits if f"{h[0]}:{h[1]}" not in VIEW_WHITELIST]
    if hard_view:
        print("\n❌ 写了却没有人构造的 View（声明在、全仓没有一处 `TypeName(`）：")
        for path, name in hard_view:
            print(f"   {path} → {name}")
        print("\n   两种修法（都要选一种，不能留着）：")
        print("     ① 接上入口 —— 让某处真的把它建起来；")
        print("     ② 删掉 —— 一个从来不出现的界面，等于没有，但它一直占着维护成本")
        print("        （2026-09-27 的月报就是这样被找出来的）。")
        print("   确实不需要被构造的，写进 VIEW_WHITELIST 并说明理由。")
        return 1
    print(f"\n✅ 每个 `: View` 的顶层结构体都有人构造（例外表 {len(VIEW_WHITELIST)} 条）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
