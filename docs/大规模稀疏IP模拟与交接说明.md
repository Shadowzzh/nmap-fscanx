# 大规模稀疏 IP 模拟与交接说明

> 补充说明：截至 `2026-04-23`，`weiwei` 上还存在一套新增的 `1000000` IP 稀疏环境核实记录，见 [weiwei当前100万IP环境核实记录.md](./weiwei当前100万IP环境核实记录.md)。本文主要记录旧的 `98304` 地址实验和对应基准结果。

## 1. 目的

本文档记录本次“大规模目标地址、极少量在线主机”实验环境的搭建方式、已执行的验证和基准测试结果，并明确后续交接给下一个 AI 时应继续关注的事项。

本次实验的目标不是模拟 `1000` 万个真实在线主机，而是模拟下面这种更接近客户场景的情况：

1. 目标地址空间很大
2. 实际在线主机极少
3. 扫描机需要跨三层访问这些目标地址

## 2. 环境角色

本次实验涉及两台机器：

- 扫描机：本机 macOS
- 模拟机：`weiwei`

关键信息如下：

- 本机外层管理地址：`192.168.1.117`
- `weiwei` 外层管理地址：`192.168.4.131`
- `weiwei` SSH Host：`weiwei`

## 3. 模拟思路

### 3.1 为什么不用真实主机堆数量

如果直接堆大量真实主机，成本高、维护复杂，而且并不符合“地址很多、在线主机很少”的目标。更合理的做法是：

1. 准备一个较大的目标地址空间
2. 只让其中极少数地址真实响应
3. 其他地址全部静默丢弃

这样可以逼近真实扫描场景中的时延、超时和结果稀疏性。

### 3.2 为什么选用 `198.18.0.0/16` 和 `198.19.0.0/17`

本次实验没有使用常见的 `10.0.0.0/8` 私网段，而是选用了：

- `198.18.0.0/16`
- `198.19.0.0/17`

原因：

1. 这两个前缀是基准测试常用保留地址段
2. 与家庭内网、办公网、VPN 地址冲突的概率更低
3. 便于和现网真实业务网段区分

总目标数为：

- `198.18.0.0/16` = `65536`
- `198.19.0.0/17` = `32768`

合计 `98304` 个目标地址，约等于 `10` 万。

### 3.3 活 IP 与死 IP 的模拟方式

在 `weiwei` 上创建 `dummy0`，并挂载 `3` 个 `/32` 地址作为活 IP：

- `198.18.1.10/32`
- `198.18.2.20/32`
- `198.19.3.30/32`

同时在 `weiwei` 上加入两条 `blackhole` 路由：

- `blackhole 198.18.0.0/16`
- `blackhole 198.19.0.0/17`

这样：

1. 命中上述 `3` 个 `/32` 的流量会被本机地址接收并响应
2. 命中其他地址的流量会被静默丢弃

这正好符合“目标网段大，但只有极少数 IP 活着”的实验需求。

### 3.4 为什么还需要三层隧道

扫描机和 `weiwei` 并不处于同一个二层广播域，本机无法简单地把测试前缀直接指向 `192.168.4.131` 作为下一跳来完成实验。

因此，本次实际采用了一个临时三层隧道：

- 本机：`gif0`
- `weiwei`：`simtun`

外层封装地址：

- 本机外层：`192.168.1.117`
- `weiwei` 外层：`192.168.4.131`

内层点对点地址：

- 本机内层：`172.31.255.1/30`
- `weiwei` 内层：`172.31.255.2/30`

然后在扫描机上把测试前缀指向 `172.31.255.2`，使实验流量经隧道进入 `weiwei`。

## 4. 当前生效配置

### 4.1 `weiwei` 当前配置

已验证当前仍生效：

- `dummy0`
- `198.18.1.10/32`
- `198.18.2.20/32`
- `198.19.3.30/32`
- `simtun 172.31.255.2/30`
- `blackhole 198.18.0.0/16`
- `blackhole 198.19.0.0/17`

### 4.2 本机当前配置

已验证当前仍生效：

- `gif0`
- `gif0` 隧道外层：`192.168.1.117 -> 192.168.4.131`
- `gif0` 内层：`172.31.255.1 -> 172.31.255.2`
- `198.18.0.0/16` 路由到 `172.31.255.2`
- `198.19.0.0/17` 路由到 `172.31.255.2`

## 5. 实际执行过的关键命令

### 5.1 `weiwei` 模拟器搭建命令

```bash
sudo ip link add dummy0 type dummy
sudo ip link set dummy0 up

sudo ip addr add 198.18.1.10/32 dev dummy0
sudo ip addr add 198.18.2.20/32 dev dummy0
sudo ip addr add 198.19.3.30/32 dev dummy0

sudo ip route add blackhole 198.18.0.0/16
sudo ip route add blackhole 198.19.0.0/17

sudo ip tunnel add simtun mode ipip local 192.168.4.131 remote 192.168.1.117
sudo ip addr add 172.31.255.2/30 dev simtun
sudo ip link set simtun up
```

### 5.2 本机扫描机配置命令

```bash
sudo ifconfig gif0 tunnel 192.168.1.117 192.168.4.131
sudo ifconfig gif0 inet 172.31.255.1 172.31.255.2 netmask 255.255.255.252 up

sudo route -n add -net 198.18.0.0/16 172.31.255.2
sudo route -n add -net 198.19.0.0/17 172.31.255.2
```

### 5.3 活 IP 验证命令

已验证下面命令可发现 `3` 个活 IP：

```bash
nmap -sn -n -PS80 -e gif0 198.18.1.10 198.18.2.20 198.19.3.30
```

## 6. 基准测试过程与结果

### 6.1 为什么没有直接用脚本的 `run` 模式

仓库里的脚本：

- `scripts/scan_benchmark.sh`

其 `run` 模式目前实际调用的是：

```bash
nmap -sn -n "${targets[@]}" | tee "$output_path"
```

但后续解析器要求输入文件里必须包含标准普通输出格式中的头尾行，例如：

- `# Nmap ... scan initiated ...`
- `# Nmap done at ...`

因此，`run` 模式当前会在汇总阶段失败，报错表现为：

```text
missing scan start line in ...
```

本次没有修改脚本，而是采用下面的折中方案：

1. 手工执行 `nmap -oN ...` 生成标准结果文件
2. 再调用 `scripts/scan_benchmark.sh parse` 计算统计结果

### 6.2 默认参数为什么没采用

直接使用默认：

```bash
nmap -sn -n
```

在本次 `98304` 地址、仅 `3` 个主机在线的模拟环境下速度较慢，不适合作为“快速稀疏扫描”的基准方案。

### 6.3 实际用于 5 轮测试的命令

本次最终采用下面这组参数做 `5` 轮手工测试：

```bash
nmap -sn -n -PS80 -e gif0 -T5 \
  --min-rate 50000 \
  --max-retries 0 \
  --initial-rtt-timeout 10ms \
  --max-rtt-timeout 20ms \
  --min-hostgroup 4096 \
  --max-hostgroup 4096 \
  -oN out/scan-benchmark-manual-20260423-1624/scan_round_N.txt \
  198.18.0.0/16 198.19.0.0/17
```

说明：

1. `-PS80` 用 TCP SYN 主机发现
2. `-e gif0` 强制走实验隧道接口
3. `--max-retries 0` 适合极稀疏目标，尽快放弃死地址
4. 大量 `retransmission cap hit (0)` 警告是预期现象，不代表实验失败

### 6.4 5 轮结果

结果目录：

- `out/scan-benchmark-manual-20260423-1624/`

汇总结果：

- 总轮数：`5`
- 每轮 IP：`98304`
- 每轮活主机：`3`
- 总耗时：`1123.65s`
- 平均耗时：`224.73s`

约等于：

- 平均每轮 `3` 分 `44.73` 秒

逐轮结果如下：

1. `291.17s`
2. `209.15s`
3. `206.60s`
4. `206.54s`
5. `210.19s`

## 7. 输出文件位置

关键结果文件如下：

- `out/scan-benchmark-manual-20260423-1624/summary.log`
- `out/scan-benchmark-manual-20260423-1624/scan_round_1.txt`
- `out/scan-benchmark-manual-20260423-1624/scan_round_2.txt`
- `out/scan-benchmark-manual-20260423-1624/scan_round_3.txt`
- `out/scan-benchmark-manual-20260423-1624/scan_round_4.txt`
- `out/scan-benchmark-manual-20260423-1624/scan_round_5.txt`

## 8. 交给下一个 AI 的任务说明

下一个 AI 接手时，建议优先处理下面几件事：

### 8.1 第一优先级：决定是否保留当前实验环境

当前实验环境仍然处于生效状态，没有自动清理。接手后应先判断：

1. 是否继续沿用当前 `gif0 + simtun + dummy0 + blackhole` 环境
2. 如果不再继续实验，先执行清理

### 8.2 第二优先级：修复 `scan_benchmark.sh`

建议优先修复：

1. `run` 模式应改用 `nmap -oN "$output_path"`，不要只用 `tee`
2. `run` 模式应支持追加自定义 `nmap` 参数
3. 最好支持接口选择，例如 `-e gif0`
4. 最好支持主机发现方式选择，例如 `-PS80`

否则脚本只能在非常有限的默认场景下使用。

### 8.3 第三优先级：固化实验脚本

建议新增或整理成下面几类脚本：

1. `setup_simulator.sh`
   在 `weiwei` 上创建 `dummy0`、`simtun` 和 `blackhole`
2. `setup_scanner_tunnel.sh`
   在本机创建 `gif0` 并写入测试路由
3. `cleanup_simulation.sh`
   同时清理本机和 `weiwei` 的实验配置
4. `run_sparse_benchmark.sh`
   固化本次实测通过的 `nmap` 参数

### 8.4 第四优先级：继续做参数对比

本次只验证了一组较激进参数。下一个 AI 可以继续做：

1. 默认 `-sn -n` 对比测试
2. `-PE` 与 `-PS80` 对比测试
3. `--min-rate` 不同取值对平均耗时的影响
4. `--max-retries 0` 与 `1` 的差异
5. 不同 `hostgroup` 大小的影响

## 9. 清理命令

如果下一个 AI 决定直接清理环境，可按以下顺序执行。

### 9.1 清理本机

```bash
sudo route -n delete -net 198.18.0.0/16 172.31.255.2
sudo route -n delete -net 198.19.0.0/17 172.31.255.2
sudo ifconfig gif0 deletetunnel
sudo ifconfig gif0 down
```

### 9.2 清理 `weiwei`

```bash
ssh weiwei '
sudo ip tunnel del simtun 2>/dev/null || true
sudo ip route del blackhole 198.18.0.0/16 2>/dev/null || true
sudo ip route del blackhole 198.19.0.0/17 2>/dev/null || true
sudo ip addr del 198.18.1.10/32 dev dummy0 2>/dev/null || true
sudo ip addr del 198.18.2.20/32 dev dummy0 2>/dev/null || true
sudo ip addr del 198.19.3.30/32 dev dummy0 2>/dev/null || true
sudo ip link del dummy0 2>/dev/null || true
'
```

## 10. 当前结论

本次实验已经证明：

1. 可以在不污染现网路由器的前提下，在本机和 `weiwei` 之间搭出一个临时大网段稀疏主机模拟环境
2. `98304` 个目标地址、`3` 个活 IP 的实验模型已经跑通
3. 在当前环境下，使用一组激进的 `nmap` 参数，`5` 轮平均耗时约为 `224.73s`
4. 当前仓库内的 `scan_benchmark.sh` 还不适合直接承担这个实验流程，需要后续修复
