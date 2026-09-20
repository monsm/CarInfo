#!/bin/bash
# =============================================================================
# generate_appicon.sh — AppIcon 图标生成脚本
# 自动生成所有 iOS 尺寸变体
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG_INPUT="${SCRIPT_DIR}/AppIcon.svg"
OUTPUT_DIR="${SCRIPT_DIR}/CarKeeper/Resources/Assets.xcassets/AppIcon.appiconset"

# 检查输入文件
if [ ! -f "$SVG_INPUT" ]; then
    echo "❌ 找不到源文件: $SVG_INPUT"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "🎨 正在生成 AppIcon..."
echo ""

# 检查 ImageMagick
if command -v magick &> /dev/null; then
    CONVERTER="magick"
elif command -v convert &> /dev/null; then
    CONVERTER="convert"
else
    echo "⚠️  未找到 ImageMagick，尝试使用 cairosvg..."
    if command -v python3 &> /dev/null; then
        python3 "${SCRIPT_DIR}/generate_appicon.py" "$SVG_INPUT" "$OUTPUT_DIR"
        exit 0
    else
        echo "❌ 请安装 ImageMagick 或 cairosvg"
        echo "   macOS: brew install imagemagick"
        echo "   Python: pip3 install cairosvg"
        exit 1
    fi
fi

# 定义尺寸映射
declare -A SIZES=(
    ["AppIcon-1024x1024.png"]="1024x1024"
    ["AppIcon-60x60@2x.png"]="120x120"
    ["AppIcon-60x60@3x.png"]="180x180"
    ["AppIcon-76x76.png"]="76x76"
    ["AppIcon-76x76@2x.png"]="152x152"
    ["AppIcon-83.5x83.5@2x.png"]="167x167"
    ["AppIcon-29x29.png"]="29x29"
    ["AppIcon-29x29@2x.png"]="58x58"
    ["AppIcon-29x29@3x.png"]="87x87"
    ["AppIcon-40x40.png"]="40x40"
    ["AppIcon-40x40@2x.png"]="80x80"
    ["AppIcon-40x40@3x.png"]="120x120"
)

echo "📐 生成图标尺寸:"
for file in "${!SIZES[@]}"; do
    size="${SIZES[$file]}"
    output="${OUTPUT_DIR}/${file}"
    echo "   → ${file} (${size})"
    $CONVERTER "$SVG_INPUT" -resize "${size}" -background none "$output"
done

echo ""
echo "✅ AppIcon 生成完成!"
echo "   位置: $OUTPUT_DIR"
echo ""
echo "   共生成 ${#SIZES[@]} 个文件"
