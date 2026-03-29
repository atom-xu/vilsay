#!/bin/bash
#
# Week 2 自动化测试脚本
# 使用方法：./run-tests.sh
#

set -e

echo "🧪 Vilsay Week 2 自动化验收测试"
echo "================================"
echo ""

# 检查 Xcode
echo "📋 检查环境..."
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误：找不到 xcodebuild，请安装 Xcode"
    exit 1
fi
echo "✅ Xcode 已安装"

# 获取项目路径
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "📁 项目路径: $PROJECT_DIR"

# 编译测试
echo ""
echo "🔨 步骤 1: 编译项目..."
cd "$PROJECT_DIR"
xcodebuild build-for-testing \
    -scheme vilsay \
    -destination 'platform=macOS' \
    -quiet

echo "✅ 编译成功"

# 运行测试
echo ""
echo "🚀 步骤 2: 运行自动化测试..."
echo "⚠️  注意：测试过程中会控制鼠标点击菜单栏"
echo ""

xcodebuild test \
    -scheme vilsay \
    -destination 'platform=macOS' \
    -only-testing:vilsayUITests/Week2AcceptanceTests \
    | tee test-results.txt \
    | grep -E "(Test Case|✅|❌|passed|failed|Test Suite)"

# 检查结果
echo ""
echo "================================"
if grep -q "Test Suite.*failed" test-results.txt 2>/dev/null; then
    echo "❌ 测试失败"
    echo "详细日志: $PROJECT_DIR/test-results.txt"
    exit 1
else
    echo "✅ 自动化测试完成"
    echo ""
    echo "📋 手动视觉验证清单："
    echo "   [ ] 菜单栏图标颜色是否正确（灰色/红色/蓝色/橙色）"
    echo "   [ ] 悬浮按钮是否在右下角显示"
    echo "   [ ] 悬浮按钮右键菜单是否正常"
    echo "   [ ] 状态切换动画是否流畅"
    echo ""
    echo "详细日志: $PROJECT_DIR/test-results.txt"
fi
