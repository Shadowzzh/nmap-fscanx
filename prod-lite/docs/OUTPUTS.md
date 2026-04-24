# 输出文件

默认输出目录来自：

- 当前执行目录下的 `./scans`

如果命令行传了 `--scan-root`，就以命令行为准。

这里要区分两层“输出”：

- `--scan-root` 控制的是 `nmap-fscanx` 这套流程的产物根目录
- `fscanx` 自身在每个阶段工作目录里默认写的是 `result.txt`

当前接入的上游 `fscanx` 语义是：

- `-json` 只会把 `result.txt` 里的内容改成 JSON 片段
- `-json` 不会把结果改成输出到 `stdout`
- `-json` 也不会自动把文件名改成 `result.json`

## 1. 现场顺序和结果依赖

现场推荐顺序是：

1. 先执行 `phase1`
2. 先看 `phase1/alive_ips.txt` 和 `phase1/phase1.summary.json`
3. 确认需要继续后，再执行 `phase2`

要点只有一个：

- `phase2` 读取的是同一个 `--scan-root` 下的 `phase1/alive_ips.txt`

这意味着：

- 单独执行 `phase2` 时，`--scan-root` 必须和之前执行 `phase1` 时保持一致
- 如果只是想重跑第二阶段，不需要重跑第一阶段，但仍然要复用原来的 `phase1/alive_ips.txt`

## 2. 目录结构

每次扫描默认生成：

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

## 3. 最重要的文件

### `input.json`

记录本次运行参数，适合做审计和复现。

### `phase1/alive_ips.txt`

第一阶段提取出的唯一 IP 列表。  
它不是“全网所有在线 IP”，而是“命中第一阶段重点端口的 IP”。

单独执行 `phase1` 时，优先看这个文件和 `phase1/phase1.summary.json`。
现场通常也是先确认这个文件，再决定是否进入第二阶段。

### `phase2/open_ip_port.txt`

第二阶段提取出的唯一 `IP:PORT` 列表。
它只会在 `phase2` 执行后更新，输入来自同一个 `scan-root` 下的 `phase1/alive_ips.txt`。

### `report.json`

最终汇总报告。  
如果只需要看最终统计，优先看这个文件。  
它只在执行完整流程或执行 `phase2` 后可靠；单独重跑 `phase1` 时，旧的 `report.json` 会被清理，避免误读旧结果。

## 4. 常见查看方式

看第一阶段命中的主机：

```bash
cat <scan-root>/phase1/alive_ips.txt
```

看第一阶段摘要：

```bash
jq '.' <scan-root>/phase1/phase1.summary.json
```

看第二阶段扫出的资产：

```bash
cat <scan-root>/phase2/open_ip_port.txt
```

看最终报告：

```bash
jq '.' <scan-root>/report.json
```

只看主机数和资产数：

```bash
jq '.phase1.alive_ip_count, .phase2.open_ip_port_count' <scan-root>/report.json
```

## 5. 排错时优先看什么

如果怀疑执行有问题，优先看：

- `phase1/console.log`
- `phase2/console.log`
- `phase1/result.txt`
- `phase2/result.txt`

实时跟日志时可以直接：

```bash
tail -f <scan-root>/phase1/console.log
tail -f <scan-root>/phase2/console.log
```

如果只是想确认最终结果，优先看：

- `phase1/alive_ips.txt`
- `phase1/phase1.summary.json`
- `phase2/open_ip_port.txt`
- `report.json`
