#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
SCHEME="CarKeeper"
XCODE_PROJ="$PROJECT_ROOT/$SCHEME.xcodeproj"

FAST_MODE=false
CLEAN_BUILD=false
SKIP_LINT=false
SWIFTLINT_OPTS=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

for arg in "$@"; do
    case $arg in
        --fast)
            FAST_MODE=true
            SWIFTLINT_OPTS="--quiet"
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --no-lint)
            SKIP_LINT=true
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Usage: ./build.sh [--fast] [--clean] [--no-lint]"
            exit 1
            ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          长安车管家 — Kansei Design Build System            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_info "Project: $PROJECT_ROOT"
log_info "Scheme:  $SCHEME"
log_info "Fast:    $FAST_MODE | Clean: $CLEAN_BUILD | Lint: $([ "$SKIP_LINT" = true ] && echo "SKIPPED" || echo "ENABLED")"
echo ""

run_swiftlint() {
    log_info "Step 1/4: SwiftLint 检查..."
    
    if [ "$SKIP_LINT" = true ]; then
        log_warn "SwiftLint 检查已跳过"
        return 0
    fi
    
    if ! command -v swiftlint &> /dev/null; then
        log_warn "未安装 swiftlint，跳过检查 (安装: brew install swiftlint)"
        return 0
    fi
    
    if [ ! -f "$PROJECT_ROOT/.swiftlint.yml" ]; then
        log_warn "未找到 .swiftlint.yml，使用默认配置"
    fi
    
    local lint_output
    lint_output=$(swiftlint lint --strict $SWIFTLINT_OPTS 2>&1) || true
    
    if [ -n "$lint_output" ]; then
        echo "$lint_output" | head -50
        local error_count=$(echo "$lint_output" | grep -c "error" || true)
        if [ "$error_count" -gt 0 ]; then
            log_error "发现 $error_count 个 lint 错误"
            return 1
        else
            log_warn "发现 $error_count 个 lint 警告"
        fi
    else
        log_success "SwiftLint 检查通过"
    fi
}

run_typecheck() {
    log_info "Step 2/4: Swift 类型检查..."
    
    if ! command -v xcodebuild &> /dev/null; then
        log_error "未安装 Xcode 命令行工具"
        log_error "请安装: xcode-select --install"
        return 1
    fi
    
    local build_args=(
        -scheme "$SCHEME"
        -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
        -quiet
        build-for-testing
    )
    
    if [ "$CLEAN_BUILD" = true ]; then
        log_info "执行 Clean..."
        xcodebuild clean -scheme "$SCHEME" > /dev/null 2>&1 || true
    fi
    
    local build_output
    build_output=$(xcodebuild "${build_args[@]}" 2>&1) || true
    
    local errors
    errors=$(echo "$build_output" | grep -E "^.*\.swift:[0-9]+:[0-9]+: error:" || true)
    
    if [ -n "$errors" ]; then
        echo "$errors" | head -30
        local error_count=$(echo "$errors" | wc -l | tr -d ' ')
        log_error "编译失败: 发现 $error_count 个错误"
        return 1
    fi
    
    local warnings
    warnings=$(echo "$build_output" | grep -E "warning:" || true)
    if [ -n "$warnings" ]; then
        local warning_count=$(echo "$warnings" | wc -l | tr -d ' ')
        log_warn "编译完成，发现 $warning_count 个警告"
    else
        log_success "Swift 类型检查通过"
    fi
    
    return 0
}

validate_xcassets() {
    log_info "Step 3/4: xcassets 图片尺寸校验..."
    
    local assets_dir="$PROJECT_ROOT/$SCHEME/Resources/Assets.xcassets"
    
    if [ ! -d "$assets_dir" ]; then
        log_warn "未找到 Assets.xcassets 目录"
        return 0
    fi
    
    local pass=true
    
    local icon_set="$assets_dir/AppIcon.appiconset"
    if [ -f "$icon_set/Contents.json" ]; then
        log_info "检查 AppIcon..."
        
        while IFS= read -r line; do
            if [[ "$line" =~ \"filename\" ]]; then
                local filename=$(echo "$line" | grep -o '"[^"]*\.png"' | tr -d '"' | tr -d '"')
                if [ -n "$filename" ]; then
                    local filepath="$icon_set/$filename"
                    if [ -f "$filepath" ]; then
                        local size
                        size=$(sips -g pixelWidth -g pixelHeight "$filepath" 2>/dev/null | grep -E "pixel(Width|Height)" | awk '{print $2}')
                        local width=$(echo "$size" | head -1)
                        local height=$(echo "$size" | sed -n '2p')
                        
                        if [ "$width" = "$height" ] && [ "$width" -gt 0 ]; then
                            log_success "  ✓ $filename ($width×$height)"
                        else
                            log_error "  ✗ $filename (尺寸不匹配: ${width}×${height})"
                            pass=false
                        fi
                    else
                        log_error "  ✗ $filename (文件不存在)"
                        pass=false
                    fi
                fi
            fi
        done < <(grep -E '"filename"|"size"' "$icon_set/Contents.json" | head -24)
    else
        log_warn "未找到 AppIcon.appiconset/Contents.json"
    fi
    
    if [ "$pass" = true ]; then
        log_success "xcassets 图片校验通过"
    else
        log_error "xcassets 图片校验失败"
        return 1
    fi
}

validate_design_tokens() {
    log_info "Step 4/4: 设计令牌一致性检查..."
    
    local kansei_file="$PROJECT_ROOT/$SCHEME/Design/Kansei.swift"
    if [ ! -f "$kansei_file" ]; then
        log_warn "未找到 Kansei.swift"
        return 0
    fi
    
    local issues=0
    
    if grep -q "static var ambient" "$kansei_file"; then
        log_success "  ✓ 时间感知配色: Kansei.Color.ambient"
    else
        log_error "  ✗ 缺少时间感知配色定义"
        ((issues++))
    fi
    
    if grep -q "breathe" "$kansei_file"; then
        log_success "  ✓ 呼吸动效: Kansei.Motion.breathe"
    else
        log_error "  ✗ 缺少呼吸动效定义"
        ((issues++))
    fi
    
    if grep -q "enum Haptic" "$kansei_file"; then
        log_success "  ✓ 触觉反馈: Kansei.Haptic"
    else
        log_error "  ✗ 缺少触觉反馈定义"
        ((issues++))
    fi
    
    if [ "$issues" -eq 0 ]; then
        log_success "设计令牌一致性检查通过"
    else
        log_error "发现 $issues 个设计令牌问题"
        return 1
    fi
}

main() {
    local start_time=$(date +%s)
    
    run_swiftlint
    run_typecheck
    validate_xcassets
    validate_design_tokens
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    log_success "构建完成! (耗时 ${duration}s)"
    echo ""
    log_info "下次运行: ./build.sh --clean (完整构建)"
    log_info "快速模式: ./build.sh --fast (跳过详细输出)"
}

main "$@"
