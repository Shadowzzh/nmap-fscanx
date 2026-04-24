# fscanx 详细使用手册

## 1. 手册定位

这份手册面向 `prod-lite` 发布包的实际使用者，重点说明：

- 如何执行两阶段扫描
- 如何用 `tmux` 在后台跑长任务
- 如何正确理解输出文件
- 如果想拿到更多字段，应该看哪里、补什么

它不假设你已经了解上游 `fscanx` 的全部参数。

## 2. 先理解这套流程在做什么

`prod-lite` 不是通用资产平台，也不是标准主机发现工具。

它的默认流程是：

1. 第一阶段扫描重点端口，默认 `22,80,443,445,3389`
2. 命中任意一个重点端口的 IP，进入第二阶段
3. 第二阶段对这些 IP 扫描更大的端口范围，默认 `1-65535`
4. 最终生成固定输出文件和 `report.json`

必须记住的一点：

- `phase1/alive_ips.txt` 的语义是“命中重点端口的 IP”
- 它不是“全网在线主机列表”

## 3. 安装前检查

先确认当前环境是否满足运行要求：

```bash
nmap-fscanx check
```

重点看三项：

- `SCANNER_STATUS=ok`
- `JQ_STATUS=ok`
- `TMUX_STATUS=ok`

如果缺一项，先不要开始扫。

## 4. 查看当前实际生效配置

```bash
nmap-fscanx print-config
```

这个命令常用于排查：

- 当前到底用了哪一个 `fscanx`
- 当前第一阶段和第二阶段端口范围是什么
- 并发和超时是多少
- 默认输出目录是什么

## 5. 最常见的配置项

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `NMAP_FSCANX_PHASE1_PORTS` | `22,80,443,445,3389` | 第一阶段重点端口 |
| `NMAP_FSCANX_PHASE2_PORTS` | `1-65535` | 第二阶段端口范围 |
| `NMAP_FSCANX_THREADS` | `4000` | `fscanx` 并发数 |
| `NMAP_FSCANX_TIMEOUT` | `1` | 单次端口探测超时，单位秒 |
| `NMAP_FSCANX_TMUX_PREFIX` | `nmap-fscanx` | 后台 `tmux` 会话名前缀 |
| `NMAP_FSCANX_SCANNER` | 自动探测 | `fscanx` 可执行文件路径 |
| `NMAP_FSCANX_SCAN_BASE` | 未设置 | 默认扫描输出根目录 |

## 6. 推荐现场流程

### 6.1 第一步：先跑第一阶段

```bash
nmap-fscanx phase1 \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root './scans/onsite-20260424'
```

适合场景：

- 先筛一轮重点端口主机
- 先确认命中范围，再决定是否进入第二阶段
- 希望人工把关第一阶段结果

命令结束后，通常会打印：

- `PHASE1_SUMMARY`
- `ALIVE_IP_COUNT`
- `ALIVE_IP_FILE`
- `ALIVE_IP_PREVIEW`

### 6.2 第二步：确认第一阶段结果

常见查看方式：

```bash
cat ./scans/onsite-20260424/phase1/alive_ips.txt
jq '.' ./scans/onsite-20260424/phase1/phase1.summary.json
```

现场判断建议：

- 如果 `ALIVE_IP_COUNT=0`，通常没必要进入第二阶段
- 如果命中范围明显不符合预期，先排查端口、并发、超时和目标段

### 6.3 第三步：确认后再跑第二阶段

```bash
nmap-fscanx phase2 \
  --scan-root './scans/onsite-20260424'
```

注意：

- 第二阶段必须复用和第一阶段相同的 `--scan-root`
- 因为它读取的是 `phase1/alive_ips.txt`

### 6.4 一次性前台跑完整流程

```bash
nmap-fscanx run \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root './scans/demo-all'
```

适合：

- 短任务
- 首次验证环境
- 不需要人工停在第一阶段审查

### 6.5 长任务放到 `tmux` 后台

推荐直接使用：

```bash
nmap-fscanx start \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root './scans/onsite-20260424' \
  --session 'nmap-fscanx-scan-20260424'
```

进入会话：

```bash
nmap-fscanx attach --session 'nmap-fscanx-scan-20260424'
```

如果没有显式传 `--session`，直接使用 `start` 输出里的 `SESSION_NAME` 或 `ATTACH_COMMAND`。

如果你想直接用原生 `tmux`：

```bash
tmux new -ds 'nmap-fscanx-scan-20260424' \
  "nmap-fscanx run --targets '192.168.1.0/24,192.168.20.0/24' --scan-root './scans/onsite-20260424'"
```

## 7. 目录结构与文件含义

一次完整扫描通常会产生：

```text
<scan-root>/
├── input.json
├── phase1/
│   ├── console.log
│   ├── result.txt
│   ├── normalized.json
│   ├── alive_ips.txt
│   └── phase1.summary.json
├── phase2/
│   ├── console.log
│   ├── result.txt
│   ├── normalized.json
│   ├── open_ip_port.txt
│   └── phase2.summary.json
└── report.json
```

最重要的几个文件：

- `input.json`：记录本次运行参数，适合审计和复现
- `phase1/alive_ips.txt`：第一阶段命中重点端口的 IP 列表
- `phase2/open_ip_port.txt`：第二阶段提取出的唯一 `IP:PORT`
- `report.json`：最终汇总报告
- `phase1/normalized.json`、`phase2/normalized.json`：原始 JSON 数组，适合二次解析更多字段

## 8. 当前最终报告到底包含什么

当前 `report.json` 稳定包含的核心信息只有：

- 第一阶段端口列表
- 第一阶段命中 IP 数量
- 第二阶段端口范围
- 第二阶段 `IP:PORT` 数量
- 最终 `assets` 数组，也就是 `IP:PORT` 列表

如果你的目标是：

- 快速拿到主机和开放端口

那么看 `report.json` 足够。

如果你的目标是：

- 看 OS
- 看 Web 指纹
- 看页面标题
- 看证书
- 看服务版本线索

那么必须继续看 `normalized.json`，不能只看 `report.json`。

## 9. 如何查看原始字段

### 9.1 看开放端口

```bash
jq -r '.[] | select(.type == "Port") | .text' ./scans/onsite-20260424/phase2/normalized.json
```

### 9.2 看 Web 产品、标题、证书、跳转来源

```bash
jq -r '.[] | select(.type == "Product") | .text' ./scans/onsite-20260424/phase2/normalized.json
```

### 9.3 看 OS 线索

```bash
jq -r '.[] | select(.type == "OsInfo") | .text' ./scans/onsite-20260424/phase2/normalized.json
```

### 9.4 看摘要信息

```bash
jq -r '.[] | select(.type == "alive" or .type == "scan") | .text' ./scans/onsite-20260424/phase2/normalized.json
```

注意：

- `alive` 是命中端口摘要，不是主机在线状态清单
- `scan` 是结束摘要，不是资产字段

## 10. 如何从原始字段里提取常见信息

### 10.1 提取唯一 IP

```bash
jq -r '
  .[]
  | select(.type == "Port")
  | try (.text | capture("open\\t(?<ip>[0-9.]+):(?<port>[0-9]+)").ip) catch empty
' ./scans/onsite-20260424/phase1/normalized.json | awk 'NF && !seen[$0]++'
```

### 10.2 提取唯一 `IP:PORT`

```bash
jq -r '
  .[]
  | select(.type == "Port")
  | try (.text | capture("open\\t(?<ip>[0-9.]+):(?<port>[0-9]+)") | "\(.ip):\(.port)") catch empty
' ./scans/onsite-20260424/phase2/normalized.json | awk 'NF && !seen[$0]++'
```

### 10.3 只看 `Product` 原始证据

```bash
jq -r '
  .[]
  | select(.type == "Product")
  | .text
' ./scans/onsite-20260424/phase2/normalized.json
```

### 10.4 只看 `OsInfo` 原始证据

```bash
jq -r '
  .[]
  | select(.type == "OsInfo")
  | .text
' ./scans/onsite-20260424/phase2/normalized.json
```

## 11. `-json` 的真实语义

上游 `fscanx` 的 `-json` 需要这样理解：

- 它只改变结果内容格式
- 默认输出文件名仍然是 `result.txt`
- 不会自动输出到 `stdout`
- 不会自动生成 `result.json`

所以当前流程才会做这一步：

1. 先拿到 `result.txt`
2. 再把按行 JSON 片段包成标准 JSON 数组
3. 输出为 `normalized.json`

## 12. 关于 `-nmap`，当前要怎么理解

上游 `fscanx` 支持 `-nmap`，作用是开启协议识别。

开启后通常更容易拿到：

- 协议名
- 更合理的插件调度
- 部分服务识别线索

但当前 `prod-lite` 默认两阶段流程没有启用 `-nmap`。

因此当前默认交付应按下面理解：

- `Port` 可稳定用于提取 `IP:PORT`
- 协议名、服务名、服务版本不能作为当前默认输出承诺

如果后续要增强字段，一般有两种做法：

- 方案 A：在 `normalized.json` 上补解析
- 方案 B：第二阶段命中后再补跑 `nmap -sV` 或 `nmap -O`

## 13. 常见排错

### 13.1 第一阶段没结果

先检查：

- 目标是否真的开放了第一阶段端口
- `NMAP_FSCANX_PHASE1_PORTS` 是否合理
- `NMAP_FSCANX_TIMEOUT` 是否过小
- 网络是否存在丢包、代理、ACL 限制

查看：

```bash
cat ./scans/onsite-20260424/phase1/console.log
cat ./scans/onsite-20260424/phase1/result.txt
```

### 13.2 第二阶段报缺少 `alive_ips.txt`

说明：

- `phase2` 使用的 `--scan-root` 和之前 `phase1` 不一致

处理方式：

- 重新使用与第一阶段完全相同的 `--scan-root`

### 13.3 想看更多字段，但 `report.json` 没有

这是当前设计如此，不是执行失败。

正确做法：

- 看 `phase1/normalized.json`
- 看 `phase2/normalized.json`
- 或在当前仓库里补结构化解析逻辑

### 13.4 想判断“在线主机数”

不要直接用 `alive_ips.txt` 当标准答案。

因为它只代表：

- 命中重点端口的主机

如果你要做标准活性发现，应单独补：

- `nmap -sn`
- `fping`
- 或其它主机发现方案

## 14. 现场建议口径

建议现场统一这样表述：

- 第一阶段：重点端口筛选
- 第二阶段：对命中主机做深一层端口扫描
- 最终报告：交付 `IP` 和 `IP:PORT`
- 原始证据：保留在 `normalized.json`

这样最不容易误导使用者。

## 15. 建议搭配阅读

- [fscanx字段支持情况说明](./fscanx字段支持情况说明.md)
- [快速开始.md](./快速开始.md)
- [输出.md](./输出.md)
- [安装.md](./安装.md)
