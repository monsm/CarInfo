#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

REF="${1:-}"
if [ -z "$REF" ]; then
  echo "用法: $0 <能编译的提交>   例如: $0 fbd26fc" >&2
  exit 2
fi
if ! git rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
  echo "❌ 不是有效的提交: $REF" >&2
  exit 2
fi

echo "== 提取 $REF 的 CarKeeper/ 快照到 scan/baseline/ =="
rm -rf scan/baseline
mkdir -p scan/baseline
git archive "$REF" CarKeeper | tar -x -C scan/baseline
n=$(find scan/baseline -name '*.swift' | wc -l | tr -d ' ')
echo "   快照 Swift 文件: $n 个"
if [ "$n" -eq 0 ]; then
  echo "❌ 快照里没有 Swift 文件 —— 检查 $REF 是否存在 CarKeeper/ 目录" >&2
  exit 1
fi

echo "== 重新生成 scan/baseline_cache.json =="
PYTHONIOENCODING=utf-8 python scan/scan.py | grep -E "基线:|✅|❌" || true

echo "== 重新生成 scan/sdk_cache.json =="
rm -f scan/sdk_cache.json
PYTHONIOENCODING=utf-8 python scan/logic.py >/dev/null
echo "   $(python -c "import json;print(len(json.load(open('scan/sdk_cache.json',encoding='utf-8'))))") 个名字"

echo
echo "✅ 完成。要提交的是这两个缓存（不是 scan/baseline/）："
echo "   git add scan/baseline_cache.json scan/sdk_cache.json"
