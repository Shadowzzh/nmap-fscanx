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

## 4. 自动安装依赖

如果目标机器可以访问系统源或内网镜像源，可以尝试：

```bash
bash install.sh --install-deps --scanner /path/to/fscanx
```

安装脚本会尽力识别：

- `apt-get`
- `dnf`
- `yum`

默认只检查依赖，不会自动安装；只有显式传 `--install-deps` 才会尝试安装。

## 5. 覆盖安装

如果目标目录已存在，需要显式传 `--force`：

```bash
bash install.sh --force --scanner /path/to/fscanx
```

## 6. 安装后检查

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

## 7. 相关文档

- [../README.md](../README.md)
- [QUICKSTART.md](QUICKSTART.md)
- [OUTPUTS.md](OUTPUTS.md)
