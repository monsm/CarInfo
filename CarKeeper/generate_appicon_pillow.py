#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""generate_appicon_pillow.py — 出包用的 AppIcon 渲染器（**唯一来源**）

用法：
    python3 generate_appicon_pillow.py                 # 写出到 appiconset
    python3 generate_appicon_pillow.py <输出目录>       # 写到别处（用来对照，不进包）

v3.0（2026-09-25）：用户在 100 个探索方向里挑了 **040「两厢 · 纸白底」**
（`design-preview/icon-100.html` 那批；选完就随稿删掉了，见 `AppIcon-SPEC.md`）。
这一版就是把 040 折进来 —— 它长什么样：**浅灰白底 + 一台深墨色的两厢侧影**，
车身满铺，车轮与车窗是**挖空**（透出底色），底下一层柔影、上面一层很淡的白高光。

与 v2.1（同一份文件的上一个版本）的差别 —— 每一条都是「用户选中的不是那个」：

  · **车形**：轿车 → 两厢。车身 934 × 473，占画布宽 91%、高 46%（v2.1 是 689 × 409）。
  · **底色**：琥珀→橙 → 纸白 #F9FAFC→#E2E7F0；车身从白 → 墨色 #161A22。
    亮底 + 一个深色物体，也是 iOS 图标语言里最常见的那一种搭配。
  · **v2.1 那道「车底下的路」（`ARC_*`）删掉**：040 里没有它。它不是不好，
    是用户挑的那一张没有 —— 折进来的东西与被挑中的东西必须长得一样。
  · 没变的两点：一层白高光 + 一层柔影（040 的 treatment 原样就是 gloss + shadow）。

几何全部写在 `CAR` / `WHEELS` / `WINDOWS` 里，单位是 1024 的坐标系；
改形状只改那几个常量（与 `AppIcon.svg` 是同一套几何，见 `AppIcon-SPEC.md`）。

与探索稿 040 的**逐点比对**（同一张 1024、同一套画法）：99.76% 的像素完全相同，
余下的是轮廓上 ±0.5px 的取整（最大色差 199，全部落在 1px 宽的车身边缘上）——
本文件的常数是取整过的整数（给人改形状用），把映射的原值写进来则是 0 处差异。
柔影的位移是这里唯一会「整体错一点」的参数，量出来的正确值是 22（见 `SHADOW_DY`）。

为什么是 Pillow 而不是 SVG 出包：这台机器没有 ImageMagick、也没有 cairosvg，
而 SVG 只能渲一套外观（浅色）—— 用它刷新会得到「一半新图一半旧图」的图标集，
正是这个仓库记过的那个坑（改了 A，真机上看到 B）。见 `generate_appicon.sh`。
"""
import os
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# =============================================================================
#  几何（1024 坐标系）
# =============================================================================
#
#  车头朝右的**两厢**侧影（探索稿里的 `hatch`）。折线一律从「后保险杠下角」起，
#  沿车顶绕到「前保险杠下角」，再沿底边回来 —— 下面每个点都标了它是车身哪一处。
#
#  这一组数是**映射出来的，不是画出来的**：探索稿把它写在 0…1 的方框里
# （`frac=0.60 × 1.52 = 0.912`，长高比 0.593），再映到 1024 的画布 ——
#  于是同一个形状在 100 个方向里能换容器、换尺寸而不改一个数。折进来时把映射结果
#  写成常数（保留 1024 这一个坐标系），逐点与探索稿比对过：见 `AppIcon-SPEC.md`。
CAR = [
    (45, 789),    # 后保险杠下
    (45, 612),    # 后保险杠上（尾门竖直的那一段）
    (101, 512),   # 尾门折角
    (232, 346),   # C 柱（两厢的尾巴是立着的，这一折不能省）
    (512, 313),   # 车顶
    (680, 368),   # A 柱
    (811, 490),   # 引擎盖
    (904, 534),   # 车鼻
    (979, 623),   # 车鼻下
    (979, 789),   # 前保险杠下
]
# 轮心必须满足 `cy + R ≤ 车底线（789）`：一旦超出，轮毂（圆心那一小块）就会从
# 车身下缘探出去、飘在底色上（v2.0 实测过：cy=700、R=84 时每个轮子下面露出 32 单位）。
WHEELS = [(236, 720), (778, 720)]
WHEEL_R = 135
HUB_R = 49
# 窗必须落在**车厢内部**（车身折线在每个 y 上的左右边界之间）—— 越界会在车身边上
# 咬出一个缺口。车厢在 y=430 处大约跨 x 250…700，所以窗从 283 排到 680；
# 两扇之间的 B 柱留 42（58pt 下约 2.4px，再窄缩小时就糊成一扇）。
WINDOWS = [(283, 376, 484, 484), (526, 376, 680, 484)]
ROUND_PX = 21          # 车身折线的圆化：用「模糊 + 阈值」实现，避免手写圆弧
HOLE_BLUR = 6          # 挖空（窗与轮拱）也走同一条路 —— 直角在 58pt 下会扎眼
WINDOW_R = 30          # 窗自己的圆角（挖空之后仍要留一点弧度）

# 柔影与高光的量（探索稿 `apply_treatment` 的 gloss + shadow）。
# 影子是**同一张形状往下偏一点、模糊后再压 30% 黑** —— 不是描边、不是投影贴图；
# 它给的是「这东西离底有一点点距离」，纯渐变没有它就会像贴纸。
SHADOW_DX = 6      # = int(1024 × 0.006)
SHADOW_DY = 22     # = int(1024 × 0.022)。**这里是 22，不是 23** —— 探索稿那一版
                   #   走的是 `int(size × 0.022)`，写成 23 会让影子整体下移 1px。
                   #   这一条是逐点比对时量出来的：22 时只有 174 个像素有差（最大 1），
                   #   23 时有 89485 个（最大 2）—— 数字不会说谎，眼睛看不出来。
SHADOW_BLUR = 18   # = int(1024 × 0.018)
GLOSS_ALPHA = 0.12     # 与柔影搭伴的顶光只给一半（影子已经在做立体感了）

# =============================================================================
#  三套外观
# =============================================================================
#
#  一律给 RGB（不带 alpha）：图标的形状由系统遮罩裁，我们只负责画面内容。
APPEARANCES = {
    # 浅色：纸白底 + 墨色车。就是 040 原样（也是这套图标语言里最稳的搭配）。
    "light": dict(bg_top=(249, 250, 252), bg_bottom=(226, 231, 240),
                  glyph=(22, 26, 34), shadow=0.30, gloss=0.12),
    # 深色：暖近黑底 + 白车 —— 深色外观在系统里本来就是「换底 + 调图形」，
    # 只换底会让墨色的车直接看不见（探索稿的 `dark_preview` 就是这个判据：
    # 车身亮度 < 128 → 深色下转白）。
    "dark": dict(bg_top=(46, 36, 24), bg_bottom=(16, 13, 10),
                 glyph=(255, 255, 255), shadow=0.30, gloss=0.12),
    # 着色：系统按**亮度**上色，所以这里只给灰阶（白车 + 中灰底）。
    # 底偏暗而不是偏亮：着色外观下系统给整张图上一层色，亮底会变成一大块实色。
    "tinted": dict(bg_top=(126, 126, 132), bg_bottom=(62, 62, 68),
                   glyph=(255, 255, 255), shadow=0.30, gloss=0.08),
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


def glyph_mask():
    """返回车身 mask（一张 L 图，255 = 画在这里）。

    步骤是有顺序的，顺序本身就是内容：**先挖空、再补回轮毂** ——
    一个实心洞是「窟窿」，洞里有芯才是「轮子」。窗与轮拱挖出来的地方透的是底色，
    不是一层更深的灰：它们必须是**底色**，否则一旦换外观（深色 / 着色）
    那两个洞就会留在原来的颜色上。
    """
    body = Image.new("L", (FIXED, FIXED), 0)
    ImageDraw.Draw(body).polygon(CAR, fill=255)
    # 「模糊 + 阈值」= 把折线的尖角换成有肉的圆角。手写贝塞尔在纯 Pillow 里代价大，
    # 而这一步的效果就是「几何但有肉」。
    body = body.filter(ImageFilter.GaussianBlur(ROUND_PX)).point(lambda v: 255 if v >= 128 else 0)

    holes = Image.new("L", (FIXED, FIXED), 0)
    hd = ImageDraw.Draw(holes)
    for cx, cy in WHEELS:
        hd.ellipse([cx - WHEEL_R, cy - WHEEL_R, cx + WHEEL_R, cy + WHEEL_R], fill=255)
    for x0, y0, x1, y1 in WINDOWS:
        hd.rounded_rectangle([x0, y0, x1, y1], radius=WINDOW_R, fill=255)
    holes = holes.filter(ImageFilter.GaussianBlur(HOLE_BLUR)).point(lambda v: 255 if v >= 128 else 0)

    mask = ImageChops.subtract(body, holes)

    # 轮毂：挖空之后再把轮子的中心补回来。
    hubs = Image.new("L", (FIXED, FIXED), 0)
    hub_draw = ImageDraw.Draw(hubs)
    for cx, cy in WHEELS:
        hub_draw.ellipse([cx - HUB_R, cy - HUB_R, cx + HUB_R, cy + HUB_R], fill=255)
    return ImageChops.lighter(mask, hubs)


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


def offset_mask(mask, dx, dy):
    """平移一张 mask。**不用 `ImageChops.offset`** —— 它会环绕，把底边那一溜
    搬到顶上去（探索稿里的影子与倒影都被它咬过一次）。
    这里平移量固定为正（往下、往右），所以 `paste` 不会有别的问题。
    """
    out = Image.new("L", (FIXED, FIXED), 0)
    out.paste(mask, (int(dx), int(dy)))
    return out


def render_master(appearance):
    """渲染 1024 主图（**满幅、不透明**）。三个外观共用同一份几何。"""
    spec = APPEARANCES[appearance]
    img = vertical_gradient(spec["bg_top"], spec["bg_bottom"], FIXED)
    mask = glyph_mask()

    # 柔影：先铺影子，再把车身压上去 —— 顺序反了影子会盖在车身上。
    if spec["shadow"] > 0:
        sh = offset_mask(mask, SHADOW_DX, SHADOW_DY).filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
        img = Image.composite(Image.new("RGB", (FIXED, FIXED), (0, 0, 0)), img,
                              sh.point(lambda v: round(v * spec["shadow"])))

    glyph = Image.new("RGB", (FIXED, FIXED), spec["glyph"])
    img.paste(glyph, (0, 0), mask)

    # 顶光：一道渐隐的白。它就是 iOS 26 图标那层「玻璃表面」，
    # 没有它纯渐变会显得平（旧版是靠一圈光晕，那是插画的做法）。
    if spec["gloss"] > 0:
        sheen = alpha_gradient(spec["gloss"], 0.0, FIXED)
        img = Image.composite(Image.new("RGB", (FIXED, FIXED), (255, 255, 255)), img, sheen)

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
