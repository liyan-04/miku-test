#!/bin/bash
# 现网测试 - ts 文件

echo "=== 非 VOD 模式 ==="
./check_redirect.sh \
  "http://pull-gy1.vzan.com/1000926916/412514442310537988/112891393043-3-1337996_2903_1_d0.ts" \
  "--resolve pull-gy1.vzan.com:80:183.60.220.70"

echo ""
echo "=== VOD 模式 ==="
./check_redirect.sh \
  "http://pull-gy1.vzan.com/1000926916/412514442310537988/112891393043-3-1337996_2903_1_d0.ts?qiniuvodi7kWcaHLk4=1" \
  "--resolve pull-gy1.vzan.com:80:183.60.220.70"
