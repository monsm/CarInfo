#!/usr/bin/env bash
# extract_baseline.sh — 重新生成符号检查的基线。
#
# 基线是什么：**一次已知能编译的提交**的源码快照。scan.py 靠它反推
# 「项目没声明、代码里却在用」的名字 = SDK 提供的，从而把这种名字列成高嫌疑。
#
# 为什么必须是冻结的提交，而不是当前工作区：
#   若拿当前代码当基线，白名单会包含我们自己刚写下的错名字，
#   于是检查器**永远绿灯**。这一点很反直觉，所以写在这里。
#
# 用法：
#   ./scan/extract_baseline.sh fbd26fc        # 用那个提交当基线
#   ./scan/extract_baseline.sh HEAD~20        # 或任意 ref
#
# 产出（后两个是**要提交**的，因为 CI 上没有基线目录）：
#   scan/baseline/              ← 快照（.gitignore 忽略；本机复现用）
#   scan/baseline_cache.json    ← 分析结果（提交）
#   scan/sdk_cache.json         ← SDK 名字表（提交）
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
# scan.py 检测到基线目录存在时会现场分析并刷新缓存
PYTHONIOENCODING=utf-8 python scan/scan.py | grep -E "基线:|✅|❌" || true

echo "== 重新生成 scan/sdk_cache.json =="
rm -f scan/sdk_cache.json
PYTHONIOENCODING=utf-8 python scan/logic.py >/dev/null
echo "   $(python -c "import json;print(len(json.load(open('scan/sdk_cache.json',encoding='utf-8'))))") 个名字"

echo
echo "✅ 完成。要提交的是这两个缓存（不是 scan/baseline/）："
echo "   git add scan/baseline_cache.json scan/sdk_cache.json"
