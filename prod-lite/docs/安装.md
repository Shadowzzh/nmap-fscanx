# 安装说明

## 1. 适用范围

这份发布包面向：

- Linux `x86_64`
- `Debian/Ubuntu`
- `RHEL/Rocky/CentOS`
- `openEuler/Anolis`

运行前需要：

- `bash`
- `jq`
- `tmux`
- 用户自己提供的 `fscanx`

## 2. 用户级安装

```bash
tar -xzf nmap-fscanx-0.1.0.tar.gz
cd nmap-fscanx-0.1.0
make install
```

或者：

```bash
bash install.sh
```

发布包默认已经自带：

```text
./fscanx-bundle
```

安装脚本会优先按当前 Linux 架构选择包内 `fscanx`。

如果包内 bundle 被删掉，安装脚本才会继续尝试：

- 系统里已有的 `fscanx`
- 发布包同级目录中的外置 `fscanx-bundle/`

如果你不想走自动选择，也可以显式指定：

```bash
make install SCANNER=/path/to/fscanx
```

或者：

```bash
bash install.sh --scanner /path/to/fscanx
```

默认安装到：

- 程序目录：`$HOME/.local/nmap-fscanx`
- 命令入口：`$HOME/.local/bin/nmap-fscanx`
- 运行配置：`$HOME/.config/nmap-fscanx/config.env`

如果 `~/.local/bin` 不在 `PATH` 中，请把它加入 shell 配置。

## 3. 系统级安装

```bash
make install-system SCANNER=/path/to/fscanx
```

或者：

```bash
sudo bash install.sh --system --scanner /path/to/fscanx
```

默认安装到：

- 程序目录：`/opt/nmap-fscanx`
- 命令入口：`/usr/local/bin/nmap-fscanx`
- 运行配置：`/etc/nmap-fscanx/config.env`

## 4. 常用配置

默认值在安装目录中的 `conf/default.env`，运行时覆盖配置在 `config.env`。

生效顺序建议按这个理解：

1. 安装目录中的默认配置 `conf/default.env`
2. 运行配置 `config.env`
3. 命令行显式参数

如果你不确定当前实际生效的是哪一组值，先执行：

```bash
nmap-fscanx print-config
```

最常用的配置项如下：

| 配置项 | 默认值 | 用途 | 运维调参建议 |
| --- | --- | --- | --- |
| `NMAP_FSCANX_PHASE1_PORTS` | `22,80,443,445,3389` | 第一阶段重点端口。命中后才会进入第二阶段。 | 想缩短首轮时间可减少端口；想提高覆盖率可增加端口。 |
| `NMAP_FSCANX_PHASE2_PORTS` | `1-65535` | 第二阶段端口范围。 | 默认全端口；如只做重点复核可缩小范围。 |
| `NMAP_FSCANX_THREADS` | `4000` | fscanx 并发数。 | 机器性能一般或网络敏感时可适当调低。 |
| `NMAP_FSCANX_TIMEOUT` | `1` | 单次端口探测超时，单位为秒。 | 弱网、跨网段或高延迟环境可适当调大。 |
| `NMAP_FSCANX_TMUX_PREFIX` | `nmap-fscanx` | 后台 tmux 会话名前缀。 | 多套任务并行时可改成更容易区分的前缀。 |
| `NMAP_FSCANX_SCANNER` | 安装时自动探测 | fscanx 可执行文件路径。 | 自动探测失败时手动指定绝对路径。 |
| `NMAP_FSCANX_SCAN_BASE` | 未设置 | 扫描输出根目录。 | 运维通常会改到专门的数据盘或审计目录。 |

示例：

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

# fscanx 可执行文件路径。
# 如果安装时没有自动识别到扫描器，可以在这里手动指定。
# NMAP_FSCANX_SCANNER=/path/to/fscanx

# 扫描结果根目录。
# 不设置时使用默认输出目录；设置后所有扫描结果会落到这里。
# NMAP_FSCANX_SCAN_BASE=/path/to/scans
```

## 5. 自动安装依赖

如果目标机器可以访问系统源或内网镜像源，可以尝试：

```bash
bash install.sh --install-deps --scanner /path/to/fscanx
```

安装脚本会尽力识别：

- `apt-get`
- `dnf`
- `yum`

默认只检查依赖，不会自动安装；只有显式传 `--install-deps` 才会尝试安装。

## 6. 覆盖安装

如果目标目录已存在，需要显式传 `--force`：

```bash
bash install.sh --force --scanner /path/to/fscanx
```

## 7. 安装后检查

```bash
make check
```

或者：

```bash
nmap-fscanx check
```

重点看：

- `JQ_STATUS=ok`
- `TMUX_STATUS=ok`
- `SCANNER_STATUS=ok`

如果 `SCANNER_STATUS=missing`，优先检查：

- 发布包目录里是不是还存在 `fscanx-bundle/`
- 如果你依赖外置 bundle，发布包同级目录是不是存在 `fscanx-bundle/`
- `--scanner` 是否传了正确路径
- 运行配置里的 `NMAP_FSCANX_SCANNER`

## 8. 相关文档

- [../README.md](../README.md)
- [QUICKSTART.md](QUICKSTART.md)
- [OUTPUTS.md](OUTPUTS.md)
