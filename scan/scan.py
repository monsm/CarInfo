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

APP = ["CarKeeper", "Design", "Services", "Models", "HealthKit", "Shared"]
WIDGET = ["Widgets", "Shared"]

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
    out = []
    for r in roots:
        p = base / r
        if p.is_dir():
            out += sorted(p.rglob("*.swift"))
        elif p.suffix == ".swift":
            out.append(p)
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
        for m2 in CALL_REF.finditer(cleaned):
            calls[m2.group(1)] = calls.get(m2.group(1), 0) + 1
        for m2 in METHOD_REF.finditer(cleaned):
            methods[m2.group(1)] = methods.get(m2.group(1), 0) + 1
        for m2 in MEMBER_REF.finditer(cleaned):
            memrefs.setdefault(m2.group(1), set()).add(m2.group(2))
    return types, members, funcs, refs, calls, methods, memrefs, problems


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
    "Shape": "SwiftUI.Shape protocol（iOS 13+；本项目用它画车钉的三角形警告形状）",
    "UnevenRoundedRectangle": "SwiftUI.UnevenRoundedRectangle（iOS 16+；底部面板只要上面两角圆角）",
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
    return types


def main():
    app_paths = target_files(APP)
    widget_paths = target_files(WIDGET)

    for label, paths in (("APP", app_paths), ("WIDGET", widget_paths)):
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

    # 基线白名单
    base_paths = sorted(BASELINE.rglob("*.swift"))
    if not base_paths:
        print("\n!! 基线缺失，先运行 extract_baseline.sh")
        return
    bt, bm, bf, bref, bcalls, bmethods, _, bprob = analyze(base_paths)
    sdk_types = bt | bref | set(bcalls) | set(VERIFIED_SDK_ADDITIONS)
    sdk_calls = bt | set(bcalls) | set(VERIFIED_SDK_ADDITIONS)
    sdk_methods = set(bmethods) | bf | set(VERIFIED_SDK_ADDITIONS)
    for v in bm.values():
        sdk_methods |= v
    print(f"显式核实的 SDK 名字: {len(VERIFIED_SDK_ADDITIONS)}")
    print(f"\n基线: {len(base_paths)} 文件, 已知名字 类型{len(sdk_types)}/方法{len(sdk_methods)}")

    report("APP", app_paths, (sdk_types, sdk_calls, sdk_methods))


if __name__ == "__main__":
    main()
