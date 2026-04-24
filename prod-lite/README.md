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
