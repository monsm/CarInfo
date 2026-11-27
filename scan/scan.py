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
BASELINE_CACHE = REPO / "scan" / "baseline_cache.json"

APP = ["CarKeeper", "Design", "Services"]

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
TRAILING_CLOSURE_REF = re.compile(r"(?m)^[ \t]*([A-Z][A-Za-z0-9_]*)[ \t]*\{")
SELF_MEMBER_REF = re.compile(r"(?<![A-Za-z0-9_.])Self\.([a-z_][A-Za-z0-9_]*)")


def read(p):
    """读取源码并把行尾归一化。

    本仓库在 Windows 上被 autocrlf 检出成 `\\r\\r\\n`（CR 写了两遍），
    直接 replace("\\r","") 会把换行也吃掉，而留着又会让行号翻倍。
    这里：先把「连续 CR + LF」收成一个 LF（保持空行），再把裸 CR 当换行。
    """
    t = p.read_bytes().decode("utf-8", "replace")
    t = re.sub(r"\r+\n", "\n", t)
    return re.sub(r"\r", "\n", t)


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


GENERIC = re.compile(
    r"(?:struct|class|enum|actor|func|extension)\s+[A-Za-z_][A-Za-z0-9_.]*\s*<([^<>{}()]*)>"
)
BARE_UPPER = re.compile(r"^[A-Z][A-Za-z0-9_]*$")


def generic_params(text):
    out = set()
    for m in GENERIC.finditer(text):
        for part in m.group(1).split(","):
            name = part.split(":")[0].strip()
            if BARE_UPPER.match(name):
                out.add(name)
    return out


def collect(text, cleaned):
    """返回 types / members(map) / funcs"""
    types = generic_params(text)
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
    for m in EXT.finditer(text):
        tname = m.group(1)
        brace = text.find("{", m.end() - 1)
        body = body_of(text, brace)
        got = set(MEMBER.findall(body)) | cases_of(body)
        members.setdefault(tname, set()).update(got)
        members.setdefault(tname.split(".")[-1], set()).update(got)

    funcs = set(FUNC.findall(text))
    return types, members, funcs


def decl_spans(masked):
    """本文件里所有类型 / extension 声明的 (名字, 体起点, 体终点)。

    只给 `Self.x` 找家用：`Self` 的含义是「当前这个类型」，而那是**位置**决定的。
    用 `masked` 而不是原文：注释里的 `struct Foo {` 不该算一个候选。
    """
    out = []
    for rx, gi in ((DECL, 2), (EXT, 1)):
        for m in rx.finditer(masked):
            brace = masked.find("{", m.end() - 1)
            if brace < 0:
                continue
            out.append((m.group(gi).split(".")[-1], brace, brace + len(body_of(masked, brace))))
    return out


def enclosing_decl(spans, pos):
    """pos 落在哪个类型的体内（多个命中时取**最内层**的那个）。"""
    best, name = -1, None
    for n, s, e in spans:
        if s < pos < e and s > best:
            best, name = s, n
    return name


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
        spans = decl_spans(cleaned)
        for m2 in SELF_MEMBER_REF.finditer(cleaned):
            owner = enclosing_decl(spans, m2.start())
            if owner:
                memrefs.setdefault(owner, set()).add(m2.group(1))
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


VERIFIED_SDK_ADDITIONS = {
    "CLLocationManager": "CoreLocation.CLLocationManager（iOS 2.0+；externalID c:objc(cs)CLLocationManager）—— 手机自己的位置，按需取一次",
    "requestWhenInUseAuthorization": "CLLocationManager.requestWhenInUseAuthorization()（iOS 8+；externalID c:objc(cs)CLLocationManager(im)requestWhenInUseAuthorization）",
    "startUpdatingLocation": "CLLocationManager.startUpdatingLocation()（iOS 2.0+；externalID c:objc(cs)CLLocationManager(im)startUpdatingLocation）",
    "stopUpdatingLocation": "CLLocationManager.stopUpdatingLocation()（iOS 2.0+；externalID c:objc(cs)CLLocationManager(im)stopUpdatingLocation）—— 取到就停",
    "Tab": "SwiftUI.Tab（iOS 18+/watchOS 11+，init(value:content:label:) 已核对 interface）",
    "AnyView": "SwiftUI.AnyView（iOS 13+）",
    "UIAccessibility": "UIKit.UIAccessibility（iOS 2.0+）—— 「降低透明度」这一档的唯一读者",
    "isReduceTransparencyEnabled": "UIAccessibility.isReduceTransparencyEnabled（UIKit；doc://com.apple.uikit/documentation/UIKit/UIAccessibility/isreducetransparencyenabled；abstract: A Boolean value that indicates whether the Reduce Transparency setting is in an enabled state.）",
    "UnitPoint": "SwiftUI.UnitPoint（iOS 13+）",
    "blendMode": "View.blendMode(_:)（iOS 13+）",
    "repeatForever": "Animation.repeatForever(autoreverses:)（iOS 13+）",
    "TimelineView": "SwiftUI.TimelineView（iOS 15+；doc：swiftui/timelineview，A view that updates according to a schedule that you provide.）—— **已无读者**（它曾是那枚刷新倒计时的秒表）",
    "periodic": "TimelineSchedule.periodic(from:by:)（iOS 15+；doc：swiftui/timelineschedule/periodic(from:by:)，A schedule for updating a timeline view at regular intervals.）—— **已无读者**（同上）",
    "preferredColorScheme": "View.preferredColorScheme(ColorScheme?)（iOS 13+；swiftui/view/preferredcolorscheme(_:)）",
    "allowsHitTesting": "View.allowsHitTesting(Bool)（iOS 13+；swiftui/view/allowshittesting(_:)）",
    "ColorScheme": "SwiftUI.ColorScheme（iOS 13+；主题自带明暗用它表达 light/dark）",
    "RadialGradient": "SwiftUI.RadialGradient(colors:center:startRadius:endRadius:)（iOS 13+；已核文档 JSON）",
    "Ellipse": "SwiftUI.Ellipse（iOS 13+；externalID s:7SwiftUI7EllipseV）——车钉脚下的接地阴影",
    "UIFont": "UIKit.UIFont（iOS 2+；externalID c:objc(cs)UIFont）——用 UIFont(name:size:) 探测中文衬线是否存在",
    "custom": "Font.custom(_ name: String, size: CGFloat)（iOS 13+；externalID s:7SwiftUI4FontV6custom_4sizeACSS_14CoreFoundation7CGFloatVtFZ）",
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
    "InsettableShape": "SwiftUI.InsettableShape protocol（iOS 13+；externalID s:7SwiftUI15InsettableShapeP；"
                       "abstract「A shape type that is able to inset itself to produce another shape.」）"
                       "—— `dsGlass` 的形状约束：那圈发丝线用的是 strokeBorder，它只在这个协议上（2026-09-25）",
    "Glass": "SwiftUI.Glass struct（iOS 26+；externalID s:7SwiftUI5GlassV）——玻璃材质的配置",
    "GlassEffectContainer": "SwiftUI.GlassEffectContainer struct（iOS 26+；externalID "
        "s:7SwiftUI20GlassEffectContainerV）——把多块玻璃合成一层，`dsGlassLayer` 是它的入口",
    "glassEffect": "View.glassEffect(_:in:)（iOS 26+；externalID "
        "s:7SwiftUI4ViewPAAE11glassEffect_2inQrAA5GlassV_qd__tAA5ShapeRd__lF）——挂液态玻璃",
    "interactive": "Glass.interactive(_:)（iOS 26+）——让玻璃按下去时有系统的压缩与折射",
    "tint": "Glass.tint(_:)（iOS 26+）——在同一档材质上再压一层色，是系统给的「更实」的形态。"
        "2026-09-26「玻璃通透度」那一档用它，而**不是**在玻璃底下垫一块面（垫面会把材质挡掉，"
        "`scan/glass.py` 的判据 ③ 正在拦）。同一名字在 Slider 上也有（那是另一件事）。",
    "UnevenRoundedRectangle": "SwiftUI.UnevenRoundedRectangle（iOS 16+；底部面板只要上面两角圆角）",
    "MapCircle": "MapKit.MapCircle struct（iOS 17+；init(center:radius:) 已核，stroke(_:style:)/foregroundStyle 见 Styling-the-circle）",
    "Canvas": "SwiftUI.Canvas（iOS 15+；init(closure:(inout GraphicsContext, CGSize) -> Void)）",
    "GraphicsContext": "SwiftUI.GraphicsContext（iOS 15+；stroke(_:with:style:)/fill(_:with:)/draw(_:at:) 已核）",
    "Path": "SwiftUI.Path（iOS 13+；move/addLine/closeSubpath）",
    "presentationDetents": "View.presentationDetents(_:)（iOS 16+；sheet 高度档）",
    "presentationBackgroundInteraction": "View.presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction)（iOS 16.4+；externalID s:7SwiftUI4ViewPAAE33presentationBackgroundInteractionyQrAA012PresentationeF0VF）—— 半屏时底下那张地图仍然可以拖，Apple 地图就是这个行为；上一版自画的抽屉从头到尾盖住地图",
    "presentationDragIndicator": "View.presentationDragIndicator(_ visibility: Visibility)（iOS 16.0+；externalID s:7SwiftUI4ViewPAAE25presentationDragIndicatoryQrAA10VisibilityOF）—— 系统那枚拉手（尺寸/对比度/热区由系统给，不再自己画 Capsule）",
    "PresentationBackgroundInteraction": "SwiftUI.PresentationBackgroundInteraction（iOS 16.4+；静态方法 enabled(upThrough: PresentationDetent) -> Self，externalID s:7SwiftUI33PresentationBackgroundInteractionV7enabled9upThroughAcA0C6DetentV_tFZ）",
    "formatted": "Date.formatted(date:time:)（iOS 15+；Foundation）",
    "LazyVStack": "SwiftUI.LazyVStack struct（iOS 14+；externalID s:7SwiftUI10LazyVStackV）",
    "constant": "Binding.constant(_:)（iOS 13+；静态方法，externalID s:7SwiftUI7BindingV8constantyACyxGxFZ）",
    "isDateInYesterday": "Calendar.isDateInYesterday(_:)（iOS 8+；Foundation，externalID s:10Foundation8CalendarV17isDateInYesterdayySbAA0D0VF）",
    "compactMap": "Sequence.compactMap(_:)（Swift 标准库；externalID s:ST13compactMapySay7ElementQd_Gqd_7ElementQRs_rlEF）",
    "presentationBackground": "View.presentationBackground(alignment:content:)（iOS 16.4+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/presentationBackground(alignment:content:)：浮层自己的背景，不是内容底）",
    "MapScaleView": "MapKit.MapScaleView（iOS 17+；init(alignment:scope:)/init(anchorEdge:scope:) 已核，externalID doc://com.apple.mapkit/documentation/MapKit/MapScaleView）",
    "mapControls": "View.mapControls(_:)（iOS 17+；decl: func mapControls(@ViewBuilder _ content: () -> some View)，externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/mapControls(_:)：把系统地图控件放进地图）",
    "mapControlVisibility": "View.mapControlVisibility(_:)（iOS 17+；decl: func mapControlVisibility(_ visibility: Visibility)，externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/mapControlVisibility(_:)）",
    "contextMenu": "View.contextMenu(menuItems:)（iOS 13+；decl: nonisolated func contextMenu<MenuItems>(@ContentBuilder menuItems: () -> MenuItems)，externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/contextMenu(menuItems:)：长按菜单——明细行的删除挂在它上面）",
    "Equatable": "Swift.Equatable（Swift 标准库；externalID doc://com.apple.Swift/documentation/Swift/Equatable）——天气快照要能比较",
    "URLQueryItem": "Foundation.URLQueryItem（iOS 8+；externalID doc://com.apple.foundation/documentation/Foundation/URLQueryItem）——拼 Open-Meteo 的查询参数",
    "URLComponents": "Foundation.URLComponents（iOS 7+；externalID doc://com.apple.foundation/documentation/Foundation/URLComponents）——用它拼 URL 而不是手写字符串，避免转义踩坑",
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
    "fullScreenCover": "View.fullScreenCover(isPresented:onDismiss:content:)（iOS 14+；decl: nonisolated func fullScreenCover<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ContentBuilder content: @escaping () -> Content) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/fullScreenCover(isPresented:onDismiss:content:)）——搜索 HUD 要盖住全屏，半屏 sheet 会把压暗背景拆成两段",
    "Sendable": "Swift.Sendable 协议（Swift 标准库；decl: protocol Sendable : SendableMetatype；externalID doc://com.apple.Swift/documentation/Swift/Sendable）——Siri 指令的结果枚举要能跨隔离传递",
    "submitLabel": "View.submitLabel(_:)（iOS 15+；decl: nonisolated func submitLabel(_ submitLabel: SubmitLabel) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/submitLabel(_:)）——搜索框回车键改成「搜索」",
    "truncationMode": "View.truncationMode(_:)（iOS 13+；decl: nonisolated func truncationMode(_ mode: Text.TruncationMode) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/truncationMode(_:)）——地图操作条在跑指令时，把「第 3 次查询 · 车辆处理中」从中间截断（尾巴比中间重要：进度数字在头部）。注：它是 View 的方法，不是 Text 的",
    "glassEffect": "View.glassEffect(_:in:)（iOS 26+；decl: func glassEffect(_ glass: Glass = .regular, in shape: some Shape = .capsule) -> some View；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/glassEffect(_:in:)；概述见「Applying Liquid Glass to custom views」）——卡片与模式条的**唯一材质来源**。用系统玻璃而不是自己叠 blur+opacity：折射与反射是物理材质，四套艺术主题下都会自己去适配底色",
    "interpolatingSpring": "Animation.interpolatingSpring(mass:stiffness:damping:initialVelocity:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/Animation/interpolatingSpring(mass:stiffness:damping:initialVelocity:)）——2026-09-25 起它只服务无障碍翻页那一步（`ArcStack.step`）：手势与惯性都归系统 `ScrollView` 了。选它而不是 easeOutBack：过冲是同一件事，但弹簧能被下一次手势接管，缓动不能",
    "rotation3DEffect": "View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/rotation3DEffect(_:axis:anchor:anchorZ:perspective:)）——卡片离开阅读线时向后转出去，滚轮叠法靠它绕圆柱面",
    "zIndex": "View.zIndex(_:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/zIndex(_:)）——把压在阅读线上的那张抬到最上层；重合叠放不加它会出现「近的那张被远的盖住」",
    "clipped": "View.clipped(antialiased:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/clipped(antialiased:)）——叠叠乐是一个固定窗口，带外的卡必须先裁掉再谈渐隐",
    "highPriorityGesture": "View.highPriorityGesture(_:including:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/highPriorityGesture(_:including:)）——模式条要「按下就展开」，所以整条的拖动优先于标签自己的点选（点选由同一条手势里判断位移来做，见 DSSwipeStrip）",
    "textCase": "View.textCase(_:)（iOS 13+；decl: func textCase(_ textCase: Text.Case?) -> some View）——卡片小标题走 iOS 分组头的大写形态",
    "accessibilityAdjustableAction": "View.accessibilityAdjustableAction(_:)（iOS 13+；decl: func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier>；externalID s:7SwiftUI4ViewPAAE29accessibilityAdjustableActionyAA15ModifiedContentVyxAA31AccessibilityAttachmentModifierVGyAA0I19AdjustmentDirectionOcF）——叠叠乐翻页的**元素级**手势：焦点落在这叠纸上时，VoiceOver 上下轻扫 = 上一张 / 下一张（方向枚举 AccessibilityAdjustmentDirection.increment 已核，externalID s:7SwiftUI32AccessibilityAdjustmentDirectionO9incrementyA2CmF）",
    "ScrollViewReader": "SwiftUI.ScrollViewReader（iOS 14+；externalID s:7SwiftUI16ScrollViewReaderV；abstract: A view that provides programmatic scrolling, by working with a proxy to scroll to known child views.）——它给的是**程序化滚动**那一个入口（无障碍翻页用）",
    "ScrollViewProxy": "SwiftUI.ScrollViewProxy（iOS 14+；externalID s:7SwiftUI15ScrollViewProxyV；abstract: A proxy value that supports programmatic scrolling of the scrollable views within a view hierarchy.）",
    "scrollTo": "ScrollViewProxy.scrollTo(_:anchor:)（iOS 14+；decl: func scrollTo<ID>(_ id: ID, anchor: UnitPoint?)，ID : Hashable；externalID s:7SwiftUI15ScrollViewProxyV8scrollTo_6anchoryx_AA9UnitPointVSgtSHRzlF）——无障碍翻页的两个落点都靠它：普通卡 `anchor: .top`（卡顶贴容器顶 = 卡顶停在阅读线），末卡 `.bottom`（末卡底贴容器底 = 我们原来的「停到底」）",
    "scrollIndicators": "View.scrollIndicators(_:axes:)（iOS 16+；decl: func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set) -> some View；externalID s:7SwiftUI4ViewPAAE16scrollIndicators_4axesQrAA25ScrollIndicatorVisibilityV_AA4AxisO3SetVtF）——卡片自己就是内容，系统滚动条在这一层是多余的 chrome",
    "onScrollGeometryChange": "View.onScrollGeometryChange(for:of:action:)（iOS 18+；decl: nonisolated func onScrollGeometryChange<T>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T, action: @escaping (T, T) -> Void) -> some View，T : Equatable；externalID s:7SwiftUI4ViewPAAE22onScrollGeometryChange3for2of6actionQrqd__m_qd__AA0eF0Vcyqd___qd__tctSQRd__lF）——形变（透明度 / 缩放）的唯一输入：`contentOffset.y`。它取代了上一版那个自管 `scroll` 状态",
    "GeometryProxy": "SwiftUI.GeometryProxy（iOS 13+；externalID s:7SwiftUI13GeometryProxyV；doc://com.apple.SwiftUI/documentation/SwiftUI/GeometryProxy）——拿到容器尺寸的那个结构体。**注意它与 MapCompass 一起被登记，但两者缘由不同**：GeometryProxy 一直都在用（`pageLayer(_ geo:)`），而 scan.py 的「未声明的类型」判据是拿**冻结提交的缓存**比 —— 基线里那一个只出现在 `members` / `calls` 里、没进 `refs`，于是本机跑（有 scan/baseline/ 目录）与 CI 跑（用提交进仓库的 baseline_cache.json）结果不一样。这一条就是把「到底认不认它」写成一个显式名字，两种跑法都对得上",
    "MapCompass": "MapKit.MapCompass（iOS 17+；decl: struct MapCompass；externalID s:15_MapKit_SwiftUI0A7CompassV；doc://com.apple.mapkit/documentation/MapKit/MapCompass，relatedModules: SwiftUI，abstract: A view that reflects the current orientation of the associated map；init(scope:) 已核：externalID s:15_MapKit_SwiftUI0A7CompassV5scopeAC0cD09NamespaceV2IDVSg_tcfc）——原型 `.compass`（右上角那枚罗盘）的真机对应物：它是地图自己的仪器（回答「哪边是北」）。**2026-09-25 第十一轮起当独立视图挂在 `MapQuickButtons` 那一列的第一格**（`MapCompass(scope: mapScope)` + 容器上的 `.mapScope(_:)`），不再放进 `.mapControls { }`（那条路的位置由 MapKit 定，会贴在状态栏里）",
    "toolbar": "View.toolbar(_:for:)（iOS 16+；decl: func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View；externalID s:7SwiftUI4ViewPAAE7toolbar_3forQrAA10VisibilityO_AA16ToolbarPlacementVdtF；doc://com.apple.SwiftUI/documentation/SwiftUI/View/toolbar(_:for:)）——按可见性控制某一条栏。首页用它把导航栏收掉（`.toolbar(.hidden, for: .navigationBar)`）：原型里**首页根本没有顶栏**，地图一直画到屏幕最上沿。⚠️ 这个名字在 **iOS 27.2 起被改名为 `toolbarVisibility(_:for:)`**（文档 JSON 里 `renamed: toolbarVisibility(_:for:)`、`deprecatedAt: 27.2`）—— 本项目的部署目标是 iOS 26.0、用 iPhoneOS26.5 SDK 编译，所以现在不产生弃用警告；等 SDK 升到 27.2 之后要改用它",
    "URLSession": "Foundation.URLSession（iOS 8+；externalID c:objc(cs)URLSession；doc://com.apple.foundation/documentation/foundation/urlsession）——取在线壁纸图的唯一网络入口（`shared.data(from:)`）",
    "UIImage": "UIKit.UIImage（iOS 2+；externalID c:objc(cs)UIImage；doc://com.apple.uikit/documentation/UIKit/UIImage）——壁纸图本体（`UIImage(data:)` 构造、`Image(uiImage:)` 上屏）",
    "PhotosPicker": "PhotosUI.PhotosPicker（iOS 16+；decl: struct PhotosPicker<Selection, InvalidSelectionError, PhotosItem>；externalID doc://com.apple.photosui/documentation/PhotosUI/PhotosPicker）——系统相册选择器（本地取，不依赖网络）",
    "PhotosPickerItem": "PhotosUI.PhotosPickerItem（iOS 16+；externalID doc://com.apple.photosui/documentation/PhotosUI/PhotosPickerItem）——相册选中的那一项（异步加载成 Data）",
    "loadTransferable": "PhotosPickerItem.loadTransferable(type:)（iOS 16+；decl: func loadTransferable<T>(type: T.Type) async throws -> T?，T: Transferable；externalID doc://com.apple.photosui/documentation/PhotosUI/PhotosPickerItem/loadTransferable(type:)）——把选中的相册项异步读成 Data",
    "preferredFont": "UIFont.preferredFont(forTextStyle:)（iOS 7+；externalID c:objc(cs)UIFont(cm)preferredFontForTextStyle:；doc://com.apple.uikit/documentation/UIKit/UIFont/preferredFont(forTextStyle:)；abstract: Returns an instance of the system font for the specified text style with scaling for the user selected content size category）——行高的唯一来源：**当前动态字号下**这一档一行有多高",
    "monospacedSystemFont": "UIFont.monospacedSystemFont(ofSize:weight:)（iOS 13+；externalID c:objc(cs)UIFont(cm)monospacedSystemFontOfSize:weight:；abstract: Returns the fixed-width font for standard interface text in the specified size）——导出预览那块等宽正文的字体（字号仍取自 caption 的真实点数，不另写一个）",
    "boundingRect": "NSString.boundingRect(with:options:attributes:context:)（iOS 7+；doc://com.apple.foundation/documentation/Foundation/NSString/boundingRect(with:options:attributes:context:)；abstract: Calculates and returns the bounding rect for the receiver drawn using the given options and display characteristics, within the specified rectangle in the current graphics context）——折行数与不折行宽度的量法（用它，而不是「字数 ÷ 每行字数」）",
    "lineHeight": "UIFont.lineHeight（iOS 2+；doc://com.apple.uikit/documentation/UIKit/UIFont/lineHeight）——一行的真实高度（含行距）；系统字号一变它跟着变",
    "CGSize": "CoreGraphics.CGSize（iOS 2+；doc://com.apple.corefoundation/documentation/corefoundation/cgsize）——量文字用的「给定宽度」与卡片视口（宽 × 高）",
    "environment": "View.environment(_:_:)（iOS 13+；doc://com.apple.SwiftUI/documentation/SwiftUI/View/environment(_:_:)）——`ArcStack` 把**量到的**卡片视口写进环境，供 `CardFit` 做裁决（读不到就是 .zero = 不知道）",
    "EnvironmentKey": "SwiftUI.EnvironmentKey 协议（iOS 13+；decl: protocol EnvironmentKey；doc://com.apple.SwiftUI/documentation/SwiftUI/EnvironmentKey）——卡片视口那个环境值的键（`defaultValue` 是 `.zero`，即「没量到」）",
    "MapReader": "MapKit.MapReader（iOS 17+；decl: struct MapReader；externalID s:15_MapKit_SwiftUI0A6ReaderV；doc://com.apple.mapkit/documentation/MapKit/MapReader；abstract: A container view that defines its contents as a function of information about the first contained map）——拿到 `MapProxy`（**已无读者**，见上）",
    "MapProxy": "MapKit.MapProxy（iOS 17+；decl: struct MapProxy；externalID s:15_MapKit_SwiftUI0A5ProxyV；doc://com.apple.mapkit/documentation/MapKit/MapProxy）——屏幕坐标 ↔ 地图坐标的那个转换器（**已无读者**）",
    "convert": "MapProxy.convert(_:from:)（iOS 17+；decl: func convert(_ point: CGPoint, from: some CoordinateSpaceProtocol) -> CLLocationCoordinate2D?；externalID s:15_MapKit_SwiftUI0A5ProxyV7convert_4fromSo22CLLocationCoordinate2DVSgSo7CGPointV_xt0cD023CoordinateSpaceProtocolRzlF；doc://com.apple.mapkit/documentation/MapKit/MapProxy/convert(_:from:)；abstract: Converts a point in the specified coordinate space to a map coordinate）——**已无读者**（它曾是自己那把比例尺唯一的测距手段）",
    "RealityView": "RealityKit.RealityView（iOS 18+；externalID s:19_RealityKit_SwiftUI0A4ViewV；decl: @MainActor @preconcurrency struct RealityView<Content> where Content: View；init(make:update:) 的 make 是 `@MainActor @Sendable (inout RealityViewCameraContent) async -> Void`）——三维车的宿主视图",
    "Entity": "RealityKit.Entity（iOS 13+；externalID s:17RealityFoundation6EntityC；decl: @MainActor @preconcurrency class Entity）——车是一台 Entity 树，转的是根节点",
    "addChild": "HasHierarchy.addChild(_:preservingWorldTransform:)，Entity 符合它（iOS 13+；decl: func addChild(_ entity: Entity, preservingWorldTransform: Bool = false)）——装配时挂子节点",
    "ModelEntity": "RealityKit.ModelEntity（iOS 13+；externalID s:17RealityFoundation11ModelEntityC）——带网格与材质的实体（车身 / 座舱 / 门 / 轮 / 灯）",
    "generateBox": "MeshResource.generateBox(width:height:depth:cornerRadius:splitFaces:)（iOS 13+；externalID s:17RealityFoundation12MeshResourceC11generateBox5width6height5depth12cornerRadius10splitFacesSbSSgtFZ；cornerRadius 与 splitFaces 都有默认值，所以只传前四个参数就成立）——车身与那些薄板都是它",
    "generateCylinder": "MeshResource.generateCylinder(height:radius:)（iOS 18+；externalID s:17RealityFoundation12MeshResourceC16generateCylinder6height6radiusACSf_SftFZ；decl: static func generateCylinder(height: Float, radius: Float) -> MeshResource）——四个轮子",
    "ShapeResource": "RealityKit.ShapeResource（iOS 13+；decl: @MainActor @preconcurrency class ShapeResource，类型页 externalID 同族）——碰撞体的形状",
    "CollisionComponent": "RealityKit.CollisionComponent（iOS 13+；decl: init(shapes: [ShapeResource], mode: CollisionComponent.Mode = .default, filter: CollisionFilter = .default)）——「点得到」的前提之一",
    "InputTargetComponent": "RealityKit.InputTargetComponent（iOS 18+；decl: init(allowedInputTypes: InputTargetComponent.InputType = .all)）——「点得到」的前提之二（这一仓只写它有的那条路）",
    "SimpleMaterial": "RealityKit.SimpleMaterial（iOS 13+；init(color:roughness:isMetallic:) 的 **iOS** 那页 externalID 是 s:17RealityFoundation14SimpleMaterialV0A3KitE5color9roughness10isMetallicACSo7UIColorC_AA0D15ScalarParameterOSbtcfc；注意 color 是 UIColor、roughness 是 MaterialScalarParameter）——车身那几个材质",
    "MaterialScalarParameter": "RealityKit.MaterialScalarParameter（iOS 13+；enum，`ExpressibleByFloatLiteral` + `ExpressibleByIntegerLiteral`：init(floatLiteral:) / init(integerLiteral:) / case float(_:) / case texture(_:)）——**roughness 的类型**；只吃字面量，传 Float 变量编译不过",
    "TapGesture": "SwiftUI.TapGesture（iOS 13+；externalID s:7SwiftUI10TapGestureV）——配 targetedToAnyEntity() 用来点车身上的部位",
    "targetedToAnyEntity": "Gesture.targetedToAnyEntity()（iOS 18+；decl: @MainActor @preconcurrency func targetedToAnyEntity() -> some Gesture<EntityTargetValue<Self.Value>>；s:7SwiftUI6Gester... 这一支由 RealityKit SwiftUI 提供）——被点中的实体直接交回来（它的 `name` 就是 `CarPart` 的 rawValue）",
    "CLLocationAccuracy": "CoreLocation.CLLocationAccuracy（iOS 2+；externalID c:@T@CLLocationAccuracy；decl: typealias CLLocationAccuracy = Double）——手机定位请求「精确定位」时的精度值",
    "Float": "Swift 标准库 Float（32 位）。本仓此前只用过 CGFloat / Double —— 而 `Entity.position` / `Entity.scale` / `simd_quatf` 的角度都是 Float，所以三维车那一批坐标与角度都写成它",
    "contentMargins": "View.contentMargins(_:_:for:)（iOS 17+；externalID s:7SwiftUI4ViewPAAE14contentMargins__3forQrAA4EdgeO3SetV_AA0G6InsetsVAA22ContentMarginPlacementVtF）——`ArcStack` 给滚动内容让出顶部内衬（第一张卡静止时让开状态栏、滑动时从时钟下连续穿过）",
    "scrollEdgeEffectStyle": "View.scrollEdgeEffectStyle(_:for:)（iOS 26+；externalID s:7SwiftUI4ViewPAAE21scrollEdgeEffectStyle_3forQrAA06ScrollefG0VSg_AA0E0O3SetVtF；decl: func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View）——iOS 26 系统给滚动边缘的那层柔化延伸（`.soft` 就是系统默认的那一档）",
    "withObservationTracking": "Observation.withObservationTracking(_:onChange:)（iOS 17+；decl: func withObservationTracking<T>(_ apply: () -> T, onChange: @autoclosure () -> () -> Void) -> T；externalID s:11Observation04withA8Tracking_8onChangexxyXE_yyYbcyXKtlF）——`KeepAwake` 用它盯 `AppStore.isCarMoving`（回调在**写入之前**触发，所以落状态推到下一个主线程回合）",
    "isIdleTimerDisabled": "UIApplication.isIdleTimerDisabled（UIKit；decl: var isIdleTimerDisabled: Bool；externalID c:objc(cs)UIApplication(py)idleTimerDisabled）——车在动时的屏幕常亮（`KeepAwake`）",
    "PreferenceKey": "SwiftUI.PreferenceKey（iOS 13+；decl: protocol PreferenceKey；externalID s:7SwiftUI13PreferenceKeyP）——视图往上申报的一个具名值（这里报的是抽屉的上沿）",
    "Anchor": "SwiftUI.Anchor<Value>（iOS 13+；decl: struct Anchor<Value>；externalID s:7SwiftUI6AnchorV）——「某一层的某段几何」的不透明引用：写给偏好值，读到的人用自己的坐标空间解它",
    "anchorPreference": "View.anchorPreference(key:value:transform:)（iOS 13+；decl: func anchorPreference<A, K>(key: K.Type, value: Anchor<A>.Source, transform: (Anchor<A>) -> K.Value) -> some View，K : PreferenceKey；externalID s:7SwiftUI4ViewPAAE16anchorPreference3key5value9transformQrqd_0_m_AA6AnchorV6SourceVyqd___G5ValueQyd_0_AIyqd__GctAA0E3PreferenceKeyRd_0_r0_lF）——抽屉把自己的上沿报出去",
    "overlayPreferenceValue": "View.overlayPreferenceValue(_:alignment:_:)（iOS 13+；decl: func overlayPreferenceValue<K, V>(_ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View，K : PreferenceKey，V : View；externalID s:7SwiftUI4ViewPAAE22overlayPreferenceValue_9alignment_Qrqd__m_AA9AlignmentVqd_0_0F0Qyd__ctAA0E3KeyRd__AaBRd_0_r0_lF）——地图右侧那一列据此贴着抽屉上沿（抽屉拉开时跟着上移）",
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
    return {
        "结构性问题": len(problems),
        "未声明的类型": len(unk_types),
        "未声明的构造/函数": len(unk_calls),
        "未声明的方法": len(unk_methods),
        "未知成员": len(bad),
    }


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
