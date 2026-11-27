#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图标门禁 —— 「出包的那份 PNG 与 `Contents.json` 说的必须是同一件事」

为什么需要它（真实事故与真实隐患）：
  · 这个仓库的图标出过一次「改了 A、真机上看到 B」：`AppIcon-SPEC.md` 记着上一版
    文档让生成器写进仓库根目录的另一份 `AppIcon/`，而 Xcode 只认 appiconset 里那份 ——
    两份并存时，改了不出包的那一份，谁都看不出来。
  · v1.0 的图标犯了三个**可量**的错，而它们全部编译得过、31 条门禁全绿、模拟器里也正常：
      ① 自己套了圆角并内缩 4%（系统还要再套一层 squircle，成品比邻居小一圈）；
      ② 生成脚本最后 `convert('RGB')` 把透明边压成了**纯黑** —— 实测四角 = (0,0,0)，
         遮罩里因此留下四个黑角；
      ③ 只有一张图，没有深色 / 着色外观（iOS 18 起主屏有三种图标外观）。
    ①②正是判据 4（「满幅」）要拦的：四角与同一行内侧的颜色必须一致。
  · 图标不是 Swift 文件，上面那些检查（design / lintcfg / eol…）一条都看不到它。

判据（每一条都当场能量出来，不靠眼睛）：
  1. `Contents.json` 能解析，且每个条目引用的文件真的在目录里。
  2. 每个条目的**实际像素尺寸**等于它声明的大小 × scale（1024 槽位视为 1024²）。
  3. 每个槽位有**三套外观**：不带 `appearances`（浅色）、`dark`、`tinted`。
  4. 三张 1024 主图**满幅**：不带透明像素，且四角与同一行内侧（x=8 与 x=72）颜色一致。
  5. 目录里没有**没人引用**的 PNG（多出来的那种文件正是「改了 A 看到 B」的来源）。

⚠️ 这里**不能用 Pillow**，原因值得记下来：
  门禁都住在 `scan/`，而脚本所在目录会被放进 `sys.path`。`scan/copy.py`（文案门禁）
  与标准库的 `copy` 同名 —— Pillow 的 XML 依赖（`defusedxml` → `xml.etree`）一
  `import copy` 就拿错了模块，当场 `AttributeError: module 'copy' has no attribute
  'deepcopy'`。也就是说：**任何在 scan/ 里 import Pillow 的门禁都跑不起来**。
  所以下面自己读 PNG（只认 8-bit RGB/RGBA、非交错 —— 我们自己的生成器只写这一种；
  其它格式一律报红让人来看，不静默放行）。

退出码：0 = 通过；1 = 有需要修的地方（带可执行的修法）。
"""
import io
import json
import os
import struct
import sys
import zlib

ROOT = os.path.join("CarKeeper", "CarKeeper", "Resources", "Assets.xcassets",
                    "AppIcon.appiconset")
CONTENTS = os.path.join(ROOT, "Contents.json")
APPEARANCE_KEYS = ("dark", "tinted")
EDGE_TOL = 14
EDGE_INSET = 64
SIG = b"\x89PNG\r\n\x1a\n"


def read_png(path):
    """返回 (宽, 高, 色彩类型, 解交错的行)。不支持的形式抛 ValueError。"""
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:8] != SIG:
        raise ValueError("不是 PNG 文件")
    pos = 8
    ihdr = None
    idat = b""
    while pos + 8 <= len(raw):
        length, ctype = struct.unpack(">I4s", raw[pos:pos + 8])
        data = raw[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            ihdr = data
        elif ctype == b"IDAT":
            idat += data
        elif ctype == b"IEND":
            break
        pos += 12 + length
    if ihdr is None or not idat:
        raise ValueError("缺少 IHDR / IDAT")
    w, h, depth, ctype, _comp, _filt, interlace = struct.unpack(">IIBBBBB", ihdr[:13])
    if depth != 8 or ctype not in (2, 6) or interlace != 0:
        raise ValueError(f"只认 8-bit RGB/RGBA、非交错（这份是 depth={depth} "
                         f"colorType={ctype} interlace={interlace}）")
    bpp = 3 if ctype == 2 else 4
    stride = w * bpp
    flat = zlib.decompress(idat)
    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(h):
        ftype = flat[pos]
        line = bytearray(flat[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if ftype == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"未知行过滤器 {ftype}")
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def pixel(rows, bpp, x, y):
    off = x * bpp
    return tuple(rows[y][off:off + 3])


def declared_pixels(entry):
    side = int(entry["size"].split("x")[0])
    scale = int(entry.get("scale", "1x")[0])
    return side * scale


def appearance_of(entry):
    for a in entry.get("appearances", []):
        if a.get("appearance") == "luminosity":
            return a.get("value")
    return "light"


def main():
    if not os.path.isfile(CONTENTS):
        print(f"[红] 找不到 {CONTENTS}")
        return 1
    with io.open(CONTENTS, encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("images", [])
    if not entries:
        print("[红] Contents.json 里一条 images 都没有 —— 图标会走 actool 的兜底，"
              "而兜底出来的东西没人验过")
        return 1

    problems = []
    referenced = set()
    slots = {}
    masters = []
    for e in entries:
        filename = e.get("filename")
        if not filename:
            problems.append(f"声明缺 filename：{e}")
            continue
        referenced.add(filename)
        path = os.path.join(ROOT, filename)
        if not os.path.isfile(path):
            problems.append(f"{filename}：Contents.json 引用了它，文件不在")
            continue
        try:
            w, h, bpp, rows = read_png(path)
        except (ValueError, zlib.error) as err:
            problems.append(f"{filename}：读不动（{err}）")
            continue
        want = declared_pixels(e)
        if (w, h) != (want, want):
            problems.append(f"{filename}：声明 {want}×{want}，实际 {w}×{h}")
        slots.setdefault((e["size"], e.get("scale")), set()).add(appearance_of(e))
        if w == 1024:
            masters.append((filename, appearance_of(e), bpp, rows, w, h))

    for (size, scale), apps in sorted(slots.items(), key=lambda kv: str(kv[0])):
        missing = ({"light"} | set(APPEARANCE_KEYS)) - apps
        if missing:
            problems.append(f"{size} {scale if scale else '(1024 主图)'}：缺外观 "
                            f"{sorted(missing)}（iOS 18 起主屏有浅色 / 深色 / 着色三种）")

    for filename, appearance, bpp, rows, w, h in masters:
        if bpp == 4:
            opaque = all(rows[y][x * 4 + 3] == 255 for y in range(0, h, 4)
                         for x in range(0, w, 4))
            if not opaque:
                problems.append(f"{filename}：带透明像素 —— 图标要满幅，圆角与内缩交给"
                                f"系统遮罩（透明边被压成 RGB 之后就是黑角）")
        mid_x, mid_y = w // 2, h // 2
        samples = {
            "左上角": (8, 8, 1, 0), "右上角": (w - 9, 8, -1, 0),
            "左下角": (8, h - 9, 1, 0), "右下角": (w - 9, h - 9, -1, 0),
            "上边中": (mid_x, 8, 0, 1), "下边中": (mid_x, h - 9, 0, -1),
            "左边中": (8, mid_y, 1, 0), "右边中": (w - 9, mid_y, -1, 0),
        }
        for label, (x, y, dx, dy) in samples.items():
            edge = pixel(rows, bpp, x, y)
            ix, iy = x + dx * EDGE_INSET, y + dy * EDGE_INSET
            inner = pixel(rows, bpp, min(max(ix, 0), w - 1), min(max(iy, 0), h - 1))
            delta = max(abs(edge[i] - inner[i]) for i in range(3))
            if delta > EDGE_TOL:
                problems.append(f"{filename}（{appearance}）：{label} {edge} 与向内 64px 的"
                                f"{inner} 差 {delta} —— 图上自己画了圆角 / 内缩 / 黑角"
                                f"（满幅图标的边缘应与内侧只差底色渐变那一丁点）")

    for name in sorted(os.listdir(ROOT)):
        if name.endswith(".png") and name not in referenced:
            problems.append(f"{name}：没人引用（多出来的图标文件正是「改了 A 看到 B」的来源）")

    print(f"图标集：{len(entries)} 条声明 / {len(referenced)} 个文件")
    if problems:
        print(f"\n[红] {len(problems)} 处：")
        for p in problems:
            print("   - " + p)
        print("\n修法：改 `CarKeeper/generate_appicon_pillow.py` 的几何 / 配色后重跑")
        print("      `bash CarKeeper/generate_appicon.sh` —— 两份产物（PNG 与 Contents.json）")
        print("      是一起更新的。")
        return 1
    print("[通过] 声明与文件一致：尺寸、三套外观、满幅、无多余文件")
    return 0


if __name__ == "__main__":
    sys.exit(main())
