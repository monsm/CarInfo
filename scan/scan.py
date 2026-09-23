#!/usr/bin/env python3
"""
地毯式静态扫描：本地没有 Xcode，用这个脚本尽量提前找出会让 swiftc 报错的代码。

SDK 白名单不是手写的，而是从「最后一次能编译的提交」(fbd26fc) 反推：
在那个状态下，凡是「项目没声明、代码里却在用」的名字 = SDK 提供的。
于是本次扫描中「未声明 + 不在白名单」的名字就是高嫌疑对象。
"""
import pathlib
import re
import subprocess

REPO = pathlib.Path(".")
CK = REPO / "CarKeeper"
BASELINE = REPO / "scan" / "baseline"
# 基线的**紧凑缓存**。基线本身是 82 个 .swift 快照，不进仓库 —— 否则全仓搜索
# 会多出一份旧代码的副本，人和工具都会被误导。所以把它**分析结果**物化成一个
# 小 JSON 一起提交：干净机器（CI）上符号检查依然能跑满，而不是打印一行提示
# 后静默 exit 0（「没检查」长得和「没问题」一模一样，是最危险的一种绿）。
BASELINE_CACHE = REPO / "scan" / "baseline_cache.json"

# App target 的源码根（相对 `CarKeeper/`，即 project.yml 所在目录）。
# ⚠️ 这里曾列着 `HealthKit` 与 `Shared` —— 两个目录都已删除，而 `target_files`
# 对不存在的目录是**静默跳过**的：「目录没了」与「目录里没东西」输出一样。
# 现在少了目录就直接失败（见 target_files 的说明）。
#
# 2026-09-23：`WIDGET = ["Widgets", "Shared"]` 整个类别已删。小组件/表盘/实时活动
# 随免费账号清理一起删除后，那两棵目录不存在了 —— WIDGET 那半边从此只会打印
# 「重复声明: 0 / 幽灵构造: 0」。**一个恒为 0 的绿灯不算绿灯**：它让「检查过」与
# 「没检查」无法区分。将来真重新引入扩展 target，要同时把 WIDGET 这类别加回来 ——
# `scan/paidcap.py` 会拦住「悄悄把扩展加回来」这种做法。
APP = ["CarKeeper", "Design", "Services", "Models"]

KEYWORDS = {
    "func", "var", "let", "case", "if", "else", "static", "in", "for", "while",
    "switch", "return", "guard", "where", "init", "self", "super", "true", "false",
    "nil", "try", "catch", "do", "repeat", "break", "continue", "default", "defer",
    "is", "as", "throw", "throws", "rethrows", "some", "any", "Type", "Protocol",
}

DECL = re.compile(
    r"^[ \t]*(?:@[A-Za-z_][\w]*(?:\([^)]*\))?[ \t]*)*"
    r"(?:public |internal |private |fileprivate |open |final |indirect )*"
    r"(struct|enum|class|actor|protocol|typealias)[ \t]+([A-Za-z_]\w*)",
    re.M,
)
EXT = re.compile(
    r"^[ \t]*(?:public |internal |private |fileprivate )*extension[ \t]+([A-Za-z_][\w.]*)", re.M
)
FUNC = re.compile(
    r"(?:^|[ \t])(?:public |private |internal |fileprivate |static |class |mutating |nonisolated |@\w+ )*"
    r"func[ \t]+([A-Za-z_]\w*)"
)
MEMBER = re.compile(
    r"(?:^|[ \t])(?:public |private |internal |fileprivate |static |class |lazy |@\w+ )*"
    r"(?:let|var|func)[ \t]+([A-Za-z_]\w*)"
)
CASE = re.compile(r"^[ \t]*(?:indirect )?case[ \t]+(.+)$", re.M)

TYPE_REF = re.compile(r"(?::[ \t]*|->[ \t]*|\[\s*|<\s*|as[?!][ \t]*|is[ \t]+|&[ \t]*)([A-Z][A-Za-z0-9_]*)")
CALL_REF = re.compile(r"(?<![A-Za-z0-9_.$])([A-Z][A-Za-z0-9_]*)\s*\(")
METHOD_REF = re.compile(r"\.([a-z_][A-Za-z0-9_]*)\s*\(")
MEMBER_REF = re.compile(r"(?<![A-Za-z0-9_.])([A-Z][A-Za-z0-9_]*)\.([a-z_][A-Za-z0-9_]*)")
# 行首的「类型名 + 尾随闭包」：ViewBuilder 容器的标准写法（`VStack { }`、`DSCard { }`）。
# 它既不是 TYPE_REF（前面没有 `:` `->` `[` `<` `as!` `is` `&`），也不是 CALL_REF（没有括号），
# 所以旧版**完全看不见它** —— 2026-09-21 的 LoginView `GlassCard {`（编译报
# "cannot find 'GlassCard' in scope"）就是这样溜到 macOS runner 上的：删文件时以为
# 无人引用（当时 grep 只看 `GlassCard(` 这类写法），编译器不这么想。
# 分析基线时用同一个正则，所以常用容器名会经 bref 进入白名单，不会新增假阳性。
TRAILING_CLOSURE_REF = re.compile(r"(?m)^[ \t]*([A-Z][A-Za-z0-9_]*)[ \t]*\{")


def read(p):
    """读取源码并把行尾归一化。

    本仓库在 Windows 上被 autocrlf 检出成 `\\r\\r\\n`（CR 写了两遍），
    直接 replace("\\r","") 会把换行也吃掉，而留着又会让行号翻倍。
    这里：先把「连续 CR + LF」收成一个 LF（保持空行），再把裸 CR 当换行。
    """
    t = p.read_bytes().decode("utf-8", "replace")   # 必须按字节读：read_text 的
    t = re.sub(r"\r+\n", "\n", t)                    # universal newlines 会先把
    return re.sub(r"\r", "\n", t)                     # \r\r\n 展开成两个换行


def target_files(roots, base=CK):
    """roots 里每一项都必须真实存在 —— 目录不存在不报错，会让「检查范围」静默缩小。"""
    out = []
    missing = []
    for r in roots:
        p = base / r
        if p.is_dir():
            out += sorted(p.rglob("*.swift"))
        elif p.suffix == ".swift" and p.is_file():
            out.append(p)
        else:
            missing.append(str(p))
    if missing:
        print("❌ 声明了不存在的源码路径:")
        for m in missing:
            print(f"   {m}")
        print("   目录已删就从清单里去掉；目录该在就把目录找回来。")
        return None
    if not out:
        print("❌ 声明的源码路径里一个 .swift 都没有 —— 检查范围是空的。")
        return None
    return out


# --------------------------------------------------------------- lexer
def lex(text, clean=False):
    """遍历源码。clean=True 时把注释/字符串换成等长空格（用于名字扫描）。"""
    out = [] if clean else None
    counts = {c: 0 for c in "()[]{}"}
    unterminated = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            if clean:
                out.append("\n")
            i += 1
            continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            if clean:
                out.append(" " * (j - i))
            i = j
            continue
        if text.startswith("/*", i):
            start, d = i, 1
            i += 2
            while i < n and d:
                if text.startswith("/*", i):
                    d, i = d + 1, i + 2
                elif text.startswith("*/", i):
                    d, i = d - 1, i + 2
                else:
                    if text[i] == "\n":
                        line += 1
                        if clean:
                            out.append("\n")
                    i += 1
            if clean:
                out.append(" " * max(0, i - start - (i - start) % 1))
            continue
        if text.startswith('"""', i):
            end = text.find('"""', i + 3)
            if end == -1:
                unterminated.append((line, 'unterminated """'))
                break
            if clean:
                out.append(" " * (end + 3 - i))
            line += text.count("\n", i, end)
            i = end + 3
            continue
        if c == '"':
            j, ok = i + 1, False
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == "\n":
                    break
                if text[j] == '"':
                    ok = True
                    break
                j += 1
            if clean:
                out.append(" " * ((j + 1 if ok else j) - i))
            if ok:
                i = j + 1
            else:
                unterminated.append((line, text[i:i + 70].replace("\n", "\\n")))
                i = j
            continue
        if c in counts:
            counts[c] += 1
        if clean:
            out.append(c)
        i += 1
    return (counts, unterminated, "".join(out)) if clean else (counts, unterminated)


def body_of(text, idx):
    """从 idx 处的 `{` 起到配对的 `}`（不含）为止。

    必须跳过注释/字符串：`Text("{")` 这类写法会让朴素的花括号计数
    把 body 拉到后面好几个成员上，语句数、子视图数全部失真。
    """
    if idx < 0 or idx >= len(text):
        return ""
    d, i, n = 0, idx, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            if text.startswith('"""', i):
                j = text.find('"""', i + 3)
                i = n if j < 0 else j + 3
                continue
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == "\n":
                    break
                j += 1
            i = j + 1
            continue
        if c == "{":
            d += 1
        elif c == "}":
            d -= 1
            if d == 0:
                return text[idx:i]
        i += 1
    return text[idx:]


def cases_of(body):
    names = set()
    for line in CASE.findall(body):
        line = line.split("{")[0]
        for part in line.split(","):
            part = part.strip()
            m = re.match(r"(?:`)?([A-Za-z_]\w*)", part)
            if m:
                names.add(m.group(1))
    return names


def collect(text, cleaned):
    """返回 types / members(map) / funcs"""
    types = set()
    qualified = []
    decls = []
    for m in DECL.finditer(text):
        name = m.group(2)
        if name in KEYWORDS:
            continue
        brace = text.find("{", m.end() - 1)
        body = body_of(text, brace)
        decls.append((name, m.start(), brace + len(body) + 1, body))
        types.add(name)
    for name, start, end, _ in decls:
        parent, best = None, -1
        for n2, s2, e2, _b in decls:
            if s2 < start < e2 and s2 > best:
                parent, best = n2, s2
        qualified.append(f"{parent}.{name}" if parent else name)

    members = {}
    for (name, _s, _e, body), q in zip(decls, qualified):
        got = set(MEMBER.findall(body)) | cases_of(body)
        members.setdefault(name, set()).update(got)
        members.setdefault(q, set()).update(got)
    # extension 里的成员
    for m in EXT.finditer(text):
        tname = m.group(1)
        brace = text.find("{", m.end() - 1)
        body = body_of(text, brace)
        got = set(MEMBER.findall(body)) | cases_of(body)
        members.setdefault(tname, set()).update(got)
        members.setdefault(tname.split(".")[-1], set()).update(got)

    funcs = set(FUNC.findall(text))
    return types, members, funcs


def analyze(paths):
    types, members, funcs = set(), {}, set()
    refs, calls, methods, memrefs = set(), {}, {}, {}
    problems = {}
    for p in paths:
        text = read(p)
        counts, unterminated, cleaned = lex(text, clean=True)
        t, m, f = collect(text, cleaned)
        types |= t
        funcs |= f
        for k, v in m.items():
            members.setdefault(k, set()).update(v)

        for a, b in (("(", ")"), ("[", "]"), ("{", "}")):
            if counts[a] != counts[b]:
                problems.setdefault(p.name, []).append(f"括号不配平 {a}={counts[a]} {b}={counts[b]}")
        for ln, snip in unterminated[:3]:
            problems.setdefault(p.name, []).append(f"L{ln} 字符串未闭合: {snip}")
        if len(re.findall(r"^\s*#if\b", text, re.M)) != len(re.findall(r"^\s*#endif\b", text, re.M)):
            problems.setdefault(p.name, []).append("#if / #endif 不配平")
        for i, ln in enumerate(text.split("\n"), 1):
            s = ln.strip()
            if re.match(r"^[a-z][A-Za-z0-9_]*[:(,)]", ln) and not re.match(
                r"^(func|let|var|static|private|public|internal|final|extension|import|case|return|if|else|guard|switch|for|while|try|await|struct|enum|class|protocol|@|#|//)", s):
                problems.setdefault(p.name, []).append(f"L{i} 顶格可疑行: {s[:80]}")

        for m2 in TYPE_REF.finditer(cleaned):
            refs.add(m2.group(1))
        for m2 in TRAILING_CLOSURE_REF.finditer(cleaned):
            refs.add(m2.group(1))
        for m2 in CALL_REF.finditer(cleaned):
            calls[m2.group(1)] = calls.get(m2.group(1), 0) + 1
        for m2 in METHOD_REF.finditer(cleaned):
            methods[m2.group(1)] = methods.get(m2.group(1), 0) + 1
        for m2 in MEMBER_REF.finditer(cleaned):
            memrefs.setdefault(m2.group(1), set()).add(m2.group(2))
    return types, members, funcs, refs, calls, methods, memrefs, problems


def save_baseline_cache(paths):
    """把基线的分析结果物化成 JSON（排序，便于 diff 与复查）。

    只存「本次扫描真正消费的」六项：main() 里的 sdk_types / sdk_calls /
    sdk_methods 恰好只由它们推出来（见 main 里那三行的定义）。
    """
    import json

    bt, bm, bf, bref, bcalls, bmethods, _m, _p = analyze(paths)
    data = {
        "_note": "由 scan/extract_baseline.sh 从冻结提交反推生成；手工修改无效（会被覆盖）",
        "_files": len(paths),
        "types": sorted(bt),
        "members": {k: sorted(v) for k, v in sorted(bm.items())},
        "funcs": sorted(bf),
        "refs": sorted(bref),
        "calls": dict(sorted(bcalls.items())),
        "methods": dict(sorted(bmethods.items())),
    }
    BASELINE_CACHE.write_text(json.dumps(data, ensure_ascii=False, indent=0),
                              encoding="utf-8")
    return bt, bm, bf, bref, bcalls, bmethods


def load_baseline_cache():
    """读缓存；不存在或版本不符则返回 None（由调用方决定是报错还是退化）。"""
    import json

    if not BASELINE_CACHE.exists():
        return None
    try:
        d = json.loads(BASELINE_CACHE.read_text(encoding="utf-8"))
    except Exception:
        return None
    need = {"types", "members", "funcs", "refs", "calls", "methods"}
    if not need <= set(d):
        return None
    return (
        set(d["types"]),
        {k: set(v) for k, v in d["members"].items()},
        set(d["funcs"]),
        set(d["refs"]),
        dict(d["calls"]),
        dict(d["methods"]),
    )


# 基线之后才引入、但已逐条对着 Apple 文档核实过确实存在的 SDK 名字。
# 基线白名单是从「最后一次能编译的提交」反推的，所以新引入的 SDK 名字
# （例如 iOS 18 的 Tab）必然不在里面 —— 在这里显式登记，登记前必须核实。
VERIFIED_SDK_ADDITIONS = {
    "Tab": "SwiftUI.Tab（iOS 18+/watchOS 11+，init(value:content:label:) 已核对 interface）",
    "AnyView": "SwiftUI.AnyView（iOS 13+）",
    "UnitPoint": "SwiftUI.UnitPoint（iOS 13+）",
    "blendMode": "View.blendMode(_:)（iOS 13+）",
    "repeatForever": "Animation.repeatForever(autoreverses:)（iOS 13+）",
    # 艺术主题（ArtTheme）用到的两个：登记前已核 Apple 文档 JSON
    "preferredColorScheme": "View.preferredColorScheme(ColorScheme?)（iOS 13+；swiftui/view/preferredcolorscheme(_:)）",
    "allowsHitTesting": "View.allowsHitTesting(Bool)（iOS 13+；swiftui/view/allowshittesting(_:)）",
    "ColorScheme": "SwiftUI.ColorScheme（iOS 13+；主题自带明暗用它表达 light/dark）",
    "RadialGradient": "SwiftUI.RadialGradient(colors:center:startRadius:endRadius:)（iOS 13+；已核文档 JSON）",
    # 光层与衬线排版（Design/SkyLight.swift、Features/Map/MapSkyOverlay.swift、MapCarPin.swift、
    # Design/Tokens.swift 的 TokensSerif）。登记前逐个核过 Apple 文档 JSON：
    "Ellipse": "SwiftUI.Ellipse（iOS 13+；externalID s:7SwiftUI7EllipseV）——车钉脚下的接地阴影",
    "UIFont": "UIKit.UIFont（iOS 2+；externalID c:objc(cs)UIFont）——用 UIFont(name:size:) 探测中文衬线是否存在",
    "custom": "Font.custom(_ name: String, size: CGFloat)（iOS 13+；externalID s:7SwiftUI4FontV6custom_4sizeACSS_14CoreFoundation7CGFloatVtFZ）",
    # 地图主屏（Features/Map/*）用到的 MapKit SwiftUI 名字。
    # 每一个都在写进代码前对着 Apple 文档 JSON 核过类型、可用版本与初始化器签名
    # （核实记录见 CarKeeper/MAPKIT-FEASIBILITY.md 第 7 节）。
    "Map": "SwiftUI/MapKit 的 Map 视图（iOS 17+；本页用 Map(position:)）",
    "mapStyle": "View.mapStyle(_ style: MapStyle)（iOS 17+；配置地图样式）",
    "MapStyle": "MapKit.MapStyle struct（iOS 17+；standard(elevation:emphasis:pointsOfInterest:showsTraffic:) 已核签名）",
    "MapCamera": "MapKit.MapCamera struct（iOS 17+；init(centerCoordinate:distance:heading:pitch:) 已核）",
    "MapCameraPosition": "MapKit.MapCameraPosition struct（iOS 17+；.automatic / .camera(_:) 已核）",
    "MapPolyline": "MapKit.MapPolyline struct（iOS 17+；用已核的 init(_ polyline: MKPolyline)）",
    "Annotation": "MapKit.Annotation struct（iOS 17+；屏幕空间标注，不随缩放变形）",
    "MKStandardMapConfiguration": "MapKit class（iOS 16+；init(elevationStyle:emphasisStyle:) 已核；EmphasisStyle.muted 已核）",
    "squareRoot": "FloatingPoint.squareRoot()（Swift 标准库；评分页算电耗的离散程度用；已核 swift/floatingpoint/squareroot() 文档 JSON，externalID s:SF10squareRootxyF）",
    "Shape": "SwiftUI.Shape protocol（iOS 13+；本项目用它画车钉的三角形警告形状）",
    "UnevenRoundedRectangle": "SwiftUI.UnevenRoundedRectangle（iOS 16+；底部面板只要上面两角圆角）",
    # 热区 / 回放 / 充电曲线（本轮）：全部写进代码前对着 Apple 文档 JSON 核过
    "MapCircle": "MapKit.MapCircle struct（iOS 17+；init(center:radius:) 已核，stroke(_:style:)/foregroundStyle 见 Styling-the-circle）",
    "Canvas": "SwiftUI.Canvas（iOS 15+；init(closure:(inout GraphicsContext, CGSize) -> Void)）",
    "GraphicsContext": "SwiftUI.GraphicsContext（iOS 15+；stroke(_:with:style:)/fill(_:with:)/draw(_:at:) 已核）",
    "Path": "SwiftUI.Path（iOS 13+；move/addLine/closeSubpath）",
    "presentationDetents": "View.presentationDetents(_:)（iOS 16+；sheet 高度档）",
    "formatted": "Date.formatted(date:time:)（iOS 15+；Foundation）",
    # 行程时间轴（TripsTimelineView）：四个均对着 Apple 文档 JSON 核过
    "LazyVStack": "SwiftUI.LazyVStack struct（iOS 14+；externalID s:7SwiftUI10LazyVStackV）",
    "constant": "Binding.constant(_:)（iOS 13+；静态方法，externalID s:7SwiftUI7BindingV8constantyACyxGxFZ）",
    "isDateInYesterday": "Calendar.isDateInYesterday(_:)（iOS 8+；Foundation，externalID s:10Foundation8CalendarV17isDateInYesterdayySbAA0D0VF）",
    "compactMap": "Sequence.compactMap(_:)（Swift 标准库；externalID s:ST13compactMapySay7ElementQd_Gqd_7ElementQRs_rlEF）",
    # 浮层画布 / 标注聚合 / 比例尺 / 长按菜单（本轮）：
    # 每个都写进代码前对着 Apple 文档 JSON 核过签名
    "presentationBackground": "View.presentationBackground(alignment:content:)（iOS 16.4+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/presentationBackground(alignment:content:)：浮层自己的背景，不是内容底）",
    "MapScaleView": "MapKit.MapScaleView（iOS 17+；init(alignment:scope:)/init(anchorEdge:scope:) 已核，externalID doc://com.apple.mapkit/documentation/MapKit/MapScaleView）",
    "mapControls": "View.mapControls(_:)（iOS 17+；decl: func mapControls(@ViewBuilder _ content: () -> some View)，externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/mapControls(_:)：把系统地图控件放进地图）",
    "mapControlVisibility": "View.mapControlVisibility(_:)（iOS 17+；decl: func mapControlVisibility(_ visibility: Visibility)，externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/mapControlVisibility(_:)）",
    "contextMenu": "View.contextMenu(menuItems:)（iOS 13+；decl: nonisolated func contextMenu<MenuItems>(@ContentBuilder menuItems: () -> MenuItems)，externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/contextMenu(menuItems:)：长按菜单——明细行的删除挂在它上面）",
    # 天气（WeatherService）：三个都是 Foundation / Swift 标准库的名字，
    # 登记前对着 Apple 文档 JSON 核过存在性与平台（iOS 全平台）：
    "Equatable": "Swift.Equatable（Swift 标准库；externalID doc://com.apple.Swift/documentation/Swift/Equatable）——天气快照要能比较",
    "URLQueryItem": "Foundation.URLQueryItem（iOS 8+；externalID doc://com.apple.foundation/documentation/Foundation/URLQueryItem）——拼 Open-Meteo 的查询参数",
    "URLComponents": "Foundation.URLComponents（iOS 7+；externalID doc://com.apple.foundation/documentation/Foundation/URLComponents）——用它拼 URL 而不是手写字符串，避免转义踩坑",
    # App Intents（Siri 车控）：整族都对着 Apple 文档 JSON 核过，
    # 旧的 INIntent 子类因为没有 Intent Extension target，永远不可能被唤起。
    "AppIntent": "AppIntents.AppIntent 协议（iOS 16+；decl: protocol AppIntent : PersistentlyIdentifiable, _SupportsAppDependencies, Sendable；externalID doc://com.apple.AppIntents/documentation/AppIntents/AppIntent）",
    "AppShortcutsProvider": "AppIntents.AppShortcutsProvider（iOS 16+；externalID doc://com.apple.AppIntents/documentation/AppIntents/AppShortcutsProvider）——实现它就等于把指令注册进系统「快捷指令」，不需要额外 target",
    "AppShortcut": "AppIntents.AppShortcut（iOS 16+；decl: init(intent:phrases:shortTitle:systemImageName:)；externalID doc://com.apple.AppIntents/documentation/AppIntents/AppShortcut）",
    "IntentDescription": "AppIntents.IntentDescription（iOS 16+；externalID doc://com.apple.AppIntents/documentation/AppIntents/IntentDescription）",
    "IntentDialog": "AppIntents.IntentDialog（iOS 16+；externalID doc://com.apple.AppIntents/documentation/AppIntents/IntentDialog）——Siri 的回话文案",
    "LocalizedStringResource": "Foundation.LocalizedStringResource（iOS 16+；externalID doc://com.apple.foundation/documentation/Foundation/LocalizedStringResource）——IntentDialog 的构造入参",
    "IntentResult": "AppIntents.IntentResult 协议（iOS 16+；return .result(dialog:) 的返回类型）",
    "ProvidesDialog": "AppIntents.ProvidesDialog 协议（iOS 16+；与 IntentResult 组合表示「这次执行有一句话要说」）",
    "appShortcuts": "AppShortcutsProvider.appShortcuts（协议要求实现的静态属性）",
    "shortTitle": "AppShortcut.init(intent:phrases:shortTitle:systemImageName:) 的 shortTitle 参数",
    "systemImageName": "AppShortcut.init(intent:phrases:shortTitle:systemImageName:) 的 systemImageName 参数",
    "phrases": "AppShortcut.init(intent:phrases:shortTitle:systemImageName:) 的 phrases 参数（LocalizedStringResource 数组，用 .applicationName 插值）",
    "openAppWhenRun": "AppIntent.openAppWhenRun（协议提供的静态属性；车控是后台动作，设为 false）",
    "perform": "AppIntent.perform()（协议要求实现的唯一方法）",
    "applicationName": "AppShortcutPhrase 里的 .applicationName（自动替换成 App 名）",
    # 全局搜索 HUD（本轮）：两个系统修饰符，登记前都打印了 decl 确认：
    "fullScreenCover": "View.fullScreenCover(isPresented:onDismiss:content:)（iOS 14+；decl: nonisolated func fullScreenCover<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping () -> Content) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/fullScreenCover(isPresented:onDismiss:content:)）——搜索 HUD 要盖住全屏，半屏 sheet 会把压暗背景拆成两段",
    "Sendable": "Swift.Sendable 协议（Swift 标准库；decl: protocol Sendable : SendableMetatype；externalID doc://com.apple.Swift/documentation/Swift/Sendable）——Siri 指令的结果枚举要能跨隔离传递",
    "submitLabel": "View.submitLabel(_:)（iOS 15+；decl: nonisolated func submitLabel(_ submitLabel: SubmitLabel) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/submitLabel(_:)）——搜索框回车键改成「搜索」",
    "truncationMode": "View.truncationMode(_:)（iOS 13+；decl: nonisolated func truncationMode(_ mode: Text.TruncationMode) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/truncationMode(_:)）——地图操作条在跑指令时，把「第 3 次查询 · 车辆处理中」从中间截断（尾巴比中间重要：进度数字在头部）。注：它是 View 的方法，不是 Text 的",
    # 叠叠乐与相机式模式条（Design/StackSpec.swift、ArcStack.swift、GlassCard.swift、
    # DSSwipeStrip.swift）。以下每个都写进代码前对着 Apple 文档核过 decl 与平台。
    "glassEffect": "View.glassEffect(_:in:)（iOS 26+；decl: func glassEffect(_ glass: Glass = .regular, in shape: some Shape = .capsule) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/glassEffect(_:in:)；概述见「Applying Liquid Glass to custom views」）——卡片与模式条的**唯一材质来源**。用系统玻璃而不是自己叠 blur+opacity：折射与反射是物理材质，四套艺术主题下都会自己去适配底色",
    "interpolatingSpring": "Animation.interpolatingSpring(mass:stiffness:damping:initialVelocity:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/Animation/interpolatingSpring(mass:stiffness:damping:initialVelocity:)）——吸附回落的弹簧。选它而不是 easeOutBack：过冲是同一件事，但弹簧能被下一次手势接管，缓动不能",
    "rotation3DEffect": "View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/rotation3DEffect(_:axis:anchor:anchorZ:perspective:)）——卡片离开阅读线时向后转出去，滚轮叠法靠它绕圆柱面",
    "zIndex": "View.zIndex(_:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/zIndex(_:)）——把压在阅读线上的那张抬到最上层；重合叠放不加它会出现「近的那张被远的盖住」",
    "clipped": "View.clipped(antialiased:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/clipped(antialiased:)）——叠叠乐是一个固定窗口，带外的卡必须先裁掉再谈渐隐",
    "highPriorityGesture": "View.highPriorityGesture(_:including:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/highPriorityGesture(_:including:)）——模式条要「按下就展开」，所以整条的拖动优先于标签自己的点选（点选由同一条手势里判断位移来做，见 DSSwipeStrip）",
    "textCase": "View.textCase(_:)（iOS 13+；decl: func textCase(_ textCase: Text.Case?) -> some View）——卡片小标题走 iOS 分组头的大写形态",
    "accessibilityAction": "View.accessibilityAction(_:_:)（iOS 13+；decl: func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier>；.scrollUp / .scrollDown 为 AccessibilityActionKind 的静态成员）——叠叠乐**没有 ScrollView**，也就没有系统给的三指滚动；不挂这两个动作，VoiceOver 用户完全无法翻页，而且不会有任何报错提醒你",
}


def report(label, paths, whitelist):
    types, members, funcs, refs, calls, methods, memrefs, problems = analyze(paths)
    sdk_types, sdk_calls, sdk_methods = whitelist
    print(f"\n===== {label}: 结构性问题 {len(problems)} =====")
    for p, msgs in sorted(problems.items()):
        for msg in msgs:
            print(f"   {p}: {msg}")

    unk_types = sorted(r for r in refs if r not in types and r not in sdk_types)
    print(f"\n-- {label} 未声明的类型: {len(unk_types)}")
    print("   " + " ".join(unk_types[:60]))

    unk_calls = sorted(c for c in calls if c not in types and c not in funcs and c not in sdk_calls)
    print(f"\n-- {label} 未声明的构造/函数: {len(unk_calls)}")
    print("   " + " ".join(unk_calls[:60]))

    all_names = set(funcs)
    for v in members.values():
        all_names |= v
    unk_methods = sorted(m for m in methods if m not in all_names and m not in sdk_methods)
    print(f"\n-- {label} 未声明的方法: {len(unk_methods)}")
    print("   " + " ".join(unk_methods[:60]))

    ignore = {"rawValue", "allCases", "self", "Type", "Protocol", "id", "init", "hashValue",
              "description", "debugDescription", "hash", "Body", "Element", "Index",
              "Iterator", "SubSequence", "key", "value", "count"}
    ignore_prefix = {"Color", "Data", "Font", "Image", "View", "Text", "Date", "Set",
                     "Array", "Dictionary", "Task", "Publisher", "Animation", "Binding"}
    bad = []
    for t, ms in sorted(memrefs.items()):
        if t not in types or t in ignore_prefix:
            continue
        declared = members.get(t, set())
        for m in sorted(ms):
            if m not in declared and m not in ignore:
                bad.append(f"{t}.{m}")
    print(f"\n-- {label} 项目类型的未知成员: {len(bad)}")
    print("   " + " ".join(bad[:60]))
    # 返回「高嫌疑」计数，供 main 决定退出码 —— 检查器必须能失败，否则它只是一段日志。
    return {
        "结构性问题": len(problems),
        "未声明的类型": len(unk_types),
        "未声明的构造/函数": len(unk_calls),
        "未声明的方法": len(unk_methods),
        "未知成员": len(bad),
    }


# 「幽灵构造」：当前代码里调用了 `X(...)`，当前树没有声明 X，
# 但冻结基线里**声明过** X —— 只可能是删除声明块时漏删的残留（CarSwitchGesture、
# GlassCard 都是这一类：基线白名单反而掩护了它们，因为「未声明」检查永远放行）。
# 已知歧义名：基线里是嵌套类型声明、当前代码用的是同名标准库类型（Result 等）。
GHOST_CALL_IGNORE = {"Result"}


def ghost_calls(label, paths, baseline_types, current_types, current_funcs):
    _, _, _, _, calls, _, _, _ = analyze(paths)
    ghosts = sorted(
        c for c in calls
        if c in baseline_types
        and c not in current_types
        and c not in current_funcs
        and c not in GHOST_CALL_IGNORE
    )
    print(f"\n-- {label} 幽灵构造（基线声明过、当前已删、代码仍在调）: {len(ghosts)}")
    if ghosts:
        print("   " + " ".join(ghosts[:60]))
    return len(ghosts)


def main():
    app_paths = target_files(APP)
    if app_paths is None:
        return 1

    for label, paths in (("APP", app_paths),):
        seen = {}
        for p in paths:
            text = read(p)
            decls = []
            for m in DECL.finditer(text):
                if m.group(2) in KEYWORDS:
                    continue
                brace = text.find("{", m.end() - 1)
                body = body_of(text, brace)
                decls.append((m.group(2), m.start(), brace + len(body) + 1))
            for name, start, end in decls:
                parent, best = None, -1
                for n2, s2, e2 in decls:
                    if s2 < start < e2 and s2 > best:
                        parent, best = n2, s2
                q = f"{parent}.{name}" if parent else name
                seen.setdefault(q, []).append(p.name)
        dups = {k: v for k, v in seen.items() if len(v) > 1}
        print(f"### {label} 重复声明: {len(dups)}")
        for k, v in sorted(dups.items()):
            print(f"   {k}: {v}")

    # 基线白名单：开发机上直接分析基线目录（并刷新缓存）；干净机器 / CI 用提交进仓库的缓存
    base_paths = sorted(BASELINE.rglob("*.swift"))
    if base_paths:
        bt, bm, bf, bref, bcalls, bmethods = save_baseline_cache(base_paths)
        base_note = f"{len(base_paths)} 文件（现场分析，缓存已刷新）"
    else:
        cached = load_baseline_cache()
        if cached is None:
            print("\n❌ 基线缺失：scan/baseline/ 与 scan/baseline_cache.json 都不存在。")
            print("   符号检查无法进行。而「无法检查」不等于「没问题」—— 所以这里按**失败**退出，")
            print("   而不是打印一行提示就 return 0（那会把绿色悄悄变成一句空话）。")
            print("   修法：git pull 取回缓存；或 scan/extract_baseline.sh <能编译的提交> 重新生成。")
            return 1
        bt, bm, bf, bref, bcalls, bmethods = cached
        base_note = "缓存快照（由 extract_baseline.sh 从冻结提交生成）"
    sdk_types = bt | bref | set(bcalls) | set(VERIFIED_SDK_ADDITIONS)
    sdk_calls = bt | set(bcalls) | set(VERIFIED_SDK_ADDITIONS)
    sdk_methods = set(bmethods) | bf | set(VERIFIED_SDK_ADDITIONS)
    for v in bm.values():
        sdk_methods |= v
    print(f"显式核实的 SDK 名字: {len(VERIFIED_SDK_ADDITIONS)}")
    print(f"\n基线: {base_note}, 已知名字 类型{len(sdk_types)}/方法{len(sdk_methods)}")

    # 幽灵构造需要「当前树的自有声明」—— analyze 只在 report 里跑过一次，
    # 这里再取一次它的类型/函数集（解析很快，重复跑可接受）。
    # 注意：基线信号只能用 **声明**（bt | bf）。第一版把 bcalls（基线代码里的调用）
    # 也算进来，结果 Text/VStack 这些 SDK 调用全成了"基线声明过的名字"，一次 164 个假阳性。
    app_types, _, app_funcs, _, _, _, _, _ = analyze(app_paths)
    base_decls = bt | bf
    found = report("APP", app_paths, (sdk_types, sdk_calls, sdk_methods))
    found["幽灵构造"] = ghost_calls("APP", app_paths, base_decls, app_types, app_funcs)
    total = sum(found.values())
    if total:
        print("\n❌ 高嫌疑汇总: " + "  ".join(f"{k}={v}" for k, v in found.items() if v))
        print("   白名单里没有它们 = 项目没声明、基线也没有 → 很可能是打错的名字（编译会挂）。")
        print("   幽灵构造 = 基线声明过、当前树已删、代码仍在调 → 删除声明块时漏删了引用（编译会挂）。")
        return 1
    print("\n✅ 未声明的类型 / 构造·函数 / 方法 / 未知成员 全部为 0")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
