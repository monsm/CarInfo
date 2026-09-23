#!/usr/bin/env python3
"""shadowguard.py — 禁止「嵌套 SDK 同名类型」的遮蔽陷阱。

背景：`extension Kansei { enum Color { … } }` 会在 `struct Kansei` 作用域内遮蔽
`SwiftUI.Color`，裸写 `Color` 就被解析成那个「没有 case 的枚举」，报
cannot be constructed / has no member 'white'（一次真实的构建事故）。

规则：任何**项目类型内部或其 extension 内**声明的类型，若名字与 SDK 类型同名 → 报错。

用法：python3 scan/shadowguard.py [路径...]   # 默认扫全部 target 目录
"""
import re
import sys
from pathlib import Path

from _roots import swift_files

STRICT = "--strict" in sys.argv
ARGV = [a for a in sys.argv[1:] if not a.startswith("--")]

# 源码根目录，逐项必须存在（见 `_roots.py` 的说明）。
TK = ["CarKeeper/CarKeeper", "CarKeeper/Services", "CarKeeper/Models",
      "CarKeeper/Design", "CarKeeper/Tests"]

# 已核实的「现存」SDK / 标准库类型名 —— 嵌套同名 = 真遮蔽（默认即报错）。
# 核实方式：Apple 文档 JSON 端点存在性（例：/documentation/swiftui/link.json 200）。
# 注：Shadow（SwiftUI）与 Mark（Charts）经核实 **不存在**，故不在此列。
SDK_NAMES = {
    # SwiftUI
    "Color", "Font", "Text", "Image", "Label", "Link", "Button", "Toggle", "Slider", "Picker",
    "Spacer", "Divider", "Group", "Section", "Rectangle", "Circle", "Capsule", "Ellipse",
    "Animation", "Shape", "Path", "Angle", "Material", "Gradient", "Environment", "Edge",
    "Alignment", "Axis", "View", "Scene", "App", "Transition", "EdgeInsets", "ImageRenderer",
    "CornerRadius", "ProgressView", "ContentUnavailableView", "Marker", "TabView", "NavigationStack",
    # Foundation / Swift
    "Date", "Data", "URL", "Error", "Result", "IndexSet", "Calendar", "Locale", "Notification",
    "Timer", "Measurement", "Decimal", "Progress",
    # 2026-09 新增：曾真实存在的遮蔽 —— Theme 里嵌套过 `enum Duration`（已随令牌合并删除）
    # 核实：/documentation/swift/duration.json → HTTP 200，struct（iOS 16+）
    "Duration",
    # Charts / MapKit
    "Annotation", "ShadowStyle", "AxisMarks", "RuleMark", "BarMark", "PointMark", "LineMark",
    "AreaMark", "SectorMark",
}

# 未来可能撞名的通用词：仅 `--strict` 时一并报出（当前仓库有 Theme.Radius / WT.Radius 等）。
FUTURE_RISK = {
    "Spacing", "Radius", "Motion", "Haptic", "Shadow", "Mark", "Style", "Size",
    "Content", "Overlay", "Insets", "Trait", "Appearance", "Index",
}

MODIFIERS = r"(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+|final\s+|open\s+)*"
TYPE_DECL = re.compile(rf"^\s*{MODIFIERS}(class|struct|enum|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)")
EXT_DECL = re.compile(rf"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)*extension\s+([A-Za-z_][A-Za-z0-9_.]*)")


def strip_literals(text):
    s = re.sub(r'"""[\s\S]*?"""', '""', text)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    s = re.sub(r"//[^\n]*", "", s)
    s = re.sub(r"/\*[\s\S]*?\*/", "", s)
    return s


def scan_file(f):
    out = []
    lines = strip_literals(Path(f).read_text(encoding="utf-8")).split("\n")
    depth = 0
    stack = []  # [(名字, 其 body 的起始 brace 深度)]
    for i, l in enumerate(lines):
        while stack and depth < stack[-1][1]:
            stack.pop()
        m = TYPE_DECL.match(l)
        e = None if m else EXT_DECL.match(l)
        if m or e:
            name = m.group(2) if m else e.group(1).split(".")[-1]
            if stack and name in (SDK_NAMES | FUTURE_RISK):
                out.append((f, i + 1, stack[-1][0], name))
            stack.append((name, depth + 1 if "{" in l else depth))
        depth += l.count("{") - l.count("}")
    return out


if ARGV:
    files = []
    for a in ARGV:
        p = Path(a)
        files += [str(p)] if p.is_file() else sorted(str(x) for x in p.rglob("*.swift"))
else:
    files = swift_files(TK)

hits = [h for f in files for h in scan_file(f)]
real = [h for h in hits if h[3] in SDK_NAMES]
future = [h for h in hits if h[3] in FUTURE_RISK and h[3] not in SDK_NAMES]

print(f"扫描 {len(files)} 个 Swift 文件")
if future:
    print(f"ℹ️ 通用词形状（非现存 SDK 名，仅提示）：{len(future)} 处")
    for f, ln, enc, name in future[:20]:
        print(f"   - {f}:{ln}  『{enc}』内声明 `{name}`")
if not real:
    print("✅ 无『嵌套现存 SDK 同名类型』（遮蔽陷阱已消除）")
else:
    print(f"❌ {len(real)} 处真遮蔽风险：")
    for f, ln, enc, name in real[:40]:
        print(f"   {f}:{ln}  『{enc}』内声明了 SDK 同名类型 `{name}`")
if real or (STRICT and future):
    sys.exit(1)
