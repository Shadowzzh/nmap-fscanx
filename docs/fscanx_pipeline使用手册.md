# fscanx_pipeline 使用手册

## 1. 适用对象

本手册面向下面这类需求：

1. 想用仓库里的 [fscanx_pipeline.sh](/Users/zhangziheng/Documents/code/nmap/scripts/fscanx_pipeline.sh:1) 跑两阶段扫描
2. 想知道应该从哪台机器发起扫描
3. 想理解输出文件怎么查看
4. 想避免把“网络路径问题”和“工具漏检问题”混在一起

## 2. 脚本做什么

这个脚本把 `fscanx` 固定成两阶段流程：

1. 第一阶段：扫描重点端口，筛出“命中重点端口的主机”
2. 第二阶段：读取第一阶段结果，对这些主机跑全端口扫描
3. 最终输出标准 `report.json`

注意：

- 第一阶段不是纯粹的“活 IP 探测”
- 第一阶段的判定逻辑是：
  只要 `22,80,443,445,3389` 里任意一个端口命中，就把该 IP 视为需要进入第二阶段

这意味着：

- 在线但没开这些端口的主机，会被第一阶段过滤掉

## 3. 运行前提

运行前需要保证：

- `bash`
- `jq`
- `/tmp/fscanx-bin/fscanx`

推荐使用：

- `tmux`

原因：

- 当前这份 `fscanx` 的 `-o` 不稳定
- 结果文件会写到当前工作目录下的 `result.txt`
- 长时间扫描不适合直接挂在普通 SSH 会话上

## 4. 什么时候用这份脚本

适合：

- 已知一批网段，先想快速筛出有重点服务的主机
- 后续只关心这些主机的资产面
- 想保留每轮扫描的审计文件

不适合：

- 需要严格意义上的“纯活 IP 发现”
- 需要把所有在线主机都找出来，不管它是否开重点端口
- 需要高精度基线对比

如果你的目标是“尽量完整找出所有在线主机”，应先用：

- `nmap -sn`
- 或其它纯活性发现方式

不要直接把这份脚本当成“活 IP 基线工具”。

## 5. 最重要的原则：先选对发起点

这份脚本是否好用，很大程度上取决于“从哪台机器发起”。

### 5.1 错误的使用方式

如果当前机器：

- 不在目标网段内
- 到目标靠默认网关跨网段转发
- 对目标有 ACL、防火墙、网关策略限制

那么结果会混入：

- 路由问题
- ACL 问题
- 探测超时问题

这时候你很容易误判成“脚本漏扫了”。

### 5.2 正确的使用方式

优先选择：

- 真正处于目标网络里的主机
- 或至少对目标网段有稳定可达路径的主机

例如本仓库里已经验证过的情况：

- 扫 `192.168.4.0/24`、`192.168.9.0/24` 时，用 `weiwei-tail` 作为发起点更合理

## 6. 帮助命令

查看脚本帮助：

```bash
bash scripts/fscanx_pipeline.sh -h
```

帮助里已经包含：

- 参数说明
- 运行流程
- 常见案例

## 7. 命令入口

脚本支持 3 个子命令：

```bash
bash scripts/fscanx_pipeline.sh phase1 ...
bash scripts/fscanx_pipeline.sh phase2 ...
bash scripts/fscanx_pipeline.sh all ...
```

含义如下：

| 子命令 | 用途 |
| --- | --- |
| `phase1` | 只跑重点端口筛选，输出存活 IP 文件 |
| `phase2` | 读取 `phase1/alive_ips.txt`，只跑全端口扫描 |
| `all` | 顺序执行 `phase1 -> phase2 -> report` |

默认推荐用法：

- `all`

## 8. 参数说明

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `--scanner` | `fscanx` 二进制路径 | `/tmp/fscanx-bin/fscanx` |
| `--targets` | 目标网段，逗号分隔 | 无 |
| `--phase1-ports` | 第一阶段重点端口 | `22,80,443,445,3389` |
| `--phase2-ports` | 第二阶段端口范围 | `1-65535` |
| `--threads` | 传给 `fscanx -t` 的并发 | `4000` |
| `--timeout` | 传给 `fscanx -time` 的超时秒数 | `1` |
| `--scan-root` | 扫描输出目录 | `scans/YYYYMMDD-fscanx` |

## 9. 常见用法

### 9.1 直接跑完整流程

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

### 9.2 第一阶段完成后，只重跑第二阶段

```bash
bash scripts/fscanx_pipeline.sh phase2 \
  --scanner /tmp/fscanx-bin/fscanx \
  --phase2-ports '1-65535' \
  --threads 4000 \
  --timeout 1 \
  --scan-root scans/20260424-fscanx
```

### 9.3 用 tmux 后台运行

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

## 10. 输出文件怎么看

假设输出目录为：

```text
scans/20260424-fscanx/
```

核心文件如下：

| 文件 | 作用 |
| --- | --- |
| `input.json` | 本次运行参数 |
| `phase1/console.log` | 第一阶段控制台日志 |
| `phase1/result.txt` | 第一阶段原始结果 |
| `phase1/alive_ips.txt` | 第一阶段提取出的唯一 IP |
| `phase1/phase1.summary.json` | 第一阶段摘要 |
| `phase2/console.log` | 第二阶段控制台日志 |
| `phase2/result.txt` | 第二阶段原始结果 |
| `phase2/open_ip_port.txt` | 第二阶段唯一 `IP:PORT` |
| `phase2/phase2.summary.json` | 第二阶段摘要 |
| `report.json` | 最终汇总报告 |

### 10.1 快速看第一阶段命中了哪些主机

```bash
cat scans/20260424-fscanx/phase1/alive_ips.txt
```

### 10.2 快速看第二阶段扫出的资产

```bash
cat scans/20260424-fscanx/phase2/open_ip_port.txt
```

### 10.3 快速看最终统计

```bash
jq '.' scans/20260424-fscanx/report.json
```

## 11. 当前已知限制

### 11.1 不要依赖 `-o`

当前这份 `fscanx` 的 `-o` 行为不稳定。  
脚本的处理方式是：

- 进入阶段目录执行
- 直接接管当前目录自动生成的 `result.txt`

### 11.2 `result.txt` 不是标准 JSON

当前这份 `fscanx` 的 `-json` 输出是 JSON 片段，不是标准数组。  
脚本会自动把它归一化成 `normalized.json` 再交给 `jq`。

### 11.3 第一阶段不是活 IP 基线

第一阶段只认重点端口命中。  
因此：

- 在线但没开重点端口的主机，不会进入第二阶段

### 11.4 当前参数偏速度优先

默认参数：

- `--threads 4000`
- `--timeout 1`

这组参数偏快，但在某些网段、某些发起点上，可能会带来漏检。

## 12. 当前排查得到的使用建议

根据本轮实测，建议这样理解和使用：

### 12.1 如果只是做资产初筛

可以直接用默认参数跑：

- 速度快
- 产物完整
- 审计方便

### 12.2 如果你要做精度对比

不要只看 `fscanx_pipeline.sh` 的第一阶段结果。  
建议同时跑：

1. `nmap -sn`
2. `nmap -Pn -p 22,80,443,445,3389`
3. `fscanx` 第一阶段

这样才能分清：

- 在线主机
- 重点端口主机
- `fscanx` 是否漏掉本该命中的目标

### 12.3 如果结果异常少

先检查下面这几项：

1. 目标网段是否真的加进去了
2. 发起点是否合理
3. 目标是否跨网段且被 ACL/防火墙限制
4. 该主机是否真的开了重点端口
5. 当前参数是否过激

不要第一时间假设是脚本拼参错误。

## 13. 当前仓库里可参考的相关文档

| 文档 | 用途 |
| --- | --- |
| [fscanx两阶段扫描脚本说明.md](/Users/zhangziheng/Documents/code/nmap/docs/fscanx两阶段扫描脚本说明.md:1) | 脚本设计与流程说明 |
| [2026-04-24-fscanx漏扫排查交接说明.md](/Users/zhangziheng/Documents/code/nmap/docs/2026-04-24-fscanx漏扫排查交接说明.md:1) | 本轮漏扫排查结论 |
| [nmap-fscanx-vs-nmap-20260424-095405-tables.md](/Users/zhangziheng/Documents/code/nmap/out/nmap-fscanx-vs-nmap-20260424-095405-tables.md:1) | `fscanx` 与 `nmap` 的表格对比 |

## 14. 一句话建议

这份脚本现在可以继续用，但要记住一件事：

- **先选对发起点，再看结果**

如果发起点不对，再好的脚本也会把网络路径问题表现成“漏扫”。  
如果发起点对了，再去讨论 `fscanx` 参数和工具本身的漏检，才有意义。
