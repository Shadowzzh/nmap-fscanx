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

## 3. 前台执行完整流程

```bash
nmap-fscanx run \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "$HOME/.local/share/nmap-fscanx/scans/demo-all"
```

适合：

- 首次验证环境
- 短任务
- 需要直接看控制台输出

## 4. 只跑第一阶段

```bash
nmap-fscanx phase1 \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "$HOME/.local/share/nmap-fscanx/scans/demo-phase1"
```

适合：

- 只想快速筛一轮重点端口主机
- 准备后续单独重跑第二阶段

## 5. 只跑第二阶段

```bash
nmap-fscanx phase2 \
  --scan-root "$HOME/.local/share/nmap-fscanx/scans/demo-all"
```

前提是对应目录下已经存在 `phase1/alive_ips.txt`。

## 6. 后台启动 tmux 会话

```bash
nmap-fscanx start \
  --targets '192.168.1.0/24,192.168.20.0/24' \
  --scan-root "$HOME/.local/share/nmap-fscanx/scans/demo-tmux"
```

启动后会打印：

- `SESSION_NAME`
- `ATTACH_COMMAND`
- `SCAN_ROOT`
- `FINAL_REPORT`

## 7. 进入后台会话

```bash
nmap-fscanx attach --session nmap-fscanx-scan-20260424
```

## 8. 示例脚本

包内还提供了下面这些可复制模板：

- `examples/run-all.example.sh`
- `examples/run-phase1.example.sh`
- `examples/run-phase2.example.sh`
