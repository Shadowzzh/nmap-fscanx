# fscanx 使用指南

## 1. 目的

本文档整理 `fscanx` 的常用用法、参数差异与大规模扫描建议，方便在当前仓库中统一理解和使用该工具。

官方仓库：

- <https://github.com/killmonday/fscanx>

`fscanx` 适合以下场景：

- 大网段快速探测
- 公网信息收集
- 内网资产测绘
- 代理或隧道下的远程扫描
- `masscan -> fscanx` 两阶段联动

## 2. 安装与编译

```bash
git clone https://github.com/killmonday/fscanx.git
cd fscanx
go build -o fscanx .
```

编译完成后可执行文件通常为：

- `./fscanx`

## 3. 与原版 fscan 的关键差异

最容易踩坑的是参数习惯。

原版 `fscan` 常见写法：

- `-nobr`
- `-nopoc`

`fscanx` 已调整为正向开关：

- 不加 `-br`，默认不爆破
- 不加 `-poc`，默认不跑 POC

也就是说，在 `fscanx` 中，下面这两个参数不要再沿用：

- `-nobr`
- `-nopoc`

`fscanx` 相比原版常见新增或强化的参数包括：

- `-auto`
- `-hf`
- `-std`
- `-iface`
- `-nmap`
- `-socks5`

## 4. 目标输入方式

### 4.1 单目标或单网段

```bash
./fscanx -h 192.168.1.0/24
./fscanx -h 192.168.1.10
```

### 4.2 多网段直接写在命令行

```bash
./fscanx -h 192.168.1.0/24,192.168.20.0/24,192.168.4.0/24
```

### 4.3 从文件导入目标

推荐复杂场景优先使用 `-hf`。

```bash
cat > targets.txt <<'EOF'
192.168.1.0/24
192.168.20.0/24
192.168.4.0/24
EOF

./fscanx -hf targets.txt
```

`-hf` 支持的不只是 CIDR，还支持：

- `ip`
- `ip:port`
- `cidr`
- `cidr:port`
- `url`
- 纯域名
- `masscan` 输出文本

## 5. 常用扫描方式

### 5.1 速度优先的重点端口扫描

如果目标是尽快摸清服务面，建议先扫少量高价值端口。

```bash
./fscanx \
  -hf targets.txt \
  -p 22,80,443,445,3389 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor \
  -o result.txt
```

参数说明：

- `-p`
  指定端口
- `-np`
  不做 ping 或 icmp
- `-t`
  端口扫描并发
- `-time`
  TCP 超时秒数
- `-nocolor`
  便于日志和后处理
- `-o`
  保存结果

### 5.2 全端口扫描

如果确认要做全端口扫描，可直接使用：

```bash
./fscanx \
  -h 192.168.1.0/24,192.168.20.0/24,192.168.4.0/24 \
  -p 1-65535 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor \
  -o result.txt
```

更稳一点的版本：

```bash
./fscanx \
  -h 192.168.1.0/24,192.168.20.0/24,192.168.4.0/24 \
  -p 1-65535 \
  -np \
  -t 2000 \
  -time 2 \
  -nocolor \
  -o result.txt
```

说明：

- `-t 4000 -time 1` 更偏速度优先
- `-t 2000 -time 2` 更偏少漏一点

### 5.3 开协议识别和 Web 指纹

如果希望在端口开放基础上补协议与资产信息，可加 `-nmap`：

```bash
./fscanx \
  -hf targets.txt \
  -p 22,80,443,445,3389 \
  -np \
  -nmap \
  -t 1000 \
  -tn 200 \
  -time 2 \
  -nocolor \
  -o result.txt
```

说明：

- `-nmap` 会明显增加扫描耗时
- `-tn` 控制 Web 并发
- 适合第二阶段补识别，不适合一上来就扫超大目标

## 6. 大网段智能探测 `-auto`

### 6.1 功能定位

`-auto` 不是“完整扫一遍全部 IP”，而是“按 `/24` 先筛活段，再深扫”。

其默认思路是：

1. 按 C 段，也就是 `/24` 为单位做预筛选
2. 默认测试每个 `/24` 中的 `1,2,253,254`
3. 默认使用 `tcp+icmp`
4. `tcp` 默认探测 `80`
5. 只要命中，就把这个 `/24` 视为活段并进入后续扫描

### 6.2 典型命令

```bash
./fscanx -h 192 -auto -nmap -t 1000 -np
```

速度优先版：

```bash
./fscanx \
  -h 192 \
  -auto \
  -am tcp \
  -ap 80 \
  -ai 1,2,253,254 \
  -atime 1 \
  -p 22,80,443,445,3389 \
  -np \
  -t 2000 \
  -nocolor \
  -o result.txt
```

### 6.3 使用边界

`-auto` 更适合：

- `/8`
- `/16`
- 大范围且较稀疏的连续地址空间

不太适合：

- 只有几个 `/24` 的小范围扫描
- 活主机不在默认的 `1,2,253,254`
- 关键资产不开放 `80`
- 要求尽量少漏的严格探活

对类似下面这种目标：

- `192.168.1.0/24`
- `192.168.20.0/24`
- `192.168.4.0/24`

通常没有必要使用 `-auto`，直接扫描更直接。

## 7. 公网信息收集

如果目标文件里混有 IP、网段、域名和 URL，推荐：

```bash
./fscanx -hf target.txt -pd -nmap -np
```

说明：

- `-pd`
  将 URL 或域名解析出的 IP 所在 C 段加入端口扫描
- 如果只做 Web 探测，不想扩 C 段，则不要加 `-pd`

## 8. 批量 URL 扫描

```bash
./fscanx -hf url.txt -tn 200
```

扫描单个 URL：

```bash
./fscanx -u https://example.com
```

## 9. 代理与远程扫描

使用 `socks5`：

```bash
./fscanx \
  -socks5 socks5://127.0.0.1:1080 \
  -h 192.168.1.1/24
```

更常见的代理场景写法：

```bash
./fscanx \
  -socks5 socks5://127.0.0.1:1080 \
  -h 192.168.1.1/24 \
  -p 22,80,443,445,3389 \
  -nmap \
  -np
```

说明：

- `-socks5` 支持端口扫描和 URL 扫描
- `-proxy` 更偏 HTTP 目标，不适合普通 TCP 端口扫描

## 10. 与 masscan 联动

这是 `fscanx` 非常适合的用法之一。

### 10.1 第一阶段：masscan 快速打重点端口

```bash
masscan 192.168.0.0/16 -p 22,80,443 --rate 50000 -oL phase1.lst
```

### 10.2 提取 `IP:PORT`

```bash
awk '/^open/ {print $4 ":" $3}' phase1.lst | sort -u > alive_ip_port.txt
```

### 10.3 第二阶段：fscanx 补识别

```bash
cat alive_ip_port.txt | ./fscanx \
  -std \
  -nmap \
  -np \
  -t 1000 \
  -tn 200 \
  -time 2 \
  -nocolor | tee phase2.log
```

## 11. `1000000` IP 的推荐打法

### 11.1 不推荐的做法

对于 `1000000` 个 IP，不建议一开始就直接：

```bash
-p 1-65535
```

原因很简单：

- 任务规模过大
- 耗时和资源消耗都会非常重
- 更容易出现看起来“卡住”的体验

### 11.2 推荐的两阶段方式

第一阶段，先用 `fscanx` 快速筛出有价值的 `IP:PORT`：

```bash
./fscanx \
  -hf targets-1m.txt \
  -p 22,80,443,445,3389 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor | tee phase1.log
```

提取第一阶段结果：

```bash
awk '/Port open/{print $4}' phase1.log | sort -u > alive_ip_port.txt
```

第二阶段，再补协议和资产识别：

```bash
cat alive_ip_port.txt | ./fscanx \
  -std \
  -nmap \
  -np \
  -t 1000 \
  -tn 200 \
  -time 2 \
  -nocolor | tee phase2.log
```

### 11.3 为什么不默认推荐 `-auto`

如果这 `1000000` IP 是碎片化的多段 CIDR 组合，而不是一个连续的大 `/8` 或 `/16`，`-auto` 通常不是默认最优解。

原因：

- `-auto` 更偏连续大段
- 其默认预筛特征较启发式
- 活主机如果不符合默认位置和端口特征，可能会漏段

因此，对碎片化 `1000000` IP，更推荐“重点端口先筛，再补识别”的两阶段方案。

## 12. 推荐命令总结

### 12.1 多网段重点端口快速扫描

```bash
./fscanx \
  -hf targets.txt \
  -p 22,80,443,445,3389 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor \
  -o result.txt
```

### 12.2 多网段全端口扫描

```bash
./fscanx \
  -h 192.168.1.0/24,192.168.20.0/24,192.168.4.0/24 \
  -p 1-65535 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor \
  -o result.txt
```

### 12.3 大网段 `-auto` 速度优先版

```bash
./fscanx \
  -h 192 \
  -auto \
  -am tcp \
  -ap 80 \
  -ai 1,2,253,254 \
  -atime 1 \
  -p 22,80,443,445,3389 \
  -np \
  -t 2000 \
  -nocolor \
  -o result.txt
```

### 12.4 `1000000` IP 两阶段版

```bash
./fscanx \
  -hf targets-1m.txt \
  -p 22,80,443,445,3389 \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor | tee phase1.log
```

```bash
awk '/Port open/{print $4}' phase1.log | sort -u > alive_ip_port.txt
```

```bash
cat alive_ip_port.txt | ./fscanx \
  -std \
  -nmap \
  -np \
  -t 1000 \
  -tn 200 \
  -time 2 \
  -nocolor | tee phase2.log
```
