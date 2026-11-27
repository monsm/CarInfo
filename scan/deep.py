#!/usr/bin/env python3
"""更深的检查：SDK 同名遮蔽、协议一致性要求、高阶函数闭包参数、清洗保真度。"""
import re
import pathlib
from scan import (read, target_files, DECL, EXT, MEMBER, KEYWORDS, body_of,
                  cases_of, lex, APP, BASELINE)

REQUIRED = {
    "View": ["body"],
    "ViewModifier": ["body"],
    "App": ["body"],
    "Scene": ["body"],
    "Widget": ["body"],
    "WidgetBundle": ["body"],
    "ButtonStyle": ["makeBody"],
    "ToggleStyle": ["makeBody"],
    "LabelStyle": ["makeBody"],
    "Identifiable": ["id"],
    "PreviewProvider": ["previews"],
    "UIViewControllerRepresentable": ["makeUIViewController", "updateUIViewController"],
    "UIViewRepresentable": ["makeUIView", "updateUIView"],
    "ActivityAttributes": ["ContentState"],
    "CaseIterable": [],
    "Codable": [],
}

HOF = re.compile(
    r"\.(map|compactMap|filter|forEach|reduce|sorted|allSatisfy|contains)"
    r"\s*(\(\s*[^()]*\))?\s*\{"
)
NO_GENERIC = re.compile(r"<[^<>]*>")
NESTED_DECL = re.compile(r"\b(struct|enum|class|actor|typealias)[ \t]+([A-Za-z_]\w*)")


def strip_generics(s):
    prev = None
    while prev != s:
        prev = s
        s = NO_GENERIC.sub("", s)
    return s


MODS = ("public", "private", "fileprivate", "internal", "open", "final", "static",
        "class", "nonisolated", "mutating", "nonmutating", "lazy", "weak", "unowned",
        "indirect", "override", "convenience", "required", "dynamic")
MOD = r"(?:(?:" + "|".join(MODS) + r")\s+|@\w+(?:\([^)]*\))?\s+)*"
DECL_LINE = re.compile(r"^\s*" + MOD + r"(let|var|func)\s+([A-Za-z_]\w*)")
TYPE_LINE = re.compile(r"^\s*" + MOD + r"(enum|struct|class|actor|extension)\s+([A-Za-z_]\w*)")


def member_dups(texts):
    """同一命名空间里重复声明的成员。

    关键是要分清「类型作用域」和「函数体」：两者花括号深度一样，
    只有类型链上的声明才算成员，局部变量不算（否则满屏误报）。
    """
    out = {}
    for p, text in texts.items():
        for m in re.finditer(r"(?m)^" + MOD + r"(enum|struct|class|actor|extension)"
                             r"\s+([A-Za-z_]\w*)[^{]*\{", text):
            name = m.group(2)
            body = body_of(text, m.end() - 1)
            owner, depth, seen = {0: [name]}, 0, {}
            for li, line in enumerate(body[1:].split("\n")):
                s = line.strip()
                o = owner.get(depth)
                if o is not None and s and not s.startswith(("//", "@")):
                    dm = DECL_LINE.match(s)
                    if dm:
                        kind, nm = dm.group(1), dm.group(2)
                        sig = ""
                        if kind == "func":
                            j = s.find("(", dm.end() - len(nm))
                            if j >= 0:
                                d2, k2 = 0, j
                                while k2 < len(s):
                                    if s[k2] == "(":
                                        d2 += 1
                                    elif s[k2] == ")":
                                        d2 -= 1
                                        if d2 == 0:
                                            break
                                    k2 += 1
                                sig = re.sub(r"\s+", "", s[j:k2 + 1])
                            else:
                                sig = re.sub(r"\s+", "", s[dm.end():])
                        key = ".".join(o + [nm]) + ("" if kind == "func" else " [属性]")
                        seen.setdefault((key, kind, sig), []).append((p.name, li, s[:70]))
                        same = [v for (k3, k4, _s3), v in seen.items()
                                if k3 == key and k4 == kind]
                        if len(same) > 1 and len(same[0]) > 1:
                            out[key] = same
                opens = line.count("{") - line.count("}")
                if opens > 0:
                    t = TYPE_LINE.match(line.split("{")[0])
                    if t and o is not None:
                        owner[depth + 1] = o + [t.group(2)]
                    else:
                        owner[depth + 1] = None
                elif opens < 0:
                    for d2 in range(depth, depth + opens, -1):
                        owner.pop(d2, None)
                depth += opens
    return out


def main():
    paths = target_files(APP)
    if not paths:
        raise SystemExit("!! 没找到源文件 —— 必须在仓库根目录运行：python3 scan/deep.py")
    texts = {p: read(p) for p in paths}
    print(f"扫描 {len(paths)} 个文件（app target）")

    base_paths = sorted(BASELINE.rglob("*.swift"))
    sdk_types = set()
    for p in base_paths:
        t = read(p)
        for m in DECL.finditer(t):
            sdk_types.add(m.group(2))
        _, _, cleaned = lex(t, clean=True)
        for m in re.finditer(r"(?::[ \t]*|->[ \t]*|\[\s*|<\s*|as[?!][ \t]*)([A-Z][A-Za-z0-9_]*)", cleaned):
            sdk_types.add(m.group(1))
    sdk_types -= set(KEYWORDS)

    members = {}
    kind = {}
    has_init = set()
    qualified_bodies = []
    conformances = {}
    nested = []
    hof_hits = []

    for p, text in texts.items():
        decls = []
        for m in DECL.finditer(text):
            if m.group(2) in KEYWORDS:
                continue
            brace = text.find("{", m.end() - 1)
            body = body_of(text, brace)
            decls.append((m.group(2), m.group(1), m.start(), brace + len(body) + 1, body,
                          strip_generics(text[m.end():brace]).replace("\n", " ")))
        for name, kw, s, e, body, proto_txt in decls:
            got = set(MEMBER.findall(body)) | cases_of(body) | {n for _k, n in NESTED_DECL.findall(body)}
            members.setdefault(name, set()).update(got)
            kind[name] = kw
            if re.search(r"\binit\s*\(", body):
                has_init.add(name)
            parent, best = None, -1
            for n2, _k2, s2, e2, _b2, _pt in decls:
                if s2 < s < e2 and s2 > best:
                    parent, best = n2, s2
            q = f"{parent}.{name}" if parent else name
            qualified_bodies.append((q, p.name, body))
            if parent:
                nested.append((parent, name, p.name))
            for part in proto_txt.replace(":", " ").split(","):
                tok = part.strip().split()[0] if part.strip() else ""
                tok = tok.strip("{}").strip()
                if tok and tok[0].isupper():
                    conformances.setdefault(tok, set()).add((name, p.name))
        for m in EXT.finditer(text):
            brace = text.find("{", m.end() - 1)
            body = body_of(text, brace)
            nm = m.group(1)
            got = set(MEMBER.findall(body)) | cases_of(body) | {n for _k, n in NESTED_DECL.findall(body)}
            members.setdefault(nm, set()).update(got)
            members.setdefault(nm.split(".")[-1], set()).update(got)
            qualified_bodies.append((nm, p.name, body))

        for m in HOF.finditer(text):
            if m.group(2) and m.group(1) != "reduce":
                continue
            brace = text.find("{", m.end() - 1)
            body = body_of(text, brace)
            if len(body) > 1200:
                continue
            head = "\n".join(body.split("\n")[:3])
            if re.search(r"\bin\b", head) or "$0" in body or "$1" in body:
                continue
            hof_hits.append((p.name, text[:m.start()].count("\n") + 1,
                             body.strip().replace("\n", " ")[:75]))

    print("\n### 1) 精确遮蔽检查：父类型里用 `C.x` 而 x 不在 C 里 / 用 `C(...)` 而 C 是无 case 的 enum")
    bugs = []
    for parent, child, fname in nested:
        if child not in members:
            continue
        child_kind = kind.get(child, "")
        child_members = members.get(child, set())
        bodies = [(f, b) for q, f, b in qualified_bodies if q == parent or q.endswith("." + parent)]
        bodies = [(f, b) for f, b in bodies if f]
        for f, body in bodies:
            for mm in re.finditer(rf"(?<![A-Za-z0-9_.]){child}\.([a-zA-Z_]\w*)", body):
                mem = mm.group(1)
                if mem not in child_members and mem not in {"self", "Type", "Protocol", "allCases"}:
                    line = body[:mm.start()].count("\n") + 1
                    bugs.append(f"{f}: 在 {parent} 中 {child}.{mem} —— {child} 没有成员 {mem}")
            if child_kind == "enum" and child not in has_init:
                for mm in re.finditer(rf"(?<![A-Za-z0-9_.]){child}\s*\(", body):
                    prev = body[max(0, mm.start() - 30):mm.start()]
                    if re.search(r"\b(enum|case)\s*$", prev):
                        continue
                    line = body[:mm.start()].count("\n") + 1
                    bugs.append(f"{f}: 在 {parent} 中构造 {child}(...) —— {child} 是无 case 的 enum")
    if bugs:
        for b in sorted(set(bugs)):
            print("   ⚠️", b)
    else:
        print("    ✅ 无")

    print("\n### 2) 协议一致性缺少必要成员")
    missing = []
    for proto, types in sorted(conformances.items()):
        need = REQUIRED.get(proto)
        if not need:
            continue
        for tname, fname in sorted(types):
            have = members.get(tname, set())
            for req in need:
                if req not in have:
                    missing.append(f"{fname}: {tname}: {proto} 需要 {req}")
    if missing:
        for s in missing:
            print("   ⚠️", s)
    else:
        print("    ✅ 无")

    print("\n### 3) 高阶函数闭包既无参数也无 $0")
    if hof_hits:
        for s in hof_hits:
            print(f"    ⚠️ {s[0]}:L{s[1]}  {{ {s[2]} }}")
    else:
        print("    ✅ 无")

    print("\n### 4) 清洗保真度")
    bad = []
    for p, text in texts.items():
        _, _, cleaned = lex(text, clean=True)
        a = sum(1 for c in text if not c.isspace())
        b = sum(1 for c in cleaned if not c.isspace())
        if a and b / a < 0.55:
            bad.append(f"{p.name}: {b}/{a} = {b/a:.2f}")
    for s in bad:
        print("    ⚠️", s)
    if not bad:
        print("    ✅ 正常")

    print("\n### 8) 同一命名空间里重复声明的成员（invalid redeclaration）")
    decl_members = member_dups(texts)
    for k in sorted(decl_members):
        hits = decl_members[k]
        print(f"    ⚠️ {k} 重复 {len(hits)} 次（{sorted({h[0] for h in hits})}）")
        for f, li, txt in hits[:3]:
            print(f"         {f} +{li}: {txt}")
    if not decl_members:
        print("    ✅ 无")

    print(f"\n（嵌套重名共 {len(nested)} 处，覆盖 {len({p for _a, _b, p in nested})} 个父类型）")


main()
