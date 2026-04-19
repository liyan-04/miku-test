#!/bin/bash
#
# JF HLS 拉流测试脚本
#
# 用法:
#   ./jf_pull_hls.sh --domain <拉流域名> --app <app> --stream <stream>
#
# 示例:
#   ./jf_pull_hls.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
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
JF HLS 拉流测试脚本

用法:
  ./jf_pull_hls.sh --domain <domain> --app <app> --stream <stream>

必填参数:
  --domain  拉流域名
  --app     app 名称
  --stream  流名称

示例:
  ./jf_pull_hls.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
EOF
}

# ========== 参数默认值 ==========
DOMAIN=""
APP=""
STREAM=""
SEG_COUNT_LIMIT=3

# ========== 解析参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)  DOMAIN="$2";  shift 2 ;;
        --app)     APP="$2";     shift 2 ;;
        --stream)  STREAM="$2"; shift 2 ;;
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

# ========== 检查 curl ==========
if ! command -v curl &>/dev/null; then
    log_error "curl 未安装"
    exit 1
fi

# ========== 构建拉流 URL ==========
URL_HLS="http://${DOMAIN}/${APP}/${STREAM}.m3u8"

log_step "测试 HLS 拉流..."
log_info "URL: $URL_HLS"

# ========== 测试 HLS ==========
HLS_TMP="/tmp/hls_playlist_$$.m3u8"
curl -s --connect-timeout 5 "$URL_HLS" -o "$HLS_TMP" 2>/dev/null &
HLS_WAIT_PID=$!
sleep 5

if kill -0 $HLS_WAIT_PID 2>/dev/null; then
    log_warn "HLS m3u8 下载超时"
    kill $HLS_WAIT_PID 2>/dev/null || true
    HLS_RESULT="超时"
else
    if [[ -f "$HLS_TMP" ]] && grep -q "EXTM3U" "$HLS_TMP" 2>/dev/null; then
        log_info "✓ HLS m3u8 获取成功"
        SEG_COUNT=$(grep -c '#EXTINF' "$HLS_TMP" 2>/dev/null || echo 0)
        echo "    播放列表片段数: $SEG_COUNT"

        # 下载多个 ts 片段验证
        TS_URLS=$(grep -v '#' "$HLS_TMP" | head -"$SEG_COUNT_LIMIT")
        SUCCESS_COUNT=0
        TOTAL_COUNT=0

        while IFS= read -r TS_URL; do
            [[ -z "$TS_URL" ]] && continue
            TOTAL_COUNT=$((TOTAL_COUNT + 1))
            TS_FILE="/tmp/test_segment_${TOTAL_COUNT}_$$.ts"
            # ts URL 是绝对路径，直接拼接域名
            curl -s --connect-timeout 5 "http://${DOMAIN}${TS_URL}" -o "$TS_FILE" 2>/dev/null
            if [[ -f "$TS_FILE" ]] && [[ -s "$TS_FILE" ]]; then
                log_info "✓ ts 片段 ${TOTAL_COUNT} 下载成功: $(du -h "$TS_FILE" | cut -f1)"
                log_info "  文件名: $(basename "$TS_URL" | cut -d'?' -f1)"
                rm -f "$TS_FILE"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                log_warn "ts 片段 ${TOTAL_COUNT} 下载失败"
            fi
        done <<< "$TS_URLS"

        echo "    片段下载: ${SUCCESS_COUNT}/${TOTAL_COUNT}"

        if [[ $SUCCESS_COUNT -gt 0 ]]; then
            HLS_RESULT="成功"
        else
            HLS_RESULT="失败"
        fi
    else
        log_warn "HLS m3u8 获取失败（服务未开启或流不存在）"
        HLS_RESULT="失败"
    fi
fi

# ========== 清理临时文件 ==========
rm -f "$HLS_TMP" 2>/dev/null || true

# ========== 返回结果 ==========
echo ""
echo "=============================================="
echo "  HLS:  $HLS_RESULT"
echo "=============================================="

if [[ "$HLS_RESULT" == "成功" ]]; then
    exit 0
else
    exit 1
fi