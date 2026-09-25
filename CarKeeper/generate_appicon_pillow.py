#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""generate_appicon_pillow.py — 出包用的 AppIcon 渲染器（**唯一来源**）

用法：
    python3 generate_appicon_pillow.py                 # 写出到 appiconset
    python3 generate_appicon_pillow.py <输出目录>       # 写到别处（用来对照，不进包）

v2.0（2026-09-25）整张重画。旧版的问题不是「不好看」这种说不清的事，四条都能指出来：

  ① **底色近黑**。旧图 1024 的亮度中位数是 0.096（深蓝黑 #1A1A2E→#0D0D1A）——
     它在主屏上就是一块黑，而 iOS 的图标语言是**亮底 + 一个物体**。这是「不符合
     iOS 调性」最主要的一条。
  ② **图上有字**（「长安车管家」+「CHANGAN CONNECT」两行）。Apple 的图标规范第一条
     就是不要放文字：29pt 下那是两团灰噪点，而它占了画面下缘整整一成高度。
  ③ **自己套了圆角与 4% 内缩**。系统会用自己的 squircle 遮罩裁一遍 —— 图里再裁一遍
     等于两层，成品比旁边系统图标小一圈。更糟的是旧脚本最后 `convert('RGB')`
     把透明边压成了**纯黑**（实测四角 = (0,0,0)），于是遮罩里留下四个黑角。
  ④ **没有深色 / 着色外观**。iOS 18 起主屏有浅色 / 深色 / 着色三种图标外观；
     只给一张图，系统只能把同一张往深色与着色里硬套。

v2.0 的画法（每条都对应上面一条）：
  · **满幅**：1024×1024 铺满，不画圆角、不留边、不留透明 —— 遮罩由系统裁。
  · **亮底**：琥珀→橙的竖向渐变（浅色外观）；深色外观是暖近黑 + 琥珀车；着色外观是
    灰阶（系统按亮度上色）。
  · **一个物体**：白色（深色外观是琥珀色）轿车侧影，窗与轮拱是**挖空**（透出底色），
    没有任何描边、阴影、光晕、贴图感。
  · **一层高光**：顶部一道很淡的白色渐变 —— iOS 26 的玻璃表面在图标上就是这么一层，
    没有它，纯渐变会显得平。

几何全部写在 `CAR` / `WHEELS` / `WINDOWS` 里，单位是 1024 的坐标系；
改形状只改那几个常量（与 `AppIcon.svg` 是同一套几何，见 `AppIcon-SPEC.md`）。
"""
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# =============================================================================
#  几何（1024 坐标系）
# =============================================================================
#
#  车头朝右的轿车侧影。四个数决定它读起来像不像一台车：
#    · **车身高度 ≈ 300**（车顶 400 → 车底 700），长 696 —— 长高比 2.3，是轿车的比例
#      （旧图那个多边形算出来是 2.0 且车顶堆在中间，像面包车）。
#  v2.1（同日第二轮）：v2.0 的车只有 300 高、只占画布 29% —— 缩到主屏尺寸后是
#  一颗「中间一条小车、四周全是底」的图标。现在实测车身 689×409（长高比 1.68），
#  占画布宽 67%、高 40%（连同底下那道弧则到画布高 93%）—— 图标该把画布填到
#  只留一圈呼吸位，而不是缩在中间。这几个数是量出来的，不是估的。
CAR = [
    (180, 780),   # 后保险杠下
    (180, 690),   # 后保险杠上
    (248, 612),   # 后备厢
    (368, 496),   # C 柱
    (470, 372),   # 车顶后
    (640, 372),   # 车顶前
    (722, 470),   # A 柱
    (804, 552),   # 引擎盖
    (852, 580),   # 车鼻
    (868, 690),   # 车鼻下
    (868, 780),   # 前保险杠下
]
# 轮心必须满足 `cy + R ≤ 车底线（780）`：一旦超出，轮毂（圆心那一小块）就会从
# 车身下缘探出去、飘在底色上（v2.0 实测过：cy=700、R=84 时每个轮子下面露出 32 单位）。
WHEELS = [(320, 684), (740, 684)]
WHEEL_R = 96
HUB_R = 34
# 窗必须落在**车厢内部**（车身折线在每个 y 上的左右边界之间）—— 越界会在车身边上
# 咬出一个缺口。车厢在 y=425 处大约跨 x 430…680，所以窗从 455 排到 665；
# 两扇之间的 B 柱留 30（58pt 下约 1.7px，再窄缩小时就糊成一扇）。
WINDOWS = [(455, 425, 545, 515), (575, 425, 665, 515)]
ROUND_PX = 16          # 角上的圆化半径（用「模糊 + 阈值」实现，避免手写圆弧）
# 那道弧：App 里「车钉外面那圈弧」（续航圈）的图形引用 —— 在图标里它是车底下一条
# **向下弯的路**。圆心在车身上、只取下面那一段，于是两端向上收、中间最低，
# 读起来是地面/道路，而不是一个包围盒。半径 250 让它在车底线（780）之下再
# 让出 45，最低点在 y=950（离画布下边还有 74）—— 弧穿过车轮会让两个形状糊在一起，
# 贴到边上则会被 squircle 遮罩的圆角切掉。
ARC_CENTER = (524, 700)
ARC_R = 250
ARC_WIDTH = 26
ARC_SPAN = (30, 150)   # 度：PIL 的角度顺时针为正、0° = 3 点钟方向

# =============================================================================
#  三套外观
# =============================================================================
#
#  一律给 RGB（不带 alpha）：图标的形状由系统遮罩裁，我们只负责画面内容。
APPEARANCES = {
    # 浅色：琥珀→橙，白色车。亮底是这套图标语言的地基（旧图正好反过来）。
    "light": dict(bg_top=(255, 197, 61), bg_bottom=(255, 118, 26),
                  glyph=(255, 255, 255), arc_alpha=0.22, sheen=0.16, shade=0.10),
    # 深色：暖近黑底 + 琥珀车 —— 就是 App 自己那套夜间配色（#FF9F00 是品牌主色）。
    "dark": dict(bg_top=(46, 36, 24), bg_bottom=(16, 13, 10),
                 glyph=(255, 179, 71), arc_alpha=0.18, sheen=0.05, shade=0.0),
    # 着色：系统按**亮度**上色，所以这里只给灰阶（白车 + 中灰底）。
    "tinted": dict(bg_top=(126, 126, 132), bg_bottom=(62, 62, 68),
                   glyph=(255, 255, 255), arc_alpha=0.20, sheen=0.08, shade=0.0),
}

# Contents.json 真正引用的七个槽位（为什么没有 1x / iPad：见 AppIcon-SPEC.md）
SLOTS = [
    ("AppIcon-1024x1024.png", 1024),
    ("AppIcon-60x60@3x.png", 180),
    ("AppIcon-60x60@2x.png", 120),
    ("AppIcon-40x40@3x.png", 120),
    ("AppIcon-40x40@2x.png", 80),
    ("AppIcon-29x29@3x.png", 87),
    ("AppIcon-29x29@2x.png", 58),
]

FIXED = 1024


def scaled(points, k):
    return [(x * k, y * k) for x, y in points]


def glyph_mask():
    """返回 (车身 mask, 弧 mask) 两张 L 图（255 = 画在这里）。

    两张分开是因为它们**用的不是同一个浓度**：车是主体（实心），
    弧是底纹（App 里那圈弧也是虚线、比车钉淡）—— 同一张 mask 画不出两种浓度。
    """
    k = 1.0
    body = Image.new("L", (FIXED, FIXED), 0)
    d = ImageDraw.Draw(body)
    # 车身：先按折线填，再用「模糊 + 阈值」把角圆化 ——
    # 手写贝塞尔在纯 Pillow 里代价大，而这一步的效果就是「几何但有肉」。
    d.polygon(scaled(CAR, k), fill=255)
    body = body.filter(ImageFilter.GaussianBlur(ROUND_PX))
    body = body.point(lambda v: 255 if v >= 128 else 0)

    holes = Image.new("L", (FIXED, FIXED), 0)
    hd = ImageDraw.Draw(holes)
    for cx, cy in WHEELS:
        r = WHEEL_R
        hd.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=255)
    for x0, y0, x1, y1 in WINDOWS:
        hd.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k],
                             radius=30 * k, fill=255)
    holes = holes.filter(ImageFilter.GaussianBlur(4 * k)).point(lambda v: 255 if v >= 128 else 0)

    mask = Image.eval(body, lambda v: v)
    mp, hp = mask.load(), holes.load()
    for y in range(FIXED):
        for x in range(FIXED):
            if hp[x, y]:
                mp[x, y] = 0

    # 轮毂：挖空之后再把轮子的中心补回来 —— 一个实心洞是「窟窿」，
    # 洞里有芯才是「轮子」。
    hd2 = ImageDraw.Draw(mask)
    for cx, cy in WHEELS:
        r = HUB_R
        hd2.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=255)

    # 弧：App 里「车钉外面那圈弧」（续航圈 / 路径）的图形引用。
    arc = Image.new("L", (FIXED, FIXED), 0)
    ImageDraw.Draw(arc).arc(
        [(ARC_CENTER[0] - ARC_R) * k, (ARC_CENTER[1] - ARC_R) * k,
         (ARC_CENTER[0] + ARC_R) * k, (ARC_CENTER[1] + ARC_R) * k],
        start=ARC_SPAN[0], end=ARC_SPAN[1], fill=255, width=int(ARC_WIDTH * k))
    return mask, arc


def vertical_gradient(top, bottom, size):
    strip = Image.new("RGB", (1, size))
    px = strip.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        px[0, y] = (round(top[0] + (bottom[0] - top[0]) * t),
                    round(top[1] + (bottom[1] - top[1]) * t),
                    round(top[2] + (bottom[2] - top[2]) * t))
    return strip.resize((size, size), Image.NEAREST)


def alpha_gradient(alpha_at_top, alpha_at_bottom, size):
    strip = Image.new("L", (1, size))
    px = strip.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        px[0, y] = round(255 * (alpha_at_top + (alpha_at_bottom - alpha_at_top) * t))
    return strip.resize((size, size), Image.NEAREST)


def render_master(appearance):
    """渲染 1024 主图（**满幅、不透明**）。三个外观共用同一份几何。"""
    spec = APPEARANCES[appearance]
    img = vertical_gradient(spec["bg_top"], spec["bg_bottom"], FIXED)

    glyph = Image.new("RGB", (FIXED, FIXED), spec["glyph"])
    mask, arc = glyph_mask()
    img.paste(glyph, (0, 0), arc.point(lambda v: round(v * spec["arc_alpha"])))
    img.paste(glyph, (0, 0), mask)

    # 玻璃高光：顶上一道渐隐的白。它就是 iOS 26 图标那层「玻璃表面」，
    # 没有它纯渐变会显得平（旧图是靠一圈光晕，那是插画的做法）。
    if spec["sheen"] > 0:
        sheen = alpha_gradient(spec["sheen"], 0.0, FIXED)
        img = Image.composite(Image.new("RGB", (FIXED, FIXED), (255, 255, 255)), img, sheen)

    # 底部压暗：给圆柱感，也让白色车尾不糊在亮底上。
    if spec["shade"] > 0:
        shade = alpha_gradient(0.0, spec["shade"], FIXED)
        img = Image.composite(Image.new("RGB", (FIXED, FIXED), (120, 40, 0)), img, shade)

    return img


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        Path(__file__).resolve().parent / "CarKeeper/Resources/Assets.xcassets/AppIcon.appiconset"
    out_dir.mkdir(parents=True, exist_ok=True)

    masters = {a: render_master(a) for a in APPEARANCES}
    written = 0
    for appearance, master in masters.items():
        for name, size in SLOTS:
            suffix = "" if appearance == "light" else "-" + appearance
            stem, ext = os.path.splitext(name)
            out = out_dir / f"{stem}{suffix}{ext}"
            master.resize((size, size), Image.LANCZOS).save(out, "PNG")
            print(f"  [OK] {out.name}  ({size}x{size}, {appearance})")
            written += 1
    print(f"\n共写出 {written} 个文件（{len(SLOTS)} 槽位 × {len(APPEARANCES)} 外观）")
    print(f"输出目录: {out_dir}")


if __name__ == "__main__":
    main()
