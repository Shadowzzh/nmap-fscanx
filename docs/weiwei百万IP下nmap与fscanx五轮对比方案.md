# `weiwei` 百万 IP 环境下 `nmap` 与 `fscanx` 五轮对比方案

## 1. 目的

本文档定义一套可重复、可审计的对比方案，用于在 `weiwei` 的 `1000000` IP 稀疏实验环境中，对：

- `nmap`
- `fscanx`

分别执行 `5` 轮测试，并输出统一口径的对比结果。

本文档是“执行方案”，不是结果报告。

## 2. 测试对象

### 2.1 执行主机

建议执行主机：

- `weiwei-tail`

实际目标主机：

- `dev-server`
- 局域网地址：`192.168.4.131`
- Tailscale 地址：`100.106.113.21`

说明：

- 当前百万 IP 稀疏环境就在这台机器上
- 在这台机器本机内部做测试，更容易排除本地扫描机到远端的三层路径差异

### 2.2 目标地址空间

目标范围固定为下面 `7` 个 CIDR：

- `10.240.0.0/13`
- `10.248.0.0/14`
- `10.252.0.0/15`
- `10.254.0.0/16`
- `10.255.0.0/18`
- `10.255.64.0/23`
- `10.255.66.0/26`

总量：

- `1000000` 个 IP

### 2.3 已知活 IP

当前已知活 IP 为：

- `10.240.1.10`
- `10.248.2.20`
- `10.255.66.30`

### 2.4 统一端口口径

两种工具统一对比的端口为：

- `22`
- `80`
- `443`
- `445`
- `3389`

## 3. 对比原则

### 3.1 必须保持一致的维度

两种工具必须保持一致：

- 相同目标范围
- 相同端口集合
- 相同执行主机
- 相同轮次数

### 3.2 不做“功能不对称”的比较

本轮对比只比较“重点端口命中能力”和执行效率，不比较：

- Web 指纹
- 协议识别
- POC
- 爆破
- 二阶段全端口资产发现

原因：

- `nmap` 与 `fscanx` 的这些能力侧重点不同
- 如果把这些能力混进来，结果就不再是同一口径

### 3.3 统计口径

每轮至少输出下面几个指标：

- 耗时
- 退出码
- 结果行数
- 唯一主机数
- 唯一 `IP:PORT` 数

## 4. 测试前检查

正式执行前，先在 `weiwei-tail` 上确认：

1. 工具存在
   - `tmux`
   - `nmap`
   - `/tmp/fscanx-bin/fscanx`
   - `/usr/bin/time`

2. 百万 IP 环境仍在
   - `dummy0` 上活 IP 是否仍存在
   - `blackhole` 路由是否仍存在

3. 目标文件准备好
   - `targets.txt`
   - 每行一个 CIDR

建议目标文件内容固定为：

```text
10.240.0.0/13
10.248.0.0/14
10.252.0.0/15
10.254.0.0/16
10.255.0.0/18
10.255.64.0/23
10.255.66.0/26
```

## 5. 输出目录设计

建议在远端 `/tmp` 下建立独立目录：

```text
/tmp/nmap-fscanx-1m-compare-YYYYMMDD-HHMMSS/
```

目录结构建议如下：

```text
/tmp/nmap-fscanx-1m-compare-YYYYMMDD-HHMMSS/
├── targets.txt
├── progress.log
├── fscanx/
│   ├── round-01/
│   ├── round-02/
│   ├── round-03/
│   ├── round-04/
│   └── round-05/
├── nmap/
│   ├── round-01/
│   ├── round-02/
│   ├── round-03/
│   ├── round-04/
│   └── round-05/
├── fscanx-summary.tsv
└── nmap-summary.tsv
```

## 6. tmux 执行方式

必须使用 `tmux`，不要使用 `screen`。

建议会话名：

```bash
nmap-fscanx-1m-compare-20260424
```

建议执行方式：

```bash
tmux new -ds nmap-fscanx-1m-compare-20260424 '<runner-script>'
```

## 7. fscanx 五轮方案

### 7.1 命令口径

`fscanx` 使用下面的参数：

```bash
/tmp/fscanx-bin/fscanx \
  -hf targets.txt \
  -p 22,80,443,445,3389 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor \
  -no
```

说明：

- `-hf` 读取目标文件
- `-p` 固定重点端口
- `-np` 禁用额外 ping/icmp
- `-t 4000`
  使用现有常用并发口径
- `-time 1`
  使用现有常用超时口径
- `-no`
  不依赖默认落盘，统一由外层日志接管

### 7.2 单轮输出

每轮建议保留：

- `console.log`
- `fscanx-hosts.txt`
- `fscanx-ipports.txt`

其中：

- `fscanx-hosts.txt`
  存唯一 IP
- `fscanx-ipports.txt`
  存唯一 `IP:PORT`

### 7.3 建议解析方式

可以直接从 `console.log` 或原始结果里提取：

- 结果行数
- 唯一主机数
- 唯一 `IP:PORT`

## 8. nmap 五轮方案

### 8.1 命令口径

`nmap` 使用下面的参数：

```bash
nmap -Pn -n -p 22,80,443,445,3389 \
  -oG round-N/nmap.gnmap \
  10.240.0.0/13 10.248.0.0/14 10.252.0.0/15 \
  10.254.0.0/16 10.255.0.0/18 10.255.64.0/23 10.255.66.0/26
```

说明：

- `-Pn`
  避免 host discovery 先行过滤
- `-n`
  禁用 DNS
- `-p`
  与 `fscanx` 保持同一端口口径
- `-oG`
  方便解析开放端口和主机

### 8.2 单轮输出

每轮建议保留：

- `nmap.log`
- `nmap.gnmap`
- `nmap-hosts.txt`
- `nmap-ipports.txt`

其中：

- `nmap-hosts.txt`
  存至少命中一个重点端口的唯一 IP
- `nmap-ipports.txt`
  存唯一 `IP:PORT`

## 9. 推荐执行顺序

按你的当前偏好，采用串行执行：

1. 先跑 `fscanx` `5` 轮
2. 再跑 `nmap` `5` 轮
3. 最后汇总

推荐原因：

- 过程更容易观察
- 不会让两种工具抢占同一台机器资源
- 更便于在 `progress.log` 里记录阶段边界

## 10. 汇总文件格式

### 10.1 fscanx-summary.tsv

建议字段：

```text
round    exit_code    real_seconds    result_rows    unique_hosts    unique_ipports    hosts_file    ipports_file
```

### 10.2 nmap-summary.tsv

建议字段：

```text
round    exit_code    real_seconds    result_rows    unique_hosts    unique_ipports    hosts_file    ipports_file
```

## 11. 最终报告建议包含的表格

最终输出到本地 `docs/` 或 `out/` 的报告，建议至少包含下面这些表：

### 11.1 每轮结果总表

| 轮次 | fscanx 耗时 | fscanx 主机数 | fscanx IP:PORT 数 | nmap 耗时 | nmap 主机数 | nmap IP:PORT 数 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |

### 11.2 平均值表

| 工具 | 平均耗时 | 平均主机数 | 平均 IP:PORT 数 |
| --- | ---: | ---: | ---: |

### 11.3 稳定性表

| 工具 | 5 轮并集主机数 | 5 轮交集主机数 |
| --- | ---: | ---: |

### 11.4 差异表

| 项目 | 数量 |
| --- | ---: |
| nmap 并集主机数 |  |
| fscanx 并集主机数 |  |
| fscanx 相比 nmap 少的主机数 |  |
| fscanx 相比 nmap 多的主机数 |  |

### 11.5 缺失主机表

| IP | nmap 命中的重点端口 |
| --- | --- |

## 12. 风险与解释规则

### 12.1 如果两者都只扫出 3 个主机

这通常说明：

- 目标环境仍符合“仅 3 个活 IP 且只开 22”这一预期

### 12.2 如果 nmap 明显多于 fscanx

优先解释为：

- `fscanx` 在当前参数下存在漏检

而不是先怀疑：

- 目标文件没传进去

因为目标文件和目标字符串是可审计的。

### 12.3 如果两者结果都抖动

优先排查：

- 本机负载
- 防火墙/限速
- 目标环境是否被改动

## 13. 推荐的执行后动作

执行完 `10` 轮后，建议做下面三件事：

1. 把远端结果目录拉回本地 `out/`
2. 生成 Markdown 报告
3. 在 `docs/` 下追加一份交接说明，写清：
   - 测试时间
   - 目标范围
   - 工具版本
   - 主要结论

## 14. 当前建议

如果你后续真的要按这份方案开跑，建议保持下面这些固定值：

- 发起点：`weiwei-tail`
- 目标：固定 `7` 个 CIDR
- 端口：固定 `22,80,443,445,3389`
- 轮次：固定 `5`
- 执行顺序：先 `fscanx`，后 `nmap`
- 会话：固定使用 `tmux`

这样后面的结果才具备可比性。
