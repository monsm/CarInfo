import json, re, sys, collections
sys.stdout.reconfigure(encoding="utf-8")
L = "D:/xm/ChangAnCarInfo/bin/Debug/changan_net_log_20260922.log"
raw = open(L, encoding="utf-8", errors="replace").read()

i = raw.find("RES HTTP 200 POST https://m.iov.changan.com.cn/appserver/api/information/pageReceiverInfoByTime")
i = raw.find("body=", i)
start = raw.find("{", i)
depth = 0
in_str = False
esc = False
end = None
for j in range(start, len(raw)):
    ch = raw[j]
    if in_str:
        if esc: esc = False
        elif ch == "\\": esc = True
        elif ch == '"': in_str = False
    else:
        if ch == '"': in_str = True
        elif ch == "{": depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = j + 1
                break
print("已配对到第", end, "字符" if end else "（未闭合，文件被截断）")
txt = raw[start:end] if end else raw[start:]
obj = None
try:
    obj = json.loads(txt, strict=False)
except Exception as e:
    print("整体解析失败:", str(e)[:80], "→ 退化为逐条消息扫描")

if obj is None:
    k = txt.find('"content"')
    k = txt.find("[", k)
    s2 = txt.find("{", k)
    depth = in_str = esc = False
    depth = 0
    end2 = None
    for j in range(s2, len(txt)):
        ch = txt[j]
        if in_str:
            if esc: esc = False
            elif ch == "\\": esc = True
            elif ch == '"': in_str = False
        else:
            if ch == '"': in_str = True
            elif ch == "{": depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end2 = j + 1
                    break
    print("第一条消息对象配对到:", end2)
    obj = {"data": {"content": [json.loads(txt[s2:end2], strict=False)]}, "_partial": True}

if obj:
    d = obj["data"]
    print("分页字段:", {k: d[k] for k in d if k != "content"} if isinstance(d, dict) else "n/a")
    content = d["content"]
    print("消息条数:", len(content))
    print("\n第一条消息的字段：")
    for k, v in content[0].items():
        s = json.dumps(v, ensure_ascii=False)
        print(f"  {k:22s} {type(v).__name__:9s} {s[:60]}")
    print("\njumpParam 内部的字段（事件细节）：")
    jp = json.loads(content[0]["jumpParam"])
    for k, v in jp.items():
        print(f"  {k:18s} {type(v).__name__:9s} {json.dumps(v, ensure_ascii=False)[:60]}")
    if "uriParams" in jp:
        for k, v in jp["uriParams"].items():
            print(f"  uriParams.{k:16s} {type(v).__name__:9s} {json.dumps(v, ensure_ascii=False)[:60]}")
    print("\n全部消息的类型与时间（前 30 条）：")
    for m in content[:30]:
        try:
            p = json.loads(m["jumpParam"])["uriParams"]
            t = p.get("gpsTime", "?")
            extra = f"flameout={p.get('flameoutReason')} ignition={p.get('ignitionReason')}"
        except Exception:
            t, extra = "?", ""
        print(f"  {m.get('createdAt')}  {m.get('infoTypeId'):10s} read={m.get('readStatus')}  {t}  {extra}  {str(m.get('summary'))[:28]}")
    print("\n类型计数:", collections.Counter(m.get("infoTypeId") for m in content))
