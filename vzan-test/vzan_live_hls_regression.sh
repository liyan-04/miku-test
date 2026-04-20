#!/bin/bash
# 伪直播模式回归测试

IP="${1:-183.60.220.70}"
URL_PATH_TS="1000926916/412514442310537988/112891393043-3-1337996_2903_1_d0.ts"
URL_PATH_M3U8="1000926916/412514442310537988/replay.1744797843.68854862.m3u8"
VOD_PARAM="?qiniuvodi7kWcaHLk4=1"

# vzan.com 域名
DOMAINS_VZAN=(
  "pull-gy1.vzan.com"
  "pull-hs1.vzan.com"
  "pull-hs2.vzan.com"
  "pull-hs3.vzan.com"
  "pull-hssh1.vzan.com"
  "pull-tx1.vzan.com"
)

# wbzt2.cn 域名
DOMAINS_WBZT2=(
  "pull-gy1.wbzt2.cn"
  "pull-hs1.wbzt2.cn"
  "pull-hs2.wbzt2.cn"
  "pull-hs3.wbzt2.cn"
  "pull-hssh1.wbzt2.cn"
  "pull-tx1.wbzt2.cn"
)

# whzxykjyxgsaac.cn 域名
DOMAINS_WHZXY=(
  "pull-gy1.whzxykjyxgsaac.cn"
  "pull-hs1.whzxykjyxgsaac.cn"
  "pull-hs2.whzxykjyxgsaac.cn"
  "pull-hs3.whzxykjyxgsaac.cn"
  "pull-hssh1.whzxykjyxgsaac.cn"
  "pull-tx1.whzxykjyxgsaac.cn"
)

PASS=0
FAIL=0

echo "IP: $IP"
echo "=========================================="

# TS 文件测试
echo "=== TS 非 VOD 模式 ==="
for domain in "${DOMAINS_VZAN[@]}" "${DOMAINS_WBZT2[@]}" "${DOMAINS_WHZXY[@]}"; do
  url="http://${domain}/${URL_PATH_TS}"
  
  # 首次请求，获取302状态码和重定向目标
  first_resp=$(curl -s -D - -o /dev/null --resolve "${domain}:80:${IP}" --connect-timeout 10 --max-time 30 "$url" 2>&1)
  first_code=$(echo "$first_resp" | grep -i "^HTTP" | tail -1 | awk '{print $2}')
  redirect_url=$(echo "$first_resp" | grep -i "^Location:" | sed 's/^[Ll]ocation: *//I' | tr -d '\r')
  
  # 最终请求
  result=$(./check_redirect.sh "$url" "--resolve ${domain}:80:${IP}" 2>&1)
  final_code=$(echo "$result" | grep "状态码:" | awk '{print $2}')
  size=$(echo "$result" | grep "大小:" | awk '{print $2}')

  if [[ "$final_code" == "200" ]]; then
    if [[ -n "$redirect_url" ]]; then
      printf "%s ✅ %s -> %s ✅ %s %s\n" "$url" "$first_code" "$redirect_url" "$final_code" "$size"
    else
      printf "%s ✅ %s %s\n" "$url" "$final_code" "$size"
    fi
    PASS=$((PASS + 1))
  else
    if [[ -n "$redirect_url" ]]; then
      printf "%s ✅ %s -> %s ❌ %s\n" "$url" "$first_code" "$redirect_url" "$final_code"
    else
      printf "%s ❌ %s\n" "$url" "$final_code"
    fi
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=== TS VOD 模式 ==="
for domain in "${DOMAINS_VZAN[@]}" "${DOMAINS_WBZT2[@]}" "${DOMAINS_WHZXY[@]}"; do
  url="http://${domain}/${URL_PATH_TS}${VOD_PARAM}"
  
  # 首次请求，获取302状态码和重定向目标
  first_resp=$(curl -s -D - -o /dev/null --resolve "${domain}:80:${IP}" --connect-timeout 10 --max-time 30 "$url" 2>&1)
  first_code=$(echo "$first_resp" | grep -i "^HTTP" | tail -1 | awk '{print $2}')
  redirect_url=$(echo "$first_resp" | grep -i "^Location:" | sed 's/^[Ll]ocation: *//I' | tr -d '\r')
  
  # 最终请求
  result=$(./check_redirect.sh "$url" "--resolve ${domain}:80:${IP}" 2>&1)
  final_code=$(echo "$result" | grep "状态码:" | awk '{print $2}')
  size=$(echo "$result" | grep "大小:" | awk '{print $2}')

  if [[ "$final_code" == "200" ]]; then
    if [[ -n "$redirect_url" ]]; then
      printf "%s ✅ %s -> %s ✅ %s %s\n" "$url" "$first_code" "$redirect_url" "$final_code" "$size"
    else
      printf "%s ✅ %s %s\n" "$url" "$final_code" "$size"
    fi
    PASS=$((PASS + 1))
  else
    if [[ -n "$redirect_url" ]]; then
      printf "%s ✅ %s -> %s ❌ %s\n" "$url" "$first_code" "$redirect_url" "$final_code"
    else
      printf "%s ❌ %s\n" "$url" "$final_code"
    fi
    FAIL=$((FAIL + 1))
  fi
done

# M3U8 文件测试
echo ""
echo "=== M3U8 非 VOD 模式 ==="
for domain in "${DOMAINS_VZAN[@]}" "${DOMAINS_WBZT2[@]}" "${DOMAINS_WHZXY[@]}"; do
  m3u8_url="http://${domain}/${URL_PATH_M3U8}"
  m3u8_tmp="/tmp/m3u8_$$_$(date +%s).txt"

  # 下载 m3u8 文件
  curl -s -L --resolve "${domain}:80:${IP}" --connect-timeout 10 --max-time 30 "$m3u8_url" -o "$m3u8_tmp"

  if [[ -f "$m3u8_tmp" ]] && grep -q "EXTM3U" "$m3u8_tmp" 2>/dev/null; then
    # 提取第一个 ts 片段
    first_ts=$(grep -v '#' "$m3u8_tmp" | grep -v '^$' | head -1)
    rm -f "$m3u8_tmp"

    if [[ -n "$first_ts" ]]; then
      # 拼接完整 ts URL
      if [[ "$first_ts" == http* ]]; then
        ts_url="$first_ts"
      else
        ts_url="http://${domain}/${first_ts}"
      fi

      # 下载 ts 验证
      ts_size=$(curl -s -L -o /dev/null -w "%{size_download}" --resolve "${domain}:80:${IP}" --connect-timeout 10 --max-time 30 "$ts_url")
      ts_code=$(curl -s -L -o /dev/null -w "%{http_code}" --resolve "${domain}:80:${IP}" --connect-timeout 10 --max-time 30 "$ts_url")

      if [[ "$ts_code" == "200" ]]; then
        printf "%-30s ✅ %s %s\n" "$domain" "$ts_code" "$ts_size"
        PASS=$((PASS + 1))
      else
        printf "%-30s ❌ ts %s\n" "$domain" "$ts_code"
        FAIL=$((FAIL + 1))
      fi
    else
      printf "%-30s ❌ 无ts片段\n" "$domain"
      FAIL=$((FAIL + 1))
      rm -f "$m3u8_tmp"
    fi
  else
    rm -f "$m3u8_tmp"
    printf "%-30s ❌ m3u8无效\n" "$domain"
    FAIL=$((FAIL + 1))
  fi
done

echo "=========================================="
echo "通过: $PASS | 失败: $FAIL"
