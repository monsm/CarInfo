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
  • 一个文件里的**顶层类型声明**（列 0 的 struct/class/enum/actor）如果在
    **其它任何文件**里一次都没被提到，就算孤儿。
  • 跳过入口类文件：含 `@main` / `PreviewProvider` / `#Preview` /
    `AppIntent` / `AppShortcutsProvider`（系统按注册发现，代码里不需要引用）/
    `UIApplicationDelegate` 的文件。
  • 白名单在下面，每条必须写清理由 —— 白名单是给「确实不需要外部引用」用的，
    不是给「暂时懒得接」用的。

退出码：0 = 无孤儿；1 = 有孤儿（或扫描失败）。
"""

import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 报告范围：编进 App 主 target 的源码目录
SCOPE_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Models",
    "CarKeeper/Design",
    "CarKeeper/Shared",
    "CarKeeper/HealthKit",
]

# 入口 / 系统发现类的标记：这些文件不需要被别的文件提到
ENTRY_MARKERS = [
    "@main",
    "PreviewProvider",
    "#Preview",
    "AppIntent",
    "AppShortcutsProvider",
    "UIApplicationDelegate",
    "UIWindowSceneDelegate",
]

# 白名单：{ 相对路径: 理由 }
# 规则：只有「确实不该被代码引用」才允许进白名单。
WHITELIST = {
    "CarKeeper/CarKeeper/Features/SiriShortcuts.swift":
        "AppIntent 由系统按定义发现（Siri/快捷指令），代码里不需要引用 —— 见该文件头部说明",
    "CarKeeper/CarKeeper/Design/DSGlass.swift":
        "玻璃的词汇表。它对外只有四个 `View` 扩展方法（`dsGlass` / `dsGlassCapsule` / "
        "`dsGlassRounded` / `dsGlassLayer`），跨文件用的是那几个方法 —— 而文件里的"
        "类型只剩 `DSGlassVariant` 一个，它只作为 `dsGlass(…variant:)` 的**参数类型**"
        "出现，调用点写的是 `.overMedia`（隐式成员表达式），判据看不见那个类型名。"
        "代价说明白：以后这个文件里真冒出没人用的类型，这里也不会报 —— 接受它，"
        "因为该文件只该放材质词汇（现在 150 行），且它的头注就是规则本身",
}

TOP_TYPE_RE = re.compile(
    r"^(?:public |internal |private |final |open |@\w+\s+)*(struct|class|enum|actor)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)


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

    # 引用计数要跨**所有** Swift 文件（含扩展 target 与测试）：
    # 只被 Widget 引用的类型不是孤儿。
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
        # 只当真名前 5 个字符以上（单字母/缩写容易和其它东西撞名）
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
