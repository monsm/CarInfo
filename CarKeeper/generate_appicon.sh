#!/bin/bash
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
