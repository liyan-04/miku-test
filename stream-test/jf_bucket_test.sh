#!/bin/bash
#
# JF Bucket 推拉流测试脚本
#
# 用法:
#   ./jf_bucket_test.sh [--bucket <bucket-name>] [--stream <stream-name>]
#
# 支持的 bucket:
#   qa-test (默认) - 推流域名: qa-publish-qnsdk.com, 拉流域名: liyan-pull.test.com, 推流IP: 10.210.32.28
#   vzan          - 推流域名: push-jfcs59.vzan.com, 拉流域名: pull-gy1.vzan.com, 推流IP: 10.210.32.28
#
# 示例:
#   ./jf_bucket_test.sh                    # 测试默认 qa-test
#   ./jf_bucket_test.sh --bucket vzan      # 测试 vzan bucket
#

set -e

# ========== Bucket 配置 ==========
BUCKET_QA_TEST="10.210.32.28|qa-publish-qnsdk.com|liyan-pull.test.com"
BUCKET_VZAN="10.210.32.28|push-jfcs59.vzan.com|pull-my-source.vzan.com"

# ========== 默认配置 ==========
BUCKET="qa-test"
STREAM="liyan_test"

# ========== 帮助信息 ==========
show_help() {
    cat << EOF
JF Bucket 推拉流测试脚本

用法:
  ./jf_bucket_test.sh [--bucket <bucket-name>] [--stream <stream-name>]

支持的 bucket:
  qa-test (默认) - 推流IP: 10.210.32.28
                   推流域名: qa-publish-qnsdk.com
                   拉流域名: liyan-pull.test.com

  vzan          - 推流IP: 10.210.32.28
                   推流域名: push-jfcs59.vzan.com
                   拉流域名: pull-gy1.vzan.com

示例:
  ./jf_bucket_test.sh                    # 测试 qa-test
  ./jf_bucket_test.sh --bucket vzan      # 测试 vzan
  ./jf_bucket_test.sh --bucket vzan --stream my_stream
EOF
}

# ========== 解析参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket)  BUCKET="$2";  shift 2 ;;
        --stream)  STREAM="$2";  shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *)         echo "未知参数: $1"; show_help; exit 1 ;;
    esac
done

# ========== 查找 bucket 配置 ==========
case "$BUCKET" in
    qa-test)  CONFIG="$BUCKET_QA_TEST" ;;
    vzan)     CONFIG="$BUCKET_VZAN" ;;
    *)       echo "不支持的 bucket: $BUCKET"
            echo "支持的 bucket: qa-test, vzan"
            exit 1 ;;
esac

# ========== 解析配置 ==========
IFS='|' read -r PUSH_IP PUSH_DOMAIN PULL_DOMAIN <<< "$CONFIG"

# ========== 脚本路径 ==========
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STREAM_TEST_SCRIPT="${SCRIPT_DIR}/jf_stream_test.sh"

if [[ ! -f "$STREAM_TEST_SCRIPT" ]]; then
    echo "错误: jf_stream_test.sh 脚本不存在"
    exit 1
fi

# ========== 执行测试 ==========
echo ""
echo "=============================================="
echo "  JF Bucket 测试"
echo "=============================================="
echo "  Bucket:    $BUCKET"
echo "  推流 IP:   $PUSH_IP"
echo "  推流域名:  $PUSH_DOMAIN"
echo "  拉流域名:  $PULL_DOMAIN"
echo "  Stream:    $STREAM"
echo "=============================================="
echo ""

"$STREAM_TEST_SCRIPT" \
    --ip "$PUSH_IP" \
    --domain "$PUSH_DOMAIN" \
    --pull-domain "$PULL_DOMAIN" \
    --app "$BUCKET" \
    --stream "$STREAM"