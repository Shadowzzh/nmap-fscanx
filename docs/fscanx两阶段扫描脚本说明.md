# fscanx 两阶段扫描脚本说明

## 1. 目标

`scripts/fscanx_pipeline.sh` 用来把当前仓库里的 `fscanx` 使用方式固定成一个可复跑、可审计的两阶段流程：

1. 第一阶段用少量重点端口快速筛选存活 IP
2. 第二阶段直接读取第一阶段产出的存活 IP 文件，做全端口扫描
3. 最后生成统一的 `report.json`

这个脚本针对的是当前环境里这份 `/tmp/fscanx-bin/fscanx` 的实际行为，而不是上游最新版本的理想行为。

## 2. 背景约束

当前这份 `fscanx` 二进制有几个关键特征：

- `-json` 会把结果写成 JSON 片段，而不是标准 JSON 数组
- `-o` 参数实测不可靠，不能用来控制输出路径
- 结果文件实际会写到当前工作目录下的 `result.txt`

所以脚本的设计核心是：

- 每个阶段都先切到自己的工作目录执行
- 每个阶段都把 `result.txt` 归一化后再解析
- 最后只输出你真正关心的结果：`IP:PORT`

## 3. 依赖

运行脚本前，需要保证这些工具可用：

- `bash`
- `jq`
- `/tmp/fscanx-bin/fscanx`

如果要后台运行，推荐使用：

- `tmux`

## 4. 命令入口

脚本入口：

```bash
bash scripts/fscanx_pipeline.sh <phase1|phase2|all> [参数]
```

查看帮助：

```bash
bash scripts/fscanx_pipeline.sh -h
```

## 5. 参数说明

- `--scanner`
  `fscanx` 二进制路径，默认 `/tmp/fscanx-bin/fscanx`

- `--targets`
  目标网段列表，逗号分隔。`phase1` 和 `all` 必填

- `--phase1-ports`
  第一阶段重点端口，默认 `22,80,443,445,3389`

- `--phase2-ports`
  第二阶段端口范围，默认 `1-65535`

- `--threads`
  传给 `fscanx -t` 的并发参数，默认 `4000`

- `--timeout`
  传给 `fscanx -time` 的超时秒数，默认 `1`

- `--scan-root`
  本次扫描输出目录。默认格式为 `scans/YYYYMMDD-fscanx`

## 6. 运行流程

### 6.1 phase1

`phase1` 的目标是从重点端口命中结果里提取存活 IP。

执行步骤：

1. 创建 `<scan-root>/phase1`
2. 进入这个目录执行：

```bash
/tmp/fscanx-bin/fscanx \
  -h '<targets>' \
  -p '<phase1-ports>' \
  -np \
  -t <threads> \
  -time <timeout> \
  -nocolor \
  -json
```

3. 获取当前目录自动生成的 `result.txt`
4. 把 `result.txt` 包装成标准 JSON 数组，写成 `normalized.json`
5. 只提取 `type == "Port"` 的记录
6. 从这些记录中抽取 IP 并去重
7. 输出 `alive_ips.txt`
8. 输出 `phase1.summary.json`

### 6.2 phase2

`phase2` 的目标是直接读取第一阶段产出的 IP 文件，做全端口扫描。

执行步骤：

1. 检查 `<scan-root>/phase1/alive_ips.txt` 是否存在
2. 如果文件为空，则直接生成空的第二阶段结果和最终报告
3. 如果文件非空，进入 `<scan-root>/phase2`
4. 执行：

```bash
/tmp/fscanx-bin/fscanx \
  -hf ../phase1/alive_ips.txt \
  -p '1-65535' \
  -np \
  -t <threads> \
  -time <timeout> \
  -nocolor \
  -json
```

5. 获取 `phase2/result.txt`
6. 归一化成 `phase2/normalized.json`
7. 只提取 `type == "Port"` 的记录
8. 从这些记录中抽取唯一 `IP:PORT`
9. 输出 `open_ip_port.txt`
10. 输出 `phase2.summary.json`
11. 结合第一阶段摘要，生成根目录 `report.json`

### 6.3 all

`all` 会顺序执行：

1. `phase1`
2. `phase2`
3. `report.json` 汇总

这是默认推荐用法。

## 7. 输出文件

以 `scans/20260424-fscanx` 为例：

```text
scans/20260424-fscanx/
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

其中：

- `alive_ips.txt` 是第一阶段筛出来的唯一 IP 列表
- `open_ip_port.txt` 是第二阶段得到的唯一 `IP:PORT`
- `report.json` 是最终统一报告

## 8. 推荐用法

### 8.1 正常执行完整流程

```bash
bash scripts/fscanx_pipeline.sh all \
  --scanner /tmp/fscanx-bin/fscanx \
  --targets '192.168.1.0/24,192.168.20.0/24,192.168.4.0/24' \
  --phase1-ports '22,80,443,445,3389' \
  --phase2-ports '1-65535' \
  --threads 4000 \
  --timeout 1 \
  --scan-root scans/20260424-fscanx
```

### 8.2 第一阶段完成后只重跑第二阶段

```bash
bash scripts/fscanx_pipeline.sh phase2 \
  --scanner /tmp/fscanx-bin/fscanx \
  --phase2-ports '1-65535' \
  --threads 4000 \
  --timeout 1 \
  --scan-root scans/20260424-fscanx
```

### 8.3 用 tmux 后台运行

```bash
tmux new -ds nmap-fscanx-20260424 \
  "bash scripts/fscanx_pipeline.sh all \
    --scanner /tmp/fscanx-bin/fscanx \
    --targets '192.168.1.0/24,192.168.20.0/24,192.168.4.0/24' \
    --phase1-ports '22,80,443,445,3389' \
    --phase2-ports '1-65535' \
    --threads 4000 \
    --timeout 1 \
    --scan-root scans/20260424-fscanx"
```

## 9. 注意事项

1. 不要依赖 `-o` 输出路径
   当前这份二进制的 `-o` 不稳定，脚本已经通过“切换工作目录”绕过这个问题

2. 不要直接把第二阶段 IP 拼成超长的 `-h ip1,ip2,...`
   当前脚本固定使用 `-hf ../phase1/alive_ips.txt`

3. 当前脚本只解析 `Port` 记录
   它的目标是产出 `IP:PORT` 资产列表，不做指纹识别和更深的协议分析
