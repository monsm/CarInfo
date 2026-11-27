#!/usr/bin/env python3
"""逻辑/结构类编译错误检查（名字解析查不出来的那几种）：

  5) `some View` 返回但多语句无 return（chargeCard / chargingBurst 那一类）
  6) 标识符未声明（`idx` 那一类 —— 重排脚本把 ForEach 参数删了）
  8) @main 绑定到非入口类型（SceneID 被插在 @main 与 App 结构体之间那一轮）
  7) ViewBuilder 直接子视图 > 10 个（buildBlock 上限，会报 extra argument）
"""
import json
import re
import bisect
from scan import (read, target_files, APP, DECL, EXT, MEMBER, FUNC, KEYWORDS,
                  body_of, cases_of, lex, BASELINE)

CONTAINERS = {
    "VStack", "HStack", "ZStack", "Group", "Section", "Form", "List", "ScrollView",
    "LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid", "Grid", "GridRow",
    "ViewThatFits", "NavigationStack", "DisclosureGroup", "Menu", "ToolbarItemGroup",
}
CONT_CHARS = ".,)]}?:&|+-*/<>="
SWIFT_KEYWORDS = set("""
if else guard for while repeat switch case default return break continue fallthrough
let var func class struct enum protocol extension init deinit subscript typealias
associatedtype import private public internal fileprivate open final static
lazy weak unowned mutating nonmutating override required convenience dynamic
self Self super nil true false try catch throw throws rethrows as is in where
some any async await actor defer do yield consume borrowing inout
get set willSet didSet newValue oldValue
""".split())
CACHE = __import__("pathlib").Path(__file__).parent / "sdk_cache.json"


def line_starts(text):
    offs, pos = [0], 0
    while True:
        pos = text.find("\n", pos)
        if pos < 0:
            break
        pos += 1
        offs.append(pos)
    return offs


def lineno(offs, pos):
    return bisect.bisect_right(offs, pos)


def stmts(inner):
    """顶层语句数／是否含 return／语句首词。
    必须同时跟踪 () [] {} 三种括号：多行函数调用的续行落在括号内，
    否则会被当成一条新语句（导致 ViewBuilder 子视图数虚高）。"""
    out, depth, has_ret, words = 0, 0, False, []
    for line in inner.split("\n"):
        s = line.strip()
        if depth == 0 and s and not s.startswith("//") and s[0] not in CONT_CHARS:
            out += 1
            words.append(re.split(r"[\s(=.]", s, maxsplit=1)[0])
        if re.search(r"\breturn\b", s):
            has_ret = True
        depth += (line.count("{") - line.count("}")
                  + line.count("(") - line.count(")")
                  + line.count("[") - line.count("]"))
    depth = max(depth, 0)
    return out, has_ret, words


def sdk_names():
    if CACHE.exists():
        d = json.loads(CACHE.read_text(encoding="utf-8"))
        return set(d)
    names = set()
    for p in sorted(BASELINE.rglob("*.swift")):
        t = read(p)
        names |= {m.group(2) for m in DECL.finditer(t)}
        names |= set(FUNC.findall(t))
        _, _, cleaned = lex(t, clean=True)
        names |= set(re.findall(r"(?<![A-Za-z0-9_.])([a-z_][A-Za-z0-9_]*)", cleaned))
        names |= set(re.findall(r"\.([a-z_][A-Za-z0-9_]*)", cleaned))
    CACHE.write_text(json.dumps(sorted(names)), encoding="utf-8")
    return names


def main():
    paths = target_files(APP)
    if not paths:
        raise SystemExit("!! 必须从仓库根目录运行")
    print(f"扫描 {len(paths)} 个文件\n")
    opaque, undecl, many = [], [], []
    mains = []

    proj, sdk = set(), sdk_names()
    texts, offs = {}, {}
    for p in paths:
        t = read(p)
        texts[p], offs[p] = t, line_starts(t)
        proj |= {m.group(2) for m in DECL.finditer(t)}
        proj |= set(FUNC.findall(t))
        proj |= set(re.findall(r"(?m)^[ \t]*(?:public |private |internal |static )*"
                               r"(?:let|var)[ \t]+([a-zA-Z_]\w*)", t))

    for p in paths:
        text = texts[p]
        O = offs[p]
        _, _, cleaned = lex(text, clean=True)
        cl_offs = line_starts(cleaned)
        lines = text.split("\n")

        for i, ln in enumerate(lines):
            mt = re.search(r"->\s*(some\s+[A-Za-z_][\w.]*|AnyView)\s*(\{)?\s*(//.*)?$", ln)
            mp = re.search(r":\s*(some\s+[A-Za-z_][\w.]*|AnyView)\s*\{", ln)
            if not mt and not mp:
                continue
            brace = O[i] + ln.rfind("{")
            if ln.rfind("{") < 0:
                nxt = "\n".join(lines[i + 1:i + 3])
                if not nxt.lstrip().startswith("{"):
                    continue
                brace = text.index("{", O[i] + len(ln))
            head = ln.split("->")[0]
            nm = re.search(r"(?:func\s+|var\s+)([A-Za-z_]\w*)", head)
            name = nm.group(1) if nm else "?"
            j, vb = i - 1, "@ViewBuilder" in ln
            while j >= 0 and not vb:
                s = lines[j].strip()
                if not s:
                    j -= 1
                    continue
                if s.startswith("@"):
                    vb = "ViewBuilder" in s
                    j -= 1
                    continue
                break
            if vb or name == "body":
                continue
            body = body_of(text, brace)
            inner = body[1:-1] if body.startswith("{") else body
            n, ret, words = stmts(inner)
            if ret:
                continue
            if n > 1 or (n == 1 and words and words[0] in
                         {"let", "var", "guard", "for", "while", "defer"}):
                opaque.append((p.name, i + 1, name, n, " ".join(words[:4])))

        for i, ln in enumerate(lines):
            if not ln.strip().startswith("@main"):
                continue
            j = i + 1
            while j < len(lines) and (not lines[j].strip()
                                      or lines[j].strip().startswith(("@", "//"))
                                      or lines[j].strip().startswith("/*")):
                j += 1
            nxt = lines[j].strip() if j < len(lines) else ""
            bound = re.match(r"(?:@\w+\s+)*(?:final\s+|public\s+|private\s+|internal\s+|open\s+)*"
                             r"(struct|class|actor|enum|extension|func|let|var)\s+([A-Za-z_]\w*)", nxt)
            if bound:
                mains.append((p.name, i + 1, f"{bound.group(1)} {bound.group(2)}"))
            else:
                mains.append((p.name, i + 1, nxt[:60] or "<空>"))

        for i, ln in enumerate(lines):
            m = re.search(r"(?<![A-Za-z0-9_.])([A-Z][A-Za-z0-9_]*)\s*(\([^{}]*\))?\s*\{\s*(//.*)?$", ln)
            if not m or m.group(1) not in CONTAINERS or ln.rfind("{") < 0:
                continue
            body = body_of(text, O[i] + ln.rfind("{"))
            inner = body[1:-1] if body.startswith("{") else body
            _n, _ret, words = stmts(inner)
            kids = sum(1 for w in words if w not in {"let", "var"})
            if kids > 10:
                many.append((p.name, i + 1, m.group(1), kids))

        local = set(re.findall(r"\b(?:let|var)\s+([a-zA-Z_]\w*)", cleaned))
        local |= set(re.findall(r"\bfor\s+([a-zA-Z_]\w*)\s+in\b", cleaned))
        local |= set(re.findall(r"\b(?:if|guard|while)\s+let\s+([a-zA-Z_]\w*)", cleaned))
        local |= set(re.findall(r"\b(?:case|catch)\s+(?:let\s+)?\(?([a-zA-Z_]\w*)", cleaned))
        local |= set(re.findall(r"\b(?:,\s*|\bcase\s+)let\s+\(?([a-zA-Z_]\w*)", cleaned))
        for line in cleaned.split("\n"):
            for mm in re.finditer(r"\bin\b", line):
                before = line[:mm.start()].strip().lstrip("{").strip()
                if len(before) > 90 or ";" in before or before.startswith("for "):
                    continue
                before = re.sub(r"->.*$", "", before.strip().strip("()")).strip()
                if before.startswith("for"):
                    continue
                for piece in before.split(","):
                    w = piece.strip().split(":")[0].strip().strip("()")
                    if re.fullmatch(r"[a-zA-Z_]\w*", w):
                        local.add(w)
            if "func " in line:
                j = line.find("(")
                if j >= 0:
                    depth, k = 0, j
                    while k < len(line):
                        if line[k] == "(":
                            depth += 1
                        elif line[k] == ")":
                            depth -= 1
                            if depth == 0:
                                break
                        k += 1
                    for piece in line[j + 1:k].split(","):
                        w = piece.strip().split(":")[0].strip().strip("()")
                        if re.fullmatch(r"[a-zA-Z_]\w*", w):
                            local.add(w)
        allowed = (local | set(MEMBER.findall(cleaned)) | cases_of(cleaned)
                   | proj | sdk | SWIFT_KEYWORDS)
        for mm in re.finditer(r"(?<![A-Za-z0-9_.@$])([a-z_][A-Za-z0-9_]*)", cleaned):
            w = mm.group(1)
            if w in allowed or len(w) <= 1:
                continue
            if re.match(r"\s*:", cleaned[mm.end():mm.end() + 8]):
                prev = cleaned[max(0, mm.start() - 1)]
                if prev in "([,":
                    continue
            undecl.append((p.name, lineno(cl_offs, mm.start()), w, "file-scope"))

    print("### 5) `some View` 有语句但无 return")
    for s in opaque:
        print(f"    ⚠️ {s[0]}:L{s[1]} {s[2]}() 顶层语句 {s[3]} 条 [{s[4]}]")
    if not opaque:
        print("    ✅ 无")

    print("\n### 6) 疑似未声明的标识符（需人工确认）")
    seen = set()
    for f, ln, w, ctx in undecl:
        if (f, w) in seen:
            continue
        seen.add((f, w))
        print(f"    ? {f}:L{ln}  {w}   (在 {ctx})")
    if not undecl:
        print("    ✅ 无")

    print("\n### 9) 只出现在注释里、别处没有声明的标识符（可能是被粘行吞掉的代码）")
    declared_clean = set()
    for p in paths:
        c = lex(texts[p], clean=True)[2]
        declared_clean |= set(FUNC.findall(c))
        declared_clean |= {m.group(2) for m in DECL.finditer(c)}
        declared_clean |= {n for _k, n in re.findall(
            r"\b(enum|struct|class|actor|typealias)\s+([A-Za-z_]\w*)", c)}
    swallowed, seen_sw = [], set()
    for p in paths:
        for i, line in enumerate(texts[p].split("\n"), 1):
            s = line.strip()
            if not s.startswith(("//", "/*", "*")):
                continue
            for m in re.finditer(r"\b(func|var|let|struct|enum|class|extension)\s+([A-Za-z_]\w*)", s):
                nm = m.group(2)
                if nm in declared_clean or (p.name, nm) in seen_sw:
                    continue
                seen_sw.add((p.name, nm))
                swallowed.append((p.name, i, nm, s[:78]))
    for f, ln, nm, txt in swallowed:
        print(f"    ⚠️ {f}:L{ln}  {nm}\n         {txt}")
    if not swallowed:
        print("    ✅ 无")

    print("\n### 8) @main 绑定（必须紧贴 struct/class/actor 入口，且全仓唯一）")
    if not mains:
        print("    ⚠️ 全仓没有任何 @main —— App 缺少入口，swiftc 会报 'main attribute is required'")
    for f, ln, tgt in mains:
        ok = bool(re.match(r"(struct|class|actor)\s+\w+", tgt))
        mark = "✅" if ok and len(mains) == 1 else "⚠️"
        print(f"    {mark} {f}:L{ln} → {tgt}")
    if len(mains) > 1:
        print(f"    ⚠️ 共 {len(mains)} 处 @main —— 全仓只允许一个入口")

    print("\n### 7) ViewBuilder 直接子视图 > 10（仅参考，本 SDK 不报错）")
    for s in sorted(set(many)):
        print(f"    ⚠️ {s[0]}:L{s[1]} {s[2]} 有 {s[3]} 个子视图")
    if not many:
        print("    ✅ 无")


main()
