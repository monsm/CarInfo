#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""20 个不同"类型"的 AppIcon 方案 —— 探索用，不是出包来源。

用完即弃（或用户选定后把中选的那个折进 generate_appicon_pillow.py）。
输出：design-preview/icon-20.html（自包含 base64，单页可看）。

20 个方案按"画的是什么物体"分成 20 类，不是 20 个配色：
   1 侧影轿车  2 车头正面  3 鸟瞰俯视  4 导航箭头  5 方向盘
   6 仪表盘    7 电池电量  8 充电枪    9 闪电能量 10 智能钥匙
  11 盾牌守护 12 扳手保养 13 公路透视 14 地图定位 15 续航环
  16 日行灯条 17 轮毂特写 18 单字标识 19 车联网云 20 圆形徽章

几何刻意统一在 1024 坐标系里，几处复用 generate_appicon_pillow.py 的车身多边形
（这样"侧影""盾牌里那台车""云里那台车""徽章里那台车"是同一台车）。
"""
import base64
import io
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W = 1024
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "CarKeeper"))
import generate_appicon_pillow as base  # noqa: E402  复用车身几何与渐变

CAR, WHEELS, WINDOWS = base.CAR, base.WHEELS, base.WINDOWS
WHEEL_R, HUB_R, ROUND_PX = base.WHEEL_R, base.HUB_R, base.ROUND_PX

LIGHT = dict(bg_top=(255, 197, 61), bg_bottom=(255, 118, 26),
             glyph=(255, 255, 255), sheen=0.16, shade=0.10)
DARK = dict(bg_top=(46, 36, 24), bg_bottom=(16, 13, 10),
            glyph=(255, 179, 71), sheen=0.05, shade=0.0)

# 底噪声用来跟生成器对齐：同一个"底"下比较形状才有意义
MONOGRAM = {"char": "车", "font": None}

# =============================================================================
#  遮罩工具
# =============================================================================
def blank():
    return Image.new("L", (W, W), 0)


def union(*masks):
    out = masks[0]
    for m in masks[1:]:
        out = ImageChops.lighter(out, m)
    return out


def sub(main, *holes):
    out = main
    for m in holes:
        out = ImageChops.subtract(out, m)
    return out


def sharpen(m):
    return m.point(lambda v: 255 if v >= 128 else 0)


def poly(points, r=0):
    m = blank()
    ImageDraw.Draw(m).polygon(points, fill=255)
    return sharpen(m.filter(ImageFilter.GaussianBlur(r))) if r else m


def rrect(box, radius):
    m = blank()
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def circle(cx, cy, r):
    return rrect([cx - r, cy - r, cx + r, cy + r], r)


def ring(cx, cy, r, width):
    m = blank()
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r],
                              outline=255, width=width)
    return m


def arc_mask(cx, cy, r, start, end, width):
    m = blank()
    ImageDraw.Draw(m).arc([cx - r, cy - r, cx + r, cy + r],
                          start, end, fill=255, width=width)
    return m


def line_mask(p1, p2, width):
    """带圆头的粗线（Pillow 的 line 没有 LineCap.round，补两个圆）。"""
    m = blank()
    d = ImageDraw.Draw(m)
    d.line([p1, p2], fill=255, width=width)
    for x, y in (p1, p2):
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2],
                  fill=255)
    return m


def car_mask(scale=1.0, center=(512, 576), hubs=True, r=None):
    """复用出包那套车身几何，可缩放/平移。hubs=False 用于「车是挖空」的场合
    —— 那时轮毂点会变成浮在洞里的白点。"""
    rp = (ROUND_PX if r is None else r) * scale
    bw, bh = (868 - 180) * scale, (780 - 372) * scale
    tx = center[0] - bw / 2 - 180 * scale
    ty = center[1] - bh / 2 - 372 * scale
    pts = [(x * scale + tx, y * scale + ty) for x, y in CAR]
    body = poly(pts, rp)

    holes = blank()
    hd = ImageDraw.Draw(holes)
    for cx, cy in WHEELS:
        rr = WHEEL_R * scale
        hd.ellipse([cx * scale + tx - rr, cy * scale + ty - rr,
                    cx * scale + tx + rr, cy * scale + ty + rr], fill=255)
    for x0, y0, x1, y1 in WINDOWS:
        hd.rounded_rectangle([x0 * scale + tx, y0 * scale + ty,
                              x1 * scale + tx, y1 * scale + ty],
                             radius=30 * scale, fill=255)
    body = sub(body, sharpen(holes.filter(ImageFilter.GaussianBlur(4 * scale))))

    if not hubs:
        return body
    hubs_m = blank()
    gd = ImageDraw.Draw(hubs_m)
    for cx, cy in WHEELS:
        rr = HUB_R * scale
        gd.ellipse([cx * scale + tx - rr, cy * scale + ty - rr,
                    cx * scale + tx + rr, cy * scale + ty + rr], fill=255)
    return union(body, hubs_m)


# =============================================================================
#  20 个方案
# =============================================================================
def d01():
    """侧影轿车（= 当前 v2.1）。车 + 底下那道弧，弧淡一档。"""
    car = car_mask(1.0)
    a = arc_mask(base.ARC_CENTER[0], base.ARC_CENTER[1], base.ARC_R,
                 base.ARC_SPAN[0], base.ARC_SPAN[1], base.ARC_WIDTH)
    return car, a


def d02():
    """车头正面：宽车身 + 车顶 + 两盏灯 + 格栅。"""
    body = rrect([170, 470, 854, 790], 120)
    cabin = rrect([336, 336, 688, 520], 92)
    m = union(body, cabin)
    holes = union(rrect([372, 388, 652, 450], 28),      # 风挡
                  rrect([226, 556, 418, 646], 40),       # 左灯
                  rrect([606, 556, 798, 646], 40),       # 右灯
                  rrect([428, 690, 596, 744], 22))       # 格栅
    return sub(m, holes), None


def d03():
    """鸟瞰俯视：纵向车身 + 四个轮包 + 前后风挡 + 车头箭头。"""
    body = rrect([300, 170, 724, 860], 180)
    wheels = union(rrect([244, 318, 320, 450], 38), rrect([704, 318, 780, 450], 38),
                   rrect([244, 598, 320, 730], 38), rrect([704, 598, 780, 730], 38))
    m = union(body, wheels)
    holes = union(poly([(348, 298), (676, 298), (648, 444), (376, 444)], 16),
                  poly([(376, 588), (648, 588), (676, 734), (348, 734)], 16),
                  poly([(452, 198), (572, 198), (512, 272)], 8))
    return sub(m, holes), None


def d04():
    """导航箭头（定位符号）。"""
    return poly([(512, 122), (836, 902), (512, 700), (188, 902)], 24), None


def d05():
    """方向盘：外圈 + 中心毂 + 三根辐条。"""
    outer = ring(512, 512, 352, 88)
    spokes = union(line_mask((512, 512), (512, 190), 80),
                   line_mask((512, 512), (218, 682), 80),
                   line_mask((512, 512), (806, 682), 80))
    return union(outer, spokes, circle(512, 512, 118)), None


def d06():
    """仪表盘：上开口弧 + 指针 + 五根刻度 + 轴心。"""
    outer = arc_mask(512, 512, 366, 205, 335, 60)
    ticks = blank()
    for deg in (205, 237, 270, 303, 335):
        rad = math.radians(deg)
        x1, y1 = 512 + 262 * math.cos(rad), 512 + 262 * math.sin(rad)
        x2, y2 = 512 + 322 * math.cos(rad), 512 + 322 * math.sin(rad)
        ticks = union(ticks, line_mask((x1, y1), (x2, y2), 20))
    needle = line_mask((512, 664), (742, 344), 54)
    return union(outer, ticks, needle, circle(512, 664, 70)), None


def d07():
    """电池电量：外框 + 右侧端子 + 左侧电量条。"""
    frame = sub(rrect([176, 370, 762, 654], 80), rrect([228, 422, 710, 602], 46))
    bar = rrect([272, 452, 556, 572], 34)
    nub = rrect([762, 460, 832, 564], 32)
    return union(frame, bar, nub), None


def d08():
    """充电枪：枪体 + 两个插脚 + 一段线缆。"""
    body = rrect([248, 396, 604, 664], 76)
    prongs = union(rrect([604, 448, 764, 506], 28), rrect([604, 554, 764, 612], 28))
    cable = line_mask((248, 530), (110, 782), 66)
    return union(body, prongs, cable), None


def d09():
    """闪电（能量符号）。"""
    return poly([(614, 140), (316, 584), (506, 584), (452, 884),
                 (724, 436), (534, 436)], 18), None


def d10():
    """智能钥匙：钥匙胚 + 遥控器身 + 环孔 + 两枚按键。"""
    blade = rrect([470, 196, 562, 440], 36)
    body = rrect([352, 392, 676, 832], 118)
    return sub(union(blade, body),
               circle(514, 520, 62), circle(452, 690, 34), circle(576, 690, 34)), None


def d11():
    """盾牌守护：盾 + 挖空的车。"""
    sh = poly([(196, 286), (828, 286), (828, 596), (512, 904), (196, 596)], 44)
    return sub(sh, car_mask(0.54, center=(512, 566), hubs=False)), None


def d12():
    """扳手（保养）：闭环端 + 杆 + 开口端，整体转 -38°。"""
    shaft = rrect([296, 452, 764, 572], 60)
    closed = ring(340, 512, 186, 100)
    opened = sub(ring(790, 512, 186, 100), rrect([782, 408, 1060, 616], 0))
    m = union(shaft, closed, opened)
    m = m.rotate(-38, resample=Image.BICUBIC, center=(512, 512), fillcolor=0)
    return sharpen(m), None


def d13():
    """公路透视：收敛的路面 + 四条虚线。"""
    road = poly([(310, 908), (714, 908), (570, 292), (454, 292)], 28)
    dashes = blank()
    for y, hw in ((822, 26), (688, 21), (554, 16), (420, 11)):
        dashes = union(dashes, rrect([512 - hw, y, 512 + hw, y + 72], hw))
    return sub(road, dashes), None


def d14():
    """地图定位：水滴针 + 中间的孔。"""
    tail = poly([(512, 936), (326, 604), (698, 604)], 44)
    return sub(union(circle(512, 430, 238), tail), circle(512, 430, 98)), None


def d15():
    """续航环：上开口大环 + 末端那颗亮点（= 车在环上的位置）。"""
    a = arc_mask(512, 512, 384, 205, 335, 58)
    rad = math.radians(335)
    dot = circle(int(512 + 384 * math.cos(rad)), int(512 + 384 * math.sin(rad)), 68)
    return a, dot


def d16():
    """日行灯条：一条光带 + 一枚灯点，上面一道更细的余光。"""
    bar = union(rrect([148, 468, 664, 558], 46), circle(796, 513, 86))
    return bar, rrect([148, 386, 452, 424], 20)


def d17():
    """轮毂特写：轮胎 + 轮辋 + 中心毂 + 五根辐条。"""
    tire = ring(512, 512, 390, 118)
    rim = ring(512, 512, 244, 60)
    spokes = blank()
    for k in range(5):
        rad = math.radians(-90 + k * 72)
        spokes = union(spokes, line_mask(
            (512, 512), (512 + 244 * math.cos(rad), 512 + 244 * math.sin(rad)), 72))
    return union(tire, rim, spokes, circle(512, 512, 76)), None


def d18():
    """单字标识：一个沉的字 + 底下那道弧。"""
    m = blank()
    if MONOGRAM["font"] is not None:
        ImageDraw.Draw(m).text((512, 470), MONOGRAM["char"], font=MONOGRAM["font"],
                               fill=255, anchor="mm")
    a = arc_mask(512, 640, 300, 30, 150, 26)
    return union(m, a), None


def d19():
    """车联网云：云里挖出一台车。"""
    cloud = union(circle(340, 470, 152), circle(512, 392, 192),
                  circle(690, 470, 152), rrect([340, 470, 690, 612], 0))
    return sub(cloud, car_mask(0.40, center=(512, 512), hubs=False)), None


def d20():
    """圆形徽章：实心圆里挖出一台车。"""
    return sub(circle(512, 512, 420),
               car_mask(0.72, center=(512, 524), hubs=False)), None


DESIGNS = [
    ("侧影轿车", "当前版本：车 + 底下那道弧", d01),
    ("车头正面", "正面看车：车顶 / 风挡 / 两盏灯 / 格栅", d02),
    ("鸟瞰俯视", "从上看：纵向车身 + 四个轮包 + 车头箭头", d03),
    ("导航箭头", "定位符号，最简的一个", d04),
    ("方向盘", "外圈 + 三根辐条 + 中心毂", d05),
    ("仪表盘", "上开口弧 + 指针 + 五根刻度", d06),
    ("电池电量", "外框 + 端子 + 电量条", d07),
    ("充电枪", "枪体 + 两个插脚 + 一段线缆", d08),
    ("闪电能量", "纯能量符号，最容易认", d09),
    ("智能钥匙", "钥匙胚 + 遥控器 + 环孔 + 按键", d10),
    ("盾牌守护", "盾里挖出一台车", d11),
    ("扳手保养", "闭环端 + 杆 + 开口端，斜放", d12),
    ("公路透视", "收敛的路面 + 四条虚线", d13),
    ("地图定位", "水滴形针 + 中间的孔", d14),
    ("续航环", "上开口大环 + 末端亮点", d15),
    ("日行灯条", "一条光带 + 一枚灯点", d16),
    ("轮毂特写", "轮胎 + 轮辋 + 五根辐条", d17),
    ("单字标识", "一个沉的字 + 底下那道弧", d18),
    ("车联网云", "云里挖出一台车", d19),
    ("圆形徽章", "实心圆里挖出一台车", d20),
]


# =============================================================================
#  渲染 / 校验
# =============================================================================
def render(fn, pal):
    img = base.vertical_gradient(pal["bg_top"], pal["bg_bottom"], W)
    main, accent = fn()
    glyph = Image.new("RGB", (W, W), pal["glyph"])
    if accent is not None:
        img.paste(glyph, (0, 0), accent.point(lambda v: round(v * 0.30)))
    img.paste(glyph, (0, 0), main)
    if pal["sheen"] > 0:
        img = Image.composite(Image.new("RGB", (W, W), (255, 255, 255)), img,
                              base.alpha_gradient(pal["sheen"], 0.0, W))
    if pal["shade"] > 0:
        img = Image.composite(Image.new("RGB", (W, W), (120, 40, 0)), img,
                              base.alpha_gradient(0.0, pal["shade"], W))
    return img


def sig(img):
    return list(img.convert("L").resize((32, 32), Image.BOX).tobytes())


def data_uri(img, size, colors=None):
    """缩到展示尺寸。**不量化**：试过 192 色，最大单通道偏差到 42 ——
    那是给「挑外观」用的图，不该让用户在看一个带抖动的近似版。
    靠尺寸控制体积就够（浅色 512 用于 200px 展示，深色只出现在 60px 位）。"""
    small = img.resize((size, size), Image.LANCZOS)
    if colors:
        small = small.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
    buf = io.BytesIO()
    small.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def ascii_art(fn, pal, n=44):
    main, _ = fn()
    m = main.resize((n, n // 2), Image.BOX)
    ramp = " .:-=+*#%@"
    px = list(m.getdata())
    lines = []
    for y in range(n // 2):
        lines.append("".join(ramp[min(9, v * 10 // 256)]
                             for v in px[y * n:(y + 1) * n]))
    return "\n".join(lines)


def load_font(size):
    for c in ("C:/Windows/Fonts/msyhbd.ttc", "C:/Windows/Fonts/msyh.ttc",
              "C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/arialbd.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if Path(c).exists():
            try:
                f = ImageFont.truetype(c, size)
                return f, ("车" if "msyh" in c or "simhei" in c else "C")
            except Exception:
                pass
    return None, "C"


# =============================================================================
#  HTML
# =============================================================================
CSS = """
*{box-sizing:border-box}
body{margin:0;padding:44px 36px 90px;background:#0b0d12;color:#e8ecf3;
     font:400 14px/1.65 -apple-system,"Segoe UI",system-ui,sans-serif}
h1{font-size:25px;font-weight:600;margin:0 0 6px;letter-spacing:-.01em}
h2{font-size:16px;font-weight:600;margin:52px 0 6px;padding-top:22px;
   border-top:1px solid #242b36}
.lead{color:#9aa4b4;max-width:80ch}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:22px;margin-top:22px}
.card{background:#151922;border:1px solid #242b36;border-radius:18px;padding:18px}
.card .head{display:flex;align-items:baseline;gap:8px;margin-bottom:12px}
.card .no{font:600 13px ui-monospace,Consolas,monospace;color:#ff9f00;
          background:#2a2113;border-radius:7px;padding:2px 7px}
.card .nm{font-size:15px;font-weight:600}
.card .ds{color:#9aa4b4;font-size:12.5px;margin-top:10px;line-height:1.5}
.big{border-radius:22.4%;overflow:hidden;display:block;width:200px;height:200px;
     margin:0 auto}
.strip{display:flex;gap:14px;align-items:center;margin-top:14px;
       background:linear-gradient(160deg,#161b26,#0d1016);border-radius:12px;
       padding:11px 13px}
.strip span{font-size:10.5px;color:#6b7484;line-height:1.35}
.ic{border-radius:22.4%;overflow:hidden;display:block;flex:none}
.row{display:flex;gap:26px;flex-wrap:wrap;align-items:flex-start;margin-top:18px}
.tiny{display:flex;gap:22px;flex-wrap:wrap;margin-top:16px}
.tiny .t{display:flex;flex-direction:column;align-items:center;gap:7px}
.tiny .t em{font-style:normal;font-size:10.5px;color:#9aa4b4}
.nb{width:60px;height:60px;border-radius:22.4%;
    background:linear-gradient(160deg,#4b5563,#2b313b);flex:none}
table{border-collapse:collapse;margin-top:14px;font-size:13px}
th,td{border:1px solid #242b36;padding:7px 12px;text-align:left}
th{color:#9aa4b4;font-weight:500;background:#151922}
.ok{color:#5ad19a}.bad{color:#ff6b6b}
code{font-family:ui-monospace,Consolas,monospace;color:#cfd8e6}
"""


def build_html(pairs, rows):
    # 同一张图在页面上出现三次（大图 / 60pt 条 / 60pt 总览），但 base64 是**字面文本**
    # —— 直接复用同一个 512 字符串会让整页重复三遍。所以每种用法各存一个够用的尺寸。
    cards = []
    for i, ((name, desc, _fn), (big, small, dsmall)) in enumerate(pairs, 1):
        cards.append(f"""  <div class="card">
    <div class="head"><span class="no">{i:02d}</span><span class="nm">{name}</span></div>
    <img class="big" src="{big}" alt="{name}">
    <div class="strip">
      <img class="ic" style="width:60px;height:60px" src="{small}">
      <img class="ic" style="width:60px;height:60px" src="{dsmall}">
      <span>60pt 真实尺寸<br>左 浅色 / 右 深色</span>
    </div>
    <div class="ds">{desc}</div>
  </div>""")

    tiny = "\n".join(
        f'    <div class="t"><img class="ic" style="width:60px;height:60px" '
        f'src="{small}"><em>{i:02d}</em></div>'
        for i, ((name, _d, _f), (big, small, dsmall)) in enumerate(pairs, 1))

    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CarKeeper · 20 个图标方向，挑一个</title>
<style>{CSS}</style>
</head>
<body>

<h1>20 个图标方向</h1>
<p class="lead">20 个方案按<b>「画的是什么」</b>分成 20 类 —— 不是同一台车换 20 个颜色。
每一版都渲了浅色与深色两套，右边那一小块是它的 <b>60pt 真实主屏尺寸</b>（左浅右深）。<br>
挑的方式：告诉我编号就行（可以多个）。选定后我会把它折进出包渲染器，
补齐浅色 / 深色 / 着色三套外观与全部 7 个槽位，并过 <code>scan/iconcheck.py</code>。</p>

<h2>全部 20 个 · 160px</h2>
<div class="grid">
{chr(10).join(cards)}
</div>

<h2>全部 20 个 · 60pt 真实尺寸（塞在邻居中间）</h2>
<p class="lead">图标大多数时间只有这么大。这一排是最该看的一排。</p>
<div class="tiny">
    <div class="t"><div class="nb"></div><em>邻居</em></div>
{tiny}
    <div class="t"><div class="nb"></div><em>邻居</em></div>
</div>

<h2>这些方案真的两两不同吗（量出来的）</h2>
<p class="lead">按 32×32 灰度签名两两比 L1 距离，最小的那一对就是最像的两个；
「覆盖率」是图形占画布的比例，用来确认每张真的画出来了、也没糊成一片。</p>
<table>
  <tr><th>方案</th><th>图形覆盖率</th><th>判读</th></tr>
{rows}
  <tr><th colspan="3">最小两两差异（L1，32×32 灰度）：MIN_PAIR ／ 上限 261120</th></tr>
</table>

<h2>边界的几句话</h2>
<p class="lead">① 这一页是 Pillow 直出的，不是 Xcode 打的包；圆角用 CSS 22.4% 近似系统 squircle。<br>
② 每个方案都能补齐浅色 / 深色 / 着色三套（着色外观由灰阶推导，系统按亮度上色）。<br>
③ 「相同的那几台车」是真的同一套几何：侧影、盾牌、云、徽章里的车是同一个多边形，
所以中选后几何是现成的。</p>

</body>
</html>
"""


def main():
    font, char = load_font(560)
    MONOGRAM["font"], MONOGRAM["char"] = font, char
    print(f"单字标识用的字：{char}（字体 {'找到' if font else '缺失，回退'}）\n")

    pairs, sigs, stats = [], [], []
    for name, desc, fn in DESIGNS:
        light, dark = render(fn, LIGHT), render(fn, DARK)
        main, _ = fn()
        cov = sum(main.tobytes()) / (W * W * 255) * 100
        pairs.append(((name, desc, fn), (data_uri(light, 384),   # 200px 展示
                                         data_uri(light, 120),   # 60pt 条
                                         data_uri(dark, 120))))  # 60pt 深色
        sigs.append(sig(light))
        stats.append((cov, ""))

    min_pair, min_which = 10 ** 9, None
    for i in range(len(sigs)):
        for j in range(i + 1, len(sigs)):
            d = sum(abs(a - b) for a, b in zip(sigs[i], sigs[j]))
            if d < min_pair:
                min_pair, min_which = d, (i + 1, j + 1)

    stats = [(cov, "覆盖率 OK" if 4 <= cov <= 70 else "⚠ 覆盖率异常")
             for cov, _ in stats]
    for i, (cov, note) in enumerate(stats, 1):
        print(f"  {i:02d} {DESIGNS[i-1][0]:<8} 覆盖 {cov:5.1f}%  {note}")

    rows = "\n".join(
        f"  <tr><td>{i:02d} {DESIGNS[i-1][0]}</td><td>{cov:.1f}%</td>"
        f"<td>{note}</td></tr>"
        for i, (cov, note) in enumerate(stats, 1))
    html = build_html(pairs, rows).replace("MIN_PAIR", str(min_pair))
    out = ROOT / "design-preview" / "icon-20.html"
    out.write_text(html, encoding="utf-8")

    print(f"\n最小两两差异 = {min_pair}（第 {min_which[0]} 与第 {min_which[1]} 最像）")
    print(f"写出 {out}  ({out.stat().st_size / 1024:.0f} KB)")

    # 几个"能不能读出来"存疑的，直接在终端看一眼
    for idx in (8, 12, 13, 16):
        name, _d, fn = DESIGNS[idx - 1]
        print(f"\n--- {idx:02d} {name} ---")
        print(ascii_art(fn, LIGHT))


if __name__ == "__main__":
    main()
