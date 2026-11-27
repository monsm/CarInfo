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

TK = ["CarKeeper/CarKeeper", "CarKeeper/Services",
      "CarKeeper/Design", "CarKeeper/Tests"]

PROJECT_ENUM_HINT = re.compile(
    r"\b(TimeOfDay|NightModeMode|TripCostType|DynamicType|BatteryModel|VehicleSummary|AppTab|Tab|Phase|Mode|Kind|State|Status|Role|Variant|Type|Level|Category|Style|Scope|Period|Source|StyleType)\b"
)
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


DECLARED_TYPE_RE = re.compile(r"\b(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z][A-Za-z0-9_]*)")
PROJECT_TYPES = set()
for f in swift_files(TK):
    PROJECT_TYPES |= {m.group(1) for m in DECLARED_TYPE_RE.finditer(Path(f).read_text(encoding="utf-8"))}


def looks_like_sdk_enum(subject):
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
