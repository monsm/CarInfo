import json, re, glob, collections, io, sys

sys.stdout.reconfigure(encoding="utf-8")
LOGS = sorted(glob.glob("D:/xm/ChangAnCarInfo/bin/Debug/changan_net_log_*.log"))

def endpoint(url):
    u = url.split("?")[0]
    for host in ("https://m.iov.changan.com.cn/appserver/api/", "https://m.iov.changan.com.cn/api/",
                 "https://scrm.changan.com.cn/app-m/prod-api/"):
        if u.startswith(host):
            return u[len(host):] or host
    return u

print("=" * 80)
print("① 三份日志的端点覆盖（看有没有只出现在旧日志里的接口）")
for L in LOGS:
    raw = open(L, encoding="utf-8", errors="replace").read()
    c = collections.Counter()
    for m in re.finditer(r"\b(REQ|RES|ERR) (POST|GET) (https?://\S+)", raw):
        if m.group(1) == "REQ":
            c[endpoint(m.group(3))] += 1
    print(f"\n--- {L.split('/')[-1]}  （{len(c)} 个端点）")
    for ep, n in c.most_common():
        print(f"    {n:3d}x  {ep}")

L = "D:/xm/ChangAnCarInfo/bin/Debug/changan_net_log_20260922.log"
raw = open(L, encoding="utf-8", errors="replace").read()

print()
print("=" * 80)
print("② 0922 日志：请求节奏（REQ 时间戳）")
reqs = [(m.group(1), endpoint(m.group(3))) for m in re.finditer(r"\[(\d\d:\d\d:\d\d\.\d+)\] REQ (POST|GET) (https?://\S+)", raw)]
for t, ep in reqs:
    print(f"  {t}  {ep}")

bodies = []
for m in re.finditer(r"body=(.*?)(?=\n\[\d\d:\d\d:\d\d\.\d+\]|\Z)", raw, re.S):
    txt = m.group(1).strip()
    if txt.startswith("{"):
        try:
            bodies.append(json.loads(txt))
        except Exception as e:
            print("  (跳过一段无法解析的 body:", str(e)[:60], ")")

def walk(o, prefix, out):
    if isinstance(o, dict):
        for k, v in o.items():
            path = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                walk(v, path, out)
            elif isinstance(v, list):
                if v and isinstance(v[0], dict):
                    walk(v[0], path + "[0]", out)
                else:
                    out.append((path, f"list[{len(v)}]", json.dumps(v, ensure_ascii=False)[:46]))
            else:
                out.append((path, type(v).__name__, json.dumps(v, ensure_ascii=False)[:46]))
    return out

print()
print("=" * 80)
print("③ 每个报文的完整字段（递归；数组取第 0 个元素）")
groups = collections.OrderedDict()
for b in bodies:
    d = b.get("data", b)
    if isinstance(d, list):
        d = d[0] if d else {}
    if isinstance(d, dict):
        sig = tuple(list(d.keys())[:4])
        groups.setdefault(sig, []).append(d)

for i, (sig, items) in enumerate(groups.items(), 1):
    fields = walk(items[0], "", [])
    print(f"\n--- 报文组 #{i}：{len(fields)} 个字段，出现 {len(items)} 次；前四个键 = {list(sig)}")
    for path, typ, val in fields:
        print(f"  {path:56s} {typ:9s} {val}")
