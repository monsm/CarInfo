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
# `Self.x`：`MEMBER_REF` 会把 `Self` 当成一个类型名（它确实长得像类型），而下面「项目类型的
# 未知成员」那条判据遇上不在类型表里的名字就 `continue` —— 于是**所有 `Self.` 引用都在盲区里**。
# 2026-09-25 的 CI 就是这么红的：`MapSpineView` 里两处 `Self.barSeam`，而声明那一行在同一次
# 编辑里丢了（注释还在、值不在），四个检查器全绿。
# 这里把 `Self.x` 归到「本文件里最内层的那个类型声明」上，于是它与 `Type.x` 走同一条判据。
SELF_MEMBER_REF = re.compile(r"(?<![A-Za-z0-9_.])Self\.([a-z_][A-Za-z0-9_]*)")


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


# 泛型参数的**声明**：`struct DSGlassSurface<S: Shape>` / `func dsGlass<S: Shape>(…)`。
#
# 为什么需要它（2026-09-25 的真实误报）：`TYPE_REF` 认的是「前面跟着 `:` `->` `[` `<`
# `as!` `is` `&` 的大写开头名字」，而 `<S: Shape>` 里的 `S` 前面正是 `<` —— 于是
# **刚声明的泛型参数**被当成了「用了但没声明的类型」，报成高嫌疑（＝编译会挂），
# 而它其实就在眼前那一行。判据错在「只认 struct/enum 那种声明」，不认泛型形参。
#
# 收窄：只取 `<…>` 里逗号分隔的、**裸大写名字**（`S` / `Content` / `Value`），
# 带约束的取 `:` 前那一段。泛型子句里有嵌套尖括号（`<T: Collection>` 之外还有
# `P<A>`）时整体不匹配 —— 那种写法本仓一次都没有，宁可不认也不误认。
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
        # `Self.x` → `<本文件里最内层的类型>.x`（理由见 SELF_MEMBER_REF 上面那段）
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


# 基线之后才引入、但已逐条对着 Apple 文档核实过确实存在的 SDK 名字。
# 基线白名单是从「最后一次能编译的提交」反推的，所以新引入的 SDK 名字
# （例如 iOS 18 的 Tab）必然不在里面 —— 在这里显式登记，登记前必须核实。
VERIFIED_SDK_ADDITIONS = {
    # 手机自己的位置（`Services/PhoneLocation.swift`，2026-09-25）。
    # 四个名字都在写进代码前核过 Apple 文档 JSON：
    #   · CLLocationManager                  c:objc(cs)CLLocationManager，iOS 2.0+
    #     「The object you use to start and stop the delivery of location-related
    #      events to your app.」
    #   · requestWhenInUseAuthorization()    c:objc(cs)CLLocationManager(im)requestWhenInUseAuthorization
    #     「Requests the user’s permission to use location services while the app
    #      is in use.」
    #   · startUpdatingLocation()            c:objc(cs)CLLocationManager(im)startUpdatingLocation
    #     「Starts the generation of updates that report the user’s current location.」
    #   · stopUpdatingLocation()             c:objc(cs)CLLocationManager(im)stopUpdatingLocation
    #     「Stops the generation of location updates.」
    "CLLocationManager": "CoreLocation.CLLocationManager（iOS 2.0+；externalID c:objc(cs)CLLocationManager）—— 手机自己的位置，按需取一次",
    "requestWhenInUseAuthorization": "CLLocationManager.requestWhenInUseAuthorization()（iOS 8+；externalID c:objc(cs)CLLocationManager(im)requestWhenInUseAuthorization）",
    "startUpdatingLocation": "CLLocationManager.startUpdatingLocation()（iOS 2.0+；externalID c:objc(cs)CLLocationManager(im)startUpdatingLocation）",
    "stopUpdatingLocation": "CLLocationManager.stopUpdatingLocation()（iOS 2.0+；externalID c:objc(cs)CLLocationManager(im)stopUpdatingLocation）—— 取到就停",
    "Tab": "SwiftUI.Tab（iOS 18+/watchOS 11+，init(value:content:label:) 已核对 interface）",
    "AnyView": "SwiftUI.AnyView（iOS 13+）",
    # 「降低透明度」那一档（Design/DSGlass.swift，2026-09-26 第二十轮）。
    # 登记前核过 Apple 文档页 uikit/uiaccessibility/isreducetransparencyenabled
    # （title + abstract：「A Boolean value that indicates whether the Reduce
    # Transparency setting is in an enabled state.」）。
    # 为什么不用 SwiftUI 那个 `@Environment(\.accessibilityReduceTransparency)`：
    # 它只能在 `View` / `ViewModifier` 里读，而「为读它而加一个泛型 `View`」已经
    # 让 App 在真机上崩过一次（栈溢出，见 `DSGlass.swift` 文件头上那段）。
    "UIAccessibility": "UIKit.UIAccessibility（iOS 2.0+）—— 「降低透明度」这一档的唯一读者",
    "isReduceTransparencyEnabled": "UIAccessibility.isReduceTransparencyEnabled（UIKit；doc://com.apple.uikit/documentation/UIKit/UIAccessibility/isreducetransparencyenabled；abstract: A Boolean value that indicates whether the Reduce Transparency setting is in an enabled state.）",
    "UnitPoint": "SwiftUI.UnitPoint（iOS 13+）",
    "blendMode": "View.blendMode(_:)（iOS 13+）",
    "repeatForever": "Animation.repeatForever(autoreverses:)（iOS 13+）",
    # 艺术主题（ArtTheme）那一轮登记的四个。2026-09-25 主题只剩原生、ArtTheme.swift
    # 已删，但四个名字**都有别的读者**，所以登记一个都不能撤：
    #   preferredColorScheme / allowsHitTesting —— 还在用（App 根部的明暗、禁点）
    #   ColorScheme —— NightModeManager.schemeOverride 的返回类型
    #   RadialGradient —— GlassCard 的强调色痕、MapCarPin 的车钉光晕
    # 登记前已核 Apple 文档 JSON：
    "preferredColorScheme": "View.preferredColorScheme(ColorScheme?)（iOS 13+；swiftui/view/preferredcolorscheme(_:)）",
    "allowsHitTesting": "View.allowsHitTesting(Bool)（iOS 13+；swiftui/view/allowshittesting(_:)）",
    "ColorScheme": "SwiftUI.ColorScheme（iOS 13+；主题自带明暗用它表达 light/dark）",
    "RadialGradient": "SwiftUI.RadialGradient(colors:center:startRadius:endRadius:)（iOS 13+；已核文档 JSON）",
    # 光层与衬线排版。**注意这两个名字原来指向谁**：`UIFont` / `custom` 是
    # `TokensSerif`（衬线标题）探中文衬线时用的，`Ellipse` 是车钉脚下的接地阴影。
    # `Design/SkyOverlay.swift`（五个装饰图层）与 `TokensSerif` 都已于 2026-09-25 删除，
    # 但另有两个**活着的**读者让这些登记不能撤：`UIFont` 还给 `CardFit` 量行高，
    # `Ellipse` 还在 `MapCarPin` 里。登记前逐个核过 Apple 文档 JSON：
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
    "InsettableShape": "SwiftUI.InsettableShape protocol（iOS 13+；externalID s:7SwiftUI15InsettableShapeP；"
                       "abstract「A shape type that is able to inset itself to produce another shape.」）"
                       "—— `dsGlass` 的形状约束：那圈发丝线用的是 strokeBorder，它只在这个协议上（2026-09-25）",
    # Liquid Glass（iOS 26+）。三个名字在写进 `Design/DSGlass.swift` 之前逐个核过
    # Apple 文档 JSON（abstract / identifier.url / metadata.externalID / platforms）：
    #   · Glass                  s:7SwiftUI5GlassV        「A structure that defines the
    #                             configuration of the Liquid Glass material.」iOS 26.0+
    #   · GlassEffectContainer   s:7SwiftUI20GlassEffectContainerV  「A view that combines
    #                             multiple Liquid Glass shapes into a single shape that can
    #                             morph individual shapes into one another.」
    #   · glassEffect(_:in:)     View 的扩展，externalID
    #                             s:7SwiftUI4ViewPAAE11glassEffect_2inQrAA5GlassV_qd__tAA5ShapeRd__lF
    #                             「Applies the Liquid Glass effect to a view.」
    # `Glass` 与 `GlassEffectContainer` 只会出现在 `Design/DSGlass.swift` 里 ——
    # 这一条由 `scan/glass.py` 守着（别处直连就是又开了第二个入口）。
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
    # 热区 / 回放 / 充电曲线（本轮）：全部写进代码前对着 Apple 文档 JSON 核过
    "MapCircle": "MapKit.MapCircle struct（iOS 17+；init(center:radius:) 已核，stroke(_:style:)/foregroundStyle 见 Styling-the-circle）",
    "Canvas": "SwiftUI.Canvas（iOS 15+；init(closure:(inout GraphicsContext, CGSize) -> Void)）",
    "GraphicsContext": "SwiftUI.GraphicsContext（iOS 15+；stroke(_:with:style:)/fill(_:with:)/draw(_:at:) 已核）",
    "Path": "SwiftUI.Path（iOS 13+；move/addLine/closeSubpath）",
    "presentationDetents": "View.presentationDetents(_:)（iOS 16+；sheet 高度档）",
    # 「其余读数」由卡里那道自画抽屉换成系统 sheet（2026-09-25）。三个名字都对着
    # Apple 文档 JSON 核过才写进代码：
    "presentationBackgroundInteraction": "View.presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction)（iOS 16.4+；externalID s:7SwiftUI4ViewPAAE33presentationBackgroundInteractionyQrAA012PresentationeF0VF）—— 半屏时底下那张地图仍然可以拖，Apple 地图就是这个行为；上一版自画的抽屉从头到尾盖住地图",
    "presentationDragIndicator": "View.presentationDragIndicator(_ visibility: Visibility)（iOS 16.0+；externalID s:7SwiftUI4ViewPAAE25presentationDragIndicatoryQrAA10VisibilityOF）—— 系统那枚拉手（尺寸/对比度/热区由系统给，不再自己画 Capsule）",
    "PresentationBackgroundInteraction": "SwiftUI.PresentationBackgroundInteraction（iOS 16.4+；静态方法 enabled(upThrough: PresentationDetent) -> Self，externalID s:7SwiftUI33PresentationBackgroundInteractionV7enabled9upThroughAcA0C6DetentV_tFZ）",
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
    "interpolatingSpring": "Animation.interpolatingSpring(mass:stiffness:damping:initialVelocity:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/Animation/interpolatingSpring(mass:stiffness:damping:initialVelocity:)）——2026-09-25 起它只服务无障碍翻页那一步（`ArcStack.step`）：手势与惯性都归系统 `ScrollView` 了。选它而不是 easeOutBack：过冲是同一件事，但弹簧能被下一次手势接管，缓动不能",
    "rotation3DEffect": "View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/rotation3DEffect(_:axis:anchor:anchorZ:perspective:)）——卡片离开阅读线时向后转出去，滚轮叠法靠它绕圆柱面",
    "zIndex": "View.zIndex(_:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/zIndex(_:)）——把压在阅读线上的那张抬到最上层；重合叠放不加它会出现「近的那张被远的盖住」",
    "clipped": "View.clipped(antialiased:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/clipped(antialiased:)）——叠叠乐是一个固定窗口，带外的卡必须先裁掉再谈渐隐",
    "highPriorityGesture": "View.highPriorityGesture(_:including:)（iOS 13+；externalID doc://com.apple.SwiftUI/documentation/SwiftUI/View/highPriorityGesture(_:including:)）——模式条要「按下就展开」，所以整条的拖动优先于标签自己的点选（点选由同一条手势里判断位移来做，见 DSSwipeStrip）",
    "textCase": "View.textCase(_:)（iOS 13+；decl: func textCase(_ textCase: Text.Case?) -> some View）——卡片小标题走 iOS 分组头的大写形态",
    # ⚠️ 这一条以前是**一条错的**：上一版白名单里写着「`.scrollUp` / `.scrollDown` 为
    # AccessibilityActionKind 的静态成员」，于是 ArcStack 照这个写，门禁全绿、
    # CI 报 `type 'AccessibilityActionKind' has no member 'scrollUp'`。
    # 教训不是「打错了一个名字」，而是：**白名单里的一句话也是断言**，
    # 而当时的 scan.py 只检查「名字在不在白名单」，从不检查白名单里的说法对不对。
    # 两个真实成员已对着 Apple 文档 JSON 核过（accessibilityactionkind 一页的
    # topicSections 列出：default / delete / escape / magicTap / showMenu）。
    #
    # 2026-09-25：`accessibilityAction` 与 `accessibilityScrollAction` 两条**已从
    # 白名单删除** —— 不再有任何一行代码用它们，而白名单里留着不用的名字就是另一种
    # 「清单失真」。前者本来只挂命名动作（翻页从来不用它）；后者是叠叠乐没有
    # `ScrollView` 时的**替身**，而那一叠现在就是系统的 `ScrollView`（三指滚动是它自带
    # 的）—— 替身没有了存在理由，随它一起删。
    "accessibilityAdjustableAction": "View.accessibilityAdjustableAction(_:)（iOS 13+；decl: func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier>；externalID s:7SwiftUI4ViewPAAE29accessibilityAdjustableActionyAA15ModifiedContentVyxAA31AccessibilityAttachmentModifierVGyAA0I19AdjustmentDirectionOcF）——叠叠乐翻页的**元素级**手势：焦点落在这叠纸上时，VoiceOver 上下轻扫 = 上一张 / 下一张（方向枚举 AccessibilityAdjustmentDirection.increment 已核，externalID s:7SwiftUI32AccessibilityAdjustmentDirectionO9incrementyA2CmF）",
    # 叠叠乐改回系统滚动（2026-09-25，用户第 1 条：「除了地图外其他的界面怎么滑动起来
    # 都很不 iOS？iOS 的原生流畅呢」）。上一版是自管手势 + 自管弹簧，代价写在 `ArcStack`
    # 头注里（没有三指滚动、没有惯性、两端硬停）；换回 `ScrollView` 之后那几条一起消失。
    # 五个名字都在写进代码前对着 Apple 文档 JSON 核过（abstract / identifier.url /
    # metadata.externalID / platforms 四项都看过）：
    "ScrollViewReader": "SwiftUI.ScrollViewReader（iOS 14+；externalID s:7SwiftUI16ScrollViewReaderV；abstract: A view that provides programmatic scrolling, by working with a proxy to scroll to known child views.）——它给的是**程序化滚动**那一个入口（无障碍翻页用）",
    "ScrollViewProxy": "SwiftUI.ScrollViewProxy（iOS 14+；externalID s:7SwiftUI15ScrollViewProxyV；abstract: A proxy value that supports programmatic scrolling of the scrollable views within a view hierarchy.）",
    "scrollTo": "ScrollViewProxy.scrollTo(_:anchor:)（iOS 14+；decl: func scrollTo<ID>(_ id: ID, anchor: UnitPoint?)，ID : Hashable；externalID s:7SwiftUI15ScrollViewProxyV8scrollTo_6anchoryx_AA9UnitPointVSgtSHRzlF）——无障碍翻页的两个落点都靠它：普通卡 `anchor: .top`（卡顶贴容器顶 = 卡顶停在阅读线），末卡 `.bottom`（末卡底贴容器底 = 我们原来的「停到底」）",
    "scrollIndicators": "View.scrollIndicators(_:axes:)（iOS 16+；decl: func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set) -> some View；externalID s:7SwiftUI4ViewPAAE16scrollIndicators_4axesQrAA25ScrollIndicatorVisibilityV_AA4AxisO3SetVtF）——卡片自己就是内容，系统滚动条在这一层是多余的 chrome",
    "onScrollGeometryChange": "View.onScrollGeometryChange(for:of:action:)（iOS 18+；decl: nonisolated func onScrollGeometryChange<T>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T, action: @escaping (T, T) -> Void) -> some View，T : Equatable；externalID s:7SwiftUI4ViewPAAE22onScrollGeometryChange3for2of6actionQrqd__m_qd__AA0eF0Vcyqd___qd__tctSQRd__lF）——形变（透明度 / 缩放）的唯一输入：`contentOffset.y`。它取代了上一版那个自管 `scroll` 状态",
    # 首页重排（2026-09-23，按原型 stack.html）新增的三个 SDK 名字。
    # 三个都对着 Apple 文档 JSON 核过 decl / 平台 / externalID。
    "GeometryProxy": "SwiftUI.GeometryProxy（iOS 13+；externalID s:7SwiftUI13GeometryProxyV；doc://com.apple.SwiftUI/documentation/SwiftUI/GeometryProxy）——拿到容器尺寸的那个结构体。**注意它与 MapCompass 一起被登记，但两者缘由不同**：GeometryProxy 一直都在用（`pageLayer(_ geo:)`），而 scan.py 的「未声明的类型」判据是拿**冻结提交的缓存**比 —— 基线里那一个只出现在 `members` / `calls` 里、没进 `refs`，于是本机跑（有 scan/baseline/ 目录）与 CI 跑（用提交进仓库的 baseline_cache.json）结果不一样。这一条就是把「到底认不认它」写成一个显式名字，两种跑法都对得上",
    "MapCompass": "MapKit.MapCompass（iOS 17+；decl: struct MapCompass；externalID s:15_MapKit_SwiftUI0A7CompassV；doc://com.apple.mapkit/documentation/MapKit/MapCompass，relatedModules: SwiftUI，abstract: A view that reflects the current orientation of the associated map；init(scope:) 已核：externalID s:15_MapKit_SwiftUI0A7CompassV5scopeAC0cD09NamespaceV2IDVSg_tcfc）——原型 `.compass`（右上角那枚罗盘）的真机对应物：它是地图自己的仪器（回答「哪边是北」）。**2026-09-25 第十一轮起当独立视图挂在 `MapQuickButtons` 那一列的第一格**（`MapCompass(scope: mapScope)` + 容器上的 `.mapScope(_:)`），不再放进 `.mapControls { }`（那条路的位置由 MapKit 定，会贴在状态栏里）",
    "toolbar": "View.toolbar(_:for:)（iOS 16+；decl: func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View；externalID s:7SwiftUI4ViewPAAE7toolbar_3forQrAA10VisibilityO_AA16ToolbarPlacementVdtF；doc://com.apple.SwiftUI/documentation/SwiftUI/View/toolbar(_:for:)）——按可见性控制某一条栏。首页用它把导航栏收掉（`.toolbar(.hidden, for: .navigationBar)`）：原型里**首页根本没有顶栏**，地图一直画到屏幕最上沿。⚠️ 这个名字在 **iOS 27.2 起被改名为 `toolbarVisibility(_:for:)`**（文档 JSON 里 `renamed: toolbarVisibility(_:for:)`、`deprecatedAt: 27.2`）—— 本项目的部署目标是 iOS 26.0、用 iPhoneOS26.5 SDK 编译，所以现在不产生弃用警告；等 SDK 升到 27.2 之后要改用它",
    # 启动轨迹的心跳（Services/StartupJournal.swift，2026-09-24 第二轮）。
    # 背景：轨迹原本在 2–12 秒之间是瞎的（打点全在头一两秒），而用户报的
    # 「地图出来以后几秒就退」正落在盲区里。补心跳时选了 GCD 的定时器，
    # 而不用 `Timer.scheduledTimer`：后者跑在调用它的 run loop 上，
    # 主线程一卡它自己也停了 —— 于是「卡死」与「被处决」又分不开了。
    # 三个名字都对着 Apple 文档核过（dispatchsourcetimer 一页列出
    # `schedule(deadline:repeating:leeway:)`，makeTimerSource(queue:) 返回它）：
    "DispatchSourceTimer": "Dispatch.DispatchSourceTimer（iOS 8+；doc://com.apple.dispatch/documentation/Dispatch/DispatchSourceTimer；由 DispatchSource.makeTimerSource(queue:) 返回）",
    "makeTimerSource": "DispatchSource.makeTimerSource(queue:)（iOS 8+；doc://com.apple.dispatch/documentation/Dispatch/DispatchSource/makeTimerSource(queue:flags:)）",
    "schedule": "DispatchSourceTimer.schedule(deadline:repeating:leeway:)（iOS 8+；doc://com.apple.dispatch/documentation/Dispatch/DispatchSourceTimer/schedule(deadline:repeating:leeway:)）——心跳的 1 秒节拍",
    # 启动轨迹的判据（Services/StartupJournal.swift，2026-09-24 第三轮）。
    # 背景：轨迹原本只记**常驻内存**（320 MB），而那个数单独看没有判据 ——
    # 4 GB 与 8 GB 的机器、前台与后台，额度完全不同。用户的反馈是一句猜测：
    # 「没闪退，我感觉是因为内存占用太多被系统杀了」。补的就是那句猜测缺的数。
    # 两个名字都对着 Apple 文档 JSON 核过（`abstract` / `metadata.modules` /
    # `metadata.externalID` / `platforms` 四项都打印出来看过）：
    "os_proc_available_memory": "os 框架（iOS 13+；decl: extern size_t os_proc_available_memory(void)；externalID c:@F@os_proc_available_memory；doc://com.apple.os/documentation/os/os_proc_available_memory；abstract: Determines the amount of memory available to the current app）——系统还可给本进程多少字节。它是「距被处决还剩多远」的**唯一**读数（RSS 单独看回答不了「这算不算高」），也是轨迹里 `距上限 X MB` 那一栏的来源。它返回 0 时按「没测到」处理（写成 `—`），不能当成「一兆不剩」",
    "didReceiveMemoryWarningNotification": "UIApplication.didReceiveMemoryWarningNotification（UIKit；externalID c:@UIApplicationDidReceiveMemoryWarningNotification；doc://com.apple.uikit/documentation/UIKit/UIApplication/didReceiveMemoryWarningNotification；abstract: A notification that posts when the app receives a warning from the operating system about low memory availability）——被内存处决之前通常会先响这一声；有与没有指向的不是同一件事，所以它随轨迹一起出去（`内存警告 N 次`）",
    # 壁纸（Services/WallpaperService.swift，2026-09-24 第六轮：子页面背景）。
    # 背景：iOS 没有读取主屏壁纸的公开 API（壁纸归 SpringBoard 进程管，App 拿不到），
    # 能做到的最接近「当前桌面的背景」的一版是：铺一张在线风景图（Unsplash 官方直链），
    # 用户可以在「我的 → 设置」里换一张 / 不铺。两个 SDK 名对着文档核过：
    "URLSession": "Foundation.URLSession（iOS 8+；externalID c:objc(cs)URLSession；doc://com.apple.foundation/documentation/foundation/urlsession）——取在线壁纸图的唯一网络入口（`shared.data(from:)`）",
    "UIImage": "UIKit.UIImage（iOS 2+；externalID c:objc(cs)UIImage；doc://com.apple.uikit/documentation/UIKit/UIImage）——壁纸图本体（`UIImage(data:)` 构造、`Image(uiImage:)` 上屏）",
    # 壁纸改版（同日，Unsplash 在线图不可靠改为相册本地选）：PhotosUI 三个名字对着文档核过：
    "PhotosPicker": "PhotosUI.PhotosPicker（iOS 16+；decl: struct PhotosPicker<Selection, InvalidSelectionError, PhotosItem>；externalID doc://com.apple.photosui/documentation/PhotosUI/PhotosPicker）——系统相册选择器（本地取，不依赖网络）",
    "PhotosPickerItem": "PhotosUI.PhotosPickerItem（iOS 16+；externalID doc://com.apple.photosui/documentation/PhotosUI/PhotosPickerItem）——相册选中的那一项（异步加载成 Data）",
    "loadTransferable": "PhotosPickerItem.loadTransferable(type:)（iOS 16+；decl: func loadTransferable<T>(type: T.Type) async throws -> T?，T: Transferable；externalID doc://com.apple.photosui/documentation/PhotosUI/PhotosPickerItem/loadTransferable(type:)）——把选中的相册项异步读成 Data",
    # 「展开后有多挤」的度量（Design/CardFit.swift，2026-09-25）。用户原话：
    # 「所有卡片内需要展开的都要严格计算展开后的拥挤程度，完全根据数据来，不能猜」。
    # 于是行高不能是写下来的常量：它必须是**当前动态字号下**那一行真实的高度；
    # 折行数必须是量出来的（「字数 ÷ 每行字数」那种估法，用户把系统字号调大就不成立了）。
    # 前三个当天取过 doc JSON（abstract / identifier.url / metadata.externalID /
    # modules 四项都看过）：
    "preferredFont": "UIFont.preferredFont(forTextStyle:)（iOS 7+；externalID c:objc(cs)UIFont(cm)preferredFontForTextStyle:；doc://com.apple.uikit/documentation/UIKit/UIFont/preferredFont(forTextStyle:)；abstract: Returns an instance of the system font for the specified text style with scaling for the user selected content size category）——行高的唯一来源：**当前动态字号下**这一档一行有多高",
    "monospacedSystemFont": "UIFont.monospacedSystemFont(ofSize:weight:)（iOS 13+；externalID c:objc(cs)UIFont(cm)monospacedSystemFontOfSize:weight:；abstract: Returns the fixed-width font for standard interface text in the specified size）——导出预览那块等宽正文的字体（字号仍取自 caption 的真实点数，不另写一个）",
    "boundingRect": "NSString.boundingRect(with:options:attributes:context:)（iOS 7+；doc://com.apple.foundation/documentation/Foundation/NSString/boundingRect(with:options:attributes:context:)；abstract: Calculates and returns the bounding rect for the receiver drawn using the given options and display characteristics, within the specified rectangle in the current graphics context）——折行数与不折行宽度的量法（用它，而不是「字数 ÷ 每行字数」）",
    # 后三个是 CoreGraphics / SwiftUI 的标准名字（同一天核过存在性与平台，没有单独拉页面）：
    "lineHeight": "UIFont.lineHeight（iOS 2+；doc://com.apple.uikit/documentation/UIKit/UIFont/lineHeight）——一行的真实高度（含行距）；系统字号一变它跟着变",
    "CGSize": "CoreGraphics.CGSize（iOS 2+；doc://com.apple.corefoundation/documentation/corefoundation/cgsize）——量文字用的「给定宽度」与卡片视口（宽 × 高）",
    "environment": "View.environment(_:_:)（iOS 13+；doc://com.apple.SwiftUI/documentation/SwiftUI/View/environment(_:_:)）——`ArcStack` 把**量到的**卡片视口写进环境，供 `CardFit` 做裁决（读不到就是 .zero = 不知道）",
    "EnvironmentKey": "SwiftUI.EnvironmentKey 协议（iOS 13+；decl: protocol EnvironmentKey；doc://com.apple.SwiftUI/documentation/SwiftUI/EnvironmentKey）——卡片视口那个环境值的键（`defaultValue` 是 `.zero`，即「没量到」）",
    # 地图比例尺（Features/Map/MapSpineReadouts.swift，2026-09-25 第三轮）。
    # 用户第 2 条：「地图页的比列缩尺放到灵动岛下面，2 秒后消失」——
    # 下面这三个名字（`MapReader` / `MapProxy` / `convert`）**2026-09-25 第十一轮起没有读者**：
    # 当时是为了「自己量一把比例尺」而登记的（理由是「系统的 `MapScaleView` 位置搬不动」——
    # 那句话第十一轮被推翻：它可以当独立视图挂，位置由我们自己给）。
    # **登记留着不撤**：白名单是按**名字**判的，撤掉 `convert` 这种泛名字会让别处合法的
    # `.convert(` 变成误报；但注释必须写明现状 —— 一张说「它在用」的登记表就是失真。
    # 三个名字当天取过 doc JSON（abstract / identifier.url / metadata.externalID /
    # platforms 四项都看过）：
    "MapReader": "MapKit.MapReader（iOS 17+；decl: struct MapReader；externalID s:15_MapKit_SwiftUI0A6ReaderV；doc://com.apple.mapkit/documentation/MapKit/MapReader；abstract: A container view that defines its contents as a function of information about the first contained map）——拿到 `MapProxy`（**已无读者**，见上）",
    "MapProxy": "MapKit.MapProxy（iOS 17+；decl: struct MapProxy；externalID s:15_MapKit_SwiftUI0A5ProxyV；doc://com.apple.mapkit/documentation/MapKit/MapProxy）——屏幕坐标 ↔ 地图坐标的那个转换器（**已无读者**）",
    # ⚠️ `convert` 这个名字很泛（白名单是按**名字**判的，所以任何 `.convert(` 都会因此通过）。
    # 它现在全仓没有调用点；换到别处去用它要重新对着文档核一遍。
    "convert": "MapProxy.convert(_:from:)（iOS 17+；decl: func convert(_ point: CGPoint, from: some CoordinateSpaceProtocol) -> CLLocationCoordinate2D?；externalID s:15_MapKit_SwiftUI0A5ProxyV7convert_4fromSo22CLLocationCoordinate2DVSgSo7CGPointV_xt0cD023CoordinateSpaceProtocolRzlF；doc://com.apple.mapkit/documentation/MapKit/MapProxy/convert(_:from:)；abstract: Converts a point in the specified coordinate space to a map coordinate）——**已无读者**（它曾是自己那把比例尺唯一的测距手段）",
    # 车控那一屏的三维车（Features/Control/CarModelView.swift，2026-09-25 第 8 条：
    # 「车控的车太丑了，能不能搞个真车或立体车，可以滑动的……也可以点击控车」）。
    # RealityKit 这一批名字在写进代码前逐个取过 Apple 文档 JSON（title / kind /
    # platforms / metadata.externalID / primaryContentSections.declarations 五项）。
    # 核实里**当场改掉了一个真错误**：`SimpleMaterial.init(color:roughness:isMetallic:)`
    # 的 iOS 页写的是 `roughness: MaterialScalarParameter`（不是 Float）—— 而
    # `MaterialScalarParameter` 是 `ExpressibleByFloatLiteral` 的枚举，只吃字面量。
    # 第一版把 roughness 写成 `Float` 参数转发，那会编译不过（值类型之间没有隐式转换）。
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
    # 子页顶部与地图页对齐（用户 2026-09-25 第 2 条）用到的两个 SwiftUI 名字。
    # 两个都取过文档 JSON（platforms / externalID / declarations 都看过）：
    "contentMargins": "View.contentMargins(_:_:for:)（iOS 17+；externalID s:7SwiftUI4ViewPAAE14contentMargins__3forQrAA4EdgeO3SetV_AA0G6InsetsVAA22ContentMarginPlacementVtF）——`ArcStack` 给滚动内容让出顶部内衬（第一张卡静止时让开状态栏、滑动时从时钟下连续穿过）",
    "scrollEdgeEffectStyle": "View.scrollEdgeEffectStyle(_:for:)（iOS 26+；externalID s:7SwiftUI4ViewPAAE21scrollEdgeEffectStyle_3forQrAA06ScrollefG0VSg_AA0E0O3SetVtF；decl: func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View）——iOS 26 系统给滚动边缘的那层柔化延伸（`.soft` 就是系统默认的那一档）",
    #  `onMapCameraChange` 这个名字**已从白名单删除**（2026-09-25，与全局文字外壳同一轮）：
    #  它唯一的两个读者（自画罗盘喂朝向、自己量那把尺子）都在第十一轮删掉了，
    #  现在全仓只剩注释里提到它。白名单里留着一个没人用的名字 = 另一种清单失真
    #（与上面 accessibilityAction / accessibilityScrollAction 两条同一条规矩）。
    #
    # 全局文字外壳（`Design/InkGlow.swift` 的 `DSTextGlow`，用户 2026-09-25 第 2 条）。
    # 两个名字写进代码前都取过 Apple 文档 JSON（abstract / identifier.url / platforms）：
    #   · TextRenderer   doc://com.apple.SwiftUI/documentation/SwiftUI/TextRenderer
    #     「A value that can replace the default text view rendering behavior.」iOS 17.0+
    #    （而 `View.textRenderer(_:)` 那个**修饰符**是 iOS 18.0+，本 App target 是 iOS 26）
    #   · EdgeInsets     doc://com.apple.SwiftUI/documentation/SwiftUI/EdgeInsets
    #     「The inset distances for the sides of a rectangle.」iOS 13.0+
    "TextRenderer": "SwiftUI.TextRenderer 协议（iOS 17+；externalID s:7SwiftUI12TextRendererP；abstract「A value that can replace the default text view rendering behavior.」）——全局文字外壳的唯一挂点（`View.textRenderer(_:)` 是 iOS 18+ 的修饰符，而 `.dsTextGlow()` 就是它）",
    "EdgeInsets": "SwiftUI.EdgeInsets（iOS 13+；externalID s:7SwiftUI10EdgeInsetsV；abstract「The inset distances for the sides of a rectangle.」）——`TextRenderer.displayPadding` 的返回类型（不报给 SwiftUI 的话，外发光会被裁掉）",
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
