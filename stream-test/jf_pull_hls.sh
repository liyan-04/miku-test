#!/bin/bash
#
# JF HLS 拉流测试脚本
#
# 用法:
#   ./jf_pull_hls.sh --domain <拉流域名> --app <app> --stream <stream> [--duration <秒>]
#
# 示例:
#   ./jf_pull_hls.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
#   ./jf_pull_hls.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test --duration 10
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
  ./jf_pull_hls.sh --domain <domain> --app <app> --stream <stream> [--duration <秒>]

必填参数:
  --domain  拉流域名
  --app     app 名称
  --stream  流名称

可选参数:
  --duration 拉流探测时长（默认 5 秒）

示例:
  ./jf_pull_hls.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
  ./jf_pull_hls.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test --duration 10
EOF
}

# ========== 参数默认值 ==========
DOMAIN=""
APP=""
STREAM=""
DURATION=5

# ========== 解析参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)   DOMAIN="$2";   shift 2 ;;
        --app)      APP="$2";      shift 2 ;;
        --stream)   STREAM="$2";   shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        -h|--help)  show_help; exit 0 ;;
        *)          log_error "未知参数: $1"; show_help; exit 1 ;;
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

# ========== 检查 ffprobe ==========
if ! command -v ffprobe &>/dev/null; then
    log_warn "ffprobe 未安装，ts 片段分析将跳过: brew install ffmpeg"
fi

# ========== 构建拉流 URL ==========
URL_HLS="http://${DOMAIN}/${APP}/${STREAM}.m3u8"

log_step "测试 HLS 拉流..."
log_info "URL: $URL_HLS"

# ========== 测试 HLS ==========
HLS_HEADERS="/tmp/hls_headers_$$.txt"
HLS_TMP="/tmp/hls_playlist_$$.m3u8"
KNOWN_TS_FILE="/tmp/known_ts_$$.txt"
touch "$KNOWN_TS_FILE"

# Step 1: 获取首次请求响应（不跟随重定向，获取响应码和 Location）
log_info "首次请求响应详情:"
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -D "$HLS_HEADERS" --connect-timeout 5 --max-time 10 "$URL_HLS" 2>/dev/null)
log_info "  首次响应码: $RESPONSE_CODE"

if [[ "$RESPONSE_CODE" == "302" ]] || [[ "$RESPONSE_CODE" == "301" ]]; then
    log_info "  检测到重定向，Location 信息:"
    grep -i "^Location:" "$HLS_HEADERS" | while read -r line; do
        log_info "    $line"
    done
fi

# Step 2: 每秒拉取一次 m3u8，发现新 ts 就下载，持续 DURATION 秒
log_info "开始探测（每 ${DURATION}s 拉取 m3u8，检查新 ts 片段）..."

BASE_URL="http://${DOMAIN}/${APP}/"
SUCCESS_COUNT=0
TOTAL_NEW_TS=0
SECOND=0

while [[ $SECOND -lt $DURATION ]]; do
    SECOND=$((SECOND + 1))

    curl -s -L --max-redirs 5 --connect-timeout 5 --max-time 5 "$URL_HLS" -o "$HLS_TMP" 2>/dev/null

    if [[ -f "$HLS_TMP" ]] && grep -q "EXTM3U" "$HLS_TMP" 2>/dev/null; then
        # 获取 base URL（从 m3u8 中提取路径）
        M3U8_DIR=$(grep -v '#' "$HLS_TMP" | head -1 | sed 's|[^/]*$||' | sed 's|^\./||')
        if [[ -n "$M3U8_DIR" ]]; then
            BASE_URL="http://${DOMAIN}/${APP}/${M3U8_DIR}"
        fi

        # 提取所有 ts 片段
        TS_URLS=$(grep -v '#' "$HLS_TMP" | grep -v '^$')

        if [[ -n "$TS_URLS" ]]; then
            while IFS= read -r TS_URL; do
                [[ -z "$TS_URL" ]] && continue
                TS_NAME=$(basename "$TS_URL" | cut -d'?' -f1)

                # 检查是否是新 ts
                if ! grep -q "^$TS_NAME$" "$KNOWN_TS_FILE" 2>/dev/null; then
                    echo "$TS_NAME" >> "$KNOWN_TS_FILE"
                    TOTAL_NEW_TS=$((TOTAL_NEW_TS + 1))

                    # 拼接完整 ts URL
                    if [[ "$TS_URL" == http* ]]; then
                        FULL_TS_URL="$TS_URL"
                    else
                        FULL_TS_URL="${BASE_URL}${TS_URL}"
                    fi

                    TS_FILE="/tmp/new_ts_${TOTAL_NEW_TS}_$$.ts"

                    log_info "  [${SECOND}s] 新 ts 片段: $TS_NAME"

                    # 下载 ts 片段
                    curl -s -L --connect-timeout 5 --max-time 30 "$FULL_TS_URL" -o "$TS_FILE" 2>/dev/null

                    if [[ -f "$TS_FILE" ]] && [[ -s "$TS_FILE" ]]; then
                        TS_SIZE=$(du -h "$TS_FILE" | cut -f1)
                        log_info "    下载成功: $TS_SIZE"

                        # 使用 ffprobe 分析 ts
                        if command -v ffprobe &>/dev/null; then
                            if ffprobe -v quiet -print_format json -show_format -show_streams "$TS_FILE" > /dev/null 2>&1; then
                                VIDEO_CODEC=$(ffprobe -v quiet -print_format json -show_streams "$TS_FILE" 2>/dev/null | grep -o '"codec_name":"[^"]*"' | head -1 | cut -d'"' -f4)
                                AUDIO_CODEC=$(ffprobe -v quiet -print_format json -show_streams "$TS_FILE" 2>/dev/null | grep -o '"codec_name":"[^"]*"' | tail -1 | cut -d'"' -f4)
                                WIDTH=$(ffprobe -v quiet -print_format json -show_streams "$TS_FILE" 2>/dev/null | grep -o '"width":[0-9]*' | head -1 | cut -d':' -f2)
                                HEIGHT=$(ffprobe -v quiet -print_format json -show_streams "$TS_FILE" 2>/dev/null | grep -o '"height":[0-9]*' | head -1 | cut -d':' -f2)

                                if [[ -n "$VIDEO_CODEC" ]]; then
                                    log_info "    video: $VIDEO_CODEC ${WIDTH}x${HEIGHT}"
                                fi
                                if [[ -n "$AUDIO_CODEC" ]]; then
                                    log_info "    audio: $AUDIO_CODEC"
                                fi
                            fi
                        fi

                        rm -f "$TS_FILE"
                        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    else
                        log_warn "    ts 片段下载失败"
                    fi
                fi
            done <<< "$TS_URLS"
        fi
    fi

    if [[ $SECOND -lt $DURATION ]]; then
        sleep 1
    fi
done

log_info "探测完成，共发现 ${TOTAL_NEW_TS} 个新 ts 片段"
HLS_RESULT=$([[ $SUCCESS_COUNT -gt 0 ]] && echo "成功" || echo "失败")

# ========== 清理临时文件 ==========
rm -f "$HLS_TMP" "$HLS_HEADERS" "$KNOWN_TS_FILE" 2>/dev/null || true

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