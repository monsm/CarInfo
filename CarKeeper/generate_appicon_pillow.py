#!/usr/bin/env python3
"""generate_appicon_pillow.py — 用 Pillow 纯 Python 生成 AppIcon 所有尺寸变体"""
import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ---------- 颜色 ----------
BG_DARK    = (26, 26, 46)    # #1A1A2E
BG_DEEP    = (13, 13, 26)    # #0D0D1A
AMBER_LIGHT= (255, 179, 71)  # #FFB347
AMBER_MAIN = (255, 159, 0)   # #FF9F00
AMBER_DARK = (217, 115, 0)   # #D97300
WHITE      = (255, 255, 255)
GRAY       = (80, 80, 100)
HEADLIGHT  = (255, 250, 240)
TAILLIGHT  = (255, 60, 40)

OUTPUT_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("AppIcon")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ---------- 工具 ----------
def lerp(a, b, t): return int(a + (b - a) * t)
def lerp_color(c1, c2, t): return (lerp(c1[0],c2[0],t), lerp(c1[1],c2[1],t), lerp(c1[2],c2[2],t))

def draw_gradient_rect(draw, xy, colors, vertical=True):
    x0,y0,x1,y1 = xy
    if vertical:
        for y in range(y0, y1):
            t = (y - y0) / max(y1 - y0, 1)
            c = lerp_color(colors[0], colors[-1], t)
            # use finer steps for smooth gradient
            draw.line([(x0,y),(x1,y)], fill=c)
    else:
        for x in range(x0, x1):
            t = (x - x0) / max(x1 - x0, 1)
            c = lerp_color(colors[0], colors[-1], t)
            draw.line([(x,y0),(x,y1)], fill=c)

def rounded_rect(draw, xy, radius, fill):
    x0,y0,x1,y1 = xy
    r = min(radius, (x1-x0)//2, (y1-y0)//2)
    draw.rectangle([x0+r, y0, x1-r, y1], fill=fill)
    draw.rectangle([x0, y0+r, x1, y1-r], fill=fill)
    draw.pieslice([x0,y0,x0+2*r,y0+2*r], 180, 270, fill=fill)
    draw.pieslice([x1-2*r,y0,x1,y0+2*r], 270, 360, fill=fill)
    draw.pieslice([x0,y1-2*r,x0+2*r,y1], 90, 180, fill=fill)
    draw.pieslice([x1-2*r,y1-2*r,x1,y1], 0, 90, fill=fill)

def draw_car_silhouette(draw, cx, cy, scale):
    """Drawing a sleek EV sedan silhouette centered at (cx,cy)"""
    # Car body path (simplified as filled polygon)
    # Lower body
    body_pts = [
        (cx-200*scale, cy+60*scale),     # left rear bumper bottom
        (cx-200*scale, cy+20*scale),     # left rear
        (cx-180*scale, cy-10*scale),     # rear slope
        (cx-100*scale, cy-50*scale),     # trunk
        (cx-60*scale, cy-80*scale),      # C-pillar top
        (cx-20*scale, cy-100*scale),     # roof rear
        (cx+40*scale, cy-108*scale),     # roof peak
        (cx+100*scale, cy-100*scale),    # roof front
        (cx+140*scale, cy-70*scale),     # A-pillar
        (cx+170*scale, cy-30*scale),     # hood start
        (cx+200*scale, cy+10*scale),     # hood
        (cx+210*scale, cy+20*scale),     # front bumper top
        (cx+210*scale, cy+60*scale),     # front bumper bottom
        (cx+170*scale, cy+60*scale),     # front wheel arch top
        (cx+170*scale, cy+80*scale),     # front wheel bottom
        (cx+140*scale, cy+80*scale),     # wheel well right
        (cx+140*scale, cy+60*scale),     # lower body right
        (cx+60*scale, cy+60*scale),      # middle lower
        (cx-60*scale, cy+60*scale),      # middle lower left
        (cx-140*scale, cy+60*scale),     # rear lower
        (cx-140*scale, cy+80*scale),     # rear wheel bottom
        (cx-170*scale, cy+80*scale),     # rear wheel arch bottom
        (cx-170*scale, cy+60*scale),     # rear wheel arch top
        (cx-200*scale, cy+60*scale),     # back to start
    ]
    draw.polygon(body_pts, fill=AMBER_MAIN)
    
    # Roof/window area (darker glass)
    roof_pts = [
        (cx-60*scale, cy-50*scale),
        (cx-20*scale, cy-100*scale),
        (cx+40*scale, cy-108*scale),
        (cx+100*scale, cy-100*scale),
        (cx+130*scale, cy-65*scale),
        (cx+120*scale, cy-50*scale),
        (cx-50*scale, cy-50*scale),
    ]
    draw.polygon(roof_pts, fill=(30, 30, 50))
    
    # Wheel arches
    for wx in [cx-155*scale, cx+155*scale]:
        draw.ellipse([wx-30*scale, cy+30*scale, wx+30*scale, cy+80*scale], fill=(20, 20, 30))
        # Tire
        draw.ellipse([wx-28*scale, cy+32*scale, wx+28*scale, cy+78*scale], fill=(15, 15, 25))
        # Rim
        draw.ellipse([wx-16*scale, cy+42*scale, wx+16*scale, cy+68*scale], fill=(60, 60, 80))
        # Hub
        draw.ellipse([wx-6*scale, cy+50*scale, wx+6*scale, cy+60*scale], fill=(100, 100, 120))
    
    # Headlights (glowing white)
    hl_y = cy + 5*scale
    draw.ellipse([cx+195*scale, hl_y-6*scale, cx+208*scale, hl_y+8*scale], fill=HEADLIGHT)
    draw.ellipse([cx+193*scale, hl_y-8*scale, cx+210*scale, hl_y+10*scale], fill=(255,255,255,80))
    
    # Tail lights (red glow)
    tl_y = cy + 10*scale
    draw.rectangle([cx-208*scale, tl_y-4*scale, cx-195*scale, tl_y+6*scale], fill=TAILLIGHT)
    
    # Amber accent line along body
    accent_pts = [
        (cx-195*scale, cy+15*scale),
        (cx-100*scale, cy-5*scale),
        (cx+100*scale, cy-5*scale),
        (cx+195*scale, cy+15*scale),
    ]
    # Draw as thick line
    for i in range(len(accent_pts)-1):
        x1,y1 = accent_pts[i]
        x2,y2 = accent_pts[i+1]
        for w in range(2, 5):
            alpha = max(0, 255 - w*50)
            draw.line([(x1,y1),(x2,y2)], fill=(AMBER_LIGHT[0], AMBER_LIGHT[1], AMBER_LIGHT[2], alpha), width=w)

def make_icon(size):
    """Create a single icon image at the given size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Background: dark rounded rect filling the whole canvas
    margin = int(size * 0.04)
    bg_w = size - margin * 2
    bg_h = size - margin * 2
    corner_r = int(size * 0.21)  # ~220/1024 ≈ 0.215
    
    # Draw rounded background
    draw.rounded_rectangle([margin, margin, margin+bg_w, margin+bg_h], 
                           radius=corner_r, fill=BG_DEEP)
    
    # Subtle gradient overlay
    for y in range(margin, margin + bg_h):
        t = (y - margin) / bg_h
        c = lerp_color(BG_DARK, BG_DEEP, t)
        draw.line([(margin, y), (margin + bg_w, y)], fill=c)
    
    # Center car
    cx, cy = size // 2, size // 2 + int(size * 0.03)
    scale = size / 400.0  # base scale factor
    
    # Glow behind car
    glow_radius = int(size * 0.25)
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse([cx-glow_radius, cy-glow_radius, cx+glow_radius, cy+glow_radius],
                       fill=(AMBER_MAIN[0], AMBER_MAIN[1], AMBER_MAIN[2], 20))
    glow_blur = glow.filter(ImageFilter.GaussianBlur(radius=int(size*0.06)))
    img.paste(glow_blur, (0, 0), glow_blur)
    
    # Second glow ring
    glow2 = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    glow2_draw = ImageDraw.Draw(glow2)
    r2 = int(size * 0.18)
    glow2_draw.ellipse([cx-r2, cy-r2, cx+r2, cy+r2],
                        fill=(AMBER_DARK[0], AMBER_DARK[1], AMBER_DARK[2], 35))
    glow2b = glow2.filter(ImageFilter.GaussianBlur(radius=int(size*0.04)))
    img.paste(glow2b, (0, 0), glow2b)
    
    # Draw car silhouette
    draw_car_silhouette(draw, cx, cy, scale)
    
    # Brand text at bottom
    try:
        font_size = max(int(size * 0.06), 10)
        font = ImageFont.truetype("arial.ttf", font_size)
    except:
        font = ImageFont.load_default()
    
    text = "CHANGAN"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    tx = (size - tw) // 2
    ty = margin + bg_h - int(size * 0.08) - th
    draw.text((tx, ty), text, fill=AMBER_MAIN, font=font)
    
    return img.convert('RGB')

def main():
    # 只生成 Contents.json 真正引用的七个槽位。
    #
    # 原来的 12 个里多出的五个是 1x（29×29 / 40×40 / 76×76）与 iPad 专属
    # （76×76@2x / 83.5×83.5@2x）：前者在本项目的最低系统（iOS 26，全部支持机型
    # 都是 @2x/@3x）上没有任何消费者，后者会被 actool 记成
    # 「AppIcon has N unassigned children」而**忽略**（iPad 图标由 1024 自动生成，
    # 详见 AppIcon-SPEC.md）。生成出来只会是没人引用的多余文件。
    sizes = [
        ("AppIcon-1024x1024.png", 1024),
        ("AppIcon-60x60@3x.png", 180),
        ("AppIcon-60x60@2x.png", 120),
        ("AppIcon-40x40@3x.png", 120),
        ("AppIcon-40x40@2x.png", 80),
        ("AppIcon-29x29@3x.png", 87),
        ("AppIcon-29x29@2x.png", 58),
    ]
    
    count = 0
    for name, size in sizes:
        img = make_icon(size)
        out_path = OUTPUT_DIR / name
        img.save(out_path, 'PNG', quality=95)
        out_name = name.replace("\u2713", "[OK]").encode('ascii','replace').decode()
        print(f"  [OK] {name}  ({size}x{size})")
        count += 1
    
    print(f"\nDone! Generated {count} files")
    print(f"  Output: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
