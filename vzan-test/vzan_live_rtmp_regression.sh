#!/bin/bash
# RTMP 回源模式回归测试（并发版）

IP="${1:-127.0.0.1}"
ZBID="54184051"
TPID="115906963"
STREAM_ID="1241447776_719317893095371490"
TMP_DIR="/tmp/rtmp_test_$$"

mkdir -p "$TMP_DIR"
trap "rm -rf $TMP_DIR" EXIT

# 直播域名列表
DOMAINS=(
  "r2.vzan.com"
  "r8.vzan.com"
  "pull-hsbj.vzan.com"
  "pull-hssh.vzan.com"
  "pull-txnj.njyqkj0ksyz.cc"
  "pull-hwgy-yq.njyqkj0ksyz.cc"
  "pull-hsbj-yq.njyqkj0ksyz.cc"
  "pull-hssh-yq.njyqkj0ksyz.cc"
  "pull-txnj-yq.njyqkj0ksyz.cc"
)

echo "IP: $IP"
echo "=========================================="
echo "开始时间: $(date '+%H:%M:%S')"
echo ""

PASS=0
FAIL=0

# ========== RTMP 拉流测试 (并发) ==========
echo "=== RTMP 拉流测试 (source pull) ==="
for domain in "${DOMAINS[@]}"; do
  rtmp_url="rtmp://${domain}/v/${ZBID}_${STREAM_ID}?zbid=${ZBID}&tpid=${TPID}"
  (
    result=$(perl -e 'alarm 10; exec @ARGV' ffmpeg -v error -i "$rtmp_url" -f null - 2>&1 || true)
    # 写入结果: 第一行是result, 第二行是domain
    echo "$result" > "$TMP_DIR/pull_${domain}.result"
    echo "$domain" >> "$TMP_DIR/pull_${domain}.result"
    echo "$rtmp_url" > "$TMP_DIR/pull_${domain}.url"
  ) &
done
wait

for domain in "${DOMAINS[@]}"; do
  rtmp_url=$(cat "$TMP_DIR/pull_${domain}.url")
  result=$(sed '$d' "$TMP_DIR/pull_${domain}.result")

  echo "URL: $rtmp_url"
  if echo "$result" | grep -qE "[0-9]+\.[0-9]+fps|[0-9]+ fps"; then
    echo "    -> ✅ 拉流正常"
    PASS=$((PASS + 1))
  elif echo "$result" | grep -qE "Connection refused|Server error|Invalid|closed|No such"; then
    echo "    -> ❌ 连接失败: $(echo $result | head -c 100)"
    FAIL=$((FAIL + 1))
  else
    echo "    -> ⚠️  $(echo $result | head -c 100)"
    FAIL=$((FAIL + 1))
  fi
done

echo ""

# ========== RTMP 播放测试 (并发) ==========
echo "=== RTMP 播放测试 ==="
for domain in "${DOMAINS[@]}"; do
  rtmp_play_url="rtmp://${domain}/v/${STREAM_ID}"
  (
    result=$(perl -e 'alarm 10; exec @ARGV' ffprobe -v error -i "$rtmp_play_url" 2>&1 || true)
    echo "$result" > "$TMP_DIR/play_${domain}.result"
    echo "$domain" >> "$TMP_DIR/play_${domain}.result"
    echo "$rtmp_play_url" > "$TMP_DIR/play_${domain}.url"
  ) &
done
wait

for domain in "${DOMAINS[@]}"; do
  rtmp_play_url=$(cat "$TMP_DIR/play_${domain}.url")
  result=$(sed '$d' "$TMP_DIR/play_${domain}.result")

  echo "URL: $rtmp_play_url"
  if echo "$result" | grep -qE "[0-9]+\.[0-9]+fps|[0-9]+ fps"; then
    echo "    -> ✅ 播放正常"
    PASS=$((PASS + 1))
  elif echo "$result" | grep -qE "Connection refused|Server error|Invalid|closed|No such"; then
    echo "    -> ❌ 连接失败: $(echo $result | head -c 100)"
    FAIL=$((FAIL + 1))
  else
    echo "    -> ⚠️  $(echo $result | head -c 100)"
    FAIL=$((FAIL + 1))
  fi
done

echo ""

# ========== FLV 播放测试 (并发) ==========
echo "=== FLV 播放测试 (HTTP) ==="
for domain in "${DOMAINS[@]}"; do
  flv_url="https://${domain}/v/${STREAM_ID}.flv"
  (
    curl -s -L -o /dev/null -w "%{http_code}|%{redirect_url}" --resolve "${domain}:443:${IP}" --connect-timeout 10 --max-time 30 "$flv_url" > "$TMP_DIR/flv_${domain}.result"
    echo "$domain" >> "$TMP_DIR/flv_${domain}.result"
    echo "$flv_url" > "$TMP_DIR/flv_${domain}.url"
  ) &
done
wait

for domain in "${DOMAINS[@]}"; do
  flv_url=$(cat "$TMP_DIR/flv_${domain}.url")
  curl_result=$(sed '$d' "$TMP_DIR/flv_${domain}.result")

  http_code=$(echo "$curl_result" | cut -d'|' -f1)
  final_url=$(echo "$curl_result" | cut -d'|' -f2 | tr -d '\r')

  echo "URL: $flv_url"
  if [[ "$http_code" == "200" ]]; then
    echo "    -> ✅ 200 -> $final_url"
    PASS=$((PASS + 1))
  elif [[ "$http_code" == "302" ]] || [[ "$http_code" == "301" ]]; then
    echo "    -> ✅ 重定向 $http_code -> $final_url"
    PASS=$((PASS + 1))
  else
    echo "    -> ❌ $http_code"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=========================================="
echo "结束时间: $(date '+%H:%M:%S')"
echo "通过: $PASS | 失败: $FAIL"
