#!/bin/bash
#
# JF 测试环境 - 推拉流测试脚本
#
# 用法:
#   ./jf_stream_test.sh --ip <IP> --domain <domain> --app <app> --stream <stream> [--pull-domain <pull_domain>] [--video <video>]
#
# 示例:
#   ./jf_stream_test.sh --ip 10.210.32.28 --domain qa-publish-callback.com --pull-domain liyan-pull.test.com --app qa-test --stream liyan_test
#

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ========== 帮助信息 ==========
show_help() {
    cat << EOF
JF 测试环境 - 推拉流测试脚本

用法:
  ./jf_stream_test.sh --ip <IP> --domain <domain> --app <app> --stream <stream> [--pull-domain <pull_domain>] [--video <video>]

必填参数:
  --ip         推流目标服务器 IP
  --domain      推流域名（用于 tcUrl）
  --app        RTMP app 名称
  --stream     流名称

可选参数:
  --pull-domain 拉流域名（默认等于 --domain）
  --video      视频文件路径（默认自动生成测试视频）

示例:
  ./jf_stream_test.sh --ip 10.210.32.28 --domain qa-publish-callback.com --pull-domain liyan-pull.test.com --app qa-test --stream liyan_test
EOF
}

# ========== 参数默认值 ==========
IP=""
DOMAIN=""
PULL_DOMAIN=""
APP=""
STREAM=""
VIDEO=""

# ========== 解析参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)          IP="$2";          shift 2 ;;
        --domain)      DOMAIN="$2";       shift 2 ;;
        --pull-domain) PULL_DOMAIN="$2";  shift 2 ;;
        --app)         APP="$2";          shift 2 ;;
        --stream)      STREAM="$2";       shift 2 ;;
        --video)       VIDEO="$2";        shift 2 ;;
        -h|--help)     show_help; exit 0 ;;
        *)             log_error "未知参数: $1"; show_help; exit 1 ;;
    esac
done

# ========== 检查必填参数 ==========
if [[ -z "$IP" ]] || [[ -z "$DOMAIN" ]] || [[ -z "$APP" ]] || [[ -z "$STREAM" ]]; then
    log_error "缺少必填参数: --ip, --domain, --app, --stream"
    show_help
    exit 1
fi

# ========== 默认拉流域名 ==========
if [[ -z "$PULL_DOMAIN" ]]; then
    PULL_DOMAIN="$DOMAIN"
fi

# ========== 脚本路径 ==========
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUSH_SCRIPT="${SCRIPT_DIR}/jf_push.sh"
PULL_FLV_SCRIPT="${SCRIPT_DIR}/jf_pull_flv.sh"
PULL_HLS_SCRIPT="${SCRIPT_DIR}/jf_pull_hls.sh"

if [[ ! -f "$PUSH_SCRIPT" ]]; then
    log_error "推流脚本不存在: $PUSH_SCRIPT"
    exit 1
fi

if [[ ! -f "$PULL_FLV_SCRIPT" ]]; then
    log_error "FLV 拉流脚本不存在: $PULL_FLV_SCRIPT"
    exit 1
fi

if [[ ! -f "$PULL_HLS_SCRIPT" ]]; then
    log_error "HLS 拉流脚本不存在: $PULL_HLS_SCRIPT"
    exit 1
fi

# ========== 检查/生成视频文件 ==========
if [[ -z "$VIDEO" ]] || [[ ! -f "$VIDEO" ]]; then
    if [[ -z "$VIDEO" ]]; then
        VIDEO="/tmp/test_stream_$$.mp4"
    fi
    log_info "生成测试视频: $VIDEO"
    if command -v ffmpeg &>/dev/null; then
        ffmpeg -f lavfi -i "testsrc=1280x720:rate=30" -f lavfi -i sine=frequency=440 -t 30 \
               -c:v libx264 -c:a aac -f mp4 "$VIDEO" -y 2>/dev/null
    fi
fi

VIDEO_SIZE=$(du -h "$VIDEO" | cut -f1)

# ========== 打印配置 ==========
echo ""
echo "=============================================="
echo "  JF 测试环境 - 推拉流测试"
echo "=============================================="
echo "  推流 IP:   $IP"
echo "  推流域名:  $DOMAIN"
echo "  拉流域名:  $PULL_DOMAIN"
echo "  App:       $APP"
echo "  Stream:    $STREAM"
echo "  视频文件:  $VIDEO ($VIDEO_SIZE)"
echo "=============================================="

# ========== 清理函数 ==========
cleanup() {
    log_info "停止推流..."
    kill $PUSH_PID 2>/dev/null || true
    wait $PUSH_PID 2>/dev/null || true
    rm -f /tmp/test_stream_$$.mp4 2>/dev/null || true
    log_info "清理完成"
}
trap cleanup EXIT INT TERM

# ========== STEP 1: 推流 ==========
echo ""
log_step "STEP 1 - 开始推流..."

"$PUSH_SCRIPT" \
    --ip "$IP" \
    --domain "$DOMAIN" \
    --app "$APP" \
    --stream "$STREAM" \
    --video "$VIDEO" &
PUSH_PID=$!

log_info "推流进程 PID: $PUSH_PID"
sleep 3

if ! kill -0 $PUSH_PID 2>/dev/null; then
    log_error "推流启动失败！"
    exit 1
fi

log_info "✓ 推流进程运行中"

# ========== STEP 2: FLV 拉流测试 ==========
echo ""
log_step "STEP 2 - 测试 FLV 拉流..."

"$PULL_FLV_SCRIPT" \
    --domain "$PULL_DOMAIN" \
    --app "$APP" \
    --stream "$STREAM"
FLV_RESULT=$?

# ========== STEP 3: HLS 拉流测试 ==========
echo ""
log_step "STEP 3 - 测试 HLS 拉流..."

"$PULL_HLS_SCRIPT" \
    --domain "$PULL_DOMAIN" \
    --app "$APP" \
    --stream "$STREAM"
HLS_RESULT=$?

# ========== 汇总结果 ==========
echo ""
echo "=============================================="
echo "  测试结果汇总"
echo "=============================================="
if kill -0 $PUSH_PID 2>/dev/null; then
    echo "  推流:   ✓ 运行中 (PID: $PUSH_PID)"
else
    echo "  推流:   ✗ 已停止"
fi
echo "  FLV:    $([[ $FLV_RESULT -eq 0 ]] && echo "✓ 成功" || echo "✗ 失败")"
echo "  HLS:    $([[ $HLS_RESULT -eq 0 ]] && echo "✓ 成功" || echo "✗ 失败")"
echo "=============================================="
log_info "按 Ctrl+C 停止推流并退出测试"
echo ""

# ========== 等待推流结束 ==========
while kill -0 $PUSH_PID 2>/dev/null; do
    sleep 5
done

log_warn "推流进程已结束"