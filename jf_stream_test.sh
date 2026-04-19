#!/bin/bash
#
# JF 测试环境 - 推拉流测试脚本
# 推流 + FLV/HLS 拉流验证
#
# 用法: ./jf_stream_test.sh [推流URL] [拉流域名] [appName] [streamId] [视频文件路径]
#

set -e

# ========== JF 环境默认配置 ==========
PUSH_URL="${1:-rtmp://liyan-pull.test.com/qa-test/liyan_push_s}"
PULL_DOMAIN="${2:-liyan-pull.test.com}"
APP="${3:-qa-test}"
STREAM="${4:-liyan_push_s}"
VIDEO="${5:-test.mp4}"

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

echo "=============================================="
echo "  JF 测试环境 - 推拉流测试"
echo "=============================================="
echo "  推流地址: $PUSH_URL"
echo "  拉流域名: $PULL_DOMAIN"
echo "  App:      $APP"
echo "  Stream:   $STREAM"
echo "  视频源:   $VIDEO"
echo "=============================================="

# ========== 检查 ffmpeg ==========
if ! command -v ffmpeg &>/dev/null; then
    log_error "ffmpeg 未安装，请先安装: brew install ffmpeg"
    exit 1
fi

# ========== 生成测试视频（如果不存在） ==========
if [[ ! -f "$VIDEO" ]]; then
    log_info "生成测试视频..."
    VIDEO="/tmp/test_stream_$$.mp4"
    ffmpeg -f lavfi -i "testsrc=1280x720:rate=30" -f lavfi -i sine=frequency=440 -t 30 \
           -c:v libx264 -c:a aac -f mp4 "$VIDEO" -y 2>/dev/null
    log_info "测试视频已生成: $VIDEO"
fi

# ========== 拉流 URL ==========
URL_RTMP="rtmp://${PULL_DOMAIN}/${APP}/${STREAM}"
URL_FLV="http://${PULL_DOMAIN}/${APP}/${STREAM}.flv"
URL_HLS="http://${PULL_DOMAIN}/${APP}/${STREAM}.m3u8"

# ========== 清理函数 ==========
cleanup() {
    log_info "停止推流进程..."
    kill $PUSH_PID 2>/dev/null || true
    kill $FLV_PID  2>/dev/null || true
    kill $HLS_PID  2>/dev/null || true
    kill $HLS_WAIT_PID 2>/dev/null || true
    wait 2>/dev/null || true
    rm -f /tmp/test_stream_$$.mp4 /tmp/ffmpeg_push_$$.log /tmp/flv_probe_$$.json /tmp/hls_playlist_$$.m3u8 /tmp/test_segment_$$.ts 2>/dev/null || true
    log_info "清理完成"
}
trap cleanup EXIT

# ========== STEP 1: 开始推流 ==========
echo ""
log_step "STEP 1 - 开始推流..."
ffmpeg -re -stream_loop -1 -i "$VIDEO" \
       -c copy -f flv "$PUSH_URL" \
       > /tmp/ffmpeg_push_$$.log 2>&1 &
PUSH_PID=$!
log_info "推流进程 PID: $PUSH_PID"
sleep 3

if ! kill -0 $PUSH_PID 2>/dev/null; then
    log_error "推流启动失败！"
    cat /tmp/ffmpeg_push_$$.log
    exit 1
fi
log_info "✓ 推流进程运行中"

# ========== STEP 2: 测试 FLV 拉流 ==========
echo ""
log_step "STEP 2 - 测试 FLV 拉流..."
log_info "URL: $URL_FLV"

ffprobe -v quiet -print_format json -show_streams "$URL_FLV" \
        -timeout 10000000 > /tmp/flv_probe_$$.json 2>&1 &
FLV_PID=$!

sleep 8
if kill -0 $FLV_PID 2>/dev/null; then
    log_warn "FLV 流探测超时（10s），服务可能未启动"
    kill $FLV_PID 2>/dev/null || true
    FLV_RESULT="超时"
else
    if grep -q '"streams"' /tmp/flv_probe_$$.json 2>/dev/null; then
        log_info "✓ FLV 流探测成功"
        cat /tmp/flv_probe_$$.json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'    - {s[\"codec_type\"]}: {s[\"codec_name\"]}') for s in d.get('streams',[])]" 2>/dev/null || true
        FLV_RESULT="成功"
    else
        log_warn "FLV 流探测无结果（服务未开启或流不存在）"
        FLV_RESULT="失败"
    fi
fi

# ========== STEP 3: 测试 HLS 拉流 ==========
echo ""
log_step "STEP 3 - 测试 HLS 拉流..."
log_info "URL: $URL_HLS"

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
        SEG_COUNT=$(grep -c '#EXTINF' $HLS_TMP 2>/dev/null || echo 0)
        echo "    播放列表片段数: $SEG_COUNT"

        # 下载第一个 ts 片段验证
        TS_URL=$(grep -v '#' "$HLS_TMP" | head -1)
        if [[ -n "$TS_URL" ]]; then
            if [[ "$TS_URL" == http* ]]; then
                TS_FILE="/tmp/test_segment_$$.ts"
                curl -s --connect-timeout 5 "$TS_URL" -o "$TS_FILE" 2>/dev/null
            else
                TS_FILE="/tmp/test_segment_$$.ts"
                curl -s --connect-timeout 5 "${URL_HLS%/*}/$TS_URL" -o "$TS_FILE" 2>/dev/null
            fi
            if [[ -f "$TS_FILE" ]] && [[ -s "$TS_FILE" ]]; then
                log_info "✓ HLS ts 片段下载成功: $(du -h $TS_FILE | cut -f1)"
                HLS_RESULT="成功"
            else
                log_warn "HLS ts 片段下载失败或为空"
                HLS_RESULT="失败"
            fi
        else
            HLS_RESULT="无片段"
        fi
    else
        log_warn "HLS m3u8 获取失败（服务未开启或流不存在）"
        HLS_RESULT="失败"
    fi
fi

# ========== 汇总结果 ==========
echo ""
echo "=============================================="
echo "  测试结果汇总"
echo "=============================================="
echo "  推流:   ✓ 运行中 (PID: $PUSH_PID)"
echo "  FLV:    $FLV_RESULT"
echo "  HLS:    $HLS_RESULT"
echo "=============================================="
log_info "测试结束后推流将自动停止（Ctrl+C）"
echo ""

# 保持脚本运行
wait $PUSH_PID
