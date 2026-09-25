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
    "CarKeeper/CarKeeper/Design/InkGlow.swift":
        "玻璃上文字的外壳（`dsInkGlow` / `dsTextGlow`）。它对外只有两个 `View` 扩展方法，"
        "跨文件用的是那两个方法 —— 而文件里唯一的类型 `DSTextGlow` 是 `TextRenderer`，"
        "它只作为 `.textRenderer(_:)` 的参数在**本文件内**被构造（系统只给这一种接法，"
        "没有「在别处引用它」这回事），所以判据看不见那个类型名。"
        "代价说明白：以后这个文件里真冒出没人用的类型，这里也不会报 —— 接受它，"
        "因为该文件只该放「玻璃上的字怎么画」（现在 180 行），且它的头注就是规则本身",
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

# =============================================================================
#  判据 ②：**扩展在系统类型上的成员，有没有读者**
# =============================================================================
#
#  为什么需要它：判据 ① 只认**顶层类型**（`TOP_TYPE_RE`），于是
#  `private extension Double { func clamped(to:) }` 这一类完全在盲区里 ——
#  2026-09-25 那个 `clamped` 就是这样活下来的：它唯一的使用点（宿主自己算档位
#  的那一段，见 `DSSwipeStrip.RowDrag`）删掉之后，声明还在，31 条门禁一条都没说话，
#  是人工过 diff 时看到的。而「声明在、没有读者」正是这个仓库反复吃亏的那一类。
#
#  判据：`extension X` 里 `X` **不是**项目自己声明的类型（= 系统 / 外部类型），
#  而它某个成员的名字在**全仓**除了声明以外一次都没出现过 —— 那就是没有读者。
#
#  收窄（宁愿漏，不可噪）：
#    · 名字短于 6 个字符不看（`==`、`id` 这类撞名太多，数读者会数出假阳性）；
#    · 只数「名字出现过」，不看它用在哪儿 —— 这是**保守**方向：
#      名字在注释里出现一次也算有人读，于是宁可漏报；
#    · `DerivedData/` 里的生成文件不参与统计（它们不是读者）。
#
#  为什么长在 orphans 里：它就是这个文件的题目 —— 「写了却没人用」。
EXT_MIN_NAME = 6

# 例外：{ "文件:类型.成员": 理由 }。只有「确实不需要被代码引用」才允许进来。
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
            # 项目自己的类型（含嵌套写法）不看：它们由判据 ① 与编译器管。
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

    # ---- 判据 ②：系统类型扩展里没有读者的成员 ----------------------------
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
