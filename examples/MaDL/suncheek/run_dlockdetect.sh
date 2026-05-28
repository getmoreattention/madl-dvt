#!/bin/bash
# ==========================================================================
# run_dlockdetect.sh — MaDL 死锁检测运行 + 格式化报告
#
# 用法:
#   bash run_dlockdetect.sh <madl_file>       # 标准模式
#   bash run_dlockdetect.sh <madl_file> -v     # 详细模式 (显示原始输出)
#   bash run_dlockdetect.sh <madl_file> -a     # 检查所有 Source
#   bash run_dlockdetect.sh <madl_file> -va    # 详细 + 所有 Source
#
# 可以在任何目录下运行，脚本自动处理路径
# ==========================================================================

export PATH="/usr/bin:/home/getmoreattention/bin:$PATH"
export MWB_PATH_Z3="/home/getmoreattention/bin"

MADL_ROOT="/home/getmoreattention/madl-dvt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORMATTER="$SCRIPT_DIR/format_report.py"

if [ -z "$1" ]; then
    echo "Usage: bash run_dlockdetect.sh <madl_file> [-v] [-a]"
    echo ""
    echo "Options:"
    echo "  -v    详细模式: 同时显示原始输出"
    echo "  -a    检查所有 Source (默认在第一个死锁处停止)"
    echo ""
    echo "Examples:"
    echo "  bash run_dlockdetect.sh tests/test_spec4_deadlock.madl"
    echo "  bash run_dlockdetect.sh tests/test_spec4_deadlock.madl -a"
    exit 1
fi

# 将相对路径转为绝对路径
INPUT_FILE="$1"
if [[ "$INPUT_FILE" != /* ]]; then
    INPUT_FILE="$(cd "$(dirname "$INPUT_FILE")" 2>/dev/null && pwd)/$(basename "$INPUT_FILE")"
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File not found: $INPUT_FILE"
    exit 1
fi

shift

# 解析选项
VERBOSE=false
ALL_SOURCES=""
DLOCKDETECT_FLAGS="-v"  # 始终用 -v 获取详细信息供解析

for arg in "$@"; do
    case "$arg" in
        -v)  VERBOSE=true ;;
        -a)  ALL_SOURCES="--all-sources" ;;
        -va|-av)  VERBOSE=true; ALL_SOURCES="--all-sources" ;;
    esac
done

cd "$MADL_ROOT"

# 运行 dlockdetect 并捕获输出
RAW_OUTPUT=$(/home/getmoreattention/bin/stack-2.13 exec -- dlockdetect $DLOCKDETECT_FLAGS $ALL_SOURCES -f "$INPUT_FILE" 2>&1)
EXIT_CODE=$?

# 如果需要详细输出，先打印原始输出
if [ "$VERBOSE" = true ]; then
    echo "$RAW_OUTPUT"
    echo ""
    echo "─────────── 以下为格式化报告 ───────────"
fi

# 用 Python 格式化报告
if [ -f "$FORMATTER" ]; then
    echo "$RAW_OUTPUT" | python3 "$FORMATTER" - "$INPUT_FILE"
else
    # 如果 Python 格式化器不可用，用简单的 bash 处理
    echo ""
    echo "======================================"

    DEADLOCK_COUNT=$(echo "$RAW_OUTPUT" | grep -c '"(model"')
    LIVE_COUNT=$(echo "$RAW_OUTPUT" | grep -c "is live")
    CYCLE_COUNT=$(echo "$RAW_OUTPUT" | grep "The network contains" | grep -oP '\d+')

    if [ "$DEADLOCK_COUNT" -gt 0 ]; then
        echo "  ✘ 死锁检测结果: 发现 $DEADLOCK_COUNT 个被阻塞的 channel"
        echo "  ✓ 存活 channel: $LIVE_COUNT 个"
        echo "  循环依赖: $CYCLE_COUNT 个"
    elif echo "$RAW_OUTPUT" | grep -q "No deadlock found"; then
        echo "  ✓ 未发现死锁 — 所有 $LIVE_COUNT 个 channel 均存活"
    else
        echo "  ⚠ 无法确定结果 (Z3 可能未正确调用)"
    fi

    echo "======================================"
fi
