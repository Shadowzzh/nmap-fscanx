# fscanx_pipeline 快速手册

## 1. 它是干什么的

[scripts/fscanx_pipeline.sh](/Users/zhangziheng/Documents/code/nmap/scripts/fscanx_pipeline.sh:1) 用来跑一个固定的两阶段流程：

1. 第一阶段扫重点端口，筛出命中主机
2. 第二阶段只对这些主机扫全端口
3. 输出统一的 `report.json`

第一阶段默认重点端口：

- `22,80,443,445,3389`

## 2. 运行前检查

先确认这 3 个东西在：

- `bash`
- `jq`
- `/tmp/fscanx-bin/fscanx`

建议再确认一件事：

- 你当前这台机器是不是适合当扫描发起点

如果目标网段不在本机可达路径上，结果会失真。

## 3. 最常用命令

### 3.1 查看帮助

```bash
bash scripts/fscanx_pipeline.sh -h
```

### 3.2 跑完整流程

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

### 3.3 只重跑第二阶段

```bash
bash scripts/fscanx_pipeline.sh phase2 \
  --scanner /tmp/fscanx-bin/fscanx \
  --phase2-ports '1-65535' \
  --threads 4000 \
  --timeout 1 \
  --scan-root scans/20260424-fscanx
```

### 3.4 用 tmux 后台跑

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

## 4. 跑完看哪里

假设输出目录是：

```text
scans/20260424-fscanx/
```

最重要的文件是：

| 文件 | 作用 |
| --- | --- |
| `phase1/alive_ips.txt` | 第一阶段筛出的主机 |
| `phase2/open_ip_port.txt` | 第二阶段扫出的 `IP:PORT` |
| `report.json` | 最终汇总 |

快速查看：

```bash
cat scans/20260424-fscanx/phase1/alive_ips.txt
cat scans/20260424-fscanx/phase2/open_ip_port.txt
jq '.' scans/20260424-fscanx/report.json
```

## 5. 这份脚本的边界

要记住两件事：

1. 第一阶段不是纯活 IP 探测  
   只会保留命中重点端口的主机

2. 当前参数偏速度优先  
   默认是：
   - `--threads 4000`
   - `--timeout 1`

如果你更在意稳定性，而不是速度，应该单独做参数对照测试。

## 6. 最容易踩的坑

### 6.1 发起点不对

如果本机不在目标网段附近，结果会混入：

- 路由问题
- ACL 问题
- 超时问题

### 6.2 目标网段没写全

脚本不会帮你猜网段。  
你漏写了哪段，它就不会扫哪段。

### 6.3 不要依赖 `-o`

当前这份 `fscanx` 的 `-o` 不稳定。  
脚本已经通过“切换工作目录 + 接管 `result.txt`”绕过了这个问题。

## 7. 什么时候先别急着怀疑脚本

如果结果异常少，先检查这几项：

1. 目标网段是不是写全了
2. 当前机器是不是合适的发起点
3. 目标主机是不是确实开了重点端口
4. 当前参数是不是太激进

## 8. 对照文档

如果你要看完整说明，再看这些：

- [fscanx两阶段扫描脚本说明.md](/Users/zhangziheng/Documents/code/nmap/docs/fscanx两阶段扫描脚本说明.md:1)
- [fscanx_pipeline使用手册.md](/Users/zhangziheng/Documents/code/nmap/docs/fscanx_pipeline使用手册.md:1)
- [2026-04-24-fscanx漏扫排查交接说明.md](/Users/zhangziheng/Documents/code/nmap/docs/2026-04-24-fscanx漏扫排查交接说明.md:1)
