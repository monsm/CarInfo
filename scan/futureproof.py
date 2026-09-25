#!/usr/bin/env python3
"""futureproof.py — 未来系统版本（iOS 27/28…）前瞻性审计。

最低部署目标 = iOS 26 时，26 以上的版本是自动支持的；唯一会让 App 在**未来版本**
上出问题的写法是：对「来自系统框架的弹性枚举」做穷举 switch 却不写
`default` / `@unknown default`。这时代码只对当前 SDK 的已知 case 穷举，
将来系统新增一个 case 会走到编译器插入的陷阱（运行时崩溃），
而且 SDK 版本升级前只会给一条 warning：
  "switch covers known cases, but 'X' may have additional unknown values"

本脚本把所有「没有 default 的 switch」列出来，并标出疑似落在 SDK 枚举上的那些。
"""
import re
import sys
from pathlib import Path

from _roots import swift_files

# 源码根目录。这里的每一项都必须真实存在 —— 由 `_roots.swift_files` 硬性保证：
# 原来这张表里还列着 `Shared` / `Widgets` / `WatchApp` / `HealthKit`，那四个目录
# 都已随扩展与死代码删除，而 `rglob` 对不存在的目录只是返回空 ——
# 于是「检查范围变小」表现得和「0 个问题」一模一样。
TK = ["CarKeeper/CarKeeper", "CarKeeper/Services", "CarKeeper/Models",
      "CarKeeper/Design", "CarKeeper/Tests"]

# 项目自己声明的类型名（从 Kansei/DS 等令牌与常见模型里来），用于区分「自有枚举」
PROJECT_ENUM_HINT = re.compile(
    r"\b(TimeOfDay|NightModeMode|TripCostType|DynamicType|BatteryModel|VehicleSummary|AppTab|Tab|Phase|Mode|Kind|State|Status|Role|Variant|Type|Level|Category|Style|Scope|Period|Source|StyleType)\b"
)
# 主题词表：**只收系统专属的名字**，不收 `status` / `phase` / `configuration` 这类
# 普通名词。
#
# 为什么（2026-09-25）：那三个词在这个仓库里遍地都是 —— 模型上叫 `status` 的属性、
# 我们自己枚举的 `phase`。判据一旦按它们命中，`switch phone.status`
#（`PhoneLocation.Status`，我们自己的枚举）就会被要求补 `@unknown default`，
# 而对自己的枚举补它是**反的**：那会把「以后新增一档时编译器提醒你改这里」
# 一起关掉 —— 正是这个门禁想保住的东西。
#
# 剩下这些名字（`scenePhase` / `dynamicTypeSize` / `authorizationStatus`…）都是
# 系统专有词，不可能与项目里的东西撞名。
#
# 代价写在明处：如果将来真的对一个**成员名叫 `status` 的系统枚举**穷举
#（例如某个框架的 `foo.status`），这条判据看不出来 —— 方向是「宁可漏，不可噪」，
# 与 `expand.py` / `initguard.py` 那几条的取向一致。
SDK_SUBJECT_HINT = re.compile(
    r"\b(colorScheme|dynamicTypeSize|userInterfaceStyle|horizontalSizeClass|verticalSizeClass|scenePhase|"
    r"authorizationStatus|locationAuthorization|interfaceOrientation|mapType|"
    r"layoutDirection|legibilityWeight|accessibilityContrast|displayScale|"
    r"privacySensitive|sizeCategory|traitCollection|UIScene|UIUserInterface|MKUserTrackingMode|"
    r"ImageOrientation|Writer|ContentMode)\b"
)


def strip_literals(text):
    s = re.sub(r'"""[\s\S]*?"""', '""', text)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    s = re.sub(r"//[^\n]*", "", s)
    s = re.sub(r"/\*[\s\S]*?\*/", "", s)
    return s


# 项目自己**声明**的类型名。用途：把「我们的枚举」从「SDK 的弹性枚举」里分出来。
#
# 为什么需要：判据说到底是在问「这个 switch 是不是穷举了一个系统框架的枚举」——
# 而上一版的依据只有**主题词的拼写**（`SDK_SUBJECT_HINT` 里那个 `status`）：
# 于是 `switch PhoneLocation.shared.status`（我们自己的 `enum Status`）被当成
# SDK 枚举，要求补 `@unknown default`。而对自己的枚举补它是**反的** ——
# 那会把「新增一档时编译器提醒你改这里」一起关掉（正是这个门禁想保住的东西）。
# 2026-09-25 新增那一枚手机位置钮时撞上的就是这个假阳性。
DECLARED_TYPE_RE = re.compile(r"\b(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z][A-Za-z0-9_]*)")
PROJECT_TYPES = set()
for f in swift_files(TK):
    PROJECT_TYPES |= {m.group(1) for m in DECLARED_TYPE_RE.finditer(Path(f).read_text(encoding="utf-8"))}


def looks_like_sdk_enum(subject):
    # 主题词命中 **且** 主语里没有项目自己的类型名 —— 两个条件都要。
    # 于是 `scenePhase` / `dynamicTypeSize` 这些还是报（它们的主语就是一个属性名），
    # 而 `PhoneLocation.shared.status` 不报。
    if SDK_SUBJECT_HINT.search(subject) is None:
        return False
    return not any(re.search(r"\b" + re.escape(t) + r"\b", subject) for t in PROJECT_TYPES)


files = swift_files(TK)
no_default = []
for f in files:
    src = strip_literals(Path(f).read_text(encoding="utf-8"))
    lines = src.split("\n")
    for i, l in enumerate(lines):
        m = re.match(r"^(\s*)switch\s+(.+?)\s*\{\s*$", l)
        if not m:
            continue
        indent, subject = m.group(1), m.group(2)
        # 花括号配对取 switch 块
        depth, j, body = 0, i, []
        while j < len(lines):
            depth += lines[j].count("{") - lines[j].count("}")
            body.append(lines[j])
            if depth <= 0 and j > i:
                break
            j += 1
        blob = "\n".join(body)
        if "default:" in blob or "@unknown default" in blob:
            continue
        no_default.append((f, i + 1, subject, looks_like_sdk_enum(subject)))

print(f"扫描 {len(files)} 个 Swift 文件")
print(f"没有 default / @unknown default 的 switch：{len(no_default)} 处")
sdk = [x for x in no_default if x[3]]
for f, ln, subj, _ in no_default:
    tag = "⚠️ 疑似 SDK 枚举" if (f, ln, subj, True) in sdk else "  （自有枚举/字符串，无风险）"
    print(f"   {tag}  {f}:{ln}   switch {subj[:60]}")
if sdk:
    print("\n❌ 存在落在 SDK 枚举上的穷举 switch —— 未来系统新增 case 会运行时崩溃：")
    for f, ln, subj, _ in sdk:
        print(f"   {f}:{ln}  switch {subj}")
    sys.exit(1)
print("\n✅ 无『SDK 枚举穷举 switch 缺 default』（未来版本不会因新增枚举值崩溃）")
