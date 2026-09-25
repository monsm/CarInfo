#!/bin/bash
# =============================================================================
# generate_appicon.sh — 重新生成 AppIcon（**唯一的入口**）
# =============================================================================
#
# 一条命令做完三件事：
#   ① 用 `generate_appicon_pillow.py` 渲染 7 个槽位 × 3 套外观（浅色 / 深色 / 着色）；
#   ② 顺手跑 `scan/iconcheck.py`（PNG 与 Contents.json 是否还一致）；
#   ③ 打印出了哪些文件。
#
# 为什么**只有 Pillow 这一条路**（2026-09-25 改）：
#   上一版先找 ImageMagick、找不到再退回 `python3 generate_appicon.py` ——
#   而那个文件**根本不存在**（仓库里只有 `generate_appicon_pillow.py`）。也就是说
#   文档承诺的退路是一条死路，而它只有在「这台机器没有 ImageMagick」时才会被走到。
#   更根本的是：ImageMagick 只能渲 SVG，而 SVG 里只有浅色一套外观 ——
#   用它刷新会得到「一半是新图、一半是旧图」的图标集，正是这个仓库记过的那个坑
#   （改了 A，真机上看到 B）。所以现在 SVG 只是矢量对照（见 AppIcon-SPEC.md），
#   出包的那一份永远由 Pillow 脚本渲染。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPICONSET="${SCRIPT_DIR}/CarKeeper/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ 需要 python3（渲染器是纯 Python + Pillow，不需要 ImageMagick / cairosvg）"
    exit 1
fi

if ! python3 -c "import PIL" >/dev/null 2>&1; then
    echo "❌ 缺少 Pillow。装它：pip3 install Pillow"
    exit 1
fi

echo "🎨 渲染 AppIcon（浅色 / 深色 / 着色）..."
python3 "${SCRIPT_DIR}/generate_appicon_pillow.py" "$APPICONSET"

echo ""
echo "🔍 自查（PNG 与 Contents.json 是否一致）..."
cd "$REPO_ROOT"
python3 scan/iconcheck.py

echo ""
echo "✅ 完成。位置: $APPICONSET"
