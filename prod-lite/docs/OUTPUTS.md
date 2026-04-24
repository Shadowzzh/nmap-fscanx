# 输出文件

默认输出目录来自：

- 用户级安装：`$HOME/.local/share/nmap-fscanx/scans`
- 系统级安装：`/var/lib/nmap-fscanx/scans`

如果命令行传了 `--scan-root`，就以命令行为准。

## 1. 目录结构

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

## 2. 最重要的文件

### `input.json`

记录本次运行参数，适合做审计和复现。

### `phase1/alive_ips.txt`

第一阶段提取出的唯一 IP 列表。  
它不是“全网所有在线 IP”，而是“命中第一阶段重点端口的 IP”。

单独执行 `phase1` 时，优先看这个文件和 `phase1/phase1.summary.json`。

### `phase2/open_ip_port.txt`

第二阶段提取出的唯一 `IP:PORT` 列表。

### `report.json`

最终汇总报告。  
如果只需要看最终统计，优先看这个文件。  
它只在执行完整流程或执行 `phase2` 后可靠；单独重跑 `phase1` 时，旧的 `report.json` 会被清理，避免误读旧结果。

## 3. 常见查看方式

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

## 4. 排错时优先看什么

如果怀疑执行有问题，优先看：

- `phase1/console.log`
- `phase2/console.log`
- `phase1/result.txt`
- `phase2/result.txt`

如果只是想确认最终结果，优先看：

- `phase1/alive_ips.txt`
- `phase1/phase1.summary.json`
- `phase2/open_ip_port.txt`
- `report.json`
