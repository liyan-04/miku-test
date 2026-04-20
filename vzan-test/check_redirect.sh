#!/bin/bash
URL="${1:-http://pull-gy1.vzan.com/1000926916/412514442310537988/112891393043-3-1337996_2903_1_d0.ts}"
RESOLVE="${2:---resolve pull-gy1.vzan.com:80:183.60.220.70}"

echo "URL: $URL"
echo ""

# 1. 首次请求，不跟随重定向
echo "=== 首次请求（不跟随重定向）==="
curl -s -D - -o /dev/null $RESOLVE --connect-timeout 10 --max-time 30 "$URL" | grep -i "^HTTP\|^[Ll]ocation\|^[Ss]erver\|^[Cc]ontent\|^[Dd]ate"

# 2. 跟随重定向，获取最终响应
echo ""
echo "=== 跟随重定向后的最终响应 ==="
curl -s -L -o /dev/null -w "状态码: %{http_code}\n大小: %{size_download} bytes\n重定向次数: %{num_redirects}\n" $RESOLVE --connect-timeout 10 --max-time 30 "$URL"
