# JF 推拉流测试脚本

## 快速开始

```bash
# 测试 vzan bucket
./jf_bucket_test.sh --bucket vzan

# 测试 qa-test bucket
./jf_bucket_test.sh --bucket qa-test
```

## 脚本说明

| 脚本 | 说明 |
|------|------|
| `jf_bucket_test.sh` | 入口脚本，按 bucket 分组配置 |
| `jf_stream_test.sh` | 推拉流主流程（推流 → FLV 拉流 → HLS 拉流） |
| `jf_push.sh` | 推流脚本 |
| `jf_pull_flv.sh` | FLV 拉流测试 |
| `jf_pull_hls.sh` | HLS 拉流测试 |

## Bucket 配置

| Bucket | 推流 IP | 推流域名 | 拉流域名 |
|--------|---------|----------|----------|
| vzan | 10.210.32.28 | push-jfcs59.vzan.com | pull-my-source.vzan.com |
| qa-test | 10.210.32.28 | qa-publish-qnsdk.com | liyan-pull.test.com |

## 测试命令

### vzan bucket

```bash
./jf_bucket_test.sh --bucket vzan
```

### qa-test bucket

```bash
./jf_bucket_test.sh --bucket qa-test
```

### 指定 Stream 名称

```bash
./jf_bucket_test.sh --bucket vzan --stream my_stream
```

## 底层调用（可选）

如果需要更细粒度控制，可直接调用 `jf_stream_test.sh`：

```bash
./jf_stream_test.sh \
    --ip 10.210.32.28 \
    --domain push-jfcs59.vzan.com \
    --pull-domain pull-my-source.vzan.com \
    --app vzan \
    --stream liyan_test
```

## 测试结果解读

```
==============================================
  测试结果汇总
==============================================
  推流:   ✓ 运行中 (PID: xxx)
  FLV:    ✓ 成功
  HLS:    ✓ 成功
==============================================
```

- **推流**：显示进程 PID 表示推流正常
- **FLV**：RTMP over HTTP 拉流
- **HLS**：m3u8 播放列表 + ts 片段下载
