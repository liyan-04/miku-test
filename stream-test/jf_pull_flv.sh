#!/bin/bash
#
# JF FLV 拉流测试脚本
#
# 用法:
#   ./jf_pull_flv.sh --domain <拉流域名> --app <app> --stream <stream> [--duration <秒>]
#
# 示例:
#   ./jf_pull_flv.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
#   ./jf_pull_flv.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test --duration 10
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
  ./jf_pull_flv.sh --domain <domain> --app <app> --stream <stream> [--duration <秒>]

必填参数:
  --domain  拉流域名
  --app     app 名称
  --stream  流名称

可选参数:
  --duration 拉流探测时长（默认 5 秒）

示例:
  ./jf_pull_flv.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test
  ./jf_pull_flv.sh --domain liyan-pull.test.com --app qa-test --stream liyan_test --duration 10
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
log_info "首次请求响应详情:"
FLV_HEADERS="/tmp/flv_headers_$$.txt"
FLV_DATA="/tmp/flv_data_$$.flv"

# Step 1: 获取首次请求响应（不跟随重定向，获取响应码和 Location）
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -D "$FLV_HEADERS" --connect-timeout 5 --max-time 10 "$URL_FLV" 2>/dev/null)
log_info "  首次响应码: $RESPONSE_CODE"

if [[ "$RESPONSE_CODE" == "302" ]] || [[ "$RESPONSE_CODE" == "301" ]]; then
    log_info "  检测到重定向，Location 信息:"
    grep -i "^Location:" "$FLV_HEADERS" | while read -r line; do
        log_info "    $line"
    done
fi

# Step 2: 下载 FLV 数据（duration 秒后 kill）
log_info "下载 FLV 数据（${DURATION}s）..."
curl -s -L --max-redirs 5 --connect-timeout 5 --max-time "$DURATION" "$URL_FLV" -o "$FLV_DATA" 2>/dev/null &
CURL_PID=$!

sleep "$DURATION"
if kill -0 $CURL_PID 2>/dev/null; then
    log_info "  下载已达 ${DURATION}s，主动结束"
    kill -9 $CURL_PID 2>/dev/null || true
    wait $CURL_PID 2>/dev/null || true
else
    wait $CURL_PID 2>/dev/null || true
fi

# 检查下载结果
if [[ -f "$FLV_DATA" ]] && [[ -s "$FLV_DATA" ]]; then
    FLV_SIZE=$(du -h "$FLV_DATA" | cut -f1)
    log_info "  下载完成: $FLV_SIZE"
else
    log_warn "  下载失败或文件为空"
fi

# Step 3: 使用 ffprobe 分析下载的 FLV 数据
FLV_FRAMES="/tmp/flv_frames_$$.txt"
if [[ -f "$FLV_DATA" ]] && [[ -s "$FLV_DATA" ]]; then
    ffprobe -v quiet -show_frames "$FLV_DATA" > "$FLV_FRAMES" 2>&1

    if grep -q 'media_type=video' "$FLV_FRAMES" 2>/dev/null; then
        log_info "✓ FLV 流探测成功"

        # 使用 ffprobe JSON 输出分析帧信息
        ffprobe -v quiet -print_format json -show_streams -show_frames "$FLV_DATA" 2>/dev/null | python3 -c "
import sys,json

d = json.load(sys.stdin)

# 流信息
streams = d.get('streams', [])
v_stream = next((s for s in streams if s.get('codec_type') == 'video'), {})
a_stream = next((s for s in streams if s.get('codec_type') == 'audio'), {})

# 帧信息
frames = d.get('frames', [])
video_frames = [f for f in frames if f.get('media_type') == 'video']
audio_frames = [f for f in frames if f.get('media_type') == 'audio']

i_frames = [f for f in video_frames if f.get('pict_type') == 'I']
p_frames = [f for f in video_frames if f.get('pict_type') == 'P']
b_frames = [f for f in video_frames if f.get('pict_type') == 'B']

video_res = f'{v_stream.get(\"width\")}x{v_stream.get(\"height\")}'
audio_sr = a_stream.get('sample_rate', 'unknown')

print(f'    - video: h264 {video_res} ({len(video_frames)} 帧)')
print(f'    - audio: aac {audio_sr}Hz ({len(audio_frames)} 帧)')

# GOP 分析
gop_durations = []
last_i_time = None
for f in video_frames:
    pts = f.get('pts_time')
    if pts and f.get('pict_type') == 'I':
        pts = float(pts)
        if last_i_time is not None:
            gop_durations.append(pts - last_i_time)
        last_i_time = pts

if i_frames:
    first_pts = float(i_frames[0].get('pts_time', 0))
    last_pts = float(video_frames[-1].get('pts_time', 0))
    print(f'    视频流时长: {last_pts - first_pts:.1f}s')

if gop_durations:
    print(f'    I 帧数: {len(i_frames)}, P 帧数: {len(p_frames)}, B 帧数: {len(b_frames)}')
    print(f'    GOP: {len(gop_durations)} 个, 平均时长: {sum(gop_durations)/len(gop_durations):.2f}s')
    gop_list = ', '.join([f'{g:.2f}s' for g in gop_durations])
    print(f'    GOP 时长列表: [{gop_list}]')

# 音频格式
if audio_frames:
    af = audio_frames[0]
    print(f'    音频格式: sample_fmt={af.get(\"sample_fmt\")}, channels={af.get(\"channels\")}, nb_samples={af.get(\"nb_samples\")}')
" 2>/dev/null || true
        FLV_RESULT="成功"
    else
        log_warn "FLV 流探测无结果（服务未开启或流不存在）"
        FLV_RESULT="失败"
    fi
else
    log_warn "FLV 流探测无结果（下载失败）"
    FLV_RESULT="失败"
fi

# ========== 清理临时文件 ==========
rm -f "$FLV_DATA" "$FLV_FRAMES" "$FLV_HEADERS" 2>/dev/null || true

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