# nmap-fscanx

一个面向内部环境分发的 `prod-lite` 发布包，用来运行 `fscanx` 两阶段扫描流程。

它不是通用资产平台，也不是“纯活 IP 基线发现工具”。它的定位是：

- 快速筛出重点端口主机
- 对命中主机做第二阶段全端口扫描
- 固定输出审计文件和 `report.json`

## 支持环境

- Linux `x86_64`
- `Debian/Ubuntu`
- `RHEL/Rocky/CentOS`
- `openEuler/Anolis`

依赖：

- `bash`
- `jq`
- `tmux`
- 用户自己提供的 `fscanx` 二进制

## 安装

用户级安装：

```bash
tar -xzf nmap-fscanx-0.1.0.tar.gz
cd nmap-fscanx-0.1.0
make install
```

或者：

```bash
bash install.sh
```

发布包现在默认自带 `fscanx-bundle/`，安装脚本会优先按当前 Linux 架构选择包内置的 `fscanx`。

如果你另外放了一个外置 `fscanx-bundle/` 在发布包同级目录，安装脚本只会把它当成后备来源。

如果你想显式指定扫描器，也可以：

```bash
make install SCANNER=/path/to/fscanx
```

或者：

```bash
bash install.sh --scanner /path/to/fscanx
```

系统级安装：

```bash
sudo bash install.sh --system --scanner /path/to/fscanx
```

如果机器能访问内网源或系统源，也可以尝试自动安装依赖：

```bash
bash install.sh --install-deps --scanner /path/to/fscanx
```

更多安装细节见 [docs/INSTALL.md](docs/INSTALL.md)。

## 常用配置

默认配置文件在安装目录中的 `conf/default.env`，运行配置文件默认在：

- 用户级安装：`$HOME/.config/nmap-fscanx/config.env`
- 系统级安装：`/etc/nmap-fscanx/config.env`

推荐做法：

- 默认值看 `conf/default.env`
- 运维定制写到 `config.env`
- 修改后执行 `nmap-fscanx print-config` 确认最终生效值

最常用的配置项如下：

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `NMAP_FSCANX_PHASE1_PORTS` | `22,80,443,445,3389` | 第一阶段重点端口。目标 IP 命中任意一个端口后，才会进入第二阶段。 |
| `NMAP_FSCANX_PHASE2_PORTS` | `1-65535` | 第二阶段扫描范围，默认全端口。 |
| `NMAP_FSCANX_THREADS` | `4000` | fscanx 并发数。数值越大速度越快，但也会增加本机和目标网络压力。 |
| `NMAP_FSCANX_TIMEOUT` | `1` | 单次端口探测超时时间，单位为秒。网络质量较差时可适当调大。 |
| `NMAP_FSCANX_TMUX_PREFIX` | `nmap-fscanx` | `start` 命令创建后台 tmux 会话时使用的前缀。 |
| `NMAP_FSCANX_SCANNER` | 安装时自动探测 | fscanx 可执行文件路径。自动探测失败时可手动指定。 |
| `NMAP_FSCANX_SCAN_BASE` | 未设置 | 扫描输出根目录。未设置时使用默认输出目录。 |

一个运维常见示例：

```env
# 第一阶段扫描端口。
# 目标 IP 只要命中这些端口中的任意一个，就会进入第二阶段全端口扫描。
NMAP_FSCANX_PHASE1_PORTS=22,80,443,445,3389

# 第二阶段扫描端口范围。
# 默认对第一阶段命中的主机执行全端口扫描。
NMAP_FSCANX_PHASE2_PORTS=1-65535

# fscanx 并发数。
# 数值越大扫描越快，但也会增加本机和目标网络压力。
NMAP_FSCANX_THREADS=4000

# 单次端口探测超时时间，单位为秒。
# 内网延迟较低时可保持默认值，网络较慢时可适当调大。
NMAP_FSCANX_TIMEOUT=1

# tmux 会话名前缀。
# 使用 start 命令后台启动扫描时，会用这个前缀拼接会话名。
NMAP_FSCANX_TMUX_PREFIX=nmap-fscanx
```

## 首次检查

```bash
make check
```

或者：

```bash
nmap-fscanx check
```

至少要看到下面几项为 `ok`：

- `JQ_STATUS=ok`
- `TMUX_STATUS=ok`
- `SCANNER_STATUS=ok`

## 最常用的运行方式

前台执行：

```bash
nmap-fscanx run --targets '192.168.1.0/24,192.168.20.0/24'
```

后台用 `tmux` 启动：

```bash
nmap-fscanx start --targets '192.168.1.0/24,192.168.20.0/24'
```

进入后台会话：

```bash
nmap-fscanx attach --session nmap-fscanx-scan-20260424
```

更多示例见 [docs/QUICKSTART.md](docs/QUICKSTART.md) 和 [examples/](examples/)。

## 输出结果

重点文件：

- `phase1/alive_ips.txt`
- `phase2/open_ip_port.txt`
- `report.json`

详细说明见 [docs/OUTPUTS.md](docs/OUTPUTS.md)。

## 卸载

用户级安装默认：

```bash
bash ~/.local/nmap-fscanx/uninstall.sh
```

系统级安装默认：

```bash
sudo bash /opt/nmap-fscanx/uninstall.sh
```

## 常见问题

### 1. `SCANNER_STATUS=missing`

说明没有找到 `fscanx`。处理方式：

- 确认发布包内的 `fscanx-bundle/` 没被删掉
- 如果你依赖外置 bundle，确认发布包同级目录存在 `fscanx-bundle/`
- 重新安装时显式传 `--scanner /path/to/fscanx`
- 或修改运行配置中的 `NMAP_FSCANX_SCANNER`

如果不确定当前到底用了哪份配置，先执行：

```bash
nmap-fscanx print-config
```

### 2. `TMUX_STATUS=missing`

说明机器没有安装 `tmux`。处理方式：

- 手工安装 `tmux`
- 或重新执行 `bash install.sh --install-deps`

### 3. `JQ_STATUS=missing`

说明机器没有安装 `jq`。处理方式：

- 手工安装 `jq`
- 或重新执行 `bash install.sh --install-deps`

### 4. 为什么结果比 `nmap -sn` 少

这是预期风险之一。第一阶段只关注固定重点端口，没命中这些端口的在线主机不会进入第二阶段。

### 5. 为什么我开了 `-json`，看到的还是 `result.txt`

这是当前接入的上游 `fscanx` 语义：

- `-json` 只改变结果内容格式
- 默认输出文件仍然是当前工作目录下的 `result.txt`
- `-json` 不会自动写到 `stdout`
- `-json` 也不会自动生成 `result.json`

`nmap-fscanx` 的做法是为每个阶段切换到自己的工作目录执行扫描，再接管这个目录里的 `result.txt`。
