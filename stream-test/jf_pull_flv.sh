#!/bin/bash
#
# JF FLV 拉流测试脚本
#
# 用法:
#   ./jf_pull_flv.sh --domain <拉流域名> --app <app> --stream <stream>
#
# 示例:
#   ./jf_pull_flv.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
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
JF FLV 拉流测试脚本

用法:
  ./jf_pull_flv.sh --domain <domain> --app <app> --stream <stream>

必填参数:
  --domain  拉流域名
  --app     app 名称
  --stream  流名称

示例:
  ./jf_pull_flv.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
EOF
}

# ========== 参数默认值 ==========
DOMAIN=""
APP=""
STREAM=""
TIMEOUT=10

# ========== 解析参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)  DOMAIN="$2";  shift 2 ;;
        --app)     APP="$2";     shift 2 ;;
        --stream)  STREAM="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *)         log_error "未知参数: $1"; show_help; exit 1 ;;
    esac
done

# ========== 检查必填参数 ==========
if [[ -z "$DOMAIN" ]] || [[ -z "$APP" ]] || [[ -z "$STREAM" ]]; then
    log_error "缺少必填参数: --domain, --app, --stream"
    show_help
    exit 1
fi

# ========== 检查 ffprobe ==========
if ! command -v ffprobe &>/dev/null; then
    log_error "ffprobe 未安装，请先安装 ffmpeg: brew install ffmpeg"
    exit 1
fi

# ========== 构建拉流 URL ==========
URL_FLV="http://${DOMAIN}/${APP}/${STREAM}.flv"

log_step "测试 FLV 拉流..."
log_info "URL: $URL_FLV"

# ========== 测试 FLV ==========
FLV_TMP="/tmp/flv_probe_$$.json"
ffprobe -v quiet -print_format json -show_streams "$URL_FLV" \
        -timeout "${TIMEOUT}000000" > "$FLV_TMP" 2>&1 &
FLV_PID=$!

sleep "$TIMEOUT"
if kill -0 $FLV_PID 2>/dev/null; then
    log_warn "FLV 流探测超时（${TIMEOUT}s），服务可能未启动"
    kill $FLV_PID 2>/dev/null || true
    FLV_RESULT="超时"
else
    if grep -q '"streams"' "$FLV_TMP" 2>/dev/null; then
        log_info "✓ FLV 流探测成功"
        cat "$FLV_TMP" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'    - {s[\"codec_type\"]}: {s[\"codec_name\"]}') for s in d.get('streams',[])]" 2>/dev/null || true
        FLV_RESULT="成功"
    else
        log_warn "FLV 流探测无结果（服务未开启或流不存在）"
        FLV_RESULT="失败"
    fi
fi

# ========== 清理临时文件 ==========
rm -f "$FLV_TMP" 2>/dev/null || true

# ========== 返回结果 ==========
echo ""
echo "=============================================="
echo "  FLV:  $FLV_RESULT"
echo "=============================================="

if [[ "$FLV_RESULT" == "成功" ]]; then
    exit 0
else
    exit 1
fi