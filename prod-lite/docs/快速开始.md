# 快速开始

## 1. 检查环境

```bash
nmap-fscanx check
```

如果 `SCANNER_STATUS`、`JQ_STATUS`、`TMUX_STATUS` 不是 `ok`，先不要开始扫。

## 2. 查看当前生效配置

```bash
nmap-fscanx print-config
```

这个命令适合排查：

- 当前到底用了哪一个 `fscanx`
- 当前并发和超时是多少
- 默认扫描输出目录是什么

## 3. 现场推荐流程：先跑第一阶段

```bash
nmap-fscanx phase1 \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "./scans/demo-manual"
```

适合：

- 现场先筛一轮重点端口主机
- 先拿到第一阶段结果，再决定是否进入第二阶段
- 需要人工确认第一阶段命中范围

命令结束后会打印：

- `PHASE1_SUMMARY`
- `ALIVE_IP_COUNT`
- `ALIVE_IP_FILE`
- `ALIVE_IP_PREVIEW`

## 4. 先确认第一阶段结果

常见查看方式：

```bash
cat ./scans/demo-manual/phase1/alive_ips.txt
jq '.' ./scans/demo-manual/phase1/phase1.summary.json
```

这里有两个现场规则：

- 如果 `ALIVE_IP_COUNT=0`，通常没必要再跑第二阶段
- 第二阶段必须复用同一个 `--scan-root`，因为它读取的是 `phase1/alive_ips.txt`

## 5. 确认后再跑第二阶段

```bash
nmap-fscanx phase2 \
  --scan-root "./scans/demo-manual"
```

前提是同一个目录下已经存在 `phase1/alive_ips.txt`。

命令结束后会打印最终 `report.json` 路径。

## 6. 自动串行便捷模式：前台一次跑完

```bash
nmap-fscanx run \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "./scans/demo-all"
```

适合：

- 首次验证环境
- 短任务
- 不需要在第一阶段和第二阶段之间人工停顿

这个命令内部仍然是先跑 `phase1`，再跑 `phase2`，只是中间不会暂停等你确认。

前台会直接显示完整阶段流转，常见输出包括：

- `COMMAND=run`
- `PHASE_START=phase1`
- `PHASE_DONE=phase1`
- `PHASE_START=phase2`
- `PHASE_DONE=phase2`
- `FINAL_REPORT=./scans/demo-all/report.json`

跑完后常见查看方式：

```bash
cat ./scans/demo-all/report.json
cat ./scans/demo-all/phase2/open_ip_port.txt
```

如果想在另一个 shell 里单独跟日志：

```bash
tail -f ./scans/demo-all/phase1/console.log
tail -f ./scans/demo-all/phase2/console.log
```

## 7. 自动串行便捷模式：后台启动 tmux 会话

```bash
nmap-fscanx start \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "./scans/demo-tmux"
```

启动后会打印：

- `SESSION_NAME`
- `ATTACH_COMMAND`
- `SCAN_ROOT`
- `FINAL_REPORT`

适合：

- 已确认要直接自动串行跑完整流程
- 任务较长，想放到 `tmux` 后台执行

## 8. 进入后台会话

```bash
nmap-fscanx attach --session nmap-fscanx-scan-20260424
```

## 9. 示例脚本

包内还提供了下面这些可复制模板：

- `examples/run-all.example.sh`
- `examples/run-phase1.example.sh`
- `examples/run-phase2.example.sh`
