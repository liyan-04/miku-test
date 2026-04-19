#!/bin/bash
#
# JF 推流脚本 - 基于 workbuddy stream-pusher 技能
#
# 用法:
#   ./jf_push.sh --ip 10.210.32.28 --domain qa-publish-callback.com --app qa-test --stream liyan_test --video test.mp4
#
#   带鉴权:
#   ./jf_push.sh --ip 10.210.32.28 --domain qa-publish-callback.com --app qa-test --stream liyan_test --video test.mp4 --params "e=1687486713&token=xxx"
#
#   推一次不循环:
#   ./jf_push.sh --ip 10.210.32.28 --app qa-test --stream liyan_test --video test.mp4 --no-loop
#

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }
log_push()  { echo -e "${CYAN}[PUSH]${NC} $1"; }

# ========== 默认值 ==========
IP=""
DOMAIN=""
APP=""
STREAM=""
VIDEO=""
PARAMS=""
NO_LOOP=false
RECODE=false
EXTRA_ARGS=""

# ========== 帮助信息 ==========
show_help() {
    cat << EOF
JF 推流脚本

用法:
  ./jf_push.sh --ip <IP> --app <app> --stream <stream> --video <video> [--domain <domain>] [--params <params>] [--no-loop] [--recode]

必填参数:
  --ip      目标服务器 IP
  --app     RTMP app 名称
  --stream  流名称
  --video   视频文件路径

可选参数:
  --domain  推流域名（用于 tcUrl）
  --params  鉴权参数，如 "e=1687486713&token=xxx"
  --no-loop 不循环推流（默认循环）
  --recode  重新编码（默认 copy 模式）
  --extra   额外 ffmpeg 参数

示例:
  ./jf_push.sh --ip 10.210.32.28 --domain qa-publish-callback.com --app qa-test --stream liyan_test --video test.mp4
  ./jf_push.sh --ip 10.210.32.28 --app qa-test --stream liyan_test --video test.mp4 --no-loop
  ./jf_push.sh --ip 10.210.32.28 --app qa-test --stream liyan_test --video test.mp4 --recode
EOF
}

# ========== 解析参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)       IP="$2";       shift 2 ;;
        --domain)   DOMAIN="$2";    shift 2 ;;
        --app)      APP="$2";      shift 2 ;;
        --stream)   STREAM="$2";   shift 2 ;;
        --video)    VIDEO="$2";     shift 2 ;;
        --params)   PARAMS="$2";    shift 2 ;;
        --no-loop)  NO_LOOP=true;   shift ;;
        --recode)   RECODE=true;    shift ;;
        --extra)    EXTRA_ARGS="$2"; shift 2 ;;
        -h|--help)  show_help; exit 0 ;;
        *)          log_error "未知参数: $1"; show_help; exit 1 ;;
    esac
done

# ========== 检查必填参数 ==========
if [[ -z "$IP" ]] || [[ -z "$APP" ]] || [[ -z "$STREAM" ]] || [[ -z "$VIDEO" ]]; then
    log_error "缺少必填参数"
    show_help
    exit 1
fi

# ========== 检查 ffmpeg ==========
if ! command -v ffmpeg &>/dev/null; then
    log_error "ffmpeg 未安装，请先安装: brew install ffmpeg"
    exit 1
fi

# ========== 检查/生成视频文件 ==========
if [[ ! -f "$VIDEO" ]]; then
    log_info "视频文件不存在，生成测试视频..."
    VIDEO="/tmp/test_stream_$$.mp4"
    ffmpeg -f lavfi -i "testsrc=1280x720:rate=30" -f lavfi -i sine=frequency=440 -t 30 \
           -c:v libx264 -c:a aac -f mp4 "$VIDEO" -y 2>/dev/null
    log_info "测试视频已生成: $VIDEO ($VIDEO_SIZE)"
fi

VIDEO_SIZE=$(du -h "$VIDEO" | cut -f1)
log_info "视频文件: $VIDEO ($VIDEO_SIZE)"

# ========== 探测视频信息 ==========
probe_video() {
    if command -v ffprobe &>/dev/null; then
        log_info "视频信息:"
        ffprobe -v quiet -print_format json -show_format -show_streams "$VIDEO" 2>/dev/null | \
            python3 -c "
import sys, json
d = json.load(sys.stdin)
fmt = d.get('format', {})
duration = float(fmt.get('duration', 0))
print(f'  时长: {duration:.1f}s')
for s in d.get('streams', []):
    ct = s.get('codec_type', '')
    if ct == 'video':
        print(f'  视频: {s.get(\"codec_name\")} {s.get(\"width\")}x{s.get(\"height\")} {s.get(\"r_frame_rate\")}')
    elif ct == 'audio':
        print(f'  音频: {s.get(\"codec_name\")} {s.get(\"sample_rate\")}Hz')
" 2>/dev/null || true
    fi
}
probe_video

# ========== 构建 RTMP URL ==========
RTMP_URL="rtmp://${IP}/${APP}/${STREAM}"
if [[ -n "$PARAMS" ]]; then
    RTMP_URL+="?${PARAMS}"
fi

# ========== 构建 tcUrl ==========
TC_URL=""
if [[ -n "$DOMAIN" ]]; then
    TC_URL="rtmp://${DOMAIN}/${APP}"
    if [[ -n "$PARAMS" ]]; then
        TC_URL+="?${PARAMS}"
    fi
fi

# ========== 打印推流信息 ==========
echo ""
echo "=============================================="
echo "  JF 推流任务"
echo "=============================================="
echo "  目标 IP:   $IP"
echo "  推流域名:  ${DOMAIN:-未指定}"
echo "  App:       $APP"
echo "  Stream:    $STREAM"
echo "  视频文件:  $VIDEO"
echo "  RTMP URL:  $RTMP_URL"
[[ -n "$DOMAIN" ]] && echo "  tcUrl:     $TC_URL"
[[ -n "$PARAMS" ]] && echo "  鉴权参数:  $PARAMS"
echo "  循环推流:  $([[ "$NO_LOOP" == true ]] && echo "否" || echo "是")"
echo "  编码模式:  $([[ "$RECODE" == true ]] && echo "重新编码" || echo "复制（不重新编码）")"
echo "=============================================="

# ========== 构建 ffmpeg 命令 ==========
CMD=("ffmpeg")

if [[ "$NO_LOOP" == false ]]; then
    CMD+=("-stream_loop" "-1")
fi

CMD+=("-re" "-i" "$VIDEO" "-f" "flv")

if [[ "$RECODE" == true ]]; then
    CMD+=("-acodec" "aac" "-vcodec" "h264")
else
    CMD+=("-acodec" "copy" "-vcodec" "copy")
fi

if [[ -n "$TC_URL" ]]; then
    CMD+=("-rtmp_tcurl" "$TC_URL")
fi

if [[ -n "$EXTRA_ARGS" ]]; then
    CMD+=($EXTRA_ARGS)
fi

CMD+=("$RTMP_URL")

echo ""
log_info "FFmpeg 命令:"
echo "  ${CMD[*]}"
echo ""
log_info "按 Ctrl+C 停止推流"
echo ""

# ========== 清理函数 ==========
cleanup() {
    log_info "停止推流进程..."
    kill $PUSH_PID 2>/dev/null || true
    wait $PUSH_PID 2>/dev/null || true
    log_info "推流已停止"
}
trap cleanup EXIT INT TERM

# ========== 执行推流 ==========
PUSH_LOG="/tmp/ffmpeg_push_$$.log"
"${CMD[@]}" > "$PUSH_LOG" 2>&1 &
PUSH_PID=$!

log_push "推流进程 PID: $PUSH_PID"

# 实时输出日志
start_time=$(date +%s)
frame_count=0
while kill -0 $PUSH_PID 2>/dev/null; do
    if [[ -s "$PUSH_LOG" ]]; then
        # 获取最新行
        tail -1 "$PUSH_LOG" | while read -r line; do
            elapsed=$(($(date +%s) - start_time))
            if [[ "$line" == *"frame="* ]] && [[ "$line" == *"fps="* ]]; then
                frame_count=$((frame_count + 1))
                if [[ $((frame_count % 30)) -eq 1 ]]; then
                    echo -e "  [${elapsed}s] $line"
                fi
            elif [[ -n "$line" ]] && [[ "$line" != *"Press"* ]]; then
                echo -e "  $line"
            fi
        done
    fi
    sleep 1
done

# 检查结果
wait $PUSH_PID
RET=$?

echo ""
if [[ $RET -eq 0 ]] || [[ $RET -eq 255 ]]; then
    log_info "推流正常结束"
else
    log_error "推流失败，ffmpeg 返回码: $RET"
    log_error "日志: $PUSH_LOG"
    cat "$PUSH_LOG"
    exit $RET
fi

rm -f "$PUSH_LOG" 2>/dev/null || true